# DriveTrack V6 电源与无线方案

配套 `layout-plan.md`（62×62 板 / 68×68×21 盒）。本文覆盖三件事：
无按键供电、WiFi 抢流量、初版欠压。

## 0. 结论

1. 无按键可行，但 **IP5306 必须换掉**。它有按键逻辑，且轻载 <45mA 约 30s 自动关 boost，和“常驻低功耗待机 + 动作唤醒”直接冲突。
2. 手机没流量不是手机的问题，是固件**开机就无条件开热点**。竞品都用 BLE，不用 AP。
3. 初版“供电电压不足”最常见根因是**单节锂电经 LDO 出 3.3V**，电池掉到 3.5V 以下就塌。必须改 buck-boost。

## 1. 无按键电源架构

### 1.1 状态机

```
OFF ──(USB 插入沿 / 动作中断)──► ON ──(APP start)──► RECORDING
 ▲                                │                      │
 └──(APP 关机 / 5min 无动作)───────┘◄──(APP stop)─────────┘
```

- OFF：只有 V_AON 和充电器活着，整机 <50µA。
- ON：3V3 上电，ESP32 启动，BLE 广播。
- RECORDING：禁止自动关机，只保留低电保护。

### 1.2 电源树

```
USB-C 5V ─ESD─► BQ24074（power-path 充电，500mA）
                  ├─ BAT ─► 103450 电芯
                  └─ SYS（3.0–4.4V，常在线）
BAT ─────────────► SYS
SYS ─► Q1 AO3401 软锁存 ─► VSYS
VSYS ─► TPS63802 buck-boost 3.3V/2A ─► 3V3（ESP32 / BMI088 / BMP390 / RGB）
VSYS ─► TPS7A2033 LDO ─► 3V3_GNSS（NEO-M9N，独立低噪）
SYS  ─► TPS7A0230 常开 3.0V/25nA ─► V_AON
        V_AON ─► LIS2DW12 唤醒加速度计（1.6µA）
        V_AON ─► NEO-M9N V_BCKP（热启动，约 30µA）
LIS2DW12 INT1 ─┐
VBUS 插入沿 ───┼─► 锁存 SET
ESP32 PWR_HOLD ─► 锁存 HOLD
```

关键点：**充电器、V_AON、GNSS 备份都接在锁存之前的 SYS 上**，所以关机也能充电、也能被动作/插 USB 唤醒。

### 1.3 为什么换掉 IP5306

| 问题 | 后果 |
| --- | --- |
| KEY 按键逻辑 | 无按键方案无法可靠开机 |
| 轻载 <45mA 约 30s 自动关 boost | 待机（BLE + GNSS 约 75mA）会被误判关机 |
| 5V boost + TPS563201 两级 | 效率低、瞬态差，是初版欠压的来源之一 |
| 没有真正的电源路径 | 充电时负载与充电互相干扰 |

替代：BQ24074（3×3，无 I2C，power path）+ TPS63802（2.5×2.0，1.3–5.5V 输入，2A）。电池 3.0V 时仍能稳出 3.3V。

### 1.4 唤醒与断电规则

| 事件 | 动作 |
| --- | --- |
| USB 插入（上升沿） | 锁存 SET，开机；同时充电 |
| LIS2DW12 any-motion（30–60mg，2 次） | 锁存 SET，开机 |
| APP `{"cmd":"poweroff"}` | flush 落盘 → 关 RGB → 释放 PWR_HOLD |
| 非 RECORDING 且 5min 无动作 | 同上自动关机 |
| USB 在场 | 禁止自动关机；APP 关机需先拔线 |
| 电量 <3.4V | 保存并关机 |
| RECORDING 中 | 禁止自动关机，只保留低电保护 |

### 1.5 必须处理的边界

1. **USB 在场时关机死循环**：VBUS 若是电平唤醒，关机后立刻又被拉起来。用 RC 微分做“插入沿”唤醒，或固件在 USB 在场时拒绝关机并提示拔线。推荐后者，简单可靠。
2. **SET 到 HOLD 的窗口**：SET 后 300ms 内 MCU 必须拉高 PWR_HOLD，否则掉电。锁存 SET 路径加 100k + 1µF（约 100ms）延展。
3. **关机前必须 flush**：先停记录、写盘、关 BLE，再释放 HOLD。
4. **误唤醒**：运输震动会唤醒并待机 5min 再关，可接受；阈值别设太低。

## 2. 电源预算（3.3V 轨）

| 负载 | 平均 | 峰值 |
| --- | --- | --- |
| ESP32-S3（BLE） | 45mA | 350mA（WiFi TX） |
| NEO-M9N | 30mA | 45mA |
| BMI088 | 5mA | 6mA |
| BMP390 | 0.5mA | 0.7mA |
| RGB（低亮） | 5mA | 40mA |
| **3V3 合计** | **≈80mA** | **≈440mA** |
| V_AON（待机） | 32µA | — |

2000mAh / 80mA ≈ 25h，按 20h 报。关机待机 2000mAh / 45µA ≈ 5 年（含 GNSS 备份）。

