#include "dt_baro.h"

#include "dt_ble.h"
#include "dt_config.h"

#include "driver/i2c_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#if DT_ENABLE_BARO

static const char *TAG = "dt_baro";

// BMP390 寄存器（BST-BMP390-DS002）
#define BMP3_REG_CHIP_ID 0x00
#define BMP3_REG_DATA 0x04        // press_xlsb/lsb/msb, temp_xlsb/lsb/msb
#define BMP3_REG_PWR_CTRL 0x1B
#define BMP3_REG_OSR 0x1C
#define BMP3_REG_ODR 0x1D
#define BMP3_REG_IIR 0x1F
#define BMP3_REG_CALIB 0x31       // 21 字节校准参数
#define BMP3_REG_CMD 0x7E
#define BMP3_CMD_SOFTRESET 0xB6
#define BMP3_CHIP_ID_388 0x50
#define BMP3_CHIP_ID_390 0x60

typedef struct {
    double t1, t2, t3;
    double p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11;
} bmp3_calib_t;

static i2c_master_bus_handle_t s_bus;
static i2c_master_dev_handle_t s_dev;
static bmp3_calib_t s_cal;
static dt_baro_sample_t s_last;
static bool s_ready;

static esp_err_t baro_read_regs(uint8_t reg, uint8_t *buf, size_t len)
{
    return i2c_master_transmit_receive(s_dev, &reg, 1, buf, len,
                                       pdMS_TO_TICKS(50));
}

static esp_err_t baro_write_reg(uint8_t reg, uint8_t value)
{
    uint8_t b[2] = {reg, value};
    return i2c_master_transmit(s_dev, b, sizeof(b), pdMS_TO_TICKS(50));
}

static bool baro_compensate(uint32_t adc_p, uint32_t adc_t,
                            dt_baro_sample_t *out);

// 寄存器快照，用于定位“芯片应答但不转换”的情况
static void baro_dump(const char *why)
{
    uint8_t err = 0, st = 0, pwr = 0, osr = 0, odr = 0, iir = 0;
    uint8_t d[6] = {0};
    baro_read_regs(0x02, &err, 1);
    baro_read_regs(0x03, &st, 1);
    baro_read_regs(BMP3_REG_PWR_CTRL, &pwr, 1);
    baro_read_regs(BMP3_REG_OSR, &osr, 1);
    baro_read_regs(BMP3_REG_ODR, &odr, 1);
    baro_read_regs(BMP3_REG_IIR, &iir, 1);
    bool ok = baro_read_regs(BMP3_REG_DATA, d, 6) == ESP_OK;
    ESP_LOGW(TAG,
             "%s err=0x%02X sta=0x%02X pwr=0x%02X osr=0x%02X odr=0x%02X "
             "iir=0x%02X data=%02X%02X%02X %02X%02X%02X%s",
             why, err, st, pwr, osr, odr, iir, d[0], d[1], d[2], d[3], d[4],
             d[5], ok ? "" : "(读失败)");

    uint32_t adc_p = ((uint32_t)d[2] << 16) | ((uint32_t)d[1] << 8) | d[0];
    uint32_t adc_t = ((uint32_t)d[5] << 16) | ((uint32_t)d[4] << 8) | d[3];
    dt_baro_sample_t tmp = {0};
    bool valid = baro_compensate(adc_p, adc_t, &tmp);
    ESP_LOGW(TAG, "  adcP=%lu adcT=%lu -> T=%.2fC P=%.1fPa valid=%d",
             (unsigned long)adc_p, (unsigned long)adc_t, tmp.temp_c,
             tmp.press_pa, (int)valid);
}

