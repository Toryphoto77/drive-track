// 电源与指示灯。
//
// V4.6 的实际连接：
//   VBAT 经 R30/R31 各 100k 分压 -> VBAT_DIV -> IO1（ADC1_CH0），所以读数要 ×2
//   5mm 状态灯：IO7 -> R25 -> Q2 低边驱动，IO7 高电平亮
//   第 4 颗电量灯：IO2 高电平亮（前三颗由 IP5306 自己驱动）
//
// 状态灯含义：待机时每 2 秒短闪一次；记录中改成快速双闪；低电时第 4 颗灯常亮。
#include "dt_power.h"

#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "dt_config.h"
#include "dt_session.h"

static const char *TAG = "dt_power";

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static adc_channel_t s_chan = ADC_CHANNEL_0;
static bool s_cali_ok;
static int s_batt_mv;

static bool adc_setup(void)
{
    adc_oneshot_unit_init_cfg_t unit = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    if (adc_oneshot_new_unit(&unit, &s_adc) != ESP_OK) {
        return false;
    }

    adc_oneshot_chan_cfg_t chan = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_oneshot_config_channel(s_adc, s_chan, &chan) != ESP_OK) {
        return false;
    }

#if ADC_CALI_SCHEME_CURVE_FITTING_SUPPORTED
    adc_cali_curve_fitting_config_t cali = {
        .unit_id = ADC_UNIT_1,
        .chan = s_chan,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    s_cali_ok = adc_cali_create_scheme_curve_fitting(&cali, &s_cali) == ESP_OK;
#endif
    if (!s_cali_ok) {
        ESP_LOGW(TAG, "ADC 未校准，电压按线性估算");
    }
    return true;
}

static int read_batt_mv(void)
{
    int sum = 0;
    int n = 0;
    for (int i = 0; i < 8; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, s_chan, &raw) != ESP_OK) {
            continue;
        }
        int mv = 0;
        if (s_cali_ok) {
            if (adc_cali_raw_to_voltage(s_cali, raw, &mv) != ESP_OK) {
                continue;
            }
        } else {
            // 12 dB 衰减满量程约 3.1 V，4095 对应 3100 mV。
            mv = raw * 3100 / 4095;
        }
        sum += mv;
        n++;
    }
    if (n == 0) {
        return -1;
    }
    // 分压比 2:1，还原到电池端。
    return (int)((float)(sum / n) * DT_BAT_DIVIDER);
}

static void power_task(void *arg)
{
    bool low = false;
    uint32_t tick = 0;

    while (true) {
        int mv = read_batt_mv();
        if (mv > 0) {
            s_batt_mv = mv;
        }

        bool recording = dt_session_active();
        if (recording) {
            // 双闪：400 ms 一个周期，两短亮。
            int phase = (int)(tick % 5);
            gpio_set_level(DT_LED_STAT_GPIO, (phase == 0 || phase == 2) ? 1 : 0);
        } else {
            // 心跳：每 2 秒亮 100 ms。
            gpio_set_level(DT_LED_STAT_GPIO, (tick % 20 == 0) ? 1 : 0);
        }

        // 低电点亮第 4 颗灯；回差 100 mV，避免电压抖动时闪烁。
        if (!low && s_batt_mv > 0 && s_batt_mv < DT_BAT_LOW_MV) {
            low = true;
            ESP_LOGW(TAG, "电量偏低 %d mV", s_batt_mv);
        } else if (low && s_batt_mv > DT_BAT_LOW_MV + 100) {
            low = false;
        }
        gpio_set_level(DT_LED_BATT4_GPIO, low ? 1 : 0);

        tick++;
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

bool dt_power_start(void)
{
    gpio_config_t out = {
        .pin_bit_mask = (1ULL << DT_LED_STAT_GPIO) | (1ULL << DT_LED_BATT4_GPIO),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&out);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "指示灯 GPIO 配置失败 %s", esp_err_to_name(err));
        return false;
    }
    gpio_set_level(DT_LED_STAT_GPIO, 0);
    gpio_set_level(DT_LED_BATT4_GPIO, 0);

    if (!adc_setup()) {
        ESP_LOGE(TAG, "ADC 初始化失败，电量不可用");
        return false;
    }

    xTaskCreate(power_task, "dt_power", 3072, NULL, 3, NULL);
    ESP_LOGI(TAG, "电源监控已启动（VBAT=IO%d，状态灯=IO%d）", DT_BAT_ADC_GPIO,
             DT_LED_STAT_GPIO);
    return true;
}

int dt_power_batt_mv(void)
{
    return s_batt_mv;
}

int dt_power_batt_percent(void)
{
    // 单节锂电的近似放电曲线：空载电压 4.20 V 满、3.30 V 空。
    // 只做展示用途，不参与保护逻辑（低电保护仍看 mV 回差）。
    static const struct {
        int mv;
        int pct;
    } curve[] = {
        {4200, 100}, {4100, 90}, {4000, 78}, {3900, 64}, {3800, 50},
        {3700, 36},  {3600, 24}, {3500, 14}, {3400, 7},  {3300, 0},
    };
    const int mv = s_batt_mv;
    if (mv <= 0) {
        return -1;
    }
    const int n = (int)(sizeof(curve) / sizeof(curve[0]));
    if (mv >= curve[0].mv) {
        return 100;
    }
    if (mv <= curve[n - 1].mv) {
        return 0;
    }
    for (int i = 1; i < n; i++) {
        if (mv >= curve[i].mv) {
            const int hi_mv = curve[i - 1].mv;
            const int lo_mv = curve[i].mv;
            const int hi_pct = curve[i - 1].pct;
            const int lo_pct = curve[i].pct;
            const int span = hi_mv - lo_mv;
            if (span <= 0) {
                return lo_pct;
            }
            return lo_pct + (mv - lo_mv) * (hi_pct - lo_pct) / span;
        }
    }
    return 0;
}
