/// 赛道目录（赛道模式专用）。
///
/// 数据与版权说明（v0.1.7 赛道重绘版）：
/// - 长度一律按“约”理解：数值取自公开资料（见各条目的 [source]，仅写网站名），
///   不同年份、不同布局的公布值会有出入，界面必须显示“约 X km”，不得当成
///   官方精确测绘值使用。本次重绘未改动任何一条赛道的长度数值（逐条核对见回执）。
/// - **轮廓为按公开布局重绘的示意图，非官网原图**：本文件只含按各赛道官网 /
///   公开资料公布的布局（弯道数量与走向、起终点位置、主直道与标志性弯角）
///   重新手绘的归一化矢量点列，绝没有直接下载、打包或描摹任何官网的版权
///   赛道图图片。轮廓仅用于在选择器 / 详情页示意赛道大致走向，不得用于
///   导航、计时判定或任何精确测量。
/// - 弯道编号点（[corners]）只标主要弯道：点位落在对应轮廓段附近，是示意
///   位置，不是官方测绘坐标；未标出的弯道不代表不存在（总数见 [totalCorners]）。
/// - 起终点（[startFinishPoint]）与轮廓第一个点重合，即轮廓从起终点线开始
///   按行进方向画；走向说明见 [startFinishNote]。本目录故意不含任何赛道的
///   起终点经纬度：公开资料里的起终点坐标未经核实，编造坐标会直接导致
///   计时错圈。起终点计时仍由用户在赛道页实地点选
///   （见 lib/track_timing.dart 的 LapTimer 入参），或由总协调后续接入
///   经核实的官方数据后再补。
/// - 分段点（[sectorPoints]）：每一点是一段的结束位置；2 个点 = S1/S2/S3
///   三段，1 个点 = S1/S2 两段，0 个点 = 无公开分段点，App 仅以前后半圈示意
///   （原因见各条目的 [sectorNote]）。分段点同样是按公开分段描述确定的
///   示意位置，不是官方计时线；计时分段仍以 LapTimer 实地 sectorPoints 为准。
/// - 查不到可靠信息的弯道名 / 分段点不编造：弯道名留空只标编号，
///   分段点留空并在 [sectorNote] 写明原因；[direction] 留空表示走向待核。

/// 归一化轮廓点：x 向右、y 向下，取值 0~1。
/// 绘制时把点列连成闭合多边形即可（首尾不用重复写第一个点）。
class OutlinePoint {
  final double x;
  final double y;
  const OutlinePoint(this.x, this.y);
}

/// 一个主要弯道的示意标注点。
class CornerMark {
  /// 官方弯道号；为 0 表示该点是知名路段名（如纽北 Karussell），
  /// 无统一官方编号，界面只显示路段名、不显示编号。
  final int number;

  /// 在轮廓上的示意位置（归一化坐标）。
  final OutlinePoint point;

  /// 弯道 / 路段名；查不到可靠名称时留空，界面只显示编号。
  final String name;

  const CornerMark(this.number, this.point, [this.name = '']);

  /// 界面用标注：有编号显示“T1”，有名显示“T1 · 名”，无编号只显示名。
  String get label {
    if (number <= 0) return name;
    if (name.isEmpty) return 'T$number';
    return 'T$number · $name';
  }
}

/// 一条赛道目录条目。
class TrackInfo {
  /// 稳定 id，供 Trip.trackId 引用，如 'shanghai'、'nordschleife'。
  final String id;

  /// 中文名。
  final String nameCn;

  /// 英文名。
  final String nameEn;

  /// 国家 / 地区。
  final String region;

  /// 长度（km，约数）。界面一律显示为“约 $lengthKm km”。
  /// 若某天查不到可靠公开值，改为 null，界面显示“约？/待核”，不得编数。
  final double? lengthKm;

  /// 长度来源（网站名即可），如 'formula1.com'、'Wikipedia'。
  final String source;

  /// 重绘轮廓点列：按公开布局重绘的示意图，非官网原图；
  /// 第一个点即起终点线位置，点列按行进方向排列。
  final List<OutlinePoint> outline;

  /// 官方弯道总数；为 0 表示总数待核。图中只标 [corners] 里的主要弯道。
  final int totalCorners;

  /// 主要弯道标注点（至少主要弯道，含弯道号与归一化坐标）。
  final List<CornerMark> corners;

  /// 起终点线位置（归一化坐标，与 outline 第一个点重合）；
  /// 为 null 表示起终点位置待核。
  final OutlinePoint? startFinishPoint;

  /// 起终点走向说明，如“主直道中段，顺时针发车”。
  final String startFinishNote;

  /// 分段点：每一点是一段的结束位置（见文件头说明）。
  final List<OutlinePoint> sectorPoints;

  /// 分段说明：分段依据，或无公开分段点的原因。
  final String sectorNote;

  /// 行进方向，如“顺时针”“逆时针”；留空表示待核。
  final String direction;

  /// 走向特征一句话，如“上字形”“8 字交叉”。
  final String shapeNote;

  /// 布局参考来源（网站名 / 公开资料名）；留空时界面回落到 [source]。
  final String layoutSource;

  /// 本条轮廓是否为本次按公开布局重绘（true）还是旧的简单示意（false）。
  final bool redrawn;

