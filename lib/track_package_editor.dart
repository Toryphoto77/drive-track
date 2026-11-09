/// 赛道包地图编辑器（v1.2.12 重做：准星落点 + 缩放平移 + 拖动微调 +
/// 吸附 + 撤销 + 点列表）。
///
/// 交互：
/// - 十字准星：手指按住拖动时准星显示在手指上方 72px 处（不被手指盖
///   住），松手才在准星位置落点；轻点同样在准星处落点。
/// - 捏合缩放（1×–12×）+ 双指平移 + “回到全景”；缩放/平移时已落点
///   与中心线跟随同一变换，不漂移；画布在可滚动区之外，单指拖动
///   不会与页面滚动抢手势。
/// - 已落点（起点 / 终点 / 龙门架 / 维修区入口 / 维修区出口 / 分段点）可按住拖动微调；点列表
///   选中某点后可用方向键微调（步长 1 米 / 5 米可切）；轮廓点仍用
///   “删除末点 / 清空”维护，不参与拖动。
/// - 吸附（默认开，可开关）：起点 / 终点 / 龙门架 / 维修区入口 / 维修区出口 / 分段点落点与拖
///   动结束时自动吸到最近的中心线点；选中的分段点另有沿中心线的
///   距离滑块微调。方向键微调不二次吸附（显式微调优先），手动输
///   经纬度同样不吸附（输入值即为准）。
/// - 撤销：多步（上限 50 步），落点 / 拖动 / 微调 / 滑块 / 删除 /
///   清空前均压栈快照。
/// - 卫星底图（默认关）：开关在工具区，开启后中心线与点位叠在 Esri
///   World Imagery 影像上（免 Key 瓦片，Image.network 拼贴，无新
///   依赖）；瓦片摆位复用同一 EditorViewTransform，影像只做底图；
///   无网络或瓦片失败达阈值时静默回落示意图，状态行提示一句。
/// - 保存逻辑与实测替换规则不变（见 [_save]）；弯角表本版编辑器
///   暂不改动；提示一律走顶部弹窗，不用 SnackBar。
///
/// 纯函数 / 纯逻辑（[editorCrosshairPosition]、[nudgeGeoPoint]、
/// [snapPointToCenterline]、[centerlineDistanceAt]、
/// [pointAtCenterlineDistance]、[EditorViewTransform]、
/// [EditorUndoStack]）均可单测，见 test/track_package_editor_test.dart。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'satellite_tiles.dart';
import 'track_library.dart';
import 'track_timing.dart';

/// 准星相对手指的上移距离（px）：手指按住时准星不被盖住。
const double editorCrosshairLiftPx = 72.0;

/// 画布上可点的命中半径（px，屏幕坐标）。
const double editorHitRadiusPx = 30.0;

/// 缩放范围。
const double editorMinZoom = 1.0;
const double editorMaxZoom = 12.0;

// ---------- 卫星底图（Esri World Imagery，免 Key 公开影像瓦片） ----------
//
// 编辑页默认仍是示意图（离线可用）；开关打开后才在中心线下方叠一层
// 卫星影像，供拖起点 / 终点 / 龙门架 / 维修区入口 / 维修区出口 /
// 分段点时对照真实起跑线与龙门架。影像只做底图：缩放 / 平移 / 准星 / 吸附 / 拖动 / 点列表
// 逻辑一律不动，瓦片摆位复用同一 [EditorViewTransform]（瓦片角点
// 经纬度 → transform.project → 屏幕矩形），不另写一套换算。
// 瓦片源：Esri World Imagery（https://server.arcgisonline.com，
// 免 Key；2026-11-05 沙箱 curl 核对瓦片返回 200 / image/jpeg）。
// 无网络或瓦片加载失败时静默回落示意图（见
// [satelliteFallbackFailureThreshold]），不弹错、不白屏。
// 来源署名在开关行与状态行写明。
//
// 常量与纯函数（[satelliteTileAttribution]、[satelliteMinZoom]、
// [satelliteMaxZoom]、[satelliteMaxTiles]、
// [satelliteFallbackFailureThreshold]、[satelliteTileUrl]、
// [satelliteTileX]、[satelliteTileY]、[satelliteTileWestLon]、
// [satelliteTileNorthLat]、[satelliteZoomForMetersPerPixel]、
// [satelliteTileRange]）已抽到 lib/satellite_tiles.dart，与分析页
// 共用；本文件只留依赖 [EditorViewTransform] 的
// [satelliteTilesForBounds] 与 [satelliteTileScreenRect]。

/// 可见经纬度范围内的卫星瓦片（z/x/y 列表）；瓦片数超限时自动
/// 降一级缩放重算，直至 [satelliteMinZoom]。
List<({int z, int x, int y})> satelliteTilesForBounds({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  required double metersPerPixel,
  required double latitude,
}) {
  var z = satelliteZoomForMetersPerPixel(metersPerPixel, latitude);
  while (z > satelliteMinZoom) {
    final r = satelliteTileRange(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      zoom: z,
    );
    final count = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
    if (count <= satelliteMaxTiles) {
      return [
        for (var x = r.x0; x <= r.x1; x++)
          for (var y = r.y0; y <= r.y1; y++) (z: z, x: x, y: y),
      ];
    }
    z--;
  }
  final r = satelliteTileRange(
    minLat: minLat,
    maxLat: maxLat,
    minLon: minLon,
    maxLon: maxLon,
    zoom: z,
  );
  return [
    for (var x = r.x0; x <= r.x1; x++)
      for (var y = r.y0; y <= r.y1; y++) (z: z, x: x, y: y),
  ];
}

/// 瓦片在画布上的屏幕矩形：瓦片西北 / 东南角点经纬度经同一
/// [EditorViewTransform] 投影得到（与中心线、落点共用换算）。
Rect satelliteTileScreenRect(EditorViewTransform transform, int z, int x, int y) {
  final nw = transform.project(
    GeoPoint(satelliteTileNorthLat(y, z), satelliteTileWestLon(x, z)),
  );
  final se = transform.project(
    GeoPoint(satelliteTileNorthLat(y + 1, z), satelliteTileWestLon(x + 1, z)),
  );
  return Rect.fromPoints(nw, se);
}

