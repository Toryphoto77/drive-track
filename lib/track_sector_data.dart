/// v1.2.0 第 6 项：赛道扇区点数据（新增文件，不改动已有文件）。
///
/// 口径（防编造，与 track_catalog.dart 文件头一致）：
/// - 目录里的 sectorPoints 在目录文件头已明说“是按公开分段描述确定
///   的示意位置，不是官方计时线”，所以本文件**没有任何一条标 official**：
///   把示意点冒充官方计时线就是编造。本轮没有从公开渠道核实到任何
///   一条赛道以“圈距离分数”形式公布的官方扇区计时线，故 official
///   一律空缺，等核实到官方分段描述后再补，绝不先填数占位。
/// - [TrackSectorSource.estimated]：分界点是轮廓距离分数（0~1，
///   0 = 起终点，1 = 回到起终点），即沿赛道轮廓/走线量出的相对位置，
///   不是官方计时线；界面必须标注“估算分段”。其中：
///   - 6 条有目录示意分段点（shanghai/spa/silverstone/monza/suzuka/
///     cota）：分数由脚本沿目录重绘轮廓折线量出（最近点投影法），
///     见各条 note；分数本身仍是示意换算，不是官方值。
///   - 其余有重绘轮廓或 OSM 走线的赛道：用轮廓距离三等分
///     （1/3、2/3）作估算分段，note 写明“均分估算”。
/// - [TrackSectorSource.pending]：无重绘轮廓、无 OSM 走线、无可核实
///   分段描述（chengdu_tianfu/goldenport/guangdong_gic/le_mans/
 ///   nordschleife），分界点一律为空，界面显示“扇区待核”，不得
///   用三等分硬凑——没有轮廓几何作依据的三等分是凭空编数。
///   nordschleife 另有原因：长圈布局随赛事而异，分段线不固定。
/// - 本文件只给“分界点在圈内的相对位置”，不给任何圈速、分段用时：
///   圈速只来自实测 Lap，见 track_timing.dart。
/// - 赛道模式不评分：本文件不含任何评分字段。

import 'track_timing.dart';

/// 扇区分界点来源。
enum TrackSectorSource {
  /// 已核实的官方扇区划分（本轮 21 条全部空缺，见文件头）。
  official,

  /// 轮廓距离估算分段：界面必须标注“估算分段”，不得称官方。
  estimated,

  /// 未核实：分界点为空，界面显示“扇区待核”。
  pending,
}

/// 一条赛道的扇区数据。
class TrackSectorData {
  /// 赛道 id，与 EncyclopediaTrack.id / TrackInfo.id 一致。
  final String trackId;

  /// 来源标注。
  final TrackSectorSource source;

  /// 分界点（圈距离分数，0~1 之间严格递增）：
  /// - 2 个点 = S1/S2/S3 三段；
  /// - pending 时为空列表，不得填数。
  final List<double> boundaries;

  /// 来源说明：官方出处，或估算方法，或待核原因；界面可直接展示。
  final String note;

  const TrackSectorData({
    required this.trackId,
    required this.source,
    this.boundaries = const [],
    required this.note,
  });

  /// 是否有可用分界点（estimated/official 且恰好 2 个点）。
  bool get hasBoundaries => boundaries.length == 2;

  /// 分段数：有分界点时为 3，否则为 0（调用方不得硬标 S1/S2/S3）。
  int get sectorCount => hasBoundaries ? 3 : 0;

  /// 分段标签：有分界点时 S1/S2/S3，否则空列表。
  List<String> get sectorLabels =>
      hasBoundaries ? const ['S1', 'S2', 'S3'] : const [];

  /// 界面用来源文案。
  String get sourceLabel => switch (source) {
        TrackSectorSource.official => '官方扇区',
        TrackSectorSource.estimated => '估算分段',
        TrackSectorSource.pending => '扇区待核',
      };

  /// 分界点合法性：pending 必须为空；其余必须恰好 2 个点、
  /// 全部在 (0, 1) 开区间内且严格递增。
  bool get isValid {
    if (source == TrackSectorSource.pending) return boundaries.isEmpty;
    if (boundaries.length != 2) return false;
    return boundaries[0] > 0 &&
        boundaries[0] < 1 &&
        boundaries[1] > 0 &&
        boundaries[1] < 1 &&
        boundaries[0] < boundaries[1];
  }
}

