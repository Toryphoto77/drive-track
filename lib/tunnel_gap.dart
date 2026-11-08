import 'dart:math' as math;

import 'models.dart';

/// 隧道丢卫星：缺口检测 + 事后补段 + 实时推算的纯逻辑。
///
/// 本文件不碰时钟、不碰网络、不碰平台通道，全部输入由调用方
/// （Recorder）传入，测试用假时间直接调。诚实规则：
/// - 推算点一律 `estimated=true`、hAcc=999、satCount=null、
///   altValid=false、G 值 0，绝不冒充实测；
/// - 无路网时只补 ≤2km，超长缺口不补、地图留虚线断开；
/// - 实时推算点在出口定位到达时由事后补段整段替换，
///   每时间戳只留一套点，不重复计里程。

/// 缺口 / 推算状态（挂在 Recorder 上，录制页药丸、地图、
/// 语音服务读同一份状态）。
enum GapStatus {
  /// 定位正常。
  ok,
  /// 已丢定位、尚未开始推算（3 秒门槛内或末速度过低）。
  lost,
  /// 缺口内正在出推算点。
  estimating,
}

/// 缺口判定常量。
class GapConstants {
  /// 超过该秒数无定位即判缺口。
  static const int gapAfterSeconds = 3;
  /// 末速度高于该值（km/h）才记缺口起点；停车/慢行丢星不补段。
  static const double minSpeedKmh = 5;
  /// 实时推算上限：秒数 / 距离，超了停发，留给事后补段。
  static const int maxEstimateSeconds = 120;
  static const double maxEstimateMeters = 3000;
  /// 无路网时事后补段的最长距离，超了不补。
  static const double maxChordFillMeters = 2000;
  /// 事后补段布点间隔（1Hz）。
  static const int fillIntervalMs = 1000;
}

/// 超过 [GapConstants.gapAfterSeconds] 秒无定位，且末速度
/// 高于 [GapConstants.minSpeedKmh] km/h 时判为缺口。
bool shouldStartGap({required int elapsedMs, required double lastSpeedMs}) {
  return elapsedMs > GapConstants.gapAfterSeconds * 1000 &&
      lastSpeedMs * 3.6 > GapConstants.minSpeedKmh;
}

/// 速度衰减模型（无 OBD 时的实时推算速度）：
/// 前 10 秒保持末速度，之后每 10 秒衰减 10%。
/// [elapsedSec] 为缺口内已过秒数（从缺口起点算）。
double decayedSpeed(double initialMs, double elapsedSec) {
  if (elapsedSec < 20) return initialMs;
  final steps = ((elapsedSec - 10) / 10).floor();
  return initialMs * math.pow(0.9, steps);
}

/// OBD 接入时，推算速度直接取 OBD 车速；未接 OBD 时用衰减模型。
/// [obdSpeedMs] 为 null = 未接 OBD。
double estimateSpeed({
  required double initialMs,
  required double elapsedSec,
  double? obdSpeedMs,
}) {
  if (obdSpeedMs != null) return obdSpeedMs;
  return decayedSpeed(initialMs, elapsedSec);
}

/// 按航向与速度从一点递推 1 秒后的位置（球面目的地公式）。
({double lat, double lon}) destPoint(
  double lat,
  double lon,
  double bearingDeg,
  double distanceM,
) {
  const r = 6371000.0;
  final d = distanceM / r;
  final br = bearingDeg * math.pi / 180;
  final lat1 = lat * math.pi / 180;
  final lon1 = lon * math.pi / 180;
  final lat2 = math.asin(math.sin(lat1) * math.cos(d) +
      math.cos(lat1) * math.sin(d) * math.cos(br));
  final lon2 = lon1 +
      math.atan2(
        math.sin(br) * math.sin(d) * math.cos(lat1),
        math.cos(d) - math.sin(lat1) * math.sin(lat2),
      );
  return (lat: lat2 * 180 / math.pi, lon: lon2 * 180 / math.pi);
}

