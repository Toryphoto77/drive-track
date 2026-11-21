// DriveTrack 自研硬件配置文件。
//
// 硬件：DriveTrack PCB V4.6
//   主控 ESP32-S3-WROOM-1U-N16R8（16 MB Flash + 8 MB 八线 PSRAM）
//   GNSS u-blox NEO-M9N、IMU Bosch BMI088（SPI）、气压计 BMP388/390（I2C）
//   电源 IP5306 + TPS563201、microSD、USB-C（原生 USB-Serial-JTAG）
//
// 下面所有引脚号都取自 V4.6 的 PCB 网表（U1 焊盘号 → 网络名），
// 已与 ASSEMBLY-v4.6.txt 的 IO7/IO2/IO1 描述交叉核对，不要凭印象改。
#pragma once

// ---------------- 固件身份 ----------------
// 改功能就同时抬高版本号；App 按 build 判断是否需要升级。
// 0.5.1 / build 13：在 0.5.0 基础上增加天线诊断（周期打开 GSV 解析 C/N0），
// 随 1.8.1 App 发布。
#define DT_FW_VERSION "0.5.1"
#define DT_FW_BUILD 13
#define DT_DEVICE_MODEL "DT-BOX-1"
#define DT_BOARD_NAME "DriveTrack V4.6"

// ---------------- WiFi 热点（OTA 通道） ----------------
// SSID 形如 DriveTrack-A1B2，后缀取 MAC 末两字节。
#define DT_AP_SSID_PREFIX "DriveTrack"
// WPA2 密码，至少 8 位；App 固件升级页显示的就是这一串。
#define DT_AP_PASSWORD "drivetrack123"
#define DT_AP_CHANNEL 6
#define DT_AP_MAX_CONN 2

// ---------------- 功能开关 ----------------
#define DT_ENABLE_GNSS 1
#define DT_ENABLE_IMU 1
// V4.6 板没有 CAN 收发器，也没有引出 TWAI 引脚，OBD/CAN 必须等下一版硬件。
// 代码保留在 dt_can.c，换板后把该项置 1 并填好下面的引脚即可。
#define DT_ENABLE_CAN 0
#define DT_ENABLE_BLE 1
#define DT_ENABLE_BARO 1
// App 的蓝牙 GPS 通道按 NMEA 0183 文本解析，因此把模块原始 GGA/RMC
// 原样转发一份；NDJSON 仍然保留，方便串口工具与后续功能直接读结构化数据。
#define DT_BLE_NMEA_PASSTHROUGH 1

// ---------------- GNSS（u-blox NEO-M9N，UART1） ----------------
// U2 pin20 TXD1（模块输出） → 网络 GPS_RX → U1 pad11(IO18)：ESP32 的接收脚；
// U2 pin21 RXD1（模块输入） → 网络 GPS_TX → U1 pad10(IO17)：ESP32 的发送脚。
// 注意：网络名 GPS_TX 指的是模块侧信号，不要按名字直接当 ESP32 的 TX。
#define DT_GNSS_UART_PORT 1
#define DT_GNSS_TX_GPIO 17
#define DT_GNSS_RX_GPIO 18
// PPS 秒脉冲，U1 pad4(IO4)，当前固件不做授时，只记录引脚。
#define DT_GNSS_PPS_GPIO 4
#define DT_GNSS_BUF_SIZE 4096
// 默认输出间隔（毫秒）。运行时支持 10 / 20 / 25 Hz，最高 25 Hz 对应 40 ms。
#define DT_GNSS_EMIT_MS 40
// NEO-M9N 硬件最高 25 Hz，启动与掉电恢复均默认使用最高档。
#define DT_GNSS_TARGET_HZ 25

// ---------------- 天线诊断（GSV / C/N0） ----------------
// 周期性打开 NMEA GSV，解析每颗星的载噪比并打到串口，用来判断天线、
// 馈线、接头和供电是否正常。GSV 只在导航解算周期输出，25 Hz 下打开会
// 瞬间灌满 38400 bps 的串口（GGA/RMC 也会跟着丢），所以诊断窗口内临时
// 把导航频率降到 1 Hz，采完立刻恢复 App 设置的档位。
// 录制期间不做诊断，避免打断 25 Hz 记录的连续性。
#define DT_GNSS_DIAG_ENABLE 1
#define DT_GNSS_DIAG_PERIOD_S 30   // 两次诊断的间隔
#define DT_GNSS_DIAG_FIRST_S 10    // 开机后第一次诊断前的等待
#define DT_GNSS_DIAG_WINDOW_MS 2500  // 单次采集窗口（1 Hz 下覆盖两轮 GSV）
#define DT_GNSS_DIAG_MAX_SATS 64     // 去重后的卫星上限
#define DT_GNSS_DIAG_STRONG 8        // 串口打印最强的几颗

