// IMU：Bosch BMI088，SPI 双片选（加速度计 CS1 / 陀螺仪 CS2）。
//
// V4.6 上的实际连接（取自 PCB 网表）：
//   SCK=IO14  MOSI=IO15  MISO=IO16  CS_ACC=IO10  CS_GYRO=IO11
//   两片共用一条 SPI 总线，靠片选区分；SPI 模式 0。
//
// 两个器件都有“读之前先来一个 dummy 字节”的 SPI 特性，
// 而且加速度计上电默认是 I2C 模式，需要一次片选动作（读一次寄存器）
// 才会切到 SPI。下面把这三点都封装掉了。
#include "dt_imu.h"

#include <math.h>
#include <string.h>

#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "dt_config.h"
#include "dt_session.h"
#include "dt_types.h"

static const char *TAG = "dt_imu";

// ---- 加速度计寄存器（BMI088 SensorAPI 定义）----
#define ACC_CHIP_ID 0x00
#define ACC_X_LSB 0x04
#define ACC_CONF 0x40
#define ACC_RANGE 0x41
#define ACC_PWR_CONF 0x7C
#define ACC_PWR_CTRL 0x7D
#define ACC_SOFTRESET 0x7E

// ---- 陀螺仪寄存器 ----
#define GYRO_CHIP_ID 0x00
#define GYRO_RATE_X_LSB 0x02
#define GYRO_RANGE 0x0F
#define GYRO_BANDWIDTH 0x10
#define GYRO_LPM1 0x11
#define GYRO_SOFTRESET 0x14

#define ACC_CHIP_ID_VALUE 0x1E
#define GYRO_CHIP_ID_VALUE 0x0F

// ACC_CONF: bit7 必须置 1；0x20=normal 带宽；0x09=200 Hz 输出率
#define ACC_CONF_200HZ_NORMAL 0xA9
// ACC_RANGE: 0x01 = ±6 g -> 5460 LSB/g
#define ACC_RANGE_6G 0x01
// GYRO_RANGE: 0x00 = ±2000 dps -> 16.384 LSB/dps
#define GYRO_RANGE_2000DPS 0x00
// GYRO_BANDWIDTH: 0x02 = 400 Hz ODR / 47 Hz 低通
#define GYRO_BW_400HZ_47HZ 0x02

#define ACC_LSB_PER_G 5460.0f
#define GYRO_LSB_PER_DPS 16.384f
#define RAD_TO_DEG 57.29578f

// 陀螺仪静态零偏（启动时若静止就估出来，运动时保持 0）。
static float s_bias_gx;
static float s_bias_gy;
static float s_bias_gz;

static spi_device_handle_t s_accel;
static spi_device_handle_t s_gyro;

// 读：地址最高位置 1，随后丢弃 1 个 dummy 字节。
static esp_err_t bus_read(spi_device_handle_t dev, uint8_t reg, uint8_t *out,
                          size_t len)
{
    uint8_t tx[16] = {0};
    uint8_t rx[16] = {0};
    if (len + 1 > sizeof(tx)) {
        return ESP_ERR_INVALID_SIZE;
    }
    tx[0] = (uint8_t)(reg | 0x80);
    spi_transaction_t t = {
        .length = (len + 1) * 8,
        .tx_buffer = tx,
        .rx_buffer = rx,
    };
    esp_err_t err = spi_device_polling_transmit(dev, &t);
    if (err == ESP_OK) {
        memcpy(out, rx + 1, len);
    }
    return err;
}

// 写：地址最高位清 0，无 dummy。
static esp_err_t bus_write(spi_device_handle_t dev, uint8_t reg, uint8_t value)
{
    uint8_t buf[2] = {(uint8_t)(reg & 0x7F), value};
    spi_transaction_t t = {
        .length = 16,
        .tx_buffer = buf,
    };
    return spi_device_polling_transmit(dev, &t);
}

static esp_err_t accel_read(uint8_t reg, uint8_t *out, size_t len)
{
    return bus_read(s_accel, reg, out, len);
}

static esp_err_t accel_write(uint8_t reg, uint8_t value)
{
    return bus_write(s_accel, reg, value);
}

static esp_err_t gyro_read(uint8_t reg, uint8_t *out, size_t len)
{
    return bus_read(s_gyro, reg, out, len);
}

static esp_err_t gyro_write(uint8_t reg, uint8_t value)
{
    return bus_write(s_gyro, reg, value);
}

