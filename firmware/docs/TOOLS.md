# 工具清单（TOOLS）

> 分「硬件工具」「软件工具」两部分。打勾的是必备，其余按需。

## 1. 硬件工具

### 必备

- [ ] **ESP32-S3 开发板**（默认 `ESP32-S3-DevKitC-1`，8 MB Flash 及以上）
- [ ] **USB-C 数据线**（必须能传数据；只充电的线一定失败）
- [ ] **NEO-M9N GNSS 模块**（UART 输出 NMEA）
- [ ] **有源 GNSS 天线**（u.FL 或 SMA，按模块接口选）
- [ ] **BMI088 模块**（I2C 模式）
- [ ] **BMP390 模块**（I2C 模式）
- [ ] **杜邦线**若干（母-母、公-母按板子针脚选）
- [ ] **3.3V 电源模块**：≥800 mA（MP1584 / AMS1117-3.3 / 独立 LDO）
- [ ] **万用表**（上电前测短路、量电压）
- [ ] **电烙铁 + 焊锡 + 助焊剂**（模块要焊排针时用）
- [ ] **100 nF、10 µF 电容**各若干（芯片电源去耦）
- [ ] **4.7 kΩ 电阻** 2 个（I2C 上拉，若模块自带可省）

### 可选但强烈建议

- [ ] 逻辑分析仪（8 通道，24 MHz 以上）——排查 I2C / UART 波形
- [ ] USB-TTL 串口模块（CH340）——不依赖开发板调试 GNSS
- [ ] 热风枪 / 吸锡带——返修焊点
- [ ] 热缩管 / 3M 双面胶 / 扎带——车顶固定
- [ ] 防水外壳（带透气孔，气压计需要）
- [ ] 保险丝 + TVS 二极管——车载电源防护

## 2. 软件工具

### 必装

| 工具 | 用途 | 下载地址 |
| --- | --- | --- |
| VS Code | 编辑器 | https://code.visualstudio.com/ |
| PlatformIO IDE 扩展 | 编译 / 烧录 / 串口监视 | https://platformio.org/install/ide?install=vscode |
| CP210x 驱动 | 板载 CP2102 串口芯片 | https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers |
| CH34x / CH343 驱动 | 板载 WCH 串口芯片（二选一） | https://www.wch.cn/downloads/CH343SER_EXE.html |

### 可选

| 工具 | 用途 | 下载地址 |
| --- | --- | --- |
| u-center | u-blox 官方 GNSS 调试（看卫星、改配置） | https://www.u-blox.com/en/product/u-center |
| esptool | 命令行烧录 / 擦除 | https://github.com/espressif/esptool |
| nRF Connect | 手机端 BLE 调试，验证 NUS 通知 | 应用商店 |
| 串口调试助手 | 看原始 NMEA 文本 | 任意（CoolTerm / SSCOM） |

### 版本记录（本次验证使用）

- PlatformIO Core：6.1.18
- Espressif32 平台：6.9.0
- NimBLE-Arduino：2.1.x
- Adafruit BMP3XX Library：2.1.x
- Adafruit Unified Sensor：1.1.14

> 版本号写在 `firmware/platformio.ini` 里，`pio run` 会自动下载对应版本，
> 不需要手工装库。

## 3. 硬件采购关键词（中文）

- `NEO-M9N 模块`（注意要 **M9N**，不是 M8N）
- `BMI088 六轴 模块`
- `BMP390 气压计 模块`
- `ESP32-S3-DevKitC-1`
- `MP1584 降压模块`
- `有源 GPS 天线 u.FL`

## 4. 车顶安装建议

- 模块 + 天线固定在**车顶中央**，远离金属遮挡和行车记录仪。
- 天线下方要有地平面（车顶本身可以），不要贴在碳纤维或玻璃上。
- 电源线加磁环，避免点火干扰。
- 外壳留透气孔给气压计，但要做防水透气膜。
- 整机工作温度范围按 -10℃ ~ 60℃ 选件。
