# DriveTrack 赛道库种子数据核对报告

> 生成方式：`tools/seed_fetch.py`（输入 `tools/tracks21.json`）从 OpenStreetMap
> 实时拉取并逐条核对后写出本目录。数据版本见 `tracks-manifest.json`
>（dataVersion `1.0`，updatedAt 2026-11-05）。
>
> **红线**：只用 openly licensed 来源。本批全部几何来自 OpenStreetMap
>（ODbL，署名见下）；官方公布长度、弯角数等公开事实仅作校验标尺，
>不作为几何来源。未核对的一律不得标为实测或官方。

## 来源与署名

| 来源 | 许可 | 署名方式 |
|---|---|---|
| OpenStreetMap（全部 19 包的中心线几何） | ODbL | 库页顶部署名行 + 本 manifest 的 `attribution` 字段 + 每包 `sourceDetail` 里的 `© OpenStreetMap contributors，ODbL` |
| 官方公布长度 / 弯角数（赛道官网、FIA、维基等公开事实） | 公开事实，仅校验 | 不写入包几何；仅用于长度偏差与弯角门限核对 |
| 用户 GPS 实测、社区上传 | 后续来源 | 本轮暂无；入库后按包标注 `measured` / `community` |

严禁复制第三方专有赛道库的数据；它们的条目数
只当参考，不当来源。公开可见不等于可自由商用。

## 总览

- 目标赛道：21 条
- 写出数据包：**19 包**（已核对 17、待核 2）
- 无经纬度包：2 条（银石、成都天府），App 内仍走内置迁移示意包
  （来源估算、核对状态待核），不影响选赛道与计时，中心线待后续补齐。

## 核对标尺（脚本内已固化，缺一不可）

- **几何**：中心线必须闭合（首尾同点）、点数 ≥ 30；不是停车场、
  不是错位的另一条赛道、不是残缺片段。
- **名称地点**：OSM 对象名与赛道名、所在地点对得上（名 token 匹配；
  中文赛道另加中文 token；日文对象同时查 `name:en` / `name:ja`）。
- **长度**：与官方公布长度对照。偏差 ≤ 10% 且无其他问题 → 已核对；
  10%–20% → 待核；**> 20% → 整包弃用**（绝不能留可疑几何）。
- **最大点间距**：> 500m 时，仅当缺口落在直道上（缺口前后走向夹角
  < 15°，按闭合环索引取模判定）且长度偏差 < 2% 才放行，否则待核。
- **起终点**：仅当关系成员 `role=start` / `start-finish` 节点落在回路线上
  25m 内才采用，否则留空标待核。
- **分段点**：一律留空标待核（OSM 几何无法推导官方分段线）。
- **弯角表**：按转向符号切分、30m 平滑窗口推导；官方总数已知时推导数
  须在 0.7×–1.3× 内才收入，否则弯角表留空标待核（宁缺勿错）。

## 逐条结果

