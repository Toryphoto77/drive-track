# 驰迹自研记录模块 · 固件

ESP32-S3 + NEO-M9N + BMI088 + BMP390 的车载定位记录模块固件。
对手机只暴露一个 BLE 串口（Nordic UART Service），把 GNSS 的 NMEA
文本按设定频率推给驰迹 App。

## 功能

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| GNSS（NEO-M9N） | 已实现 | UART1，自动切 115200，默认 10 Hz，可配 25 Hz；转发 GGA/RMC/GSA |
| BLE 串口（NUS） | 已实现 | 广播 `DriveTrack-GPS`，自动按 MTU 分片 |
| 控制命令 | 已实现 | `RATE=` / `STATUS?` / `REBOOT` |
| BMI088 IMU | 已实现（低频自检） | I2C 直驱，上电自检 + 5 Hz 采样；默认不推 BLE |
| BMP390 气压计 | 已实现（低频自检） | 1 Hz 采样，串口输出气压/温度 |
| 数据落盘 / OTA | 未实现 | 当前定位数据只走 BLE，升级用 USB |

> App 目前只消费 GNSS 的 NMEA。IMU / 气压计数据先留在设备侧做硬件
> 自检，等 App 增加外部 IMU 输入后再实现推送。

## 目录

```
firmware/
├── platformio.ini        # 编译与依赖
├── include/config.h      # 引脚、频率、功能开关（改这里）
├── src/
│   ├── main.cpp          # 启动、主循环、健康日志
│   ├── gnss.*            # NEO-M9N：UBX 配置 + NMEA 行透传
│   ├── ble_nus.*         # BLE 串口（NUS）与分片发送
│   ├── imu_bmi088.*      # BMI088 I2C 驱动
│   ├── baro_bmp390.*     # BMP390 封装
│   └── nmea_util.*       # 校验和与语句过滤
└── docs/
    ├── WIRING.md         # 接线与上电检查
    ├── FLASHING.md       # 烧录步骤与排错
    ├── TOOLS.md          # 工具清单
    └── PROTOCOL.md       # BLE / NMEA 协议
```

## 快速开始

```bash
cd firmware
pio run -t upload        # 编译并烧录
pio device monitor       # 115200 看日志
```

没有 PlatformIO 的机器，按 [docs/FLASHING.md](docs/FLASHING.md) 的
方式 A（VS Code）或方式 C（esptool）操作。

## 构建状态

- 已用 PlatformIO Core 6.1.18 + espressif32 6.9.0 编译通过：
  RAM 9.4%，Flash 15.9%（NimBLE-Arduino 2.5.2、Adafruit BMP3XX 2.1.6）。
- 已生成现成固件，可直接烧录，见 [`release/`](release/)：
  - `DriveTrack-GPS-full.bin`：整包，烧到 `0x0`
  - `DriveTrack-GPS-app.bin`：仅应用，升级时烧到 `0x10000`
- **尚未在真机上跑过**：编译通过不等于硬件验证。首次上电请按
  [docs/FLASHING.md](docs/FLASHING.md) 第 4 节核对启动日志；
  GNSS 定位、IMU/气压计 ID、BLE 连接需要实测。

## 默认参数

| 项 | 默认值 | 位置 |
| --- | --- | --- |
| BLE 名称 | `DriveTrack-GPS` | `config.h` |
| GNSS 频率 | 10 Hz | `config.h` |
| GNSS 波特率 | 启动 38400 → 运行 115200 | `config.h` |
| UART 引脚 | RX=18，TX=17 | `config.h` |
| I2C 引脚 | SDA=8，SCL=9，400 kHz | `config.h` |
| IMU 地址 | 加速度计 0x18，陀螺仪 0x68 | `config.h` |
| 气压计地址 | 0x77 | `config.h` |

**引脚必须与你的 PCB 一致**，接法见 [docs/WIRING.md](docs/WIRING.md)。

## 启动日志

```
[DriveTrack] booting
[GNSS] uart1 rx=18 tx=17 rate=10Hz baud=115200
[IMU] BMI088 ok
[BARO] BMP390 ok
[BLE] advertising as DriveTrack-GPS
[STAT] fix=0 lines=30 sent=30 drop=0 imu=1 ax=0.01 ay=-0.02 az=1.00 baro=1 p=1013.2hPa t=28.4C
```

- `fix=0`：未定位，到室外等 30–60 秒。
- `lines` 每秒增长约 `频率 × 3`（GGA+RMC+GSA）。
- `drop` 持续增长说明 BLE 带宽不够，检查 MTU 或降低频率。

## 与 App 对接

App 侧无需新增插件：

1. 设备中心 → 外接定位 → 扫描，出现 `DriveTrack-GPS`；
2. 连接后自动订阅 NUS 并解析 NMEA；
3. 赛道模式硬件门槛为 ≥5 Hz，默认 10 Hz 可过。

协议细节、带宽计算见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

## 已知限制

- 不支持 OTA，升级需 USB 重烧。
- 不做数据落盘；断连期间的定位不会补发。
- IMU / 气压计仅做自检，尚未参与 App 的 G 值或海拔融合。
- 固件按 WGS-84 原样转发，不做 GCJ-02 纠偏（与 App 的 OSM 赛道一致）。