// ---------------- IMU（Bosch BMI088，SPI2） ----------------
// 加速度计与陀螺仪共用一组 SPI，各自一个片选：
//   IMU_SCK  U1 pad22(IO14) / IMU_MOSI pad8(IO15) / IMU_MISO pad9(IO16)
//   IMU_CS1  pad18(IO10) 加速度计 / IMU_CS2 pad19(IO11) 陀螺仪
//   IMU_INT1 pad5(IO5) / IMU_INT3 pad6(IO6)，当前用轮询，不用中断
// ESP32-S3 上 SPI2_HOST=1、SPI3_HOST=2（见 hal/spi_types.h）。
// microSD 走 SPI3，IMU 必须走 SPI2，否则两条外设抢同一条 SPI 总线，
// 后初始化的一方 spi_bus_initialize 会返回 ESP_ERR_INVALID_STATE。
#define DT_IMU_SPI_HOST 1
#define DT_IMU_SPI_SCK 14
#define DT_IMU_SPI_MOSI 15
#define DT_IMU_SPI_MISO 16
#define DT_IMU_CS_ACCEL 10
#define DT_IMU_CS_GYRO 11
#define DT_IMU_INT_ACCEL 5
#define DT_IMU_INT_GYRO 6
#define DT_IMU_HZ 20
// 板子装进外壳后若有 90°/180° 旋转，用这个角度把坐标系转正。
#define DT_IMU_MOUNT_YAW_DEG 0

// ---------------- 气压计（BMP390，I2C） ----------------
// U4 pin5 SDO 接 +3V3，所以 I2C 地址是 0x77。
#define DT_BARO_SDA_GPIO 8
#define DT_BARO_SCL_GPIO 9
#define DT_BARO_SCL_HZ 400000
#define DT_BARO_ADDR 0x77
// 采样与上报频率。10 Hz 才能给 ESKF 的垂直通道提供足够的高差/坡度分辨率；
// BMP390 本身可到 50 Hz，10 Hz 不会刷爆串口和蓝牙。
#define DT_BARO_HZ 10

// ---------------- microSD（SPI3 + FATFS） ----------------
// 0.4.0 起：开机先挂 SD，挂上就用 SD 存会话缓存，挂不上自动回落片内 SPIFFS。
#define DT_SD_CS_GPIO 12
#define DT_SD_CD_GPIO 13
#define DT_SD_SCK_GPIO 38
#define DT_SD_MOSI_GPIO 39
#define DT_SD_MISO_GPIO 40
#define DT_SD_MOUNT_POINT "/sdcard"
#define DT_SD_FILE DT_SD_MOUNT_POINT "/session.ndjson"

// ---------------- 电源与指示灯 ----------------
// VBAT 经 R30/R31 各 100k 分压为 VBAT_DIV，接 U1 pad39(IO1)=ADC1_CH0。
#define DT_BAT_ADC_GPIO 1
#define DT_BAT_DIVIDER 2.0f
// 5mm 状态灯：IO7 高电平 → R25 → Q2 → 灯亮。
#define DT_LED_STAT_GPIO 7
// 第 4 颗电量灯由 IO2 高电平点亮（前三颗由 IP5306 驱动）。
#define DT_LED_BATT4_GPIO 2
// 低于这个电压点亮第 4 颗灯，作为“该充电了”的提示。
#define DT_BAT_LOW_MV 3500

// ---------------- CAN / OBD（V4.6 无收发器，占位） ----------------
// 注意：V4.6 上 IO21 是 DUMMY_EN 网络、IO47 是 NC（Pad24 空脚）。
// 下面两个值只是占位，换板时必须按新板网表重新核对，不要直接沿用。
#define DT_CAN_TX_GPIO 21
#define DT_CAN_RX_GPIO 47
#define DT_CAN_BITRATE_KBPS 500
#define DT_OBD_REQUEST_ID 0x7DF
#define DT_OBD_POLL_MS 200

// ---------------- 首板联调串口输出 ----------------
// 每隔一段时间把 GNSS/IMU 的关键值打到串口，tools/verify_board.ps1 靠它判断
// 传感器是否真的在出数。出货固件可以置 0 关掉。
#define DT_SERIAL_TELEMETRY 1
#define DT_SERIAL_TELEMETRY_MS 5000

// ---------------- 本地缓存 ----------------
#define DT_STORE_MOUNT_POINT "/store"
#define DT_STORE_FILE DT_STORE_MOUNT_POINT "/session.ndjson"
#define DT_STORE_NVS_NAMESPACE "dtbox"