| 赛道 | 状态 | 点数 | 实测长度 | 公布长度 | 偏差 | 最大点间距 | 弯角（推导/官方） | 起终点 | OSM 来源对象 |
|---|---|---|---|---|---|---|---|---|---|
| 上海国际赛车场 | 已核对 | 257 | 5.459km | 5.451km | +0.15% | 300m | 留空（11/16 未过 0.7 门限） | 有 | relation 2094941（circuit） |
| 珠海国际赛车场 | 待核 | 64 | 4.310km | 4.319km | -0.21% | 550m | 11/14 | 无 | relation 20397790（circuit） |
| 宁波国际赛车场 | 已核对 | 59 | 3.968km | 4.010km | -1.05% | 308m | 19/22 | 无 | highway=raceway 单条闭合 way |
| 浙江国际赛车场 | 已核对 | 83 | 3.202km | 3.200km | +0.06% | 266m | 16/16 | 无 | highway=raceway 单条闭合 way |
| 上海天马山赛车场 | 已核对 | 86 | 2.036km | 2.063km | -1.31% | 207m | 10/14 | 无 | highway=raceway 单条闭合 way |
| 鄂尔多斯国际赛车场 | 已核对 | 194 | 3.697km | 3.751km | -1.44% | 203m | 留空（11/18 未过门限） | 无 | highway=raceway 单条闭合 way（鄂尔多斯赛道，way 118820675） |
| 纽博格林北环 | 已核对 | 1070 | 20.831km | 20.832km | -0.00% | 543m（直道稀疏节点，已放行） | 75/73 | 无 | route 38566（Nürburgring Nordschleife，关系直取） |
| 斯帕 | 已核对 | 330 | 6.995km | 7.004km | -0.13% | 338m | 21/19 | 有 | relation 284560（circuit） |
| 蒙扎 | 已核对 | 284 | 5.792km | 5.793km | -0.02% | 384m | 12/11 | 有 | relation 284565（circuit，空 role 成员拼接） |
| 铃鹿 | 已核对 | 261 | 5.801km | 5.807km | -0.10% | 348m | 16/18 | 无 | relation 284570（circuit，日文主名 + 英名匹配） |
| 拉古纳塞卡 | 已核对 | 206 | 3.601km | 3.602km | -0.03% | 249m | 13/11 | 无 | route 21195763（WeatherTech Raceway Laguna Seca） |
| 美洲赛道 | 已核对 | 347 | 5.502km | 5.513km | -0.20% | 296m | 17/20 | 有 | relation 6537729（circuit） |
| 富士 | 已核对 | 229 | 4.554km | 4.563km | -0.20% | 1288m（主直道稀疏节点，走向夹角 3.3°，已放行） | 12/16 | 无 | highway=raceway 单条闭合 way（Fuji Speedway，way 148622740） |
| 北京金港国际赛车场 | 已核对 | 101 | 2.380km | 2.390km | -0.42% | 381m | 9（无官方总数可比，5–40 合理区间内） | 无 | highway=raceway 单条闭合 way |
| 广东国际赛车场 | 待核 | 96 | 2.815km | 2.820km | -0.18% | 713m | 留空（待核包不收弯角） | 无 | highway=raceway 单条闭合 way |
| 摩纳哥赛道 | 已核对 | 375 | 3.300km | 3.337km | -1.11% | 60m | 18/19 | 有（start-finish 节点） | relation 148194（circuit，街道成员拼接） |
| 勒芒萨尔特赛道 | 已核对 | 872 | 13.635km | 13.626km | +0.07% | 567m（直道稀疏节点，已放行） | 30/38 | 有（start-finish 节点） | route 2126739（Circuit des 24 Heures du Mans） |
| 雪邦国际赛车场 | 已核对 | 168 | 5.529km | 5.543km | -0.25% | 369m | 13/15 | 有 | relation 284496（circuit） |
| 巴瑟斯特全景山赛道 | 已核对 | 363 | 6.197km | 6.213km | -0.26% | 203m | 19/23 | 无 | relation 6942508（circuit，非 pit 成员） |

## 待核 2 条的原因

- **珠海**：几何闭合、长度偏差仅 -0.21%，但最大点间距 550m 且缺口
  不在直道上（走向夹角超限），几何可能缺段 → 整包标待核，不得当
  已核对用。
- **广东 GIC**：同理，最大点间距 713m 且缺口位于回路边界、无法判定
  直道性 → 标待核。

## 无经纬度包 2 条的原因与后续

- **银石**：OSM 关系 51160（Silverstone Grand Prix）成员总长 11.43km，
  远超公布 5.891km——关系内混入多个布局（GP / International / Stowe
  共用路段）的段，简单拼接会拼出错误回路（实测曾拼出 2.44km 与
  11.2km 两种错误结果，均被长度带挡下，未写入包）。后续需按布局
  感知的方式恢复（例如按弯角段名序列拼 GP 布局，或用 International
  关系 51162 做差分），本轮不硬凑。
- **成都天府**：全部查询词（成都天府国际赛车场 / 天府国际赛车场 /
  Chengdu Tianfu International Circuit）均无 Nominatim 候选，疑似 OSM
  暂无该 venue。后续待 OSM 补录或用户实测上传。

## 拉取受阻情况（均已如实记录，未因此编造数据）

- Overpass 主端点（overpass-api.de、kumi、nchc、private.coffee）不通；
  镜像 overpass.osm.ch 可连通但按名查上海疑似数据滞后、区域关系查询
  超时，故主路线不用 Overpass。
