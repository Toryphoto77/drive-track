# 接线说明（WIRING）

> 本文按 **ESP32-S3-DevKitC-1 + NEO-M9N + BMI088 + BMP390** 给出默认接法。
> 引脚定义都在 [`include/config.h`](../include/config.h)，**以你手上的 PCB 为准**；
> 如果板子已经打样，请对照原理图改 `config.h` 后重新编译。

## 1. 引脚总表（默认值）

| 信号 | ESP32-S3 引脚 | 对端 | 说明 |
| --- | --- | --- | --- |
| GNSS TXD → ESP RX | GPIO18 | NEO-M9N **TXD** | 交叉连接 |
| GNSS RXD ← ESP TX | GPIO17 | NEO-M9N **RXD** | 交叉连接 |
| I2C SDA | GPIO8 | BMI088 SDA / BMP390 SDA | 共用一条 I2C |
| I2C SCL | GPIO9 | BMI088 SCL / BMP390 SCL | 400 kHz |
| 3V3 | 3V3 | 各模块 VCC / VDDIO | 必须 3.3V |
| GND | GND | 各模块 GND | 必须共地 |

## 2. 供电

- ESP32-S3 峰值电流可达 500 mA（BLE 广播 + 射频），**不要用开发板 3V3 针脚
  给三个模块同时供电**。建议独立 3.3V / ≥800 mA 降压模块（MP1584、AMS1117-3.3
  加散热片均可）。
- 每个芯片电源脚旁放 **100 nF + 10 µF** 去耦电容。
- NEO-M9N 模块若带 5V 输入稳压，可以接 5V；但 **UART 电平必须是 3.3V**，
  接 5V TTL 会损坏 ESP32。
- 有源天线需要模块提供 3.3V 偏置（多数 breakout 已内置），确认天线电流
  不超过模块规格。

## 3. NEO-M9N（GNSS）

- UART1，8N1。出厂 38400，固件启动后自动切到 **115200** 并写入模块配置。
- 天线：u.FL / SMA 有源天线，尽量远离 ESP32 的 2.4G 天线，天线面朝上，
  下方留地平面。室内基本收不到星，测试请到窗边或室外。
- 只接 TX/RX/GND/VCC 四根线即可；TIMEPULSE 可不接。

## 4. BMI088（IMU，I2C 模式）

BMI088 进 I2C 模式有硬性条件，接错会读不到 ID：

| 引脚 | 接法 | 原因 |
| --- | --- | --- |
| CSB1（加速度计片选） | 接 **VDDIO（3.3V）** | 拉高才进入 I2C |
| CSB2（陀螺仪片选） | 接 **VDDIO（3.3V）** | 拉高才进入 I2C |
| SAO（加速度计地址） | 接 **GND** | 地址 0x18 |
| SDO（陀螺仪地址） | 接 **GND** | 地址 0x68 |
| VDD / VDDIO | 3.3V | VDDIO 决定 IO 电平 |

- 陀螺仪和加速度计是**两个独立 I2C 地址**，固件分别初始化。
- I2C 上拉：4.7 kΩ 到 3.3V。若 BMI088/BMP390 的 breakout 板已带上拉，
  不要再并一组，否则总线电容过大、400 kHz 下波形变差。

## 5. BMP390（气压计，I2C 模式）

| 引脚 | 接法 | 结果 |
| --- | --- | --- |
| CSB | 接 VDDIO | 选择 I2C |
| SDO | 接 VDDIO | 地址 **0x77** |
| SDO | 接 GND | 地址 0x76（需改 `BMP390_ADDR`） |

- 气压计对气流敏感：外壳要留透气孔，但避免风扇直吹和阳光直射，
  否则高度会跳。

## 6. 上电前检查清单

1. 万用表测 3.3V 与 GND **没有短路**。
2. GNSS 的 TX 接 ESP 的 RX，不要接反。
3. BMI088 的 CSB1、CSB2 都已拉高（这是最容易漏的一步）。
4. 所有模块共地。
5. 先只插 USB 不接电池，确认串口能打印启动日志，再逐步接模块。

## 7. 改引脚

例如你的板子把 GNSS 接在 GPIO4/5、I2C 接在 GPIO1/2：

```c
#define PIN_GNSS_RX 4
#define PIN_GNSS_TX 5
#define PIN_I2C_SDA 1
#define PIN_I2C_SCL 2
```

改完重新执行 `pio run -t upload`。注意 ESP32-S3 的 GPIO19/20 是原生 USB，
GPIO0 是 BOOT，GPIO45/46 是启动 strapping 脚，尽量避开。
