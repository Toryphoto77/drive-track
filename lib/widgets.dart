import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'models.dart';
import 'recorder.dart';
import 'sport_moto_paths.dart';

// ---------- Web Mercator ----------
double _mercY(double lat) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
}

Offset latLonToScreen(double lat, double lon, double cLat, double cLon, double zoom, Size size) {
  final scale = 256 * math.pow(2, zoom);
  final wx = (lon + 180) / 360 * scale;
  final wy = _mercY(lat) * scale;
  final cx = (cLon + 180) / 360 * scale;
  final cy = _mercY(cLat) * scale;
  return Offset(wx - cx + size.width / 2, wy - cy + size.height / 2);
}

// ---------- 瓦片底图（v0.1.2 多源 fallback） ----------
//
// v0.1.1 根因（已用 curl 与 Dart 实测确认）：
//  ① 唯一源 basemaps.cartocdn.com/dark_all，Image.network 无 User-Agent、
//     无重试、无备用源；国内网络下该域名常不可达/缓慢，整幅地图只剩深色底。
//     沙箱 curl 测得该源模板本身语法无误（z/x/y 顺序正确，上海 z16 瓦片
//     返回 200），所以不是模板错，而是“单源 + 无 fallback”在国内不可用。
//  ② 录制页把 height=double.infinity 传进来，瓦片范围计算里
//     (-inf).floor() 在 Dart 抛 "Infinity or NaN toInt"，录制页地图根本
//     无法建成——这是“地图未调起”的另一半根因，本版一并修掉（无限高时
//     改用 LayoutBuilder 的实际约束高度）。
//  ③ 旧 errorBuilder 只给深色块，不区分“源挂了”与“单张瓦片缺失”，
//     也不会切源，用户看到的就是一堆深色/空白贴图。
//
// 本版：默认高德栅格瓦片（webrd0X.is.autonavi.com，无需个人 key，国内
// 可达；沙箱实测上海 z16 瓦片 200 / 21835 字节）→ 备用 OSM
// （tile.openstreetmap.org，WGS-84）→ 备用 CARTO dark_all。整幅地图
// 以源为单位切换（不逐张混源，避免坐标系混用）；高德源使用 GCJ-02，
// 本文件把 WGS-84 的 GPS 点/中心统一转 GCJ-02 再算瓦片与画轨迹，
// 切到 OSM/CARTO 时用回原始 WGS-84。失败瓦片一律画深色占位，
// 绝不把带错误码/错误文案的图片贴到地图上；底部有源名 + 手动切源。
enum TileSource { amap, osm, carto }

String _tileUrl(TileSource src, int z, int x, int y) {
  switch (src) {
    case TileSource.amap:
      final host = 'webrd0${(x + y) % 4 + 1}.is.autonavi.com';
      return 'https://$host/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x=$x&y=$y&z=$z';
    case TileSource.osm:
      return 'https://tile.openstreetmap.org/$z/$x/$y.png';
    case TileSource.carto:
      return 'https://basemaps.cartocdn.com/dark_all/$z/$x/$y.png';
  }
}

String _tileAttribution(TileSource src) => switch (src) {
      TileSource.amap => '© 高德地图 · 轨迹已按 GCJ-02 对齐',
      TileSource.osm => '© OpenStreetMap contributors',
      TileSource.carto => '© OpenStreetMap contributors © CARTO',
    };

// WGS-84 → GCJ-02（标准偏移算法；境外返回原值）。
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

class DarkTileMap extends StatefulWidget {
  final List<TrackPoint> points;
  final double centerLat, centerLon, heading;
  final double zoom;
  final int highlightIndex;
  final double height;
  final Color trackColor;
  const DarkTileMap({
    super.key,
    required this.points,
    required this.centerLat,
    required this.centerLon,
    required this.heading,
    required this.zoom,
    this.highlightIndex = -1,
    required this.height,
    this.trackColor = const Color(0xFF22D3EE),
  });

  @override
  State<DarkTileMap> createState() => _DarkTileMapState();
}

class _DarkTileMapState extends State<DarkTileMap> {
  TileSource _source = TileSource.amap;
  int _failed = 0;
  bool _switchScheduled = false;
  int _manualCycle = 0;

