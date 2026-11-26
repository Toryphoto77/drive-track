import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'models.dart';
import 'recorder.dart';
import 'car_paths.dart';
import 'mode_icon_paths.dart';
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

// ---------- G 值圆盘 ----------
//
// 设计口径（v1.6 G 表盘改版）：
// - 圆心大数字 = 合成 G（√(纵向²+横向²)），一眼看出当前用掉多少抓地力；
// - 圆盘四边 = 本趟四向峰值（上加速 / 下刹车 / 右 / 左），是“你自己的
//   数据”，与参考图不同：参考图只放量程刻度，我们把本次行程的极值
//   直接标在四个方向，跑完一圈就知道哪个方向最狠；
// - 外圈细环 + 十字轴刻度保留专业摩擦圆语义，满圈 1.0g；
// - 颜色沿用 App 既有阈值：<0.3g 绿、<0.5g 黄、否则红；
// - 5 秒拖尾保留，便于看矢量移动轨迹。
// 未标定时不画圆盘（上层直接显示“未标定”），绝不编造数值。
class GCirlce extends StatelessWidget {
  final double longG, latG;
  final List<GSample> trail; // 最近 5 秒，车体坐标
  final double threshold;
  final bool calibrated;
  final double size;
  final double? peakLong;
  final double? peakLat;

  /// 本趟四向峰值（非负）。不传则由 [peakLong] / [peakLat] 的符号推导，
  /// 只有本方向存在极值时才有读数，另一侧显示 “—”。
  final double? maxAccelG;
  final double? maxBrakeG;
  final double? maxRightG;
  final double? maxLeftG;

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
    this.maxAccelG,
    this.maxBrakeG,
    this.maxRightG,
    this.maxLeftG,
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
    // 四向读数：优先用 Recorder 的四向峰值，缺省时按带符号峰值推导。
    final accel = maxAccelG ??
        (peakLong != null && peakLong! > 0 ? peakLong : null);
    final brake = maxBrakeG ??
        (peakLong != null && peakLong! < 0 ? -peakLong! : null);
    final right =
        maxRightG ?? (peakLat != null && peakLat! > 0 ? peakLat : null);
    final left =
        maxLeftG ?? (peakLat != null && peakLat! < 0 ? -peakLat! : null);
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
          maxAccelG: accel,
          maxBrakeG: brake,
          maxRightG: right,
          maxLeftG: left,
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
  final double? maxAccelG;
  final double? maxBrakeG;
  final double? maxRightG;
  final double? maxLeftG;

  /// 满圈 = 1.0g；超量程时圆点钳在圆边，数值本身不钳制。
  static const double _fullScaleG = 1.0;

  GCirlcePainter(
    this.longG,
    this.latG,
    this.trail,
    this.threshold,
    this.calibrated,
    this.color, {
    this.peakLong,
    this.peakLat,
    this.maxAccelG,
    this.maxBrakeG,
    this.maxRightG,
    this.maxLeftG,
  });

  double _clamp(double v) => v.clamp(-_fullScaleG, _fullScaleG);

  Offset _pt(double lat, double lg, Offset c, double r, Size size) => Offset(
        (c.dx + _clamp(lat) / _fullScaleG * r).clamp(2.0, size.width - 2),
        (c.dy - _clamp(lg) / _fullScaleG * r).clamp(2.0, size.height - 2),
      );

  void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final innerR = r - 6;

