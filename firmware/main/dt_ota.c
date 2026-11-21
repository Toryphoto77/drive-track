// WiFi 热点 + HTTP OTA。设备只做两件事：报身份、收固件。
// 固件写进当前未运行的 OTA 分区，校验摘要后才切换启动分区，
// 所以升级中途断电只会回到旧版本，不会变砖。
#include "dt_ota.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>

#include "esp_err.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_ota_ops.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"
#include "cJSON.h"

#include "dt_config.h"
#include "dt_gnss.h"
#include "dt_baro.h"
#include "dt_imu.h"
#include "dt_power.h"
#include "dt_sd.h"
#include "dt_session.h"
#include "dt_store.h"

static const char *TAG = "dt_ota";

#define OTA_CHUNK 4096

static bool s_updating;
static char s_ssid[33];

static void to_hex(const unsigned char *in, size_t len, char *out)
{
    static const char *digits = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        out[i * 2] = digits[in[i] >> 4];
        out[i * 2 + 1] = digits[in[i] & 0x0F];
    }
    out[len * 2] = '\0';
}

static bool hex_equal(const char *a, const char *b)
{
    if (a == NULL || b == NULL || strlen(a) != strlen(b)) {
        return false;
    }
    for (size_t i = 0; a[i] != '\0'; i++) {
        char ca = a[i];
        char cb = b[i];
        if (ca >= 'A' && ca <= 'F') ca = (char)(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'F') cb = (char)(cb - 'A' + 'a');
        if (ca != cb) return false;
    }
    return true;
}

static esp_err_t info_get(httpd_req_t *req)
{
    char body[288];
    int n = snprintf(body, sizeof(body),
                     "{\"model\":\"%s\",\"board\":\"%s\",\"fw\":\"%s\","
                     "\"build\":%d,\"battMv\":%d,\"battery\":%d,"
                     "\"freeHeap\":%u,\"uptimeMs\":%lld}",
                     DT_DEVICE_MODEL, DT_BOARD_NAME, DT_FW_VERSION,
                     DT_FW_BUILD, dt_power_batt_mv(),
                     dt_power_batt_percent(),
                     (unsigned)esp_get_free_heap_size(),
                     (long long)(esp_timer_get_time() / 1000));
    if (n < 0 || n >= (int)sizeof(body)) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, body, n);
}

// App 的硬件管理卡每 3 秒轮询一次，字段缺失时界面显示“—”。
static esp_err_t status_get(httpd_req_t *req)
{
    char body[768];
    dt_sd_refresh();
    // 实时读数：缺失时输出 null，App 显示“—”，不伪造 0。
    char imu_json[192];
    dt_imu_sample_t imu;
    if (dt_imu_read(&imu)) {
        snprintf(imu_json, sizeof(imu_json),
                 "{\"ax\":%.3f,\"ay\":%.3f,\"az\":%.3f,"
                 "\"gx\":%.2f,\"gy\":%.2f,\"gz\":%.2f,"
                 "\"roll\":%.2f,\"pitch\":%.2f,\"cal\":%d}",
                 imu.ax, imu.ay, imu.az, imu.gx, imu.gy, imu.gz,
                 imu.roll_deg, imu.pitch_deg, dt_imu_calibrated() ? 1 : 0);
    } else {
        snprintf(imu_json, sizeof(imu_json), "null");
    }
    char baro_json[160];
    dt_baro_sample_t baro;
    if (dt_baro_read(&baro)) {
        snprintf(baro_json, sizeof(baro_json),
                 "{\"temp\":%.2f,\"press\":%.1f,\"alt\":%.2f,"
                 "\"rel\":%.3f,\"cal\":%d}",
                 baro.temp_c, baro.press_pa, baro.alt_m, baro.rel_alt_m,
                 dt_baro_calibrated() ? 1 : 0);
    } else {
        snprintf(baro_json, sizeof(baro_json), "null");
    }
    const char *current_file = dt_store_current_file();
    char file_json[72];
    if (current_file != NULL) {
        snprintf(file_json, sizeof(file_json), "\"%s\"", current_file);
    } else {
        snprintf(file_json, sizeof(file_json), "null");
    }
    int n = snprintf(
        body, sizeof(body),
        "{\"model\":\"%s\",\"fw\":\"%s\",\"build\":%d,"
        "\"battery\":%d,\"battMv\":%d,\"recording\":%d,"
        "\"fix\":%d,\"sats\":%d,\"gnssHz\":%d,\"imu\":%d,\"baro\":%d,"
        "\"imuData\":%s,\"baroData\":%s,\"file\":%s,"
        "\"uptimeMs\":%lld,\"freeHeap\":%u,\"sd\":%d,\"sdState\":\"%s\","
        "\"sdTotalKb\":%llu,\"sdFreeKb\":%llu,"
        "\"caps\":[\"shutdown\",\"storage\",\"sensors\",\"gnss-rate\","
        "\"file-backhaul\"]}",
        DT_DEVICE_MODEL, DT_FW_VERSION, DT_FW_BUILD, dt_power_batt_percent(),
        dt_power_batt_mv(), dt_session_active() ? 1 : 0,
        dt_gnss_last_fix() ? 1 : 0, dt_gnss_last_sats(), dt_gnss_rate_hz(),
        dt_imu_ready() ? 1 : 0, dt_baro_ready() ? 1 : 0, imu_json, baro_json,
        file_json,
        (long long)(esp_timer_get_time() / 1000),
        (unsigned)esp_get_free_heap_size(), dt_sd_ready() ? 1 : 0,
        dt_sd_state_text(), (unsigned long long)dt_sd_total_kb(),
        (unsigned long long)dt_sd_free_kb());
    if (n < 0 || n >= (int)sizeof(body)) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, body, n);
}

