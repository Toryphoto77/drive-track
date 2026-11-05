/// 赛道模式纯 Dart 计时逻辑（新文件，不改动已有文件）。
///
/// 设计原则：
/// - 本文件零 Flutter 依赖、零项目内 import，可直接单测：调用方把 1Hz 轨迹点
///   喂给 [LapTimer.addPoint] 即可，事后也可用同一类对已存轨迹做离线重算。
/// - 本文件不引用 models.dart 的 TrackPoint：调用方把 lat/lon/speed/timeMs
///   抄成 [TimedPoint] 再喂入，避免计时逻辑与行程模型互相耦合。
/// - 赛道模式下不套用街道驾驶评分：本文件只输出圈速与圈速稳定性指标
///   （[LapStability]：圈速标准差 / 极差 / 平均圈速），评分字段由接线方
///   在赛道模式下留空或标注“赛道模式不评分”，不得把街道评分混进来。
/// - 越线检测（v1.2.14）：每条计时线 = “点 + 方向”，方向取包中心线在
///   该点最近线段处的切线方向（纯函数 [tangentAtPoint]，可单测）。
///   计时线过该点、垂直于行进方向、横 across 赛道。连续两定位点到
///   计时线的带符号距离变号，且位移方向与赛道方向一致（点积 > 0），
///   即判定过线；过线时刻按带符号距离比例线性插值，不取最近点时间。
///   过线点到边界点的沿线横向偏移须落在计时线半宽（[crossingRadiusM]）
///   内，否则视为平行维修区通道横穿计时线延长线，不触发。
///   没有中心线（或未传切线）的边界回落旧半径法，不得崩、不得编造方向。
///   中心线须按行车方向排序；有 2 个分段点时，内部按起终点→S1→S2
///   的环形顺序检查，若顺序反了说明中心线按行车反方向排序，全部切线
///   自动取反；无分段点时无法纠正，须保证中心线本身按行车方向。
///   由调用方在构造 [LapTimer] 时传入。本文件不猜、不内置任何赛道坐标
///   （目录文件 track_catalog.dart 也故意不含坐标，见其文件头注释）。
/// - 维修区检测（v1.2.17）：构造时另传 [LapTimer.pitIn] / [LapTimer.pitOut]
///   （维修区入口 / 出口点），仅两者均非 null 且中心线可用时生效，
///   否则整个维修区逻辑关闭。入口 / 出口各为一条计时线（方向取中心线
///   在该点处最近点的切线，与起终点 / 分段线同一做法，横向半宽同样
///   复用 [LapTimer.crossingRadiusM]），复用越线 machinery 判定穿越：
///   穿入口线 → [LapTimer.inPit] 为真并开始计 [LapTimer.pitStopMs]，
///   穿出口线 → 清除；完圈时按本圈内是否穿越过出 / 入口线定
///   [Lap.kind]（出站圈优先于进站圈）。停车 30 秒自动暂停与
///   dwellNotCounted 规则原样保留，在维修区里停着的圈仍按 dwell
///   规则不计成绩。
/// - 段速（v1.2.17）：[LapTimer.sectorSpeeds] 与分段标签等长，
///   每段取该段内已喂入轨迹点速度的最低 / 最高（km/h），尚未开始
///   的段为 null；无分段点时为空列表，不拼假段。
/// - 到下一计时线距离（v1.2.17）：[LapTimer.nextLineDistanceM] 为
///   当前位置沿中心线到按行进方向最近的下一个边界点（分段点或
///   起终点）的米数；无中心线或无任何边界点时为 null，不编数。

import 'dart:math' as math;

/// 计时用的最小轨迹点：时间（ms）、经纬度、速度（m/s）。
class TimedPoint {
  final int timeMs;
  final double lat;
  final double lon;
  final double speed;
  const TimedPoint({
    required this.timeMs,
    required this.lat,
    required this.lon,
    required this.speed,
  });
}

/// 一个经纬度点（起终点 / 分段点）。
class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint(this.lat, this.lon);
}

/// 赛道行进方向：单位向量，东 / 北分量（米制本地坐标系）。
/// 由调用方直接传入，或由 [tangentAtPoint] 从包中心线算出。
class TrackDirection {
  final double east;
  final double north;
  const TrackDirection(this.east, this.north);
}

/// 中心线在 [point] 最近线段处的切线方向（单位向量，东 / 北分量）。
/// 纯函数：最近线段指 [point] 到中心线各线段的最短距离最小者，
/// 切线取该线段方向（按中心线排序方向，即行车方向）。
/// 中心线不足 2 点、或最近线段退化（长度为 0）时返回 null，
/// 调用方对该边界回落半径法。
TrackDirection? tangentAtPoint(List<GeoPoint> centerline, GeoPoint point) {
  if (centerline.length < 2) return null;
  final lat0 = _rad(point.lat);
  var bestDistSq = double.infinity;
  var bestDx = 0.0;
  var bestDy = 0.0;
  var found = false;
  for (var i = 0; i + 1 < centerline.length; i++) {
    final ax = (centerline[i].lon - point.lon) * math.cos(lat0) * 111320;
    final ay = (centerline[i].lat - point.lat) * 110540;
    final bx = (centerline[i + 1].lon - point.lon) * math.cos(lat0) * 111320;
    final by = (centerline[i + 1].lat - point.lat) * 110540;
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq <= 0) continue;
    var t = (-ax * dx + -ay * dy) / lenSq;
    t = t.clamp(0, 1);
    final px = ax + t * dx;
    final py = ay + t * dy;
    final dSq = px * px + py * py;
    if (dSq < bestDistSq) {
      bestDistSq = dSq;
      bestDx = dx;
      bestDy = dy;
      found = true;
    }
  }
  if (!found) return null;
  final len = math.sqrt(bestDx * bestDx + bestDy * bestDy);
  return TrackDirection(bestDx / len, bestDy / len);
}

