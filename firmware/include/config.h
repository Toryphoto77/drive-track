#pragma once

// ============================================================================
// 驰迹自研记录模块 —— 编译期配置
//
// 引脚必须与你的 PCB / 接线一致。默认值按 ESP32-S3-DevKitC-1 + 杜邦线
// 接法给出，详见 docs/WIRING.md。改完重新编译烧录即可生效。
// ============================================================================

// ---------- 设备身份 ----------
// BLE 广播名。App 的“无过滤扫描”会显示这个名字；
// 同时本机广播 Nordic UART 服务，App 会按 NUS 自动订阅。
#define DEVICE_NAME "DriveTrack-GPS"

// ---------- GNSS：u-blox NEO-M9N ----------
// ESP32 的 RX 接模块 TX，TX 接模块 RX（交叉）。
#define PIN_GNSS_RX 18
#define PIN_GNSS_TX 17

// M9N 出厂默认 38400；固件启动后会切到 115200 并持久化到模块。
#define GNSS_BAUD_BOOT 38400
#define GNSS_BAUD_RUN 115200

// 输出频率（Hz）：10 或 25。
// App 的赛道硬件门槛是 ≥5Hz；25Hz 需要 App 侧 MTU 协商（本仓库已加）。
#define GNSS_RATE_HZ 10

// ---------- I2C：BMI088 + BMP390 ----------
#define PIN_I2C_SDA 8
#define PIN_I2C_SCL 9
#define I2C_FREQ_HZ 400000

#define BMI088_ACC_ADDR 0x18  // SAO 接地
#define BMI088_GYR_ADDR 0x68  // SAO 接地
#define BMP390_ADDR 0x77      // SDO 接 VDDIO 时为 0x77，接地为 0x76

// ---------- 功能开关 ----------
#define ENABLE_IMU 1
#define ENABLE_BARO 1

// ---------- 状态灯（可选） ----------
// DevKitC-1 板载 RGB 灯是 WS2812，不能直接 digitalWrite。
// 若你外接了普通 LED，把引脚填进来并置 1。
#define ENABLE_STATUS_LED 0
#define PIN_STATUS_LED 2
