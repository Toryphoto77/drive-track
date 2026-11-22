// 会话层：把传感器数据打成 JSON 行，实时经 BLE 推送，同时按需落盘；
// 记录结束后给出本机汇总（里程、极速、最大侧向/纵向 G）。
// 真正的走线对比与完整分析在 App 侧做，这里只保证原始数据足够密、足够准。
#include "dt_session.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "dt_ble.h"
#include "dt_config.h"
#include "dt_ota.h"
#include "dt_power.h"
#include "dt_store.h"
#include "dt_types.h"

static const char *TAG = "dt_session";

#define LINE_MAX 320
#define G 9.80665f

static bool s_active;
static uint32_t s_session_id;
static int64_t s_start_us;
static dt_session_summary_t s_summary;

static bool s_have_last_fix;
static double s_last_lat;
static double s_last_lon;
static int64_t s_last_fix_us;
static float s_speed_filtered;
static float s_prev_speed_kph;
static int64_t s_last_hb_us;

static void emit(const char *line)
{
    // 连得上就直接发；发不出去才落盘，重连后按游标补传。
    // 这样缓存里只留断线期间的数据，SPIFFS 不会被常态录制写满。
    // OTA 期间暂停 BLE 遥测，把射频时间片让给 WiFi，避免上传被拖慢。
    bool sent = false;
    if (!dt_ota_active()) {
        sent = dt_ble_send_line(line);
    }
    if (s_active && !sent) {
        dt_store_write_line(line);
    }
}

static double haversine_m(double lat1, double lon1, double lat2, double lon2)
{
    const double rad = 3.14159265358979323846 / 180.0;
    double dlat = (lat2 - lat1) * rad;
    double dlon = (lon2 - lon1) * rad;
    double a = sin(dlat / 2) * sin(dlat / 2) +
               cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2) * sin(dlon / 2);
    return 6371000.0 * 2.0 * atan2(sqrt(a), sqrt(1 - a));
}

void dt_session_init(void)
{
    s_start_us = esp_timer_get_time();
    dt_store_set_recording(false);
    dt_ble_set_cmd_callback(dt_session_handle_command);
}

void dt_session_on_gps(const dt_gps_sample_t *sample)
{
    if (sample == NULL) {
        return;
    }

    char line[LINE_MAX];
    snprintf(line, sizeof(line),
             "{\"t\":\"gps\",\"fix\":%d,\"sats\":%u,\"lat\":%.7f,\"lon\":%.7f,"
             "\"alt\":%.1f,\"spd\":%.2f,\"cog\":%.1f,\"hdop\":%.1f}",
             sample->fix ? 1 : 0, (unsigned)sample->sats, sample->lat,
             sample->lon, sample->alt_m, sample->speed_kph, sample->course_deg,
             sample->hdop);
    emit(line);

    if (!sample->fix) {
        return;
    }

    s_speed_filtered = 0.7f * s_speed_filtered + 0.3f * sample->speed_kph;
    if (s_speed_filtered > s_summary.vmax_kph) {
        s_summary.vmax_kph = s_speed_filtered;
    }

    if (s_active) {
        int64_t now = esp_timer_get_time();
        if (s_have_last_fix) {
            s_summary.distance_m +=
                (float)haversine_m(s_last_lat, s_last_lon, sample->lat,
                                   sample->lon);
            int64_t dt_us = now - s_last_fix_us;
            if (dt_us > 20000 && dt_us < 2000000) {
                // 纵向加速度用速度差分；GPS 速度噪声大，取平滑后的值。
                float dv = (sample->speed_kph - s_prev_speed_kph) / 3.6f;
                float acc = dv / ((float)dt_us / 1e6f);
                if (fabsf(acc) < 2.0f * G) {
                    if (fabsf(acc) > fabsf(s_summary.max_long_g)) {
                        s_summary.max_long_g = acc;
                    }
                }
                s_prev_speed_kph = sample->speed_kph;
            }
        } else {
            s_have_last_fix = true;
        }
        s_last_lat = sample->lat;
        s_last_lon = sample->lon;
        s_last_fix_us = now;
        s_summary.samples++;
    }
}

