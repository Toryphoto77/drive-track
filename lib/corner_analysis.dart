import 'dart:math' as math;

import 'models.dart';

/// 弯角分析（v1.7.0）：只从已有轨迹点算，不依赖 IMU 标定。
///
/// 方法：用三点外接圆半径估算局部曲率，半径小于阈值且持续若干采样点
/// 的连续段视为弯；再按航向角累计变化量过滤掉直道抖动与变道。
/// 每弯给出入弯 / 弯心 / 出弯速度、最短速度、最大横向 G（仅在
/// 传感器已标定时）、弯长、走线跨度。数据不足时返回空列表，界面
/// 显示“数据不足”，绝不补造弯角。
enum CornerDirection { left, right }

class CornerAnalysis {
  const CornerAnalysis({
    required this.index,
    required this.direction,
    required this.entryIndex,
    required this.apexIndex,
    required this.exitIndex,
    required this.entryKmh,
    required this.apexKmh,
    required this.exitKmh,
    required this.minKmh,
    required this.durationMs,
    required this.lengthM,
    required this.lineSpanM,
    required this.apexDistanceM,
    this.maxLateralG,
  });

  /// 从 1 开始的弯序（按出现顺序）。
  final int index;
  final CornerDirection direction;

  /// 在传入点列表里的下标。
  final int entryIndex;
  final int apexIndex;
  final int exitIndex;

  final double entryKmh;
  final double apexKmh;
  final double exitKmh;
  final double minKmh;
  final int durationMs;
  final double lengthM;

  /// 走线跨度：弯内轨迹点相对入弯—出弯连线的最大垂距（米），
  /// 反映实际走线有多宽，不是赛道宽度。
  final double lineSpanM;

  /// 弯心距切片起点的累计距离（米）。
  final double apexDistanceM;

  /// 最大横向 G；无标定传感器时为 null（界面显示“—”，不当 0）。
  final double? maxLateralG;
}

/// 识别弯角。参数默认值针对 1Hz 轨迹点，可按数据源调整。
List<CornerAnalysis> analyzeCorners(
  List<TrackPoint> points, {
  double maxRadiusM = 90,
  double minSpeedMps = 3,
  double minTurnDeg = 20,
  int minSamples = 2,
  int maxCorners = 60,
}) {
  if (points.length < 6) return const [];

  // 累计距离（米）。
  final dists = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    dists[i] =
        dists[i - 1] +
        _haversineM(
          points[i - 1].lat,
          points[i - 1].lon,
          points[i].lat,
          points[i].lon,
        );
  }

  // 候选点：三点外接圆半径足够小，且速度不为零。
  final candidates = <int>[];
  for (var i = 2; i < points.length - 2; i++) {
    final p = points[i];
    if (p.speed < minSpeedMps) continue;
    final r = _circleRadiusM(points[i - 2], p, points[i + 2]);
    if (r != null && r <= maxRadiusM) candidates.add(i);
  }
  if (candidates.isEmpty) return const [];

  // 聚类：索引间隔 <= 3 视为同一个弯。
  final clusters = <List<int>>[];
  var current = <int>[candidates.first];
  for (var i = 1; i < candidates.length; i++) {
    if (candidates[i] - candidates[i - 1] <= 3) {
      current.add(candidates[i]);
    } else {
      clusters.add(current);
      current = <int>[candidates[i]];
    }
  }
  clusters.add(current);

  final corners = <CornerAnalysis>[];
  for (final cluster in clusters) {
    if (cluster.length < minSamples) continue;
    final start = cluster.first;
    final end = cluster.last;

    // 航向累计变化：不足阈值的当直道抖动 / 变道丢弃。
    var turn = 0.0;
    for (var i = start; i <= end; i++) {
      turn += _bearingDelta(_course(points[i - 1]), _course(points[i]));
    }
    if (turn.abs() < minTurnDeg) continue;

    var apex = start;
    for (var i = start; i <= end; i++) {
      if (points[i].speed < points[apex].speed) apex = i;
    }
    final entryIdx = start > 0 ? start - 1 : start;
    final exitIdx = end + 1 < points.length ? end + 1 : end;

    double? maxLat;
    for (var i = start; i <= end; i++) {
      final p = points[i];
      if (!p.calibrated) continue;
      final v = p.latG.abs();
      if (maxLat == null || v > maxLat) maxLat = v;
    }

    corners.add(
      CornerAnalysis(
        index: corners.length + 1,
        direction: turn >= 0 ? CornerDirection.right : CornerDirection.left,
        entryIndex: entryIdx,
        apexIndex: apex,
        exitIndex: exitIdx,
        entryKmh: points[entryIdx].speed * 3.6,
        apexKmh: points[apex].speed * 3.6,
        exitKmh: points[exitIdx].speed * 3.6,
        minKmh:
            points
                .sublist(start, end + 1)
                .map((p) => p.speed)
                .reduce(math.min) *
            3.6,
        durationMs: points[end].timeMs - points[start].timeMs,
        lengthM: dists[end] - dists[start],
        lineSpanM: _lineSpanM(points, dists, entryIdx, exitIdx),
        apexDistanceM: dists[apex],
        maxLateralG: maxLat,
      ),
    );
    if (corners.length >= maxCorners) break;
  }
  return corners;
}

/// 三点外接圆半径；三点退化共线 / 距离过近时返回 null。
double? _circleRadiusM(TrackPoint a, TrackPoint b, TrackPoint c) {
  final ab = _haversineM(a.lat, a.lon, b.lat, b.lon);
  final bc = _haversineM(b.lat, b.lon, c.lat, c.lon);
  final ca = _haversineM(c.lat, c.lon, a.lat, a.lon);
  if (ab < 0.5 || bc < 0.5 || ca < 0.5) return null;
  final s = (ab + bc + ca) / 2;
  final areaSq = s * (s - ab) * (s - bc) * (s - ca);
  if (areaSq <= 1e-9) return null;
  final area = math.sqrt(areaSq);
  if (area <= 1e-6) return null;
  return (ab * bc * ca) / (4 * area);
}

/// 走线跨度：入弯点到出弯点连线，弯内各点到该连线的最大垂距（米）。
double _lineSpanM(
  List<TrackPoint> points,
  List<double> dists,
  int entry,
  int exit,
) {
  if (exit - entry < 2) return 0;
  final origin = points[entry];
  final cosLat = math.cos(origin.lat * math.pi / 180);
  double x(TrackPoint p) => (p.lon - origin.lon) * 111320 * cosLat;
  double y(TrackPoint p) => (p.lat - origin.lat) * 110540;
  final ex = x(points[exit]);
  final ey = y(points[exit]);
  final chord = math.sqrt(ex * ex + ey * ey);
  if (chord < 1) return 0;
  var maxDev = 0.0;
  for (var i = entry + 1; i < exit; i++) {
    final px = x(points[i]);
    final py = y(points[i]);
    final dev = (px * ey - py * ex).abs() / chord;
    if (dev > maxDev) maxDev = dev;
  }
  return maxDev;
}

double _course(TrackPoint p) => p.bearing.abs() > 0.01 ? p.bearing : p.heading;

double _bearingDelta(double from, double to) {
  var d = to - from;
  while (d > 180) {
    d -= 360;
  }
  while (d < -180) {
    d += 360;
  }
  return d;
}

/// 两点的球面距离（米）。
double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const earth = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
