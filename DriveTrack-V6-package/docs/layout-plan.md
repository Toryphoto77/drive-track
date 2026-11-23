# DriveTrack V6 紧凑方盒方案（已确认）

## 决策记录

- 形态：方盒叠板（电芯在板下，传感器区不在电芯上方）
- 电芯：103450，34 × 50 × 10 mm，约 2000mAh
- 主控：ESP32-S3-MINI-1U（替代 ESP32-S3-WROOM-1U）
- 移除：microSD、全部测试点 / DNI 器件（U.FL、原 SK6812、J5、J9、TP1–TP10）
- 灯：5 颗 0805 → 1 颗 SK6812MINI RGB
- 保留：25×25 陶瓷天线、NEO-M9N、BMI088、BMP390、USB-C
- 电源：改为 BQ24074 + TPS63802 + 软锁存（无按键），详见 `power-and-wireless.md`
- 安装：4 × M2 对称，全部落在上下边条，不穿电芯、不进天线投影

## 最终尺寸

| 项目 | 数值 |
| --- | --- |
| PCB | 62 × 62 × 1.6 mm，四层 FR-4，圆角 R2.0 |
| 外壳盒体 | 68 × 68 × 21 mm（壁厚 3 mm，螺钉内置，无外翻边） |
| 体积 | 97 cm³ |
| 对比 V5 优化版 | 147 cm³ → 97 cm³，减 34% |
| 对比 v9（52×70） | 117 cm³ → 97 cm³，减 17% |
| 电芯投影 | X = 26–60，Y = 6–56（板下） |
| 传感器安全区 | X = 0–26，全高无电芯 |
| 续航估算 | 约 18h（GNSS 10Hz + IMU + BLE；WiFi 仅 OTA 时开启） |

## 高度叠层（21 mm）

| 层 | 厚度 |
| --- | --- |
| 底壳 | 2.0 |
| 电芯下泡棉 | 0.8 |
| 电芯 | 10.0 |
| 绝缘片 | 0.3 |
| PCB | 1.6 |
| 顶部最高件（USB-C 3.3 / JST-SH 2.9 / ESP32 2.4 / L1 2.0） | 3.3 |
| 盖板 | 1.8 |
| 装配间隙 | 0.5 |
| 合计 | 20.3 → 外形 21 |

关键：必须用低矮电池座（JST-SH，成高约 2.9 mm）和低矮电感（4×4×2）。继续用 JST-PH 的 8 mm 插头会直接把高度拉回 25 mm 以上。

## 区域划分

| 区域 | X (mm) | Y (mm) | 内容 | 规则 |
| --- | --- | --- | --- | --- |
| GNSS 天线 | 0–27 | 0–26 | 25×25 patch | 正下方完整地，无走线/过孔，板边 ≥2 mm |
| GNSS 模块 | 5–22 | 26–42 | NEO-M9N | 馈线 <10 mm，50Ω CPWG，删除 R8 |
| IMU / 气压 | 0–14 | 40–56 | BMI088 + BMP390 | 隔离槽，远离功率；BMP 贴左壁通气孔 |
| 主控 | 27–62 | 0–26 | ESP32-S3-MINI-1U | IPEX 朝上边，距 patch ≥10 mm |
| 电源 / 接口 | 25–56 | 42–57 | BQ24074/TPS63802/TPS7A2033/L1/USB-C | 热回路小，电感离 BMP ≥8 mm |
| 电池投影（板下） | 26–60 | 6–56 | 103450 | 无柱、无通孔；四角外留安装条 |

## 关键布局规则

1. 四层板：Sig / GND / PWR / Sig，GND 完整，缝合孔 3–5 mm。
2. GNSS 馈线 patch → NEO RF_IN 直连，不换层、不上过孔，两侧地过孔护栏。
3. 天线正下方 25×25 内禁止任何走线、过孔、铜箔割缝和螺钉。
4. BMI088 四周开隔离槽，下方无电芯、无连接器；SPI 走线短且不跨分割。
5. BMP390 距 BQ24074 / TPS63802 / L1 ≥ 8 mm，靠近左壁透气孔，局部挖铜隔热。
6. VBUS / BAT / 3V3 主干 0.5–1.0 mm；充电热回路面积最小化。
7. USB-C ESD 器件距连接器 ≤3 mm；D+/D- 等长差 <5 mm。
8. 电池座 JST-SH 放在板东侧 (58.5,49)，开口朝南；板边开 2.0×4.3 mm 出线缺口（X 60–62，Y 55–59.3），极耳线从缺口上翻，不横穿板面。JST 从原 (57.5,55) 北移，避开 MH4 安装柱。
9. 安装孔 Ø2.2 NPTH，位置 **(30,3)、(54,3)、(21.5,59)、(54,59)**，柱外径 ≤4.6 mm。**左下孔从 (30,59) 西移到 (21.5,59)**：原位置正好压在 USB-C 插座本体上；外壳 v10 的对应螺钉柱需同步从 X=33.3 改到 X=24.8（见 `enclosure-v10/notes-v10.md`）。
10. 2.4GHz IPEX 到盖内 FPC 的走线避开 GNSS patch 投影。
11. 出线缺口 5 mm 范围内不得有走线或裸露铜箔，缺口边缘做 0.3 mm 倒圆，防止割伤线皮。

## BOM 变更