  void _reportTileFailure() {
    if (_switchScheduled) return;
    _switchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _switchScheduled = false;
      if (!mounted) return;
      _failed++;
      // 单源连续失败 ≥4 张才整幅切源，避免单张缺失就乱跳。
      if (_failed >= 4 && _source != TileSource.carto) {
        setState(() {
          _source = TileSource.values[_source.index + 1];
          _failed = 0;
        });
      }
    });
  }

  void _cycleSource() {
    setState(() {
      _source = TileSource.values[(_source.index + 1) % TileSource.values.length];
      _failed = 0;
      _manualCycle++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 关键修复：无限高（录制页旧传参）改用实际约束高度，杜绝 floor(inf) 抛错。
      final effHeight = widget.height.isFinite
          ? widget.height
          : (constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0);
      final useGcj = _source == TileSource.amap;
      final c = useGcj ? _wgsToGcj(widget.centerLat, widget.centerLon) : (lat: widget.centerLat, lon: widget.centerLon);
      final dispPoints = useGcj
          ? widget.points.map((p) {
              final g = _wgsToGcj(p.lat, p.lon);
              return TrackPoint(
                timeMs: p.timeMs, lat: g.lat, lon: g.lon, alt: p.alt, speed: p.speed,
                bearing: p.bearing, hAcc: p.hAcc, vAcc: p.vAcc, speedAcc: p.speedAcc,
                provider: p.provider, longG: p.longG, latG: p.latG, vertG: p.vertG,
                pitch: p.pitch, roll: p.roll, heading: p.heading, pressureHpa: p.pressureHpa,
                calibrated: p.calibrated, powerW: p.powerW, powerEstimated: p.powerEstimated,
                cadenceRpm: p.cadenceRpm, heartRate: p.heartRate, sensorStatus: p.sensorStatus,
                altValid: p.altValid,
              );
            }).toList()
          : widget.points;
      final size = Size(constraints.maxWidth, effHeight - 28);
      final scale = 256 * math.pow(2, widget.zoom);
      final cx = (c.lon + 180) / 360 * scale;
      final cy = _mercY(c.lat) * scale;
      final tx0 = ((cx - size.width / 2) / 256).floor();
      final tx1 = ((cx + size.width / 2) / 256).ceil();
      final ty0 = ((cy - size.height / 2) / 256).floor();
      final ty1 = ((cy + size.height / 2) / 256).ceil();
      final tiles = <Widget>[];
      for (var x = tx0; x <= tx1; x++) {
        for (var y = ty0; y <= ty1; y++) {
          final left = x * 256 - (cx - size.width / 2);
          final top = y * 256 - (cy - size.height / 2);
          tiles.add(Positioned(
            left: left,
            top: top,
            width: 256,
            height: 256,
            child: Image.network(
              _tileUrl(_source, widget.zoom.toInt(), x, y),
              key: ValueKey('$_source-$_manualCycle-$x-$y'),
              headers: const {'User-Agent': 'DriveTrack/0.1.2'},
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // 失败只画深色占位，绝不贴错误图/错误文案；同时记一次源失败。
              errorBuilder: (_, __, ___) {
                _reportTileFailure();
                return Container(color: const Color(0xFF0A0F1E));
              },
            ),
          ));
        }
      }
      return Container(
        height: effHeight,
        color: const Color(0xFF0A0F1E),
        child: Column(children: [
          Expanded(
            child: RepaintBoundary(child: Stack(children: [
              ...tiles,
              CustomPaint(
                size: size,
                painter: TrajectoryPainter(dispPoints, c.lat, c.lon, widget.zoom, widget.heading, widget.highlightIndex, widget.trackColor),
              ),
            ])),
          ),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.black54,
            child: Row(children: [
              Expanded(
                child: Text(
                  '${_source == TileSource.amap ? '高德' : _source == TileSource.osm ? 'OSM' : 'CARTO'} · ${_tileAttribution(_source)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _cycleSource,
                child: const Text('切换底图源', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}

class TrajectoryPainter extends CustomPainter {
  final List<TrackPoint> points;
  final double cLat, cLon, zoom, heading;
  final int highlightIndex;
  final Color trackColor;
  TrajectoryPainter(this.points, this.cLat, this.cLon, this.zoom, this.heading, this.highlightIndex, [this.trackColor = const Color(0xFF22D3EE)]);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final pts = points.map((p) => latLonToScreen(p.lat, p.lon, cLat, cLon, zoom, size)).toList();
    // 辉光轨迹：由宽到窄三层
    for (final w in [10.0, 6.0, 3.0]) {
      final paint = Paint()
        ..color = trackColor.withValues(alpha: w == 3 ? 0.95 : 0.25)
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final pt in pts.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
    // 车标：朝向光锥 + 圆点
    final last = highlightIndex >= 0 && highlightIndex < pts.length ? pts[highlightIndex] : pts.last;
    final hdg = (highlightIndex >= 0 && highlightIndex < points.length ? points[highlightIndex].heading : heading) * math.pi / 180;
    final cone = Path()
      ..moveTo(last.dx, last.dy)
      ..lineTo(last.dx + math.sin(hdg - 0.45) * 34, last.dy - math.cos(hdg - 0.45) * 34)
      ..lineTo(last.dx + math.sin(hdg) * 48, last.dy - math.cos(hdg) * 48)
      ..lineTo(last.dx + math.sin(hdg + 0.45) * 34, last.dy - math.cos(hdg + 0.45) * 34)
      ..close();
    canvas.drawPath(cone, Paint()..color = trackColor.withValues(alpha: 0.25));
    canvas.drawCircle(last, 9, Paint()..color = trackColor);
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter old) => true;
}

// ---------- G 值圆 ----------
class GCirlce extends StatelessWidget {
  final double longG, latG;
  final List<GSample> trail; // 最近 5 秒，车体坐标
  final double threshold;
  final bool calibrated;
  final double size;
  final double? peakLong;
  final double? peakLat;
  const GCirlce({
    super.key,
    required this.longG,
    required this.latG,
    required this.trail,
    required this.threshold,
    required this.calibrated,
    this.size = 120,
    this.peakLong,
    this.peakLat,
  });

  @override
  Widget build(BuildContext context) {
    final mag = math.sqrt(longG * longG + latG * latG);
    final color = !calibrated
        ? Colors.grey
        : mag < 0.3
            ? const Color(0xFF22C55E)
            : mag < 0.5
                ? const Color(0xFFEAB308)
                : const Color(0xFFEF4444);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CustomPaint(
        size: Size(size, size),
        painter: GCirlcePainter(
          longG,
          latG,
          trail,
          threshold,
          calibrated,
          color,
          peakLong: peakLong,
          peakLat: peakLat,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        calibrated
            ? S.of(context).t(
                '纵向 ${longG.toStringAsFixed(2)}g · 横向 ${latG.toStringAsFixed(2)}g',
                'Long ${longG.toStringAsFixed(2)}g · lat ${latG.toStringAsFixed(2)}g',
              )
            : S.of(context).t('未标定', 'Not calibrated'),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ]);
  }
}

class GCirlcePainter extends CustomPainter {
  final double longG, latG;
  final List<GSample> trail;
  final double threshold;
  final bool calibrated;
  final Color color;
  final double? peakLong;
  final double? peakLat;
  GCirlcePainter(this.longG, this.latG, this.trail, this.threshold, this.calibrated, this.color,
      {this.peakLong, this.peakLat});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    // 刻度圈：0.25g 一档，满圈 1.0g
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(
          c,
          r * i / 4,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.15)
            ..style = PaintingStyle.stroke);
    }
    // 阈值虚线圈
    final tp = Paint()
      ..color = Colors.orange.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dashPath = Path();
    for (var a = 0.0; a < math.pi * 2; a += 0.35) {
      dashPath.addArc(Rect.fromCircle(center: c, radius: r * threshold.clamp(0.1, 1.0)), a, 0.18);
    }
    canvas.drawPath(dashPath, tp);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), Paint()..color = Colors.white24);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), Paint()..color = Colors.white24);
    if (!calibrated) return;
    // 本节峰值刻度：横向在横轴，纵向在竖轴（上为正）。满圈仍是 1g。
    final peakPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (peakLong != null) {
      final y = c.dy - peakLong!.clamp(-1.0, 1.0) * r;
      canvas.drawLine(Offset(c.dx - 5, y), Offset(c.dx + 5, y), peakPaint);
    }
    if (peakLat != null) {
      final x = c.dx + peakLat!.clamp(-1.0, 1.0) * r;
      canvas.drawLine(Offset(x, c.dy - 5), Offset(x, c.dy + 5), peakPaint);
    }
    // 5 秒拖尾
    if (trail.length > 1) {
      for (var i = 1; i < trail.length; i++) {
        final a = trail[i - 1];
        final b = trail[i];
        canvas.drawLine(
          Offset(c.dx + a.latG * r, c.dy - a.longG * r),
          Offset(c.dx + b.latG * r, c.dy - b.longG * r),
          Paint()
            ..color = color.withValues(alpha: 0.2 + 0.8 * i / trail.length)
            ..strokeWidth = 2,
        );
      }
    }
    final dot = Offset((c.dx + latG * r).clamp(0, size.width), (c.dy - longG * r).clamp(0, size.height));
    canvas.drawCircle(dot, 10, Paint()..color = color.withValues(alpha: 0.3));
    canvas.drawCircle(dot, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant GCirlcePainter old) => true;
}

// ---------- G 波形（最近 60 秒） ----------
class GWaveform extends StatelessWidget {
  final List<GSample> history;
  final double threshold;
  final double height;
  const GWaveform({super.key, required this.history, required this.threshold, this.height = 110});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _WaveformPainter(history, threshold),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<GSample> history;
  final double threshold;
  _WaveformPainter(this.history, this.threshold);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = Colors.white24);
    for (final t in [threshold, -threshold]) {
      final y = mid - t * mid; // 满幅按 1g 计
      final p = Paint()
        ..color = Colors.orange.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var x = 0.0; x < size.width; x += 10) {
        path.moveTo(x, y);
        path.lineTo(x + 5, y);
      }
      canvas.drawPath(path, p);
    }
    if (history.length < 2) return;
    final now = history.last.timeMs;
    void drawLine(bool isLong, Color color) {
      final path = Path();
      var started = false;
      for (final s in history) {
        final age = (now - s.timeMs) / 60000; // 0=最新
        final x = size.width * (1 - age);
        if (x < 0) continue;
        final v = isLong ? s.longG : s.latG;
        final y = (mid - v * mid).clamp(0.0, size.height);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke);
    }

    drawLine(true, const Color(0xFF22D3EE));
    drawLine(false, const Color(0xFFE879F9));
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => true;
}

// ---------- 天气滚动条 ----------
class WeatherMarquee extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  const WeatherMarquee({super.key, required this.text, required this.onTap});

  @override
  State<WeatherMarquee> createState() => _WeatherMarqueeState();
}

class _WeatherMarqueeState extends State<WeatherMarquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
  bool _paused = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = '${widget.text}    •    ${widget.text}    •    ';
    return GestureDetector(
      onTap: () {
        setState(() {
          _paused = !_paused;
          if (_paused) {
            _c.stop();
          } else {
            _c.repeat();
          }
        });
        widget.onTap();
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              return LayoutBuilder(builder: (context, constraints) {
                final w = constraints.maxWidth;
                final offset = -_c.value * w;
                return Stack(children: [
                  Positioned(left: offset, child: Text(content, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 13), maxLines: 1)),
                  Positioned(left: offset + w, child: Text(content, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 13), maxLines: 1)),
                ]);
              });
            },
          ),
        ),
      ),
    );
  }
}

