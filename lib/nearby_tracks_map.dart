/// 附近赛道地图：深色底图 + 赛道/卡丁车标记 + 当前位置。
///
/// 设计口径：
/// - 底图只用 CARTO dark_all 瓦片（WGS-84，与 OSM 赛道包坐标同源，
///   无需 GCJ-02 纠偏；国内道路会相对高德有偏移，但赛道位置不受影响）。
/// - 坐标换算复用 slippy-map Web Mercator，与 refined_map.dart 一致。
/// - 标记为白色胶囊 + 灰色编号圆 + 蓝色指地针，点击回调给调用方。
/// - 手势：单指拖动、双指缩放；右下角回到当前位置按钮。
/// - 失败瓦片画深色占位，不贴错误图；不自动切源（仅一个深色源）。
///
/// 本文件不引用 main.dart，可独立测试。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'track_library.dart';
import 'track_timing.dart';

/// 地图上的一个赛道 POI。
class TrackPoi {
  final String id;
  final String name;
  final double lat;
  final double lon;

  /// 是否卡丁车赛道（决定标记编号来源）。
  final bool isKart;

  const TrackPoi({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.isKart,
  });

  static TrackPoi? fromPackage(TrackPackage p) {
    final pt = p.start ?? (p.centerline.isNotEmpty ? GeoPoint(
      p.centerline.first.lat, p.centerline.first.lon) : null);
    if (pt == null) return null;
    return TrackPoi(
      id: p.id,
      name: p.nameCn,
      lat: pt.lat,
      lon: pt.lon,
      isKart: p.id.startsWith('kart_'),
    );
  }
}

double _mercY(double lat) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
}

double _tileX(double lon, int z) => (lon + 180) / 360 * math.pow(2, z);
double _tileY(double lat, int z) => _mercY(lat) * math.pow(2, z);

const _minZoom = 2.0;
const _maxZoom = 18.0;

class NearbyTracksMap extends StatefulWidget {
  final List<TrackPoi> pois;
  final GeoPoint? currentLocation;
  final ValueChanged<TrackPoi>? onPoiTap;
  final Color accentColor;

  const NearbyTracksMap({
    super.key,
    this.pois = const [],
    this.currentLocation,
    this.onPoiTap,
    this.accentColor = const Color(0xFF2563EB),
  });

  @override
  State<NearbyTracksMap> createState() => _NearbyTracksMapState();
}

