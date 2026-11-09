/// v1.3.3：选赛道卫星预览共用组件（ⓘ 详情页 + 选择器缩略图共用）。
///
/// 只读预览：固定视口框住包中心线，不跟随平移 / 缩放手势，不改选赛道
/// 逻辑、不改 500m 门控、不改包数据。
///
/// 数据口径（与记录页 Map 页一致，不编数）：
/// - 底图：Esri World Imagery 卫星瓦片（lib/satellite_tiles.dart），
///   落点换算走 lib/track_analysis_geo.dart 的 [AnalysisGeoProjector]；
///   不另写瓦片 URL 或投影。
/// - 中心线只用包经纬度实点（[TrackPackage.centerline]）；起终点只用
///   包的经纬度实点；目录归一化轮廓不是经纬度，绝不画到卫星图上。
/// - 无中心线 / 中心线不足 2 点时显示调用方传入的 [fallback]（现有示意
///   图或“轮廓待补”占位），不画假线。
/// - 回落：瓦片累计失败达到阈值（默认 [satelliteFallbackFailureThreshold]，
///   3 张）即自动回落 [fallback]，不弹错、不白屏；详情页状态行写明
///   “卫星图未加载，已显示示意图”（[showStatusLine]）。
/// - 卫星显示时右下角署名 [satelliteTileAttribution]。
/// 不做离线瓦片下载，不做 3D 地图回放。

import 'package:flutter/material.dart';

import 'satellite_tiles.dart';
import 'track_analysis_geo.dart';
import 'track_timing.dart';

/// 预览视口：中心线 + 起终点并集；中心线不足 2 点时返回 null
///（调用方显示占位，不画假线）。单点 / 全部重合时以首点为中心扩一小框
///（约 ±220 m，±0.002°），与 recordingMapBounds 同口径。
GeoBounds? previewGeoBounds(
  List<GeoPoint> centerline, {
  GeoPoint? start,
  GeoPoint? finish,
}) {
  if (centerline.length < 2) return null;
  final pts = <({double lat, double lon})>[
    ...centerline.map((p) => (lat: p.lat, lon: p.lon)),
    if (start != null) (lat: start.lat, lon: start.lon),
    if (finish != null) (lat: finish.lat, lon: finish.lon),
  ];
  final bounds = analysisGeoBounds(pts);
  if (bounds != null) return bounds;
  final p = pts.first;
  return (
    minLat: p.lat - 0.002,
    maxLat: p.lat + 0.002,
    minLon: p.lon - 0.002,
    maxLon: p.lon + 0.002,
  );
}

/// 选赛道卫星预览：Esri 卫星底图 + 包中心线叠加 + 起终点标记。
///
/// [fallback] 为瓦片失败或无中心线时回落显示的现有示意图（调用方传入，
/// 不得为空）；[showStatusLine] 为 true 时在图下方显示状态行（详情页用，
/// 选择器 64px 缩略图放不下，用 false）。
class TrackSatellitePreview extends StatefulWidget {
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;

  /// 预览高度（px）；宽度由父级约束（详情页全宽，选择器 96px）。
  final double height;

  /// 回落时显示的现有示意图 / 占位（须自行适配 [height] 高度，如
  /// OutlineDiagram(height: height) 且不带 caption，否则溢出）。
  final Widget fallback;

  /// 是否在图下方显示状态行。
  final bool showStatusLine;

  /// 回落阈值（测试缝，默认 [satelliteFallbackFailureThreshold]）。
  final int fallbackThreshold;

  const TrackSatellitePreview({
    super.key,
    required this.centerline,
    this.start,
    this.finish,
    required this.height,
    required this.fallback,
    this.showStatusLine = false,
    this.fallbackThreshold = satelliteFallbackFailureThreshold,
  });

  @override
  State<TrackSatellitePreview> createState() => _TrackSatellitePreviewState();
}

class _TrackSatellitePreviewState extends State<TrackSatellitePreview> {
  /// 已失败过的瓦片 URL（去重计数；单张失败只计一次）。
  final Set<String> _failedTileUrls = {};

  bool get _fallback => _failedTileUrls.length >= widget.fallbackThreshold;

  void _onTileError(String url) {
    if (_failedTileUrls.contains(url)) return;
    _failedTileUrls.add(url);
    // 图片加载失败发生在帧外，此处经 post-frame 再刷新，避免
    // 在 build 期间 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bounds = previewGeoBounds(
      widget.centerline,
      start: widget.start,
      finish: widget.finish,
    );
    // 无中心线 / 中心线不足 2 点：直接显示调用方传入的现有示意图或占位，
    // 不画假线、不请求瓦片。
    if (bounds == null) {
      return SizedBox(height: widget.height, child: widget.fallback);
    }
    // 瓦片失败达到阈值：回落调用方传入的现有示意图（须自行适配 height
    // 高度，如 OutlineDiagram(height: height) 且不带 caption，否则溢出）；
    // 详情页在图底以半透明条覆盖状态行，不另占高度。
    if (_fallback) {
      return SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            widget.fallback,
            if (widget.showStatusLine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: Colors.black.withValues(alpha: 0.65),
                  child: const Text(
                    '卫星图未加载，已显示示意图',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      child: _SatelliteMapBody(
        bounds: bounds,
        centerline: widget.centerline,
        start: widget.start,
        finish: widget.finish,
        onTileError: _onTileError,
      ),
    );
  }
}

/// 卫星图本体（纯布局 + 瓦片拼贴 + 叠加层）：无中心线或已回落时调用方
/// 不建本组件。
class _SatelliteMapBody extends StatelessWidget {
  final GeoBounds bounds;
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;
  final void Function(String url) onTileError;