// ---------- 整趟 G-G 散点图（复盘用，点密处颜色越亮） ----------
class GScatter extends StatelessWidget {
  final List<TrackPoint> points;
  final double threshold;
  final double size;
  const GScatter({super.key, required this.points, required this.threshold, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GScatterPainter(points, threshold),
    );
  }
}

class _GScatterPainter extends CustomPainter {
  final List<TrackPoint> points;
  final double threshold;
  _GScatterPainter(this.points, this.threshold);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(
          c,
          r * i / 4,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.15)
            ..style = PaintingStyle.stroke);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), Paint()..color = Colors.white24);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), Paint()..color = Colors.white24);
    var maxR = 0.0;
    for (final p in points) {
      if (!p.calibrated) continue;
      maxR = math.max(maxR, p.combinedG);
      final x = (c.dx + p.latG * r).clamp(0.0, size.width);
      final y = (c.dy - p.longG * r).clamp(0.0, size.height);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = const Color(0xFF22D3EE).withValues(alpha: 0.35));
    }
    if (maxR > 0) {
      canvas.drawCircle(c, r * maxR.clamp(0, 1), Paint()..color = Colors.orange.withValues(alpha: 0.3)..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GScatterPainter old) => true;
}

// ---------- 模式矢量图标（v0.1.2 自绘，拒绝只换 Material 图标名） ----------
// 汽车：低趴跑车，车头朝右。摩托：同向侧视仿赛，轮廓描自确认稿。
class ModeVehicleIcon extends StatelessWidget {
  final TripMode mode;
  final bool selected;
  final Color color;
  final double size;
  const ModeVehicleIcon({super.key, required this.mode, required this.selected, required this.color, this.size = 36});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: mode == TripMode.car
          ? _SportCarPainter(color)
          : mode == TripMode.moto
              ? _SportMotoPainter(color)
              : _BikePainter(color),
    );
  }
}

