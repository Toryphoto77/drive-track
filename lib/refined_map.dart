import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 精细化地图（v0.1.3 分工：地图 UI 精细化）。
///
/// 底图逻辑照搬现有 DarkTileMap（lib/widgets.dart），不重写坐标系：
/// - 默认高德栅格 webrd0X.is.autonavi.com，style=8（影像路网）→
///   备用 OSM → 备用 CARTO dark_all，整幅以源为单位切换，不逐张混源；
/// - 高德源用 GCJ-02：WGS-84 的 GPS 点 / 中心统一转 GCJ-02 再算瓦片
///   与画轨迹，切到 OSM / CARTO 时用回原始 WGS-84；
/// - 失败瓦片一律画深色占位，绝不贴错误码图；单源连续失败 ≥4 张
///   才整幅切源；全部瓦片失败时出深色占位 + 重试按钮。
///
/// 高德深色风格结论（已查代码与公开瓦片文档）：
/// appmaptile 的 style 参数只有 6=卫星影像、7=矢量路网、8=影像路网，
/// 没有“深色风格”选项；官方深色要走 JS API / SDK 的自定义样式，
/// 栅格瓦片参数给不出来。本文件因此保留 style=8 的浅色路网，
/// 不硬说已深色；深色感由黑色毛玻璃控件、信息条、角标与深色
/// 占位提供，CARTO 备用源本身是 dark_all 深色。
/// 朝向优先（headingUp）时整层渲染图层做视觉旋转，不是瓦片重投影，
/// 旋转后四角用多算一圈瓦片补齐，比例尺仍按北向上近似值算。
///
/// API 全部走构造函数参数，不引用 main.dart 的任何类。

enum RefinedTileSource { amap, osm, carto }

extension RefinedTileSourceLabel on RefinedTileSource {
  String get label => switch (this) {
        RefinedTileSource.amap => '高德',
        RefinedTileSource.osm => 'OSM',
        RefinedTileSource.carto => 'CARTO',
      };
  String get attribution => switch (this) {
        RefinedTileSource.amap => '© 高德地图 · 轨迹已按 GCJ-02 对齐',
        RefinedTileSource.osm => '© OpenStreetMap contributors',
        RefinedTileSource.carto => '© OpenStreetMap contributors © CARTO',
      };
}

String _refinedTileUrl(RefinedTileSource src, int z, int x, int y) {
  switch (src) {
    case RefinedTileSource.amap:
      final host = 'webrd0${(x + y) % 4 + 1}.is.autonavi.com';
      return 'https://$host/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=$x&y=$y&z=$z';
    case RefinedTileSource.osm:
      return 'https://tile.openstreetmap.org/$z/$x/$y.png';
    case RefinedTileSource.carto:
      return 'https://basemaps.cartocdn.com/dark_all/$z/$x/$y.png';
  }
}

// ---------- Web Mercator + WGS-84 → GCJ-02（照搬 widgets.dart 算法） ----------

double _mercY(double lat) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
}

Offset _latLonToScreen(double lat, double lon, double cLat, double cLon, double zoom, Size size) {
  final scale = 256 * math.pow(2, zoom);
  final wx = (lon + 180) / 360 * scale;
  final wy = _mercY(lat) * scale;
  final cx = (cLon + 180) / 360 * scale;
  final cy = _mercY(cLat) * scale;
  return Offset(wx - cx + size.width / 2, wy - cy + size.height / 2);
}