class _NearbyTracksMapState extends State<NearbyTracksMap>
    with TickerProviderStateMixin {
  double _lat = 30.0;
  double _lon = 120.0;
  double _zoom = 10.0;
  late final AnimationController _pulse;
  bool _locInit = false;

  Size _size = Size.zero;
  Offset _lastFocal = Offset.zero;
  double _lastZoom = 10.0;
  double _worldFocalX = 0;
  double _worldFocalY = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    final loc = widget.currentLocation;
    if (loc != null) {
      _lat = loc.lat;
      _lon = loc.lon;
      _locInit = true;
    }
  }

  @override
  void didUpdateWidget(covariant NearbyTracksMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loc = widget.currentLocation;
    if (loc != null && (!_locInit || oldWidget.currentLocation == null)) {
      _lat = loc.lat;
      _lon = loc.lon;
      _locInit = true;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _toScreen(double lat, double lon, Size size) {
    final scale = 256 * math.pow(2, _zoom);
    final wx = (lon + 180) / 360 * scale;
    final wy = _mercY(lat) * scale;
    final cx = (_lon + 180) / 360 * scale;
    final cy = _mercY(_lat) * scale;
    return Offset(wx - cx + size.width / 2, wy - cy + size.height / 2);
  }

  void _recenter() {
    final loc = widget.currentLocation;
    if (loc != null) {
      setState(() {
        _lat = loc.lat;
        _lon = loc.lon;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _lastZoom = _zoom;
    final scale = 256 * math.pow(2, _zoom);
    final cx = (_lon + 180) / 360 * scale;
    final cy = _mercY(_lat) * scale;
    _worldFocalX = cx + d.localFocalPoint.dx - _size.width / 2;
    _worldFocalY = cy + d.localFocalPoint.dy - _size.height / 2;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newZoom = (_lastZoom * d.scale).clamp(_minZoom, _maxZoom);
    final scale = 256 * math.pow(2, newZoom);
    // 让缩放下的世界点仍落在手指焦点上
    final cx = _worldFocalX - d.localFocalPoint.dx + _size.width / 2;
    final cy = _worldFocalY - d.localFocalPoint.dy + _size.height / 2;
    final newLon = cx / scale * 360 - 180;
    // inverse mercator
    final n = math.pi * (1 - 2 * cy / scale);
    final newLat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    setState(() {
      _zoom = newZoom;
      _lon = newLon.clamp(-179.0, 179.0);
      _lat = newLat.clamp(-85.0, 85.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      _size = size;
      final pois = widget.pois;
      // 按距离当前位置排序，远的先画（近的压在上面），编号 1 起。
      final loc = widget.currentLocation;
      final sorted = [...pois]
        ..sort((a, b) {
          if (loc == null) return 0;
          final da = (a.lat - loc.lat) * (a.lat - loc.lat) +
              (a.lon - loc.lon) * (a.lon - loc.lon);
          final db = (b.lat - loc.lat) * (b.lat - loc.lat) +
              (b.lon - loc.lon) * (b.lon - loc.lon);
          return da.compareTo(db);
        });

      return Stack(
        children: [
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Stack(
              children: [
                _tileLayer(size),
                for (var i = 0; i < sorted.length; i++)
                  _poiMarker(sorted[i], i + 1, size),
                if (loc != null) _currentLocation(loc, size),
              ],
            ),
          ),
          // 回到当前位置按钮（不参与手势）
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              backgroundColor: const Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      );
    });
  }

  Widget _tileLayer(Size size) {
    final z = _zoom.floor().clamp(2, 18);
    final scale = 256 * math.pow(2, z);
    final cx = (_lon + 180) / 360 * scale;
    final cy = _mercY(_lat) * scale;
    final x0 = ((cx - size.width / 2) / 256).floor() - 1;
    final x1 = ((cx + size.width / 2) / 256).ceil() + 1;
    final y0 = ((cy - size.height / 2) / 256).floor() - 1;
    final y1 = ((cy + size.height / 2) / 256).ceil() + 1;
    final n = 1 << z;

    final tiles = <Widget>[];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final tx = x % n;
        final ty = y % n;
        if (tx < 0 || ty < 0 || ty >= n) continue;
        final left = (x * 256 - cx) + size.width / 2;
        final top = (y * 256 - cy) + size.height / 2;
        tiles.add(Positioned(
          left: left,
          top: top,
          width: 256,
          height: 256,
          child: _Tile(z: z, x: tx, y: ty),
        ));
      }
    }
    return Container(
      width: size.width,
      height: size.height,
      color: const Color(0xFF0E0E10),
      child: Stack(children: tiles),
    );
  }

  Widget _poiMarker(TrackPoi poi, int index, Size size) {
    final pos = _toScreen(poi.lat, poi.lon, size);
    if (pos.dx < -200 || pos.dx > size.width + 200 ||
        pos.dy < -200 || pos.dy > size.height + 200) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Transform.translate(
        offset: const Offset(0, -44),
        child: GestureDetector(
          onTap: () => widget.onPoiTap?.call(poi),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE5E7EB),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$index',
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        poi.name,
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // 蓝色指地针
              CustomPaint(
                size: const Size(10, 14),
                painter: _NeedlePainter(color: widget.accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _currentLocation(GeoPoint loc, Size size) {
    final pos = _toScreen(loc.lat, loc.lon, size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Transform.translate(
        offset: const Offset(-14, -14),
        child: SizedBox(
          width: 28,
          height: 28,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = _pulse.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 28 + t * 40,
                    height: 28 + t * 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18 * (1 - t)),
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black38, blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final int z, x, y;
  const _Tile({required this.z, required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    final url =
        'https://basemaps.cartocdn.com/dark_all/$z/$x/$y.png';
    return Image.network(
      url,
      fit: BoxFit.fill,
      errorBuilder: (_, __, ___) => Container(color: const Color(0xFF121214)),
      gaplessPlayback: true,
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final Color color;
  const _NeedlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter old) => old.color != color;
}