  const TrackInfo({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.region,
    required this.lengthKm,
    required this.source,
    required this.outline,
    this.totalCorners = 0,
    this.corners = const [],
    this.startFinishPoint,
    this.startFinishNote = '',
    this.sectorPoints = const [],
    this.sectorNote = '',
    this.direction = '',
    this.shapeNote = '',
    this.layoutSource = '',
    this.redrawn = false,
  });

  /// 界面用长度文案：有值显示“约 X km”，无值显示“约？/待核”。
  String get lengthLabel =>
      lengthKm == null ? '约？/待核' : '约 ${lengthKm} km';

  /// 是否国内赛道（按 region 判断，供选择器分组用）。
  bool get isDomestic => region == '中国';

  /// 布局来源文案：优先 layoutSource，留空回落到长度来源。
  String get layoutSourceLabel => layoutSource.isEmpty ? source : layoutSource;

  /// 是否有公开分段点（有则按 S1/S2/S3 计，无则前后半圈示意）。
  bool get hasSectorPoints => sectorPoints.isNotEmpty;

  /// 按分段点数生成的分段标签，与 track_viz.dart 的 sectorLabels 口径一致：
  /// 2 个点 = S1/S2/S3，1 个点 = S1/S2，0 个点 = 前半圈/后半圈。
  List<String> get sectorLabels {
    if (sectorPoints.length >= 2) return const ['S1', 'S2', 'S3'];
    if (sectorPoints.length == 1) return const ['S1', 'S2'];
    return const ['前半圈', '后半圈'];
  }

  /// 弯道文案：总数已知时“共 N 弯 · 图中标 M 个”，否则“图中标 M 个”。
  String get cornerLabel {
    if (totalCorners > 0) return '共 $totalCorners 弯 · 图中标 ${corners.length} 个';
    return '图中标 ${corners.length} 个';
  }
}

// 下面每条赛道的 outline 均为按公开布局重绘的 24~48 点轮廓（旧版为 8~14 点），
// 点列从起终点线开始按行进方向排列；弯道点与分段点均落在轮廓段附近。
// 所有轮廓统一标注：轮廓为按公开布局重绘的示意图，非官网原图。

