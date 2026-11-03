// v0.1.8 记录页 3D 黑色风格地图（新建文件，不改 refined_map.dart，
// 行程详情页的 RefinedMap 瓦片地图不受影响）。
//
// 风格化示意，非真实建筑/路网、非真实 3D 城市模型：
// 本文件只用 Flutter CustomPainter 自绘，零 pub 插件，不引入任何需要
// API Key 的第三方 3D 地图 SDK，不画任何真实建筑、真实路网数据。
// 画面元素只有：深炭灰底、远处地平线微光、透视网格地面、风格化暗色
// 光晕块、轨迹线、起点/照片点立体标记、场景中心车标。
// v1.0.4 路网：联网时按当前位置周边向 Overpass API（OpenStreetMap
// 道路数据）拉取并缓存道路线，在透视场景里以暗灰细线 + 微弱发光
// 画出（道路暗、轨迹亮）；无网络或无数据时退回现有网格 + 轨迹，
// 并在地图角落小字注明“路网未加载”。不编造道路、不画真实导航图、
// 不恢复瓦片旋转地图。
// 轨迹点复用调用方传入的经纬度 + 速度，不改 Recorder 的数据模型。
//
// 视角：跟随车头的 3D 俯视透视，俯仰角约 60-70 度（地平线在画面
// 约 16% 高处、车标在约 72% 高处，近大远小）；车头朝上为默认跟随
// 模式（headingUp=true 时场景按车头朝向旋转，车标恒朝上；
// headingUp=false 时北向上，车标按朝向旋转）。
// 2D 俯视是同一场景去掉透视的俯视投影，不是瓦片地图。
//
// 性能：投影是 O(n) 的简单三角运算；绘制前按屏幕距离抽稀
// （相邻保留点 < 7px 时跳过，末点恒保留），并做同侧视野裁剪，
// 不每帧全量绘制全部线段；轨迹点再多也不会逐段画到卡顿。
// 回退：调用方角落有 3D 透视 / 2D 俯视切换按钮；3D 渲染异常时
// 用户切 2D 俯视即可继续记录，不卡死（记录流程与本组件无关）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'native.dart';
import 'photo_points.dart';

/// 3D 地图用的最小轨迹点（经纬度 + 时速），调用方由 TrackPoint 映射，
/// 不依赖 models.dart，避免与详情页耦合。
class Recording3dPoint {
  final double lat;
  final double lon;
  final double speedKmh;
  const Recording3dPoint({required this.lat, required this.lon, this.speedKmh = 0});
}

/// v1.0.4：OpenStreetMap 道路线（Overpass API 拉取结果的折线）。
class RoadWay {
  final List<(double, double)> points; // (lat, lon)
  const RoadWay(this.points);
}

/// v1.0.7：Overpass 拉取结果（含失败分档，绝不编造道路）。
class RoadFetchResult {
  final List<RoadWay> ways;
  /// none=成功有数据，empty=成功但周边无道路，offline=无网络，
  /// timeout=超时，busy=服务器繁忙（HTTP 429/502/503/504），other=其他失败。
  final String errorKind;
  const RoadFetchResult(this.ways, this.errorKind);
}

