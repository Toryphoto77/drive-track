/// v1.3.2：记录页实时 Map 分页（第 1 页，计时页 / 地图页左右滑）。
///
/// 只看不操作：本页不放任何操作按钮（暂停 / 结束 / 标记都在第 0 页）。
/// 固定视口，不跟随平移 / 缩放手势。街道模式框住已录轨迹。
/// 赛道模式有已知中心线时框住赛道本身，不把整段行程并进范围。
///
/// 数据口径（与分析页一致，不编数）：
/// - 底图：高德标准路网栅格瓦片（lib/amap_service.dart 的
///   [amapTileUrl]，免 Key，style=7），落点换算走
///   lib/track_analysis_geo.dart 的 [AnalysisGeoProjector]。
///   高德瓦片是 GCJ-02，全部叠加点（中心线 / 轨迹 / 当前位置 /
///   幽灵车 / 起终点 / 分段点）均为 WGS-84，画之前一律经
///   [wgsToGcjLocal] 转 GCJ-02 再定界 / 投影，否则叠加层与道路
///   错位可达约 500 米。编辑页与分析页仍用 Esri 卫星瓦片，不动。
/// - 赛道中心线只用包经纬度实点（[TrackPackage.centerline]），
///   起终点 / 分段点只用包与计时器已采用的经纬度实点；
///   目录归一化轮廓（[TrackInfo]）不是经纬度，绝不画到地图上。
/// - 已录轨迹只用 GPS 实测点连线；无有效位置时不画当前位置箭头。
/// - 回落：瓦片累计失败达到 [satelliteFallbackFailureThreshold]
///   （3 张）即自动回落示意图（深色底 + 中心线 / 轨迹 / 箭头），
///   不弹错、不白屏，状态行写明“地图未加载，已显示示意图”。
/// - 无点（中心线与轨迹都空）时显示占位文案“暂无位置，等待定位”，
///   不画假线。单点 / 全部重合时以该点为中心扩一小框（约 ±220 m），
///   保证 bounds 计算不除零、箭头仍有可画的视口。
/// 不做离线瓦片下载，不做 3D 地图回放。
///
/// v1.3.4：幽灵车叠加——调用方按参考圈（本节最佳圈）插值出位置
/// （ghostPositionForLap / ghostPositionAt 纯函数），本页只画一个
/// 空心青色箭头 + 左上角图例；门控缺一不可（见 main.dart 调用处）。
///
/// 已知赛道（中心线至少 2 点）打开即锁在该赛道上，不等第一次过
/// 起终点线。[showTrackOverlayFor] 在 hasKnownCircuit 时即为真，
/// 视口由 [circuitMapFrame] 只框中心线，并入落在赛道附近的车与
/// 幽灵车。画出的轨迹只保留赛道附近的点，进城路不会把画面拉成
/// 城市图。没有中心线时仍等第一次过线才画起终点 / 分段点。状态行
/// 过线前仍是“等待通过起终点线”（[trackMapStatusLine]）。幽灵车
/// 另有门控（有参考圈才画），与叠加层不是同一个状态。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'amap_service.dart';
import 'models.dart';
import 'satellite_tiles.dart';
import 'track_analysis_geo.dart';
import 'track_timing.dart';

/// v1.3.4：幽灵车插值纯函数（参考圈 = 本节最佳圈）。
///
/// 口径：[lapPoints] 为已按参考圈起止切出的轨迹点，[elapsedMs] 为
/// 相对圈起点的用时（调用方传 LapTimer.currentLapMs，已扣暂停；
/// 参考圈切片 elapsed 是原始时间，但计入圈不会有超 30 秒停留，
/// 停留圈不计入最佳圈，漂移可忽略）。
/// - elapsed < 0 或点数 < 2 时返回 null（无幽灵车）；
/// - 超出参考圈时长时钳制到最后一个点（幽灵车在终点线等），
///   朝向取末段行进方向；
/// - 两点之间按时间线性插值经纬度，朝向取该段行进方向（0° = 北）。
double ghostBearingDeg(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final meanLat = (lat1 + lat2) / 2 * math.pi / 180;
  final dx = (lon2 - lon1) * math.cos(meanLat);
  final dy = lat2 - lat1;
  if (dx == 0 && dy == 0) return 0;
  var deg = math.atan2(dx, dy) * 180 / math.pi;
  if (deg < 0) deg += 360;
  return deg;
}