    // 深色底盘 + 细边：与职业计时页的 HUD 底子一致。
    canvas.drawCircle(c, r - 1, Paint()..color = const Color(0xFF15171B));
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 外圈按当前合成 G 上色（细环，不抢读数）。
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 摩擦圆：1/3、2/3 辅助环 + 十字轴。
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, innerR / 3, ringPaint);
    canvas.drawCircle(c, innerR * 2 / 3, ringPaint);
    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - innerR, c.dy),
        Offset(c.dx + innerR, c.dy), axisPaint);
    canvas.drawLine(Offset(c.dx, c.dy - innerR),
        Offset(c.dx, c.dy + innerR), axisPaint);

    // 轴向刻度：0.45 / 0.65 / 0.85 各一档，给圆心大数字让位。
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (final g in const [0.45, 0.65, 0.85]) {
      final d = g * innerR;
      final t = (size.width * 0.02).clamp(2.0, 4.0);
      canvas.drawLine(Offset(c.dx - t, c.dy - d), Offset(c.dx + t, c.dy - d), tickPaint);
      canvas.drawLine(Offset(c.dx - t, c.dy + d), Offset(c.dx + t, c.dy + d), tickPaint);
      canvas.drawLine(Offset(c.dx - d, c.dy - t), Offset(c.dx - d, c.dy + t), tickPaint);
      canvas.drawLine(Offset(c.dx + d, c.dy - t), Offset(c.dx + d, c.dy + t), tickPaint);
    }

    // 急弯阈值提示：极淡的虚线环，保留原有语义但不抢读数。
    final thrR = threshold.clamp(0.1, 1.0) * innerR;
    final thrPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var a = 0.0; a < math.pi * 2; a += 0.4) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: thrR), a, 0.2, false, thrPaint);
    }

    if (!calibrated) return;

    // 5 秒拖尾（矢量移动轨迹）。
    if (trail.length > 1) {
      for (var i = 1; i < trail.length; i++) {
        final a = trail[i - 1];
        final b = trail[i];
        canvas.drawLine(
          _pt(a.latG, a.longG, c, innerR, size),
          _pt(b.latG, b.longG, c, innerR, size),
          Paint()
            ..color = color.withValues(alpha: 0.10 + 0.45 * i / trail.length)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 四边本趟峰值：上加速 / 下刹车 / 右 / 左，无数据显 “—”。
    final edgeSize = (size.width * 0.075).clamp(7.5, 22.0);
    final edgeStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.55),
      fontSize: edgeSize,
      fontWeight: FontWeight.w500,
      height: 1.0,
    );
    String fmt(double? v) {
      if (v == null || v < 0.005) return '—';
      return v.toStringAsFixed(1);
    }
    final off = innerR * 0.80;
    _text(canvas, fmt(maxAccelG), c + Offset(0, -off), edgeStyle);
    _text(canvas, fmt(maxBrakeG), c + Offset(0, off), edgeStyle);
    _text(canvas, fmt(maxRightG), c + Offset(off, 0), edgeStyle);
    _text(canvas, fmt(maxLeftG), c + Offset(-off, 0), edgeStyle);

    // 圆心：合成 G 大数字（2 位小数）+ 小 g + “合成”标注。
    final mag = math.sqrt(longG * longG + latG * latG);
    final numSize = size.width * 0.19;
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: mag.toStringAsFixed(2),
          style: TextStyle(
            color: color,
            fontSize: numSize,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        TextSpan(
          text: 'g',
          style: TextStyle(
            color: color.withValues(alpha: 0.65),
            fontSize: numSize * 0.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2 - size.width * 0.03));
    _text(
      canvas,
      '合成',
      c + Offset(0, size.width * 0.105),
      TextStyle(
        color: Colors.white.withValues(alpha: 0.32),
        fontSize: (size.width * 0.062).clamp(6.5, 15.0),
        height: 1.0,
      ),
    );

    // 当前矢量圆点：白色描边 + 阈值色填充，超量程钳在圆边。
    final dot = _pt(latG, longG, c, innerR - 4, size);
    canvas.drawCircle(dot, 9, Paint()..color = color.withValues(alpha: 0.20));
    canvas.drawCircle(dot, 5.5, Paint()..color = color);
    canvas.drawCircle(
      dot,
      5.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant GCirlcePainter old) =>
      old.longG != longG ||
      old.latG != latG ||
      old.calibrated != calibrated ||
      old.color != color ||
      old.threshold != threshold ||
      old.peakLong != peakLong ||
      old.peakLat != peakLat ||
      old.maxAccelG != maxAccelG ||
      old.maxBrakeG != maxBrakeG ||
      old.maxRightG != maxRightG ||
      old.maxLeftG != maxLeftG ||
      old.trail.length != trail.length;
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
// 三个都是车头朝左的侧视矢量，黑底上轮圈用图标色，不靠纯黑轮胎。
// 汽车：从本应用的侧视剪影描出，车头朝左，不镜像。宽度和轮底对齐仿赛，不撑满高度。
// 自行车：大轮深框的公路赛车，宽度对齐仿赛。路径不要改。
// 摩托：描线仿赛，由 _SportMotoPainter 镜像并撑满，路径本身不要改。
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
      painter: switch (mode) {
        TripMode.car => _SportCarPainter(color),
        TripMode.moto => _SportMotoPainter(color),
        TripMode.kart => _KartPainter(color),
        TripMode.bike => _BikePainter(color),
      },
    );
  }
}

