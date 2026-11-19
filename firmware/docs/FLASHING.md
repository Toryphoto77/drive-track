# 固件烧录说明（FLASHING）

> 适用于本仓库 `firmware/` 目录。按顺序做，第一次烧录大约 15 分钟
> （主要花在下载工具链上，之后每次 1 分钟内）。

## 0. 你需要先确认的三件事

1. **板子型号**：ESP32-S3（本项目默认 `esp32-s3-devkitc-1`）。
   如果是自定义板，改 `platformio.ini` 里的 `board =`。
2. **USB 口**：用板子的 **USB-C / Micro-USB 数据口**，不是只供电的线。
   劣质线只能充电，电脑不会出现串口。
3. **串口驱动**：看板子上的 USB 转串口芯片。
   - CP2102 / CP2104 → 装 Silicon Labs CP210x 驱动
   - CH340 / CH343 / CH9102 → 装 WCH 驱动
   - 原生 USB（ESP32-S3 自带 USB）→ Win10/11、macOS、Linux 免驱

## 1. 方式 A：VS Code + PlatformIO（推荐）

### 安装

1. 安装 [VS Code](https://code.visualstudio.com/)。
2. 在扩展市场搜索 **PlatformIO IDE** 并安装。
3. 安装完成后左侧会出现 PlatformIO 图标（小蚂蚁）。

### 编译与烧录

1. VS Code → 文件 → 打开文件夹 → 选择本仓库的 **`firmware/`** 目录。
2. 首次打开会自动下载 ESP32 工具链和依赖库（约 1–2 GB，耐心等，
   只需一次；之后编译在 1 分钟内）。
3. 左下角状态栏确认环境是 `esp32s3`。
4. 用 USB 线连接板子，点击底部 **→（Upload）** 按钮。
5. 看到 `SUCCESS` 即烧录完成。
6. 点 **插头图标（Serial Monitor）**，波特率 115200，查看日志。

> 如果上传卡在 `Connecting...`：按住板子 **BOOT** 键，点一下 **RST**，
> 再松开 BOOT，然后重新点 Upload。

## 2. 方式 B：命令行（macOS / Linux / Windows PowerShell）

```bash
cd firmware

# 1) 建虚拟环境（只需一次）
python3 -m venv .venv

# 2) 安装 PlatformIO（只需一次）
.venv/bin/pip install platformio

# 3) 编译
.venv/bin/pio run

# 4) 烧录
.venv/bin/pio run -t upload

# 5) 看日志（Ctrl+C 退出）
.venv/bin/pio device monitor
```

Windows 下把 `.venv/bin/` 换成 `.venv\Scripts\`。

## 3. 方式 C：手动 esptool（没有 PlatformIO 时）

先编译出 bin 文件，再按地址烧录。ESP32-S3 的地址如下：

| 文件 | 烧录地址 |
| --- | --- |
| `bootloader.bin` | `0x0` |
| `partitions.bin` | `0x8000` |
| `boot_app0.bin` | `0xE000` |
| `firmware.bin` | `0x10000` |

文件位置：

```
firmware/.pio/build/esp32s3/bootloader.bin
firmware/.pio/build/esp32s3/partitions.bin
firmware/.pio/build/esp32s3/firmware.bin
~/.platformio/packages/framework-arduinoespressif32/tools/partitions/boot_app0.bin
```

烧录命令：

```bash
esptool.py --chip esp32s3 -p /dev/ttyUSB0 -b 921600 write_flash \
  0x0     bootloader.bin \
  0x8000  partitions.bin \
  0xE000  boot_app0.bin \
  0x10000 firmware.bin
```

- Windows 串口形如 `COM5`，macOS 形如 `/dev/cu.usbserial-0001`。
- 没装 esptool：`pip install esptool`。
- 想整片擦除重来：`esptool.py --chip esp32s3 -p <端口> erase_flash`。

## 3.5 免编译烧录（直接使用已构建固件）

`firmware/release/` 里已经放了编译好的固件，不想装 PlatformIO 时可直接烧：

| 文件 | 用途 | 烧录地址 |
| --- | --- | --- |
| `DriveTrack-GPS-full.bin` | 整包（引导 + 分区 + 应用） | `0x0` |
| `DriveTrack-GPS-app.bin` | 仅应用（后续升级用） | `0x10000` |

整包烧录（推荐，一次搞定）：

```bash
esptool.py --chip esp32s3 -p /dev/ttyUSB0 -b 921600 write_flash \
  0x0 release/DriveTrack-GPS-full.bin
```

Windows 把 `/dev/ttyUSB0` 换成 `COM5` 之类的端口。

> 该整包按 **ESP32-S3 DevKitC-1 / 8 MB Flash** 构建。如果你的是
> 4 MB 或其他自定义板，建议改 `platformio.ini` 后自己编译，避免
> Flash 容量不匹配。

校验值（SHA-256）：

```
afa07fb76eb691650aa77999bb9c1726ec1a7f4f06c120c2a2346584d30ba962  DriveTrack-GPS-full.bin
513fcdf03a6cb1cd2ab89ba37d99a6c8137298db1628c3480fe9b72dd88622d4  DriveTrack-GPS-app.bin
```

## 4. 烧录成功后应该看到什么

串口日志（115200）应类似：

```
[DriveTrack] booting
[GNSS] uart1 rx=18 tx=17 rate=10Hz baud=115200
[IMU] BMI088 ok
[BARO] BMP390 ok
[BLE] advertising as DriveTrack-GPS
[STAT] fix=0 lines=30 sent=30 drop=0 imu=1 ax=0.01 ay=-0.02 az=1.00 baro=1 p=1013.2hPa t=28.4C
```

- `fix=0` 表示还没定位，到窗边/室外等 30–60 秒。
- `fix=1` 后 `lines` 会持续增长，App 里应显示 5–10 Hz。
- 如果 `[IMU] BMI088 failed` 或 `[BARO] BMP390 not found`，先查接线和
  地址（见 `WIRING.md`），不影响 GNSS 定位。

## 5. 和 App 联调

1. 手机装好驰迹 App，打开 **设备中心 → 外接定位**。
2. 点「扫描附近 GPS」。
3. 列表里应出现 **DriveTrack-GPS**（BLE 通道）。
4. 点击连接，App 会自动订阅 NUS 并开始解析 NMEA。
5. 回到赛道模式，硬件门槛要求 ≥5 Hz；默认 10 Hz 应通过。

> 首次使用请允许 App 的蓝牙与定位权限，并打开手机定位开关。

## 6. 常见问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 找不到串口 | 数据线 / 驱动问题 | 换线，装 CP210x 或 CH34x 驱动 |
| `Permission denied`（Linux） | 无串口权限 | `sudo usermod -aG dialout $USER` 后重新登录 |
| 上传报 `Failed to connect` | 没进下载模式 | 按住 BOOT → 点 RST → 松开 BOOT 再上传 |
| 上传成功但没日志 | 看错串口 | 选带 USB 字样的端口；波特率 115200 |
| 日志 `GNSS` 无数据 | TX/RX 接反或波特率不对 | 交叉接线；确认模块是 3.3V 电平 |
| GNSS 完全无输出 | 模块串口不是 38400/115200 | 用 u-center 把 UART1 设为 38400，再烧录本固件 |
| `fix` 一直为 0 | 室内 / 天线问题 | 到室外，检查天线是否接好、是否朝上 |
| App 显示 0 Hz | 未连接 / 未订阅 | 断开重连；确认固件日志 `[BLE] connected` |
| 蓝牙能看到但连不上 | 被其他手机占用 | 关闭其他已连接设备后重试 |
| 反复重启 | 供电不足 | 换独立 3.3V 电源，加大电容 |

## 7. 升级固件

当前版本 **不支持 OTA**，升级一律用 USB 重新烧录（覆盖即可，不需要擦除）。
后续加入 OTA 会另行说明。
