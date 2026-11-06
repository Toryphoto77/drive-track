/// v1.3.7：赛后分析页「3D 回放」。
///
/// 只画本行程实测轨迹点（`Trip.points`），不插值、不编数：
/// - 轨迹点过少（<2 个）时显示占位文案，不启动回放；
/// - 回放按轨迹点时间戳推进（Timer 100ms 一跳 × 倍速），
///   位置取 [replayPointAt] 二分到的实测点，不插值造点；
/// - 速度/时间取当前实测点的 `speed` / `timeMs`，速度无效
///   （NaN / 负值）时不显示速度、不编数；
/// - 3D 透视投影复用 lib/perspective_projection.dart（与记录页
///   同一套数学：相机高 140 米、地平线 16%、车标 72%），
///   朝向与速度取值复用 lib/video_map_gauge.dart 的纯函数，
///   速度着色复用 lib/track_analysis_geo.dart 的彩虹色阶；
///   本文件不另写一套 3D 渲染，不叠卫星底图、不拉路网、不读缓存。
///
/// 视口：北向上固定视口（headingUp=false），投影中心取轨迹
/// 南缘外 55 米（全部点前向距离 > 0，透视因子 < 1，纵向恒在
/// 地平线与车标线之间）；横向按全部实测点投影跨度等比适配，
/// 整条轨迹始终在画内，不跟随、不旋转。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'perspective_projection.dart';
import 'track_analysis_geo.dart';
import 'video_map_gauge.dart';

/// 回放倍速。
enum ReplaySpeed { x1, x2, x4 }

extension ReplaySpeedLabel on ReplaySpeed {
  double get factor => switch (this) {
        ReplaySpeed.x1 => 1,
        ReplaySpeed.x2 => 2,
        ReplaySpeed.x4 => 4,
      };

  String get label => switch (this) {
        ReplaySpeed.x1 => '1x',
        ReplaySpeed.x2 => '2x',
        ReplaySpeed.x4 => '4x',
      };
}

/// 回放总时长（毫秒，末点 − 首点）；点不足 2 个时为 0，不启动回放。
int replayTotalMs(List<TrackPoint> points) {
  if (points.length < 2) return 0;
  final total = points.last.timeMs - points.first.timeMs;
  return total > 0 ? total : 0;
}