({double lat, double lon}) _wgsToGcj(double lat, double lon) {
  if (lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271) {
    return (lat: lat, lon: lon);
  }
  double transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(y / 12.0 * math.pi) + 300.0 * math.sin(y / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  const a = 6378245.0, ee = 0.00669342162296594323;
  final dLat = transformLat(lon - 105.0, lat - 35.0);
  final dLon = transformLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final mgLat = lat + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final mgLon = lon + (dLon * 180.0) / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (lat: mgLat, lon: mgLon);
}

/// 轨迹点（自带最小字段，不依赖 main.dart / models.dart 的 TrackPoint）。
class RefinedTrackPoint {
  final double lat;
  final double lon;

  /// 时速 km/h，用于轨迹按速度渐变色；未知时传 0。
  final double speedKmh;
  /// 推算点（隧道补段）：画虚线 + 灰/琥珀色，不进速度渐变色。
  final bool estimated;
  const RefinedTrackPoint(
      {required this.lat, required this.lon, this.speedKmh = 0, this.estimated = false});
}

class RefinedMap extends StatefulWidget {
  final double centerLat;
  final double centerLon;

  /// 方向角（度，0=北，顺时针），用于车辆标记朝向与指北针。
  final double headingDeg;

  /// 定位精度（米），用于精度圆半径；<=0 或过大时不画精度圆。
  final double accuracyMeters;
  final double zoom;
  final List<RefinedTrackPoint> points;

  /// 跟随模式：为 true 且中心点变化时相机做 600ms 平滑动画跟随。
  final bool follow;

  /// 朝向优先：为 true 时渲染层随方向角视觉旋转，指北针同步转。
  final bool headingUp;
  final RefinedTileSource source;
  final double height;

  /// 当前时速 km/h；为 null 时取轨迹最后一点的速度。
  final double? currentSpeedKmh;
  final Color accentColor;

  /// v0.1.4 地图车标：0 轿车 / 1 跑车 / 2 摩托 / 3 自行车（自绘矢量轮廓）。
  final int vehicleMarkerKind;
  final Color? vehicleMarkerColor;
  // v1.0.2：新 3D 车标画笔（调用方用 markerPainterFor 传入，headingDeg=0，
  // 画布已按航向旋转）；为空时回落旧 kind 绘制。
  final CustomPainter? vehicleMarkerPainter;

  final ValueChanged<RefinedTileSource>? onSourceChanged;
  final ValueChanged<double>? onZoomChanged;
  final VoidCallback? onRecenter;
  final VoidCallback? onRetry;

  /// 指北针点击：调用方一般用它关掉朝向优先（回到北向上）。
  final VoidCallback? onCompassTap;

  const RefinedMap({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.headingDeg,
    this.accuracyMeters = 0,
    required this.zoom,
    required this.points,
    this.follow = true,
    this.headingUp = true,
    this.source = RefinedTileSource.amap,
    required this.height,
    this.currentSpeedKmh,
    this.accentColor = const Color(0xFFE10600),
    this.vehicleMarkerKind = 0,
    this.vehicleMarkerColor,
    this.vehicleMarkerPainter,
    this.onSourceChanged,
    this.onZoomChanged,
    this.onRecenter,
    this.onRetry,
    this.onCompassTap,
  });

  @override
  State<RefinedMap> createState() => _RefinedMapState();
}

class _RefinedMapState extends State<RefinedMap> with TickerProviderStateMixin {
  late final AnimationController _camera =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  double _fromLat = 0, _fromLon = 0, _toLat = 0, _toLon = 0;
  bool _cameraInit = false;
  RefinedTileSource? _sourceOverride;
  int _generation = 0;
  int _retryKey = 0;
  final Set<String> _failedKeys = {};
  int _tileTotal = 0;

  @override
  void dispose() {
    _camera.dispose();
    _pulse.dispose();
    super.dispose();
  }

  RefinedTileSource get _effectiveSource => _sourceOverride ?? widget.source;

  @override
  void didUpdateWidget(covariant RefinedMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) {
      _sourceOverride = null;
      _resetFailures();
    }
    if (widget.follow &&
        (widget.centerLat != oldWidget.centerLat || widget.centerLon != oldWidget.centerLon)) {
      _fromLat = _toLat;
      _fromLon = _toLon;
      _toLat = widget.centerLat;
      _toLon = widget.centerLon;
      _camera.forward(from: 0);
    }
  }

  void _resetFailures() {
    _generation++;
    _failedKeys.clear();
    _tileTotal = 0;
  }

  void _reportFailure(String key) {
    final gen = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _generation) return;
      if (_failedKeys.add(key)) {
        setState(() {});
        // 单源连续失败 ≥4 张才整幅切源，避免单张缺失就乱跳。
        if (_failedKeys.length >= 4) {
          final cur = _effectiveSource;
          if (cur != RefinedTileSource.carto) {
            final next = RefinedTileSource.values[cur.index + 1];
            if (widget.onSourceChanged != null) {
              widget.onSourceChanged!(next);
            } else {
              setState(() => _sourceOverride = next);
            }
            _resetFailures();
          }
        }
      }
    });
  }

  void _cycleSource() {
    final cur = _effectiveSource;
    final next = RefinedTileSource.values[(cur.index + 1) % RefinedTileSource.values.length];
    if (widget.onSourceChanged != null) {
      widget.onSourceChanged!(next);
    } else {
      setState(() => _sourceOverride = next);
    }
    _resetFailures();
  }

  void _retry() {
    setState(() {
      _retryKey++;
      _resetFailures();
    });
    widget.onRetry?.call();
  }

  void _zoom(double delta) {
    final z = (widget.zoom + delta).clamp(3.0, 19.0);
    widget.onZoomChanged?.call(z);
  }

  /// 比例尺：取 100px 对应的米数，凑整到 50 / 100 / 200 / 500 / 1000…。
  ({String label, double widthPx}) _scaleBar(double lat) {
    final mpp = 156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, widget.zoom);
    final target = mpp * 100;
    const nice = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0];
    var chosen = nice.last;
    for (final n in nice) {
      if (n >= target) {
        chosen = n;
        break;
      }
    }
    final label = chosen >= 1000 ? '${(chosen / 1000).toStringAsFixed(chosen % 1000 == 0 ? 0 : 1)} km' : '${chosen.toInt()} m';
    return (label: label, widthPx: (chosen / mpp).clamp(24.0, 160.0));
  }

  Widget _glass({required Widget child, double radius = 999, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Widget _roundControl({required IconData icon, required VoidCallback? onTap, String? tooltip}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          // 长按不弹文本：不用 Tooltip，语义标签只给读屏。
          child: Semantics(label: tooltip, child: Icon(icon, size: 20, color: Colors.white)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraInit) {
      _cameraInit = true;
      _toLat = widget.centerLat;
      _toLon = widget.centerLon;
      _fromLat = widget.centerLat;
      _fromLon = widget.centerLon;
    }
    final headingRad = widget.headingDeg * math.pi / 180;
    final rotate = widget.headingUp ? -headingRad : 0.0;
    final speed = widget.currentSpeedKmh ?? (widget.points.isEmpty ? 0 : widget.points.last.speedKmh);
    final scale = _scaleBar(widget.centerLat);
    final allFailed = _tileTotal > 0 && _failedKeys.length >= _tileTotal;

    return LayoutBuilder(builder: (context, constraints) {
      final effHeight = widget.height.isFinite
          ? widget.height
          : (constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0);
      return Container(
        height: effHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AnimatedBuilder(
            animation: Listenable.merge([_camera, _pulse]),
            builder: (context, _) {
              final t = _camera.isAnimating || _camera.value > 0
                  ? Curves.easeOutCubic.transform(_camera.value)
                  : 1.0;
              final dispLat = _fromLat + (_toLat - _fromLat) * t;
              final dispLon = _fromLon + (_toLon - _fromLon) * t;
              final useGcj = _effectiveSource == RefinedTileSource.amap;
              final c = useGcj ? _wgsToGcj(dispLat, dispLon) : (lat: dispLat, lon: dispLon);
              final dispPoints = useGcj
                  ? widget.points.map((p) {
                      final g = _wgsToGcj(p.lat, p.lon);
                      return RefinedTrackPoint(lat: g.lat, lon: g.lon, speedKmh: p.speedKmh);
                    }).toList()
                  : widget.points;
              final size = Size(constraints.maxWidth, effHeight - 28);
              final mapScale = 256 * math.pow(2, widget.zoom);
              final cx = (c.lon + 180) / 360 * mapScale;
              final cy = _mercY(c.lat) * mapScale;
              // 朝向优先旋转时多算一圈瓦片，补旋转后露出的四角。
              final pad = widget.headingUp ? 1 : 0;
              final tx0 = ((cx - size.width / 2) / 256).floor() - pad;
              final tx1 = ((cx + size.width / 2) / 256).ceil() + pad;
              final ty0 = ((cy - size.height / 2) / 256).floor() - pad;
              final ty1 = ((cy + size.height / 2) / 256).ceil() + pad;
              final tiles = <Widget>[];
              var total = 0;
              for (var x = tx0; x <= tx1; x++) {
                for (var y = ty0; y <= ty1; y++) {
                  total++;
                  final key = '$_effectiveSource-$_retryKey-$x-$y';
                  final left = x * 256 - (cx - size.width / 2);
                  final top = y * 256 - (cy - size.height / 2);
                  tiles.add(Positioned(
                    left: left,
                    top: top,
                    width: 256,
                    height: 256,
                    child: Image.network(
                      _refinedTileUrl(_effectiveSource, widget.zoom.toInt(), x, y),
                      key: ValueKey(key),
                      headers: const {'User-Agent': 'DriveTrack/0.1.3'},
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) {
                        _reportFailure(key);
                        return Container(color: const Color(0xFF0A0F1E));
                      },
                    ),
                  ));
                }
              }
              // 总瓦片数只在变化时更新，避免 build 内 setState。
              if (total != _tileTotal) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && total != _tileTotal) setState(() => _tileTotal = total);
                });
              }
              final mpp = 156543.03392 * math.cos(dispLat * math.pi / 180) / math.pow(2, widget.zoom);
              final accuracyPx = widget.accuracyMeters > 0
                  ? (widget.accuracyMeters / mpp).clamp(8.0, 140.0)
                  : 0.0;
              return Stack(children: [
                // 瓦片 + 轨迹层（朝向优先时整体视觉旋转）。
                Transform.rotate(
                  angle: rotate,
                  alignment: Alignment.center,
                  child: Stack(children: [
                    ...tiles,
                    CustomPaint(
                      size: size,
                      painter: _RefinedTrackPainter(
                        points: dispPoints,
                        centerLat: c.lat,
                        centerLon: c.lon,
                        zoom: widget.zoom,
                        headingRad: headingRad,
                        accuracyPx: accuracyPx,
                        pulse: _pulse.value,
                        accent: widget.accentColor,
                        markerKind: widget.vehicleMarkerKind,
                        markerColor: widget.vehicleMarkerColor ?? widget.accentColor,
                        vehicleMarkerPainter: widget.vehicleMarkerPainter,
                      ),
                    ),
                  ]),
                ),
                // 左上：底图源切换入口（毛玻璃药丸）。
                Positioned(
                  left: 12,
                  top: 12,
                  child: GestureDetector(
                    onTap: _cycleSource,
                    child: _glass(
                      child: Text('${_effectiveSource.label} · 切换底图',
                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ),
                // 右上：指北针（随朝向转，点击回调由调用方接管，如回到北向上）。
                Positioned(
                  right: 12,
                  top: 12,
                  child: GestureDetector(
                    onTap: widget.onCompassTap,
                    child: _glass(
                      radius: 999,
                      padding: const EdgeInsets.all(8),
                      child: Transform.rotate(
                        angle: rotate,
                        child: const Text('N', style: TextStyle(color: Color(0xFFE10600), fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
                // 跟随暂停提示（毛玻璃药丸，点按回到当前位置）。
                if (!widget.follow)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: Center(
                      child: GestureDetector(
                        onTap: widget.onRecenter,
                        child: _glass(child: const Text('跟随已暂停 · 点按回到当前位置', style: TextStyle(color: Colors.white, fontSize: 11))),
                      ),
                    ),
                  ),
                // 右侧：缩放 +/- 与回到当前位置（毛玻璃圆钮）。
                Positioned(
                  right: 12,
                  top: 72,
                  child: Column(children: [
                    _roundControl(icon: Icons.add, onTap: () => _zoom(1), tooltip: '放大'),
                    const SizedBox(height: 8),
                    _roundControl(icon: Icons.remove, onTap: () => _zoom(-1), tooltip: '缩小'),
                    const SizedBox(height: 8),
                    _roundControl(icon: Icons.my_location, onTap: widget.onRecenter, tooltip: '回到当前位置'),
                  ]),
                ),
                // 左下：比例尺（毛玻璃药丸）。
                Positioned(
                  left: 12,
                  bottom: 40,
                  child: _glass(
                    radius: 8,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(scale.label, style: const TextStyle(color: Colors.white, fontSize: 11)),
                      const SizedBox(height: 2),
                      Container(
                        width: scale.widthPx,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.black54),
                        ),
                      ),
                    ]),
                  ),
                ),
                // 底部信息条（黑底毛玻璃，绝无白色大块）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${_effectiveSource.label} · ${_effectiveSource.attribution} · ${speed.toStringAsFixed(0)} km/h'
                          '${widget.accuracyMeters > 0 ? ' · 精度 ${widget.accuracyMeters.toStringAsFixed(0)} m' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _cycleSource,
                        child: const Text('切换底图源', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ]),
                  ),
                ),
                // 全部瓦片失败：深色占位 + 重试（绝不贴错误码图）。
                if (allFailed)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0A0F1E),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.map_outlined, color: Colors.white38, size: 32),
                          const SizedBox(height: 8),
                          const Text('地图加载失败', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _retry,
                            child: _glass(
                              child: Text('重试', style: TextStyle(color: widget.accentColor, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      );
    });
  }
}

Color _speedColor(double speed, double maxSpeed) {
  const slow = Color(0xFF22C55E);
  const mid = Color(0xFFEAB308);
  const fast = Color(0xFFE10600);
  final t = maxSpeed <= 0 ? 0.0 : (speed / maxSpeed).clamp(0.0, 1.0);
  if (t < 0.5) return Color.lerp(slow, mid, t * 2)!;
  return Color.lerp(mid, fast, (t - 0.5) * 2)!;
}

/// 推算段虚线：8px 实线 + 6px 间隔。
void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
  final total = (b - a).distance;
  if (total <= 0) return;
  const dash = 8.0, gap = 6.0;
  final dir = (b - a) / total;
  var d = 0.0;
  while (d < total) {
    final end = math.min(d + dash, total);
    canvas.drawLine(a + dir * d, a + dir * end, paint);
    d = end + gap;
  }
}

class _RefinedTrackPainter extends CustomPainter {
  final List<RefinedTrackPoint> points;
  final double centerLat, centerLon, zoom, headingRad, accuracyPx, pulse;
  final Color accent;
  final int markerKind;
  final Color markerColor;
  final CustomPainter? vehicleMarkerPainter;
  _RefinedTrackPainter({
    required this.points,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.headingRad,
    required this.accuracyPx,
    required this.pulse,
    required this.accent,
    this.markerKind = 0,
    required this.markerColor,
    this.vehicleMarkerPainter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final pts = points.map((p) => _latLonToScreen(p.lat, p.lon, centerLat, centerLon, zoom, size)).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    // 轨迹辉光：宽层低透明 + 中层。
    for (final glow in [(12.0, 0.18), (7.0, 0.30)]) {
      canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: glow.$2)
            ..strokeWidth = glow.$1
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke);
    }
    // 按速度渐变色：逐段着色，慢绿 → 中黄 → 快红。
    // 推算段不进速度渐变色：画琥珀虚线（任一端是推算点即算推算段）。
    final maxSpeed = points.fold(0.0, (a, p) => math.max(a, p.speedKmh));
    if (pts.length > 1) {
      for (var i = 1; i < pts.length; i++) {
        final isEstimated = points[i].estimated || points[i - 1].estimated;
        if (isEstimated) {
          _drawDashedLine(
            canvas,
            pts[i - 1],
            pts[i],
            Paint()
              ..color = const Color(0xFFFFB300)
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round,
          );
          continue;
        }
        final segSpeed = math.max(points[i - 1].speedKmh, points[i].speedKmh);
        canvas.drawLine(
            pts[i - 1],
            pts[i],
            Paint()
              ..color = _speedColor(segSpeed, maxSpeed)
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round);
      }
    }
    // 起点（白环）/ 终点（红实心）图钉。
    void pin(Offset at, Color fill, Color ring) {
      canvas.drawCircle(at, 10, Paint()..color = ring);
      canvas.drawCircle(at, 7, Paint()..color = fill);
      canvas.drawCircle(at, 3, Paint()..color = Colors.white);
    }

    pin(pts.first, Colors.white, Colors.black54);
    if (pts.length > 1) pin(pts.last, accent, Colors.white);
    // 车辆标记：精度圆（半透明 + 脉动外圈）+ 朝向光锥 + 车点。
    final cur = pts.last;
    if (accuracyPx > 0) {
      canvas.drawCircle(cur, accuracyPx, Paint()..color = accent.withValues(alpha: 0.12));
      canvas.drawCircle(
          cur,
          accuracyPx * (0.85 + 0.35 * pulse),
          Paint()
            ..color = accent.withValues(alpha: (1 - pulse) * 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    final cone = Path()
      ..moveTo(cur.dx, cur.dy)
      ..lineTo(cur.dx + math.sin(headingRad - 0.45) * 34, cur.dy - math.cos(headingRad - 0.45) * 34)
      ..lineTo(cur.dx + math.sin(headingRad) * 48, cur.dy - math.cos(headingRad) * 48)
      ..lineTo(cur.dx + math.sin(headingRad + 0.45) * 34, cur.dy - math.cos(headingRad + 0.45) * 34)
      ..close();
    canvas.drawPath(cone, Paint()..color = accent.withValues(alpha: 0.25));
    // v0.1.4 车标：按选择自绘矢量轮廓（前向为 -y，见 headingRad 定义）。
    canvas.save();
    canvas.translate(cur.dx, cur.dy);
    canvas.rotate(headingRad);
    // v1.0.2：新 3D 车标优先（画笔版，画布已旋转故画笔朝向为 0）。
    if (vehicleMarkerPainter != null) {
      canvas.save();
      canvas.translate(-20, -20);
      vehicleMarkerPainter!.paint(canvas, const Size(40, 40));
      canvas.restore();
      canvas.restore();
      return;
    }
    final body = Paint()..color = markerColor;
    final dark = Paint()..color = const Color(0xFF111111);
    final white = Paint()..color = Colors.white;
    if (markerKind == 2) {
      // 摩托：双轮 + 整流罩仿赛轮廓
      canvas.drawCircle(const Offset(0, -11), 5, dark);
      canvas.drawCircle(const Offset(0, 11), 5, dark);
      final fairing = Path()..moveTo(-6, 12)..lineTo(6, 12)..lineTo(0, -16)..close();
      canvas.drawPath(fairing, body);
      canvas.drawCircle(const Offset(0, -2), 3, white);
    } else if (markerKind == 3) {
      // 自行车：双轮 + 车架三角
      canvas.drawCircle(const Offset(0, -11), 6, Paint()..color = const Color(0xFF111111)..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawCircle(const Offset(0, 11), 6, Paint()..color = const Color(0xFF111111)..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawLine(const Offset(0, -11), const Offset(0, 11), body..strokeWidth = 2);
      canvas.drawLine(const Offset(0, -11), const Offset(5, 2), body..strokeWidth = 2);
      canvas.drawLine(const Offset(0, 11), const Offset(5, 2), body..strokeWidth = 2);
    } else {
      // 轿车 / 跑车：低趴车身，跑车加尾翼
      final r = markerKind == 1 ? 5.0 : 7.0;
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-9, -15, 18, 30), Radius.circular(r)), body);
      canvas.drawRect(const Rect.fromLTWH(-6, -6, 12, 8), Paint()..color = const Color(0xFF0B1226));
      if (markerKind == 1) canvas.drawRect(const Rect.fromLTWH(-11, 13, 22, 3), body);
      canvas.drawCircle(const Offset(0, 0), 3, white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RefinedTrackPainter old) => true;
}