/// v1.0.7：按中心点周边 1000 米向 Overpass 拉取 highway 道路线。
/// 改动：POST + User-Agent，按顺序轮换多个公开镜像，一个失败立即试
/// 下一个（实测 overpass-api.de 不带 UA 406、带 UA 502 已满，单站
/// 不可靠；国内直连更难）。失败原因分档返回，调用方如实显示。
Future<RoadFetchResult> fetchRoadWaysAround(double lat, double lon) async {
  const mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  const queryTemplate = '[out:json][timeout:20];(way["highway"](around:1000,__LAT__,__LON__););out geom;';
  final query = queryTemplate
      .replaceAll('__LAT__', lat.toString())
      .replaceAll('__LON__', lon.toString());
  var lastKind = 'other';
  for (final base in mirrors) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse(base));
      req.headers.set('User-Agent', 'DriveTrack/1.0.7');
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write('data=${Uri.encodeQueryComponent(query)}');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 429 ||
          resp.statusCode == 502 ||
          resp.statusCode == 503 ||
          resp.statusCode == 504) {
        lastKind = 'busy';
        continue;
      }
      if (resp.statusCode != 200) {
        lastKind = 'other';
        continue;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? const [];
      final ways = <RoadWay>[];
      for (final e in elements) {
        if (e is! Map || e['type'] != 'way') continue;
        final geom = (e['geometry'] as List?) ?? const [];
        final pts = <(double, double)>[];
        for (final g in geom) {
          if (g is Map && g['lat'] is num && g['lon'] is num) {
            pts.add(((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()));
          }
        }
        if (pts.length >= 2) ways.add(RoadWay(pts));
        if (ways.length >= 200) break;
      }
      return RoadFetchResult(ways, ways.isEmpty ? 'empty' : 'none');
    } on SocketException {
      lastKind = 'offline';
    } on TimeoutException {
      lastKind = 'timeout';
    } catch (_) {
      lastKind = 'other';
    } finally {
      client.close();
    }
  }
  return RoadFetchResult(const [], lastKind);
}

/// v1.0.7：路网缓存文件（按经纬度取 2 位小数分格，约 1km 一格）。
Future<String?> _roadCachePath(double lat, double lon) async {
  try {
    final dir = await Native.getCacheDir();
    return '$dir/road_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}.json';
  } catch (_) {
    return null;
  }
}

Future<List<RoadWay>> _loadCachedRoads(double lat, double lon) async {
  try {
    final path = await _roadCachePath(lat, lon);
    if (path == null) return const [];
    final f = File(path);
    if (!await f.exists()) return const [];
    final data = jsonDecode(await f.readAsString()) as List;
    final ways = <RoadWay>[];
    for (final w in data) {
      if (w is! List) continue;
      final pts = <(double, double)>[];
      for (final p in w) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
      if (pts.length >= 2) ways.add(RoadWay(pts));
    }
    return ways;
  } catch (_) {
    return const [];
  }
}

Future<void> _saveCachedRoads(double lat, double lon, List<RoadWay> ways) async {
  try {
    final path = await _roadCachePath(lat, lon);
    if (path == null || ways.isEmpty) return;
    final data = ways.map((w) => w.points.map((p) => [p.$1, p.$2]).toList()).toList();
    await File(path).writeAsString(jsonEncode(data));
  } catch (_) {}
}

class Recording3dMap extends StatefulWidget {
  final double centerLat;
  final double centerLon;
  final double headingDeg;
  final List<Recording3dPoint> points;
  final List<PhotoPoint> photoPoints;
  final bool is3d;
  final ValueChanged<bool> onModeChanged;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool headingUp;
  final VoidCallback onCompassTap;
  final Color accentColor;
  final Color vehicleColor;
  // v1.0.2：新 3D 车标画笔（调用方用 markerPainterFor 传入，headingDeg=0，
  // 外层已按朝向旋转，避免双重旋转）；为空时回落旧三角车体。
  final CustomPainter? vehicleMarkerPainter;

  const Recording3dMap({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.headingDeg,
    required this.points,
    this.photoPoints = const [],
    required this.is3d,
    required this.onModeChanged,
    required this.zoom,
    required this.onZoomChanged,
    required this.headingUp,
    required this.onCompassTap,
    required this.accentColor,
    required this.vehicleColor,
    this.vehicleMarkerPainter,
  });

  @override
  State<Recording3dMap> createState() => _Recording3dMapState();
}