/// 国内赛道目录。
const List<TrackInfo> domesticTracks = [
  TrackInfo(
    id: 'shanghai',
    nameCn: '上海国际赛车场',
    nameEn: 'Shanghai International Circuit',
    region: '中国',
    lengthKm: 5.451,
    source: 'formula1.com',
    layoutSource: 'formula1.com / FIA 赛道图',
    totalCorners: 16,
    direction: '顺时针',
    shapeNote: '上字形：左端收紧蜗牛弯 + 右侧 T11–T13 大回环 + 两条长直道',
    startFinishNote: '主直道中段，顺时针发车；T1–T2 收紧蜗牛弯在左端',
    sectorNote: 'S1 止于 T5 附近（T6 发夹弯前），S2 止于 T10 附近（T11 大回环前）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.60, 0.88),
    sectorPoints: [
      OutlinePoint(0.48, 0.50),
      OutlinePoint(0.84, 0.60),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.12, 0.80), '蜗牛弯'),
      CornerMark(2, OutlinePoint(0.10, 0.62), '蜗牛弯'),
      CornerMark(3, OutlinePoint(0.22, 0.48), '蜗牛弯'),
      CornerMark(6, OutlinePoint(0.56, 0.40), '发夹弯'),
      CornerMark(7, OutlinePoint(0.74, 0.30), '高速左弯'),
      CornerMark(11, OutlinePoint(0.88, 0.42), '大回环'),
      CornerMark(13, OutlinePoint(0.84, 0.60), '大回环'),
      CornerMark(14, OutlinePoint(0.74, 0.70), '发夹弯'),
      CornerMark(16, OutlinePoint(0.66, 0.84), '回主直道'),
    ],
    outline: [
      OutlinePoint(0.600, 0.880),
      OutlinePoint(0.520, 0.885),
      OutlinePoint(0.440, 0.890),
      OutlinePoint(0.360, 0.885),
      OutlinePoint(0.280, 0.880),
      OutlinePoint(0.220, 0.860),
      OutlinePoint(0.160, 0.840),
      OutlinePoint(0.090, 0.740),
      OutlinePoint(0.090, 0.670),
      OutlinePoint(0.090, 0.600),
      OutlinePoint(0.160, 0.500),
      OutlinePoint(0.280, 0.470),
      OutlinePoint(0.360, 0.540),
      OutlinePoint(0.480, 0.500),
      OutlinePoint(0.520, 0.450),
      OutlinePoint(0.560, 0.400),
      OutlinePoint(0.610, 0.360),
      OutlinePoint(0.660, 0.320),
      OutlinePoint(0.780, 0.300),
      OutlinePoint(0.880, 0.360),
      OutlinePoint(0.890, 0.430),
      OutlinePoint(0.900, 0.500),
      OutlinePoint(0.840, 0.600),
      OutlinePoint(0.760, 0.680),
      OutlinePoint(0.680, 0.760),
      OutlinePoint(0.660, 0.840),
    ],
  ),
  TrackInfo(
    id: 'zhuhai',
    nameCn: '珠海国际赛车场',
    nameEn: 'Zhuhai International Circuit',
    region: '中国',
    lengthKm: 4.319,
    source: 'Wikipedia',
    layoutSource: 'zic.com.cn（官网赛道介绍）',
    totalCorners: 14,
    direction: '顺时针',
    shapeNote: '900 米主直道 + 技术型内场中段 + 末端高速弯回主直道',
    startFinishNote: '主直道（900 米）中段，顺时针发车；T1 为主直道末端高速右弯',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.55, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.12, 0.76), '高速右弯'),
      CornerMark(3, OutlinePoint(0.24, 0.46), '高速右弯'),
      CornerMark(4, OutlinePoint(0.48, 0.42), '重刹左弯'),
      CornerMark(9, OutlinePoint(0.70, 0.52), '连续左弯'),
      CornerMark(10, OutlinePoint(0.82, 0.42), '连续左弯'),
      CornerMark(14, OutlinePoint(0.66, 0.80), '全场最快弯'),
    ],
    outline: [
      OutlinePoint(0.550, 0.860),
      OutlinePoint(0.465, 0.865),
      OutlinePoint(0.380, 0.870),
      OutlinePoint(0.220, 0.850),
      OutlinePoint(0.120, 0.760),
      OutlinePoint(0.100, 0.620),
      OutlinePoint(0.180, 0.500),
      OutlinePoint(0.300, 0.420),
      OutlinePoint(0.440, 0.400),
      OutlinePoint(0.540, 0.460),
      OutlinePoint(0.620, 0.560),
      OutlinePoint(0.720, 0.520),
      OutlinePoint(0.820, 0.420),
      OutlinePoint(0.880, 0.300),
      OutlinePoint(0.800, 0.200),
      OutlinePoint(0.720, 0.185),
      OutlinePoint(0.640, 0.170),
      OutlinePoint(0.560, 0.185),
      OutlinePoint(0.480, 0.200),
      OutlinePoint(0.340, 0.240),
      OutlinePoint(0.090, 0.580),
      OutlinePoint(0.085, 0.720),
      OutlinePoint(0.080, 0.880),
      OutlinePoint(0.240, 0.880),
      OutlinePoint(0.400, 0.880),
      OutlinePoint(0.520, 0.880),
      OutlinePoint(0.620, 0.880),
    ],
  ),
  TrackInfo(
    id: 'ningbo',
    nameCn: '宁波国际赛车场',
    nameEn: 'Ningbo International Circuit',
    region: '中国',
    lengthKm: 4.01,
    source: 'sohu.com',
    layoutSource: '51gt3.com',
    totalCorners: 22,
    direction: '逆时针',
    shapeNote: '逆时针山地赛道：前段 T1–T12 走走停停，T13 起连续变速弯 + T17 发夹弯',
    startFinishNote: '主直道中段，逆时针发车（约 850 米主直道接 T1 重刹）',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.58, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.14, 0.80)),
      CornerMark(7, OutlinePoint(0.34, 0.42)),
      CornerMark(12, OutlinePoint(0.74, 0.32)),
      CornerMark(13, OutlinePoint(0.88, 0.42)),
      CornerMark(17, OutlinePoint(0.82, 0.64), '发夹弯'),
      CornerMark(22, OutlinePoint(0.68, 0.78)),
    ],
    outline: [
      OutlinePoint(0.580, 0.860),
      OutlinePoint(0.500, 0.865),
      OutlinePoint(0.420, 0.870),
      OutlinePoint(0.340, 0.865),
      OutlinePoint(0.260, 0.860),
      OutlinePoint(0.200, 0.830),
      OutlinePoint(0.140, 0.800),
      OutlinePoint(0.120, 0.730),
      OutlinePoint(0.100, 0.660),
      OutlinePoint(0.130, 0.590),
      OutlinePoint(0.160, 0.520),
      OutlinePoint(0.220, 0.480),
      OutlinePoint(0.280, 0.440),
      OutlinePoint(0.400, 0.400),
      OutlinePoint(0.500, 0.460),
      OutlinePoint(0.580, 0.560),
      OutlinePoint(0.660, 0.480),
      OutlinePoint(0.700, 0.360),
      OutlinePoint(0.800, 0.300),
      OutlinePoint(0.880, 0.360),
      OutlinePoint(0.880, 0.430),
      OutlinePoint(0.880, 0.500),
      OutlinePoint(0.800, 0.580),
      OutlinePoint(0.840, 0.680),
      OutlinePoint(0.740, 0.740),
      OutlinePoint(0.640, 0.800),
    ],
  ),
  TrackInfo(
    id: 'zhejiang',
    nameCn: '浙江国际赛车场',
    nameEn: 'Zhejiang International Circuit',
    region: '中国',
    lengthKm: 3.20,
    source: 'racetrackworld.com',
    layoutSource: 'manilatimes.net（EXEED 2026 赛道介绍）',
    totalCorners: 16,
    direction: '逆时针',
    shapeNote: '逆时针山地赛道，依山势起伏，连续变速弯为主',
    startFinishNote: '主直道中段，逆时针发车',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.56, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.14, 0.78)),
      CornerMark(5, OutlinePoint(0.30, 0.42)),
      CornerMark(9, OutlinePoint(0.72, 0.32)),
      CornerMark(13, OutlinePoint(0.80, 0.62)),
      CornerMark(16, OutlinePoint(0.66, 0.82)),
    ],
    outline: [
      OutlinePoint(0.560, 0.860),
      OutlinePoint(0.480, 0.865),
      OutlinePoint(0.400, 0.870),
      OutlinePoint(0.320, 0.865),
      OutlinePoint(0.240, 0.860),
      OutlinePoint(0.180, 0.820),
      OutlinePoint(0.120, 0.780),
      OutlinePoint(0.110, 0.710),
      OutlinePoint(0.100, 0.640),
      OutlinePoint(0.130, 0.570),
      OutlinePoint(0.160, 0.500),
      OutlinePoint(0.220, 0.460),
      OutlinePoint(0.280, 0.420),
      OutlinePoint(0.420, 0.400),
      OutlinePoint(0.520, 0.480),
      OutlinePoint(0.480, 0.580),
      OutlinePoint(0.560, 0.640),
      OutlinePoint(0.680, 0.580),
      OutlinePoint(0.660, 0.440),
      OutlinePoint(0.740, 0.340),
      OutlinePoint(0.860, 0.360),
      OutlinePoint(0.880, 0.500),
      OutlinePoint(0.800, 0.600),
      OutlinePoint(0.840, 0.700),
      OutlinePoint(0.740, 0.760),
      OutlinePoint(0.640, 0.800),
    ],
  ),
  TrackInfo(
    id: 'tianma',
    nameCn: '上海天马山赛车场',
    nameEn: 'Shanghai Tianma Circuit',
    region: '中国',
    lengthKm: 2.063,
    source: 'Wikipedia',
    layoutSource: 'racetrackworld.com',
    totalCorners: 14,
    direction: '',
    shapeNote: '紧凑俱乐部赛道：短直道 + 密集内场中速弯，T1 为快速扫弯',
    startFinishNote: '主直道中段发车；走向待核，图中方向仅为示意',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.56, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.14, 0.76), '快速扫弯'),
      CornerMark(5, OutlinePoint(0.32, 0.42)),
      CornerMark(9, OutlinePoint(0.72, 0.36)),
      CornerMark(14, OutlinePoint(0.66, 0.80)),
    ],
    outline: [
      OutlinePoint(0.560, 0.860),
      OutlinePoint(0.480, 0.865),
      OutlinePoint(0.400, 0.870),
      OutlinePoint(0.320, 0.860),
      OutlinePoint(0.240, 0.850),
      OutlinePoint(0.180, 0.805),
      OutlinePoint(0.120, 0.760),
      OutlinePoint(0.110, 0.690),
      OutlinePoint(0.100, 0.620),
      OutlinePoint(0.160, 0.500),
      OutlinePoint(0.220, 0.460),
      OutlinePoint(0.280, 0.420),
      OutlinePoint(0.400, 0.420),
      OutlinePoint(0.480, 0.500),
      OutlinePoint(0.440, 0.600),
      OutlinePoint(0.520, 0.640),
      OutlinePoint(0.640, 0.580),
      OutlinePoint(0.620, 0.440),
      OutlinePoint(0.720, 0.340),
      OutlinePoint(0.840, 0.380),
      OutlinePoint(0.850, 0.450),
      OutlinePoint(0.860, 0.520),
      OutlinePoint(0.780, 0.620),
      OutlinePoint(0.820, 0.720),
      OutlinePoint(0.720, 0.780),
      OutlinePoint(0.640, 0.820),
    ],
  ),
  TrackInfo(
    id: 'ordos',
    nameCn: '鄂尔多斯国际赛车场',
    nameEn: 'Ordos International Circuit',
    region: '中国',
    lengthKm: 3.751,
    source: 'Wikipedia',
    layoutSource: 'Wikipedia',
    totalCorners: 18,
    direction: '顺时针',
    shapeNote: '奔马形：T1 类上海大奖赛道长右弯开局 + 长后直道 + 多发夹弯',
    startFinishNote: '主直道中段，顺时针发车；T1 为长右弯接急左弯',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.58, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.16, 0.78), '长右弯'),
      CornerMark(6, OutlinePoint(0.36, 0.40)),
      CornerMark(10, OutlinePoint(0.78, 0.32)),
      CornerMark(14, OutlinePoint(0.80, 0.62)),
      CornerMark(18, OutlinePoint(0.68, 0.82)),
    ],
    outline: [
      OutlinePoint(0.580, 0.860),
      OutlinePoint(0.500, 0.865),
      OutlinePoint(0.420, 0.870),
      OutlinePoint(0.340, 0.865),
      OutlinePoint(0.260, 0.860),
      OutlinePoint(0.140, 0.780),
      OutlinePoint(0.120, 0.710),
      OutlinePoint(0.100, 0.640),
      OutlinePoint(0.120, 0.570),
      OutlinePoint(0.140, 0.500),
      OutlinePoint(0.240, 0.420),
      OutlinePoint(0.360, 0.380),
      OutlinePoint(0.480, 0.420),
      OutlinePoint(0.520, 0.520),
      OutlinePoint(0.460, 0.600),
      OutlinePoint(0.560, 0.640),
      OutlinePoint(0.680, 0.580),
      OutlinePoint(0.660, 0.510),
      OutlinePoint(0.640, 0.440),
      OutlinePoint(0.720, 0.320),
      OutlinePoint(0.840, 0.340),
      OutlinePoint(0.880, 0.480),
      OutlinePoint(0.800, 0.580),
      OutlinePoint(0.840, 0.680),
      OutlinePoint(0.740, 0.740),
      OutlinePoint(0.660, 0.800),
    ],
  ),
];