void dt_session_on_imu(const dt_imu_sample_t *sample)
{
    if (sample == NULL) {
        return;
    }

    // 侧向加速度 g = 速度(m/s) × 横摆角速度(rad/s) / 9.80665
    float lat_g =
        (s_speed_filtered / 3.6f) * (sample->gz * 0.0174533f) / G;
    if (s_active && fabsf(lat_g) < 3.0f &&
        fabsf(lat_g) > fabsf(s_summary.max_lat_g)) {
        s_summary.max_lat_g = lat_g;
    }

    char line[LINE_MAX];
    snprintf(line, sizeof(line),
             "{\"t\":\"imu\",\"ax\":%.2f,\"ay\":%.2f,\"az\":%.2f,"
             "\"gx\":%.1f,\"gy\":%.1f,\"gz\":%.1f,\"roll\":%.1f,"
             "\"pitch\":%.1f,\"latg\":%.2f}",
             sample->ax, sample->ay, sample->az, sample->gx, sample->gy,
             sample->gz, sample->roll_deg, sample->pitch_deg, lat_g);
    emit(line);
}

void dt_session_on_obd(const dt_obd_sample_t *sample)
{
    if (sample == NULL) {
        return;
    }
    char line[LINE_MAX];
    snprintf(line, sizeof(line),
             "{\"t\":\"obd\",\"rpm\":%.0f,\"spd\":%.0f,\"thr\":%.1f,"
             "\"cool\":%.0f}",
             sample->has_rpm ? sample->rpm : -1.0f,
             sample->has_speed ? sample->speed_kph : -1.0f,
             sample->has_throttle ? sample->throttle_pct : -1.0f,
             sample->has_coolant ? sample->coolant_c : -999.0f);
    emit(line);
}

bool dt_session_active(void)
{
    return s_active;
}

void dt_session_start(void)
{
    if (s_active) {
        return;
    }
    memset(&s_summary, 0, sizeof(s_summary));
    s_have_last_fix = false;
    s_speed_filtered = 0;
    s_prev_speed_kph = 0;
    s_start_us = esp_timer_get_time();
    s_session_id++;
    s_active = true;

    dt_store_set_recording(true);

    char line[LINE_MAX];
    snprintf(line, sizeof(line),
             "{\"t\":\"sess\",\"ev\":\"start\",\"id\":%u,\"ts\":%lld}",
             (unsigned)s_session_id, (long long)(s_start_us / 1000));
    emit(line);
    ESP_LOGI(TAG, "记录开始 id=%u", (unsigned)s_session_id);
}

void dt_session_stop(void)
{
    if (!s_active) {
        return;
    }
    int64_t now = esp_timer_get_time();
    s_summary.duration_s = (uint32_t)((now - s_start_us) / 1000000);
    s_summary.vavg_kph =
        s_summary.duration_s > 0
            ? (s_summary.distance_m / (float)s_summary.duration_s) * 3.6f
            : 0;

    char line[LINE_MAX];
    snprintf(line, sizeof(line),
             "{\"t\":\"sum\",\"id\":%u,\"dur\":%u,\"dist\":%.1f,\"vmax\":%.1f,"
             "\"vavg\":%.1f,\"latg\":%.2f,\"longg\":%.2f,\"n\":%u}",
             (unsigned)s_session_id, (unsigned)s_summary.duration_s,
             s_summary.distance_m, s_summary.vmax_kph, s_summary.vavg_kph,
             s_summary.max_lat_g, s_summary.max_long_g,
             (unsigned)s_summary.samples);
    // 先发再停：手机此刻没连上时，汇总仍会落进本地缓存。
    emit(line);

    s_active = false;
    dt_store_set_recording(false);
    ESP_LOGI(TAG, "记录结束：%.0f m，%u s", s_summary.distance_m,
             (unsigned)s_summary.duration_s);
}