- OSM map API 有 bbox 面积 / 节点上限：银石扩框 3 倍曾返回 HTTP 400
  （脚本 v4 已修复：扩框失败时回落首轮数据走诊断，不误报拉取失败）；
  纽北固定大框（0.20°×0.13°）恒 400，改走关系 38566 直取解决。
- Nominatim 覆盖问题：鄂尔多斯须用 OSM 实际对象名“鄂尔多斯赛道”
  才能命中（“鄂尔多斯国际赛车场”无候选）；成都天府暂无候选（见上）。
- 摩纳哥 / 勒芒的起终点节点 role 为 `start-finish`（非 `start`），
  脚本已同时认两种 role。

## App 内呈现

- 已核对包：显示 OSM 来源 + 已核对徽标，可用于选赛道示意图与
  LapTimer 起终点 / 分段点（起终点仅在有起点且与记录首点 < 500m 时采用）。
- 待核包：显示待核徽标与待核原因，几何仍可用于示意图，但不作为
  已核对数据宣传。
- 无包赛道：仍走内置迁移示意包（归一化示意、来源估算、状态待核），
  绝不把示意坐标当经纬度用。

## 分段核对报告（2026-11-05，第一步 + 第二步 + 第三步）

### 许可结论（第一步）

- Lovely Sim Racing track data：仓库根目录无 LICENSE 文件，但 README
  末尾声明 © 2025 by Lovely Sim Racing，CC BY-NC-SA 4.0（署名 -
  非商业性使用 - 相同方式共享）。许可检查通过，有条件使用：
  - BY：每包 sectorNote 与本报告署名“Lovely Sim Racing track data，
    CC BY-NC-SA 4.0”；
  - NC：当前免费分发（GitHub Release 免费下载）符合；若 App 日后
    monetize（付费下载、广告、与分发挂钩的打赏），NC 即有风险，
    须另行定夺（DriveTrack 早期有“打赏码待用户后续补”一项，
    与 NC 的关系需主代理定夺，此处不隐瞒）；
  - SA：派生数据须同样以 CC BY-NC-SA 4.0 分发；本包 JSON 同时含
    OSM（ODbL）几何与 CC BY-NC-SA 分段值，两者 share-alike 并不
    形式兼容，缓解办法是按字段分别署名（几何 = ODbL，分段值 =
    CC BY-NC-SA），不在整文件层面声称单一许可。
- tobi/track-atlas：LICENSE 为 MIT，但文件末尾注明许可只覆盖仓库
  代码，数据另行许可（OSM 几何为 ODbL，见 ATTRIBUTION.md）；
  ATTRIBUTION.md 写明 Lovely 来源部分遵循上游复用条款（即
  CC BY-NC-SA 4.0）。结论：track-atlas 不带来新的许可，其分段值
  仍受 Lovely 的 CC BY-NC-SA 4.0 约束；track-atlas 的价值是起终点
  锚点与交叉校验，不是独立许可来源。拉古纳实测分段线来自
  track-atlas 自身的 NAIP 航拍核对（美国政府公开航拍，公有领域），
  不属于 Lovely 链条。
- Lovely 只取分段比例数值，不取弯角/直道名称，故其“弯角名称上游
  致谢 Racing Circuits”链条不影响本任务。
- 严禁复制第三方专有库分段数据（本批未碰）；
  FastF1 的 get_circuit_info 给的是 marshal sectors（旗语区段），
  不是计时分段，未用。

### 分段语义

- Lovely 的 sector 数组中 marker = 该分段的结束点占整圈的比例
  （圈长比例，0~1）；3 分段赛道为 [S1 结束，S2 结束，1.0]，
  其中 1.0 即起终点线。本 App 的 LapTimer 对 sectorPoints 做
  take(2)，即只取前 2 个点 = [S1 结束，S2 结束]，S3 结束即起终点。
  因此写入包的 sectorPoints = Lovely sector markers 去掉末尾 1.0。