/// 卡丁车（v1.5.8 重绘）：按参考的实心剪影稿 1:1 矢量化，车头朝左。
///
/// 设计语言与前两个图标一致——整块单色剪影 + 极细负空间：
/// 车身是一条平滑楔形（前翼白槽、驾驶舱开口、尾部楔形），
/// 两个等大外露车轮为实心圆盘，靠车身缺口留出细白环；
/// 头盔与尾部进气口由轮廓负空间勾出。全部坐标来自参考图轮廓提取，
/// 归一化到 140×78 设计框，轮底 76 对齐 0.88 基线。
class _KartPainter extends CustomPainter {
  final Color c;
  _KartPainter(this.c);

  /// 设计框：宽 140、高 64（y 14–78），轮底 y≈76.3，车头朝左。
  /// 宽度 1.60 倍图标（约 56dp），视觉体量与轿跑/仿赛对齐。
  static const Rect _src = Rect.fromLTRB(0, 14, 140, 78);
  static const double _widthFrac = 1.60;

  /// 车身外轮廓（x,y 交替，闭合多边形）。
  static const List<double> _body = [99.33, 22.5, 95.46, 22.5, 95.46, 23.15, 92.88, 23.15, 92.88, 23.79, 91.59, 23.79, 91.59, 24.44, 90.95, 24.44, 90.95, 25.08, 90.3, 25.08, 89.66, 26.37, 89.01, 26.37, 89.01, 27.66, 90.3, 27.66, 90.3, 28.3, 90.95, 28.3, 90.95, 27.66, 95.46, 27.66, 95.46, 28.3, 97.39, 28.3, 97.39, 28.95, 98.04, 28.95, 98.04, 31.53, 96.75, 31.53, 96.75, 32.17, 95.46, 32.17, 95.46, 32.82, 93.53, 32.82, 93.53, 33.46, 89.01, 33.46, 89.01, 34.1, 85.79, 34.1, 85.79, 34.75, 85.15, 34.75, 85.15, 39.91, 85.79, 39.91, 85.79, 40.55, 88.37, 40.55, 88.37, 41.84, 87.08, 41.84, 87.08, 42.48, 84.5, 42.48, 84.5, 43.13, 80.64, 43.13, 80.64, 43.77, 76.77, 43.77, 76.77, 44.42, 71.61, 44.42, 71.61, 45.06, 63.88, 45.06, 63.88, 44.42, 61.94, 44.42, 61.94, 43.77, 60.65, 43.77, 60.65, 43.13, 59.36, 43.13, 59.36, 42.48, 58.72, 42.48, 58.72, 41.84, 58.08, 41.84, 58.08, 41.19, 57.43, 41.19, 57.43, 40.55, 56.79, 40.55, 56.79, 39.91, 56.14, 39.91, 56.14, 39.26, 55.5, 39.26, 55.5, 38.62, 54.85, 38.62, 54.85, 37.97, 54.21, 37.97, 53.56, 36.68, 51.63, 36.68, 51.63, 37.33, 50.99, 37.33, 50.99, 39.26, 51.63, 39.26, 51.63, 40.55, 52.27, 40.55, 52.27, 41.19, 53.56, 41.84, 53.56, 43.77, 52.92, 43.77, 52.92, 44.42, 51.63, 44.42, 50.99, 45.71, 49.7, 45.71, 49.7, 46.35, 48.41, 46.35, 47.76, 47.64, 46.47, 47.64, 46.47, 48.28, 45.18, 48.28, 45.18, 48.93, 42.61, 48.93, 42.61, 49.57, 40.03, 49.57, 40.03, 50.22, 36.81, 50.22, 36.81, 50.86, 34.87, 50.86, 34.87, 51.51, 32.29, 51.51, 32.29, 52.15, 29.72, 52.15, 29.72, 52.8, 27.78, 52.8, 27.78, 53.44, 25.85, 53.44, 25.85, 54.09, 23.91, 54.09, 23.91, 54.73, 21.98, 54.73, 21.98, 55.37, 20.05, 55.37, 20.05, 56.02, 18.11, 56.02, 18.11, 56.66, 16.18, 56.66, 16.18, 57.31, 14.89, 57.31, 14.89, 57.95, 12.96, 57.95, 12.96, 58.6, 11.02, 58.6, 11.02, 59.24, 9.73, 59.24, 9.73, 59.89, 8.45, 59.89, 8.45, 60.53, 6.51, 60.53, 6.51, 61.18, 5.22, 61.18, 5.22, 61.82, 4.58, 61.82, 4.58, 63.11, 32.29, 63.11, 32.29, 62.46, 33.58, 61.82, 33.58, 60.53, 34.23, 60.53, 34.23, 58.6, 34.87, 58.6, 34.87, 57.31, 35.52, 57.31, 35.52, 56.66, 36.16, 56.66, 36.16, 56.02, 36.81, 56.02, 36.81, 55.37, 37.45, 55.37, 37.45, 54.73, 38.09, 54.73, 38.74, 53.44, 40.03, 53.44, 40.03, 52.8, 41.32, 52.8, 41.32, 52.15, 42.61, 52.15, 42.61, 51.51, 45.83, 51.51, 45.83, 50.86, 48.41, 50.86, 48.41, 51.51, 49.05, 51.51, 49.05, 50.86, 50.99, 50.86, 50.99, 50.22, 52.27, 50.22, 52.92, 48.93, 54.21, 48.93, 54.21, 48.28, 55.5, 48.28, 56.14, 47, 58.72, 47, 58.72, 47.64, 59.36, 47.64, 59.36, 48.28, 60.01, 48.28, 60.65, 49.57, 61.94, 49.57, 61.94, 50.22, 63.88, 50.22, 63.88, 50.86, 66.45, 50.86, 66.45, 51.51, 67.1, 51.51, 67.1, 50.86, 74.19, 50.86, 74.19, 52.15, 73.55, 52.15, 73.55, 52.8, 71.61, 52.8, 71.61, 53.44, 67.74, 53.44, 67.74, 52.8, 61.94, 52.8, 61.94, 52.15, 60.01, 52.15, 60.01, 52.8, 58.08, 52.8, 58.08, 53.44, 56.79, 54.09, 56.79, 55.37, 58.08, 56.02, 58.08, 57.31, 59.36, 57.95, 59.36, 59.24, 60.01, 59.24, 60.01, 61.18, 60.65, 61.18, 60.65, 69.55, 60.01, 69.55, 60.01, 70.84, 59.36, 70.84, 59.36, 72.13, 60.01, 72.13, 60.01, 72.78, 96.75, 72.78, 96.75, 72.13, 97.39, 72.13, 97.39, 70.2, 96.75, 70.2, 96.75, 67.62, 96.1, 67.62, 96.1, 62.46, 96.75, 62.46, 96.75, 60.53, 97.39, 60.53, 97.39, 58.6, 98.04, 58.6, 98.04, 57.31, 98.68, 57.31, 98.68, 56.66, 99.33, 56.66, 99.33, 56.02, 99.97, 56.02, 99.97, 55.37, 100.62, 55.37, 100.62, 54.73, 101.26, 54.73, 101.91, 53.44, 103.19, 53.44, 103.84, 52.15, 105.77, 52.15, 105.77, 51.51, 108.35, 51.51, 108.35, 50.86, 111.57, 50.86, 111.57, 51.51, 114.8, 51.51, 114.8, 52.15, 116.09, 52.15, 116.09, 52.8, 117.37, 52.8, 118.02, 54.09, 119.31, 54.09, 119.31, 54.73, 120.6, 55.37, 120.6, 56.66, 121.89, 57.31, 121.89, 58.6, 122.53, 58.6, 122.53, 59.89, 123.18, 59.89, 123.18, 61.18, 123.82, 61.18, 123.82, 68.91, 123.18, 68.91, 123.18, 70.84, 122.53, 70.84, 122.53, 72.13, 123.18, 72.13, 123.18, 72.78, 136.71, 72.78, 136.71, 72.13, 137.36, 72.13, 137.36, 70.84, 138, 70.84, 138, 66.33, 137.36, 66.33, 137.36, 64.4, 136.71, 64.4, 136.07, 63.11, 134.78, 63.11, 134.78, 62.46, 134.13, 62.46, 134.13, 61.82, 133.49, 61.82, 133.49, 61.18, 132.84, 61.18, 132.2, 59.89, 130.91, 59.89, 130.91, 59.24, 130.27, 59.24, 129.62, 57.95, 128.33, 57.95, 128.33, 57.31, 127.69, 57.31, 127.04, 56.02, 125.75, 56.02, 125.11, 54.73, 123.82, 54.73, 123.82, 54.09, 123.18, 54.09, 123.18, 53.44, 121.89, 53.44, 121.24, 52.15, 119.95, 52.15, 119.95, 51.51, 118.66, 51.51, 118.02, 50.22, 116.73, 50.22, 116.73, 49.57, 115.44, 49.57, 115.44, 48.93, 114.15, 48.93, 114.15, 48.28, 112.86, 48.28, 112.86, 47.64, 110.93, 47.64, 110.93, 47, 109.64, 47, 109.64, 46.35, 108.35, 46.35, 108.35, 45.71, 106.42, 45.71, 106.42, 45.06, 104.48, 45.06, 104.48, 44.42, 103.19, 44.42, 103.19, 43.77, 102.55, 43.77, 102.55, 42.48, 101.91, 42.48, 101.91, 39.26, 102.55, 39.26, 102.55, 38.62, 103.19, 38.62, 103.19, 37.97, 103.84, 37.97, 103.84, 37.33, 105.13, 36.68, 105.13, 35.39, 105.77, 35.39, 105.77, 33.46, 106.42, 33.46, 106.42, 29.59, 105.77, 29.59, 105.77, 27.66, 105.13, 27.66, 105.13, 26.37, 104.48, 26.37, 104.48, 25.73, 103.84, 25.73, 103.84, 25.08, 103.19, 25.08, 102.55, 23.79, 101.26, 23.79, 101.26, 23.15];