class _SportCarPainter extends CustomPainter {
  final Color c;
  _SportCarPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = c..style = PaintingStyle.fill;
    final w = s.width, h = s.height;
    // 低趴车身
    final body = Path()
      ..moveTo(w * 0.06, h * 0.72)
      ..lineTo(w * 0.14, h * 0.58)
      ..lineTo(w * 0.34, h * 0.50)
      ..lineTo(w * 0.48, h * 0.34)
      ..lineTo(w * 0.68, h * 0.34)
      ..lineTo(w * 0.80, h * 0.50)
      ..lineTo(w * 0.94, h * 0.58)
      ..lineTo(w * 0.94, h * 0.72)
      ..close();
    canvas.drawPath(body, p);
    // 尾翼
    canvas.drawRect(Rect.fromLTWH(w * 0.78, h * 0.30, w * 0.20, h * 0.07), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.84, h * 0.37, w * 0.04, h * 0.14), p);
    // 车窗
    canvas.drawPath(Path()
      ..moveTo(w * 0.38, h * 0.50)
      ..lineTo(w * 0.50, h * 0.38)
      ..lineTo(w * 0.66, h * 0.38)
      ..lineTo(w * 0.74, h * 0.50)
      ..close(), Paint()..color = Colors.black.withValues(alpha: 0.55));
    // 车轮
    final wheel = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(w * 0.26, h * 0.74), w * 0.13, wheel);
    canvas.drawCircle(Offset(w * 0.74, h * 0.74), w * 0.13, wheel);
    final hub = Paint()..color = c;
    canvas.drawCircle(Offset(w * 0.26, h * 0.74), w * 0.05, hub);
    canvas.drawCircle(Offset(w * 0.74, h * 0.74), w * 0.05, hub);
  }

  @override
  bool shouldRepaint(covariant _SportCarPainter o) => o.c != c;
}