static bool baro_load_calib(void)
{
    uint8_t c[21];
    if (baro_read_regs(BMP3_REG_CALIB, c, sizeof(c)) != ESP_OK) {
        return false;
    }

    // 寄存器里是原始整数，必须先按各自的 2 的幂缩放，补偿公式才成立。
    // 缩放系数与 Bosch BMP3_SensorAPI 的 quantized_calib_data 完全一致。
    uint16_t t1r = (uint16_t)(c[0] | (c[1] << 8));
    uint16_t t2r = (uint16_t)(c[2] | (c[3] << 8));
    int8_t t3r = (int8_t)c[4];
    int16_t p1r = (int16_t)(c[5] | (c[6] << 8));
    int16_t p2r = (int16_t)(c[7] | (c[8] << 8));
    int8_t p3r = (int8_t)c[9];
    int8_t p4r = (int8_t)c[10];
    uint16_t p5r = (uint16_t)(c[11] | (c[12] << 8));
    uint16_t p6r = (uint16_t)(c[13] | (c[14] << 8));
    int8_t p7r = (int8_t)c[15];
    int8_t p8r = (int8_t)c[16];
    uint16_t p9r = (uint16_t)(c[17] | (c[18] << 8));
    int8_t p10r = (int8_t)c[19];
    int8_t p11r = (int8_t)c[20];

    s_cal.t1 = (double)t1r * 256.0;                    // 1/(1/2^8)
    s_cal.t2 = (double)t2r / 1073741824.0;             // 2^30
    s_cal.t3 = (double)t3r / 281474976710656.0;        // 2^48
    s_cal.p1 = (double)(p1r - 16384) / 1048576.0;      // 2^20
    s_cal.p2 = (double)(p2r - 16384) / 536870912.0;    // 2^29
    s_cal.p3 = (double)p3r / 4294967296.0;             // 2^32
    s_cal.p4 = (double)p4r / 137438953472.0;           // 2^37
    s_cal.p5 = (double)p5r * 8.0;                      // 1/(1/2^3)
    s_cal.p6 = (double)p6r / 64.0;
    s_cal.p7 = (double)p7r / 256.0;
    s_cal.p8 = (double)p8r / 32768.0;
    s_cal.p9 = (double)p9r / 281474976710656.0;        // 2^48
    s_cal.p10 = (double)p10r / 281474976710656.0;      // 2^48
    s_cal.p11 = (double)p11r / 36893488147419103232.0; // 2^65

    ESP_LOGI(TAG, "校准原始 T1=%u T2=%u T3=%d P1=%d P2=%d P5=%u P6=%u P9=%u",
             t1r, t2r, t3r, p1r, p2r, p5r, p6r, p9r);
    return true;
}

// Bosch BMP3 官方补偿算法（浮点版）
static bool baro_compensate(uint32_t adc_p, uint32_t adc_t,
                            dt_baro_sample_t *out)
{
    if (adc_t == 0x800000 || adc_p == 0x800000) {
        return false;
    }

    double pd1 = (double)adc_t - s_cal.t1;
    double pd2 = pd1 * s_cal.t2;
    double t_lin = pd2 + (pd1 * pd1) * s_cal.t3;
    if (t_lin < -40.0) {
        t_lin = -40.0;
    } else if (t_lin > 85.0) {
        t_lin = 85.0;
    }

    pd1 = s_cal.p6 * t_lin;
    pd2 = s_cal.p7 * t_lin * t_lin;
    double pd3 = s_cal.p8 * t_lin * t_lin * t_lin;
    double po1 = s_cal.p5 + pd1 + pd2 + pd3;

    pd1 = s_cal.p2 * t_lin;
    pd2 = s_cal.p3 * t_lin * t_lin;
    pd3 = s_cal.p4 * t_lin * t_lin * t_lin;
    double po2 = (double)adc_p * (s_cal.p1 + pd1 + pd2 + pd3);

    pd1 = (double)adc_p * (double)adc_p;
    pd2 = s_cal.p9 + s_cal.p10 * t_lin;
    pd3 = pd1 * pd2;
    double pd4 = pd3 + s_cal.p11 * t_lin * t_lin * t_lin;

    float press_pa = (float)(po1 + po2 + pd4);
    out->temp_c = (float)t_lin;
    out->press_pa = press_pa;
    // 国际标准大气：1013.25 hPa 对应 0 m
    out->alt_m = 44330.0f * (1.0f - powf(press_pa / 101325.0f, 0.190295f));
    return press_pa >= 30000.0f && press_pa <= 125000.0f;
}

static bool baro_sample_once(dt_baro_sample_t *out)
{
    uint8_t d[6];
    if (baro_read_regs(BMP3_REG_DATA, d, sizeof(d)) != ESP_OK) {
        return false;
    }
    uint32_t adc_p = ((uint32_t)d[2] << 16) | ((uint32_t)d[1] << 8) | d[0];
    uint32_t adc_t = ((uint32_t)d[5] << 16) | ((uint32_t)d[4] << 8) | d[3];
    return baro_compensate(adc_p, adc_t, out);
}

static void baro_task(void *arg)
{
    (void)arg;
    char line[128];

    while (true) {
        dt_baro_sample_t s;
        if (baro_sample_once(&s)) {
            s_last = s;
            ESP_LOGI(TAG, "T=%.1fC P=%.1fPa alt=%.1fm", s.temp_c, s.press_pa,
                     s.alt_m);
            snprintf(line, sizeof(line),
                     "{\"t\":\"baro\",\"tc\":%.2f,\"pa\":%.1f,\"alt\":%.1f}",
                     s.temp_c, s.press_pa, s.alt_m);
            dt_ble_send_line(line);
        } else {
            baro_dump("读数无效");
        }
        vTaskDelay(pdMS_TO_TICKS(1000 / DT_BARO_HZ));
    }
}

