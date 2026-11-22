# DriveTrack V6 交付包

PCB V6 rev 6.1（KiCad 9：原理图 + 真实封装 PCB）+ 外壳 v10（CadQuery / STL / STEP）+ 网表 / BOM / 布局文档。
打包日期：2026-11-23

---

## 一、先读这段：现在到哪一步了

**原理图已重画、PCB 已换真实封装并赋网络；PCB 仍未布线、未铺铜、未跑 DRC/ERC。**

| 已完成 | 尚未完成 |
| --- | --- |
| 原理图 rev 6.1：BQ24074 + TPS63802 + TPS7A2033/0230 + 软锁存 + LIS2DW12 | PCB 布线（0 走线 / 0 过孔 / 0 铜区） |
| 75 个器件的引脚级网表（50 个网络，311 个设计引脚） | DRC / ERC（沙箱无 kicad-cli，只做了结构自检） |
| PCB 上 75 个真实封装、311 个引脚全部有焊盘并赋网络 | 去耦电容按引脚就近重摆（当前为自动聚类参考） |
| 62 × 62 板框、4 × M2 孔位、分区禁布 | 阻抗 / 等长 / 电源载流复核 |
| 与外壳 v10 的装配关系（含螺钉柱、USB 开口、灯窗、通气孔） | 首件打样与实测 |

原理图自检结果：

- 71 个符号实例（4 个安装孔无引脚），274 个引脚全部带全局标签，37 个 NC 脚都有 no-connect。
- 标签数量与 `nets-v6.csv` 每个网络的节点数逐一吻合；每个引脚端点的标签名与其设计网络一致。
- 无 KiCad CLI，未做 ERC。

PCB 自检结果：

- 75 个 footprint，位号唯一；括号平衡；板内无 courtyard 重叠（USB-C 按设计伸出南边 1.9 mm）。
- 每个设计引脚的焊盘编号都存在，且焊盘网络与网表一致；没有多余的有网络焊盘。

---

## 二、目录

