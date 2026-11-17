// CAN / OBD-II：TWAI 接收，解析 ISO-TP 单帧的 Mode 01 应答。
// 需要外接 CAN 收发器；直接接 OBD 口时把 500k 波特率对准车辆。
//
// V4.6 板上没有 CAN 收发器，配置里 DT_ENABLE_CAN=0，本文件整体不参与编译，
// 只保留两个空实现，换板后把开关置 1 即可启用。
#include "dt_can.h"

#include "dt_config.h"

#if !DT_ENABLE_CAN

bool dt_can_start(void)
{
    return false;
}

void dt_can_request_pid(uint8_t pid)
{
    (void)pid;
}

#else

#include <string.h>

#include "driver/twai.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "dt_session.h"
#include "dt_types.h"

static const char *TAG = "dt_can";

static dt_obd_sample_t s_sample;
static int64_t s_last_emit_us;
static bool s_running;

static void emit_sample(void)
{
    int64_t now = esp_timer_get_time();
    if (now - s_last_emit_us < 100000) {
        return;
    }
    s_last_emit_us = now;
    dt_session_on_obd(&s_sample);
}

static void handle_frame(const twai_message_t *msg)
{
    if (msg->identifier < 0x7E8 || msg->identifier > 0x7EF) {
        return;
    }
    if (msg->data_length_code < 4) {
        return;
    }
    if ((msg->data[0] >> 4) != 0x0) {
        return;  // 多帧应答本版不拼包
    }
    if (msg->data[1] != 0x41) {
        return;  // Mode 01 应答
    }

    uint8_t pid = msg->data[2];
    uint8_t a = msg->data[3];
    uint8_t b = msg->data_length_code > 4 ? msg->data[4] : 0;

    switch (pid) {
    case 0x0C:  // 发动机转速
        s_sample.rpm = ((float)a * 256.0f + b) / 4.0f;
        s_sample.has_rpm = true;
        break;
    case 0x0D:  // 车速
        s_sample.speed_kph = (float)a;
        s_sample.has_speed = true;
        break;
    case 0x05:  // 冷却液温度
        s_sample.coolant_c = (float)a - 40.0f;
        s_sample.has_coolant = true;
        break;
    case 0x11:  // 节气门开度
        s_sample.throttle_pct = (float)a * 100.0f / 255.0f;
        s_sample.has_throttle = true;
        break;
    default:
        return;
    }
    emit_sample();
}

static esp_err_t send_pid_request(uint8_t pid)
{
    twai_message_t msg = {
        .identifier = DT_OBD_REQUEST_ID,
        .data_length_code = 8,
    };
    msg.data[0] = 0x02;
    msg.data[1] = 0x01;
    msg.data[2] = pid;
    msg.data[3] = 0x00;
    msg.data[4] = 0x00;
    msg.data[5] = 0x00;
    msg.data[6] = 0x00;
    msg.data[7] = 0x00;
    return twai_transmit(&msg, pdMS_TO_TICKS(50));
}

static void can_task(void *arg)
{
    static const uint8_t pids[] = {0x0C, 0x0D, 0x05, 0x11};
    size_t next_pid = 0;
    TickType_t last_poll = 0;

    while (true) {
        twai_message_t msg;
        esp_err_t err = twai_receive(&msg, pdMS_TO_TICKS(50));
        if (err == ESP_OK) {
            handle_frame(&msg);
        } else if (err != ESP_ERR_TIMEOUT) {
            ESP_LOGW(TAG, "接收异常 %s", esp_err_to_name(err));
            vTaskDelay(pdMS_TO_TICKS(500));
            twai_start();
        }

        if (xTaskGetTickCount() - last_poll >= pdMS_TO_TICKS(DT_OBD_POLL_MS)) {
            last_poll = xTaskGetTickCount();
            send_pid_request(pids[next_pid]);
            next_pid = (next_pid + 1) % (sizeof(pids) / sizeof(pids[0]));
        }
    }
}

bool dt_can_start(void)
{
    twai_general_config_t general = TWAI_GENERAL_CONFIG_DEFAULT(
        DT_CAN_TX_GPIO, DT_CAN_RX_GPIO, TWAI_MODE_NORMAL);
    twai_timing_config_t timing = TWAI_TIMING_CONFIG_500KBITS();
#if DT_CAN_BITRATE_KBPS == 250
    timing = TWAI_TIMING_CONFIG_250KBITS();
#elif DT_CAN_BITRATE_KBPS == 1000
    timing = TWAI_TIMING_CONFIG_1MBITS();
#endif
    twai_filter_config_t filter = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    esp_err_t err = twai_driver_install(&general, &timing, &filter);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "TWAI 安装失败 %s", esp_err_to_name(err));
        return false;
    }
    err = twai_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "TWAI 启动失败 %s", esp_err_to_name(err));
        return false;
    }

    s_running = true;
    xTaskCreate(can_task, "dt_can", 4096, NULL, 4, NULL);
    ESP_LOGI(TAG, "CAN 已启动 %d kbps tx=%d rx=%d", DT_CAN_BITRATE_KBPS,
             DT_CAN_TX_GPIO, DT_CAN_RX_GPIO);
    return true;
}

void dt_can_request_pid(uint8_t pid)
{
    if (s_running) {
        send_pid_request(pid);
    }
}

#endif  // DT_ENABLE_CAN