/// 国外赛道目录。
const List<TrackInfo> overseasTracks = [
  TrackInfo(
    id: 'nordschleife',
    nameCn: '纽博格林北环',
    nameEn: 'Nürburgring Nordschleife',
    region: '德国',
    lengthKm: 20.832,
    source: 'nuerburgring.de',
    layoutSource: 'nuerburgring.de / 51gt3.com',
    totalCorners: 73,
    direction: '顺时针',
    shapeNote: '长而曲折的林间长圈：起伏 + 连续变向 + 末端 2.1 km Döttinger Höhe 长直道',
    startFinishNote: '主直道（Döttinger Höhe 末端）附近，顺时针发车',
    sectorNote: '无公开分段点：长圈布局随赛事而异，分段线不固定，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.62, 0.86),
    corners: [
      CornerMark(0, OutlinePoint(0.20, 0.36), 'Flugplatz'),
      CornerMark(0, OutlinePoint(0.16, 0.56), 'Fuchsröhre'),
      CornerMark(0, OutlinePoint(0.36, 0.28), 'Bergwerk'),
      CornerMark(0, OutlinePoint(0.56, 0.20), 'Karussell'),
      CornerMark(0, OutlinePoint(0.76, 0.22), 'Brünnchen'),
      CornerMark(0, OutlinePoint(0.88, 0.50), 'Döttinger Höhe'),
    ],
    outline: [
      OutlinePoint(0.620, 0.860),
      OutlinePoint(0.550, 0.870),
      OutlinePoint(0.480, 0.880),
      OutlinePoint(0.360, 0.840),
      OutlinePoint(0.260, 0.880),
      OutlinePoint(0.160, 0.800),
      OutlinePoint(0.120, 0.680),
      OutlinePoint(0.160, 0.560),
      OutlinePoint(0.120, 0.440),
      OutlinePoint(0.200, 0.340),
      OutlinePoint(0.300, 0.260),
      OutlinePoint(0.420, 0.300),
      OutlinePoint(0.520, 0.220),
      OutlinePoint(0.620, 0.180),
      OutlinePoint(0.720, 0.240),
      OutlinePoint(0.820, 0.200),
      OutlinePoint(0.900, 0.280),
      OutlinePoint(0.890, 0.350),
      OutlinePoint(0.880, 0.420),
      OutlinePoint(0.890, 0.490),
      OutlinePoint(0.900, 0.560),
      OutlinePoint(0.820, 0.660),
      OutlinePoint(0.860, 0.780),
      OutlinePoint(0.740, 0.820),
      OutlinePoint(0.660, 0.740),
      OutlinePoint(0.600, 0.800),
    ],
  ),
  TrackInfo(
    id: 'spa',
    nameCn: '斯帕',
    nameEn: 'Circuit de Spa-Francorchamps',
    region: '比利时',
    lengthKm: 7.004,
    source: 'sportmonks.com',
    layoutSource: 'formula1.com / Spa 官网布局描述',
    totalCorners: 19,
    direction: '顺时针',
    shapeNote: '阿登森林长圈：La Source 发夹弯 → Eau Rouge 上坡 → Kemmel 长直道 → Pouhon → Blanchimont → Bus Stop',
    startFinishNote: '主直道中段，顺时针发车；出线即 La Source 发夹弯',
    sectorNote: 'S1 止于 Les Combes 出口附近，S2 止于 Stavelot 附近（分段点为示意位置）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.58, 0.86),
    sectorPoints: [
      OutlinePoint(0.70, 0.28),
      OutlinePoint(0.44, 0.56),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.28, 0.80), 'La Source'),
      CornerMark(2, OutlinePoint(0.22, 0.68), 'Eau Rouge'),
      CornerMark(5, OutlinePoint(0.74, 0.30), 'Les Combes'),
      CornerMark(8, OutlinePoint(0.84, 0.48), 'Bruxelles'),
      CornerMark(10, OutlinePoint(0.66, 0.58), 'Pouhon'),
      CornerMark(16, OutlinePoint(0.36, 0.66), 'Blanchimont'),
      CornerMark(19, OutlinePoint(0.46, 0.82), 'Bus Stop'),
    ],
    outline: [
      OutlinePoint(0.580, 0.860),
      OutlinePoint(0.510, 0.865),
      OutlinePoint(0.440, 0.870),
      OutlinePoint(0.320, 0.840),
      OutlinePoint(0.240, 0.760),
      OutlinePoint(0.200, 0.640),
      OutlinePoint(0.240, 0.590),
      OutlinePoint(0.280, 0.540),
      OutlinePoint(0.330, 0.500),
      OutlinePoint(0.380, 0.460),
      OutlinePoint(0.430, 0.420),
      OutlinePoint(0.480, 0.380),
      OutlinePoint(0.530, 0.340),
      OutlinePoint(0.580, 0.300),
      OutlinePoint(0.700, 0.280),
      OutlinePoint(0.800, 0.320),
      OutlinePoint(0.860, 0.420),
      OutlinePoint(0.840, 0.540),
      OutlinePoint(0.740, 0.600),
      OutlinePoint(0.620, 0.580),
      OutlinePoint(0.520, 0.500),
      OutlinePoint(0.440, 0.560),
      OutlinePoint(0.340, 0.620),
      OutlinePoint(0.280, 0.700),
      OutlinePoint(0.360, 0.780),
      OutlinePoint(0.480, 0.820),
    ],
  ),
  TrackInfo(
    id: 'silverstone',
    nameCn: '银石',
    nameEn: 'Silverstone Circuit',
    region: '英国',
    lengthKm: 5.891,
    source: 'sportmonks.com',
    layoutSource: 'formula1.com / Silverstone 官网布局描述',
    totalCorners: 18,
    direction: '顺时针',
    shapeNote: '旧机场赛道：Arena 内场新段 + Wellington 直道 + Copse → Maggotts–Becketts–Chapel 高速换向 + Hangar 直道 → Stowe',
    startFinishNote: 'Hamilton 直道（Club 与 Abbey 之间），顺时针发车',
    sectorNote: 'S1 止于 Chapel 出口附近，S2 止于 Club 附近（分段点为示意位置）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.52, 0.86),
    sectorPoints: [
      OutlinePoint(0.84, 0.48),
      OutlinePoint(0.50, 0.74),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.30, 0.86), 'Abbey'),
      CornerMark(3, OutlinePoint(0.20, 0.52), 'Village'),
      CornerMark(6, OutlinePoint(0.50, 0.38), 'Brooklands'),
      CornerMark(9, OutlinePoint(0.74, 0.29), 'Copse'),
      CornerMark(10, OutlinePoint(0.84, 0.44), 'Maggotts'),
      CornerMark(15, OutlinePoint(0.70, 0.66), 'Stowe'),
      CornerMark(16, OutlinePoint(0.56, 0.72), 'Vale'),
    ],
    outline: [
      OutlinePoint(0.520, 0.860),
      OutlinePoint(0.450, 0.865),
      OutlinePoint(0.380, 0.870),
      OutlinePoint(0.310, 0.855),
      OutlinePoint(0.240, 0.840),
      OutlinePoint(0.190, 0.790),
      OutlinePoint(0.140, 0.740),
      OutlinePoint(0.130, 0.670),
      OutlinePoint(0.120, 0.600),
      OutlinePoint(0.150, 0.540),
      OutlinePoint(0.180, 0.480),
      OutlinePoint(0.280, 0.420),
      OutlinePoint(0.340, 0.520),
      OutlinePoint(0.420, 0.560),
      OutlinePoint(0.460, 0.440),
      OutlinePoint(0.540, 0.340),
      OutlinePoint(0.600, 0.310),
      OutlinePoint(0.660, 0.280),
      OutlinePoint(0.780, 0.300),
      OutlinePoint(0.860, 0.400),
      OutlinePoint(0.800, 0.500),
      OutlinePoint(0.860, 0.580),
      OutlinePoint(0.760, 0.640),
      OutlinePoint(0.640, 0.680),
      OutlinePoint(0.520, 0.740),
      OutlinePoint(0.460, 0.820),
    ],
  ),
  TrackInfo(
    id: 'monza',
    nameCn: '蒙扎',
    nameEn: 'Autodromo Nazionale Monza',
    region: '意大利',
    lengthKm: 5.793,
    source: 'sportmonks.com',
    layoutSource: 'monzanet.it / Mercedes-AMG F1 弯道介绍',
    totalCorners: 11,
    direction: '顺时针',
    shapeNote: '高速长直道 + 三个减速弯：Rettifilo → Curva Grande → Roggia → Lesmo → Ascari → Parabolica 大右弯回主直道',
    startFinishNote: '主直道中段，顺时针发车；出线即 Rettifilo 减速弯',
    sectorNote: 'S1 止于 Lesmo 2 出口附近，S2 止于 Ascari 出口附近（分段点为示意位置）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.50, 0.88),
    sectorPoints: [
      OutlinePoint(0.80, 0.36),
      OutlinePoint(0.58, 0.62),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.12, 0.78), 'Rettifilo'),
      CornerMark(3, OutlinePoint(0.26, 0.54), 'Curva Grande'),
      CornerMark(4, OutlinePoint(0.48, 0.38), 'Roggia'),
      CornerMark(6, OutlinePoint(0.68, 0.30), 'Lesmo 1'),
      CornerMark(7, OutlinePoint(0.80, 0.36), 'Lesmo 2'),
      CornerMark(8, OutlinePoint(0.62, 0.58), 'Ascari'),
      CornerMark(11, OutlinePoint(0.24, 0.76), 'Parabolica'),
    ],
    outline: [
      OutlinePoint(0.500, 0.880),
      OutlinePoint(0.430, 0.885),
      OutlinePoint(0.360, 0.890),
      OutlinePoint(0.290, 0.885),
      OutlinePoint(0.220, 0.880),
      OutlinePoint(0.120, 0.820),
      OutlinePoint(0.120, 0.680),
      OutlinePoint(0.200, 0.580),
      OutlinePoint(0.300, 0.500),
      OutlinePoint(0.360, 0.460),
      OutlinePoint(0.420, 0.420),
      OutlinePoint(0.480, 0.380),
      OutlinePoint(0.540, 0.340),
      OutlinePoint(0.660, 0.300),
      OutlinePoint(0.780, 0.320),
      OutlinePoint(0.860, 0.420),
      OutlinePoint(0.820, 0.540),
      OutlinePoint(0.700, 0.600),
      OutlinePoint(0.600, 0.560),
      OutlinePoint(0.560, 0.660),
      OutlinePoint(0.460, 0.700),
      OutlinePoint(0.360, 0.640),
      OutlinePoint(0.260, 0.700),
      OutlinePoint(0.200, 0.800),
      OutlinePoint(0.300, 0.860),
      OutlinePoint(0.400, 0.870),
    ],
  ),
  TrackInfo(
    id: 'suzuka',
    nameCn: '铃鹿',
    nameEn: 'Suzuka Circuit',
    region: '日本',
    lengthKm: 5.807,
    source: 'formula1.com',
    layoutSource: 'suzukacircuit.jp / formula1.com',
    totalCorners: 18,
    direction: '顺时针',
    shapeNote: '8 字交叉：S 弯 → Degner → 立交下穿 → 发夹弯 → Spoon → 130R → Casio 三角弯回主直道',
    startFinishNote: '主直道中段，顺时针发车；T1 右弯接 S 弯',
    sectorNote: 'S1 止于 Degner 出口（立交下穿）附近，S2 止于 130R 出口附近（分段点为示意位置）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.52, 0.88),
    sectorPoints: [
      OutlinePoint(0.38, 0.40),
      OutlinePoint(0.84, 0.60),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.30, 0.86), 'T1'),
      CornerMark(3, OutlinePoint(0.20, 0.58), 'S Curves'),
      CornerMark(8, OutlinePoint(0.36, 0.42), 'Degner'),
      CornerMark(11, OutlinePoint(0.62, 0.40), '发夹弯'),
      CornerMark(13, OutlinePoint(0.76, 0.38), 'Spoon'),
      CornerMark(15, OutlinePoint(0.86, 0.52), '130R'),
      CornerMark(16, OutlinePoint(0.64, 0.74), 'Casio Triangle'),
    ],
    // 注意：8 字布局在平面示意里必然有一处交叉：中心点 (0.50, 0.52)
    // 在点列里出现两次，左环与右环在此交汇，刻意保留的 8 字特征，
    // 对应现实中 Degner 后下穿段与后段直道的立交，不是画错。
    outline: [
      OutlinePoint(0.520, 0.880),
      OutlinePoint(0.450, 0.880),
      OutlinePoint(0.380, 0.880),
      OutlinePoint(0.260, 0.840),
      OutlinePoint(0.180, 0.740),
      OutlinePoint(0.160, 0.620),
      OutlinePoint(0.220, 0.520),
      OutlinePoint(0.300, 0.460),
      OutlinePoint(0.380, 0.400),
      OutlinePoint(0.460, 0.440),
      OutlinePoint(0.500, 0.520),
      OutlinePoint(0.580, 0.460),
      OutlinePoint(0.680, 0.380),
      OutlinePoint(0.780, 0.360),
      OutlinePoint(0.860, 0.440),
      OutlinePoint(0.880, 0.560),
      OutlinePoint(0.800, 0.660),
      OutlinePoint(0.680, 0.700),
      OutlinePoint(0.620, 0.670),
      OutlinePoint(0.560, 0.640),
      OutlinePoint(0.530, 0.580),
      OutlinePoint(0.500, 0.520),
      OutlinePoint(0.560, 0.620),
      OutlinePoint(0.640, 0.700),
      OutlinePoint(0.680, 0.800),
      OutlinePoint(0.600, 0.860),
    ],
  ),
  TrackInfo(
    id: 'laguna_seca',
    nameCn: '拉古纳塞卡',
    nameEn: 'WeatherTech Raceway Laguna Seca',
    region: '美国',
    lengthKm: 3.602,
    source: 'Wikipedia',
    layoutSource: 'laguna-seca.com / racetrackworld.com',
    totalCorners: 11,
    direction: '逆时针',
    shapeNote: '逆时针湖畔赛道：Andretti 发夹弯 → 内场 → Rahal 直道爬坡 → 开瓶塞（T8/8A）盲顶下坡 → Rainey 弯 → T11 回主直道',
    startFinishNote: '主直道中段，逆时针发车；出线下坡接 Andretti 发夹弯',
    sectorNote: '无公开分段点：未查到该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.56, 0.86),
    corners: [
      CornerMark(1, OutlinePoint(0.30, 0.84)),
      CornerMark(2, OutlinePoint(0.12, 0.72), 'Andretti Hairpin'),
      CornerMark(6, OutlinePoint(0.50, 0.36)),
      CornerMark(8, OutlinePoint(0.78, 0.34), 'Corkscrew'),
      CornerMark(9, OutlinePoint(0.82, 0.56), 'Rainey Curve'),
      CornerMark(11, OutlinePoint(0.66, 0.80)),
    ],
    outline: [
      OutlinePoint(0.560, 0.860),
      OutlinePoint(0.490, 0.865),
      OutlinePoint(0.420, 0.870),
      OutlinePoint(0.350, 0.865),
      OutlinePoint(0.280, 0.860),
      OutlinePoint(0.220, 0.830),
      OutlinePoint(0.160, 0.800),
      OutlinePoint(0.130, 0.740),
      OutlinePoint(0.100, 0.680),
      OutlinePoint(0.140, 0.560),
      OutlinePoint(0.240, 0.480),
      OutlinePoint(0.360, 0.440),
      OutlinePoint(0.420, 0.520),
      OutlinePoint(0.380, 0.620),
      OutlinePoint(0.480, 0.660),
      OutlinePoint(0.580, 0.600),
      OutlinePoint(0.560, 0.480),
      OutlinePoint(0.640, 0.380),
      OutlinePoint(0.760, 0.320),
      OutlinePoint(0.860, 0.380),
      OutlinePoint(0.870, 0.450),
      OutlinePoint(0.880, 0.520),
      OutlinePoint(0.800, 0.620),
      OutlinePoint(0.860, 0.720),
      OutlinePoint(0.760, 0.780),
      OutlinePoint(0.640, 0.820),
    ],
  ),
  TrackInfo(
    id: 'cota',
    nameCn: '美洲赛道',
    nameEn: 'Circuit of the Americas',
    region: '美国',
    lengthKm: 5.513,
    source: 'FIA 赛道执照表',
    layoutSource: 'formula1.com',
    totalCorners: 20,
    direction: '逆时针',
    shapeNote: '逆时针：T1 陡坡盲顶左弯 → Esses 高速换向 → 长后直道 → T11 发夹弯 → 体育场技术段 → T19–T20 回主直道',
    startFinishNote: '主直道中段，逆时针发车；出线爬坡接 T1 盲顶左弯',
    sectorNote: 'S1 止于 Esses 出口附近，S2 止于体育场段出口附近（分段点为示意位置）',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.54, 0.88),
    sectorPoints: [
      OutlinePoint(0.46, 0.44),
      OutlinePoint(0.70, 0.66),
    ],
    corners: [
      CornerMark(1, OutlinePoint(0.20, 0.82), '陡坡盲顶'),
      CornerMark(3, OutlinePoint(0.22, 0.54), 'Esses'),
      CornerMark(11, OutlinePoint(0.86, 0.36), '发夹弯'),
      CornerMark(13, OutlinePoint(0.78, 0.58), '体育场段'),
      CornerMark(19, OutlinePoint(0.66, 0.66)),
      CornerMark(20, OutlinePoint(0.56, 0.78)),
    ],
    outline: [
      OutlinePoint(0.540, 0.880),
      OutlinePoint(0.400, 0.890),
      OutlinePoint(0.260, 0.860),
      OutlinePoint(0.160, 0.780),
      OutlinePoint(0.140, 0.640),
      OutlinePoint(0.200, 0.520),
      OutlinePoint(0.300, 0.460),
      OutlinePoint(0.260, 0.360),
      OutlinePoint(0.340, 0.280),
      OutlinePoint(0.440, 0.300),
      OutlinePoint(0.500, 0.400),
      OutlinePoint(0.440, 0.500),
      OutlinePoint(0.540, 0.540),
      OutlinePoint(0.640, 0.480),
      OutlinePoint(0.620, 0.360),
      OutlinePoint(0.720, 0.280),
      OutlinePoint(0.840, 0.300),
      OutlinePoint(0.860, 0.370),
      OutlinePoint(0.880, 0.440),
      OutlinePoint(0.800, 0.520),
      OutlinePoint(0.840, 0.620),
      OutlinePoint(0.740, 0.680),
      OutlinePoint(0.640, 0.640),
      OutlinePoint(0.620, 0.740),
      OutlinePoint(0.520, 0.800),
      OutlinePoint(0.460, 0.840),
    ],
  ),
  TrackInfo(
    id: 'fuji',
    nameCn: '富士 Speedway',
    nameEn: 'Fuji Speedway',
    region: '日本',
    lengthKm: 4.563,
    source: 'racefans.net',
    layoutSource: 'fujispeedway.jp / racetrackworld.com',
    totalCorners: 16,
    direction: '顺时针',
    shapeNote: '1.475 km 主直道 + 前段高速弯 + 后段上坡技术弯',
    startFinishNote: '主直道（约 1.475 km）中段，顺时针发车；直道末端重刹接 T1',
    sectorNote: '无公开分段点：未查到经核实的该赛道公开分段计时线，仅前后半圈示意',
    redrawn: true,
    startFinishPoint: OutlinePoint(0.50, 0.88),
    corners: [
      CornerMark(1, OutlinePoint(0.12, 0.78), 'Coca-Cola'),
      CornerMark(4, OutlinePoint(0.34, 0.45), '100R'),
      CornerMark(5, OutlinePoint(0.60, 0.35), '发夹弯'),
      CornerMark(8, OutlinePoint(0.84, 0.54), 'Dunlop'),
      CornerMark(12, OutlinePoint(0.68, 0.78)),
    ],
    outline: [
      OutlinePoint(0.500, 0.880),
      OutlinePoint(0.420, 0.890),
      OutlinePoint(0.340, 0.890),
      OutlinePoint(0.240, 0.880),
      OutlinePoint(0.140, 0.840),
      OutlinePoint(0.180, 0.800),
      OutlinePoint(0.100, 0.740),
      OutlinePoint(0.110, 0.640),
      OutlinePoint(0.170, 0.550),
      OutlinePoint(0.220, 0.515),
      OutlinePoint(0.270, 0.480),
      OutlinePoint(0.380, 0.430),
      OutlinePoint(0.480, 0.410),
      OutlinePoint(0.520, 0.380),
      OutlinePoint(0.580, 0.360),
      OutlinePoint(0.680, 0.320),
      OutlinePoint(0.780, 0.340),
      OutlinePoint(0.850, 0.400),
      OutlinePoint(0.840, 0.440),
      OutlinePoint(0.870, 0.500),
      OutlinePoint(0.820, 0.590),
      OutlinePoint(0.860, 0.660),
      OutlinePoint(0.800, 0.720),
      OutlinePoint(0.720, 0.760),
      OutlinePoint(0.640, 0.800),
      OutlinePoint(0.570, 0.840),
    ],
  ),
];

/// 全部赛道（国内在前，国外在后）。
const List<TrackInfo> allTracks = [...domesticTracks, ...overseasTracks];

/// 按 id 查找，找不到返回 null（调用方不得用 null 冒充默认赛道）。
TrackInfo? trackById(String? id) {
  if (id == null) return null;
  for (final t in allTracks) {
    if (t.id == id) return t;
  }
  return null;
}