bool dt_baro_start(void)
{
    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = DT_BARO_SDA_GPIO,
        .scl_io_num = DT_BARO_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    if (i2c_new_master_bus(&bus_cfg, &s_bus) != ESP_OK) {
        ESP_LOGW(TAG, "I2C 总线初始化失败");
        return false;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = DT_BARO_ADDR,
        .scl_speed_hz = DT_BARO_SCL_HZ,
    };
    if (i2c_master_bus_add_device(s_bus, &dev_cfg, &s_dev) != ESP_OK) {
        ESP_LOGW(TAG, "I2C 设备挂载失败");
        return false;
    }

    uint8_t id = 0;
    if (baro_read_regs(BMP3_REG_CHIP_ID, &id, 1) != ESP_OK) {
        ESP_LOGW(TAG, "读不到 CHIP_ID（0x%02X），气压计未焊接或地址不对",
                 DT_BARO_ADDR);
        return false;
    }
    if (id != BMP3_CHIP_ID_390 && id != BMP3_CHIP_ID_388) {
        ESP_LOGW(TAG, "CHIP_ID=0x%02X，不是 BMP388/390", id);
        return false;
    }
    ESP_LOGI(TAG, "CHIP_ID=0x%02X（%s）", id,
             id == BMP3_CHIP_ID_390 ? "BMP390" : "BMP388/BMP581?");

    baro_write_reg(BMP3_REG_CMD, BMP3_CMD_SOFTRESET);
    vTaskDelay(pdMS_TO_TICKS(10));

    if (!baro_load_calib()) {
        ESP_LOGW(TAG, "校准参数读取失败");
        return false;
    }

    // 过采样 ×4（温度/气压），ODR 25 Hz，IIR 系数 3
    baro_write_reg(BMP3_REG_OSR, 0x12);
    baro_write_reg(BMP3_REG_ODR, 0x03);
    baro_write_reg(BMP3_REG_IIR, 0x02);
    // PWR_CTRL: mode=normal(0b10<<4) | temp_en | press_en = 0x23
    // 注意：mode 位是 bit5:4，写成 0x33 会落进保留模式，芯片不转换，
    // 数据寄存器恒为 0x800000（无效）。
    if (baro_write_reg(BMP3_REG_PWR_CTRL, 0x23) != ESP_OK) {
        ESP_LOGW(TAG, "启动转换失败");
        return false;
    }
    vTaskDelay(pdMS_TO_TICKS(10));
    uint8_t pwr_rb = 0;
    baro_read_regs(BMP3_REG_PWR_CTRL, &pwr_rb, 1);
    ESP_LOGI(TAG, "PWR_CTRL 写 0x23，读回 0x%02X", pwr_rb);
    if (((pwr_rb >> 4) & 0x03) == 0x00) {
        // 个别批次首次写入会被丢弃，重写一次
        baro_write_reg(BMP3_REG_PWR_CTRL, 0x23);
        vTaskDelay(pdMS_TO_TICKS(10));
        baro_read_regs(BMP3_REG_PWR_CTRL, &pwr_rb, 1);
        ESP_LOGW(TAG, "重写 PWR_CTRL，读回 0x%02X", pwr_rb);
    }

    // 首帧要等第一次转换完成（×4 过采样约 20 ms），轮询最多 300 ms
    bool got = false;
    for (int i = 0; i < 30; i++) {
        vTaskDelay(pdMS_TO_TICKS(10));
        if (baro_sample_once(&s_last)) {
            got = true;
            break;
        }
    }
    if (!got) {
        baro_dump("首帧读数无效");
        ESP_LOGW(TAG, "继续运行，每秒打印寄存器快照便于定位");
    }
    s_ready = true;

    BaseType_t ok = xTaskCreate(baro_task, "dt_baro", 4096, NULL, 4, NULL);
    if (ok != pdPASS) {
        s_ready = false;
        return false;
    }

    ESP_LOGI(TAG, "BMP3%c 已启动 %d Hz（I2C %d/%d，0x%02X）",
             id == BMP3_CHIP_ID_390 ? '9' : '8', DT_BARO_HZ,
             DT_BARO_SDA_GPIO, DT_BARO_SCL_GPIO, DT_BARO_ADDR);
    return true;
}

bool dt_baro_read(dt_baro_sample_t *out)
{
    if (!s_ready || out == NULL) {
        return false;
    }
    *out = s_last;
    return true;
}

#else

bool dt_baro_start(void)
{
    return false;
}

bool dt_baro_read(dt_baro_sample_t *out)
{
    (void)out;
    return false;
}

#endif