({double lat, double lon, double headingDeg})? ghostPositionAt(
  List<TrackPoint> lapPoints,
  int elapsedMs,
) {
  if (elapsedMs < 0 || lapPoints.length < 2) return null;
  final t0 = lapPoints.first.timeMs;
  final target = t0 + elapsedMs;
  if (target >= lapPoints.last.timeMs) {
    var i = lapPoints.length - 2;
    while (i > 0 &&
        lapPoints[i].lat == lapPoints[i + 1].lat &&
        lapPoints[i].lon == lapPoints[i + 1].lon) {
      i--;
    }
    return (
      lat: lapPoints.last.lat,
      lon: lapPoints.last.lon,
      headingDeg: ghostBearingDeg(
        lapPoints[i].lat,
        lapPoints[i].lon,
        lapPoints.last.lat,
        lapPoints.last.lon,
      ),
    );
  }
  for (var i = 0; i < lapPoints.length - 1; i++) {
    final a = lapPoints[i];
    final b = lapPoints[i + 1];
    if (target >= a.timeMs && target <= b.timeMs) {
      final span = b.timeMs - a.timeMs;
      final f = span <= 0 ? 0.0 : (target - a.timeMs) / span;
      return (
        lat: a.lat + (b.lat - a.lat) * f,
        lon: a.lon + (b.lon - a.lon) * f,
        headingDeg: ghostBearingDeg(a.lat, a.lon, b.lat, b.lon),
      );
    }
  }
  return null;
}

/// 从全部轨迹点里按 [lap] 起止切出参考圈，再按 [elapsedMs] 插值。
/// 圈内无点（点数 < 2）时返回 null，不画假幽灵车。
({double lat, double lon, double headingDeg})? ghostPositionForLap(
  List<TrackPoint> points,
  Lap lap,
  int elapsedMs,
) {
  if (elapsedMs < 0) return null;
  final slice = points
      .where((p) => p.timeMs >= lap.startMs && p.timeMs <= lap.endMs)
      .toList();
  return ghostPositionAt(slice, elapsedMs);
}

