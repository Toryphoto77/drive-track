import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// v1.3.6：视频回顾页地图仪表（诚实回放叠加）。
///
/// 只画本行程实测轨迹点（`Trip.points`），不画任何假线、不插值。
/// - 轨迹点过少（<2 个或全部重合）时显示占位文案，不画假线；
/// - 当前位置取调用方按行程时间二分到的轨迹点（与回顾页 `_pointAt`
///   同口径），朝向由相邻轨迹点算出，算不出时只画圆点、不编方向；
/// - 速度取该点的 `speed` 字段（m/s → km/h），速度无效（NaN / 负值）
///   时不显示速度、不编数；
/// - 本仪表只在本页回放时叠加（与 HUD 同层逻辑），不同步进导出的
///   视频文件；同步复用回顾页既有 250ms 轮询，不另起高频定时器。

/// 轨迹经纬度范围（实测点算出）。
typedef VideoGaugeBounds = ({
  double minLat,
  double maxLat,
  double minLon,
  double maxLon,
});

/// 由实测点列算范围；点不足 2 个或范围退化（全部重合）时返回 null。
VideoGaugeBounds? videoGaugeBounds(List<TrackPoint> points) {
  if (points.length < 2) return null;
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLon = points.first.lon;
  var maxLon = points.first.lon;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  if ((maxLat - minLat).abs() < 1e-9 && (maxLon - minLon).abs() < 1e-9) {
    return null;
  }
  return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
}

/// 经纬度 → 仪表画布坐标（等比适配，居中，留 [padding] 边距）。
/// 单向跨度为 0 时按该向居中，不除零、不编造跨度。
Offset videoGaugeProject({
  required VideoGaugeBounds bounds,
  required double lat,
  required double lon,
  required Size size,
  double padding = 8,
}) {
  final midLat = (bounds.minLat + bounds.maxLat) / 2;
  final cosLat = math.cos(midLat * math.pi / 180).abs().clamp(0.01, 1.0);
  final spanXM = (bounds.maxLon - bounds.minLon).abs() * 111320 * cosLat;
  final spanYM = (bounds.maxLat - bounds.minLat).abs() * 110540;
  final availW = math.max(1.0, size.width - padding * 2);
  final availH = math.max(1.0, size.height - padding * 2);
  final scaleX = spanXM > 0 ? availW / spanXM : double.infinity;
  final scaleY = spanYM > 0 ? availH / spanYM : double.infinity;
  var scale = math.min(scaleX, scaleY);
  if (!scale.isFinite) scale = 1.0;
  final wM = spanXM * scale;
  final hM = spanYM * scale;
  final originX = (size.width - wM) / 2;
  final originY = (size.height - hM) / 2;
  final xM = (lon - bounds.minLon) * 111320 * cosLat * scale;
  // 纬度向北为正，画布 y 向下为正，故取反。
  final yM = (bounds.maxLat - lat) * 110540 * scale;
  return Offset(originX + xM, originY + yM);
}