static esp_err_t gnss_rate_post(httpd_req_t *req)
{
    char body[96];
    if (req->content_len == 0 || req->content_len >= sizeof(body)) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"bad json\"}");
    }
    size_t received = 0;
    while (received < req->content_len) {
        int got = httpd_req_recv(req, body + received,
                                 req->content_len - received);
        if (got <= 0) {
            httpd_resp_set_status(req, "400 Bad Request");
            httpd_resp_set_type(req, "application/json");
            return httpd_resp_sendstr(
                req, "{\"ok\":false,\"error\":\"incomplete json\"}");
        }
        received += (size_t)got;
    }
    body[received] = '\0';

    cJSON *root = cJSON_Parse(body);
    const cJSON *value =
        root == NULL ? NULL : cJSON_GetObjectItemCaseSensitive(root, "hz");
    bool valid = cJSON_IsNumber(value) &&
                 value->valuedouble == (double)value->valueint &&
                 dt_gnss_set_rate(value->valueint);
    int hz = dt_gnss_rate_hz();
    cJSON_Delete(root);

    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    if (!valid) {
        httpd_resp_set_status(req, "400 Bad Request");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"hz must be 10, 20 or 25\"}");
    }
    char response[48];
    int n = snprintf(response, sizeof(response),
                     "{\"ok\":true,\"hz\":%d}", hz);
    return httpd_resp_send(req, response, n);
}

// 圈速在 App 侧计算，设备端没有赛道信息，返回空列表让界面走“无圈速”分支。
static esp_err_t laps_get(httpd_req_t *req)
{
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_sendstr(req, "{\"laps\":[]}");
}

static void shutdown_task(void *arg)
{
    // 先把 HTTP 响应发回手机，再停会话、进入深度睡眠。
    vTaskDelay(pdMS_TO_TICKS(1000));
    dt_session_stop();
    ESP_LOGW(TAG, "收到 App 关机指令，进入深度睡眠");
    esp_deep_sleep_start();
}

static esp_err_t shutdown_post(httpd_req_t *req)
{
    static bool s_shutting_down;
    if (s_shutting_down) {
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(req, "{\"ok\":true}");
    }
    s_shutting_down = true;
    httpd_resp_set_type(req, "application/json");
    esp_err_t err = httpd_resp_sendstr(req, "{\"ok\":true}");
    xTaskCreate(shutdown_task, "dt_shutdown", 2048, NULL, 5, NULL);
    return err;
}

