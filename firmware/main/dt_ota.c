// WiFi 热点 + HTTP OTA。设备只做两件事：报身份、收固件。
// 固件写进当前未运行的 OTA 分区，校验摘要后才切换启动分区，
// 所以升级中途断电只会回到旧版本，不会变砖。
#include "dt_ota.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

#include "dt_config.h"
#include "dt_gnss.h"
#include "dt_power.h"
#include "dt_session.h"

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
    char body[288];
    int n = snprintf(body, sizeof(body),
                     "{\"model\":\"%s\",\"fw\":\"%s\",\"build\":%d,"
                     "\"battery\":%d,\"battMv\":%d,\"recording\":%d,"
                     "\"fix\":%d,\"sats\":%d,\"uptimeMs\":%lld,"
                     "\"freeHeap\":%u,\"caps\":[\"shutdown\"]}",
                     DT_DEVICE_MODEL, DT_FW_VERSION, DT_FW_BUILD,
                     dt_power_batt_percent(), dt_power_batt_mv(),
                     dt_session_active() ? 1 : 0, dt_gnss_last_fix() ? 1 : 0,
                     dt_gnss_last_sats(),
                     (long long)(esp_timer_get_time() / 1000),
                     (unsigned)esp_get_free_heap_size());
    if (n < 0 || n >= (int)sizeof(body)) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, body, n);
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

void dt_ota_start(void)
{
    dt_wifi_start();

    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.stack_size = 8192;
    cfg.max_uri_handlers = 8;
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
    httpd_uri_t shutdown_uri = {
        .uri = "/api/shutdown",
        .method = HTTP_POST,
        .handler = shutdown_post,
    };
    httpd_register_uri_handler(server, &info_uri);
    httpd_register_uri_handler(server, &ota_uri);
    httpd_register_uri_handler(server, &status_uri);
    httpd_register_uri_handler(server, &laps_uri);
    httpd_register_uri_handler(server, &shutdown_uri);

    ESP_LOGI(TAG, "OTA 服务已就绪 http://192.168.4.1/api/info");
}