/// 行程时间 → 轨迹点下标（二分取 timeMs ≤ tripMs 的最后一点，与
/// 回顾页 `_pointAt` 同口径）；点列为空返回 -1。
int videoGaugePointIndex(List<TrackPoint> points, int tripMs) {
  if (points.isEmpty) return -1;
  var lo = 0, hi = points.length - 1, ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (points[mid].timeMs <= tripMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// 由相邻轨迹点算朝向（度，正北为 0、顺时针；东 90 / 南 180 / 西 270）。
/// 优先用 前一点→后一点；端点处退化为 当前点→下一（上一）点；
/// 相邻点重合、算不出时返回 null（调用方只画圆点，不编方向）。
double? videoGaugeHeadingDeg(List<TrackPoint> points, int index) {
  if (points.isEmpty || index < 0 || index >= points.length) return null;
  final cur = points[index];
  TrackPoint? a, b;
  if (index > 0 && index < points.length - 1) {
    a = points[index - 1];
    b = points[index + 1];
  } else if (index == 0 && points.length > 1) {
    a = cur;
    b = points[1];
  } else if (index == points.length - 1 && points.length > 1) {
    a = points[index - 1];
    b = cur;
  }
  if (a == null || b == null) return null;
  final cosLat = math.cos(cur.lat * math.pi / 180).abs().clamp(0.01, 1.0);
  final dx = (b.lon - a.lon) * 111320 * cosLat;
  final dy = (b.lat - a.lat) * 110540;
  if (dx.abs() < 1e-9 && dy.abs() < 1e-9) return null;
  var deg = math.atan2(dx, dy) * 180 / math.pi;
  if (deg < 0) deg += 360;
  return deg;
}

/// 该点速度（km/h）；速度无效（NaN / 负值）时返回 null，不编数。
/// 注意：`TrackPoint.speed` 为非空 double，0 是合法的静止速度，
/// 只有 NaN / 负值才视为“无速度值”。
double? videoGaugeSpeedKmh(TrackPoint point) {
  if (point.speed.isNaN || point.speed < 0) return null;
  return point.speed * 3.6;
}

/// 地图仪表在视频画面上的位置（三档，默认右上）。
enum VideoGaugePosition { topLeft, topRight, bottomRight }

extension VideoGaugePositionLabel on VideoGaugePosition {
  String get label => switch (this) {
        VideoGaugePosition.topLeft => '左上',
        VideoGaugePosition.topRight => '右上',
        VideoGaugePosition.bottomRight => '右下',
      };

  /// 下一档（右上 → 右下 → 左上 → 右上）。
  VideoGaugePosition get next => switch (this) {
        VideoGaugePosition.topRight => VideoGaugePosition.bottomRight,
        VideoGaugePosition.bottomRight => VideoGaugePosition.topLeft,
        VideoGaugePosition.topLeft => VideoGaugePosition.topRight,
      };
}

/// 视频回顾页地图仪表：实测轨迹轮廓 + 当前位置点 + 朝向箭头 +
/// 当前速度小字。画布区 IgnorePointer，不挡播放控制；位置切换与
/// 隐藏按钮由调用方放在仪表角上（本 widget 只负责画）。
class VideoMapGauge extends StatelessWidget {
  final List<TrackPoint> points;
  final TrackPoint? current;
  final double width;
  final double height;

  const VideoMapGauge({
    super.key,
    required this.points,
    required this.current,
    this.width = 148,
    this.height = 112,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = videoGaugeBounds(points);
    final speedKmh = current == null ? null : videoGaugeSpeedKmh(current!);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bounds == null)
            const SizedBox(
              height: 76,
              child: Center(
                child: Text(
                  '轨迹点不足，无法画地图',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SizedBox(
              width: width - 8,
              height: 76,
              child: CustomPaint(
                painter: _VideoGaugePainter(
                  points: points,
                  current: current,
                  bounds: bounds,
                ),
              ),
            ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '轨迹地图',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              // 无速度值时不显示速度，不编数。
              if (speedKmh != null)
                Text(
                  '${speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoGaugePainter extends CustomPainter {
  final List<TrackPoint> points;
  final TrackPoint? current;
  final VideoGaugeBounds bounds;

  _VideoGaugePainter({
    required this.points,
    required this.current,
    required this.bounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = videoGaugeProject(
        bounds: bounds,
        lat: points[i].lat,
        lon: points[i].lon,
        size: size,
      );
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final cur = current;
    if (cur == null) return;
    final pos = videoGaugeProject(
      bounds: bounds,
      lat: cur.lat,
      lon: cur.lon,
      size: size,
    );
    final index = videoGaugePointIndex(points, cur.timeMs);
    final heading = index >= 0 ? videoGaugeHeadingDeg(points, index) : null;
    if (heading != null) {
      // 朝向箭头：画布 x 向东、y 向下；正北为 0 顺时针的朝向角
      // 对应画布方向向量 (sin h, -cos h)。
      final rad = heading * math.pi / 180;
      final dir = Offset(math.sin(rad), -math.cos(rad));
      final angle = math.atan2(dir.dy, dir.dx);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle);
      final arrow = Path()
        ..moveTo(9, 0)
        ..lineTo(-6, -5)
        ..lineTo(-3, 0)
        ..lineTo(-6, 5)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()..color = Colors.red,
      );
      canvas.restore();
    }
    // 当前位置点（有朝向时画在箭头尾部中央，无朝向时只画圆点）。
    canvas.drawCircle(
      pos,
      4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      pos,
      4,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoGaugePainter old) =>
      old.points != points || old.current != current || old.bounds != bounds;
}