  /// 尾部横向白槽（负空间，用相反绕向挖掉）。
  static const List<double> _slot = [32.29, 65.04, 2.64, 65.04, 2.64, 65.69, 2, 65.69, 2, 66.98, 1.36, 66.98, 1.36, 70.84, 2, 70.84, 2, 72.13, 2.64, 72.13, 2.64, 72.78, 34.23, 72.78, 34.23, 69.55, 33.58, 69.55, 33.58, 66.98, 32.94, 66.98, 32.94, 65.69];

  /// 两个等大外露车轮：实心圆盘，细白环由车身缺口留出。
  static const Offset _frontWheel = Offset(110.28, 64.72);
  static const double _frontR = 11.28;
  static const Offset _rearWheel = Offset(47.44, 64.72);
  static const double _rearR = 11.6;

  static Path _buildPath() {
    final p = Path();
    void polygon(List<double> pts) {
      p.moveTo(pts[0], pts[1]);
      for (var i = 2; i < pts.length; i += 2) {
        p.lineTo(pts[i], pts[i + 1]);
      }
      p.close();
    }

    polygon(_body);
    polygon(_slot);
    p.addOval(Rect.fromCircle(center: _frontWheel, radius: _frontR));
    p.addOval(Rect.fromCircle(center: _rearWheel, radius: _rearR));
    return p;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final b = _src;
    final scale = _widthFrac * s.width / b.width;
    final left = (s.width - b.width * scale) / 2;
    canvas.save();
    canvas.translate(left - b.left * scale, 0.88 * s.height - b.bottom * scale);
    canvas.scale(scale);
    canvas.drawPath(_buildPath(), Paint()..color = c);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KartPainter old) => old.c != c;
}