/// [point] 在中心线上的弧长位置（0~1，0 = 中心线起点，1 = 终点）：
/// 最近线段投影点处的累计弧长 / 中心线总长。纯函数。
/// 中心线不足 2 点、或总长为 0 时返回 null。
/// 供 [LapTimer] 内部检查起终点→S1→S2 的环形顺序、纠正反向中心线。
double? centerlineFractionAt(List<GeoPoint> centerline, GeoPoint point) {
  if (centerline.length < 2) return null;
  final lat0 = _rad(point.lat);
  // 各顶点相对 point 的本地米制坐标。
  final xs = <double>[];
  final ys = <double>[];
  for (final p in centerline) {
    xs.add((p.lon - point.lon) * math.cos(lat0) * 111320);
    ys.add((p.lat - point.lat) * 110540);
  }
  var total = 0.0;
  final cum = <double>[0];
  for (var i = 0; i + 1 < centerline.length; i++) {
    final dx = xs[i + 1] - xs[i];
    final dy = ys[i + 1] - ys[i];
    total += math.sqrt(dx * dx + dy * dy);
    cum.add(total);
  }
  if (total <= 0) return null;
  var bestDistSq = double.infinity;
  var bestArc = 0.0;
  for (var i = 0; i + 1 < centerline.length; i++) {
    final dx = xs[i + 1] - xs[i];
    final dy = ys[i + 1] - ys[i];
    final lenSq = dx * dx + dy * dy;
    if (lenSq <= 0) continue;
    var t = (-xs[i] * dx + -ys[i] * dy) / lenSq;
    t = t.clamp(0, 1);
    final px = xs[i] + t * dx;
    final py = ys[i] + t * dy;
    final dSq = px * px + py * py;
    if (dSq < bestDistSq) {
      bestDistSq = dSq;
      bestArc = cum[i] + t * (cum[i + 1] - cum[i]);
    }
  }
  return (bestArc / total).clamp(0, 1);
}

/// 中心线总长（m）：各线段按等距圆柱投影（与 [centerlineFractionAt]
/// 同一近似）累加；供 [LapTimer.nextLineDistanceM] 把 fraction 换算成米。
double _centerlineTotalLengthM(List<GeoPoint> centerline) {
  if (centerline.length < 2) return 0;
  var latSum = 0.0;
  for (final p in centerline) {
    latSum += p.lat;
  }
  final lat0 = _rad(latSum / centerline.length);
  var total = 0.0;
  for (var i = 0; i + 1 < centerline.length; i++) {
    final dx =
        (centerline[i + 1].lon - centerline[i].lon) * math.cos(lat0) * 111320;
    final dy = (centerline[i + 1].lat - centerline[i].lat) * 110540;
    total += math.sqrt(dx * dx + dy * dy);
  }
  return total;
}

/// 一圈的种类（v1.2.17）：
/// - [flying]：飞驰圈（本圈内未穿越维修区出 / 入口线）；
/// - [outLap]：出站圈（本圈内穿越过维修区出口线）；
/// - [inLap]：进站圈（本圈内穿越过维修区入口线、未穿越出口线）。
/// 同一圈内两者都穿越过时出站圈优先（见 [LapTimer] 维修区检测）。
enum LapKind { flying, outLap, inLap }

/// 一圈的计时结果。
class Lap {
  /// 圈号，从 1 开始。发车圈（第一次穿越起终点之前）不计圈，不产生 Lap。
  final int number;
  final int startMs;
  final int endMs;

  /// 圈速（ms，已扣除暂停时长，见 [pausedMs]）。
  final int durationMs;

  /// 本圈内因停车暂停而扣除的时长（ms）。
  final int pausedMs;

  /// 本圈内是否发生过停车超阈值停留。若为 true，本圈标注“停留不计圈”，
  /// 不进入最快圈、圈速榜与圈速稳定性统计（但仍保留在 [LapTimer.laps] 里备查）。
  final bool dwellNotCounted;

  /// 分段用时（ms）：
  /// - 若构造时给了 2 个分段点：[S1, S2, S3]，共 3 段；
  /// - 若无分段点：按圈时长中点切成 2 段 [前半圈, 后半圈]（见文件头与
  ///   [LapTimer] 注释：这是无分段点时的退化分段，不是真实 S1/S2 边界，
  ///   界面须标注“无分段点，前后半圈示意”）；
  /// - 若给了分段点但某段因 GPS 丢点未触发：缺失段不补数，sectors 长度
  ///   小于应有段数，调用方按实际长度显示，不得脑补。
  final List<int> sectorsMs;

  /// 圈种（v1.2.17）：默认 [LapKind.flying]；完圈时由 [LapTimer]
  /// 按本圈内是否穿越过维修区出 / 入口线定（出站圈优先于进站圈）。
  final LapKind kind;

  const Lap({
    required this.number,
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    required this.pausedMs,
    required this.dwellNotCounted,
    required this.sectorsMs,
    this.kind = LapKind.flying,
  });

  /// 是否计入成绩（未停留的圈才计入）。
  bool get counted => !dwellNotCounted;

  Map<String, dynamic> toJson() => {
        'n': number,
        's': startMs,
        'e': endMs,
        'd': durationMs,
        'paused': pausedMs,
        'dwell': dwellNotCounted,
        'sec': sectorsMs,
        'k': switch (kind) {
          LapKind.flying => 'flying',
          LapKind.outLap => 'out',
          LapKind.inLap => 'in',
        },
      };