/// 已播毫秒 → 轨迹点下标（二分取 timeMs ≤ 目标的最后一点，
/// 与 videoGaugePointIndex 同口径）；越界钳制到首/末点；
/// 点不足 2 个时返回 -1。
int replayPointIndex(List<TrackPoint> points, int elapsedMs) {
  if (points.length < 2) return -1;
  final target = points.first.timeMs + elapsedMs;
  if (target <= points.first.timeMs) return 0;
  if (target >= points.last.timeMs) return points.length - 1;
  var lo = 0, hi = points.length - 1, ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (points[mid].timeMs <= target) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// 已播毫秒 → 当前实测点；点不足 2 个时返回 null（不编点）。
TrackPoint? replayPointAt(List<TrackPoint> points, int elapsedMs) {
  final i = replayPointIndex(points, elapsedMs);
  return i < 0 ? null : points[i];
}

/// 已播毫秒 → 进度 0..1；总时长 ≤ 0 时为 0。
double replayProgressMs(int elapsedMs, int totalMs) {
  if (totalMs <= 0) return 0;
  return (elapsedMs / totalMs).clamp(0.0, 1.0);
}

/// 进度 0..1 → 已播毫秒（Slider 拖动后从拖到的点继续播）；
/// 越界钳制到 [0, totalMs]。
int replayElapsedFromProgress(double progress, int totalMs) {
  if (totalMs <= 0) return 0;
  return (progress.clamp(0.0, 1.0) * totalMs).round();
}

/// 一跳推进的毫秒数（定时器间隔 × 倍速）。
int replayAdvanceMs(int tickMs, ReplaySpeed speed) =>
    (tickMs * speed.factor).round();

/// 毫秒 → m:ss（≥ 1 小时时 h:mm:ss），只用于回放读数显示。
String replayTimeLabel(int ms) {
  final totalSeconds = (ms / 1000).round();
  final s = totalSeconds % 60;
  final m = (totalSeconds ~/ 60) % 60;
  final h = totalSeconds ~/ 3600;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$m:$ss';
}

/// 3D 回放投影中心：北向上固定视口，中心纬度取轨迹南缘外
/// 约 55 米（0.0005 度），使全部点前向距离 > 0、透视因子 < 1；
/// 中心经度取轨迹东西中点。点不足 2 个或全部重合时返回 null。
({double centerLat, double centerLon})? replayProjectionCenter(
    List<TrackPoint> points) {
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
  return (
    centerLat: minLat - 0.0005,
    centerLon: (minLon + maxLon) / 2,
  );
}

/// 3D 回放横向比例（像素/米）：以 pxPerM=1 投影全部实测点，
/// 取横向跨度，等比适配到画布宽度的 92%；跨度 < 1 米时回落
/// 记录页 zoom 16 默认比例（画布宽 / 170），不除零、不爆缩。
double replayPxPerM({
  required Size size,
  required List<TrackPoint> points,
  required double centerLat,
  required double centerLon,
}) {
  if (size.width <= 0) return 1;
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  for (final p in points) {
    final o = perspectiveProjectLatLon(
      size: size,
      centerLat: centerLat,
      centerLon: centerLon,
      headingDeg: 0,
      headingUp: false,
      lat: p.lat,
      lon: p.lon,
      pxPerM: 1,
      is3d: true,
    );
    if (o.dx < minX) minX = o.dx;
    if (o.dx > maxX) maxX = o.dx;
  }
  final span = maxX - minX;
  if (span < 1) return size.width / 170;
  return size.width * 0.92 / span;
}

/// 3D 回放视图：3D 透视地图 + 播放条（播放/暂停、进度拖动、
/// 倍速）+ 当前速度与时间读数。只动回放显示，不动任何计时与
/// 统计口径；切出页面 / dispose 时停掉定时器，不泄漏。
class Replay3dView extends StatefulWidget {
  final List<TrackPoint> points;
  final double height;

  const Replay3dView({
    super.key,
    required this.points,
    this.height = 260,
  });

  @override
  State<Replay3dView> createState() => _Replay3dViewState();
}

class _Replay3dViewState extends State<Replay3dView> {
  int _elapsedMs = 0;
  bool _playing = false;
  ReplaySpeed _speed = ReplaySpeed.x1;
  Timer? _timer;

  int get _totalMs => replayTotalMs(widget.points);

  int get _index => replayPointIndex(widget.points, _elapsedMs);

  TrackPoint? get _current =>
      _index < 0 ? null : widget.points[_index];

  @override
  void didUpdateWidget(covariant Replay3dView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points && _elapsedMs > _totalMs) {
      _elapsedMs = _totalMs;
    }
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final next = _elapsedMs + replayAdvanceMs(100, _speed);
      if (next >= _totalMs) {
        setState(() {
          _elapsedMs = _totalMs;
          _playing = false;
        });
        _stopTimer();
      } else {
        setState(() => _elapsedMs = next);
      }
    });
  }

  void _togglePlay() {
    if (_totalMs <= 0) return;
    if (_playing) {
      setState(() => _playing = false);
      _stopTimer();
      return;
    }
    setState(() {
      if (_elapsedMs >= _totalMs) _elapsedMs = 0;
      _playing = true;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            '轨迹点不足，无法 3D 回放',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final current = _current;
    final speedKmh =
        current == null ? null : videoGaugeSpeedKmh(current);
    final totalMs = _totalMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _Replay3dPainter(
              points: widget.points,
              currentIndex: _index,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              key: const ValueKey('replay-3d-play-pause'),
              icon: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              tooltip: _playing ? '暂停' : '播放',
              onPressed: _togglePlay,
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('replay-3d-slider'),
                value: _elapsedMs.toDouble().clamp(
                    0.0, totalMs > 0 ? totalMs.toDouble() : 1.0),
                min: 0,
                max: totalMs > 0 ? totalMs.toDouble() : 1.0,
                onChanged: totalMs > 0
                    ? (v) => setState(() => _elapsedMs = v.round())
                    : null,
              ),
            ),
            for (final s in ReplaySpeed.values)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  key: ValueKey('replay-3d-speed-${s.label}'),
                  label: Text(s.label),
                  selected: _speed == s,
                  onSelected: (_) => setState(() => _speed = s),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${replayTimeLabel(_elapsedMs)} / ${replayTimeLabel(totalMs)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            // 速度无效时不显示速度，不编数。
            if (speedKmh != null)
              Text(
                '${speedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Replay3dPainter extends CustomPainter {
  final List<TrackPoint> points;
  final int currentIndex;

  _Replay3dPainter({required this.points, required this.currentIndex});

  bool _sameSideOutside(Offset a, Offset b, Size size) {
    const m = 60.0;
    if (a.dx < -m && b.dx < -m) return true;
    if (a.dx > size.width + m && b.dx > size.width + m) return true;
    if (a.dy < -m && b.dy < -m) return true;
    if (a.dy > size.height + m && b.dy > size.height + m) return true;
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF121212));
    final center = replayProjectionCenter(points);
    if (center == null) return;
    final pxPerM = replayPxPerM(
      size: size,
      points: points,
      centerLat: center.centerLat,
      centerLon: center.centerLon,
    );

    Offset project(TrackPoint p) => perspectiveProjectLatLon(
          size: size,
          centerLat: center.centerLat,
          centerLon: center.centerLon,
          headingDeg: 0,
          headingUp: false,
          lat: p.lat,
          lon: p.lon,
          pxPerM: pxPerM,
          is3d: true,
        );

    // 远处地平线微光（与记录页 3D 地图同式，固定屏幕位置的装饰）。
    final horizonY = size.height * perspectiveHorizonFraction;
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFFE10600).withValues(alpha: 0.18),
          Colors.transparent
        ],
      ).createShader(Rect.fromLTWH(0, horizonY - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, horizonY - 30, size.width, 60), glow);

    // 透视网格地面（与记录页 3D 地图同式，风格化网格线，非路网）。
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (final d in [0.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0]) {
      final y = perspectiveProject(
              size: size, forward: d, right: 0, pxPerM: pxPerM, is3d: true)
          .dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (final r in [-200.0, -100.0, -50.0, 0.0, 50.0, 100.0, 200.0]) {
      final path = Path();
      var first = true;
      for (var d = 0.0; d <= 1000; d += 100) {
        final p = perspectiveProject(
            size: size, forward: d, right: r, pxPerM: pxPerM, is3d: true);
        if (first) {
          path.moveTo(p.dx, p.dy);
          first = false;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // 全程轨迹（实测点连线，未播部分暗色）。
    final projected = points.map(project).toList();
    final dimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dimPath = Path();
    for (var i = 0; i < projected.length; i++) {
      if (i == 0) {
        dimPath.moveTo(projected[i].dx, projected[i].dy);
      } else {
        dimPath.lineTo(projected[i].dx, projected[i].dy);
      }
    }
    canvas.drawPath(dimPath, dimPaint);

    // 已播部分按速度彩虹着色（与分析页同色阶，区间取自本节实测速度）。
    final speedsKmh =
        points.map((p) => p.speed * 3.6).where((v) => v.isFinite).toList();
    final minKmh =
        speedsKmh.isEmpty ? 0.0 : speedsKmh.reduce(math.min);
    final maxKmh =
        speedsKmh.isEmpty ? 0.0 : speedsKmh.reduce(math.max);
    final playedEnd = currentIndex.clamp(0, points.length - 1);
    for (var i = 1; i <= playedEnd; i++) {
      final a = projected[i - 1], b = projected[i];
      if (_sameSideOutside(a, b, size)) continue;
      final midKmh = (points[i - 1].speed + points[i].speed) / 2 * 3.6;
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = speedToRainbowColor(midKmh, minKmh, maxKmh)
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke);
    }

    // 起点绿点 / 终点白点（实测首末点，不编位置）。
    canvas.drawCircle(projected.first, 5,
        Paint()..color = Colors.greenAccent);
    canvas.drawCircle(projected.last, 5, Paint()..color = Colors.white);

    // 当前位置：朝向箭头（相邻实测点算出，算不出时只画圆点、不编方向）
    // + 白点红环（与视频地图仪表同式）。
    if (currentIndex >= 0 && currentIndex < points.length) {
      final pos = projected[currentIndex];
      final heading = videoGaugeHeadingDeg(points, currentIndex);
      if (heading != null) {
        final rad = heading * math.pi / 180;
        final dir = Offset(math.sin(rad), -math.cos(rad));
        final angle = math.atan2(dir.dy, dir.dx);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(angle);
        final arrow = Path()
          ..moveTo(10, 0)
          ..lineTo(-7, -6)
          ..lineTo(-4, 0)
          ..lineTo(-7, 6)
          ..close();
        canvas.drawPath(arrow, Paint()..color = Colors.red);
        canvas.restore();
      }
      canvas.drawCircle(pos, 4, Paint()..color = Colors.white);
      canvas.drawCircle(
          pos,
          4,
          Paint()
            ..color = Colors.red
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _Replay3dPainter old) =>
      old.points != points || old.currentIndex != currentIndex;
}