/// 仿赛把车身高度放进 0.28–0.88 后，宽度大约是图标的 1.164 倍。
/// 轿跑和公路车用同一宽度、同一条轮底，避免轿跑在槽里显得又高又宽。
const double _kMotoWidthFrac = 888.39 / 458.01 * 0.60;

/// v1.5.8：轿跑侧视比仿赛更扁更长，按仿赛同宽缩放时高度只剩 12dp，
/// 视觉上明显比摩托“小一号”。单独放大到仿赛宽度的 1.36 倍，
/// 让车高回到 17dp 左右，三个图标的视觉体量对齐。
const double _kCarWidthFrac = _kMotoWidthFrac * 1.36;

void _fitModeWidth(Canvas canvas, Size s, Rect src, void Function(Canvas canvas) draw,
    {double widthFrac = _kMotoWidthFrac}) {
  final scale = widthFrac * s.width / src.width;
  final left = (s.width - src.width * scale) / 2;
  canvas.save();
  canvas.translate(left - src.left * scale, 0.88 * s.height - src.bottom * scale);
  canvas.scale(scale);
  draw(canvas);
  canvas.restore();
}

class _SportCarPainter extends CustomPainter {
  final Color c;
  _SportCarPainter(this.c);

  static final Path _car = coupeSilhouettePath();

