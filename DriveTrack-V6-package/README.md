# DriveTrack V6 交付包

PCB V6（KiCad 9）+ 外壳 v10（CadQuery / STL / STEP）+ 布局与电源文档。
打包日期：2026-11-23

---

## 一、先读这段：PCB V6 当前是什么

**V6 是"机械与布局参考板"，不是可投产板。** 请按下列边界使用：

| 可信 | 不可信 |
| --- | --- |
| 62 × 62 板框、R2 圆角、4 × M2 孔位 | 布线（无任何走线 / 过孔 / 铜区） |
| 23 个器件的坐标、朝向、占位尺寸 | DRC / ERC（未跑，沙箱无 kicad-cli） |
| 分区禁布（天线区 / 传感器区 / 电源热区 / 电池投影） | 电气连接（原理图仍是 V5 的 IP5306 方案） |
| 与外壳 v10 的装配关系（螺钉柱、USB 开口、灯窗、通气孔、电池出线缺口） | 新电源件的焊盘（U5/U6/U7/U8/U9/L1/Q2/J3 为无焊盘机械占位） |

具体说明：

- 器件 U5 BQ24074、U6 TPS63802、U7 TPS7A2033、U8 TPS7A0230、U9 LIS2DW12、
  L1、Q2、J3 在板上只有外形占位，**没有焊盘、没有网络**。
- 保留下来的 V5 器件沿用旧网络名（例如 Q3 的 `KEY_GATE`、`KEY`），仅作占位，
  不代表 V6 的最终连接。重画原理图时会整体替换。
- 因此本包的价值是：**确认几何、确认堆叠、确认外壳孔位、作为下一轮布线的起点**，
  而不是直接发给板厂。

---

## 二、目录

```
DriveTrack-V6-package/
├── README.md                     ← 本文件
├── pcb-v6/                       KiCad 9 工程
│   ├── drivetrack-pcb-v6.kicad_pcb
│   ├── drivetrack-pcb-v6.kicad_pro
│   ├── fp-lib-table
│   ├── DriveTrack.pretty/        自定义封装（天线 / BMI088 / BMP390 / 安装孔）
│   └── previews/placement-v6.png 布局图（PNG + SVG）
├── enclosure-v10/                外壳 v10
│   ├── base-v10.stl / .step      底座（打印件）
│   ├── lid-v10.stl / .step       盖板（打印件）
│   ├── lens-v10.stl / .step      灯窗导光柱（打印件）
│   ├── assembled-v10-DO-NOT-PRINT.stl/.step   仅装配检查，勿打印
│   ├── enclosure_v10.py          参数化脚本（自带尺寸与探针校验）
│   ├── notes-v10.md              打印参数、五金、装配顺序、密封注意
│   └── previews/                 渲染预览
├── docs/
│   ├── layout-plan.md            布局方案（分区、规则、BOM 变更、风险）
│   ├── placement.csv             器件坐标表（23 项 + 1 可选 DNP）
│   ├── keepouts.csv              禁布 / 禁铺铜区域
│   └── power-and-wireless.md     电源树、无按键状态机、BLE-OTA 方案、固件改动清单
└── tools/
    └── build_v6_pcb.py           由 V5 板生成 V6 的脚本（可复现）
```

---

## 三、尺寸结论

| 项目 | 数值 |
| --- | --- |
| PCB | 62 × 62 × 1.6 mm，四层（Sig / GND / PWR / Sig），R2 圆角 |
| 外壳 | 68.6 × 68.6 × 21.0 mm，壁厚 2.8，平面圆角 R6 |
| 体积 | 约 99 cm³ |
| 对比 V5 优化版（147 cm³） | −33% |
| 对比 v9（117 cm³） | −15% |
| 对比 Dragy（36 cm³） | 仍大约 2.7 倍，主因是 25×25 陶瓷天线 + 2000mAh 电芯 |

Z 向堆叠：底壳 2.0 → 泡棉 0.8 → 电芯 10.0 → 绝缘 0.3 → PCB 1.6 → 顶部件 3.3 → 盖板 1.8 + 间隙。
详见 [docs/layout-plan.md](docs/layout-plan.md) 与 [enclosure-v10/notes-v10.md](enclosure-v10/notes-v10.md)。

---

## 四、PCB V6 布局摘要

23 个器件（`docs/placement.csv`）：

| 区域 | 器件 | 要点 |
| --- | --- | --- |
| GNSS 天线 | ANT1 25×25（13.5,13） | 正下方完整地，禁走线/过孔/螺钉，板边 ≥2 mm |
| GNSS 模块 | U2 NEO-M9N（13.5,34，−90°） | 馈线 <10 mm，50Ω CPWG，直连不去 R8 |
| 传感器 | U3 BMI088（7.5,50）、U4 BMP390（3.5,45） | 左侧无电池区；BMP 贴西壁通气孔，距电源 ≥8 mm |
| 主控 / RF | U1 ESP32-S3-MINI-1U（45,14.5）、LED1（56,8） | IPEX 朝上边，距 patch ≥10 mm；单颗 RGB |
| 接口 | J2 USB-C（31,58）、D1–D3 ESD（26.5/29/31.5, 52） | ESD 距连接器 ≤3 mm |
| 电源热区 | U5 BQ24074、U6 TPS63802、U7 TPS7A2033、U8 TPS7A0230、U9 LIS2DW12、L1、Q1–Q3 | 集中右下，热回路小；L1 离 BMP ≥8 mm |
| 电池 | J3 JST-SH（57.5,55，180°） | 开口朝南，板边 2×4.3 缺口出线 |
| 机械 | MH1–MH4 Ø2.2 NPTH | (30,3)(54,3)(30,59)(54,59)，全部在电芯投影外 |

