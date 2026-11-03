import 'dart:math' as math;
import 'models.dart';

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// 事件检测。轨迹点是 1Hz 汇总点：一点超阈值即代表该秒均值超阈值，
/// 满足“持续 0.5 秒以上”的口径；颠簸用 GPS 速度变化交叉验证。
List<TripEvent> detectEvents(List<TrackPoint> pts, TripMode mode) {
  final th = ModeThresholds.of(mode);
  final out = <TripEvent>[];
  if (pts.length < 3) return out;

  void addGroup(String kind, int s, int e) {
    final seg = pts.sublist(s, e + 1);
    final peakLong = seg.map((p) => p.longG).reduce((a, b) => a.abs() > b.abs() ? a : b);
    final peakLat = seg.map((p) => p.latG).reduce((a, b) => a.abs() > b.abs() ? a : b);
    final entry = s > 0 ? pts[s - 1].speed : seg.first.speed;
    final exit = e + 1 < pts.length ? pts[e + 1].speed : seg.last.speed;
    final minV = seg.map((p) => p.speed).reduce(math.min);
    // GPS 交叉验证：急加速/急刹车必须伴随速度同向变化，否则当作颠簸丢弃。
    if (kind == 'harshAccel' && exit - entry < 0.5) return;
    if (kind == 'harshBrake' && entry - exit < 0.5) return;
    double leanL = 0, leanR = 0;
    for (final p in seg) {
      if (p.roll < 0) leanL = math.max(leanL, -p.roll);
      if (p.roll > 0) leanR = math.max(leanR, p.roll);
    }
    double apex = 0;
    if (seg.isNotEmpty) {
      final apexPt = seg.reduce((a, b) => a.speed < b.speed ? a : b);
      apex = apexPt.roll;
    }
    out.add(TripEvent(
      kind: kind,
      startMs: pts[s].timeMs,
      endMs: pts[e].timeMs,
      startIndex: s,
      endIndex: e,
      peakLongG: peakLong,
      peakLatG: peakLat,
      entrySpeed: entry,
      minSpeed: minV,
      exitSpeed: exit,
      maxLeanLeft: leanL,
      maxLeanRight: leanR,
      leanAtApex: apex,
    ));
  }

  // 纵向事件
  int? runStart;
  String? runKind;
  void flushRun(int end) {
    if (runStart != null && runKind != null) addGroup(runKind!, runStart!, end);
    runStart = null;
    runKind = null;
  }

  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    if (!p.calibrated) continue;
    String? k;
    if (p.longG > th.harshAccel) {
      k = 'harshAccel';
    } else if (p.longG < th.harshBrake) {
      k = 'harshBrake';
    }
    if (k == runKind) continue;
    if (runStart != null) flushRun(i - 1);
    if (k != null) {
      runStart = i;
      runKind = k;
    }
  }
  if (runStart != null) flushRun(pts.length - 1);

  // 过弯：横向 G 超阈值的连续段，且累计航向变化 >= 20 度才算弯，排除变道抖动。
  int? cStart;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final over = p.calibrated && p.latG.abs() > th.harshCorner && p.speed > 3;
    if (over && cStart == null) cStart = i;
    if ((!over || i == pts.length - 1) && cStart != null) {
      final e = over ? i : i - 1;
      var turn = 0.0;
      for (var j = cStart + 1; j <= e; j++) {
        var d = (pts[j].heading - pts[j - 1].heading).abs();
        if (d > 180) d = 360 - d;
        turn += d;
      }
      if (turn >= 20) addGroup('corner', cStart, e);
      cStart = null;
    }
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}

class ScoreResult {
  final double total;
  final Map<String, double> sub;
  final List<String> reasons;
  const ScoreResult(this.total, this.sub, this.reasons);
}

/// 评分：只用自有传感器数据；没有可靠限速源之前不算超速分。
ScoreResult scoreTrip(TripMode mode, List<TrackPoint> pts, List<TripEvent> events) {
  if (pts.length < 10) return const ScoreResult(0, {}, ['数据太少，未评分']);
  double distKm = 0;
  for (var i = 1; i < pts.length; i++) {
    distKm += haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon) / 1000;
  }
  final per100 = distKm > 0.1 ? 100 / distKm : 100.0;
  final nAccel = events.where((e) => e.kind == 'harshAccel').length;
  final nBrake = events.where((e) => e.kind == 'harshBrake').length;
  final nCorner = events.where((e) => e.kind == 'corner').length;
  final reasons = <String>[];
  if (nBrake > 0) reasons.add('急刹车 $nBrake 次');
  if (nAccel > 0) reasons.add('急加速 $nAccel 次');
  if (nCorner > 0) reasons.add('过弯偏急 $nCorner 次');

  if (mode == TripMode.bike) {
    final splits = paceSplitsKm(pts);
    double paceScore = 100;
    if (splits.length >= 3) {
      final mean = splits.reduce((a, b) => a + b) / splits.length;
      final sd = math.sqrt(splits.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / splits.length);
      paceScore = _clamp(100 - (mean > 0 ? sd / mean * 300 : 0), 40, 100);
    }
    final powers = pts.where((p) => p.powerW != null).map((p) => p.powerW!).toList();
    double powerScore = 100;
    if (powers.length >= 10) {
      final mean = powers.reduce((a, b) => a + b) / powers.length;
      final sd = math.sqrt(powers.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / powers.length);
      powerScore = _clamp(100 - (mean > 0 ? sd / mean * 200 : 0), 40, 100);
    }
    final total = paceScore * 0.6 + powerScore * 0.4;
    return ScoreResult(
      total,
      {'配速稳定': paceScore, '功率稳定': powerScore},
      reasons.isEmpty ? ['配速平稳'] : reasons,
    );
  }

  final smooth = _clamp(100 - (nAccel * per100 * 8 + nBrake * per100 * 10), 30, 100);
  final corner = _clamp(100 - nCorner * per100 * 10, 30, 100);
  final moving = pts.where((p) => p.speed > 3).map((p) => p.speed).toList();
  double stability = 100;
  if (moving.length >= 10) {
    final mean = moving.reduce((a, b) => a + b) / moving.length;
    final sd = math.sqrt(moving.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / moving.length);
    stability = _clamp(100 - (mean > 0 ? sd / mean * 150 : 0), 40, 100);
  }
  final total = smooth * 0.4 + corner * 0.35 + stability * 0.25;
  return ScoreResult(total, {'平顺': smooth, '过弯': corner, '速度稳定': stability},
      reasons.isEmpty ? ['驾驶平稳，无急加速 / 急刹车 / 偏急过弯'] : reasons);
}

/// 每公里配速（分钟/公里），按累计里程切分。
List<double> paceSplitsKm(List<TrackPoint> pts) {
  final out = <double>[];
  if (pts.length < 2) return out;
  var acc = 0.0;
  var segStart = pts.first.timeMs;
  for (var i = 1; i < pts.length; i++) {
    acc += haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
    if (acc >= 1000) {
      final mins = (pts[i].timeMs - segStart) / 60000;
      out.add(mins * (1000 / acc));
      acc = 0;
      segStart = pts[i].timeMs;
    }
  }
  return out;
}

/// 指数平滑（显示用，不改原始记录）。
double smoothG(double prev, double raw, [double alpha = 0.35]) => prev + alpha * (raw - prev);