/// 中心线与已录轨迹的并集视口；两边都空时返回 null（调用方显示占位）。
/// 单点或全部重合时以该点为中心扩一小框（约 ±220 m），不除零。
/// 赛道模式不要直接拿整段行程调用本函数，用 [circuitMapFrame]。
GeoBounds? recordingMapBounds(
  List<GeoPoint> centerline,
  List<GeoPoint> trail,
) {
  final pts = <({double lat, double lon})>[
    ...centerline.map((p) => (lat: p.lat, lon: p.lon)),
    ...trail.map((p) => (lat: p.lat, lon: p.lon)),
  ];
  if (pts.isEmpty) return null;
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

/// 赛道外沿、维修区和定位抖动都在这个量级以内。再远的点属于
/// 进城路：不参与定框，也不画进赛道图。
const double circuitCameraMarginM = 400;

/// 点是否落在 [bounds] 外扩 [marginM] 米之内（含框内）。
bool pointWithinBoundsMargin(
  GeoBounds bounds,
  double lat,
  double lon, {
  double marginM = circuitCameraMarginM,
}) {
  final midLat = (bounds.minLat + bounds.maxLat) / 2 * math.pi / 180;
  final cosLat = math.cos(midLat).abs().clamp(0.01, 1.0);
  final dLat = marginM / 110540.0;
  final dLon = marginM / (111320.0 * cosLat);
  return lat >= bounds.minLat - dLat &&
      lat <= bounds.maxLat + dLat &&
      lon >= bounds.minLon - dLon &&
      lon <= bounds.maxLon + dLon;
}

/// 已知赛道的地图框。视口锁在中心线（并入起终点 / 分段点，以及
/// 落在赛道附近的车与幽灵车），不把远离赛道的轨迹并进范围。
/// 返回的轨迹只保留赛道附近的点，进城的那一段不会横穿赛道图。
/// 中心线不足 2 点、或范围退化且无法扩框时返回 null。
({GeoBounds bounds, List<GeoPoint> trail})? circuitMapFrame({
  required List<GeoPoint> centerline,
  GeoPoint? start,
  GeoPoint? finish,
  List<GeoPoint> sectorPoints = const [],
  List<GeoPoint> trail = const [],
  double? vehicleLat,
  double? vehicleLon,
  double? ghostLat,
  double? ghostLon,
  double marginM = circuitCameraMarginM,
}) {
  if (centerline.length < 2) return null;
  final base = <GeoPoint>[
    ...centerline,
    if (start != null) start,
    if (finish != null) finish,
    ...sectorPoints,
  ];
  final circuit = recordingMapBounds(base, const []);
  if (circuit == null) return null;
  final extra = <GeoPoint>[];
  if (vehicleLat != null &&
      vehicleLon != null &&
      vehicleLat != 0 &&
      vehicleLon != 0 &&
      pointWithinBoundsMargin(
        circuit,
        vehicleLat,
        vehicleLon,
        marginM: marginM,
      )) {
    extra.add(GeoPoint(vehicleLat, vehicleLon));
  }
  if (ghostLat != null &&
      ghostLon != null &&
      pointWithinBoundsMargin(
        circuit,
        ghostLat,
        ghostLon,
        marginM: marginM,
      )) {
    extra.add(GeoPoint(ghostLat, ghostLon));
  }
  final bounds =
      extra.isEmpty ? circuit : (recordingMapBounds(base, extra) ?? circuit);
  final localTrail = <GeoPoint>[
    for (final p in trail)
      if (pointWithinBoundsMargin(circuit, p.lat, p.lon, marginM: marginM)) p,
  ];
  return (bounds: bounds, trail: localTrail);
}

/// 赛道叠加层是否显示（纯函数）。
/// - 街道模式恒真：街道本就没有起终点线要过，门控只针对赛道模式，
///   街道已录轨迹不受影响；
/// - 赛道模式只要已有已知中心线（[hasKnownCircuit]）就为真，打开
///   即框住赛道，不等第一次过线；
/// - 没有中心线时仍等第一次通过起终点线。过线后保持真
///   （调用方传入的 hasCrossedStartLine 一旦为真不再变假），
///   叠加层不因后续圈数变化而消失。
bool showTrackOverlayFor({
  required bool isTrack,
  required bool hasCrossedStartLine,
  bool hasKnownCircuit = false,
}) =>
    !isTrack || hasKnownCircuit || hasCrossedStartLine;

/// v1.3.5：赛道模式 Map 页状态行（纯函数）：无计时器 → '等待定位'；
/// 未第一次过线 → '等待通过起终点线'；已过线 → '[圈标签] · 当前圈 [用时]'。
/// '等待通过起终点线'只在过线前出现，过线后不再出现。
String trackMapStatusLine({
  required bool hasTimer,
  required bool hasCrossedStartLine,
  required String lapLabel,
  required String currentLapDuration,
}) {
  if (!hasTimer) return '等待定位';
  if (!hasCrossedStartLine) return '等待通过起终点线';
  return '$lapLabel · 当前圈 $currentLapDuration';
}

/// 当前位置箭头三角形的三个顶点（朝向：0° = 北 / 屏幕上，顺时针为正）。
/// 尖角朝前 12px，底边在后 8px、半宽 7px。
({Offset tip, Offset baseLeft, Offset baseRight}) recordingMapArrowVertices(
  Offset center,
  double headingDeg,
) {
  final rad = headingDeg * math.pi / 180;
  final f = Offset(math.sin(rad), -math.cos(rad));
  final r = Offset(math.cos(rad), math.sin(rad));
  return (
    tip: center + f * 12,
    baseLeft: center - f * 8 - r * 7,
    baseRight: center - f * 8 + r * 7,
  );
}

/// 记录页实时地图页（第 1 页）：高德底图 + 中心线 / 起终点 / 分段点 /
/// 已录轨迹 / 当前位置箭头 + 底部状态行。只看不操作。
class RecordingMapPage extends StatefulWidget {
  /// 是否赛道模式（只决定调用方传什么数据，本页不另取状态）。
  final bool isTrack;

  /// 赛道中心线（经纬度实点；街道模式传空）。
  final List<GeoPoint> centerline;

  /// 包起终点（经纬度；街道模式为 null）。
  final GeoPoint? start;
  final GeoPoint? finish;

  /// 计时器已采用的分段点（经纬度实点，最多 2 点）。
  final List<GeoPoint> sectorPoints;

  /// 已录轨迹（经纬度实点）。
  final List<GeoPoint> trail;

  /// 当前位置（0 表示无效）与朝向（度，0 = 北）。
  final double curLat;
  final double curLon;
  final double curHeading;

  /// v1.3.4：幽灵车位置与朝向（调用方按参考圈插值算好；全为 null =
  /// 无幽灵车）。只在赛道模式 + 有最佳圈 + 已过发车圈 + 不在维修区
  /// 内 + 当前圈已开始计时时传值，街道模式不传。
  final double? ghostLat;
  final double? ghostLon;
  final double? ghostHeading;

  /// 赛道叠加层是否显示（调用方用 [showTrackOverlayFor] 算好传入；
  /// 默认 true = 不门控，兼容旧调用）。已知中心线时调用方在过线前
  /// 就传 true，本页随即把视口锁在赛道上。为假时不画中心线 / 起终点 /
  /// 分段点，视口只跟已录轨迹，只显示高德底图 + 当前位置箭头 + 轨迹。
  /// 幽灵车不受此门控影响（另有自己的门控）。街道模式调用方传 true。
  final bool showTrackOverlay;

  /// 调用方算好的紧凑状态行文本。
  final String statusLine;

  const RecordingMapPage({
    super.key,
    required this.isTrack,
    required this.centerline,
    required this.start,
    required this.finish,
    required this.sectorPoints,
    required this.trail,
    required this.curLat,
    required this.curLon,
    required this.curHeading,
    this.ghostLat,
    this.ghostLon,
    this.ghostHeading,
    this.showTrackOverlay = true,
    required this.statusLine,
  });

  @override
  State<RecordingMapPage> createState() => _RecordingMapPageState();
}

class _RecordingMapPageState extends State<RecordingMapPage> {
  /// 已失败过的瓦片 URL（去重计数；单张失败只计一次）。
  final Set<String> _failedTileUrls = {};

  bool get _fallback => shouldFallbackToSchematic(_failedTileUrls.length);

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
    // 调用方未打开叠加层时不画中心线 / 起终点 / 分段点。已知赛道
    // 打开叠加层后，视口锁在赛道上，远处轨迹不参与定框。
    final overlayCenterline =
        widget.showTrackOverlay ? widget.centerline : const <GeoPoint>[];
    final overlayStart = widget.showTrackOverlay ? widget.start : null;
    final overlayFinish = widget.showTrackOverlay ? widget.finish : null;
    final overlaySectors =
        widget.showTrackOverlay ? widget.sectorPoints : const <GeoPoint>[];
    // 高德瓦片是 GCJ-02，入参全部是 WGS-84：先统一转 GCJ-02 再定界 /
    // 投影，否则叠加层与道路错位。框外点（包括无效的 0,0）原样返回。
    GeoPoint toGcj(GeoPoint p) {
      final (la, lo) = wgsToGcjLocal(p.lat, p.lon);
      return GeoPoint(la, lo);
    }

    final gcjCenterline = overlayCenterline.map(toGcj).toList();
    final gcjTrail = widget.trail.map(toGcj).toList();
    final gcjStart = overlayStart == null ? null : toGcj(overlayStart);
    final gcjFinish = overlayFinish == null ? null : toGcj(overlayFinish);
    final gcjSectors = overlaySectors.map(toGcj).toList();
    final (gcjCurLat, gcjCurLon) =
        wgsToGcjLocal(widget.curLat, widget.curLon);
    double? gcjGhostLat;
    double? gcjGhostLon;
    if (widget.ghostLat != null && widget.ghostLon != null) {
      final (la, lo) = wgsToGcjLocal(widget.ghostLat!, widget.ghostLon!);
      gcjGhostLat = la;
      gcjGhostLon = lo;
    }
    final frame = widget.isTrack && gcjCenterline.length >= 2
        ? circuitMapFrame(
            centerline: gcjCenterline,
            start: gcjStart,
            finish: gcjFinish,
            sectorPoints: gcjSectors,
            trail: gcjTrail,
            vehicleLat: widget.curLat != 0 && widget.curLon != 0
                ? gcjCurLat
                : null,
            vehicleLon: widget.curLat != 0 && widget.curLon != 0
                ? gcjCurLon
                : null,
            ghostLat: gcjGhostLat,
            ghostLon: gcjGhostLon,
          )
        : null;
    final bounds = frame?.bounds ?? recordingMapBounds(gcjCenterline, gcjTrail);
    final paintedTrail = frame?.trail ?? gcjTrail;
    if (bounds == null) {
      return Container(
        color: const Color(0xFF0A0A0A),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '暂无位置，等待定位',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              widget.statusLine,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;
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
        final satelliteOn = !_fallback;
        return Column(
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFF0A0A0A),
                child: Stack(
                  children: [
                    if (satelliteOn)
                      for (var y = projector.tileRange.y0;
                          y <= projector.tileRange.y1;
                          y++)
                        for (var x = projector.tileRange.x0;
                            x <= projector.tileRange.x1;
                            x++)
                          Positioned.fromRect(
                            rect: projector.tileScreenRect(x, y),
                            child: Image.network(
                              amapTileUrl(zoom, x, y),
                              key: ValueKey('recmap-amap-$zoom-$x-$y'),
                              headers: const {
                                'User-Agent': 'DriveTrack/1.5.6',
                              },
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) {
                                _onTileError(amapTileUrl(zoom, x, y));
                                return Container(
                                    color: const Color(0xFF0A0A0A));
                              },
                            ),
                          ),
                    CustomPaint(
                      key: const ValueKey('recording-map-overlay'),
                      size: Size(width, height),
                      painter: RecordingMapPainter(
                        projector: projector,
                        centerline: gcjCenterline,
                        start: gcjStart,
                        finish: gcjFinish,
                        sectorPoints: gcjSectors,
                        trail: paintedTrail,
                        curLat: gcjCurLat,
                        curLon: gcjCurLon,
                        curHeading: widget.curHeading,
                        ghostLat: gcjGhostLat,
                        ghostLon: gcjGhostLon,
                        ghostHeading: widget.ghostHeading,
                        satelliteOn: satelliteOn,
                      ),
                    ),
                    // v1.3.4：幽灵车图例（有幽灵车时才出现）。
                    if (widget.ghostLat != null &&
                        widget.ghostLon != null &&
                        widget.ghostHeading != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          key: const ValueKey('ghost-legend'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '◇ 幽灵车 · 参考圈',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ),
                    if (satelliteOn)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            amapTileAttribution,
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF111111),
              child: Text(
                _fallback
                    ? '${widget.statusLine} · 地图未加载，已显示示意图'
                    : widget.statusLine,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 实时地图叠加层：中心线 / 起终点 / 分段点 / 已录轨迹 / 当前位置箭头。
/// 公开类：测试直接取 CustomPaint 的 painter 核对标记字段。
class RecordingMapPainter extends CustomPainter {
  final AnalysisGeoProjector projector;
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;
  final List<GeoPoint> sectorPoints;
  final List<GeoPoint> trail;
  final double curLat;
  final double curLon;
  final double curHeading;

  /// v1.3.4：幽灵车位置与朝向（全为 null = 无幽灵车）。
  final double? ghostLat;
  final double? ghostLon;
  final double? ghostHeading;

  /// 卫星底图是否在显示（决定白晕 / 标签暗底是否启用）。
  final bool satelliteOn;

  RecordingMapPainter({
    required this.projector,
    required this.centerline,
    required this.start,
    required this.finish,
    required this.sectorPoints,
    required this.trail,
    required this.curLat,
    required this.curLon,
    required this.curHeading,
    this.ghostLat,
    this.ghostLon,
    this.ghostHeading,
    required this.satelliteOn,
  });

  /// 起终点是否重合（< 1e-6 度，约 0.1 m）：重合时只画一个（方格旗）。
  bool get startFinishCoincident =>
      start != null &&
      finish != null &&
      (start!.lat - finish!.lat).abs() < 1e-6 &&
      (start!.lon - finish!.lon).abs() < 1e-6;

  bool get hasValidPosition => curLat != 0 && curLon != 0;

  /// v1.3.4：是否有幽灵车可画（三值齐全才画，缺一不可）。
  bool get hasGhost =>
      ghostLat != null && ghostLon != null && ghostHeading != null;

  @override
  void paint(Canvas canvas, Size size) {
    Offset pt(GeoPoint p) => projector.project(p.lat, p.lon);

    // 赛道中心线：卫星图上白晕打底（编辑页做法：7px 白底 + 3px 红线），
    // 示意图上只画红线。
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

    // 已录轨迹：实测点连线，白色 2px。
    if (trail.length >= 2) {
      final path = Path()..moveTo(pt(trail.first).dx, pt(trail.first).dy);
      for (var i = 1; i < trail.length; i++) {
        final o = pt(trail[i]);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
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

    // 分段点：蓝点 + S1/S2 标签（编辑页做法）。
    for (var i = 0; i < sectorPoints.length; i++) {
      _drawDot(canvas, pt(sectorPoints[i]), Colors.blue, 'S${i + 1}');
    }

    // 当前位置箭头：带朝向的红色三角形（白边）；无有效位置时不画。
    if (hasValidPosition) {
      final center = pt(GeoPoint(curLat, curLon));
      final v = recordingMapArrowVertices(center, curHeading);
      final path = Path()
        ..moveTo(v.tip.dx, v.tip.dy)
        ..lineTo(v.baseRight.dx, v.baseRight.dy)
        ..lineTo(v.baseLeft.dx, v.baseLeft.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = const Color(0xFFE10600),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // v1.3.4：幽灵车空心箭头——只描边不填充，青色描边 + 白边，
    // 与当前位置实心红三角明确区分。
    if (hasGhost) {
      final center = pt(GeoPoint(ghostLat!, ghostLon!));
      final v = recordingMapArrowVertices(center, ghostHeading!);
      final path = Path()
        ..moveTo(v.tip.dx, v.tip.dy)
        ..lineTo(v.baseRight.dx, v.baseRight.dy)
        ..lineTo(v.baseLeft.dx, v.baseLeft.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 4.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF22D3EE)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
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

  /// 终点方格旗：4 列 × 3 行黑白格（与 CheckeredFlag 同画法），
  /// 以落点为中心，白边 1px。
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
  bool shouldRepaint(covariant RecordingMapPainter old) => true;
}