  const _SatelliteMapBody({
    required this.bounds,
    required this.centerline,
    required this.start,
    required this.finish,
    required this.onTileError,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
        final zoom = analysisGeoZoom(
          bounds: bounds,
          widthPx: width,
          heightPx: height,
        );
        final projector = AnalysisGeoProjector(
          bounds: bounds,
          zoom: zoom,
          size: Size(width, height),
        );
        return Container(
          color: const Color(0xFF0A0A0A),
          child: Stack(
            children: [
              for (var y = projector.tileRange.y0;
                  y <= projector.tileRange.y1;
                  y++)
                for (var x = projector.tileRange.x0;
                    x <= projector.tileRange.x1;
                    x++)
                  Positioned.fromRect(
                    rect: projector.tileScreenRect(x, y),
                    child: Image.network(
                      satelliteTileUrl(zoom, x, y),
                      key: ValueKey('track-preview-sat-$zoom-$x-$y'),
                      headers: const {
                        'User-Agent': 'DriveTrack/1.5.5',
                      },
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) {
                        onTileError(satelliteTileUrl(zoom, x, y));
                        return Container(color: const Color(0xFF0A0A0A));
                      },
                    ),
                  ),
              CustomPaint(
                key: const ValueKey('track-preview-overlay'),
                size: Size(width, height),
                painter: TrackSatellitePreviewPainter(
                  projector: projector,
                  centerline: centerline,
                  start: start,
                  finish: finish,
                  satelliteOn: true,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    satelliteTileAttribution,
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 卫星预览叠加层：中心线 / 起点 / 终点（与记录页 Map 页同画法：
/// 中心线卫星图上白晕打底 7px + 红线 3px，示意图上只画红线）。
/// 公开类：测试直接取 CustomPaint 的 painter 核对标记字段。
class TrackSatellitePreviewPainter extends CustomPainter {
  final AnalysisGeoProjector projector;
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;

  /// 卫星底图是否在显示（决定白晕 / 标签暗底是否启用）。
  final bool satelliteOn;

  TrackSatellitePreviewPainter({
    required this.projector,
    required this.centerline,
    required this.start,
    required this.finish,
    required this.satelliteOn,
  });

  /// 起终点是否重合（< 1e-6 度，约 0.1 m）：重合时只画一个（方格旗）。
  bool get startFinishCoincident =>
      start != null &&
      finish != null &&
      (start!.lat - finish!.lat).abs() < 1e-6 &&
      (start!.lon - finish!.lon).abs() < 1e-6;

  @override
  void paint(Canvas canvas, Size size) {
    Offset pt(GeoPoint p) => projector.project(p.lat, p.lon);

    // 赛道中心线。
    if (centerline.length >= 2) {
      final path = Path()
        ..moveTo(pt(centerline.first).dx, pt(centerline.first).dy);
      for (var i = 1; i < centerline.length; i++) {
        final o = pt(centerline[i]);
        path.lineTo(o.dx, o.dy);
      }
      if (satelliteOn) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 7
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFE10600)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }

    // 起点绿点 / 终点方格旗：重合时只画方格旗。
    if (start != null && !startFinishCoincident) {
      _drawDot(canvas, pt(start!), Colors.green, '起');
    }
    if (finish != null) {
      _drawCheckeredFlag(canvas, pt(finish!));
    }
  }

  /// 圆点标记：r9 实心 + 白边 + 标签（卫星图上标签加暗底保可读）。
  void _drawDot(Canvas canvas, Offset o, Color color, String label) {
    canvas.drawCircle(o, 9, Paint()..color = color);
    canvas.drawCircle(
      o,
      9,
      Paint()
        ..color = satelliteOn ? Colors.white : Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = satelliteOn ? 3 : 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelTopLeft = o - Offset(tp.width / 2, tp.height / 2);
    if (satelliteOn) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            labelTopLeft.dx - 3,
            labelTopLeft.dy - 1,
            tp.width + 6,
            tp.height + 2,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
    }
    tp.paint(canvas, labelTopLeft);
  }

  /// 终点方格旗：4 列 × 3 行黑白格，以落点为中心，白边 1px。
  void _drawCheckeredFlag(Canvas canvas, Offset o) {
    const w = 22.0;
    const h = 15.0;
    const cols = 4;
    const rows = 3;
    final left = o.dx - w / 2;
    final top = o.dy - h / 2;
    final cw = w / cols;
    final ch = h / rows;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(left + c * cw, top + r * ch, cw, ch),
          Paint()
            ..color = (r + c) % 2 == 0 ? Colors.black : Colors.white,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(left, top, w, h),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant TrackSatellitePreviewPainter old) => true;
}
