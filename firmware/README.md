# DriveTrack 自研硬件固件（V4.6 / ESP32-S3）

配合 App 的「设备中心 → 自研设备固件升级」使用：设备开热点，手机连上后 App
检测版本、下载固件并通过 WiFi 写入设备备用分区，全程不拆机、不插线。

- 主控：ESP32-S3-WROOM-1U-N16R8（16 MB Flash + 8 MB 八线 PSRAM）
- 框架：ESP-IDF v5.1 ~ v5.4
- 依赖：全部为 IDF 内置组件（NimBLE、esp_http_server、spiffs、mbedtls、cJSON、
  esp_adc），不需要联网拉第三方组件

## 1. 硬件与引脚（V4.6 实测网表）

以下全部取自 `drivetrack-pcb-v4.6.kicad_pcb` 的 U1 焊盘网络，已与
`ASSEMBLY-v4.6.txt` 交叉核对。改硬件时只改
[main/include/dt_config.h](main/include/dt_config.h) 一个文件。

| 功能 | 器件 | 信号 | ESP32-S3 |
| --- | --- | --- | --- |
| GNSS | u-blox NEO-M9N | 模块 TXD1 → ESP RX（IO17）、ESP TX（IO18） → 模块 RXD1 | UART1 |
| GNSS | NEO-M9N | PPS | IO4（当前不用） |
| IMU | Bosch BMI088 | SCK / MOSI / MISO | IO14 / IO15 / IO16（SPI2） |
| IMU | BMI088 | CS 加速度计 / CS 陀螺仪 | IO10 / IO11 |
| IMU | BMI088 | INT1 / INT3 | IO5 / IO6（当前轮询，不用中断） |
| 气压计 | BMP388/390 | SDA / SCL，地址 0x77 | IO8 / IO9（当前未读） |
| microSD | — | CS / CD / SCK / MOSI / MISO | IO12 / 13 / 38 / 39 / 40（当前未挂） |
| 电源 | IP5306 + TPS563201 | VBAT 分压 1/2 → ADC1_CH0 | IO1 |
| 指示灯 | 5 mm 状态灯 | IO7 高 → R25 → Q2 | IO7 |
| 指示灯 | 第 4 颗电量灯 | IO2 高电平点亮 | IO2 |
| USB | 原生 USB-Serial-JTAG | D- / D+ | IO19 / IO20 |
| 启动 | BOOT 键 | — | IO0 |

注意：

- IO33~IO37 被八线 PSRAM 占用，板上留空，不要复用。
- **V4.6 没有 CAN 收发器**，OBD/CAN 功能在这版硬件上不可实现，
  `DT_ENABLE_CAN` 固定为 0，`dt_can.c` 只保留空实现；换板后置 1 并填
  `DT_CAN_TX_GPIO` / `DT_CAN_RX_GPIO` 即可。
- Φ12 自锁按钮串在电池正极，是硬开关，固件不读。
- 前三颗电量灯由 IP5306 自己驱动，固件只控制第 4 颗（低电提示）。

## 2. 编译

安装 ESP-IDF v5.1+（或乐鑫官方 VS Code 插件），然后：

```bash
cd firmware
idf.py set-target esp32s3
idf.py build
```

产物：`build/drivetrack-box.bin`（含 bootloader 与分区表）。

## 3. 首次烧录（必须用串口，仅此一次）

板上有原生 USB-Serial-JTAG，插 USB-C 后一般直接出现串口，不需要 USB-TTL：

```bash
idf.py -p COM3 flash monitor
```

或纯 esptool（注意 16 MB Flash、DIO 40 MHz）：

```bash
esptool.py -p COM3 -b 460800 --before default_reset --after hard_reset \
  write_flash --flash_mode dio --flash_freq 40m --flash_size 16MB \
  0x0     build/bootloader/bootloader.bin \
  0x8000  build/partition_table/partition-table.bin \
  0x20000 build/drivetrack-box.bin
```

烧完设备会开热点 `DriveTrack-XXXX`（密码 `drivetrack123`），
浏览器访问 `http://192.168.4.1/api/info` 应能看到型号、板卡、电量与版本。
之后所有升级都走 App，不用再连线。

> ESP32-S3 的 bootloader 偏移是 `0x0`（经典 ESP32 才是 `0x1000`），别照抄旧文档。

## 4. WiFi 升级链路

| 接口 | 说明 |
| --- | --- |
| `GET /api/info` | `{"model":"DT-BOX-1","board":"DriveTrack V4.6","fw":"0.2.0","build":2,"battMv":4020,"freeHeap":..,"uptimeMs":..}` |
| `POST /api/ota` | 请求体为固件 `.bin`，头 `X-Firmware-Sha256` 为 64 位十六进制摘要 |

设备收到固件后：写入当前未运行的 OTA 分区 → 校验 SHA-256 → 切换启动分区 →
重启 → 新固件跑满 10 秒未崩溃才取消回滚标记。任何一步失败都停在旧固件上，不会变砖。

分区表见 [partitions.csv](partitions.csv)：双 OTA 各 4 MB，剩余 8 MB 做断线缓存。

## 5. 发布一个新版本

1. 改 `DT_FW_VERSION` 和 `DT_FW_BUILD`（必须比清单里的旧版本大，App 按 build 比较）。
2. `idf.py build`，把 `build/drivetrack-box.bin` 复制成
   `firmware/bin/drivetrack-box-<版本>.bin`。
3. 取文件大小与 SHA-256：

   ```powershell
   $f = "firmware/bin/drivetrack-box-0.2.1.bin"
   "{0} {1}" -f (Get-Item $f).Length, (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
   ```