```
DriveTrack-V6-package/
├── README.md                     ← 本文件
├── pcb-v6/                       KiCad 9 工程
│   ├── drivetrack-v6.kicad_sch           原理图 rev 6.1
│   ├── drivetrack-pcb-v6-electrical.kicad_pcb   ★ 真实封装电气板（75 器件，未布线）
│   ├── drivetrack-pcb-v6.kicad_pcb        rev 6.0 机械参考板（仅几何）
│   ├── drivetrack-pcb-v6.kicad_pro
│   ├── fp-lib-table
│   ├── netlist-v6.csv            引脚级网表（Ref, Pin, Name, Net）
│   ├── nets-v6.csv               网络 → 节点
│   ├── bom-v6.csv                按封装归并的 BOM
│   ├── DriveTrack.pretty/        自定义 + 新增真实封装（ESP32 / BQ24074 / TPS7A0230 / LIS2DW12 / JST-SH / SOT-23 …）
│   └── previews/placement-v6.png 布局图（PNG + SVG）
├── enclosure-v10/                外壳 v10（已按新孔位重新生成）
│   ├── base-v10.stl / .step      底座（打印件）
│   ├── lid-v10.stl / .step       盖板（打印件）
│   ├── lens-v10.stl / .step      灯窗导光柱（打印件）
│   ├── assembled-v10-DO-NOT-PRINT.stl/.step   仅装配检查，勿打印
│   ├── enclosure_v10.py          参数化脚本（自带尺寸与探针校验）
│   └── notes-v10.md              打印参数、五金、装配顺序、密封注意
├── docs/
│   ├── layout-plan.md            布局方案（分区、规则、BOM 变更、风险、当前状态）
│   ├── placement.csv             75 个器件坐标（含无源件）
│   ├── keepouts.csv              禁布 / 禁铺铜区域
│   └── power-and-wireless.md     电源树、无按键状态机、BLE-OTA 方案、固件改动清单
└── tools/
    ├── v6_design.py              单一数据源：75 器件 / 引脚 / 网络
    ├── gen_schematic.py          生成 .kicad_sch 与 netlist / nets / bom CSV
    ├── build_v6_pcb_real.py      生成电气板（真实封装 + 自动摆放 + 赋网络）
    ├── render_preview.py         生成布局预览 PNG/SVG
    └── build_v6_pcb.py           生成 rev 6.0 机械参考板
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

---

## 四、电气方案（rev 6.1）

电源树：

```
USB VBUS → BQ24074（电源路径 + 500mA 充电）→ VSYS
VSYS → Q1 AO3401（P-MOS 软锁存）→ VLOAD → TPS63802（3.3V buck-boost）→ +3V3
VSYS → TPS7A0230（3.0V / 25nA 常开）→ V_AON → LIS2DW12 + NEO-M9N V_BCKP
+3V3 → TPS7A2033（低噪声）→ GPS_VCC
```

- 无按键：VBUS 分压经 D4、LIS2DW12 INT1 经 D5，二极管或门驱动 Q2；Q3 由 GPIO41 PWR_HOLD 拉低。
  LATCH_G 由 100k 上拉 VSYS。关机顺序必须是“关运动中断 → 释放 PWR_HOLD”。
- USB 在场时固件应拒绝 APP 关机（电平唤醒会立刻重新上电）。
- 充电配置：EN1=3V3 / EN2=GND（500mA USB 模式），ILIM=3.09k，ISET=1.78k，TS=10k，TMR=47k，CE/SYSOFF=GND。
- TPS63802：EN=VLOAD，MODE=GND（省电），L1=0.47µH 4×4×2，C5/C6=22µF，FB 560k/100k → 3.3V。
- I2C：BMI088 与 BMP390 共用 GPIO9/GPIO8；LIS2DW12 同总线，SA0=GND → 0x18。

完整引脚表见 `pcb-v6/netlist-v6.csv`，推演见 `docs/power-and-wireless.md`。

---

## 五、PCB 布局摘要

75 个器件（`docs/placement.csv`），关键位置：

| 区域 | 器件 | 要点 |
| --- | --- | --- |
| GNSS 天线 | ANT1 25×25（13.5,13） | 正下方完整地，禁走线/过孔/螺钉，板边 ≥2 mm |
| GNSS 模块 | U2 NEO-M9N（13.5,34，−90°） | 馈线 <10 mm，50Ω CPWG，直连不去 R8 |
| 传感器 | U3 BMI088（7.5,50）、U4 BMP390（3.5,45） | 左侧无电池区；BMP 贴西壁通气孔，距电源 ≥8 mm |
| 主控 / RF | U1 ESP32-S3-MINI-1U（45,14.5）、LED1（56,8） | courtyard 含天线端净空 Y 6.4–27.6 |
| 接口 | J2 USB-C（31,58）、D1–D3 ESD（26.5/29/31.5,51） | ESD 距连接器 ≤3 mm；USB 本体伸出南边 1.9 mm |
| 电源热区 | U5 BQ24074、U6 TPS63802、U7 TPS7A2033、U8 TPS7A0230、U9 LIS2DW12、L1、Q1–Q3、D4/D5 | 集中右下，热回路小；L1 离 BMP ≥8 mm |
| 电池 | J3 JST-SH（58.5,49，180°） | 开口朝南，已北移避开 MH4 |
| 机械 | MH1–MH4 Ø2.2 NPTH | (30,3)(54,3)**(21.5,59)**(54,59) |

**相对 rev 6.0 的两处结构修正**

1. MH3 从 (30,59) 西移到 (21.5,59)：原位置正好压在 USB-C 插座本体上。外壳 v10 的对应螺钉柱已同步改到 X=24.8 并重新生成 STL。
2. J3 从 (57.5,55) 北移到 (58.5,49)：避开 MH4 安装柱。

电池 103450 只占板下右侧 X 26–60 / Y 6–56；左侧 X 0–26 全高无电池，给传感器和天线让位。

---

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
五金、装配顺序、密封注意见 `enclosure-v10/notes-v10.md`。

**未定项**：USB 开口按 mid-mount 建模。若实际用 top-mount 座，开口需下移约 1.6 mm，
首件打印请先量实物座子。

---

## 八、复现

```bash
# 原理图 + CSV（纯标准库）
cd tools && python3 gen_schematic.py

# 电气板：真实封装 + 自动摆放 + 赋网络
python3 build_v6_pcb_real.py

# 布局预览（需 matplotlib）
python3 render_preview.py

# 机械参考板（需 V5 原始板作模板）
python3 build_v6_pcb.py

# 外壳（需 cadquery 2.8 / Python 3.12）
cd enclosure-v10 && python enclosure_v10.py
```

`v6_design.py` 是唯一数据源；改引脚或网络后依次重跑 `gen_schematic.py`、
`build_v6_pcb_real.py`、`render_preview.py` 即可同步。

---

## 九、投产前还必须做的（按顺序）

1. **布线**：GNSS 馈线优先（50Ω CPWG、少过孔），3V3/VLOAD 主干 0.5–1.0 mm，USB 差分等长 <5 mm。
2. **去耦重摆**：把 C7/C13/C16/C17/C21/C23 等按引脚就近放到 U1 电源脚，当前自动聚类只保证不重叠。
3. **分区落铜**：按 `docs/keepouts.csv` 画禁铺铜，天线区与传感器区下方完整地。
4. **ERC / DRC**：导入 `netlist-v6.csv` 与原理图对照，跑 KiCad ERC 和 DRC；确认 BQ24074 散热焊盘过孔阵列。
5. **首件打样**：先只贴电源链 + ESP32，实测充电、待机 45µA、唤醒与关机（含“关中断再释放 HOLD”时序）。
6. **结构首件**：打印 v10 底座 + 盖板，实测 USB 座高度、电池出线、密封圈压缩量、MH3 新孔位。
7. **App 侧 OTA 流程改造**（见第六节）。
