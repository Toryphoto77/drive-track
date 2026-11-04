import 'package:flutter/material.dart';

import 'card_style.dart';
import 'track_catalog.dart';
import 'track_encyclopedia.dart';
import 'track_widgets.dart';

/// 赛道图鉴详情数据（v1.1.0 图鉴重做）。
///
/// 口径（防编造，与图鉴页一致）：
/// - 历史段落全部用自己的话重写，不原文搬运任何来源；
///   每条详情页底部写参考来源行。
/// - 最快圈速只写核实过的：赛事系列 + 车手 + 车辆 + 圈速 + 年份；
///   核实不到的为 null，界面显示“待核”，绝不编造、不拿别条赛道的圈速顶替。
/// - 办赛历史只写核实过的年份 + 赛事/系列；核实不到的为空，界面显示“待核”。
/// - FIA 等级仅核实过的才写，否则留空不显示。

/// 一条最快圈速（全部字段核实后才填，否则整条为 null）。
class TrackLapRecord {
  final String series;
  final String driver;
  final String car;
  final String lapTime;
  final int year;
  const TrackLapRecord({
    required this.series,
    required this.driver,
    required this.car,
    required this.lapTime,
    required this.year,
  });
}

/// 办赛历史时间线一条。
class TrackEventEntry {
  final int year;
  final String event;
  const TrackEventEntry(this.year, this.event);
}

/// 一条赛道的图鉴详情（历史 + 圈速 + 办赛史 + 来源）。
class TrackGuide {
  final List<String> historyParagraphs;
  final TrackLapRecord? lapRecord;
  /// 绝对最快（排位/测试/表演），与正赛纪录口径不同，不得顶替正赛纪录。
  final TrackLapRecord? outrightLap;
  /// 圈速口径说明（如年份存疑、布局年份段、系列区分）。
  final String lapNote;
  final List<TrackEventEntry> events;
  final String openedYear;
  final String fiaGrade;
  final String sources;
  const TrackGuide({
    required this.historyParagraphs,
    this.lapRecord,
    this.outrightLap,
    this.lapNote = '',
    this.events = const [],
    this.openedYear = '',
    this.fiaGrade = '',
    required this.sources,
  });
}

/// OSM 真实走线（v1.1.0）：仅新 7 条中拉到完整走线且长度对得上的才填；
/// 点列已归一化到 0~1（x 向右、y 向下），按行进方向排列，首点即起终点附近。
/// 拉不到或只有一半的赛道不在此表里，界面继续显示“轮廓待补”。
const Map<String, List<OutlinePoint>> trackOsmOutlines = {
  'monaco': [
    OutlinePoint(0.000, 0.702),
    OutlinePoint(0.033, 0.479),
    OutlinePoint(0.677, 0.353),
    OutlinePoint(0.729, 0.296),
    OutlinePoint(0.653, 0.196),
    OutlinePoint(0.665, 0.160),
    OutlinePoint(0.822, 0.000),
    OutlinePoint(0.917, 0.103),
    OutlinePoint(0.887, 0.028),
    OutlinePoint(1.000, 0.005),
    OutlinePoint(0.968, 0.198),
    OutlinePoint(0.819, 0.347),
    OutlinePoint(0.666, 0.412),
    OutlinePoint(0.465, 0.447),
    OutlinePoint(0.455, 0.472),
    OutlinePoint(0.093, 0.512),
    OutlinePoint(0.056, 0.621),
    OutlinePoint(0.133, 0.806),
    OutlinePoint(0.105, 0.843),
    OutlinePoint(0.239, 0.996),
    OutlinePoint(0.128, 1.000),
    OutlinePoint(0.060, 0.901),
    OutlinePoint(0.001, 0.707),
  ],
  'sepang': [
    OutlinePoint(0.554, 0.515),
    OutlinePoint(0.034, 0.566),
    OutlinePoint(0.000, 0.530),
    OutlinePoint(0.018, 0.494),
    OutlinePoint(0.091, 0.492),
    OutlinePoint(0.045, 0.340),
    OutlinePoint(0.086, 0.192),
    OutlinePoint(0.469, 0.000),
    OutlinePoint(0.541, 0.299),
    OutlinePoint(0.629, 0.345),
    OutlinePoint(0.741, 0.262),
    OutlinePoint(0.814, 0.268),
    OutlinePoint(1.000, 0.519),
    OutlinePoint(0.972, 0.626),
    OutlinePoint(0.555, 0.690),
    OutlinePoint(0.641, 0.818),
    OutlinePoint(0.633, 0.914),
    OutlinePoint(0.583, 1.000),
    OutlinePoint(0.367, 0.806),
    OutlinePoint(0.191, 0.856),
    OutlinePoint(0.100, 0.786),
    OutlinePoint(0.112, 0.727),
    OutlinePoint(0.840, 0.566),
    OutlinePoint(0.865, 0.534),
    OutlinePoint(0.838, 0.492),
    OutlinePoint(0.679, 0.505),
  ],
  'bathurst': [
    OutlinePoint(0.981, 0.029),
    OutlinePoint(0.624, 0.000),
    OutlinePoint(0.478, 0.502),
    OutlinePoint(0.421, 0.517),
    OutlinePoint(0.215, 0.453),
    OutlinePoint(0.142, 0.462),
    OutlinePoint(0.134, 0.479),
    OutlinePoint(0.190, 0.532),
    OutlinePoint(0.174, 0.594),
    OutlinePoint(0.036, 0.669),
    OutlinePoint(0.000, 0.719),
    OutlinePoint(0.009, 0.759),
    OutlinePoint(0.109, 0.848),
    OutlinePoint(0.443, 0.876),
    OutlinePoint(0.476, 0.900),
    OutlinePoint(0.518, 0.905),
    OutlinePoint(0.629, 0.953),
    OutlinePoint(0.684, 1.000),
    OutlinePoint(0.712, 0.990),
    OutlinePoint(0.785, 0.912),
    OutlinePoint(0.910, 0.410),
    OutlinePoint(0.997, 0.291),
    OutlinePoint(0.952, 0.239),
    OutlinePoint(1.000, 0.041),
    OutlinePoint(0.983, 0.029),
  ],
};