4. 在 `firmware/manifest.json` 的 `releases` 里加一条（url 用 jsDelivr 或
   GitHub raw 全路径，sha256 用上一步的结果）：

   ```json
   {
     "channel": "stable",
     "updatedAt": "2026-11-16T12:00:00Z",
     "releases": [
       {
         "version": "0.2.1",
         "build": 3,
         "model": "DT-BOX-1",
         "url": "https://cdn.jsdelivr.net/gh/Toryphoto77/drive-track@main/firmware/bin/drivetrack-box-0.2.1.bin",
         "sha256": "<上一步算出的 64 位摘要>",
         "size": 1234567,
         "notes": "修正 GNSS 波特率探测"
       }
     ]
   }
   ```

5. 提交推送后必须刷新 CDN 缓存，否则 App 12 小时内都看不到新清单：

   ```powershell
   Invoke-WebRequest "https://purge.jsdelivr.net/gh/Toryphoto77/drive-track@main/firmware/manifest.json" | Out-Null
   Invoke-WebRequest "https://purge.jsdelivr.net/gh/Toryphoto77/drive-track@main/firmware/bin/drivetrack-box-0.2.1.bin" | Out-Null
   ```

## 6. BLE 数据通道（App 实时读取）

服务与特征沿用 Nordic UART Service（App 现有常量即此标准 UUID 的前 31 位）：

- 服务 `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- RX（手机写）`6e400002-…`
- TX（设备通知）`6e400003-…`

设备按采样率推送 NDJSON（一行一条 JSON）：

```json
{"t":"gps","fix":1,"sats":9,"lat":30.1234567,"lon":120.1234567,"alt":8.1,"spd":45.20,"cog":128.4,"hdop":0.9}
{"t":"imu","ax":0.02,"ay":-0.01,"az":0.99,"gx":1.2,"gy":-0.4,"gz":12.3,"roll":0.8,"pitch":-0.3,"latg":0.42}
{"t":"sess","ev":"start","id":1,"ts":123456}
{"t":"sum","id":1,"dur":92,"dist":812.4,"vmax":63.2,"vavg":31.8,"latg":1.12,"longg":-0.86,"n":912}
{"t":"dev","model":"DT-BOX-1","board":"DriveTrack V4.6","fw":"0.2.0","build":2,"rec":0,"up":35,"heap":142336,"batt":4020,"cache":0}
```

App 下发指令（同样是一行 JSON）：

| 指令 | 作用 |
| --- | --- |
| `{"cmd":"start"}` | 开始记录（同时开始落盘） |
| `{"cmd":"stop"}` | 结束记录并回传本段汇总 |
| `{"cmd":"status"}` | 立即回一条 `t=dev` 状态 |
| `{"cmd":"sync"}` | 主动补传一段本地缓存 |
| `{"cmd":"clear-cache"}` | App 确认收全后清空缓存与游标 |

掉线期间数据写在 SPIFFS（`storage` 分区，约 8 MB），重连后按 NVS 里的游标续传，
默认每秒补 1 KB，足够追上 10 Hz 采样。

## 7. 参数与实现说明

- **GNSS**：启动时依次探测 38400 / 115200 / 9600，命中后发 UBX `CFG-MSG`
  关掉 GSA/GSV、`CFG-RATE` 设 100 ms（10 Hz）。**不改模块波特率**，避免把
  未知批次配坏；探测失败则按 9600 继续跑，日志里能看到原始帧便于排查。
- **IMU**：BMI088 固定 ±6 g（5460 LSB/g）/ ±2000 dps（16.384 LSB/dps）、
  200 Hz 输出、20 Hz 上报。加速度计上电默认 I2C，首次片选动作会自动切 SPI。
  启动时若静止会标定陀螺零偏（抖动 > 5 dps 则跳过），互补滤波输出 roll/pitch。
- **气压计与 SD 卡**：V4.6 已布线但当前固件不驱动，缓存走片内 Flash。
- **OBD/CAN**：V4.6 无收发器，功能关闭。
- **走线分析**：固件负责 10 Hz 定位 + 20 Hz 姿态与 G 值 + 结束汇总；
  轨迹与理想线对比、分段时间、弯心速度曲线在 App 侧计算。
- **本地缓存**：只在 BLE 发不出去（手机断开）时落盘，8 MB 分区在 4 KB/s 下
  可覆盖约 30 分钟断线，重连后自动续传。

## 8. 首板验证清单

按顺序做，任何一步失败都只影响对应模块：

1. 上电后串口应打印 `DriveTrack V4.6 fw=0.2.0 build=2`。
2. 状态灯 IO7 每 2 秒短闪一次；低电时第 4 颗灯（IO2）常亮。
3. 手机能搜到 `DriveTrack-XXXX`，连上后 `http://192.168.4.1/api/info` 返回 JSON，
   `battMv` 与万用表测的电池电压相差应在 ±100 mV 内。
4. 串口日志出现 `GNSS 波特率探测命中 xxxx bps`，随后 `t=gps` 行里 `sats > 0`、
   `fix` 最终变 1。
5. 串口日志出现 `BMI088 已启动 20 Hz`，`t=imu` 行静止时 `az≈1.0`、`gz≈0`。
6. App 连 BLE，下发 `{"cmd":"start"}` 收到 `sess/ack`，状态灯转为双闪；
   `{"cmd":"stop"}` 收到 `sum` 汇总。
7. App 打开固件升级页，能看到当前 `0.2.0 / build 2`；发一个新版本后能升级并自重启。

> 本仓库没有 ESP-IDF 构建环境，固件未在本地编译验证。`idf.py build` 若报错，
> 优先检查目标芯片是否为 `esp32s3`、`dt_config.h` 引脚是否与板上一致。