static void ack(const char *cmd)
{
    char line[96];
    snprintf(line, sizeof(line), "{\"t\":\"ack\",\"cmd\":\"%s\"}", cmd);
    dt_ble_send_line(line);
}

static void send_status(void)
{
    char line[256];
    snprintf(line, sizeof(line),
             "{\"t\":\"dev\",\"model\":\"%s\",\"board\":\"%s\",\"fw\":\"%s\","
             "\"build\":%d,\"rec\":%d,\"up\":%lld,\"heap\":%u,\"batt\":%d,"
             "\"ota\":%d,\"cache\":%u}",
             DT_DEVICE_MODEL, DT_BOARD_NAME, DT_FW_VERSION, DT_FW_BUILD,
             s_active ? 1 : 0, (long long)(esp_timer_get_time() / 1000000),
             (unsigned)esp_get_free_heap_size(), dt_power_batt_mv(),
             dt_ota_active() ? 1 : 0, (unsigned)dt_store_backlog());
    dt_ble_send_line(line);
}

// 热点状态：App 收到 on=1 后再切到 WiFi 上传固件。
static void send_ota_status(void)
{
    char line[256];
    snprintf(line, sizeof(line),
             "{\"t\":\"ota\",\"on\":%d,\"ssid\":\"%s\",\"pass\":\"%s\","
             "\"url\":\"http://192.168.4.1/api/info\"}",
             dt_ota_active() ? 1 : 0, dt_ota_ssid(), DT_AP_PASSWORD);
    dt_ble_send_line(line);
}

// 开热点会阻塞上百毫秒，别占着 BLE 主机任务；先回 ack，再在独立任务里开。
static void ota_start_task(void *arg)
{
    (void)arg;
    dt_ota_start();
    send_ota_status();
    vTaskDelete(NULL);
}

void dt_session_handle_command(const char *json, size_t len)
{
    if (json == NULL || len == 0) {
        return;
    }
    char buf[192];
    if (len >= sizeof(buf)) {
        len = sizeof(buf) - 1;
    }
    memcpy(buf, json, len);
    buf[len] = '\0';

    cJSON *root = cJSON_Parse(buf);
    if (root == NULL) {
        return;
    }
    const cJSON *cmd = cJSON_GetObjectItemCaseSensitive(root, "cmd");
    if (!cJSON_IsString(cmd)) {
        cJSON_Delete(root);
        return;
    }

    if (strcmp(cmd->valuestring, "start") == 0) {
        dt_session_start();
        ack("start");
    } else if (strcmp(cmd->valuestring, "stop") == 0) {
        dt_session_stop();
        ack("stop");
    } else if (strcmp(cmd->valuestring, "status") == 0) {
        send_status();
    } else if (strcmp(cmd->valuestring, "ota-start") == 0) {
        ack("ota-starting");
        xTaskCreate(ota_start_task, "ota_start", 4096, NULL, 4, NULL);
    } else if (strcmp(cmd->valuestring, "ota-stop") == 0) {
        dt_ota_stop();
        send_ota_status();
    } else if (strcmp(cmd->valuestring, "sync") == 0) {
        size_t moved = dt_store_sync_step(1500);
        if (moved == 0 && dt_store_backlog() == 0) {
            ack("sync-done");
        }
    } else if (strcmp(cmd->valuestring, "clear-cache") == 0) {
        dt_store_clear();
        ack("clear-cache");
    } else {
        ack("unknown");
    }
    cJSON_Delete(root);
}

void dt_session_tick(void)
{
    int64_t now = esp_timer_get_time();

    // 连着手机时自动续传积压，1 KB/s 足够追上 10 Hz 采样。
    if (dt_ble_connected() && dt_store_backlog() > 0) {
        dt_store_sync_step(1024);
    }

    if (now - s_last_hb_us >= 10000000) {
        s_last_hb_us = now;
        if (dt_ble_connected()) {
            send_status();
        }
    }
}
