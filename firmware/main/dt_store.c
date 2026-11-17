// 本地缓存：记录期间把每一行 JSON 追加到 SPIFFS，断线后重连按游标续传。
// 游标存在 NVS，设备重启也不会从头重发。
#include "dt_store.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_spiffs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "nvs.h"
#include "nvs_flash.h"

#include "dt_ble.h"
#include "dt_config.h"

static const char *TAG = "dt_store";

#define CURSOR_KEY "cursor"
#define FLUSH_EVERY 10
#define CURSOR_SAVE_STEP 4096

static bool s_mounted;
static bool s_recording;
static FILE *s_fp;
static size_t s_size;
static size_t s_cursor;
static size_t s_cursor_saved;
static size_t s_partition_bytes;
static uint32_t s_writes;
static SemaphoreHandle_t s_lock;
static nvs_handle_t s_nvs = 0;

static void load_cursor(void)
{
    if (s_nvs == 0) {
        return;
    }
    uint32_t value = 0;
    if (nvs_get_u32(s_nvs, CURSOR_KEY, &value) == ESP_OK) {
        s_cursor = value;
        s_cursor_saved = value;
    }
}

static void save_cursor(bool force)
{
    if (s_nvs == 0) {
        return;
    }
    if (!force && s_cursor < s_cursor_saved + CURSOR_SAVE_STEP) {
        return;
    }
    nvs_set_u32(s_nvs, CURSOR_KEY, (uint32_t)s_cursor);
    nvs_commit(s_nvs);
    s_cursor_saved = s_cursor;
}

bool dt_store_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    if (s_lock == NULL) {
        return false;
    }

    if (nvs_open(DT_STORE_NVS_NAMESPACE, NVS_READWRITE, &s_nvs) != ESP_OK) {
        ESP_LOGW(TAG, "NVS 打开失败，续传游标不会持久化");
        s_nvs = 0;
    }

    esp_vfs_spiffs_conf_t conf = {
        .base_path = DT_STORE_MOUNT_POINT,
        .partition_label = "storage",
        .max_files = 4,
        .format_if_mount_failed = true,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SPIFFS 挂载失败 %s", esp_err_to_name(err));
        return false;
    }
    s_mounted = true;

    size_t used = 0;
    esp_spiffs_info("storage", &s_partition_bytes, &used);

    FILE *fp = fopen(DT_STORE_FILE, "r");
    if (fp != NULL) {
        fseek(fp, 0, SEEK_END);
        s_size = (size_t)ftell(fp);
        fclose(fp);
    }
    load_cursor();
    if (s_cursor > s_size) {
        s_cursor = s_size;
    }
    ESP_LOGI(TAG, "缓存就绪：%u/%u 字节已用，游标 %u", (unsigned)used,
             (unsigned)s_partition_bytes, (unsigned)s_cursor);
    return true;
}

void dt_store_set_recording(bool recording)
{
    if (!s_mounted) {
        return;
    }
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        return;
    }
    if (!recording && s_fp != NULL) {
        fflush(s_fp);
        fclose(s_fp);
        s_fp = NULL;
    }
    s_recording = recording;
    xSemaphoreGive(s_lock);
}

bool dt_store_write_line(const char *line)
{
    if (!s_mounted || !s_recording || line == NULL) {
        return false;
    }
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(100)) != pdTRUE) {
        return false;
    }

    bool ok = false;
    if (s_fp == NULL) {
        s_fp = fopen(DT_STORE_FILE, "a");
    }
    if (s_fp != NULL) {
        size_t len = strlen(line);
        if (s_size + len + 1 > s_partition_bytes) {
            ESP_LOGW(TAG, "缓存已满，停止落盘");
            s_recording = false;
            fclose(s_fp);
            s_fp = NULL;
        } else if (fprintf(s_fp, "%s\n", line) > 0) {
            s_size += len + 1;
            ok = true;
            if (++s_writes % FLUSH_EVERY == 0) {
                fflush(s_fp);
            }
        }
    }

    xSemaphoreGive(s_lock);
    return ok;
}

size_t dt_store_backlog(void)
{
    if (!s_mounted) {
        return 0;
    }
    return s_size > s_cursor ? s_size - s_cursor : 0;
}

size_t dt_store_sync_step(size_t max_bytes)
{
    if (!s_mounted || max_bytes == 0) {
        return 0;
    }
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        return 0;
    }

    if (s_fp != NULL) {
        fflush(s_fp);
    }

    size_t sent = 0;
    FILE *fp = fopen(DT_STORE_FILE, "r");
    if (fp != NULL) {
        fseek(fp, (long)s_cursor, SEEK_SET);
        char line[400];
        while (sent < max_bytes) {
            long pos = ftell(fp);
            if (fgets(line, sizeof(line), fp) == NULL) {
                break;
            }
            size_t len = strlen(line);
            // 断电可能留下半行，半行不推进游标，下次补齐后再发。
            if (len == 0 || line[len - 1] != '\n') {
                break;
            }
            line[len - 1] = '\0';
            if (!dt_ble_send_line(line)) {
                break;
            }
            sent += len;
            s_cursor = (size_t)pos + len;
            vTaskDelay(pdMS_TO_TICKS(4));
        }
        fclose(fp);
    }

    save_cursor(false);
    xSemaphoreGive(s_lock);
    return sent;
}

void dt_store_clear(void)
{
    if (!s_mounted) {
        return;
    }
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(500)) != pdTRUE) {
        return;
    }
    if (s_fp != NULL) {
        fclose(s_fp);
        s_fp = NULL;
    }
    remove(DT_STORE_FILE);
    s_size = 0;
    s_cursor = 0;
    save_cursor(true);
    xSemaphoreGive(s_lock);
    ESP_LOGI(TAG, "缓存已清空");
}
