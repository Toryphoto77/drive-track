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
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"

#include "dt_config.h"
#include "dt_power.h"

static const char *TAG = "dt_ota";

#define OTA_CHUNK 4096

static bool s_updating;
static bool s_active;
static bool s_netif_ready;
static bool s_wifi_ready;
static httpd_handle_t s_server;
static int64_t s_last_activity_us;
static char s_ssid[33];

// 没有 HTTP 请求超过这个时间就自动关热点，把射频还给 BLE。
#define OTA_IDLE_STOP_US (120LL * 1000000LL)

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
    s_last_activity_us = esp_timer_get_time();
    char body[288];
    int n = snprintf(body, sizeof(body),
                     "{\"model\":\"%s\",\"board\":\"%s\",\"fw\":\"%s\","
                     "\"build\":%d,\"battMv\":%d,\"freeHeap\":%u,"
                     "\"uptimeMs\":%lld}",
                     DT_DEVICE_MODEL, DT_BOARD_NAME, DT_FW_VERSION,
                     DT_FW_BUILD, dt_power_batt_mv(),
                     (unsigned)esp_get_free_heap_size(),
                     (long long)(esp_timer_get_time() / 1000));
    if (n < 0 || n >= (int)sizeof(body)) {
        return httpd_resp_send_500(req);
    }
    httpd_resp_set_type(req, "application/json");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return httpd_resp_send(req, body, n);
}

static void ota_reboot_task(void *arg)
{
    // 留出时间让 HTTP 响应真正发回手机。
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

static esp_err_t ota_post(httpd_req_t *req)
{
    s_last_activity_us = esp_timer_get_time();
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

const char *dt_ota_ssid(void)
{
    if (s_ssid[0] == '\0') {
        uint8_t mac[6] = {0};
        esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
        snprintf(s_ssid, sizeof(s_ssid), "%s-%02X%02X", DT_AP_SSID_PREFIX,
                 mac[4], mac[5]);
    }
    return s_ssid;
}

static bool dt_wifi_start(void)
{
    // netif 和 WiFi 驱动整个生命周期只初始化一次；
    // 之后只做 start/stop，避免重复建 netif 导致 DHCP 异常。
    if (!s_netif_ready) {
        ESP_ERROR_CHECK(esp_netif_init());
        esp_err_t err = esp_event_loop_create_default();
        if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
            ESP_LOGE(TAG, "事件循环创建失败 %s", esp_err_to_name(err));
            return false;
        }
        esp_netif_create_default_wifi_ap();
        s_netif_ready = true;
    }
    if (!s_wifi_ready) {
        wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
        ESP_ERROR_CHECK(esp_wifi_init(&init));
        ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
        s_wifi_ready = true;
    }

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));

    wifi_config_t cfg = {0};
    const char *ssid = dt_ota_ssid();
    memcpy(cfg.ap.ssid, ssid, strlen(ssid));
    cfg.ap.ssid_len = (uint8_t)strlen(ssid);
    memcpy(cfg.ap.password, DT_AP_PASSWORD, strlen(DT_AP_PASSWORD));
    cfg.ap.channel = DT_AP_CHANNEL;
    cfg.ap.max_connection = DT_AP_MAX_CONN;
    cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
    cfg.ap.pmf_cfg.required = false;

    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &cfg));
    esp_err_t err = esp_wifi_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "热点启动失败 %s", esp_err_to_name(err));
        return false;
    }
    return true;
}

static void ota_idle_task(void *arg)
{
    (void)arg;
    while (s_active) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        if (!s_active) {
            break;
        }
        if (s_updating) {
            continue;
        }
        if (esp_timer_get_time() - s_last_activity_us > OTA_IDLE_STOP_US) {
            ESP_LOGI(TAG, "OTA 空闲超时，关闭热点");
            dt_ota_stop();
            break;
        }
    }
    vTaskDelete(NULL);
}

void dt_ota_start(void)
{
    if (s_active) {
        s_last_activity_us = esp_timer_get_time();
        return;
    }
    if (!dt_wifi_start()) {
        return;
    }

    httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
    cfg.stack_size = 8192;
    cfg.max_uri_handlers = 6;
    cfg.lru_purge_enable = true;
    cfg.recv_wait_timeout = 30;
    cfg.send_wait_timeout = 30;

    esp_err_t err = httpd_start(&s_server, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "HTTP 服务启动失败 %s", esp_err_to_name(err));
        esp_wifi_stop();
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
    httpd_register_uri_handler(s_server, &info_uri);
    httpd_register_uri_handler(s_server, &ota_uri);

    s_active = true;
    s_last_activity_us = esp_timer_get_time();
    xTaskCreate(ota_idle_task, "ota_idle", 2048, NULL, 3, NULL);
    ESP_LOGI(TAG, "OTA 已按需开启：%s http://192.168.4.1/api/info", dt_ota_ssid());
}

void dt_ota_stop(void)
{
    if (!s_active) {
        return;
    }
    if (s_updating) {
        ESP_LOGW(TAG, "升级进行中，拒绝关闭热点");
        return;
    }
    s_active = false;
    if (s_server != NULL) {
        httpd_stop(s_server);
        s_server = NULL;
    }
    if (s_wifi_ready) {
        esp_wifi_stop();
    }
    ESP_LOGI(TAG, "OTA 热点已关闭，射频归还 BLE");
}

bool dt_ota_active(void)
{
    return s_active;
}