- 数据瑕疵（已发现，记录在案，不阻塞）：
  - 上海 f12024/shanghai.json 的 S3 marker 为 0.1（应为 1.0，属
    0.1/1.0 数字换位错误）；因 S3 结束即起终点、映射时本来就要
    丢掉末尾 marker，故不影响。
  - 摩纳哥 f12024/monaco.json 的 Sainte Devote 弯道 marker
    （0.0663）与其 start 字段（0.0905）不一致（start > marker，
    且 start > end 0.0711），属弯道数据小瑕疵，与分段无关；
    marker 序列本身单调且几何合理，予以采用。
  - 拉古纳 iRacing 文件用 5 分段体系（0.184/0.377/0.643/0.804/
    1.0），与本 App 的 3 分段模型不直接对应；且其 country 字段
    误写为 AU（应为 US）。均属数据瑕疵，记录在案。
  - 上海 f12024 与 f12025 文件逐值一致（分段与全部 16 个弯道
    marker 均相同）；铃鹿 f12024 与 track-atlas 引用的 f12025
    分段逐值一致。故 F1 赛道以 f12024 系列为主值，24/25 年
    份差异不影响本批（斯帕/摩纳哥/蒙扎/美洲的 f12025 文件未
    逐一比对，分段线历年来不变，风险低，记为已知缺口）。

### 锚点与方向校验（关键发现：5 条原起终点错位）

- 本包自带起终点（7 条）经与 track-atlas start_finish 逐一比对，
  仅斯帕一致（0.0m）；其余 5 条均偏离真实起终点线，且都落在
  同一起终点直道上、沿赛道方向错开：上海 167.6m、摩纳哥 625.5m、
  蒙扎 197.1m、美洲 296.1m、勒芒 114.6m。种子脚本采纳的 OSM
  role=start / start-finish 节点并非起终点线位置（摩纳哥的节点
  落在隧道后港池直道上，偏离 1445m 的圈长位置）。
- 由于 LapTimer 的分段检测要求圈起点与分段同一起点（圈内按
  S1、S2 顺序触发），若起终点错位则分段触发顺序错乱，故本批
  同时把 5 条错位起终点校正为 track-atlas 起终点线位置，并把
  3 条原无起终点的可映射包（铃鹿、拉古纳、富士）按同一锚点补入
  起终点（否则 500m 门控下分段点根本不会被采用）。起终点校正
  与补入均记入各包 startNote；包版本与分段同批升为 2（未发布
  前的同一批，不另 bump）。
- 方向校验（全部 9 条可映射包均为中心线顺序 = 行车方向）：
  - 弯角投影法（6 条）：track-atlas 弯角位置投影到本包中心线，
    以锚点起算的正向分数与 marker 对照，正向中位误差 0~7m，
    反向中位误差 902~2098m（摩纳哥 6.5m/902m、上海 0m/1210m、
    铃鹿 1.3m/1652m、富士 0m/1457m、蒙扎 0.7m/1854m、
    斯帕 0m/2098m）。
  - 集合法（美洲、勒芒）：Lovely 弯道 marker 集与本包弯角弧位集
    最近邻对照，正向平均误差美洲 38m、勒芒 64m（勒芒含 LMU
    0.01 圈取整量化约 ±68m），反向 124m/121m。
  - 实测线法（拉古纳）：正向映射点距实测 S1/S2 结束线中点
    1.4m/5.9m，反向映射点距 441m/432m——方向与分数同时得证，
    是本批最强的单项校验。
- 锚点投影：9 条锚点落在本包中心线上的偏离均 ≤2.7m（多为 0m），
  说明本包几何与 track-atlas 同源（同 OSM 关系），映射无系统
  几何偏差。

### 覆盖表（19 包）

- 已映射 9 条（包版本 1→2，sectorNote 标模拟器推导/实测线、
  待实测核对，绝不标 verified、绝不标官方）：
  - 上海 0.2607/0.5486（Lovely F1 2024；起终点校正 167.6m）
  - 摩纳哥 0.3195/0.7442（Lovely F1 2024；起终点校正 625.5m）
  - 蒙扎 0.3274/0.6428（Lovely F1 2024；起终点校正 197.1m；
    track-atlas 蒙扎分段为粗值 0.35/0.65，与 Lovely 差约 130m，
    取 Lovely 精确值，记为已知容差）
  - 斯帕 0.3317/0.7229（Lovely F1 2024；起终点与原包一致）
  - 铃鹿 0.3821/0.8173（Lovely F1 2024；起终点新增）
  - 美洲 0.3014/0.7118（Lovely F1 2024；起终点校正 296.1m）
  - 勒芒 0.14/0.57（Lovely LMU，0.01 圈取整，单点量化约 ±68m；
    起终点校正 114.6m；iRacing 7 分段值仅作参考，不直接用）
  - 拉古纳 0.37671/0.64227（track-atlas 实测分段线；起终点新增；
    与 ACC 模拟器分段 S1 0.254 冲突约 442m，已取实测线，因
    两条实测边界与 iRacing 独立分段边界 0.377/0.643 重合，
    而 ACC S1 无任何其他来源印证）
  - 富士 0.41/0.66（Lovely LMU，0.01 圈取整，单点量化约 ±23m；
    起终点新增；与 track-atlas 富士分段逐值一致）