电池 103450 只占板下右侧 X 26–60 / Y 6–56；左侧 X 0–26 全高无电池，给传感器和天线让位。

---

## 五、电源与"无按键"

完整推演见 [docs/power-and-wireless.md](docs/power-and-wireless.md)，要点：

- 充电 / 电源路径：**BQ24074** → **TPS63802**（3.3V buck-boost，覆盖 3.0–4.4V）→
  GNSS 再经 **TPS7A2033** 低噪声 LDO。
- 常开域：**TPS7A0230**（3.0V / 25nA）供 **LIS2DW12**（1.6µA 动作检测）与 NEO `V_BCKP`。
- 软锁存：AO3401 + 2 × 2N7002，SET 来自 USB 插入沿或动作中断，HOLD 由 ESP32 上电后
  300 ms 内拉高，APP 指令或 5 分钟无动作释放；关机待机约 45µA。
- USB 在场时禁止 APP 关机，避免边充边关。
- 取消 IP5306 的原因：其 KEY 逻辑与轻载 30 s 自动关 boost 与无按键方案冲突。

## 六、WiFi 占用流量问题（已改固件）

根因：`main.c` 开机无条件 `dt_ota_start()`，设备常态开 AP。

已改为：常态 BLE，App 收到状态后再按需开热点。

| 文件 | 改动 |
| --- | --- |
| `firmware/main/main.c` | 删除开机 `dt_ota_start()`；BLE 名改用 `ESP_MAC_WIFI_SOFTAP` |
| `firmware/main/dt_ota.c` | 拆出 `dt_ota_start/stop/active/ssid`，netif/WiFi 只初始化一次，120 s 空闲自动关 |
| `firmware/main/dt_session.c` | 新增 `ota-start` / `ota-stop` 指令，回 `{"t":"ota","on":1,...}`；status 加 `ota` 字段；OTA 期间暂停 BLE 遥测 |
| `firmware/main/include/dt_config.h` | 版本 0.2.1 / build 3 |

App 侧还需改：先发 `ota-start`，收到 `on=1` 后再连设备热点上传（当前是先连 WiFi）。
**固件未经编译验证**（沙箱无 ESP-IDF），请本地 `idf.py build` 后实机复测。

---

## 七、外壳 v10 打印

| 件 | 材料 | 朝向 |
| --- | --- | --- |
| `base-v10.stl` | ASA / ABS | 开口朝上，原样 |
| `lid-v10.stl` | ASA / ABS | **翻面**，顶面贴床 |
| `lens-v10.stl` | 透明 PETG | 法兰贴床，100% 填充 |

0.2 mm 层高 / 4 圈 / 40% gyroid；盖板翻面后密封舌朝上，FPC 槽与 GPS 减薄区不悬空。
五金、装配顺序、密封注意见 [enclosure-v10/notes-v10.md](enclosure-v10/notes-v10.md)。

**未定项**：USB 开口按 mid-mount 建模。若实际用 top-mount 座，开口需下移约 1.6 mm，
首件打印请先量实物座子。

---

## 八、复现

```bash
# 外壳（需 cadquery 2.8 / Python 3.12）
cd enclosure-v10 && python enclosure_v10.py

# PCB（需先有 V5 原始板作模板）
python tools/build_v6_pcb.py
```

`build_v6_pcb.py` 顶部写死了 V5 源路径
（`/workspace/drivetrack-v5-optimized/DriveTrack-PCB-V5/drivetrack-pcb-v5.kicad_pcb`）
和 V6 输出路径，换机器时改这两行即可。脚本会重建板框、保留 14 个器件、
新增 9 个占位、删除 V5 的 microSD / 测试点 / 旧电源件，并清空全部走线与铜区。

---

## 九、投产前还必须做的（按顺序）

1. **重画原理图**：用 BQ24074 + TPS63802 + TPS7A2033/0230 + 软锁存替换 IP5306 段。
2. **换真实封装**：ESP32-S3-MINI-1U、BQ24074 DRZ、TPS63802、JST-SH SM02B、
   USB-C（先定 mid / top-mount）。当前 U5–U9/L1/Q2/J3 只是方块占位。
3. **布线 + DRC/ERC**：GNSS 馈线优先，电源主干 0.5–1.0 mm，USB 差分等长 <5 mm。
4. **分区落铜**：按 `docs/keepouts.csv` 画禁铺铜，天线区与传感器区下方完整地。
5. **首件打样**：先只贴电源链 + ESP32，实测充电、待机 45µA、唤醒与关机。
6. **结构首件**：打印 v10 底座 + 盖板，实测 USB 座高度、电池出线、密封圈压缩量。
7. **App 侧 OTA 流程改造**（见第六节）。