  static Lap fromJson(Map<String, dynamic> j) => Lap(
        number: (j['n'] as num).toInt(),
        startMs: (j['s'] as num).toInt(),
        endMs: (j['e'] as num).toInt(),
        durationMs: (j['d'] as num).toInt(),
        pausedMs: (j['paused'] as num?)?.toInt() ?? 0,
        dwellNotCounted: (j['dwell'] as bool?) ?? false,
        sectorsMs:
            ((j['sec'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
        // 老数据无 'k' 键时读作飞驰圈，保持兼容。
        kind: switch (j['k'] as String?) {
          'out' => LapKind.outLap,
          'in' => LapKind.inLap,
          _ => LapKind.flying,
        },
      );
}

/// 一段内的速度区间（km/h，v1.2.17）：该段内已喂入轨迹点速度的
/// 最低 / 最高值。供 [LapTimer.sectorSpeeds] 返回；尚未开始的段
/// 为 null，不拼假段。
class SectorSpeed {
  final double minKmh;
  final double maxKmh;
  const SectorSpeed(this.minKmh, this.maxKmh);
}

/// 圈速稳定性指标：只统计计入成绩的圈（停留不计圈的圈排除在外）。
/// 圈数不足 2 圈时无意义，[LapTimer.stability] 返回 null。
class LapStability {
  /// 计入统计的圈数。
  final int count;

  /// 平均圈速（ms）。
  final double meanMs;

  /// 圈速标准差（ms，总体标准差）。
  final double stdDevMs;

  /// 极差（ms）= 最慢计入圈 - 最快计入圈。
  final double rangeMs;

  const LapStability({
    required this.count,
    required this.meanMs,
    required this.stdDevMs,
    required this.rangeMs,
  });
}

/// 圈速计时器：逐点喂入轨迹，实时输出当前圈 / 上一圈 / 最快圈 / Delta。
///
/// 判定阈值（全部可在构造时覆盖，下面的默认值就是接线默认值）：
/// - [crossingRadiusM] = 30 m：双重含义。越线模式下为计时线半宽：
///   过线点到边界点的沿线横向偏移超过该值不触发（防维修区通道横穿
///   计时线延长线误触发）；无中心线回落半径法时为穿越判定半径。
///   1Hz 采样下高速通过起终点时两点之间可能跨过 30 m 半径，因此
///   半径法判定不用“单点落入圆内”，而用“上一轨迹点到当前轨迹点的
///   线段到起终点的最短距离 < 半径”，同一判定也用于分段点。
///   越线模式下不存在跨点漏判：带符号距离变号即触发，与采样间隔无关。
/// - [minLapMs] = 30_000 ms：最短圈间隔。穿越后 30 秒内的再次穿越视为
///   同一圈内的 GPS 抖动 / 掉头，不计圈；同时穿越后必须先离开起终点
///   2 倍半径（60 m）之外才重新获得穿越资格（防原地抖动连触发）。
/// - [dwellSpeedMs] = 0.5 m/s、[dwellThresholdMs] = 30_000 ms：速度持续
///   低于 0.5 m/s 满 30 秒即判定停车：计时自动暂停（暂停时长不计入圈速），
///   且本圈标注“停留不计圈”；速度回升到 0.5 m/s 及以上时自动恢复计时。
/// - 分段：构造时传 2 个分段点（S1 终点、S2 终点）得 S1/S2/S3；不传则
///   退化为按圈时长中点切两段，界面须标注“无分段点，前后半圈示意”。
/// - 越线模式：构造时传 [centerline]（包中心线，内部按最近线段算切线）
///   或直接传 [startFinishTangent] / [sectorTangents]（显式切线优先于
///   中心线）；任一边界无切线时该边界单独回落半径法，其余边界不受影响。
/// - 维修区检测（v1.2.17）：构造时另传 [pitIn] / [pitOut]，仅两者均
///   非 null 且中心线可用（中心线非 null 且两点处均能算出切线）时
///   生效，否则整个维修区逻辑关闭。入口 / 出口线方向同样取中心线
///   最近线段切线（中心线反向时与起终点 / 分段线一同取反），横向
///   半宽复用 [crossingRadiusM]；判定复用越线 machinery。
/// - 段速（v1.2.17）：[sectorSpeeds] 与分段标签等长，只取 GPS 实测点；
///   无分段点时为空列表。
/// - 到下一计时线距离（v1.2.17）：[nextLineDistanceM] 沿中心线弧长算，
///   环形赛道按起终点处绕回；无中心线时为 null。
class LapTimer {
  /// 起终点经纬度（调用方传入：赛道起终点或用户点选的起终点）。
  final GeoPoint startFinish;

  /// 起终点穿越判定半径（m），默认 30。
  final double crossingRadiusM;

  /// 最短圈间隔（ms），默认 30 秒。
  final int minLapMs;

  /// 停车判定速度阈值（m/s），默认 0.5。
  final double dwellSpeedMs;

  /// 停车判定持续时长（ms），默认 30 秒。
  final int dwellThresholdMs;

  /// 分段点：空 = 无分段点（退化两段）；1 个 = S1/S2 两段；
  /// 2 个 = S1/S2/S3 三段。多于 2 个只取前 2 个。
  final List<GeoPoint> sectorPoints;

  /// 维修区入口点（v1.2.17）：仅与 [pitOut] 同传且中心线可用时生效。
  final GeoPoint? pitIn;

  /// 维修区出口点（v1.2.17）：仅与 [pitIn] 同传且中心线可用时生效。
  final GeoPoint? pitOut;

  /// 包中心线（原样保存，供 [nextLineDistanceM] 沿线算距）。
  final List<GeoPoint>? centerline;

  /// 每条计时边界（[0] = 起终点，[1..] = 分段点）：点 + 切线方向。
  /// 切线为 null 的边界用半径法回落（见 [_crossingTimeMs]）。
  final List<_Boundary> _boundaries;

  /// 维修区出入线（[0] = 入口，[1] = 出口）：点 + 切线方向。
  /// 仅 pitIn/pitOut 均传入且中心线可用时非 null，否则维修区
  /// 检测整体关闭（见 [_resolvePitBoundaries]）。
  final List<_Boundary>? _pitBoundaries;

  /// 中心线是否按行车反方向排序（起终点 / 分段线与维修区线
  /// 的切线已取反纠正；见 [_tangentsReversed]）。
  final bool _centerlineReversed;

  LapTimer({
    required this.startFinish,
    this.crossingRadiusM = 30,
    this.minLapMs = 30000,
    this.dwellSpeedMs = 0.5,
    this.dwellThresholdMs = 30000,
    List<GeoPoint> sectorPoints = const [],
    List<GeoPoint>? centerline,
    TrackDirection? startFinishTangent,
    List<TrackDirection>? sectorTangents,
    this.pitIn,
    this.pitOut,
  })  : sectorPoints = sectorPoints.take(2).toList(),
        centerline = centerline,
        _centerlineReversed = _tangentsReversed(
          startFinish,
          sectorPoints.take(2).toList(),
          centerline,
          startFinishTangent,
          sectorTangents,
        ),
        _pitBoundaries = _resolvePitBoundaries(
          pitIn,
          pitOut,
          centerline,
          startFinish,
          sectorPoints.take(2).toList(),
          startFinishTangent,
          sectorTangents,
        ),
        _boundaries = _resolveBoundaries(
          startFinish,
          sectorPoints.take(2).toList(),
          centerline,
          startFinishTangent,
          sectorTangents,
        ) {
    _resetSectorSpeeds();
  }

  /// 中心线是否按行车反方向排序（与 [_resolveBoundaries] 内的纠正
  /// 条件一致）：全部切线均来自中心线、且有 2 个分段点、且沿中心线
  /// 从起终点出发先遇到 S2 再遇到 S1。条件不满足时返回 false，
  /// 调用方按中心线本身按行车方向处理。
  static bool _tangentsReversed(
    GeoPoint startFinish,
    List<GeoPoint> sectorPoints,
    List<GeoPoint>? centerline,
    TrackDirection? startFinishTangent,
    List<TrackDirection>? sectorTangents,
  ) {
    if (centerline == null) return false;
    if (startFinishTangent != null) return false;
    if (sectorTangents != null && sectorTangents.isNotEmpty) return false;
    if (sectorPoints.length != 2) return false;
    final points = [startFinish, ...sectorPoints];
    if (points.any((p) => tangentAtPoint(centerline, p) == null)) {
      return false;
    }
    final f0 = centerlineFractionAt(centerline, startFinish);
    final f1 = centerlineFractionAt(centerline, sectorPoints[0]);
    final f2 = centerlineFractionAt(centerline, sectorPoints[1]);
    if (f0 == null || f1 == null || f2 == null) return false;
    // 从起终点出发沿中心线前进，应先遇到 S1 再遇到 S2；
    // 否则中心线是反向的，全部切线取反。
    final d1 = (f1 - f0) % 1.0;
    final d2 = (f2 - f0) % 1.0;
    return d1 > d2;
  }

  /// 解析维修区出入线的切线方向（v1.2.17）：入口 / 出口各为一条
  /// 计时线，方向取中心线在该点处最近线段的切线，与起终点 / 分段线
  /// 同一做法；中心线反向时切线与主边界一同取反。
  /// pitIn 与 pitOut 任一缺失、中心线缺失或不足 2 点、任一点处
  /// 算不出切线时返回 null，维修区检测整体关闭，不影响现有行为。
  static List<_Boundary>? _resolvePitBoundaries(
    GeoPoint? pitIn,
    GeoPoint? pitOut,
    List<GeoPoint>? centerline,
    GeoPoint startFinish,
    List<GeoPoint> sectorPoints,
    TrackDirection? startFinishTangent,
    List<TrackDirection>? sectorTangents,
  ) {
    if (pitIn == null || pitOut == null) return null;
    if (centerline == null || centerline.length < 2) return null;
    var tIn = tangentAtPoint(centerline, pitIn);
    var tOut = tangentAtPoint(centerline, pitOut);
    if (tIn == null || tOut == null) return null;
    if (_tangentsReversed(startFinish, sectorPoints, centerline,
        startFinishTangent, sectorTangents)) {
      tIn = TrackDirection(-tIn.east, -tIn.north);
      tOut = TrackDirection(-tOut.east, -tOut.north);
    }
    return [_Boundary(pitIn, tIn), _Boundary(pitOut, tOut)];
  }

  /// 解析每条边界的切线方向：显式切线 > 中心线最近线段切线 > null（半径法）。
  /// 有 2 个分段点且全部切线均来自中心线时，按起终点→S1→S2 的环形
  /// 顺序检查中心线方向：若顺序反了，说明中心线按行车反方向排序，
  /// 全部切线取反（反向中心线否则会让正向过线永远不触发、反向误触发）。
  static List<_Boundary> _resolveBoundaries(
    GeoPoint startFinish,
    List<GeoPoint> sectorPoints,
    List<GeoPoint>? centerline,
    TrackDirection? startFinishTangent,
    List<TrackDirection>? sectorTangents,
  ) {
    final points = [startFinish, ...sectorPoints];
    final fromCenterline =
        startFinishTangent == null && (sectorTangents == null || sectorTangents.isEmpty);
    var tangents = List<TrackDirection?>.generate(points.length, (i) {
      if (i == 0 && startFinishTangent != null) return startFinishTangent;
      if (i > 0 &&
          sectorTangents != null &&
          i - 1 < sectorTangents.length) {
        return sectorTangents[i - 1];
      }
      if (centerline != null) return tangentAtPoint(centerline, points[i]);
      return null;
    });
    if (fromCenterline &&
        centerline != null &&
        sectorPoints.length == 2 &&
        tangents.every((t) => t != null) &&
        _tangentsReversed(startFinish, sectorPoints, centerline,
            startFinishTangent, sectorTangents)) {
      // 中心线按行车反方向排序，全部切线取反（反向中心线否则会让
      // 正向过线永远不触发、反向误触发）。
      tangents =
          tangents.map((t) => TrackDirection(-t!.east, -t.north)).toList();
    }
    return List<_Boundary>.generate(
        points.length, (i) => _Boundary(points[i], tangents[i]));
  }

  final List<Lap> _laps = [];
  final List<int> _pointLapNumbers = [];
  final List<bool> _sectorCrossed = [];

  TimedPoint? _prev;
  TimedPoint? _last;
  int? _lapStartMs;
  int _currentLapNumber = 0; // 0 = 发车圈（第一次穿越前），未开始计时
  bool _canCross = true;
  bool _paused = false;
  int? _pauseStartMs;
  int _pausedMsCurrentLap = 0;
  bool _dwellInCurrentLap = false;
  int? _lowSpeedSinceMs;
  final List<int> _sectorSplitElapsed = [];

  // --- 维修区检测状态（v1.2.17） ---
  /// 是否正在维修区内（穿越入口线后、出口线前，与圈无关）。
  bool _inPit = false;

  /// 本次进维修区的入口穿越时刻（ms，插值时刻）；不在维修区内时为 null。
  int? _pitInMs;

  /// 本圈内是否穿越过维修区入口 / 出口线（完圈定 [Lap.kind] 用，
  /// [_startLap] 时清零；发车圈内的穿越不计入任何一圈）。
  bool _crossedPitInCurrentLap = false;
  bool _crossedPitOutCurrentLap = false;

  // --- 段速状态（v1.2.17） ---
  /// 当前圈各段内已喂入点的速度最低 / 最高（km/h），长度 =
  /// 分段数（sectorPoints.length + 1）；尚未喂入点的段为 null。
  final List<double?> _sectorMinKmh = [];
  final List<double?> _sectorMaxKmh = [];

  /// 是否正在维修区内：穿越入口线后为真，穿越出口线后为假。
  /// 维修区检测未生效（pitIn/pitOut 缺失或中心线不可用）时恒为假。
  bool get inPit => _inPit;

  /// 本次停站已用时长（ms）：在维修区内时为自入口穿越起的毫秒数
  /// （按最后喂入点的时间算），否则为 0。
  int get pitStopMs {
    if (!_inPit) return 0;
    final inMs = _pitInMs;
    final last = _last;
    if (inMs == null || last == null) return 0;
    final ms = last.timeMs - inMs;
    return ms < 0 ? 0 : ms;
  }

  /// 当前圈各段的速度区间（v1.2.17）：与分段标签等长（2 分段点 →
  /// 3 段，1 分段点 → 2 段），每段取该段内已喂入轨迹点速度
  /// （m/s 转 km/h）的最低 / 最高；尚未开始的段为 null。
  /// 无分段点时为空列表，不拼假段。只读快照，不改动计时状态。
  List<SectorSpeed?> get sectorSpeeds {
    if (sectorPoints.isEmpty) return const [];
    final n = sectorPoints.length + 1;
    return List<SectorSpeed?>.generate(n, (i) {
      if (i >= _sectorMinKmh.length) return null;
      final mn = _sectorMinKmh[i];
      final mx = _sectorMaxKmh[i];
      if (mn == null || mx == null) return null;
      return SectorSpeed(mn, mx);
    });
  }

  /// 到下一计时线的距离（m，v1.2.17）：当前位置沿中心线到按行进
  /// 方向最近的下一个边界点（分段点或起终点）的米数；沿中心线
  /// 弧长算，环形赛道按起终点处绕回。无中心线、无已喂入点、
  /// 中心线总长为 0、或无任何边界点时返回 null，不编数。
  /// 只读，不改动计时状态。
  double? get nextLineDistanceM {
    final cl = centerline;
    final last = _last;
    if (cl == null || cl.length < 2 || last == null) return null;
    final total = _centerlineTotalLengthM(cl);
    if (total <= 0) return null;
    final f = centerlineFractionAt(cl, GeoPoint(last.lat, last.lon));
    if (f == null) return null;
    var best = double.infinity;
    for (final b in [startFinish, ...sectorPoints]) {
      final fb = centerlineFractionAt(cl, b);
      if (fb == null) continue;
      // 中心线反向时行进方向为 fraction 递减（切线已取反，见构造）。
      var forward = _centerlineReversed ? (f - fb) % 1.0 : (fb - f) % 1.0;
      // 恰好压在线上时该边界算已过（取下一圈的同一条线），
      // 使过线后立即切到下一边界，不在过线瞬间闪 0。
      if (forward < 1e-9) forward = 1.0;
      final d = forward * total;
      if (d < best) best = d;
    }
    if (best == double.infinity) return null;
    return best;
  }

  /// 已完成的所有圈（含停留不计圈的圈，调用方按 [Lap.counted] 过滤显示）。
  List<Lap> get laps => List.unmodifiable(_laps);

  /// 上一圈（最近完成的一圈，含停留不计圈的圈；成绩榜用 [leaderboard]）。
  Lap? get lastLap => _laps.isEmpty ? null : _laps.last;

  /// 最快圈：只在计入成绩的圈里取最快；无计入圈时为 null。
  Lap? get bestLap {
    final counted = _laps.where((l) => l.counted).toList();
    if (counted.isEmpty) return null;
    counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    return counted.first;
  }

  /// 圈速榜：计入成绩的圈按圈速从快到慢排（停留不计圈的圈不进榜）。
  List<Lap> get leaderboard {
    final counted = _laps.where((l) => l.counted).toList();
    counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    return counted;
  }

  /// 当前圈号：0 表示还在发车圈（未第一次穿越起终点），否则为进行中的圈号。
  int get currentLapNumber => _currentLapNumber;

  /// 是否因停车处于自动暂停中。
  bool get isPaused => _paused;

  /// 当前圈已用时长（ms，已扣除暂停时长）；未开始计时时为 null。
  int? get currentLapMs {
    final start = _lapStartMs;
    final last = _last;
    if (start == null || last == null) return null;
    return last.timeMs - start - _effectivePausedMs(last.timeMs);
  }

  /// 与最快圈的 Delta（ms）= 当前圈已用时长 - 最快圈圈速。
  /// 负值表示当前圈比最快圈更快；无最快圈或未开始计时时为 null。
  int? get currentDeltaMs {
    final cur = currentLapMs;
    final best = bestLap;
    if (cur == null || best == null) return null;
    return cur - best.durationMs;
  }

  /// 进行中圈已完成分段的各段用时（ms，已扣除暂停时长）：
  /// 由本圈已触发的分段点时刻差算出（第 i 段 = 第 i 个分段点时刻
  /// 减上一分段点时刻，首段减圈起点）；未开始计时、或尚未触发
  /// 任何分段点时为空列表。只读快照，不改动任何计时状态。
  /// 注意：无分段点（sectorPoints 为空）时进行中圈没有已完成
  /// 分段，本 getter 恒为空——前后半圈切分只在完圈时
  /// （[_buildSectors]）才能确定，不得在进行中把半圈当成
  /// 已完成分段去算 delta。
  List<int> get currentCompletedSectorsMs {
    if (_lapStartMs == null) return const [];
    final sectors = <int>[];
    var prevSplit = 0;
    for (final split in _sectorSplitElapsed) {
      sectors.add(split - prevSplit);
      prevSplit = split;
    }
    return sectors;
  }

  /// 进行中圈当前分段已用耗时（ms，已扣除暂停时长）：
  /// = 当前圈已用时长 - 已完成分段用时之和；未开始计时时为 null。
  /// 只读，不改动计时状态。
  int? get currentSectorElapsedMs {
    final cur = currentLapMs;
    if (cur == null) return null;
    var done = 0;
    for (final s in currentCompletedSectorsMs) {
      done += s;
    }
    return cur - done;
  }

  /// 进行中圈已完成分段相对本节最佳圈的 delta（ms）：
  /// 第 i 项 = 本圈第 i 段实测 - 最佳圈第 i 段；负 = 更快，正 = 更慢。
  /// 长度 = 已完成分段数；对应位置无参照数据时（无最佳圈，或
  /// 最佳圈没有该段——分段口径不一致时）该项为 null，不得拿
  /// 错位的段相减。只读，参照圈固定为 [bestLap]，调用方不得
  /// 在此改参照口径。
  List<int?> get currentSectorDeltasVsBest {
    final completed = currentCompletedSectorsMs;
    final best = bestLap;
    return List<int?>.generate(completed.length, (i) {
      if (best == null || i >= best.sectorsMs.length) return null;
      return completed[i] - best.sectorsMs[i];
    });
  }

  /// 预测圈（ms，参照圈默认本节最佳圈）：
  /// = 已完成分段实测之和 + 参照圈从当前分段起的各段用时。
  /// 等价于参照圈总圈速 + 已完成分段 delta 之和：当前分段按
  /// 参照圈 pace 投影，当前分段已用耗时不另加——若在
  /// [currentLapMs] 之外再加参照圈剩余段，会把当前分段算两次；
  /// 若只加当前分段之后的参照段，则等于默认当前分段立即结束，
  /// 会系统性低估。两种错误算法本 getter 一律不用。
  /// 返回 null 的情形（不编数）：未开始计时；无最佳圈；参照圈
  /// 无分段数据；参照圈分段数 <= 已完成分段数（无剩余分段可
  /// 投影，或分段口径不一致）；无真实分段点（v1.2.15：无分段点
  /// 时已完成分段恒为空，本 getter 原会退化成“预测圈 = 最佳圈
  /// 总时长”，那个数不是预测，是把最佳圈原样复读，界面须显示
  /// 占位，不得拿它冒充预测圈）。
  int? get predictedLapMsVsBest {
    if (currentLapMs == null) return null;
    // v1.2.15：无真实分段点时不预测（见本 getter 文档）。
    if (sectorPoints.isEmpty) return null;
    final best = bestLap;
    if (best == null || best.sectorsMs.isEmpty) return null;
    final completed = currentCompletedSectorsMs;
    final k = completed.length;
    if (best.sectorsMs.length <= k) return null;
    var sum = 0;
    for (final s in completed) {
      sum += s;
    }
    for (var i = k; i < best.sectorsMs.length; i++) {
      sum += best.sectorsMs[i];
    }
    return sum;
  }

  /// 圈速稳定性（只统计计入圈）；计入圈不足 2 圈时为 null。
  LapStability? get stability {
    final ds =
        _laps.where((l) => l.counted).map((l) => l.durationMs.toDouble()).toList();
    if (ds.length < 2) return null;
    final mean = ds.reduce((a, b) => a + b) / ds.length;
    var sumSq = 0.0;
    for (final d in ds) {
      sumSq += (d - mean) * (d - mean);
    }
    final std = math.sqrt(sumSq / ds.length);
    final range = ds.reduce(math.max) - ds.reduce(math.min);
    return LapStability(
        count: ds.length, meanMs: mean, stdDevMs: std, rangeMs: range);
  }

  /// 逐点对应的圈号（与喂入点数一一对应）：
  /// 0 = 发车圈（第一次穿越前），N >= 1 = 第 N 圈。
  /// 供行程详情页按圈分段显示轨迹时分组用（见接线规格）。
  /// 穿越点本身归属新开始的一圈。
  List<int> get pointLapNumbers => List.unmodifiable(_pointLapNumbers);

  /// 喂入一个轨迹点（调用方按时间顺序喂，1Hz 即可）。
  void addPoint(TimedPoint p) {
    final prev = _prev;

    // 1) 停车 / 恢复判定（用当前点速度与时间戳；暂停时长在取值时统一扣除）。
    _updateDwell(p);

    // 2) 维修区出入线穿越判定（v1.2.17）：复用越线 machinery
    // （[_crossingTimeMs]），在起终点判定之前跑，使同一点同时
    // 穿越入站线与起终点时，圈种先记到正在关闭的这一圈上。
    // 维修区检测未生效时 [_pitBoundaries] 为 null，本步为空操作。
    if (_pitBoundaries != null) {
      final inMs = _crossingTimeMs(_pitBoundaries[0], prev, p);
      if (inMs != null) {
        _inPit = true;
        _pitInMs = inMs;
        if (_lapStartMs != null) _crossedPitInCurrentLap = true;
      }
      final outMs = _crossingTimeMs(_pitBoundaries[1], prev, p);
      if (outMs != null) {
        _inPit = false;
        _pitInMs = null;
        if (_lapStartMs != null) _crossedPitOutCurrentLap = true;
      }
    }

    // 3) 起终点穿越判定：有切线时为越线检测（返回插值过线时刻），
    // 无切线时回落半径法（返回当前点时刻，与旧行为一致）。
    final crossMs = _crossingTimeMs(_boundaries[0], prev, p);
    // 离开起终点 2 倍半径之外后，才重新获得穿越资格。
    if (_distanceM(p, startFinish) > crossingRadiusM * 2) {
      _canCross = true;
    }

    if (crossMs != null && _canCross) {
      if (_lapStartMs == null) {
        // 第一次穿越：发车圈结束，开始第 1 圈计时。
        _startLap(crossMs, 1);
        _canCross = false;
      } else if (crossMs - _lapStartMs! >= minLapMs) {
        // 完成一圈，立即开始下一圈（穿越点归属新圈）。
        _closeLap(crossMs);
        _startLap(crossMs, _currentLapNumber + 1);
        _canCross = false;
      }
      // 30 秒内的再次穿越：忽略（GPS 抖动），不关闭、不重启。
    }

    // 4) 分段点穿越判定（同样越线检测 / 半径法回落；每圈每段只记一次）。
    // 分段时刻同样用插值过线时刻，S1/S2/S3 由此切分。
    if (_lapStartMs != null && sectorPoints.isNotEmpty) {
      for (var i = 0; i < sectorPoints.length; i++) {
        if (_sectorCrossed[i]) continue;
        final hitMs = _crossingTimeMs(_boundaries[i + 1], prev, p);
        if (hitMs != null) {
          _sectorCrossed[i] = true;
          _sectorSplitElapsed.add(
              hitMs - _lapStartMs! - _effectivePausedMs(hitMs));
        }
      }
    }

    // 5) 记录当前段速度（v1.2.17）：点归属其穿越后所在的段
    // （分段点穿越已在步骤 4 更新 _sectorSplitElapsed；起终点
    // 穿越已在步骤 3 开新圈并清零段速）。
    if (_lapStartMs != null && sectorPoints.isNotEmpty) {
      final seg = _sectorSplitElapsed.length;
      if (seg < _sectorMinKmh.length) {
        final kmh = p.speed * 3.6;
        final mn = _sectorMinKmh[seg];
        final mx = _sectorMaxKmh[seg];
        _sectorMinKmh[seg] = mn == null ? kmh : math.min(mn, kmh);
        _sectorMaxKmh[seg] = mx == null ? kmh : math.max(mx, kmh);
      }
    }

    // 6) 记录本点归属圈号与最新点。
    _pointLapNumbers.add(_currentLapNumber);
    _prev = p;
    _last = p;
  }

  /// 单条边界的穿越判定，返回过线时刻（ms），未穿越返回 null。
  /// - 有切线：越线检测（见 [_lineCrossingMs]），时刻为两点间插值；
  /// - 无切线：半径法回落（线段到边界点最短距离 < 半径即命中），
  ///   时刻取当前点时间，与 v1.2.13 及之前行为一致。
  int? _crossingTimeMs(_Boundary b, TimedPoint? prev, TimedPoint cur) {
    if (b.tangent == null) {
      final hit = prev == null
          ? _distanceM(cur, b.point) < crossingRadiusM
          : _segmentDistanceM(prev, cur, b.point) < crossingRadiusM;
      return hit ? cur.timeMs : null;
    }
    if (prev == null) {
      // 首点无法判定越线（无前一点）：只记下带符号距离，供下一段比较。
      b.prevSignedM = _signedDistanceM(cur, b.point, b.tangent!);
      return null;
    }
    return _lineCrossingMs(b, prev, cur);
  }

  /// 越线检测：连续两定位点到计时线的带符号距离变号，且位移方向
  /// 与赛道方向一致（位移向量与切线点积 > 0），即判定过线。
  /// 过线时刻 = 两点间按带符号距离比例线性插值；
  /// 过线点横向偏移超过计时线半宽（[crossingRadiusM]）不触发。
  int? _lineCrossingMs(_Boundary b, TimedPoint prev, TimedPoint cur) {
    final t = b.tangent!;
    final sPrev = b.prevSignedM ?? _signedDistanceM(prev, b.point, t);
    final sCur = _signedDistanceM(cur, b.point, t);
    b.prevSignedM = sCur;
    double f;
    if (sPrev == 0 && sCur == 0) {
      return null; // 两点都在计时线上：沿线行驶，非过线
    } else if (sPrev == 0) {
      f = 0; // 上一点恰在线上：过线时刻即上一点时刻
    } else if (sCur == 0) {
      f = 1; // 当前点恰在线上：过线时刻即当前点时刻
    } else if (sPrev.sign != sCur.sign) {
      f = sPrev / (sPrev - sCur); // 带符号距离过零点的插值比例
    } else {
      return null; // 未变号：未过线
    }
    // 反向经过不触发：位移向量与切线方向点积须 > 0。
    if (!_movingForward(prev, cur, t)) return null;
    // 过线点横向偏移须落在计时线半宽内（防维修区通道横穿延长线）。
    final lat = prev.lat + (cur.lat - prev.lat) * f;
    final lon = prev.lon + (cur.lon - prev.lon) * f;
    if (_lateralOffsetM(lat, lon, b.point, t).abs() > crossingRadiusM) {
      return null;
    }
    return prev.timeMs + ((cur.timeMs - prev.timeMs) * f).round();
  }

  /// 定位点到计时线的带符号距离（m）：沿切线方向为正，
  /// 即计时线把空间分成“线前（负）/ 线后（正）”两半。
  double _signedDistanceM(TimedPoint p, GeoPoint g, TrackDirection t) {
    final meanLat = _rad((p.lat + g.lat) / 2);
    final east = (p.lon - g.lon) * math.cos(meanLat) * 111320;
    final north = (p.lat - g.lat) * 110540;
    return east * t.east + north * t.north;
  }

  /// 位移方向是否与赛道方向一致：位移向量与切线方向点积 > 0。
  bool _movingForward(TimedPoint a, TimedPoint b, TrackDirection t) {
    final meanLat = _rad((a.lat + b.lat) / 2);
    final east = (b.lon - a.lon) * math.cos(meanLat) * 111320;
    final north = (b.lat - a.lat) * 110540;
    return east * t.east + north * t.north > 0;
  }

  /// 给定经纬度点相对边界点的沿线横向偏移（m）：沿计时线方向为正，
  /// 计时线方向 = 切线逆时针旋转 90°（-north, east）。
  double _lateralOffsetM(
      double lat, double lon, GeoPoint g, TrackDirection t) {
    final meanLat = _rad((lat + g.lat) / 2);
    final east = (lon - g.lon) * math.cos(meanLat) * 111320;
    final north = (lat - g.lat) * 110540;
    return east * (-t.north) + north * t.east;
  }

  void _startLap(int timeMs, int number) {
    _lapStartMs = timeMs;
    _currentLapNumber = number;
    _paused = false;
    _pauseStartMs = null;
    _pausedMsCurrentLap = 0;
    _dwellInCurrentLap = false;
    _lowSpeedSinceMs = null;
    _sectorSplitElapsed.clear();
    _sectorCrossed.clear();
    _sectorCrossed.addAll(List.filled(sectorPoints.length, false));
    _crossedPitInCurrentLap = false;
    _crossedPitOutCurrentLap = false;
    _resetSectorSpeeds();
  }

  /// 段速累计清零（开圈时调；长度 = 分段数，尚未喂入点的段为 null）。
  void _resetSectorSpeeds() {
    _sectorMinKmh
      ..clear()
      ..addAll(List<double?>.filled(sectorPoints.length + 1, null));
    _sectorMaxKmh
      ..clear()
      ..addAll(List<double?>.filled(sectorPoints.length + 1, null));
  }

  void _closeLap(int endMs) {
    final start = _lapStartMs;
    if (start == null) return;
    final paused = _effectivePausedMs(endMs);
    final duration = endMs - start - paused;
    final sectors = _buildSectors(duration);
    // 圈种（v1.2.17）：本圈内穿越过出口线 → 出站圈；否则本圈内
    // 穿越过入口线 → 进站圈；否则飞驰圈。同圈双穿时出站圈优先。
    // 停车 30 秒自动暂停与 dwellNotCounted 规则原样保留。
    final kind = _crossedPitOutCurrentLap
        ? LapKind.outLap
        : _crossedPitInCurrentLap
            ? LapKind.inLap
            : LapKind.flying;
    _laps.add(Lap(
      number: _currentLapNumber,
      startMs: start,
      endMs: endMs,
      durationMs: duration,
      pausedMs: paused,
      dwellNotCounted: _dwellInCurrentLap,
      sectorsMs: sectors,
      kind: kind,
    ));
  }

  List<int> _buildSectors(int duration) {
    if (sectorPoints.isEmpty) {
      // 无分段点退化分段：按圈时长中点切两段（前半圈 / 后半圈示意）。
      final half = duration ~/ 2;
      return [half, duration - half];
    }
    // 有分段点：分段用时 = 各分段点时刻 - 上一分段点时刻，末段补到圈终点。
    final sectors = <int>[];
    var prevSplit = 0;
    for (final split in _sectorSplitElapsed) {
      sectors.add(split - prevSplit);
      prevSplit = split;
    }
    sectors.add(duration - prevSplit);
    return sectors;
  }

  void _updateDwell(TimedPoint p) {
    if (_lapStartMs == null) {
      // 发车圈不做停车判定（发车格等待不应污染第一圈）。
      _lowSpeedSinceMs = null;
      return;
    }
    if (p.speed < dwellSpeedMs) {
      _lowSpeedSinceMs ??= p.timeMs;
      if (!_paused &&
          p.timeMs - _lowSpeedSinceMs! >= dwellThresholdMs) {
        // 停车超阈值：自动暂停计时，本圈标注停留不计圈。
        _paused = true;
        _pauseStartMs = p.timeMs;
        _dwellInCurrentLap = true;
      }
    } else {
      // 速度恢复：结束暂停，暂停时长计入扣除。
      if (_paused && _pauseStartMs != null) {
        _pausedMsCurrentLap += p.timeMs - _pauseStartMs!;
      }
      _paused = false;
      _pauseStartMs = null;
      _lowSpeedSinceMs = null;
    }
  }

  int _effectivePausedMs(int atMs) {
    var paused = _pausedMsCurrentLap;
    if (_paused && _pauseStartMs != null) {
      paused += atMs - _pauseStartMs!;
    }
    return paused;
  }

  /// 圈速格式化：m:ss.mmm；null 显示占位。
  static String formatLapTime(int? ms) {
    if (ms == null || ms < 0) return '--:--.---';
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// Delta 格式化：带正负号，负为更快，如 -0:01.234 / +0:02.500。
  static String formatDelta(int? ms) {
    if (ms == null) return '--';
    final sign = ms < 0 ? '-' : '+';
    return sign + formatLapTime(ms.abs());
  }
}

/// 一条计时边界：点 + 切线方向（null = 无切线，该边界用半径法回落）。
/// [prevSignedM] 为上一轨迹点到计时线的带符号距离（仅越线模式使用，
/// 逐点更新；变号即过线）。
class _Boundary {
  final GeoPoint point;
  final TrackDirection? tangent;
  double? prevSignedM;
  _Boundary(this.point, this.tangent);
}

double _rad(double d) => d * math.pi / 180;

double _distanceM(TimedPoint p, GeoPoint g) {
  const r = 6371000.0;
  final dLat = _rad(g.lat - p.lat);
  final dLon = _rad(g.lon - p.lon);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(p.lat)) * math.cos(_rad(g.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// 线段（上一轨迹点 -> 当前轨迹点）到目标点的最短距离（m）。
/// 用等距圆柱投影近似（赛道尺度下误差可忽略），避免高速跨点漏判。
double _segmentDistanceM(TimedPoint a, TimedPoint b, GeoPoint g) {
  final meanLat = _rad((a.lat + b.lat) / 2);
  final ax = 0.0;
  final ay = 0.0;
  final bx = (b.lon - a.lon) * math.cos(meanLat) * 111320;
  final by = (b.lat - a.lat) * 110540;
  final gx = (g.lon - a.lon) * math.cos(meanLat) * 111320;
  final gy = (g.lat - a.lat) * 110540;
  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  double t = 0;
  if (lenSq > 0) {
    t = ((gx - ax) * dx + (gy - ay) * dy) / lenSq;
    t = t.clamp(0, 1);
  }
  final px = ax + t * dx;
  final py = ay + t * dy;
  return math.sqrt((gx - px) * (gx - px) + (gy - py) * (gy - py));
}