- 仍无分段 10 条（sectorPoints 保持 0 条，原 sectorNote 不动）：
  - 雪邦：无 Lovely 数据（F1 游戏 2024/2025 已无雪邦），
    track-atlas 亦无雪邦；第二步遥测亦不可得（见下）。
  - 宁波、浙江、天马、鄂尔多斯、珠海、广东 GIC、金港：
    中国赛道均不在模拟器数据里，无 Lovely 条目。
  - 纽北：有 iRacing 10 分段值，但无起终点锚点（本包无、
    track-atlas 无），且 10 分段结构不适配本 App 的 2 点模型；
    ACC nurburgring-24h 是 GP+北环组合布局（约 25km），
    绝不能用于纯北环包。
  - 巴瑟斯特：有 ACC 3 分段（0.316/0.764）与 iRacing 6 分段
    （0.182/0.36/0.521/0.594/0.629/1.0），两者结构冲突，
    且无起终点锚点（本包无、track-atlas 无）。

### 第二步：遥测反推（结论：无可映射赛道）

- 按任务范围，第二步只做第一步覆盖不到的 F1 赛道。19 包中的
  F1 赛道为上海、摩纳哥、蒙扎、斯帕、铃鹿、美洲、雪邦，其中
  第一步未覆盖的仅雪邦。
- 雪邦最后一场 F1 是 2017 年马来西亚大奖赛（2017-10-01，
  维斯塔潘夺冠；此后未再续约，2018 赛季起无马来西亚站），
  早于 OpenF1（2023 年起）与 FastF1（2018 年起）的档案起点，
  故两个档案中均无雪邦 F1 遥测，分段无法反推，留空待核。
- 附带说明：本次文本抓取 OpenF1 接口返回 404（工具层原因，
  未作为缺失证据）；缺失结论依据的是赛历事实（2017 后无
  马来西亚站），不是抓取失败。不得为凑数把第二步扩大成对
  已覆盖赛道的复核；若主代理希望用遥测复核已覆盖赛道，须
  另行定夺。

### 第三步：实测替换规则（落点）

- 合并层面的“用户改动胜出”已经成立，无需重做（已核对）：
  mergePackages 中 userModified 覆盖层无条件胜出；
  diffUpdates 与 applyUpdates 均跳过 userModified 覆盖层
  （远端永不覆盖，检查结果区记入 skippedUserModified 明示）。
- 已补的缺口：编辑器 _save 原先只改 sectorPoints、verification、
  verificationNote，不改 sectorNote——用户手动替换推导分段后，
  注记仍会写着模拟器推导来源。已修：编辑器保存时比较分段点
  是否变化，分段变了则 sectorNote 改为实测口径（“用户实测
  分段点（编辑器手动落点），以实测为准”），分段清空则改为
  待补口径，分段没动则不动原注记。规则抽为纯函数
  sectorNoteAfterEdit（lib/track_library.dart），并补测试
  （test/track_sector_rules_test.dart）。
- 编辑器落分段点流程本身已有功能（工具栏分段点工具、删除末
  分段点、保存），已核对可用，不重做。
- “从行程定分段”小入口：超出最小改动范围（需行程选择器 +
  轨迹上点选 UI），未做，记为缺口；现有路径为：从行程导入
  包轮廓后，在编辑器中手动落分段点，已满足实测替换主路径。

### 精度说明（汇总）

- F1 2024 分段（4 位小数）：分数本身精确到约 1m 量级（0.0001
  圈 ≈ 0.5m），但模拟器赛道与真实计时线圈位置的偏差未知；
  拉古纳实测线校验（1.4m/5.9m）证明方法本身无系统偏差，
  但不证明每条 F1 赛道的模拟器分段等于真实线圈位置。
  故全部 9 条仍标待实测核对，不标 verified。