| 原 | 新 | 说明 |
| --- | --- | --- |
| ESP32-S3-WROOM-1U-N16R8 | ESP32-S3-MINI-1U-N8R2 | 省 5×5 mm、0.7 mm 高 |
| 104060 4000mAh | 103450 2000mAh | 板宽 -6、板长 -10 |
| microSD Hirose DM3AT | 删除 | 固件未挂载；可选 128MB SPI NOR |
| JST-PH 2.0 卧式 | JST-SH 1.0 卧式 | 高度 -5 mm |
| L1 7.3×7.3×4.5 | 4×4×2 屏蔽电感 | 高度 -2.5 mm |
| IP5306 + TPS563201 | BQ24074 + TPS63802 + TPS7A2033 + TPS7A0230 + 软锁存 | 无按键电源；3.3V buck-boost 覆盖 3.0–4.4V |
| — | Q2/Q3 BSS138、D4/D5 1N4148W、R7/R9/R14 100k | 软锁存与 USB/动作唤醒或门 |
| 5 × LED 0805 + 电阻 | 1 × SK6812MINI | 简化灯窗 |
| U.FL / SK6812 / J5 / J9 / TP1–10 | 删除 | 量产不贴，只保留工厂 pogo 焊盘 |
| R8 0Ω（GNSS 馈线） | 删除 | 直连 50Ω |

## 待确认风险

1. **Flash 容量**：ESP32-S3-MINI-1U 常见最大为 8MB Flash + 2MB PSRAM（N8R2）。现固件分区按 16MB 规划（2×4MB OTA + 8MB 缓存），需改为 2×2.5MB OTA + 2.5MB 缓存（固件约 1.5MB，够用）；若 16MB 是硬指标，只能回 WROOM-1U。
2. 若断线缓存需要 >30 min，加一颗 64/128MB SPI NOR（约 6×5 mm，可放板上）。
3. JST-SH 座已定在 (58.5,49)、开口朝南；电芯极耳朝南偏东，线长按约 25 mm 实配。
4. 外壳已按 62×62 出 v10：68.6×68.6×21.0 mm，无按键、无外翻边，STL 见 `enclosure-v10/`。
5. 电源键已取消：USB 插入沿 + LIS2DW12 动作唤醒，APP 或 5 分钟无动作关机；外壳只保留 USB 与通气孔。
6. BQ24074 / TPS63802 与电芯之间在结构上留 ≥2 mm 间隙，避免充电发热烤电芯。
7. 四颗 M2 螺钉位于密封圈内侧，需用带 O 圈的螺钉或点胶，否则是进水通道。

## 当前状态（rev 6.1，已布线铺铜）

- 原理图：`DriveTrack-PCB-V6/drivetrack-v6.kicad_sch`，71 个符号（4 个安装孔无引脚）、274 个引脚全部带全局标签、37 个 NC 脚全部有 no-connect。
- 网表 / BOM / 布局：`netlist-v6.csv`、`nets-v6.csv`、`bom-v6.csv`、`placement.csv`，由 `tools/v6_design.py` 单一数据源生成。
- 电气板：`DriveTrack-PCB-V6/drivetrack-pcb-v6-electrical.kicad_pcb`，75 个真实封装、50 个网络、311 个设计引脚全部落焊盘并赋网络。
- **已布线板**：`DriveTrack-PCB-V6/drivetrack-pcb-v6-routed.kicad_pcb`
  - 1053 段走线 / 130 个过孔 / 75 个封装 / 50 个网络。
  - 四层 GND 铺铜：F.Cu 3048 mm²、In1.Cu 2078 mm²、In2.Cu 2894 mm²、B.Cu 3439 mm²。板边内缩 0.6 mm，热焊盘连接，U5 的 GND 焊盘为实心。
  - DRC（`kicad-cli pcb drc`）：**0 error / 0 unconnected**；316 条 warning（丝印压焊盘 131、lib_footprint 72、丝印重叠 53、text_height 53、丝印贴边 4、悬空过孔 3）。
  - 规则：Default netclass clearance 0.15 mm、走线 0.25 mm、过孔 0.6/0.3 mm；板边/孔壁 0.2 mm。
  - J2 mid-mount 焊盘贴边：由 `drivetrack-pcb-v6-routed.kicad_dru` 中 `A.Parent == 'J2'` 的 edge_clearance 豁免解决。
  - 已知取舍：B.Cu 被 USB_DM 的 D3→U1 长斜线切成两块（x≈33→45）；USB 差分未等长、GNSS 馈线未做 50Ω 控阻抗；板上无 keepout/rule area（ESP32 模块为外置天线型号）。
- 制造文件：`DriveTrack-PCB-V6/fabrication/`（11 层 Gerber + Excellon PTH/NPTH + 钻孔报告），基于已铺铜的 routed 板。
- 预览：`DriveTrack-PCB-V6/previews/`，`placement-v6.png/.svg`（布局）+ `routed-F_Cu/B_Cu/In1_Cu/In2_Cu.png/.svg`（含铺铜各层）+ `routed-3d-top/bottom/iso.png`。

## 下一步

1. **ERC**：本地打开工程跑 KiCad ERC，确认无未驱动/多驱动；沙箱只跑了 DRC。
2. **打样前自查 Gerber**：重点看 USB-C 贴边、板框圆角、NPTH 4×Ø2.2、PTH 130×Ø0.3。
3. **测试版首件**：先贴电源链 + ESP32 + GNSS，实测充电、待机 45µA、唤醒/关机时序、GNSS TTFF。
4. **量产前整改**：去耦就近重摆；USB 差分等长；GNSS 馈线 50Ω CPWG；B.Cu 分割问题。
5. 补 `fp-lib-table`（如需要“Update from library”），当前封装已内嵌在 PCB 文件中，可直接打开。
6. 外壳 v10 已生成（68.6×68.6×21.0），材料定为 MJF PA12（黑色染色），制造与验收按 `enclosure-v10/notes-v10.md`（板坐标 MH3 21.5,59 / 壳坐标 24.8,62.3）。