static void ota_reboot_task(void *arg)
{
    // 留出时间让 HTTP 响应真正发回手机。
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

static esp_err_t ota_post(httpd_req_t *req)
{
    if (s_updating) {
        httpd_resp_set_status(req, "409 Conflict");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"busy\"}");
    }

    char sha_header[80] = {0};
    if (httpd_req_get_hdr_value_str(req, "X-Firmware-Sha256", sha_header,
                                    sizeof(sha_header)) != ESP_OK) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"missing sha256\"}");
    }

    const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
    if (target == NULL) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"no ota partition\"}");
    }
    if (req->content_len == 0 || req->content_len > target->size) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"bad size\"}");
    }

    char *buf = malloc(OTA_CHUNK);
    if (buf == NULL) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"no memory\"}");
    }

    s_updating = true;
    esp_ota_handle_t handle = 0;
    esp_err_t err = esp_ota_begin(target, req->content_len, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_begin 失败 %s", esp_err_to_name(err));
        free(buf);
        s_updating = false;
        httpd_resp_set_status(req, "500 Internal Server Error");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"begin\"}");
    }

    mbedtls_sha256_context sha;
    mbedtls_sha256_init(&sha);
    mbedtls_sha256_starts(&sha, 0);

    size_t remaining = req->content_len;
    int idle = 0;
    err = ESP_OK;
    while (remaining > 0) {
        int want = remaining > OTA_CHUNK ? OTA_CHUNK : (int)remaining;
        int got = httpd_req_recv(req, buf, want);
        if (got == HTTPD_SOCK_ERR_TIMEOUT) {
            if (++idle > 5) {
                err = ESP_ERR_TIMEOUT;
                break;
            }
            continue;
        }
        if (got <= 0) {
            err = ESP_FAIL;
            break;
        }
        idle = 0;
        mbedtls_sha256_update(&sha, (const unsigned char *)buf, (size_t)got);
        err = esp_ota_write(handle, buf, (size_t)got);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "esp_ota_write 失败 %s", esp_err_to_name(err));
            break;
        }
        remaining -= (size_t)got;
    }

    unsigned char digest[32];
    char digest_hex[65];
    mbedtls_sha256_finish(&sha, digest);
    mbedtls_sha256_free(&sha);
    to_hex(digest, sizeof(digest), digest_hex);

    bool sha_ok = hex_equal(digest_hex, sha_header);
    if (err == ESP_OK && !sha_ok) {
        ESP_LOGE(TAG, "摘要不一致：收到 %s", digest_hex);
        err = ESP_ERR_INVALID_CRC;
    }

    if (err == ESP_OK) {
        err = esp_ota_end(handle);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "esp_ota_end 失败 %s", esp_err_to_name(err));
        }
    } else {
        esp_ota_abort(handle);
    }

    if (err == ESP_OK) {
        err = esp_ota_set_boot_partition(target);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "切换启动分区失败 %s", esp_err_to_name(err));
        }
    }

    free(buf);
    s_updating = false;
    httpd_resp_set_type(req, "application/json");

    if (err != ESP_OK) {
        httpd_resp_set_status(req, "400 Bad Request");
        if (err == ESP_ERR_INVALID_CRC) {
            return httpd_resp_sendstr(
                req, "{\"ok\":false,\"error\":\"sha256 mismatch\"}");
        }
        return httpd_resp_sendstr(req, "{\"ok\":false,\"error\":\"write\"}");
    }

    esp_err_t send_err = httpd_resp_sendstr(req, "{\"ok\":true}");
    ESP_LOGI(TAG, "固件已写入 %s，1.5 秒后重启", target->label);
    xTaskCreate(ota_reboot_task, "ota_reboot", 2048, NULL, 5, NULL);
    return send_err;
}

static void dt_wifi_start(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));

    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    snprintf(s_ssid, sizeof(s_ssid), "%s-%02X%02X", DT_AP_SSID_PREFIX, mac[4],
             mac[5]);

    wifi_config_t cfg = {0};
    memcpy(cfg.ap.ssid, s_ssid, strlen(s_ssid));
    cfg.ap.ssid_len = (uint8_t)strlen(s_ssid);
    memcpy(cfg.ap.password, DT_AP_PASSWORD, strlen(DT_AP_PASSWORD));
    cfg.ap.channel = DT_AP_CHANNEL;
    cfg.ap.max_connection = DT_AP_MAX_CONN;
    cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
    cfg.ap.pmf_cfg.required = false;

    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &cfg));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_LOGI(TAG, "热点已开：%s（密码 %s）", s_ssid, DT_AP_PASSWORD);
}

// 只允许下载本设备生成的会话文件，拒绝路径穿越与任意文件名。
static bool safe_session_name(const char *name)
{
    if (name == NULL || strncmp(name, "session_", 8) != 0) {
        return false;
    }
    if (strstr(name, "..") != NULL) {
        return false;
    }
    for (const char *p = name; *p != '\0'; ++p) {
        if (!isalnum((unsigned char)*p) && *p != '_' && *p != '.') {
            return false;
        }
    }
    return true;
}