class _Recording3dMapState extends State<Recording3dMap> {
  List<RoadWay> _roads = const [];
  bool _roadLoaded = false;
  bool _roadFromCache = false;
  String? _roadError;
  bool _fetching = false;
  double? _fetchLat;
  double? _fetchLon;
  DateTime? _lastAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetch());
  }

  @override
  void didUpdateWidget(covariant Recording3dMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFetch();
  }

  double _distM(double lat1, double lon1, double lat2, double lon2) {
    final dx = (lon2 - lon1) * math.cos(lat1 * math.pi / 180) * 111320;
    final dy = (lat2 - lat1) * 110540;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _maybeFetch({bool force = false}) {
    if (!mounted) return;
    if (widget.centerLat == 0 && widget.centerLon == 0) return;
    if (_fetching) return;
    // v1.0.7：失败不记 _fetchLat；成功有数据才记位置。静止时只要距
    // 上次尝试超过 30 秒就重试，不再出现“失败一次、400 米内永不重拉”。
    if (!force && _fetchLat != null &&
        _distM(_fetchLat!, _fetchLon!, widget.centerLat, widget.centerLon) <= 400) {
      return;
    }
    if (!force && _lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!) < const Duration(seconds: 30)) {
      return;
    }
    _fetching = true;
    _lastAttempt = DateTime.now();
    final lat = widget.centerLat;
    final lon = widget.centerLon;
    // 先读缓存：网络不行时也能先显示上次成功的路网。
    _loadCachedRoads(lat, lon).then((cached) {
      if (!mounted) return;
      if (cached.isNotEmpty && !_roadLoaded) {
        setState(() {
          _roads = cached;
          _roadFromCache = true;
        });
      }
    });
    fetchRoadWaysAround(lat, lon).then((result) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        if (result.ways.isNotEmpty) {
          _fetchLat = lat;
          _fetchLon = lon;
          _roads = result.ways;
          _roadLoaded = true;
          _roadFromCache = false;
          _roadError = null;
          _saveCachedRoads(lat, lon, result.ways);
        } else {
          // 失败不记 _fetchLat（下次 30 秒后可重试）；成功但无道路时
          // 同样不记位置，避免把“无数据”误当成已拉取。
          _roadError = switch (result.errorKind) {
            'offline' => '无网络',
            'timeout' => '请求超时',
            'busy' => '服务器繁忙',
            'empty' => '周边无道路数据',
            _ => '拉取失败',
          };
          if (!_roadLoaded) _roadFromCache = _roads.isNotEmpty;
        }
      });
    });
  }

  void _manualRefresh() {
    _fetchLat = null;
    _lastAttempt = null;
    _maybeFetch(force: true);
  }

  String get _roadLabel {
    if (_roadLoaded) return '路网：OpenStreetMap';
    if (_roadFromCache && _roads.isNotEmpty) return '缓存路网（点按重拉）';
    if (_roadError != null) return '路网：$_roadError（点按重拉）';
    return '路网加载中…（点按重拉）';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _Recording3dPainter(
            centerLat: widget.centerLat,
            centerLon: widget.centerLon,
            headingDeg: widget.headingDeg,
            points: widget.points,
            photoPoints: widget.photoPoints,
            roadWays: _roads,
            is3d: widget.is3d,
            headingUp: widget.headingUp,
            zoom: widget.zoom,
            accentColor: widget.accentColor,
            vehicleColor: widget.vehicleColor,
            vehicleMarkerPainter: widget.vehicleMarkerPainter,
          ),
        ),
      ),
      // 左上角：路网状态小字，点按可手动重拉；失败原因分档显示，
      // 不再只写“路网未加载”。缓存路网时注明“缓存路网”。
      Positioned(
        top: 12,
        left: 12,
        child: GestureDetector(
          onTap: _manualRefresh,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(6))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(_roadLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ),
          ),
        ),
      ),
      // 右上角控制：指南针 / 缩放 / 3D-2D 切换（回退开关）。
      Positioned(
        top: 12,
        right: 12,
        child: Column(children: [
          _ctlButton(
            onTap: widget.onCompassTap,
            child: Transform.rotate(
              angle: widget.headingUp ? -widget.headingDeg * math.pi / 180 : 0,
              child: const Icon(Icons.navigation, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onZoomChanged((widget.zoom + 1).clamp(12, 19)),
            child: const Icon(Icons.add, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onZoomChanged((widget.zoom - 1).clamp(12, 19)),
            child: const Icon(Icons.remove, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onModeChanged(!widget.is3d),
            child: Text(widget.is3d ? '3D' : '2D',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
      ),
      // 左下角：风格化声明小字。
      const Positioned(
        left: 12,
        bottom: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(6))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('风格化示意，非真实 3D 城市模型；路网来自 OpenStreetMap',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
          ),
        ),
      ),
    ]);
  }

  Widget _ctlButton({required VoidCallback onTap, required Widget child}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
  }
}

class _Proj {
  final Offset p;
  final double speedKmh;
  final double factor; // 透视缩放因子（2D 时为 1）
  const _Proj(this.p, this.speedKmh, this.factor);
}

class _Recording3dPainter extends CustomPainter {
  final double centerLat, centerLon, headingDeg, zoom;
  final List<Recording3dPoint> points;
  final List<PhotoPoint> photoPoints;
  final List<RoadWay> roadWays;
  final bool is3d, headingUp;
  final Color accentColor, vehicleColor;
  final CustomPainter? vehicleMarkerPainter;

  _Recording3dPainter({
    required this.centerLat,
    required this.centerLon,
    required this.headingDeg,
    required this.points,
    required this.photoPoints,
    this.roadWays = const [],
    required this.is3d,
    required this.headingUp,
    required this.zoom,
    required this.accentColor,
    required this.vehicleColor,
    this.vehicleMarkerPainter,
  });

  // 经纬度 -> 以中心为原点的东/北米制坐标，再按跟随模式转成
  // 前向（forward）/ 右向（right）米制坐标。
  (double, double) _toForwardRight(double lat, double lon) {
    final dx = (lon - centerLon) * math.cos(centerLat * math.pi / 180) * 111320;
    final dy = (lat - centerLat) * 110540;
    if (!headingUp) return (dy, dx);
    final h = headingDeg * math.pi / 180;
    final forward = dx * math.sin(h) + dy * math.cos(h);
    final right = dx * math.cos(h) - dy * math.sin(h);
    return (forward, right);
  }

  Offset _project(Size size, double forward, double right, double pxPerM) {
    if (!is3d) {
      return Offset(size.width / 2 + right * pxPerM, size.height / 2 - forward * pxPerM);
    }
    // 透视：相机高度约 140 米，地平线 16% 高、车标 72% 高；
    // factor = camH / (camH + 前向距离)，近大远小，远处收束到地平线。
    const camH = 140.0;
    final d = forward < -100 ? -100 : forward;
    final factor = camH / (camH + d);
    final horizonY = size.height * 0.16;
    final vehY = size.height * 0.72;
    return Offset(size.width / 2 + right * pxPerM * factor, horizonY + (vehY - horizonY) * factor);
  }

  double _factorFor(double forward) {
    if (!is3d) return 1;
    const camH = 140.0;
    final d = forward < -100 ? -100 : forward;
    return camH / (camH + d);
  }

  Color _speedColor(double kmh) {
    final t = (kmh / 120).clamp(0.0, 1.0);
    const stops = [
      (0.0, Color(0xFF22D3EE)),
      (0.33, Color(0xFF22C55E)),
      (0.66, Color(0xFFF59E0B)),
      (1.0, Color(0xFFEF4444)),
    ];
    for (var i = 0; i < stops.length - 1; i++) {
      final a = stops[i], b = stops[i + 1];
      if (t <= b.$1) {
        final f = (t - a.$1) / (b.$1 - a.$1);
        return Color.lerp(a.$2, b.$2, f)!;
      }
    }
    return stops.last.$2;
  }

  bool _sameSideOutside(Offset a, Offset b, Size size) {
    const m = 60.0;
    if (a.dx < -m && b.dx < -m) return true;
    if (a.dx > size.width + m && b.dx > size.width + m) return true;
    if (a.dy < -m && b.dy < -m) return true;
    if (a.dy > size.height + m && b.dy > size.height + m) return true;
    return false;
  }

  // 立体标记：底座光晕椭圆 + 阴影椭圆 + 竖杆 + 顶部圆点（不是平面贴图）。
  void _drawMarker(Canvas canvas, Offset p, Color color, double r) {
    final halo = Paint()..color = color.withValues(alpha: 0.25);
    canvas.drawOval(Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.7), width: r * 3.2, height: r * 1.2), halo);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset(p.dx + 2, p.dy + r * 0.9), width: r * 2.2, height: r * 0.8), shadow);
    final stem = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(p.dx, p.dy), Offset(p.dx, p.dy - r * 2.2), stem);
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(p.dx, p.dy - r * 2.2), r * 0.9, dot);
    canvas.drawCircle(Offset(p.dx, p.dy - r * 2.2), r * 0.4, Paint()..color = Colors.white);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // v1.0.4：深炭灰底（纯黑底除外项，与主框架 #121212 同步）。
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF121212));
    final zoomScale = math.pow(2, zoom - 16).toDouble();
    final pxPerM = (is3d ? size.width / 170 : size.width / 300) * zoomScale;

    // 远处地平线微光 + 风格化暗色光晕（固定屏幕位置的装饰，
    // 不是真实建筑；透视模式下只画在地平线附近）。
    if (is3d) {
      final horizonY = size.height * 0.16;
      final glow = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, accentColor.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, horizonY - 30, size.width, 60));
      canvas.drawRect(Rect.fromLTWH(0, horizonY - 30, size.width, 60), glow);
      for (var i = 0; i < 5; i++) {
        final cx = size.width * (0.12 + i * 0.19);
        final blob = Paint()..color = Colors.white.withValues(alpha: 0.03);
        canvas.drawCircle(Offset(cx, horizonY - 6), 26 + i * 4, blob);
      }
    }

    // 透视网格地面（风格化网格线，非路网）。
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    if (is3d) {
      for (final d in [0.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0]) {
        final y = _project(size, d, 0, pxPerM).dy;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      for (final r in [-200.0, -100.0, -50.0, 0.0, 50.0, 100.0, 200.0]) {
        final path = Path();
        var first = true;
        for (var d = 0.0; d <= 1000; d += 100) {
          final p = _project(size, d, r, pxPerM);
          if (first) {
            path.moveTo(p.dx, p.dy);
            first = false;
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, gridPaint);
      }
    } else {
      // 2D 俯视网格：每 100 米一条线（相对中心，不依赖任何瓦片）。
      for (var m = -400.0; m <= 400; m += 100) {
        canvas.drawLine(Offset(size.width / 2 + m * pxPerM, 0),
            Offset(size.width / 2 + m * pxPerM, size.height), gridPaint);
        canvas.drawLine(Offset(0, size.height / 2 - m * pxPerM),
            Offset(size.width, size.height / 2 - m * pxPerM), gridPaint);
      }
    }

    // v1.0.4 路网：暗灰细线 + 微弱发光（两遍：宽淡光晕 + 细主线），
    // 与亮红轨迹带区分（道路暗、轨迹亮）；无数据时本段自然不画。
    for (final way in roadWays) {
      final proj = <Offset>[];
      for (final (lat, lon) in way.points) {
        final fr = _toForwardRight(lat, lon);
        proj.add(_project(size, fr.$1, fr.$2, pxPerM));
      }
      for (var pass = 0; pass < 2; pass++) {
        final paint = Paint()
          ..color = pass == 0
              ? const Color(0xFF888888).withValues(alpha: 0.20)
              : const Color(0xFFB0B0B0).withValues(alpha: 0.85)
          ..strokeWidth = pass == 0 ? 7 : 2.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        final path = Path();
        var first = true;
        for (final p in proj) {
          if (first) {
            path.moveTo(p.dx, p.dy);
            first = false;
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }

    // 轨迹：先投影 + 按屏幕距离抽稀，再分段绘制（同侧出视野跳过）。
    final projected = <_Proj>[];
    for (final p in points) {
      final fr = _toForwardRight(p.lat, p.lon);
      projected.add(_Proj(_project(size, fr.$1, fr.$2, pxPerM), p.speedKmh, _factorFor(fr.$1)));
    }
    final kept = <_Proj>[];
    for (var i = 0; i < projected.length; i++) {
      final cur = projected[i];
      if (i == projected.length - 1 || kept.isEmpty || (cur.p - kept.last.p).distance >= 7) {
        kept.add(cur);
      }
    }
    // 发光底：先画一遍宽半透明（红色主色发光感），再画速度渐变色主线。
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 1; i < kept.length; i++) {
        final a = kept[i - 1], b = kept[i];
        if (_sameSideOutside(a.p, b.p, size)) continue;
        final w = pass == 0
            ? (16 * ((a.factor + b.factor) / 2)).clamp(3.0, 18.0).toDouble()
            : (9 * ((a.factor + b.factor) / 2)).clamp(1.5, 10.0).toDouble();
        final paint = Paint()
          ..color = pass == 0 ? Colors.red.withValues(alpha: 0.22) : _speedColor((a.speedKmh + b.speedKmh) / 2)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(a.p, b.p, paint);
      }
    }

    // 起点 / 照片点立体标记（终点即当前车标，不另画）。
    if (projected.isNotEmpty) _drawMarker(canvas, projected.first.p, Colors.greenAccent, 7);
    for (final pp in photoPoints) {
      final fr = _toForwardRight(pp.lat, pp.lon);
      final p = _project(size, fr.$1, fr.$2, pxPerM);
      if (p.dx < -20 || p.dx > size.width + 20 || p.dy < -20 || p.dy > size.height + 20) continue;
      _drawMarker(canvas, p, Colors.amber, 6);
    }

    // 场景中心车标：阴影 + 朝向锥 + 车体（朝向跟随 headingDeg；
    // headingUp 时场景已旋转故车标恒朝上，否则按朝向旋转）。
    final veh = is3d ? Offset(size.width / 2, size.height * 0.72) : Offset(size.width / 2, size.height / 2);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset(veh.dx + 3, veh.dy + 12), width: 44, height: 16), shadow);
    canvas.save();
    canvas.translate(veh.dx, veh.dy);
    canvas.rotate(headingUp ? 0 : headingDeg * math.pi / 180);
    final cone = Path()
      ..moveTo(-13, 6)
      ..lineTo(0, -52)
      ..lineTo(13, 6)
      ..close();
    canvas.drawPath(cone, Paint()..color = accentColor.withValues(alpha: 0.25));
    // v1.0.2：新 3D 车标（画笔版，外层已旋转故画笔朝向为 0）。
    if (vehicleMarkerPainter != null) {
      canvas.save();
      canvas.translate(-28, -28);
      vehicleMarkerPainter!.paint(canvas, const Size(56, 56));
      canvas.restore();
    } else {
      final body = Path()
        ..moveTo(0, -20)
        ..lineTo(12, 12)
        ..lineTo(6, 18)
        ..lineTo(-6, 18)
        ..lineTo(-12, 12)
        ..close();
      canvas.drawPath(body, Paint()..color = vehicleColor);
      canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Recording3dPainter old) =>
      old.centerLat != centerLat ||
      old.centerLon != centerLon ||
      old.headingDeg != headingDeg ||
      old.roadWays != roadWays ||
      old.points != points ||
      old.photoPoints != photoPoints ||
      old.is3d != is3d ||
      old.headingUp != headingUp ||
      old.vehicleMarkerPainter != vehicleMarkerPainter ||
      old.zoom != zoom;
}