enum _EditTool { start, finish, gantry, pitIn, pitOut, sector, outline }

extension _EditToolLabel on _EditTool {
  String get label => switch (this) {
    _EditTool.start => '起点',
    _EditTool.finish => '终点',
    _EditTool.gantry => '龙门架',
    _EditTool.pitIn => '维修区入口',
    _EditTool.pitOut => '维修区出口',
    _EditTool.sector => '分段点',
    _EditTool.outline => '轮廓点',
  };

  IconData get icon => switch (this) {
    _EditTool.start => Icons.flag,
    _EditTool.finish => Icons.sports_score,
    _EditTool.gantry => Icons.door_front_door,
    _EditTool.pitIn => Icons.login,
    _EditTool.pitOut => Icons.logout,
    _EditTool.sector => Icons.timeline,
    _EditTool.outline => Icons.polyline,
  };
}

/// 准星位置：手指位置向上偏移 [liftPx]，不被手指盖住。
Offset editorCrosshairPosition(Offset finger, [double liftPx = editorCrosshairLiftPx]) =>
    Offset(finger.dx, finger.dy - liftPx);

/// 按米微调一点：northM 向北、eastM 向东（局部等距圆柱近似，
/// 与中心线简化共用 110540 / 111320 常数）。
GeoPoint nudgeGeoPoint(GeoPoint p, {required double northM, required double eastM}) {
  final cosLat = math.cos(p.lat * math.pi / 180);
  return GeoPoint(
    p.lat + northM / 110540,
    p.lon + eastM / (111320 * (cosLat.abs() < 1e-6 ? 1e-6 : cosLat)),
  );
}

/// 最近点计算结果：线上最近点 / 沿线距离（米，自线首累计）/
/// 点到线的直线距离（米）。
typedef NearestOnPolyline = ({GeoPoint point, double alongM, double distM});

/// 点到折线的最近点（局部等距圆柱投影下的点到线段距离）。
/// 线不足 2 点时返回原点、沿线 0、距离 0。
NearestOnPolyline nearestOnPolyline(GeoPoint p, List<GeoPoint> line) {
  if (line.length < 2) return (point: p, alongM: 0, distM: 0);
  final cosLat = math.cos(p.lat * math.pi / 180);
  var bestDist = double.infinity;
  var bestPoint = line.first;
  var bestAlong = 0.0;
  var acc = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i];
    final b = line[i + 1];
    final segLen = polylineLengthM([a, b]);
    final bx = (b.lon - a.lon) * cosLat * 111320;
    final by = (b.lat - a.lat) * 110540;
    final px = (p.lon - a.lon) * cosLat * 111320;
    final py = (p.lat - a.lat) * 110540;
    final len2 = bx * bx + by * by;
    var t = 0.0;
    if (len2 > 0) {
      t = ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    }
    final cx = t * bx;
    final cy = t * by;
    final d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
    if (d < bestDist) {
      bestDist = d;
      bestPoint = GeoPoint(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon));
      bestAlong = acc + t * segLen;
    }
    acc += segLen;
  }
  return (point: bestPoint, alongM: bestAlong, distM: bestDist);
}

/// 把一点吸附到中心线最近点；无中心线时原样返回。
GeoPoint snapPointToCenterline(GeoPoint p, List<GeoPoint> line) {
  if (line.length < 2) return p;
  return nearestOnPolyline(p, line).point;
}

/// 一点在中心线上的沿线距离（米，自线首累计；无中心线时为 0）。
double centerlineDistanceAt(GeoPoint p, List<GeoPoint> line) {
  if (line.length < 2) return 0;
  return nearestOnPolyline(p, line).alongM;
}

/// 沿中心线取距离线首 [distanceM] 米处的点（超界钳制到两端）。
GeoPoint pointAtCenterlineDistance(List<GeoPoint> line, double distanceM) {
  if (line.isEmpty) return const GeoPoint(0, 0);
  if (line.length == 1 || distanceM <= 0) return line.first;
  var acc = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i];
    final b = line[i + 1];
    final segLen = polylineLengthM([a, b]);
    if (acc + segLen >= distanceM) {
      final t = segLen == 0 ? 0.0 : (distanceM - acc) / segLen;
      return GeoPoint(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon));
    }
    acc += segLen;
  }
  return line.last;
}

/// 画布视图变换：基础等距圆柱投影 + 缩放 + 平移。
///
/// 屏幕坐标 = (基础投影 − 画布中心) × zoom + 画布中心 + pan。
/// 缩放以手势焦点为锚点（焦点下的地理点不动），已落点与中心线
/// 共用同一变换，不漂移。
class EditorViewTransform {
  final LatLonProjection base;
  final Size size;
  double zoom;
  Offset pan;

  EditorViewTransform({
    required this.base,
    required this.size,
    this.zoom = editorMinZoom,
    this.pan = Offset.zero,
  });

  Offset get center => Offset(size.width / 2, size.height / 2);

  Offset project(GeoPoint p) {
    final (x, y) = base.project(p, size.width, size.height);
    return (Offset(x, y) - center) * zoom + center + pan;
  }

  GeoPoint unproject(Offset s) {
    final b = (s - center - pan) / zoom + center;
    return base.unproject(b.dx, b.dy, size.width, size.height);
  }

  /// 以 [focal] 为锚点缩放 [factor] 倍（钳制到 [editorMinZoom]–
  /// [editorMaxZoom]）。
  void zoomAt(Offset focal, double factor) {
    final newZoom = (zoom * factor).clamp(editorMinZoom, editorMaxZoom);
    final k = newZoom / zoom;
    pan = focal - (focal - center - pan) * k - center;
    zoom = newZoom;
    _clampPan();
  }

  /// 平移（双指拖动）；宽松钳制，不让赛道整体滑出视野太远。
  void panBy(Offset delta) {
    pan += delta;
    _clampPan();
  }

  void reset() {
    zoom = editorMinZoom;
    pan = Offset.zero;
  }

