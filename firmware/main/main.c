// DriveTrack 自研硬件主程序。
//
// 启动顺序：NVS -> 本地缓存 -> 会话层 -> WiFi/HTTP/OTA -> BLE -> 传感器。
// 任一外设没接好只打印告警，不影响其余功能，方便分模块联调。
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "dt_ble.h"
#include "dt_can.h"
#include "dt_config.h"
#include "dt_gnss.h"
#include "dt_imu.h"
#include "dt_ota.h"
#include "dt_power.h"
#include "dt_session.h"
#include "dt_store.h"

static const char *TAG = "dt_main";

// BLE 名称与热点名同源，都取 MAC 末两字节，多台设备不会重名。
static void build_device_name(char *out, size_t len)
{
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(out, len, "%s-%02X%02X", DT_AP_SSID_PREFIX, mac[4], mac[5]);
}

void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_LOGI(TAG, "%s fw=%s build=%d", DT_DEVICE_MODEL, DT_FW_VERSION,
             DT_FW_BUILD);

    if (!dt_store_init()) {
        ESP_LOGW(TAG, "本地缓存不可用，掉线数据不会补传");
    }
    dt_session_init();
    if (!dt_power_start()) {
        ESP_LOGW(TAG, "电源监控不可用，电量与指示灯失效");
    }
    dt_ota_start();

#if DT_ENABLE_BLE
    char name[24];
    build_device_name(name, sizeof(name));
    dt_ble_init(name);
#endif

#if DT_ENABLE_GNSS
    dt_gnss_start();
#endif
#if DT_ENABLE_IMU
    if (!dt_imu_start()) {
        ESP_LOGW(TAG, "IMU 未就绪，其余功能继续");
    }
#endif
#if DT_ENABLE_CAN
    if (!dt_can_start()) {
        ESP_LOGW(TAG, "CAN 未就绪，其余功能继续");
    }
#endif

    // 新固件启动后先跑 10 秒自检窗口；确认没崩溃再取消回滚标记，
    // 这期间若异常重启，bootloader 会自动退回旧分区。
    bool rollback_released = false;
    uint32_t uptime_s = 0;
    while (true) {
        dt_session_tick();
        vTaskDelay(pdMS_TO_TICKS(1000));
        uptime_s++;

#if defined(CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE)
        if (!rollback_released && uptime_s >= 10) {
            err = esp_ota_mark_app_valid_cancel_rollback();
            ESP_LOGI(TAG, "新固件自检通过，取消回滚 (%s)",
                     esp_err_to_name(err));
            rollback_released = true;
        }
#endif
    }
}