- LMU 分段（2 位小数）：单点量化步长约 136m（勒芒）/
  45m（富士），即 ±68m/±23m，属已知误差。
- 映射插值：中心线稀疏段（如富士主直道 1288m 缺口）按段
  线性插值，弧长误差随中心线几何误差走，不另引入等分。
- 映射脚本：tools/sector_map.py（读 tools/sector-sources.json，
  含锚点、弯角校验数据、冲突记录）；校验报告：
  tools/sector-map-report.json。

### 版本

- 9 条可映射包版本 1→2（manifest 同步 bump）；数据总版本
  保持 V1.0.1，updatedAt 2026-11-05；其余 10 条包版本不动。
- 本批数据尚未发布（未推仓库、未建 Release），随下个版本走。

## V1.4.0 补充（2026-11-24）

数据总版本 V1.3.0 → V1.4.0；软件版本不动。逐条来源见 `data/track-sources-v1.4.0.json`，脚本见 `tools/track-batch-v1.4/`。

### 规则

- 几何只取 OpenStreetMap（ODbL），沿用 `tools/seed_fetch.py` 的核对规则：闭合、点数 ≥ 30、名称/位置对得上、最大点间距检查。
- 公布长度取英文维基百科信息框（每条记录页面与 revision），只作校验，不作几何来源。偏差 ≤ 10% 且无大缺口为已核对；有大缺口为待核；偏差 > 10% 本轮不收。
- 起终点只采用 OSM 关系 role=start 节点，否则留空；分段点、龙门架一律留空待核。
- 卡丁车场多数没有可引用的公布长度，一律标待核。
- 新增可选字段 `kinds`（`kart` / `moto` / `car`，可多选）：卡丁车来自 OSM sport=karting 或场地名；摩托依据维基信息框当前赛事含摩托赛事（MotoGP、WorldSBK、BSB、MotoAmerica、FIM EWC 等）。没有依据的不写，App 回落按名称归类。

### 新增 45 条