  void _clampPan() {
    final mx = size.width * 1.5;
    final my = size.height * 1.5;
    pan = Offset(pan.dx.clamp(-mx, mx), pan.dy.clamp(-my, my));
  }

  /// 当前缩放下的米 / 像素（精度提示用）。
  double get metersPerPixel {
    if (size.width <= 0 || size.height <= 0) return double.nan;
    final a = unproject(Offset.zero);
    final b = unproject(const Offset(1, 0));
    return polylineLengthM([a, b]);
  }
}

/// 多步撤销栈（上限 [maxDepth] 步，超限丢弃最旧快照）。
class EditorUndoStack<T> {
  final int maxDepth;
  final List<T> _items = [];

  EditorUndoStack({this.maxDepth = 50});

  bool get canUndo => _items.isNotEmpty;
  int get length => _items.length;

  void push(T item) {
    _items.add(item);
    if (_items.length > maxDepth) _items.removeAt(0);
  }

  T? undo() => _items.isEmpty ? null : _items.removeLast();

  void clear() => _items.clear();
}

/// 画布上的一个可编辑点（起点 / 终点 / 龙门架 / 维修区入口 /
/// 维修区出口 / 第 index 个分段点）。
class _SelectedPoint {
  final _EditTool kind;
  final int index; // 仅分段点用，其余为 -1

  const _SelectedPoint(this.kind, [this.index = -1]);

  @override
  bool operator ==(Object other) =>
      other is _SelectedPoint && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

class _EditorSnapshot {
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;
  final GeoPoint? gantry;
  final GeoPoint? pitIn;
  final GeoPoint? pitOut;
  final List<GeoPoint> sectors;

  _EditorSnapshot({
    required this.centerline,
    required this.start,
    required this.finish,
    required this.gantry,
    required this.pitIn,
    required this.pitOut,
    required this.sectors,
  });
}

enum _CanvasMode { none, crosshair, drag, zoom }

/// 赛道包编辑器。
class TrackPackageEditorPage extends StatefulWidget {
  final TrackPackage package;
  final ValueChanged<TrackPackage> onSave;

  const TrackPackageEditorPage({
    super.key,
    required this.package,
    required this.onSave,
  });

  @override
  State<TrackPackageEditorPage> createState() => _TrackPackageEditorPageState();
}

class _TrackPackageEditorPageState extends State<TrackPackageEditorPage> {
  late List<GeoPoint> _centerline;
  late GeoPoint? _start;
  late GeoPoint? _finish;
  late GeoPoint? _gantry;
  late GeoPoint? _pitIn;
  late GeoPoint? _pitOut;
  late List<GeoPoint> _sectors;
  _EditTool _tool = _EditTool.start;
  GeoPoint? _lastTap;
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  _EditTool _manualTarget = _EditTool.start;

  // v1.2.12：视图 / 准星 / 选中 / 吸附 / 撤销。
  double _zoom = editorMinZoom;
  Offset _pan = Offset.zero;
  Size _canvasSize = Size.zero;
  Offset? _crosshair;
  _CanvasMode _mode = _CanvasMode.none;
  double _lastScale = 1.0;
  bool _dragDirty = false;
  bool _snapEnabled = true;
  double _nudgeStepM = 1.0;
  _SelectedPoint? _selected;
  final _undo = EditorUndoStack<_EditorSnapshot>();

  // 卫星底图（默认关）：开后瓦片叠在中心线下；失败达阈值回落示意图。
  bool _satelliteEnabled = false;
  bool _satelliteFailed = false;
  int _failedSatelliteTiles = 0;
  int _pendingSatelliteErrors = 0;
  bool _satelliteErrorScheduled = false;

  /// 卫星开关：打开重计失败数（允许重试），关闭即回示意图。
  void _toggleSatellite(bool v) {
    setState(() {
      _satelliteEnabled = v;
      _satelliteFailed = false;
      _failedSatelliteTiles = 0;
      _pendingSatelliteErrors = 0;
    });
  }