### 2.1 初版欠压的排查表

| 可能原因 | 现象 | 修正 |
| --- | --- | --- |
| 单节锂电直进 3.3V LDO | 电池 <3.5V 时 3V3 跟着塌 | 改 TPS63802 buck-boost |
| IP5306 轻载自动关 boost | 待机随机断电 | 换 BQ24074 + TPS63802 |
| ESP32 旁路电容不足 | WiFi 一发射就重启 | 2×22µF + 100nF，贴近 3V3 引脚 |
| VBUS/BAT/3V3 走线太细 | 大电流时压降 200mV+ | 主干 0.5–1.0mm，多打过孔 |
| GNSS 与数字共用电源 | 定位漂、灵敏度差 | 独立 TPS7A2033 + 磁珠 |
| BMI088 VDDIO 与 IO 电平不一致 | SPI 读写出错 | VDD/VDDIO 都 3.3V |
| USB 5V 经 LDO 出 3.3V | 发热、掉压 | 充电走 BQ24074，3.3V 走 buck-boost |

### 2.2 布局要求

- 3V3 主干 0.5–1.0mm，BAT/VBUS 同样加粗，回流地完整。
- TPS63802 的 SW 节点面积最小，电感贴近，远离 GNSS/IMU。
- GNSS LDO 输入加磁珠，输出 10µF + 100nF，单独铺地。
- 充电器与电芯之间留热间隙，别把 BQ24074 贴在电芯投影正中。
- V_AON 走线细、短，只喂 LIS2DW12 和 V_BCKP。

## 3. WiFi 抢流量：根因与方案

### 3.1 根因

`main.c` 开机第 56 行无条件调用 `dt_ota_start()`；`dt_ota.c` 里它直接 `WIFI_MODE_AP` + HTTP 服务。手机连上一个没有internet的热点，Android 就把默认路由切过去，蜂窝数据自然断。**不是热点“占用”了 WiFi，是设备常态在当 AP。**

### 3.2 竞品做法

- Dragy：BLE 连接 App，实时推数据，没有 AP；固件升级也走 App。
- RaceBox Mini：BLE 5.2，20m 范围，同样不做常驻 AP。
- 结论：实时数据走 BLE，WiFi 只在升级时短暂出现，是行业通行做法。

### 3.3 我们的方案（三步）

1. **常态只开 BLE**：实时遥测走现有 NUS 通道，10Hz 约 300B/s，BLE 5 轻松。
2. **AP 按需**：删除开机 `dt_ota_start()`；新增 `dt_ota_request_start()`，由 BLE 命令触发，120s 无连接自动关。升级完立即 `esp_wifi_stop()`。
3. **可选 BLE OTA**：1.5MB 固件在 BLE 5 2M PHY 下约 20–40s，可彻底不用 AP。

### 3.4 Android 兜底

如果仍要保留 AP：App 侧用 `ConnectivityManager.requestNetwork(TRANSPORT_CELLULAR)` + `bindProcessToNetwork()`，把 App 自己的 HTTP 绑到蜂窝。但这只救自己，别的 App 仍断网，所以只能当兜底，不能当方案。

### 3.5 固件改动清单

| 文件 | 改动 |
| --- | --- |
| main.c | 删除开机 `dt_ota_start()` |
| dt_ota.c | 拆出 `dt_ota_request_start()` / `dt_ota_stop()`；空闲 120s 关 AP |
| dt_ble.c | 增加 OTA 控制特征（start/stop/status） |
| dt_power.c | 增加 PWR_HOLD、LIS2DW12 动作检测、5min 空闲关机、低电关机 |
| dt_config.h | 新增唤醒/关机相关引脚与阈值 |
| 共存 | AP 开启时暂停 BLE 广播，避免 WiFi/BLE 互抢 |

## 4. BOM 变更（相对 V6 初稿）

| 原 | 新 | 说明 |
| --- | --- | --- |
| IP5306 | BQ24074 | power-path 充电，500mA，无 I2C |
| TPS563201 | TPS63802 | 3.3V/2A buck-boost，覆盖 3.0–4.4V |
| L1 4×4 + L2 1210 | L1 1µH 4×4 | 只保留 buck-boost 电感 |
| — | TPS7A2033 | GNSS 独立低噪 LDO |
| — | TPS7A0230 | 常开 3.0V/25nA，喂唤醒与 V_BCKP |
| — | LIS2DW12 | 2×2，1.6µA 动作唤醒 |
| — | AO3401 + 2×2N7002 | 软锁存 |
| 5 LED | 1 SK6812MINI | 已定 |

净增面积约 10mm²，仍落在 X25–56 / Y42–57 的电源区内。

## 5. 下一步

1. 按本文件更新原理图：电源树、软锁存、唤醒、V_BCKP。
2. 固件先做“AP 按需”最小改动，立刻解决手机流量问题；BLE OTA 二期。
3. 打样前做上电时序与欠压复测：电池 3.0V / 3.3V / 4.2V 三档，WiFi TX 峰值抓 3V3 纹波。
