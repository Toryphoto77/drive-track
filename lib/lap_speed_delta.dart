import 'dart:math' as math;

/// 速度差分析（v1.7.0）：分析圈相对参照圈，按距离对齐后的速度差。
///
/// 只做插值对比，不改变任何原始数据；参照圈缺数据的一段不参与统计，
/// 点数不足返回 null，界面显示“数据不足”。
class LapSpeedDeltaSummary {
  const LapSpeedDeltaSummary({
    required this.avgDeltaKmh,
    required this.medianDeltaKmh,
    required this.maxGainKmh,
    required this.maxGainFraction,
    required this.maxLossKmh,
    required this.maxLossFraction,
    required this.pointCount,
  });

  /// 分析圈 − 参照圈的平均速度差（km/h，正 = 更快）。
  final double avgDeltaKmh;

  /// 分析圈 − 参照圈的中位速度差（km/h，正 = 更快）。中位数不受
  /// 个别异常点（如起步/停车段）拉偏，比平均值更能代表整体水平。
  final double medianDeltaKmh;

  /// 分析圈领先最多的一段。
  final double maxGainKmh;

  /// 该段在分析圈里的距离占比 0..1。
  final double maxGainFraction;

  /// 分析圈落后最多的一段（正数，含义为落后多少 km/h）。
  final double maxLossKmh;
  final double maxLossFraction;

  final int pointCount;
}

LapSpeedDeltaSummary? compareLapSpeeds({
  required List<double> selDistances,
  required List<double> selSpeedsKmh,
  required List<double> refDistances,
  required List<double> refSpeedsKmh,
}) {
  if (selDistances.length < 2 ||
      refDistances.length < 2 ||
      selDistances.length != selSpeedsKmh.length ||
      refDistances.length != refSpeedsKmh.length) {
    return null;
  }
  final total = selDistances.last;
  if (total <= 0) return null;

  var sum = 0.0;
  var count = 0;
  var maxGain = 0.0;
  var maxGainAt = 0.0;
  var maxLoss = 0.0;
  var maxLossAt = 0.0;
  final deltas = <double>[];

  for (var i = 0; i < selDistances.length; i++) {
    final d = selDistances[i];
    final refKmh = _interpolate(refDistances, refSpeedsKmh, d);
    if (refKmh == null) continue;
    final delta = selSpeedsKmh[i] - refKmh;
    sum += delta;
    count++;
    deltas.add(delta);
    if (delta > maxGain) {
      maxGain = delta;
      maxGainAt = d / total;
    }
    if (delta < -maxLoss) {
      maxLoss = -delta;
      maxLossAt = d / total;
    }
  }
  if (count == 0) return null;
  deltas.sort();
  final mid = deltas.length ~/ 2;
  final median = deltas.length.isOdd
      ? deltas[mid]
      : (deltas[mid - 1] + deltas[mid]) / 2;
  return LapSpeedDeltaSummary(
    avgDeltaKmh: sum / count,
    medianDeltaKmh: median,
    maxGainKmh: maxGain,
    maxGainFraction: maxGainAt.clamp(0.0, 1.0),
    maxLossKmh: maxLoss,
    maxLossFraction: maxLossAt.clamp(0.0, 1.0),
    pointCount: count,
  );
}

/// 在距离轴上线性插值速度；超出参照圈范围返回 null（不钳制端点，
/// 避免把参照圈边界的速度当成整段真实数据）。
double? _interpolate(List<double> xs, List<double> ys, double x) {
  if (x < xs.first || x > xs.last) return null;
  var lo = 0;
  var hi = xs.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (xs[mid] <= x) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final x0 = xs[lo];
  final x1 = xs[hi];
  final y0 = ys[lo];
  final y1 = ys[hi];
  if ((x1 - x0).abs() < 1e-9) return y1;
  return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
}

/// 速度差评级（评估项）：按平均速度差与时间差给出定性判断。
/// 只做事实映射，不生成“驾驶技术好/差”之类的主观结论。
String speedDeltaVerdict(double avgDeltaKmh) {
  if (avgDeltaKmh >= 3) return '整体明显更快';
  if (avgDeltaKmh >= 1) return '整体略快';
  if (avgDeltaKmh <= -3) return '整体明显更慢';
  if (avgDeltaKmh <= -1) return '整体略慢';
  return '整体基本持平';
}

/// 供界面显示：把秒差格式化为 +0.123s / -0.123s。
String formatDeltaSeconds(double seconds) {
  final v = seconds.abs();
  final sign = seconds > 0.0005 ? '+' : (seconds < -0.0005 ? '-' : '±');
  final minutes = v ~/ 60;
  if (minutes >= 1) {
    final s = v % 60;
    return '$sign${minutes.toStringAsFixed(0)}:'
        '${s.toStringAsFixed(3).padLeft(6, '0')}';
  }
  return '$sign${v.toStringAsFixed(3)}s';
}

/// 百分比位置显示（用于“最大领先/落后发生在 xx%”）。
String formatPercent(double fraction) =>
    '${(math.max(0, math.min(1, fraction)) * 100).toStringAsFixed(0)}%';