  /// 描线端点的外框。轮底在底边上，用来和仿赛接地。
  static const Rect _src = Rect.fromLTRB(2.0, 2.6, 1034.0, 309.7);

  @override
  void paint(Canvas canvas, Size s) {
    // 剪影已经朝左，不镜像。轮底与仿赛对齐，宽度单独放大一档。
    _fitModeWidth(canvas, s, _src, (canvas) {
      canvas.drawPath(_car, Paint()..color = c);
    }, widthFrac: _kCarWidthFrac);
  }

  @override
  bool shouldRepaint(covariant _SportCarPainter o) => o.c != c;
}

class _SportMotoPainter extends CustomPainter {
  final Color c;
  _SportMotoPainter(this.c);

  static final Path _body = sportMotoBodyPath();
  static final Path _tires = sportMotoTirePath();
  static final Rect _src = _body.getBounds().expandToInclude(_tires.getBounds());

  /// 和汽车（尾翼 0.30、轮底 0.87）、自行车（车把 0.28、轮底 0.88）同一条垂直槽。
  /// 仿赛描线比这条槽更扁，等比放大后左右会多出约 3dp，落在模式项 14dp 的间距里，
  /// 不裁切，避免轮子被切掉后又显得偏小。
  static const double _slotTop = 0.28;
  static const double _slotBottom = 0.88;

  @override
  void paint(Canvas canvas, Size s) {
    final b = _src;
    final scale = (_slotBottom - _slotTop) * s.height / b.height;
    final left = (s.width - b.width * scale) / 2;
    canvas.save();
    // 描线车头在高 x。镜像后车头朝左，与跑车、自行车一致。
    // screenX = left + (b.right - x) * scale
    // screenY = slotTop + (y - b.top) * scale
    canvas.translate(left + b.right * scale, _slotTop * s.height - b.top * scale);
    canvas.scale(-scale, scale);
    // 轮胎与车身同一支颜色。轮圈、辐条靠路径镂空透出底色，
    // 纯黑或近黑背景上不再消失。选中/未选中都跟图标色走。
    final paint = Paint()..color = c;
    canvas.drawPath(_tires, paint);
    canvas.drawPath(_body, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SportMotoPainter o) => o.c != c;
}

class _BikePainter extends CustomPainter {
  final Color c;
  _BikePainter(this.c);

  static final Path _wheels = modeIconPath(kRoadBikeWheels);
  static final Path _frame = modeIconPath(kRoadBikeFrame)..fillType = PathFillType.nonZero;
  static final Path _chain = modeIconPath(kRoadBikeChain);
  static const Rect _src = Rect.fromLTRB(70.0, 224.0, 1070.0, 760.0);

  @override
  void paint(Canvas canvas, Size s) {
    // 和仿赛同一宽度、同一条轮底。车架路径不变。
    _fitModeWidth(canvas, s, _src, (canvas) {
      final paint = Paint()..color = c;
      canvas.drawPath(_wheels, paint);
      canvas.drawPath(_frame, paint);
      canvas.drawPath(_chain, paint);
    });
  }

  @override
  bool shouldRepaint(covariant _BikePainter o) => o.c != c;
}