/// 图鉴详情数据表（key = EncyclopediaTrack.id）。
/// 新 7 条先用图鉴已核实的历史/赛事改写；原 14 条历史与圈速在研究员
/// 核查回执后填实，在此之前一律待核，不写推测。
const Map<String, TrackGuide> trackGuides = {
  'shanghai': TrackGuide(
    historyParagraphs: [
      '位于上海嘉定的赛车场，2004 年启用，由 Hermann Tilke 设计，全长 5.451 公里、16 个弯，布局灵感被描述为汉字“上”字，约 1.2 公里长直道接 14 号发夹弯是主要超车点。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Michael Schumacher', car: 'Ferrari F2004', lapTime: '1:32.238', year: 2004),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Oscar Piastri', car: 'McLaren', lapTime: '1:30.641', year: 2025),
    events: [
      TrackEventEntry(2004, 'F1 中国大奖赛首办'),
      TrackEventEntry(2019, 'F1 中国大奖赛（2019 年前最后一届）'),
      TrackEventEntry(2024, 'F1 中国大奖赛回归'),
      TrackEventEntry(2025, '赛道全面重铺后办 F1'),
    ],
    openedYear: '2004',
    sources: '参考：Formula1.com、维基百科',
  ),
  'zhuhai': TrackGuide(
    historyParagraphs: [
      '位于广东珠海的赛车场，1996 年 11 月启用，是中国内地第一条永久性国际赛道，FIA 二级，全长 4.319 公里、14 个弯。',
    ],
    lapRecord: TrackLapRecord(series: '洲际勒芒杯（ILMC）', driver: 'Franck Montagny', car: 'Peugeot 908 HDi FAP', lapTime: '1:22.296', year: 2010),
    outrightLap: TrackLapRecord(series: 'ILMC 排位赛', driver: 'Anthony Davidson', car: 'Peugeot 908', lapTime: '1:21.769', year: 2011),
    events: [
      TrackEventEntry(1996, '启用；BPR Global GT'),
      TrackEventEntry(2007, 'A1GP（2007–08 赛季）'),
      TrackEventEntry(2010, '洲际勒芒杯珠海站'),
      TrackEventEntry(2011, '洲际勒芒杯珠海站'),
    ],
    openedYear: '1996',
    sources: '参考：维基百科、珠海官网（zic.com.cn）',
  ),
  'ningbo': TrackGuide(
    historyParagraphs: [
      '位于浙江宁波的赛车场，2017 年启用，由 Alan Wilson 设计，建于旧采石场故地，地势起伏，FIA 二级，全长约 4.01 公里。',
    ],
    lapRecord: TrackLapRecord(series: 'Formula Regional', driver: 'Jake Hughes', car: 'Tatuus F3 T318-Alfa Romeo', lapTime: '1:40.798', year: 2018),
    lapNote: '房车线另记：WTCR 正赛 1:51.640（Thed Björk，Hyundai i30 N TCR，2018 年），与方程式纪录口径不同。',
    events: [
      TrackEventEntry(2017, '中国 F4 开幕赛；WTCC 中国站'),
      TrackEventEntry(2018, 'WTCR'),
      TrackEventEntry(2019, 'WTCR'),
      TrackEventEntry(2022, 'WTCR'),
    ],
    openedYear: '2017',
    sources: '参考：Motor Sport Magazine 数据库、51GT3',
  ),
  'zhejiang': TrackGuide(
    historyParagraphs: [
      '位于浙江绍兴的赛车场，2016 年启用，设计方为英国 Apex Circuit Design，FIA 二级，全长 3.200 公里、16 个弯，可拆为东、西两条短布局，高差约 22 米，属多弯起伏型赛道。',
    ],
    lapRecord: TrackLapRecord(series: 'LMP3', driver: 'Leo Ye（叶弘历）', car: 'Ligier JS P3', lapTime: '1:26.922', year: 2017),
    lapNote: '年份存疑：另有来源把同一成绩记为 2022 年，车手、车型、成绩一致，年份待二次核对。另注：NIO EP9 的 1:26.180（2021 年）为厂商测试圈，非正赛成绩，不顶替。',
    events: [
      TrackEventEntry(2016, '启用'),
      TrackEventEntry(2017, 'TCR 国际系列赛、TCR 亚洲、Blancpain GT 亚洲系列赛'),
      TrackEventEntry(2026, 'TCR 世界巡回赛浙江站（排期）'),
    ],
    openedYear: '2016',
    sources: '参考：维基百科、Motor Sport Magazine',
  ),
  'tianma': TrackGuide(
    historyParagraphs: [
      '位于上海松江的赛车场，2004 年与上赛同年启用，全长仅 2.063 公里，短而多弯，附带越野场、试验场等汽车主题园区设施。',
    ],
    lapRecord: TrackLapRecord(series: 'TCR 中国站', driver: 'Ma Qinghua（马青骅）', car: 'Lynk & Co 03 TCR', lapTime: '1:06.007', year: 2020),
    events: [
      TrackEventEntry(2004, '启用'),
      TrackEventEntry(2011, 'WTCC 中国站'),
      TrackEventEntry(2020, 'TCR 中国站'),
    ],
    openedYear: '2004',
    sources: '参考：维基百科、Motor Sport Magazine',
  ),
  'ordos': TrackGuide(
    historyParagraphs: [
      '位于内蒙古鄂尔多斯康巴什的赛车场，2010 年启用，全长 3.751 公里、18 个弯，布局被描述为马匹造型，看台顶棚似鹰。',
    ],
    lapRecord: TrackLapRecord(series: 'Superleague Formula', driver: 'Ben Hanley', car: 'Panoz DP09', lapTime: '1:30.021', year: 2010),
    events: [
      TrackEventEntry(2010, 'CTCC 首届；Superleague Formula'),
      TrackEventEntry(2011, 'FIA GT1 世锦赛'),
      TrackEventEntry(2012, 'Audi R8 LMS Cup'),
      TrackEventEntry(2013, 'Porsche Carrera Cup Asia'),
    ],
    openedYear: '2010',
    sources: '参考：维基百科、Motor Sport Magazine',
  ),
  'nordschleife': TrackGuide(
    historyParagraphs: [
      '位于德国纽博格林的北环，1927 年 6 月启用，现行北环 20.832 公里、73 个弯、高差逾 300 米，被 Jackie Stewart 称为“绿色地狱”；24 小时赛用“大奖赛赛道 + 北环”组合布局。',
    ],
    outrightLap: TrackLapRecord(series: '官方计时挑战（非正赛）', driver: 'Timo Bernhard', car: 'Porsche 919 Hybrid Evo', lapTime: '5:19.546', year: 2018),
    lapNote: '北环没有一条可与现代大奖赛赛道直接对标的纯北环正赛纪录，故正赛纪录标待核；量产车标杆另记：Mercedes-AMG One 6:29.090（2024 年）。',
    events: [
      TrackEventEntry(1927, '启用'),
      TrackEventEntry(1970, '纽博格林 24 小时耐力赛起'),
      TrackEventEntry(1976, 'F1 德国大奖赛最后一年用北环'),
      TrackEventEntry(1984, '现代大奖赛赛道起承接 F1 / DTM 等'),
    ],
    openedYear: '1927',
    sources: '参考：纽博格林官网、维基百科',
  ),
  'spa': TrackGuide(
    historyParagraphs: [
      '位于比利时斯帕-弗朗科尚的赛道，1921 年由公共道路三角布局构成，1979 年缩短重建为约 7 公里现代布局，现行 7.004 公里、19 个弯，是 F1 现行最长赛道，Eau Rouge–Raidillon 组合是其标志。',
    ],
    outrightLap: TrackLapRecord(series: 'F1 冲刺排位赛', driver: 'Oscar Piastri', car: 'McLaren', lapTime: '1:40.510', year: 2025),
    lapNote: '正赛纪录待核：两处来源分别记为 1:46.286（2018 年）与 1:46.196（2022 年），不可能同为纪录，需以 Formula1.com 官方分站正赛最快圈复核后再定。',
    events: [
      TrackEventEntry(1921, '建成（公共道路三角布局）'),
      TrackEventEntry(1925, '首届比利时大奖赛'),
      TrackEventEntry(1950, 'F1 世锦赛比利时站起'),
      TrackEventEntry(1979, '缩短重建为现代布局'),
      TrackEventEntry(1985, 'F1 基本固定于此'),
    ],
    openedYear: '1921',
    sources: '参考：F1Technical、维基百科',
  ),
  'silverstone': TrackGuide(
    historyParagraphs: [
      '位于英国银石的赛道，由二战 RAF 轰炸机训练机场的跑道与环场路改建，1948 年正式办赛，现行大奖赛布局 5.891 公里、18 个弯，Maggotts–Becketts–Chapel 高速组合是其标志。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Max Verstappen', car: 'Red Bull RB16', lapTime: '1:27.097', year: 2020),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Lewis Hamilton', car: 'Mercedes', lapTime: '1:24.303', year: 2020),
    events: [
      TrackEventEntry(1948, '首届英国大奖赛'),
      TrackEventEntry(1950, '首届 F1 世锦赛揭幕战'),
      TrackEventEntry(1987, '固定为英国站主场'),
    ],
    openedYear: '1948',
    sources: '参考：Formula1.com、维基百科',
  ),
  'monza': TrackGuide(
    historyParagraphs: [
      '位于意大利蒙扎公园的赛道，1922 年 110 天建成，初版为公路赛道加高速椭圆组合，椭圆弯道近 30 度倾角，现已停用但遗迹犹存；现行 5.793 公里，以长直道与低阻力调校著称，号称“速度圣殿”。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Rubens Barrichello', car: 'Ferrari', lapTime: '1:21.046', year: 2004),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Lewis Hamilton', car: 'Mercedes W11', lapTime: '1:18.887', year: 2020),
    events: [
      TrackEventEntry(1922, '启用；首届意大利大奖赛'),
      TrackEventEntry(1961, '高速椭圆布局最后一年用于 F1'),
      TrackEventEntry(1980, '意大利站改伊莫拉（唯一例外年份）'),
      TrackEventEntry(2000, '现行布局起'),
    ],
    openedYear: '1922',
    sources: '参考：Formula1.com、维基百科',
  ),
  'suzuka': TrackGuide(
    historyParagraphs: [
      '位于日本铃鹿的赛道，1962 年 9 月启用，原为本田测试场，由本田宗一郎主导兴建，荷兰人 John Hugenholtz 设计，5.807 公里、18 个弯，全球罕见的“8”字布局，后直道以高架桥跨越前段，S 弯、130R、卡西欧三角减速弯为标志。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Andrea Kimi Antonelli', car: 'Mercedes', lapTime: '1:30.965', year: 2025),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Max Verstappen', car: 'Red Bull', lapTime: '1:26.983', year: 2025),
    events: [
      TrackEventEntry(1962, '启用（本田测试场）'),
      TrackEventEntry(1987, 'F1 日本大奖赛起'),
      TrackEventEntry(2009, 'F1 日本大奖赛回归'),
    ],
    openedYear: '1962',
    sources: '参考：Total Motorsport、维基百科',
  ),
  'laguna_seca': TrackGuide(
    historyParagraphs: [
      '位于美国加利福尼亚的赛道，1957 年建于干湖床（西班牙语 Laguna Seca 即“干湖”），取代因事故被禁的圆石滩公路赛；1988 年加建内场段后成现行 3.602 公里、11 个弯，8/8A 号“Corkscrew”盲顶左-右急坠约 18 米是其标志。',
    ],
    lapRecord: TrackLapRecord(series: 'IndyCar', driver: 'Álex Palou', car: 'Dallara DW12', lapTime: '1:08.4168', year: 2023),
    outrightLap: TrackLapRecord(series: 'Ferrari Racing Days 表演（非正赛）', driver: 'Marc Gené', car: 'Ferrari F2003-GA', lapTime: '1:05.786', year: 2012),
    events: [
      TrackEventEntry(1957, '首赛（SCCA）'),
      TrackEventEntry(1983, 'CART / Champ Car 起'),
      TrackEventEntry(2005, 'MotoGP 美国站回归（至 2013 年）'),
      TrackEventEntry(2019, 'IndyCar 回归'),
    ],
    openedYear: '1957',
    sources: '参考：维基百科',
  ),
  'cota': TrackGuide(
    historyParagraphs: [
      '位于美国得克萨斯奥斯汀的赛道，2012 年启用，由 Hermann Tilke 牵头设计，5.513 公里、20 个弯，1 号弯陡坡爬升、模仿多条名赛道弯角组合是其设计特点。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Charles Leclerc', car: 'Ferrari SF90', lapTime: '1:36.169', year: 2019),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Valtteri Bottas', car: 'Mercedes', lapTime: '1:32.029', year: 2019),
    events: [
      TrackEventEntry(2012, '启用；F1 美国站首秀'),
      TrackEventEntry(2013, 'MotoGP 美洲站起'),
      TrackEventEntry(2021, 'F1 与 MotoGP 恢复举办（2020 年因疫情停办）'),
    ],
    openedYear: '2012',
    sources: '参考：Formula1.com、维基百科',
  ),
  'fuji': TrackGuide(
    historyParagraphs: [
      '位于日本富士山脚的赛道，1965 年启用，2000 年丰田收购后委托 Tilke 于 2003–2005 年重建为现行 4.563 公里、16 个弯布局，旧高速倾斜弯被取消，保留约 1.475 公里主直道，为全球最长直道之一。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Felipe Massa', car: 'Ferrari F2008', lapTime: '1:18.426', year: 2008),
    lapNote: 'WEC 线另记：LMP1 正赛 1:27.759（Mark Webber，Porsche 919 Hybrid，2014 年），与 F1 纪录口径不同；旧布局纪录与现行布局不可比。',
    events: [
      TrackEventEntry(1965, '启用'),
      TrackEventEntry(1976, 'F1 日本大奖赛（1976–1977 年）'),
      TrackEventEntry(2007, 'F1 日本大奖赛回归（现行布局，2007–2008 年）'),
      TrackEventEntry(2012, 'WEC 富士 6 小时起'),
    ],
    openedYear: '1965',
    sources: '参考：维基百科、FIA WEC',
  ),
  'chengdu_tianfu': TrackGuide(
    historyParagraphs: [
      '位于成都东部新区简州新城的赛车场，为替代 2007–2019 年的成都金港（成都国际赛车场）而建，2023 年 12 月 1 日开放。一期西赛道按 FIA 二级标准建设，19 个弯中 12 个左弯、7 个右弯，落差约 20 米。',
    ],
    lapRecord: TrackLapRecord(series: 'F4 中国站', driver: 'Oscar Pedersen', car: 'Mygale M21-F4', lapTime: '1:21.413', year: 2024),
    events: [
      TrackEventEntry(2023, '开放；中国耐力锦标赛收官战'),
      TrackEventEntry(2024, 'F4 中国锦标赛起'),
      TrackEventEntry(2026, 'TCR 世界巡回赛成都站（排期）'),
    ],
    openedYear: '2023',
    sources: '参考：Wikipedia、racetrackworld.com',
  ),
  'goldenport': TrackGuide(
    historyParagraphs: [
      '位于北京朝阳金盏、首都机场附近的赛车场，2001 年 12 月建成，由澳大利亚设计师 Michael McDonough 设计，短而多弯、高速段少，长约 2.39 公里。',
      '弯道数来源有冲突：英文资料作 12 弯，国内资料作 16 弯，本条不二选一，弯道数标待核；建成年份另有资料记为 1999 年，亦存疑。',
    ],
    outrightLap: TrackLapRecord(series: 'FIA GT1 排位赛', driver: 'Maxime Martin / Bertrand Baguette', car: 'Matech Ford GT1', lapTime: '1:00.344', year: 2011),
    lapNote: '全场正赛纪录待核：另有 1:01.844（测试口径）等说法均未核实为正赛纪录，不采纳；系列正赛另记：WTCC 正赛 1:05.382（Tom Chilton，Chevrolet Cruze TC1，2014 年北京站）。',
    events: [
      TrackEventEntry(2001, '建成'),
      TrackEventEntry(2011, 'FIA GT1 世锦赛'),
      TrackEventEntry(2014, 'WTCC 北京站'),
      TrackEventEntry(2015, 'F4 中国锦标赛揭幕战'),
    ],
    openedYear: '2001',
    sources: '参考：Wikipedia、racingcircuits.info（弯道数来源冲突，标待核）',
  ),
  'guangdong_gic': TrackGuide(
    historyParagraphs: [
      '位于广东肇庆四会大旺的赛车场，2009 年 12 月正式开始运营，按 FIA F3 级别设计建造，13 个弯中 5 个左弯、8 个右弯，顺时针，以低速紧弯多著称。注意勿与珠海混淆：广东国际赛车场在肇庆，珠海国际赛车场在珠海。',
    ],
    lapRecord: TrackLapRecord(series: 'Formula Abarth', driver: 'Parth Ghorpade', car: 'Tatuus FA010', lapTime: '1:14.318', year: 2012),
    events: [
      TrackEventEntry(2009, '开始运营；CTCC'),
      TrackEventEntry(2010, 'Formula BMW Pacific'),
      TrackEventEntry(2012, 'Formula Pilota China'),
      TrackEventEntry(2017, 'TCR China'),
    ],
    openedYear: '2009',
    sources: '参考：Wikipedia、racetrackworld.com',
  ),
  'monaco': TrackGuide(
    historyParagraphs: [
      '位于蒙特卡洛的城市街道赛道，首届摩纳哥大奖赛 1929 年举行，1950 年起成为 F1 世锦赛分站。赛道沿港口与市区街道布置，顺时针，3.337 公里、19 个弯、高差约 44 米，Fairmont 发夹弯约 48 公里/小时为 F1 最慢弯，隧道段约 260 公里/小时，全程护栏、几乎无缓冲区。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Lewis Hamilton', car: 'Mercedes W12', lapTime: '1:12.909', year: 2021),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Lando Norris', car: 'McLaren', lapTime: '1:09.954', year: 2025),
    events: [
      TrackEventEntry(1929, '首届摩纳哥大奖赛'),
      TrackEventEntry(1950, '成为 F1 世锦赛分站'),
    ],
    openedYear: '1929（首届大奖赛）',
    sources: '参考：racetrackworld.com、mercedesamgf1.com、Formula1.com',
  ),
  'le_mans': TrackGuide(
    historyParagraphs: [
      '位于法国勒芒的萨尔特赛道，1923 年 5 月 26 日开放，是永久赛道与封闭公共道路混合的布局，现布局自 2018 年起使用，全长 13.626 公里、38 个弯；Mulsanne 直道（现含减速弯）、Porsche 弯、Dunlop 弯为标志，布加迪短布局位于其内侧。',
    ],
    lapRecord: TrackLapRecord(series: 'WEC 勒芒 24 小时（现行布局）', driver: 'Mike Conway', car: 'Toyota TS050 Hybrid', lapTime: '3:17.297', year: 2019),
    outrightLap: TrackLapRecord(series: 'WEC 排位赛', driver: 'Kamui Kobayashi', car: 'Toyota TS050 Hybrid', lapTime: '3:14.791', year: 2017),
    lapNote: '布局口径提醒：3:17.475（2015 年）是 2007–2017 布局的纪录，不是现行布局纪录，本条用现行布局 3:17.297。',
    events: [
      TrackEventEntry(1923, '开放；首届勒芒 24 小时'),
      TrackEventEntry(1949, '勒芒 24 小时恢复并延续至今'),
      TrackEventEntry(2018, '现布局开始使用'),
    ],
    openedYear: '1923',
    sources: '参考：Wikipedia、racetrackworld.com、Toyota Gazoo',
  ),
  'sepang': TrackGuide(
    historyParagraphs: [
      '位于马来西亚雪邦、吉隆坡国际机场旁的赛车场，1999 年 3 月开放，由 Hermann Tilke 设计，顺时针，5.543 公里、15 个弯，长直道加高速弯组合，是 Tilke 新一代 F1 赛道中的首座。',
    ],
    lapRecord: TrackLapRecord(series: 'F1', driver: 'Sebastian Vettel', car: 'Ferrari SF70H', lapTime: '1:34.080', year: 2017),
    outrightLap: TrackLapRecord(series: 'F1 排位赛', driver: 'Lewis Hamilton', car: 'Mercedes', lapTime: '1:30.076', year: 2017),
    events: [
      TrackEventEntry(1999, '开放；首届 F1 马来西亚大奖赛'),
      TrackEventEntry(2017, '最后一届 F1 马来西亚大奖赛（1999–2017 年，共 19 届）'),
      TrackEventEntry(2022, 'MotoGP 马来西亚站恢复'),
    ],
    openedYear: '1999',
    sources: '参考：racetrackworld.com、维基百科',
  ),
  'bathurst': TrackGuide(
    historyParagraphs: [
      '位于澳大利亚新南威尔士巴瑟斯特的环山赛道，1938 年首办赛事，原为环山观光道路，逆时针，6.213 公里，非比赛日按 60 公里/小时双向通行，高差 174 米，Conrod 直道约 1.9 公里、尾速约 290 公里/小时，The Chase 减速弯为其后段标志。',
    ],
    lapRecord: TrackLapRecord(series: 'Supercars Bathurst 1000', driver: 'Chaz Mostert', car: 'Ford Mustang GT', lapTime: '2:04.7602', year: 2019),
    outrightLap: TrackLapRecord(series: 'Supercars Top 10 Shootout（排位）', driver: 'Chaz Mostert', car: 'Ford Mustang', lapTime: '2:03.373', year: 2021),
    lapNote: '口径提醒：Supercars 官网把 2:03.373 标为“Lap Record”，实为 Shootout 排位圈，勿当作正赛纪录；Gen3 时代正赛纪录另记 2:06.7265（Will Brown，Chevrolet Camaro，2025 年）。启用具体日来源不一（道路开通与首赛周末），本条只写 1938 年。',
    events: [
      TrackEventEntry(1938, '首办赛事'),
      TrackEventEntry(1963, 'Bathurst 1000 迁至此并延续至今'),
      TrackEventEntry(1991, 'Bathurst 12 小时起'),
    ],
    openedYear: '1938',
    sources: '参考：racetrackworld.com、V8Sleuth',
  ),
};