// GET /api/files：列出 SD 上全部会话文件，供 App 回 pits 后整场回传。
static esp_err_t files_get(httpd_req_t *req)
{
    if (!dt_store_is_sd()) {
        httpd_resp_set_status(req, "409 Conflict");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"sd_not_ready\"}");
    }
    DIR *dir = opendir(DT_SD_MOUNT_POINT);
    if (dir == NULL) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"open_dir\"}");
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    httpd_resp_sendstr_chunk(req, "{\"ok\":true,\"files\":[");
    bool first = true;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "session_", 8) != 0) {
            continue;
        }
        char path[96];
        // 设备自己生成的文件名是 session_0001.ndjson；限制长度既防越界，
        // 也避免 FAT 长文件名把 JSON 缓冲撑爆（编译期 -Werror=format-truncation）。
        snprintf(path, sizeof(path), "%s/%.64s", DT_SD_MOUNT_POINT,
                 entry->d_name);
        struct stat st;
        if (stat(path, &st) != 0 || !S_ISREG(st.st_mode)) {
            continue;
        }
        char item[160];
        snprintf(item, sizeof(item), "%s{\"name\":\"%.64s\",\"size\":%ld}",
                 first ? "" : ",", entry->d_name, (long)st.st_size);
        first = false;
        if (httpd_resp_sendstr_chunk(req, item) != ESP_OK) {
            break;
        }
    }
    closedir(dir);
    httpd_resp_sendstr_chunk(req, "]}");
    httpd_resp_sendstr_chunk(req, NULL);
    return ESP_OK;
}

// GET /api/files/download?name=session_0001.ndjson：流式回传整场记录。
static esp_err_t file_download_get(httpd_req_t *req)
{
    char query[128];
    char name[64];
    if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK ||
        httpd_query_key_value(query, "name", name, sizeof(name)) != ESP_OK ||
        !safe_session_name(name)) {
        httpd_resp_set_status(req, "400 Bad Request");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"bad_name\"}");
    }
    char path[96];
    snprintf(path, sizeof(path), "%s/%s", DT_SD_MOUNT_POINT, name);
    FILE *fp = fopen(path, "r");
    if (fp == NULL) {
        httpd_resp_set_status(req, "404 Not Found");
        httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(
            req, "{\"ok\":false,\"error\":\"not_found\"}");
    }
    httpd_resp_set_type(req, "application/x-ndjson");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    char buf[2048];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        if (httpd_resp_send_chunk(req, buf, (ssize_t)n) != ESP_OK) {
            fclose(fp);
            return ESP_FAIL;
        }
    }
    fclose(fp);
    httpd_resp_send_chunk(req, NULL, 0);
    return ESP_OK;
}

void dt_ota_start(void)
{
    dt_wifi_start();

    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.stack_size = 8192;
    cfg.max_uri_handlers = 10;
    cfg.lru_purge_enable = true;
    cfg.recv_wait_timeout = 30;
    cfg.send_wait_timeout = 30;

    httpd_handle_t server = NULL;
    esp_err_t err = httpd_start(&server, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "HTTP 服务启动失败 %s", esp_err_to_name(err));
        return;
    }

    httpd_uri_t info_uri = {
        .uri = "/api/info",
        .method = HTTP_GET,
        .handler = info_get,
    };
    httpd_uri_t ota_uri = {
        .uri = "/api/ota",
        .method = HTTP_POST,
        .handler = ota_post,
    };
    httpd_uri_t status_uri = {
        .uri = "/api/status",
        .method = HTTP_GET,
        .handler = status_get,
    };
    httpd_uri_t laps_uri = {
        .uri = "/api/laps",
        .method = HTTP_GET,
        .handler = laps_get,
    };
    httpd_uri_t gnss_rate_uri = {
        .uri = "/api/gnss-rate",
        .method = HTTP_POST,
        .handler = gnss_rate_post,
    };
    httpd_uri_t shutdown_uri = {
        .uri = "/api/shutdown",
        .method = HTTP_POST,
        .handler = shutdown_post,
    };
    httpd_uri_t files_uri = {
        .uri = "/api/files",
        .method = HTTP_GET,
        .handler = files_get,
    };
    httpd_uri_t file_download_uri = {
        .uri = "/api/files/download",
        .method = HTTP_GET,
        .handler = file_download_get,
    };
    httpd_register_uri_handler(server, &info_uri);
    httpd_register_uri_handler(server, &ota_uri);
    httpd_register_uri_handler(server, &status_uri);
    httpd_register_uri_handler(server, &laps_uri);
    httpd_register_uri_handler(server, &gnss_rate_uri);
    httpd_register_uri_handler(server, &shutdown_uri);
    httpd_register_uri_handler(server, &files_uri);
    httpd_register_uri_handler(server, &file_download_uri);

    ESP_LOGI(TAG, "OTA 服务已就绪 http://192.168.4.1/api/info");
}
