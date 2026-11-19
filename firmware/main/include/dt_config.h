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
#define DT_FW_VERSION "0.3.0"
#define DT_FW_BUILD 3
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
// App 的蓝牙 GPS 通道按 NMEA 0183 文本解析，因此把模块原始 GGA/RMC
// 原样转发一份；NDJSON 仍然保留，方便串口工具与后续功能直接读结构化数据。
#define DT_BLE_NMEA_PASSTHROUGH 1

// ---------------- GNSS（u-blox NEO-M9N，UART1） ----------------
// U2 pin21 TXD1 → 网络 GPS_TX → U1 pad10(IO17)：这是 ESP32 的接收脚；
// U2 pin20 RXD1 → 网络 GPS_RX → U1 pad11(IO18)：这是 ESP32 的发送脚。
#define DT_GNSS_UART_PORT 1
#define DT_GNSS_TX_GPIO 18
#define DT_GNSS_RX_GPIO 17
// PPS 秒脉冲，U1 pad4(IO4)，当前固件不做授时，只记录引脚。
#define DT_GNSS_PPS_GPIO 4
#define DT_GNSS_BUF_SIZE 4096
// 上报给 App 的最小间隔（毫秒）。10 Hz 对应 100。
#define DT_GNSS_EMIT_MS 100
// 启动时尝试把模块导航频率改到这个值（1~25）。设 0 表示完全不动模块配置。
#define DT_GNSS_TARGET_HZ 10

// ---------------- IMU（Bosch BMI088，SPI2） ----------------
// 加速度计与陀螺仪共用一组 SPI，各自一个片选：
//   IMU_SCK  U1 pad22(IO14) / IMU_MOSI pad8(IO15) / IMU_MISO pad9(IO16)
//   IMU_CS1  pad18(IO10) 加速度计 / IMU_CS2 pad19(IO11) 陀螺仪
//   IMU_INT1 pad5(IO5) / IMU_INT3 pad6(IO6)，当前用轮询，不用中断
#define DT_IMU_SPI_HOST 2
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

// ---------------- 气压计（BMP388/390，I2C） ----------------
// U4 pin5 SDO 接 +3V3，所以 I2C 地址是 0x77。当前固件不读气压计。
#define DT_BARO_SDA_GPIO 8
#define DT_BARO_SCL_GPIO 9
#define DT_BARO_SCL_HZ 400000
#define DT_BARO_ADDR 0x77

// ---------------- microSD（SPI） ----------------
// 当前固件用片内 Flash 做缓存，不挂 SD 卡；引脚先记在这里。
#define DT_SD_CS_GPIO 12
#define DT_SD_CD_GPIO 13
#define DT_SD_SCK_GPIO 38
#define DT_SD_MOSI_GPIO 39
#define DT_SD_MISO_GPIO 40

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