class _SportMotoPainter extends CustomPainter {
  final Color c;
  _SportMotoPainter(this.c);

  static final Path _body = sportMotoBodyPath();
  static final Path _tires = sportMotoTirePath();

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / kSportMotoViewBox, s.height / kSportMotoViewBox);
    canvas.drawPath(_tires, Paint()..color = const Color(0xFF111111));
    canvas.drawPath(_body, Paint()..color = c);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SportMotoPainter o) => o.c != c;
}

class _BikePainter extends CustomPainter {
  final Color c;
  _BikePainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = c..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final w = s.width, h = s.height;
    canvas.drawCircle(Offset(w * 0.24, h * 0.72), w * 0.16, p);
    canvas.drawCircle(Offset(w * 0.76, h * 0.72), w * 0.16, p);
    canvas.drawLine(Offset(w * 0.24, h * 0.72), Offset(w * 0.50, h * 0.38), p);
    canvas.drawLine(Offset(w * 0.76, h * 0.72), Offset(w * 0.50, h * 0.38), p);
    canvas.drawLine(Offset(w * 0.50, h * 0.38), Offset(w * 0.66, h * 0.38), p);
    canvas.drawLine(Offset(w * 0.66, h * 0.38), Offset(w * 0.76, h * 0.72), p);
    canvas.drawLine(Offset(w * 0.42, h * 0.38), Offset(w * 0.36, h * 0.28), p);
    canvas.drawLine(Offset(w * 0.30, h * 0.28), Offset(w * 0.42, h * 0.28), p);
  }

  @override
  bool shouldRepaint(covariant _BikePainter o) => o.c != c;
}