/// 21 条赛道扇区数据（key = 赛道 id，覆盖图鉴 21 条）。
const Map<String, TrackSectorData> trackSectorData = {
  // —— 有目录示意分段点：分数 = 沿目录重绘轮廓折线量出的相对位置 ——
  'shanghai': TrackSectorData(
    trackId: 'shanghai',
    source: TrackSectorSource.estimated,
    boundaries: [0.512, 0.836],
    note: '估算分段：由目录示意分段点（S1 止于 T5 附近、S2 止于 T10 附近）'
        '沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  'spa': TrackSectorData(
    trackId: 'spa',
    source: TrackSectorSource.estimated,
    boundaries: [0.453, 0.776],
    note: '估算分段：由目录示意分段点（S1 止于 Les Combes 出口附近、'
        'S2 止于 Stavelot 附近）沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  'silverstone': TrackSectorData(
    trackId: 'silverstone',
    source: TrackSectorSource.estimated,
    boundaries: [0.717, 0.934],
    note: '估算分段：由目录示意分段点（S1 止于 Chapel 出口附近、'
        'S2 止于 Club 附近）沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  'monza': TrackSectorData(
    trackId: 'monza',
    source: TrackSectorSource.estimated,
    boundaries: [0.507, 0.697],
    note: '估算分段：由目录示意分段点（S1 止于 Lesmo 2 出口附近、'
        'S2 止于 Ascari 出口附近）沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  'suzuka': TrackSectorData(
    trackId: 'suzuka',
    source: TrackSectorSource.estimated,
    boundaries: [0.318, 0.623],
    note: '估算分段：由目录示意分段点（S1 止于 Degner 出口附近、'
        'S2 止于 130R 出口附近）沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  'cota': TrackSectorData(
    trackId: 'cota',
    source: TrackSectorSource.estimated,
    boundaries: [0.444, 0.849],
    note: '估算分段：由目录示意分段点（S1 止于 Esses 出口附近、'
        'S2 止于体育场段出口附近）沿重绘轮廓换算为圈距离分数，非官方计时线。',
  ),
  // —— 有重绘轮廓但无目录分段点：轮廓距离三等分估算 ——
  'zhuhai': TrackSectorData(
    trackId: 'zhuhai',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'ningbo': TrackSectorData(
    trackId: 'ningbo',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'zhejiang': TrackSectorData(
    trackId: 'zhejiang',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'tianma': TrackSectorData(
    trackId: 'tianma',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'ordos': TrackSectorData(
    trackId: 'ordos',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'laguna_seca': TrackSectorData(
    trackId: 'laguna_seca',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  'fuji': TrackSectorData(
    trackId: 'fuji',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按重绘轮廓距离三等分估算，非官方扇区。',
  ),
  // —— 有 OSM 走线但无目录分段点：走线距离三等分估算 ——
  'monaco': TrackSectorData(
    trackId: 'monaco',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按 OSM 走线距离三等分估算，非官方扇区。',
  ),
  'sepang': TrackSectorData(
    trackId: 'sepang',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按 OSM 走线距离三等分估算，非官方扇区。',
  ),
  'bathurst': TrackSectorData(
    trackId: 'bathurst',
    source: TrackSectorSource.estimated,
    boundaries: [0.333, 0.667],
    note: '估算分段：无公开分段点，按 OSM 走线距离三等分估算，非官方扇区。',
  ),
  // —— 待核：无轮廓几何依据，不填数 ——
  'nordschleife': TrackSectorData(
    trackId: 'nordschleife',
    source: TrackSectorSource.pending,
    note: '扇区待核：长圈布局随赛事而异，分段线不固定，未填分界点。',
  ),
  'chengdu_tianfu': TrackSectorData(
    trackId: 'chengdu_tianfu',
    source: TrackSectorSource.pending,
    note: '扇区待核：无重绘轮廓、无公开分段点，未填分界点。',
  ),
  'goldenport': TrackSectorData(
    trackId: 'goldenport',
    source: TrackSectorSource.pending,
    note: '扇区待核：无重绘轮廓、无公开分段点（弯道数本身亦存疑），未填分界点。',
  ),
  'guangdong_gic': TrackSectorData(
    trackId: 'guangdong_gic',
    source: TrackSectorSource.pending,
    note: '扇区待核：无重绘轮廓、无公开分段点，未填分界点。',
  ),
  'le_mans': TrackSectorData(
    trackId: 'le_mans',
    source: TrackSectorSource.pending,
    note: '扇区待核：无重绘轮廓、无公开分段点，未填分界点。',
  ),
};

/// 按 id 查扇区数据；查不到返回 null（调用方不得用 null 冒充默认赛道）。
TrackSectorData? sectorDataFor(String? trackId) {
  if (trackId == null) return null;
  return trackSectorData[trackId];
}

/// 圈距离分数落在第几段（0-based）；无分界点时返回 -1。
int sectorIndexForFraction(TrackSectorData? data, double fraction) {
  if (data == null || !data.hasBoundaries) return -1;
  if (fraction < data.boundaries[0]) return 0;
  if (fraction < data.boundaries[1]) return 1;
  return 2;
}

/// 第 [index] 段在圈距离分数上的起止区间；无分界点或越界返回 null。
/// 返回 (start, end)，均为 0~1。
({double start, double end})? sectorFractionRange(
    TrackSectorData? data, int index) {
  if (data == null || !data.hasBoundaries) return null;
  if (index < 0 || index > 2) return null;
  final b = data.boundaries;
  return switch (index) {
    0 => (start: 0, end: b[0]),
    1 => (start: b[0], end: b[1]),
    _ => (start: b[1], end: 1),
  };
}

/// 无效圈标注：返回 null 表示计入成绩的圈；非 null 为界面展示的标注。
/// - 停留不计圈（Lap.dwellNotCounted）：'无效圈 · 停留不计圈'；
/// - 分段缺失（sectorsMs 为空）：'无效圈 · 分段缺失'（不进理论最佳圈统计）。
/// 其余圈（即使某段缺失导致段数不一致）不在此判无效，由调用方按段数
/// 过滤进理论最佳圈统计，见 [bestSectorMs]。
String? lapInvalidReason(Lap lap) {
  if (lap.dwellNotCounted) return '无效圈 · 停留不计圈';
  if (lap.sectorsMs.isEmpty) return '无效圈 · 分段缺失';
  return null;
}

/// 各段最佳用时（ms）：只统计计入成绩（[lapInvalidReason] 为 null）
/// 且有该段数据的圈；某段无任何圈数据时该位置为 null。
/// [sectorCount] 为 0 时取计入圈的最大段数。
List<int?> bestSectorMs(List<Lap> laps, {int sectorCount = 0}) {
  final counted =
      laps.where((l) => lapInvalidReason(l) == null).toList();
  var n = sectorCount;
  if (n <= 0) {
    for (final l in counted) {
      if (l.sectorsMs.length > n) n = l.sectorsMs.length;
    }
  }
  if (n <= 0) return const [];
  final best = List<int?>.filled(n, null);
  for (final l in counted) {
    for (var i = 0; i < n && i < l.sectorsMs.length; i++) {
      final v = l.sectorsMs[i];
      if (best[i] == null || v < best[i]!) best[i] = v;
    }
  }
  return best;
}

/// 理论最佳圈（ms）= 各分段最佳相加；任一段无数据时返回 null，
/// 不拿不完整数据拼一个假理论圈。
int? theoreticalBestLapMs(List<Lap> laps, {int sectorCount = 0}) {
  final best = bestSectorMs(laps, sectorCount: sectorCount);
  if (best.isEmpty || best.any((v) => v == null)) return null;
  var sum = 0;
  for (final v in best) {
    sum += v!;
  }
  return sum;
}

/// 本节最优圈（直播面板用）：先按最佳圈的分段长度过滤参与拼合
/// 的圈，保证分段口径一致——退化半圈（无扇区点时的前后半圈）
/// 绝不与真实分段按下标混算；再调 theoreticalBestLapMs。
/// 无最佳圈时为 null，不拼假圈。
int? sessionOptimalLapMs(List<Lap> laps) {
  final best = sessionBestLap(laps);
  if (best == null) return null;
  return theoreticalBestLapMs(laps
      .where((l) => l.sectorsMs.length == best.sectorsMs.length)
      .toList());
}

/// 赛后理论最优圈（分析页用）：与直播页 [sessionOptimalLapMs]
/// 同口径（先按最佳圈段数过滤，再各段最快相加），另加一道真实
/// 分段门控——最佳圈须至少 3 段（即 2 个真实分段点均已触发）。
/// 2 段无法区分“1 个真实分段点”与“无分段点时的前后半圈切分”，
/// 保守起见返回 null（1 分段点赛道的理论最优暂不显示，等分段口
/// 径随行程持久化后再放开）；无分段点的半圈拼合一律不显示。
/// 无计入圈、最佳圈段数不足时为 null，界面显示占位。
int? analysisTheoreticalBestLapMs(List<Lap> laps) {
  final best = sessionBestLap(laps);
  if (best == null || best.sectorsMs.length < 3) return null;
  return sessionOptimalLapMs(laps);
}

/// 本节最佳圈：计入成绩的圈里最快的一圈；无计入圈时为 null。
/// 与 LapTimer.bestLap 口径一致（只看 counted），供不持有 LapTimer
/// 的分析页复用。
Lap? sessionBestLap(List<Lap> laps) {
  final counted =
      laps.where((l) => lapInvalidReason(l) == null).toList();
  if (counted.isEmpty) return null;
  counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
  return counted.first;
}