static bool accel_probe(void)
{
    uint8_t id = 0;
    // 第一次读会触发“I2C -> SPI”切换，返回值不可信，读两次。
    accel_read(ACC_CHIP_ID, &id, 1);
    vTaskDelay(pdMS_TO_TICKS(2));
    for (int i = 0; i < 3; i++) {
        if (accel_read(ACC_CHIP_ID, &id, 1) == ESP_OK &&
            id == ACC_CHIP_ID_VALUE) {
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    ESP_LOGE(TAG, "加速度计 ID=0x%02X（期望 0x%02X），检查 CS=IO%d",
             id, ACC_CHIP_ID_VALUE, DT_IMU_CS_ACCEL);
    return false;
}

static bool gyro_probe(void)
{
    uint8_t id = 0;
    for (int i = 0; i < 3; i++) {
        if (gyro_read(GYRO_CHIP_ID, &id, 1) == ESP_OK &&
            id == GYRO_CHIP_ID_VALUE) {
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    ESP_LOGE(TAG, "陀螺仪 ID=0x%02X（期望 0x%02X），检查 CS=IO%d", id,
             GYRO_CHIP_ID_VALUE, DT_IMU_CS_GYRO);
    return false;
}

static esp_err_t accel_configure(void)
{
    esp_err_t err = accel_write(ACC_SOFTRESET, 0xB6);
    if (err != ESP_OK) {
        return err;
    }
    // 软复位后约 1 ms 才接受下一条命令，给足 50 ms。
    vTaskDelay(pdMS_TO_TICKS(50));

    err = accel_write(ACC_PWR_CTRL, 0x04);  // 加速度计上电
    if (err != ESP_OK) {
        return err;
    }
    err = accel_write(ACC_PWR_CONF, 0x00);  // 退出挂起
    if (err != ESP_OK) {
        return err;
    }
    vTaskDelay(pdMS_TO_TICKS(5));

    err = accel_write(ACC_CONF, ACC_CONF_200HZ_NORMAL);
    if (err != ESP_OK) {
        return err;
    }
    return accel_write(ACC_RANGE, ACC_RANGE_6G);
}

static esp_err_t gyro_configure(void)
{
    esp_err_t err = gyro_write(GYRO_SOFTRESET, 0xB6);
    if (err != ESP_OK) {
        return err;
    }
    // 陀螺仪复位后需要 30 ms。
    vTaskDelay(pdMS_TO_TICKS(30));

    err = gyro_write(GYRO_RANGE, GYRO_RANGE_2000DPS);
    if (err != ESP_OK) {
        return err;
    }
    err = gyro_write(GYRO_BANDWIDTH, GYRO_BW_400HZ_47HZ);
    if (err != ESP_OK) {
        return err;
    }
    return gyro_write(GYRO_LPM1, 0x00);  // 正常模式
}

static bool read_gyro_dps(float *gx, float *gy, float *gz)
{
    uint8_t raw[6];
    if (gyro_read(GYRO_RATE_X_LSB, raw, sizeof(raw)) != ESP_OK) {
        return false;
    }
    *gx = (float)(int16_t)((raw[1] << 8) | raw[0]) / GYRO_LSB_PER_DPS;
    *gy = (float)(int16_t)((raw[3] << 8) | raw[2]) / GYRO_LSB_PER_DPS;
    *gz = (float)(int16_t)((raw[5] << 8) | raw[4]) / GYRO_LSB_PER_DPS;
    return true;
}

// 启动时估陀螺零偏：只在数据抖动很小时采纳，装着车在动就当没估到。
static void calibrate_gyro(void)
{
    const int n = 40;
    float sx = 0, sy = 0, sz = 0;
    float min_v[3] = {1e9f, 1e9f, 1e9f};
    float max_v[3] = {-1e9f, -1e9f, -1e9f};
    int got = 0;

    for (int i = 0; i < n; i++) {
        float gx, gy, gz;
        if (read_gyro_dps(&gx, &gy, &gz)) {
            sx += gx;
            sy += gy;
            sz += gz;
            float v[3] = {gx, gy, gz};
            for (int k = 0; k < 3; k++) {
                if (v[k] < min_v[k]) min_v[k] = v[k];
                if (v[k] > max_v[k]) max_v[k] = v[k];
            }
            got++;
        }
        vTaskDelay(pdMS_TO_TICKS(1000 / DT_IMU_HZ));
    }

    if (got < n / 2) {
        return;
    }
    float spread = 0;
    for (int k = 0; k < 3; k++) {
        float span = max_v[k] - min_v[k];
        if (span > spread) spread = span;
    }
    if (spread > 5.0f) {
        ESP_LOGW(TAG, "启动时设备在动（抖动 %.1f dps），跳过零偏标定", spread);
        return;
    }

    s_bias_gx = sx / (float)got;
    s_bias_gy = sy / (float)got;
    s_bias_gz = sz / (float)got;
    ESP_LOGI(TAG, "陀螺零偏 gx=%.2f gy=%.2f gz=%.2f dps", s_bias_gx, s_bias_gy,
             s_bias_gz);
}

static void imu_task(void *arg)
{
    float roll = 0;
    float pitch = 0;
    bool have_attitude = false;
    int64_t last_us = 0;
    int64_t last_log_us = 0;
    uint32_t errors = 0;

    // 外壳安装角度补偿（绕竖直轴）
    const float yaw = (float)DT_IMU_MOUNT_YAW_DEG / RAD_TO_DEG;
    const float cy = cosf(yaw);
    const float sy = sinf(yaw);

    while (true) {
        uint8_t raw[6];
        if (accel_read(ACC_X_LSB, raw, sizeof(raw)) != ESP_OK) {
            if (++errors % 20 == 1) {
                ESP_LOGW(TAG, "加速度读取失败（已连续 %u 次）",
                         (unsigned)errors);
            }
            vTaskDelay(pdMS_TO_TICKS(1000 / DT_IMU_HZ));
            continue;
        }
        errors = 0;

        int16_t ax_raw = (int16_t)((raw[1] << 8) | raw[0]);
        int16_t ay_raw = (int16_t)((raw[3] << 8) | raw[2]);
        int16_t az_raw = (int16_t)((raw[5] << 8) | raw[4]);

        float ax = (float)ax_raw / ACC_LSB_PER_G;
        float ay = (float)ay_raw / ACC_LSB_PER_G;
        float az = (float)az_raw / ACC_LSB_PER_G;

        float gx = 0, gy = 0, gz = 0;
        if (!read_gyro_dps(&gx, &gy, &gz)) {
            gx = gy = gz = 0;
        }
        gx -= s_bias_gx;
        gy -= s_bias_gy;
        gz -= s_bias_gz;

        // 安装偏航补偿：只在水平面内旋转，保持 az 不变。
        float ax_r = ax * cy + ay * sy;
        float ay_r = -ax * sy + ay * cy;

        int64_t now_us = esp_timer_get_time();
        // 实际间隔，首次调用按标称周期算，避免上电第一帧爆掉。
        float dt = last_us > 0 ? (float)(now_us - last_us) / 1e6f
                               : 1.0f / (float)DT_IMU_HZ;
        last_us = now_us;
        if (dt < 0.001f || dt > 0.5f) {
            dt = 1.0f / (float)DT_IMU_HZ;
        }

        float roll_acc = atan2f(ay_r, az) * RAD_TO_DEG;
        float pitch_acc =
            atan2f(-ax_r, sqrtf(ay_r * ay_r + az * az)) * RAD_TO_DEG;
        if (!have_attitude) {
            roll = roll_acc;
            pitch = pitch_acc;
            have_attitude = true;
        } else {
            // 陀螺积分为主，加速度计慢速校正。
            roll = 0.98f * (roll + gx * dt) + 0.02f * roll_acc;
            pitch = 0.98f * (pitch + gy * dt) + 0.02f * pitch_acc;
        }

        dt_imu_sample_t sample = {
            .ax = ax_r,
            .ay = ay_r,
            .az = az,
            .gx = gx,
            .gy = gy,
            .gz = gz,
            .roll_deg = roll,
            .pitch_deg = pitch,
        };
        dt_session_on_imu(&sample);

#if DT_SERIAL_TELEMETRY
        // 首板联调：输出原始重力分量与角速度，静态时 |a| 应接近 1 g。
        if (now_us - last_log_us >= (int64_t)DT_SERIAL_TELEMETRY_MS * 1000) {
            last_log_us = now_us;
            ESP_LOGI(TAG,
                     "a=(%.2f,%.2f,%.2f)g gz=%.1fdps roll=%.1f pitch=%.1f",
                     ax_r, ay_r, az, gz, roll, pitch);
        }
#endif

        vTaskDelay(pdMS_TO_TICKS(1000 / DT_IMU_HZ));
    }
}

bool dt_imu_start(void)
{
    spi_bus_config_t bus = {
        .mosi_io_num = DT_IMU_SPI_MOSI,
        .miso_io_num = DT_IMU_SPI_MISO,
        .sclk_io_num = DT_IMU_SPI_SCK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 32,
    };

    esp_err_t err =
        spi_bus_initialize((spi_host_device_t)DT_IMU_SPI_HOST, &bus,
                           SPI_DMA_DISABLED);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "SPI 总线初始化失败 %s", esp_err_to_name(err));
        return false;
    }

    spi_device_interface_config_t accel_cfg = {
        .clock_speed_hz = 5 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = DT_IMU_CS_ACCEL,
        .queue_size = 1,
    };
    err = spi_bus_add_device((spi_host_device_t)DT_IMU_SPI_HOST, &accel_cfg,
                             &s_accel);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "加速度计设备注册失败 %s", esp_err_to_name(err));
        return false;
    }

    spi_device_interface_config_t gyro_cfg = {
        .clock_speed_hz = 5 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = DT_IMU_CS_GYRO,
        .queue_size = 1,
    };
    err = spi_bus_add_device((spi_host_device_t)DT_IMU_SPI_HOST, &gyro_cfg,
                             &s_gyro);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "陀螺仪设备注册失败 %s", esp_err_to_name(err));
        return false;
    }

    if (!accel_probe() || !gyro_probe()) {
        return false;
    }

    err = accel_configure();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "加速度计配置失败 %s", esp_err_to_name(err));
        return false;
    }
    err = gyro_configure();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "陀螺仪配置失败 %s", esp_err_to_name(err));
        return false;
    }

    calibrate_gyro();

    xTaskCreate(imu_task, "dt_imu", 4096, NULL, 4, NULL);
    ESP_LOGI(TAG, "BMI088 已启动 %d Hz（±6 g / ±2000 dps）", DT_IMU_HZ);
    return true;
}