| id | 赛道 | 地区 | 类型 | 计算长度 | 公布长度 | 偏差 | 状态 | 起终点 |
|---|---|---|---|---|---|---|---|---|
| assen | 阿森赛道 / TT Circuit Assen | 荷兰 | car/moto | 4547 m | 4.555 km | -0.17% | 已核对 | 无 |
| autopolis | Autopolis 赛道 / Autopolis | 日本 | car/moto | 4633 m | 4.673 km | -0.86% | 已核对 | 无 |
| bilster_berg | 比尔斯特贝格赛道 / Bilster Berg | 德国 | 按名称 | 4186 m | 4.274 km | -2.07% | 已核对 | 无 |
| brno | 布尔诺赛道 / Brno Circuit | 捷克 | 按名称 | 5401 m | 5.403 km | -0.03% | 已核对 | 无 |
| buriram | 武里南国际赛道 / Chang International Circuit | 泰国 | car/moto | 4567 m | 4.554 km | +0.29% | 待核 | 无 |
| cadwell_park | 卡德威尔公园 / Cadwell Park | 英国 | car/moto | 3490 m | 3.502 km | -0.33% | 已核对 | 无 |
| dubai_autodrome | 迪拜赛车场 / Dubai Autodrome | 阿联酋 | car | 5406 m | 5.39 km | +0.29% | 已核对 | 无 |
| inje | 麟蹄赛道 / Inje Speedium | 韩国 | car | 3947 m | 3.908 km | +1.01% | 已核对 | 无 |
| knockhill | 诺克希尔赛道 / Knockhill Racing Circuit | 英国 | car/moto | 2071 m | 2.0389 km | +1.58% | 已核对 | 无 |
| knutstorp | 克努茨托普赛道 / Ring Knutstorp | 瑞典 | car | 2064 m | 2.079 km | -0.72% | 已核对 | 无 |
| kymiring | 屈米环 / KymiRing | 芬兰 | car | 4497 m | 4.65 km | -3.30% | 待核 | 无 |
| ledenon | 莱德农赛道 / Circuit de Lédenon | 法国 | car | 3149 m | 3.151 km | -0.07% | 已核对 | 无 |
| lihpao | 丽宝国际赛车场 / Lihpao International Circuit | 中国 | car | 3561 m | 3.5 km | +1.74% | 已核对 | 无 |
| lime_rock | 莱姆罗克公园 / Lime Rock Park | 美国 | car | 2390 m | 2.462 km | -2.92% | 已核对 | 无 |
| madras | 马德拉斯国际赛道 / Madras International Circuit | 印度 | car | 3724 m | 3.717 km | +0.19% | 已核对 | 无 |
| mid_ohio | 中俄亥俄赛道 / Mid-Ohio Sports Car Course | 美国 | car/moto | 3539 m | 3.634 km | -2.62% | 已核对 | 无 |
| misano | 米萨诺赛道 / Misano World Circuit Marco Simoncelli | 意大利 | car/moto | 4218 m | 4.226 km | -0.18% | 已核对 | 有 |
| most | 莫斯特赛道 / Autodrom Most | 捷克 | car/moto | 4208 m | 4.212 km | -0.09% | 已核对 | 无 |
| motegi | 茂木赛道 / Mobility Resort Motegi | 日本 | car/moto | 4812 m | 4.801 km | +0.22% | 已核对 | 无 |
| navarra | 纳瓦拉赛道 / Circuito de Navarra | 西班牙 | car | 4296 m | 4.313 km | -0.39% | 已核对 | 无 |
| nogaro | 诺加罗赛道 / Circuit Paul Armagnac | 法国 | car | 3514 m | 3.636 km | -3.36% | 已核对 | 无 |
| nola | 新奥尔良赛车场 / NOLA Motorsports Park | 美国 | car | 4442 m | 4.423 km | +0.44% | 已核对 | 无 |
| oschersleben | 奥舍斯莱本赛道 / Motorsport Arena Oschersleben | 德国 | car/moto | 3664 m | 3.668 km | -0.11% | 已核对 | 无 |
| oulton_park | 奥尔顿公园 / Oulton Park | 英国 | car/moto | 4317 m | 4.307 km | +0.23% | 已核对 | 无 |
| phillip_island | 菲利普岛赛道 / Phillip Island Grand Prix Circuit | 澳大利亚 | car/moto | 4454 m | 4.448 km | +0.13% | 已核对 | 无 |
| poznan | 波兹南赛道 / Tor Poznań | 波兰 | car | 4073 m | 4.083 km | -0.24% | 已核对 | 有 |
| sachsenring | 萨克森林赛道 / Sachsenring | 德国 | car/moto | 3649 m | 3.671 km | -0.60% | 已核对 | 有 |
| sandown | 桑当赛道 / Sandown Raceway | 澳大利亚 | car | 3154 m | 3.104 km | +1.61% | 已核对 | 无 |
| sebring | 赛百灵赛道 / Sebring International Raceway | 美国 | car | 5866 m | 6.019 km | -2.55% | 待核 | 无 |
| sonoma | 索诺玛赛道 / Sonoma Raceway | 美国 | car | 4095 m | 4.056 km | +0.95% | 已核对 | 无 |
| sugo | 菅生赛道 / Sportsland Sugo | 日本 | car | 3581 m | 3.704 km | -3.33% | 已核对 | 无 |
| termas | 里奥翁多温泉赛道 / Autódromo Termas de Río Hondo | 阿根廷 | car | 4504 m | 4.805 km | -6.26% | 待核 | 无 |
| thruxton | 斯拉克斯顿赛道 / Thruxton Circuit | 英国 | car/moto | 3767 m | 3.793 km | -0.69% | 已核对 | 无 |
| thunderhill | 雷霆山赛道 / Thunderhill Raceway Park | 美国 | car | 4609 m | 4.612 km | -0.07% | 已核对 | 无 |
| tokachi | 十胜赛道 / Tokachi International Speedway | 日本 | car | 5088 m | 5.091 km | -0.06% | 已核对 | 无 |
| vallelunga | 瓦莱伦加赛道 / Vallelunga Circuit (Historic International Circuit) | 意大利 | car | 3229 m | 3.222 km | +0.23% | 已核对 | 有 |
| vir | 弗吉尼亚国际赛道 / Virginia International Raceway | 美国 | car/moto | 5254 m | 5.262 km | -0.15% | 已核对 | 无 |
| willow_springs | 柳泉国际赛道 / Willow Springs International Raceway | 美国 | car | 3944 m | 4.023 km | -1.97% | 已核对 | 无 |
| winton | 温顿赛道 / Winton Motor Raceway | 澳大利亚 | car | 3001 m | 3.0 km | +0.03% | 已核对 | 无 |
| kart_osm_108771044 | 路环卡丁车场 / Coloane Karting Track | 中国 | kart | 1216 m | 待核 | — | 待核 | 无 |
| kart_osm_75490872 | 南加尔达卡丁车场 / South Garda Karting | 意大利 | kart | 1178 m | 待核 | — | 待核 | 无 |
| kart_osm_643206090 | 那不勒斯国际赛道（萨尔诺）卡丁车道 / Circuito Internazionale Napoli Kart Circuit | 意大利 | kart | 1647 m | 待核 | — | 待核 | 无 |
| kart_osm_87888593 | 克里斯蒂安斯塔德卡丁车场 / Kristianstad Karting (Åsum ring) | 瑞典 | kart | 1240 m | 待核 | — | 待核 | 无 |
| kart_osm_94517023 | 法涅卡丁车场（马里昂堡） / Karting des Fagnes | 比利时 | kart | 1363 m | 待核 | — | 待核 | 无 |
| kart_osm_67660672 | 亨克卡丁车场 / Karting Genk | 比利时 | kart | 1317 m | 1.36 km | — | 已核对 | 无 |