double _bearingBetween(double lat1, double lon1, double lat2, double lon2) {
  final dLon = (lon2 - lon1) * math.pi / 180;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final y = math.sin(dLon) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

TrackPoint _estimatedPoint({
  required int timeMs,
  required double lat,
  required double lon,
  required double speed,
  required double bearing,
  required double alt,
  required String provider,
}) =>
    TrackPoint(
      timeMs: timeMs,
      lat: lat,
      lon: lon,
      alt: alt,
      altValid: false,
      speed: speed,
      bearing: bearing,
      hAcc: 999,
      vAcc: 999,
      speedAcc: 999,
      provider: provider,
      longG: 0,
      latG: 0,
      vertG: 0,
      pitch: 0,
      roll: 0,
      heading: bearing,
      pressureHpa: 0,
      calibrated: false,
      estimated: true,
    );

/// 事后补段：在 [start]（缺口起点，实测）与 [end]（出口，实测）
/// 之间按 1Hz 布推算点。速度由起点向终点线性过渡。
///
/// - [roadPolyline]：有路网时传入的隧道折线（lat,lon 序列，
///   tunnel=yes 的 way 优先，由调用方从 fetchRoadWaysAround
///   取）；无路网传 null，走入口→出口直线；
/// - 无路网且弦长 > [GapConstants.maxChordFillMeters] 时返回
///   空列表（不补、地图留虚线断开）；
/// - 时长不足 2 秒时无中间点，返回空列表。
/// 返回的点按时间升序，不含起终点本身。
List<TrackPoint> fillGap({
  required TrackPoint start,
  required TrackPoint end,
  List<(double lat, double lon)>? roadPolyline,
}) {
  final durationMs = end.timeMs - start.timeMs;
  if (durationMs < 2 * GapConstants.fillIntervalMs) return const [];
  final chordM = haversineM(start.lat, start.lon, end.lat, end.lon);
  final useRoad = roadPolyline != null && roadPolyline.length >= 2;
  if (!useRoad && chordM > GapConstants.maxChordFillMeters) return const [];
  final count = durationMs ~/ GapConstants.fillIntervalMs - 1;
  if (count <= 0) return const [];
  final out = <TrackPoint>[];
  // 沿路采样：把折线按累计长度归一化，按分数取点。
  List<double>? cum;
  double totalRoad = 0;
  if (useRoad) {
    final road = roadPolyline;
    cum = [0];
    for (var i = 1; i < road.length; i++) {
      totalRoad += haversineM(
          road[i - 1].$1, road[i - 1].$2, road[i].$1, road[i].$2);
      cum.add(totalRoad);
    }
    if (totalRoad <= 0) {
      cum = null;
      totalRoad = 0;
    }
  }
  (double, double) pointAtFraction(double f) {
    if (cum == null) {
      return (
        start.lat + (end.lat - start.lat) * f,
        start.lon + (end.lon - start.lon) * f,
      );
    }
    final target = totalRoad * f;
    var seg = 0;
    while (seg < cum.length - 2 && cum[seg + 1] < target) {
      seg++;
    }
    final segLen = cum[seg + 1] - cum[seg];
    final t = segLen <= 0 ? 0.0 : (target - cum[seg]) / segLen;
    final road = roadPolyline!;
    final a = road[seg];
    final b = road[seg + 1];
    return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
  }

  for (var i = 1; i <= count; i++) {
    final f = i / (count + 1);
    final pos = pointAtFraction(f);
    // 下一点位置用于算本段航向；最后一点用终点方向。
    final nextF = (i + 1) / (count + 1);
    final nextPos =
        i < count ? pointAtFraction(nextF) : (end.lat, end.lon);
    final bearing = _bearingBetween(pos.$1, pos.$2, nextPos.$1, nextPos.$2);
    out.add(_estimatedPoint(
      timeMs: start.timeMs + i * GapConstants.fillIntervalMs,
      lat: pos.$1,
      lon: pos.$2,
      speed: start.speed + (end.speed - start.speed) * f,
      bearing: bearing,
      alt: start.alt,
      provider: 'estimated',
    ));
  }
  return out;
}

/// 用事后补段替换缺口内的实时推算点：先删掉 [gapStartMs,
/// gapEndMs] 区间内的全部推算点，再把 [fill] 按时间顺序插回。
/// 实测点原样保留；返回新列表（不改原列表）。
List<TrackPoint> replaceLiveEstimates({
  required List<TrackPoint> points,
  required int gapStartMs,
  required int gapEndMs,
  required List<TrackPoint> fill,
}) {
  final kept = points
      .where((p) =>
          !(p.estimated && p.timeMs > gapStartMs && p.timeMs < gapEndMs))
      .toList();
  final out = [...kept, ...fill];
  out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return out;
}

/// 从路网里挑补段用的折线：tunnel=yes 的 way 优先，否则取离
/// [lat],[lon] 最近的 way。返回 null = 无可用路网，走弦补段。
/// [ways] 每项为 (points, tunnel)。
List<(double lat, double lon)>? chooseGapPolyline(
  double lat,
  double lon,
  List<({List<(double, double)> points, bool tunnel})> ways,
) {
  if (ways.isEmpty) return null;
  ({List<(double, double)> points, bool tunnel})? best;
  var bestD = double.infinity;
  for (final w in ways) {
    if (w.points.length < 2) continue;
    var d = double.infinity;
    for (final p in w.points) {
      d = math.min(d, haversineM(lat, lon, p.$1, p.$2));
    }
    // tunnel 优先：等效距离打 10 折后比较。
    final scored = w.tunnel ? d * 0.1 : d;
    if (scored < bestD) {
      bestD = scored;
      best = w;
    }
  }
  return best?.points;
}

/// 把一点投影到折线上最近的点（实时推算贴路用）。
/// 折线不足 2 点时原样返回。
({double lat, double lon}) projectOntoPolyline(
  double lat,
  double lon,
  List<(double lat, double lon)> polyline,
) {
  if (polyline.length < 2) return (lat: lat, lon: lon);
  var best = (lat: polyline.first.$1, lon: polyline.first.$2);
  var bestD = double.infinity;
  for (var i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    // 等距圆柱近似投影（隧道尺度下足够）。
    final dx = (b.$2 - a.$2) * math.cos(a.$1 * math.pi / 180);
    final dy = b.$1 - a.$1;
    final px = (lon - a.$2) * math.cos(a.$1 * math.pi / 180);
    final py = lat - a.$1;
    final len2 = dx * dx + dy * dy;
    final t = len2 <= 0 ? 0.0 : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
    final cand = (
      lat: a.$1 + dy * t,
      lon: a.$2 + (dx * t) / math.cos(a.$1 * math.pi / 180),
    );
    final d = haversineM(lat, lon, cand.lat, cand.lon);
    if (d < bestD) {
      bestD = d;
      best = cand;
    }
  }
  return best;
}

/// 推算里程（只计 estimated 点之间的段）与实测里程分开算，
/// 行程详情页分开列，驾驶评分只看实测。
double estimatedDistanceM(List<TrackPoint> points) {
  var d = 0.0;
  for (var i = 1; i < points.length; i++) {
    if (points[i].estimated || points[i - 1].estimated) {
      d += haversineM(points[i - 1].lat, points[i - 1].lon, points[i].lat,
          points[i].lon);
    }
  }
  return d;
}