TrackGuide guideFor(EncyclopediaTrack t) {
  final g = trackGuides[t.id];
  if (g != null) return g;
  return TrackGuide(
    historyParagraphs: const ['历史资料：待核'],
    events: const [],
    sources: t.source,
  );
}

/// 通用轮廓图：画任意归一化点列（用于 OSM 走线；目录轮廓仍走
/// TrackSchematicDiagram，不存在第二套目录轮廓）。
class OutlineDiagram extends StatelessWidget {
  final List<OutlinePoint> outline;
  final double height;
  final String? caption;
  const OutlineDiagram({
    super.key,
    required this.outline,
    this.height = 220,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: CustomPaint(painter: _OutlinePainter(outline)),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption!,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _OutlinePainter extends CustomPainter {
  final List<OutlinePoint> outline;
  _OutlinePainter(this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.length < 3) return;
    const pad = 14.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset toOffset(OutlinePoint p) => Offset(pad + p.x * w, pad + p.y * h);
    final pts = outline.map(toOffset).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE10600)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    // 起终点：白芯红边圆点。
    canvas.drawCircle(
      pts.first,
      6,
      Paint()..color = const Color(0xFFE10600),
    );
    canvas.drawCircle(
      pts.first,
      3,
      Paint()..color = Colors.white,
    );
    // 方向箭头：沿第一段方向画在起终点后一小段处。
    final d = pts[1] - pts.first;
    final len = d.distance;
    if (len > 1) {
      final u = d / len;
      final mid = pts.first + u * 18;
      final normal = Offset(-u.dy, u.dx);
      final tip = Offset(mid.dx + u.dx * 7, mid.dy + u.dy * 7);
      final left = Offset(
        mid.dx - u.dx * 5 + normal.dx * 5,
        mid.dy - u.dy * 5 + normal.dy * 5,
      );
      final right = Offset(
        mid.dx - u.dx * 5 - normal.dx * 5,
        mid.dy - u.dy * 5 - normal.dy * 5,
      );
      final arrow = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()..color = const Color(0xFFE10600),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter old) =>
      old.outline != outline;
}

/// 赛道图鉴详情页（v1.1.0 新 UI：深色 #121212 + 法拉利红，与 App 一致）。
class TrackDetailPage extends StatelessWidget {
  final EncyclopediaTrack track;
  final ValueChanged<TrackInfo>? onSelectCatalogTrack;
  const TrackDetailPage({
    super.key,
    required this.track,
    this.onSelectCatalogTrack,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final catalog = track.catalog;
    final guide = guideFor(track);
    final osm = trackOsmOutlines[track.id];
    final corners = track.resolvedCorners;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(track.nameCn),
        backgroundColor: const Color(0xFF121212),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部大轮廓图。
            if (osm != null)
              OutlineDiagram(
                outline: osm,
                height: 220,
                caption: '轮廓来源：OpenStreetMap（© OpenStreetMap contributors，ODbL），已简化',
              )
            else if (catalog != null && track.hasOutline)
              TrackSchematicDiagram(
                track: catalog,
                height: 220,
                showCorners: true,
                showSectors: true,
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const Center(
                  child: Text(
                    '轮廓待补',
                    style: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ),
              ),
            if (catalog == null && osm == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '未按公开布局重绘或未拉到完整 OSM 走线，暂不展示示意图，以免编造轮廓。',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              track.nameCn,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.nameEn,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 12),
            // 信息条。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(track.location),
                _infoChip(track.lengthLabel),
                _infoChip(
                  corners == null ? '弯道数：待核' : '共 $corners 弯',
                ),
                if (catalog != null && catalog.direction.isNotEmpty)
                  _infoChip('${catalog.direction}'),
                if (catalog != null && catalog.shapeNote.isNotEmpty)
                  _infoChip(catalog.shapeNote),
                if (guide.openedYear.isNotEmpty)
                  _infoChip('开业：${guide.openedYear}'),
                if (guide.fiaGrade.isNotEmpty)
                  _infoChip('FIA 等级：${guide.fiaGrade}'),
              ],
            ),
            const SizedBox(height: 16),
            // 历史资料。
            _sectionTitle('历史资料', accent),
            const SizedBox(height: 8),
            for (final p in guide.historyParagraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  p,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 最快圈速。
            _sectionTitle('最快圈速', accent),
            const SizedBox(height: 8),
            DriveTrackInnerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (guide.lapRecord != null) ...[
                    const Text(
                      '正赛纪录',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    Text(
                      guide.lapRecord!.lapTime,
                      style: TextStyle(
                        color: accent,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${guide.lapRecord!.series} · ${guide.lapRecord!.year}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${guide.lapRecord!.driver} · ${guide.lapRecord!.car}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ] else
                    const Text(
                      '正赛纪录：待核',
                      style: TextStyle(color: Colors.white54, fontSize: 15),
                    ),
                  if (guide.outrightLap != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '绝对最快（排位 / 测试 / 表演，非正赛纪录）',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      guide.outrightLap!.lapTime,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${guide.outrightLap!.series} · ${guide.outrightLap!.year}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${guide.outrightLap!.driver} · ${guide.outrightLap!.car}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (guide.lapNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      guide.lapNote,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // 办赛历史时间线。
            _sectionTitle('办赛历史', accent),
            const SizedBox(height: 8),
            if (guide.events.isEmpty)
              const Text(
                '办赛历史：待核',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              )
            else
              for (final e in guide.events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${e.year}',
                          style: TextStyle(
                            color: accent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.event,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              '参考来源：${guide.sources}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (catalog != null && onSelectCatalogTrack != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  onSelectCatalogTrack!(catalog);
                  Navigator.of(context).pop();
                },
                child: const Text('在赛道模式中使用该赛道'),
              ),
            ] else if (catalog == null) ...[
              const SizedBox(height: 20),
              const Text(
                '该赛道尚未接入赛道模式，选赛道仍走原有赛道选择器（目录 14 条）。',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _sectionTitle(String title, Color accent) {
    return Row(
      children: [
        Container(width: 4, height: 18, color: accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