### 现有包补 kinds（103 条，包版本 +1，几何不动）

- 卡丁车 85 条：`kinds: ["kart"]`（sourceDetail 均为 sport=karting）。
- 汽车 + 摩托 18 条：斯帕、铃鹿、拉古纳塞卡、美洲赛道、雪邦国际赛车场、巴塞罗那-加泰罗尼亚赛道、红牛环、银石赛道、卢赛尔国际赛道、阿尔加维国际赛道、布加迪赛道、埃斯托里尔赛道、穆杰洛赛道、赫雷斯赛道、马尼库尔赛道、保罗·里卡德赛道、多宁顿公园、东望洋赛道。

### 未收录（28 条）

- 安格尔西赛道（Anglesey Circuit）：OSM 拼出的回路与公布长度偏差 >20%，几何疑似错段，弃用
- 阿拉贡赛道（MotorLand Aragón）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 巴伯赛车公园（Barber Motorsports Park）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 布宜诺斯艾利斯赛道（Autódromo Oscar y Juan Gálvez）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 克拉克国际赛道（Clark International Speedway）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 克罗夫特赛道（Croft Circuit）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 汉普顿唐斯赛道（Hampton Downs Motorsport Park）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 伊戈拉赛道（Igora Drive）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- PFI 卡丁车场（PF International）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 劳西茨赛道（Lausitzring）：OSM 拼出的回路与公布长度偏差 >20%，几何疑似错段，弃用
- 曼达利卡赛道（Mandalika International Street Circuit）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 蒙特布兰科赛道（Circuito Monteblanco）：OSM 回路长度与公布长度偏差 -13.35%（>10%），不收
- 冈山国际赛车场（Okayama International Circuit）：与现有包 aida（TI 赛道 Aida，即冈山国际赛车场旧名）为同一赛道，去重
- 大鹏湾国际赛车场（Penbay International Circuit）：Wikipedia 布局年份 2011–2019，且 OSM 节点标注停业，不收已停用赛道
- 匹兹堡国际赛车场（Pittsburgh International Race Complex）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 昆士兰赛道（Queensland Raceway）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 里卡多·托莫赛道（Circuit Ricardo Tormo）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 美国之路赛道（Road America）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 亚特兰大公路赛道（Road Atlanta）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 萨尔茨堡赛道（Salzburgring）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 森图尔国际赛道（Sentul International Circuit）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 斯洛伐克赛道（Slovakia Ring）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 斯内特顿赛道（Snetterton Circuit）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 悉尼赛车公园（Sydney Motorsport Park）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 陶波赛道（Taupo International Motorsport Park）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- The Bend 赛车场（The Bend Motorsport Park）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
- 筑波赛道（Tsukuba Circuit）：OSM 回路长度与公布长度偏差 -18.01%（>10%），不收
- 犹他赛车园（Utah Motorsports Campus）：OSM 中没有能核实的闭合赛道中心线（无匹配 circuit 关系，raceway 也拼不成闭合回路）