  /// 单张瓦片加载失败上报：合并到下一帧统一计数，避免 build 期
  /// setState；累计达 [satelliteFallbackFailureThreshold] 张即回落
  /// 示意图（状态行给一句，不弹错、不白屏）。
  void _reportSatelliteTileError() {
    _pendingSatelliteErrors++;
    if (_satelliteErrorScheduled) return;
    _satelliteErrorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _satelliteErrorScheduled = false;
      if (!mounted) return;
      final n = _pendingSatelliteErrors;
      _pendingSatelliteErrors = 0;
      if (_satelliteFailed || !_satelliteEnabled) return;
      setState(() {
        _failedSatelliteTiles += n;
        if (_failedSatelliteTiles >= satelliteFallbackFailureThreshold) {
          _satelliteFailed = true;
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _centerline = List.of(widget.package.centerline);
    _start = widget.package.start;
    _finish = widget.package.finish;
    _gantry = widget.package.gantry;
    _pitIn = widget.package.pitIn;
    _pitOut = widget.package.pitOut;
    _sectors = List.of(widget.package.sectorPoints);
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  List<GeoPoint> get _framePoints {
    if (_centerline.isNotEmpty) return _centerline;
    return [
      if (_start != null) _start!,
      if (_finish != null) _finish!,
      if (_gantry != null) _gantry!,
      if (_pitIn != null) _pitIn!,
      if (_pitOut != null) _pitOut!,
      ..._sectors,
    ];
  }

  EditorViewTransform _transform(Size size) => EditorViewTransform(
    base: LatLonProjection(_framePoints),
    size: size,
    zoom: _zoom,
    pan: _pan,
  );

  _EditorSnapshot _capture() => _EditorSnapshot(
    centerline: List.of(_centerline),
    start: _start,
    finish: _finish,
    gantry: _gantry,
    pitIn: _pitIn,
    pitOut: _pitOut,
    sectors: List.of(_sectors),
  );

  void _pushUndo() => _undo.push(_capture());

  void _restore(_EditorSnapshot s) {
    _centerline = List.of(s.centerline);
    _start = s.start;
    _finish = s.finish;
    _gantry = s.gantry;
    _pitIn = s.pitIn;
    _pitOut = s.pitOut;
    _sectors = List.of(s.sectors);
    _selected = null;
    _lastTap = null;
  }

  void _doUndo() {
    final s = _undo.undo();
    if (s == null) return;
    setState(() => _restore(s));
  }

  GeoPoint? _pointOf(_SelectedPoint sel) => switch (sel.kind) {
    _EditTool.start => _start,
    _EditTool.finish => _finish,
    _EditTool.gantry => _gantry,
    _EditTool.pitIn => _pitIn,
    _EditTool.pitOut => _pitOut,
    _EditTool.sector =>
      (sel.index >= 0 && sel.index < _sectors.length) ? _sectors[sel.index] : null,
    _EditTool.outline => null,
  };

  void _setPointOf(_SelectedPoint sel, GeoPoint p) {
    switch (sel.kind) {
      case _EditTool.start:
        _start = p;
      case _EditTool.finish:
        _finish = p;
      case _EditTool.gantry:
        _gantry = p;
      case _EditTool.pitIn:
        _pitIn = p;
      case _EditTool.pitOut:
        _pitOut = p;
      case _EditTool.sector:
        if (sel.index >= 0 && sel.index < _sectors.length) {
          _sectors[sel.index] = p;
        }
      case _EditTool.outline:
        break;
    }
  }

  bool _isSnappable(_EditTool tool) => tool != _EditTool.outline;

  /// 吸附：有中心线且开关开时，把 [p] 吸到最近的中心线点。
  GeoPoint _maybeSnap(GeoPoint p, _EditTool tool) {
    if (!_snapEnabled || !_isSnappable(tool)) return p;
    return snapPointToCenterline(p, _centerline);
  }

  /// 画布命中检测：返回 [pos] 附近（30px 内）最近的可拖动点。
  _SelectedPoint? _hitTest(Offset pos) {
    if (_canvasSize.isEmpty) return null;
    final t = _transform(_canvasSize);
    _SelectedPoint? best;
    var bestDist = editorHitRadiusPx;
    void consider(GeoPoint? p, _SelectedPoint sel) {
      if (p == null) return;
      final d = (t.project(p) - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = sel;
      }
    }

    consider(_start, const _SelectedPoint(_EditTool.start));
    consider(_finish, const _SelectedPoint(_EditTool.finish));
    consider(_gantry, const _SelectedPoint(_EditTool.gantry));
    consider(_pitIn, const _SelectedPoint(_EditTool.pitIn));
    consider(_pitOut, const _SelectedPoint(_EditTool.pitOut));
    for (var i = 0; i < _sectors.length; i++) {
      consider(_sectors[i], _SelectedPoint(_EditTool.sector, i));
    }
    return best;
  }

  /// 手指位置 → 准星处经纬度（带吸附），越界返回 null。
  GeoPoint? _geoAtFinger(Offset finger, _EditTool tool) {
    if (_canvasSize.isEmpty) return null;
    final cross = editorCrosshairPosition(finger);
    final raw = _transform(_canvasSize).unproject(cross);
    if (raw.lat < -90 || raw.lat > 90 || raw.lon < -180 || raw.lon > 180) {
      return null;
    }
    return _maybeSnap(raw, tool);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1.0;
    _dragDirty = false;
    if (d.pointerCount == 1) {
      final hit = _hitTest(d.localFocalPoint);
      if (hit != null) {
        // 按住已有落点：进入拖动微调（选中该点）。
        _mode = _CanvasMode.drag;
        _selected = hit;
        setState(
          () => _crosshair = editorCrosshairPosition(d.localFocalPoint),
        );
      } else {
        _mode = _CanvasMode.crosshair;
        setState(
          () => _crosshair = editorCrosshairPosition(d.localFocalPoint),
        );
      }
    } else {
      _mode = _CanvasMode.zoom;
      setState(() => _crosshair = null);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 || d.scale != 1.0) {
      // 捏合缩放 / 双指平移。
      if (_mode != _CanvasMode.zoom) {
        _mode = _CanvasMode.zoom;
        _crosshair = null;
      }
      final factor = d.scale / _lastScale;
      _lastScale = d.scale;
      final t = _transform(_canvasSize);
      t.zoomAt(d.localFocalPoint, factor);
      t.panBy(d.focalPointDelta);
      setState(() {
        _zoom = t.zoom;
        _pan = t.pan;
        _crosshair = null;
      });
      return;
    }
    _lastScale = 1.0;
    final pos = d.localFocalPoint;
    if (_mode == _CanvasMode.crosshair) {
      setState(() => _crosshair = editorCrosshairPosition(pos));
    } else if (_mode == _CanvasMode.drag && _selected != null) {
      final sel = _selected!;
      final geo = _geoAtFinger(pos, sel.kind);
      if (geo == null) return;
      if (!_dragDirty) {
        _pushUndo();
        _dragDirty = true;
      }
      setState(() {
        _setPointOf(sel, geo);
        _lastTap = geo;
        _crosshair = editorCrosshairPosition(pos);
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _CanvasMode.crosshair && _crosshair != null) {
      // 松手才落点：准星处经纬度（已吸附）。
      final raw = _transform(_canvasSize).unproject(_crosshair!);
      if (raw.lat < -90 || raw.lat > 90 || raw.lon < -180 || raw.lon > 180) {
        showAppNotice(context, '落点超出经纬度范围，请点在赛道区域内', AppNoticeKind.warning);
      } else {
        _commitDrop(_maybeSnap(raw, _tool));
      }
    }
    // 拖动模式已在移动中实时写回并压过撤销快照，松手只需清状态。
    setState(() {
      _mode = _CanvasMode.none;
      _crosshair = null;
      _dragDirty = false;
    });
  }

  void _commitDrop(GeoPoint p) {
    _pushUndo();
    setState(() {
      _lastTap = p;
      switch (_tool) {
        case _EditTool.start:
          _start = p;
          _selected = const _SelectedPoint(_EditTool.start);
        case _EditTool.finish:
          _finish = p;
          _selected = const _SelectedPoint(_EditTool.finish);
        case _EditTool.gantry:
          _gantry = p;
          _selected = const _SelectedPoint(_EditTool.gantry);
        case _EditTool.pitIn:
          _pitIn = p;
          _selected = const _SelectedPoint(_EditTool.pitIn);
        case _EditTool.pitOut:
          _pitOut = p;
          _selected = const _SelectedPoint(_EditTool.pitOut);
        case _EditTool.sector:
          _sectors.add(p);
          _selected = _SelectedPoint(_EditTool.sector, _sectors.length - 1);
        case _EditTool.outline:
          if (_centerline.length >= 2 &&
              _centerline.first.lat == _centerline.last.lat &&
              _centerline.first.lon == _centerline.last.lon) {
            // 闭合回路：新点插在末点之前，保持首尾重合。
            _centerline.insert(_centerline.length - 1, p);
          } else {
            _centerline.add(p);
          }
          _selected = null;
          // 轮廓变了，参照系跟着变：回到全景，避免视图错位。
          _zoom = editorMinZoom;
          _pan = Offset.zero;
      }
    });
  }

  void _manualDrop() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null ||
        lon == null ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      showAppNotice(
        context,
        '经纬度格式不对（纬度 -90~90，经度 -180~180）',
        AppNoticeKind.warning,
      );
      return;
    }
    _pushUndo();
    setState(() {
      // 手动输入不吸附：输入值即为准。
      _lastTap = GeoPoint(lat, lon);
      switch (_manualTarget) {
        case _EditTool.start:
          _start = GeoPoint(lat, lon);
          _selected = const _SelectedPoint(_EditTool.start);
        case _EditTool.finish:
          _finish = GeoPoint(lat, lon);
          _selected = const _SelectedPoint(_EditTool.finish);
        case _EditTool.gantry:
          _gantry = GeoPoint(lat, lon);
          _selected = const _SelectedPoint(_EditTool.gantry);
        case _EditTool.pitIn:
          _pitIn = GeoPoint(lat, lon);
          _selected = const _SelectedPoint(_EditTool.pitIn);
        case _EditTool.pitOut:
          _pitOut = GeoPoint(lat, lon);
          _selected = const _SelectedPoint(_EditTool.pitOut);
        case _EditTool.sector:
          _sectors.add(GeoPoint(lat, lon));
          _selected = _SelectedPoint(_EditTool.sector, _sectors.length - 1);
        case _EditTool.outline:
          _centerline.add(GeoPoint(lat, lon));
          _zoom = editorMinZoom;
          _pan = Offset.zero;
      }
    });
  }

  /// 方向键微调：选中点按 [northM]/[eastM] 移动（不二次吸附）。
  void _nudge(double northM, double eastM) {
    final sel = _selected;
    if (sel == null) return;
    final cur = _pointOf(sel);
    if (cur == null) return;
    _pushUndo();
    final moved = nudgeGeoPoint(cur, northM: northM, eastM: eastM);
    setState(() {
      _setPointOf(sel, moved);
      _lastTap = moved;
    });
  }

  void _removeLastOutlinePoint() {
    if (_centerline.isEmpty) return;
    _pushUndo();
    setState(() {
      if (_centerline.length >= 2 &&
          _centerline.first.lat == _centerline.last.lat &&
          _centerline.first.lon == _centerline.last.lon &&
          _centerline.length > 2) {
        _centerline.removeAt(_centerline.length - 2);
      } else {
        _centerline.removeLast();
      }
      _zoom = editorMinZoom;
      _pan = Offset.zero;
    });
  }

  void _removeLastSectorPoint() {
    if (_sectors.isEmpty) return;
    _pushUndo();
    setState(() {
      _sectors.removeLast();
      _selected = null;
    });
  }

  Future<void> _clearOutline() async {
    if (_centerline.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空轮廓？'),
        content: const Text('轮廓点将全部删除（起点、终点、维修区出入口、分段点不受影响）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _pushUndo();
      setState(() {
        _centerline.clear();
        _zoom = editorMinZoom;
        _pan = Offset.zero;
      });
    }
  }

  void _zoomBy(double factor) {
    if (_canvasSize.isEmpty) return;
    final t = _transform(_canvasSize);
    t.zoomAt(t.center, factor);
    setState(() {
      _zoom = t.zoom;
      _pan = t.pan;
    });
  }

  void _resetView() {
    setState(() {
      _zoom = editorMinZoom;
      _pan = Offset.zero;
    });
  }

  void _save() {
    final lengthM = _centerline.length >= 2
        ? polylineLengthM(_centerline).round()
        : widget.package.lengthM;
    // 实测替换规则：用户改动了分段点，分段来源就不再是推导值，必须同步
    // 改写 sectorNote，否则界面仍会把实测点标成“模拟器数据推导”。
    final sectorNote = sectorNoteAfterEdit(
      original: widget.package.sectorPoints,
      edited: _sectors,
      originalNote: widget.package.sectorNote,
    );
    final updated = widget.package.copyWith(
      centerline: _centerline,
      start: _start,
      finish: _finish,
      gantry: _gantry,
      pitIn: _pitIn,
      pitOut: _pitOut,
      sectorPoints: _sectors,
      sectorNote: sectorNote,
      lengthM: lengthM,
      verification: TrackPackageVerification.pending,
      verificationNote: '用户编辑，待核对',
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _framePoints;
    final lengthLabel = _centerline.length >= 2
        ? '${(polylineLengthM(_centerline) / 1000).toStringAsFixed(3)} km'
        : widget.package.lengthLabel;
    final mpp = frame.isEmpty || _canvasSize.isEmpty
        ? double.nan
        : _transform(_canvasSize).metersPerPixel;
    final precisionLabel = mpp.isFinite
        ? '精度约 ${mpp < 10 ? mpp.toStringAsFixed(1) : mpp.round()} 米/像素'
        : '';
    // 吸附预览：准星处的原始点与吸附后点的屏幕位置（不同时画虚线）。
    Offset? snapPreview;
    if (_crosshair != null &&
        _snapEnabled &&
        _centerline.length >= 2 &&
        !_canvasSize.isEmpty) {
      final t = _transform(_canvasSize);
      final raw = t.unproject(_crosshair!);
      final snapped = snapPointToCenterline(raw, _centerline);
      if (polylineLengthM([raw, snapped]) > 0.5) {
        snapPreview = t.project(snapped);
      }
    }
    final selectedSector =
        _selected?.kind == _EditTool.sector &&
        _selected!.index >= 0 &&
        _selected!.index < _sectors.length &&
        _centerline.length >= 2;
    final totalLenM = _centerline.length >= 2
        ? polylineLengthM(_centerline)
        : 0.0;
    final sectorDistM = selectedSector
        ? centerlineDistanceAt(_sectors[_selected!.index], _centerline)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text('编辑：${widget.package.nameCn}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '撤销',
            onPressed: _undo.canUndo ? _doUndo : null,
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 0)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '按住画布拖动准星，松手落点；按住已有落点可拖动微调；捏合缩放、双指平移。保存后核对状态回落为待核。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                // 工具切换：大卡片分段选择，当前工具高亮。
                Row(
                  children: _EditTool.values.map((t) {
                    final selected = _tool == t;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: t == _EditTool.values.last ? 0 : 6,
                        ),
                        child: InkWell(
                          onTap: () => setState(() => _tool = t),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 64,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFE10600).withValues(alpha: 0.18)
                                  : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFE10600)
                                    : Colors.white.withValues(alpha: 0.14),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  t.icon,
                                  size: 22,
                                  color: selected
                                      ? const Color(0xFFE10600)
                                      : Colors.white70,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                // 缩放 / 全景 / 吸附工具栏。
                Row(
                  children: [
                    _toolbarButton(
                      icon: Icons.zoom_out,
                      tooltip: '缩小',
                      onPressed: _zoom <= editorMinZoom
                          ? null
                          : () => _zoomBy(1 / 1.25),
                    ),
                    SizedBox(
                      width: 52,
                      child: Center(
                        child: Text(
                          '${(_zoom * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    _toolbarButton(
                      icon: Icons.zoom_in,
                      tooltip: '放大',
                      onPressed: _zoom >= editorMaxZoom
                          ? null
                          : () => _zoomBy(1.25),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: (_zoom == editorMinZoom && _pan == Offset.zero)
                            ? null
                            : _resetView,
                        child: const Text('回到全景'),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '吸附',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Switch(
                      value: _snapEnabled,
                      activeThumbColor: const Color(0xFFE10600),
                      onChanged: (v) => setState(() => _snapEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 卫星底图开关（默认关；整行 44px 可点，与吸附开关同区）。
                InkWell(
                  onTap: () => _toggleSatellite(!_satelliteEnabled),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _satelliteEnabled
                            ? const Color(0xFFE10600)
                            : Colors.white.withValues(alpha: 0.14),
                        width: _satelliteEnabled ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.satellite_alt,
                          size: 20,
                          color: _satelliteEnabled
                              ? const Color(0xFFE10600)
                              : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '卫星底图',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _satelliteEnabled
                                ? satelliteTileAttribution
                                : '对照真实起跑线与龙门架',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Switch(
                          key: const ValueKey('satelliteToggle'),
                          value: _satelliteEnabled,
                          activeThumbColor: const Color(0xFFE10600),
                          onChanged: _toggleSatellite,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 画布（不在滚动区内，单指拖动不与页面滚动抢手势）。
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: frame.isEmpty
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '暂无坐标：请先在库页从行程导入轮廓，或在下方手动输入坐标落点。',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);
                        _canvasSize = size;
                        // 卫星开且未回落时才叠瓦片层；回落即回纯示意图。
                        final showSatellite =
                            _satelliteEnabled && !_satelliteFailed;
                        final canvas = GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          child: CustomPaint(
                            size: size,
                            painter: _EditorPainter(
                              transform: _transform(size),
                              centerline: _centerline,
                              start: _start,
                              finish: _finish,
                              gantry: _gantry,
                              pitIn: _pitIn,
                              pitOut: _pitOut,
                              sectors: _sectors,
                              lastTap: _lastTap,
                              selected: _selected,
                              crosshair: _crosshair,
                              snapPreview: snapPreview,
                              satelliteOn: showSatellite,
                            ),
                          ),
                        );
                        if (!showSatellite) return canvas;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              _SatelliteTiles(
                                transform: _transform(size),
                                size: size,
                                onTileError: _reportSatelliteTileError,
                              ),
                              canvas,
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '轮廓 ${_centerline.length} 点 · 分段 ${_sectors.length} 点 · 当前长度 $lengthLabel'
              '${precisionLabel.isEmpty ? '' : ' · $precisionLabel'}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          if (_satelliteEnabled && _satelliteFailed)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                '卫星图未加载，已显示示意图',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ),
          if (_lastTap != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Text(
                '上次落点：${_lastTap!.lat.toStringAsFixed(5)}, ${_lastTap!.lon.toStringAsFixed(5)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          // 下半区：点列表 / 滑块 / 方向键 / 手动输入 / 保存取消。
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '落点列表（点某行选中该点，再用方向键或滑块微调）',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _pointRow(
                    color: Colors.green,
                    label: '起点',
                    point: _start,
                    selected: _selected == const _SelectedPoint(_EditTool.start),
                    onTap: _start == null
                        ? null
                        : () => setState(
                            () => _selected = const _SelectedPoint(_EditTool.start),
                          ),
                  ),
                  _pointRow(
                    color: Colors.black,
                    label: '终点',
                    point: _finish,
                    selected: _selected == const _SelectedPoint(_EditTool.finish),
                    onTap: _finish == null
                        ? null
                        : () => setState(
                            () => _selected = const _SelectedPoint(_EditTool.finish),
                          ),
                  ),
                  _pointRow(
                    color: Colors.orange,
                    label: '龙门架',
                    point: _gantry,
                    selected: _selected == const _SelectedPoint(_EditTool.gantry),
                    onTap: _gantry == null
                        ? null
                        : () => setState(
                            () => _selected = const _SelectedPoint(_EditTool.gantry),
                          ),
                  ),
                  _pointRow(
                    color: Colors.purple,
                    label: '维修区入口',
                    point: _pitIn,
                    selected: _selected == const _SelectedPoint(_EditTool.pitIn),
                    onTap: _pitIn == null
                        ? null
                        : () => setState(
                            () => _selected = const _SelectedPoint(_EditTool.pitIn),
                          ),
                  ),
                  _pointRow(
                    color: Colors.teal,
                    label: '维修区出口',
                    point: _pitOut,
                    selected: _selected == const _SelectedPoint(_EditTool.pitOut),
                    onTap: _pitOut == null
                        ? null
                        : () => setState(
                            () => _selected = const _SelectedPoint(_EditTool.pitOut),
                          ),
                  ),
                  for (var i = 0; i < _sectors.length; i++)
                    _pointRow(
                      color: Colors.blue,
                      label: '分段 S${i + 1}',
                      point: _sectors[i],
                      trailing: _centerline.length >= 2
                          ? '距起点 ${centerlineDistanceAt(_sectors[i], _centerline).round()} 米'
                          : null,
                      selected: _selected == _SelectedPoint(_EditTool.sector, i),
                      onTap: () => setState(
                        () => _selected = _SelectedPoint(_EditTool.sector, i),
                      ),
                    ),
                  if (selectedSector) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          '沿中心线微调',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          '距起点 ${sectorDistM.round()} / ${totalLenM.round()} 米',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: sectorDistM.clamp(0.0, totalLenM),
                      max: totalLenM,
                      activeColor: const Color(0xFFE10600),
                      onChangeStart: (_) => _pushUndo(),
                      onChanged: (v) {
                        final sel = _selected!;
                        setState(() {
                          _setPointOf(
                            sel,
                            pointAtCenterlineDistance(_centerline, v),
                          );
                          _lastTap = _pointOf(sel);
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  // 方向键微调。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          _nudgeButton(
                            icon: Icons.keyboard_arrow_up,
                            onPressed: _selected == null
                                ? null
                                : () => _nudge(_nudgeStepM, 0),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _nudgeButton(
                                icon: Icons.keyboard_arrow_left,
                                onPressed: _selected == null
                                    ? null
                                    : () => _nudge(0, -_nudgeStepM),
                              ),
                              _nudgeButton(
                                icon: Icons.keyboard_arrow_down,
                                onPressed: _selected == null
                                    ? null
                                    : () => _nudge(-_nudgeStepM, 0),
                              ),
                              _nudgeButton(
                                icon: Icons.keyboard_arrow_right,
                                onPressed: _selected == null
                                    ? null
                                    : () => _nudge(0, _nudgeStepM),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '微调步长',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [1.0, 5.0].map((s) {
                                final selected = _nudgeStepM == s;
                                return ChoiceChip(
                                  label: Text('${s.toStringAsFixed(0)} 米'),
                                  selected: selected,
                                  selectedColor: const Color(0xFFE10600),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _nudgeStepM = s),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _selected == null
                                  ? '未选中落点：点画布上的点或上方列表选中。'
                                  : '已选中 ${_selectedLabel(_selected!)}，方向键按步长移动。',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _centerline.isEmpty
                            ? null
                            : _removeLastOutlinePoint,
                        child: const Text('删除轮廓末点'),
                      ),
                      OutlinedButton(
                        onPressed: _sectors.isEmpty
                            ? null
                            : _removeLastSectorPoint,
                        child: const Text('删除末分段点'),
                      ),
                      OutlinedButton(
                        onPressed: _centerline.isEmpty ? null : _clearOutline,
                        child: const Text('清空轮廓'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '手动输入坐标落点',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      DropdownButton<_EditTool>(
                        value: _manualTarget,
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        items: _EditTool.values
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.label),
                              ),
                            )
                            .toList(),
                        onChanged: (t) {
                          if (t != null) setState(() => _manualTarget = t);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _latCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: '纬度',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _lonCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: '经度',
                            labelStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _manualDrop,
                          child: const Text('落点'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE10600),
                            ),
                            onPressed: _save,
                            child: const Text('保存'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _selectedLabel(_SelectedPoint sel) => switch (sel.kind) {
    _EditTool.start => '起点',
    _EditTool.finish => '终点',
    _EditTool.gantry => '龙门架',
    _EditTool.pitIn => '维修区入口',
    _EditTool.pitOut => '维修区出口',
    _EditTool.sector => '分段 S${sel.index + 1}',
    _EditTool.outline => '轮廓点',
  };

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        color: Colors.white,
        onPressed: onPressed,
      ),
    );
  }

  Widget _nudgeButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2A2A2A),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _pointRow({
    required Color color,
    required String label,
    required GeoPoint? point,
    String? trailing,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE10600).withValues(alpha: 0.15)
                : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE10600)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  point == null
                      ? '未设置'
                      : '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final EditorViewTransform transform;
  final List<GeoPoint> centerline;
  final GeoPoint? start;
  final GeoPoint? finish;
  final GeoPoint? gantry;
  final GeoPoint? pitIn;
  final GeoPoint? pitOut;
  final List<GeoPoint> sectors;
  final GeoPoint? lastTap;
  final _SelectedPoint? selected;
  final Offset? crosshair;
  final Offset? snapPreview;

  /// 卫星底图开启时为 true：跳过深色底（瓦片层已铺底），中心线与
  /// 点位改描白边 / 加白晕，保证在影像上看得清。
  final bool satelliteOn;

  _EditorPainter({
    required this.transform,
    required this.centerline,
    required this.start,
    required this.finish,
    required this.gantry,
    required this.pitIn,
    required this.pitOut,
    required this.sectors,
    required this.lastTap,
    required this.selected,
    required this.crosshair,
    required this.snapPreview,
    this.satelliteOn = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!satelliteOn) {
      final bg = Paint()..color = const Color(0xFF0A0A0A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
        bg,
      );
    }
    Offset pt(GeoPoint p) => transform.project(p);

    if (centerline.length >= 2) {
      final path = Path()
        ..moveTo(pt(centerline.first).dx, pt(centerline.first).dy);
      for (var i = 1; i < centerline.length; i++) {
        final o = pt(centerline[i]);
        path.lineTo(o.dx, o.dy);
      }
      if (satelliteOn) {
        // 白晕打底：红线在亮 / 暗影像上都看得清。
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

    void dot(GeoPoint p, Color color, String label, bool isSelected) {
      final o = pt(p);
      if (isSelected) {
        canvas.drawCircle(
          o,
          15,
          Paint()
            ..color = const Color(0xFFE10600)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(o, 9, Paint()..color = color);
      // 点位描白边：卫星图上用 3px 实白边，示意图上沿用 1px 白灰边。
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
        // 标签暗底：白字在亮色影像上仍可读。
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

    for (var i = 0; i < sectors.length; i++) {
      dot(
        sectors[i],
        Colors.blue,
        'S${i + 1}',
        selected == _SelectedPoint(_EditTool.sector, i),
      );
    }
    if (gantry != null) {
      dot(gantry!, Colors.orange, '门', selected == const _SelectedPoint(_EditTool.gantry));
    }
    if (pitIn != null) {
      dot(pitIn!, Colors.purple, '入', selected == const _SelectedPoint(_EditTool.pitIn));
    }
    if (pitOut != null) {
      dot(pitOut!, Colors.teal, '出', selected == const _SelectedPoint(_EditTool.pitOut));
    }
    if (finish != null) {
      dot(finish!, Colors.black, '终', selected == const _SelectedPoint(_EditTool.finish));
    }
    if (start != null) {
      dot(start!, Colors.green, '起', selected == const _SelectedPoint(_EditTool.start));
    }
    if (lastTap != null) {
      final o = pt(lastTap!);
      canvas.drawCircle(
        o,
        5,
        Paint()
          ..color = Colors.white54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    // 吸附预览：准星（实线）与吸附后位置（空心圈）之间的虚线。
    if (crosshair != null && snapPreview != null) {
      final dash = Paint()
        ..color = Colors.white54
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      const step = 6.0;
      final total = (snapPreview! - crosshair!).distance;
      final dir = (snapPreview! - crosshair!) / total;
      var d = 0.0;
      while (d < total) {
        final a = crosshair! + dir * d;
        final b = crosshair! + dir * (d + step / 2).clamp(0.0, total);
        path.moveTo(a.dx, a.dy);
        path.lineTo(b.dx, b.dy);
        d += step;
      }
      canvas.drawPath(path, dash);
      canvas.drawCircle(
        snapPreview!,
        8,
        Paint()
          ..color = const Color(0xFFE10600)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // 十字准星：手指上方，不被盖住。
    if (crosshair != null) {
      final c = crosshair!;
      if (satelliteOn) {
        canvas.drawCircle(
          c,
          16,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
      final paint = Paint()
        ..color = const Color(0xFFE10600)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(c, 14, paint);
      canvas.drawLine(c + const Offset(-22, 0), c + const Offset(-8, 0), paint);
      canvas.drawLine(c + const Offset(8, 0), c + const Offset(22, 0), paint);
      canvas.drawLine(c + const Offset(0, -22), c + const Offset(0, -8), paint);
      canvas.drawLine(c + const Offset(0, 8), c + const Offset(0, 22), paint);
      canvas.drawCircle(
        c,
        2,
        Paint()..color = const Color(0xFFE10600),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) =>
      old.transform.zoom != transform.zoom ||
      old.transform.pan != transform.pan ||
      old.centerline != centerline ||
      old.start != start ||
      old.finish != finish ||
      old.gantry != gantry ||
      old.pitIn != pitIn ||
      old.pitOut != pitOut ||
      old.sectors != sectors ||
      old.lastTap != lastTap ||
      old.selected != selected ||
      old.crosshair != crosshair ||
      old.snapPreview != snapPreview ||
      old.satelliteOn != satelliteOn;
}

/// 卫星瓦片层：只在卫星开关开启时参与绘制。
///
/// 摆位复用编辑器同一 [EditorViewTransform]：先由变换反推可见经纬度
/// 范围，再按画布米 / 像素选瓦片缩放、拼出覆盖范围的瓦片，逐张按
/// [satelliteTileScreenRect] 落到屏幕矩形（Image.network 拼贴，
/// 无新依赖）。单张失败只留深色占位并上报一次；累计失败达阈值时
/// 由编辑页回落示意图。
class _SatelliteTiles extends StatelessWidget {
  final EditorViewTransform transform;
  final Size size;
  final VoidCallback onTileError;

  const _SatelliteTiles({
    required this.transform,
    required this.size,
    required this.onTileError,
  });

  @override
  Widget build(BuildContext context) {
    if (size.isEmpty) return const SizedBox.shrink();
    final corners = [
      transform.unproject(Offset.zero),
      transform.unproject(Offset(size.width, 0)),
      transform.unproject(Offset(0, size.height)),
      transform.unproject(Offset(size.width, size.height)),
    ];
    var minLat = corners.first.lat;
    var maxLat = corners.first.lat;
    var minLon = corners.first.lon;
    var maxLon = corners.first.lon;
    for (final c in corners) {
      minLat = math.min(minLat, c.lat);
      maxLat = math.max(maxLat, c.lat);
      minLon = math.min(minLon, c.lon);
      maxLon = math.max(maxLon, c.lon);
    }
    final mpp = transform.metersPerPixel;
    final tiles = satelliteTilesForBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      metersPerPixel: mpp.isFinite && mpp > 0 ? mpp : 10.0,
      latitude: (minLat + maxLat) / 2,
    );
    return Stack(
      children: [
        Container(color: const Color(0xFF0A0A0A)),
        for (final t in tiles)
          Positioned.fromRect(
            rect: satelliteTileScreenRect(transform, t.z, t.x, t.y),
            child: Image.network(
              satelliteTileUrl(t.z, t.x, t.y),
              key: ValueKey('sat-${t.z}-${t.x}-${t.y}'),
              headers: const {'User-Agent': 'DriveTrack/1.5.6'},
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) {
                onTileError();
                return Container(color: const Color(0xFF0A0A0A));
              },
            ),
          ),
      ],
    );
  }
}
