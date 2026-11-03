/// 海拔剖面与道路类型（估算）——v0.1.7 追加项 5。
///
/// 海拔来源（已核实，见回执）：
/// - 手机 GPS：原生 MainActivity.onLocationChanged 传 location.altitude，
///   并自 v0.1.7 起附带 hasAlt（Location.hasAltitude()）；NETWORK
///   定位无海拔时 altitude 为占位 0，Recorder 以 altValid=false 存入。
/// - BleDIY 外接 GPS：GGA 第 9 字段即海拔（平均海平面以上，米），
///   v0.1.7 前 blediy_gps.dart 解析时丢弃了该字段，导致外接点恒写
///   alt: 0；现已接通，RMC 单独定位时沿用上一次 GGA 海拔，从未
///   收到 GGA 时为无海拔（altValid=false）。
/// - 无海拔的点一律排除：不画进剖面图、不计入爬升、不进 GPX
///   的 <ele>；页面会注明排除了多少点。0 米占位绝不等同于海平面。
///
/// 累计爬升算法（口径写清，不藏参数）：
/// 1. 只取 altValid 的点；
/// 2. 5 点居中滑动平均平滑（1Hz 采样 ≈ 5 秒窗口，见 models.dart
///    smoothAltitudes），压单点毛刺；
/// 3. 阈值分段累计（thresholdClimbM，阈值 3.0 米）：把平滑序列切
///    成上升段，只累计总上升量 ≥ 3.0 米的段，不足的起伏视为 GPS
///    抖动丢弃。代价是 < 3 米的真实小坡也会被丢弃，因此累计值
///    是保守下限，不是精确爬升。下降段不计入、不抵扣。
/// 4. 最高 / 最低点取平滑序列的极值，与图上峰值一致，避免单点
///    毛刺虚高；原始极值不另行展示。
///
/// 道路类型——结论只能是“估算”，不是实测（见回执）：
/// 本 App 的高德 / OSM / CARTO 底图只是栅格瓦片（refined_map.dart），
/// 不返回结构化道路等级或路名；离线地图导入也只支持瓦片包与轨迹
/// 叠加层，不含道路属性。因此没有任何真实路名 / 道路等级可用，
/// 绝不编造。本文件只做速度区间里程占比：按终点速度把相邻点间
/// 的里程分桶，桶名后一律标“（估算）”，页面上另有整段说明文字。
/// 速度区间口径（km/h，终点速度，见 estimateRoadMix）：
///   < 10 为低速 / 停车（不属于道路类型，仅作里程参考）；
///   10–<40 城市道路 / 乡村道路（估算）；
///   40–<80 城市主干道（估算）；≥ 80 高速公路 / 快速路（估算）。
/// 速度判道路的固有误判（页面与回执均注明）：高速堵车会落入低速桶，
/// 城市快速路低速行驶会被判为城市道路，骑行模式下高速桶通常为 0。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// 爬升阈值（米），与 models.dart thresholdClimbM 默认值保持一致。
const double kClimbThresholdM = 3.0;

/// 海拔剖面统计结果。validCount < 2 时曲线与极值均为空，调用方
/// 应显示“暂无”并注明 excludedCount，而不是画假曲线。
class AltitudeProfileData {
  final List<TrackPoint> validPoints;
  final List<double> distancesKm;
  final List<double> smoothedAltM;
  final double climbM;
  final double? maxAltM;
  final double? minAltM;
  final int validCount;
  final int excludedCount;

  const AltitudeProfileData({
    required this.validPoints,
    required this.distancesKm,
    required this.smoothedAltM,
    required this.climbM,
    required this.maxAltM,
    required this.minAltM,
    required this.validCount,
    required this.excludedCount,
  });

  bool get hasCurve => validPoints.length >= 2;
}

AltitudeProfileData computeAltitudeProfile(List<TrackPoint> points) {
  final valid = points.where((p) => p.altValid && p.alt.isFinite).toList();
  final excluded = points.length - valid.length;
  if (valid.length < 2) {
    return AltitudeProfileData(
      validPoints: valid,
      distancesKm: const [],
      smoothedAltM: const [],
      climbM: 0,
      maxAltM: null,
      minAltM: null,
      validCount: valid.length,
      excludedCount: excluded,
    );
  }
  final distances = <double>[0];
  for (var i = 1; i < valid.length; i++) {
    distances.add(distances.last +
        haversineM(valid[i - 1].lat, valid[i - 1].lon, valid[i].lat, valid[i].lon) / 1000);
  }
  // 注意：被排除的无海拔点之间的里程，在此按相邻有效点的直线
  // 距离 bridging，剖面横轴因此在缺口处是近似值，不是逐点里程。
  final smoothed = smoothAltitudes(valid.map((p) => p.alt).toList());
  return AltitudeProfileData(
    validPoints: valid,
    distancesKm: distances,
    smoothedAltM: smoothed,
    climbM: thresholdClimbM(smoothed, thresholdM: kClimbThresholdM),
    maxAltM: smoothed.reduce(math.max),
    minAltM: smoothed.reduce(math.min),
    validCount: valid.length,
    excludedCount: excluded,
  );
}

/// 速度区间里程桶。isRoadType=false 的桶（低速 / 停车）不是道路
/// 类型，只占里程参考行；其余桶名在界面上必须带“（估算）”。
class RoadBucket {
  final String label;
  final bool isRoadType;
  final double distanceM;
  final double share;
  const RoadBucket({
    required this.label,
    required this.isRoadType,
    required this.distanceM,
    required this.share,
  });
}

List<RoadBucket> estimateRoadMix(List<TrackPoint> points) {
  var low = 0.0, urban = 0.0, arterial = 0.0, highway = 0.0;
  for (var i = 1; i < points.length; i++) {
    final d = haversineM(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
    if (d <= 0) continue;
    final kmh = points[i].speed * 3.6;
    if (kmh < 10) {
      low += d;
    } else if (kmh < 40) {
      urban += d;
    } else if (kmh < 80) {
      arterial += d;
    } else {
      highway += d;
    }
  }
  final total = low + urban + arterial + highway;
  RoadBucket b(String label, bool isRoad, double d) => RoadBucket(
        label: label,
        isRoadType: isRoad,
        distanceM: d,
        share: total > 0 ? d / total : 0,
      );
  return [
    b('低速 / 停车', false, low),
    b('城市道路 / 乡村道路（估算）', true, urban),
    b('城市主干道（估算）', true, arterial),
    b('高速公路 / 快速路（估算）', true, highway),
  ];
}

String _fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

/// 海拔剖面图：横轴里程（km）、纵轴海拔（m），纯 CustomPainter，
/// 无新插件。点按 / 拖动查看该点里程、海拔与时刻。点数 < 2 时
/// 调用方不应实例化本 widget，应先显示“暂无”。
class AltitudeProfileChart extends StatefulWidget {
  final AltitudeProfileData data;
  const AltitudeProfileChart({super.key, required this.data});

  @override
  State<AltitudeProfileChart> createState() => _AltitudeProfileChartState();
}

class _AltitudeProfileChartState extends State<AltitudeProfileChart> {
  int? _sel;

  void _pick(Offset local, Size size) {
    final n = widget.data.validPoints.length;
    if (n < 2 || size.width <= 0) return;
    final frac = (local.dx / size.width).clamp(0.0, 1.0);
    setState(() => _sel = (frac * (n - 1)).round().clamp(0, n - 1));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final sel = _sel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 200,
        width: double.infinity,
        child: LayoutBuilder(builder: (_, constraints) {
          final size = Size(constraints.maxWidth, 200);
          return GestureDetector(
            onTapDown: (d) => _pick(d.localPosition, size),
            onPanUpdate: (d) => _pick(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: _AltitudePainter(
                distancesKm: data.distancesKm,
                altitudesM: data.smoothedAltM,
                selected: sel,
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(
        sel != null && sel >= 0 && sel < data.validPoints.length
            ? '${data.distancesKm[sel].toStringAsFixed(2)} km · '
                '海拔 ${data.smoothedAltM[sel].toStringAsFixed(0)} m · '
                '${_fmtClock(data.validPoints[sel].timeMs)}'
            : '点击或拖动曲线查看该点里程与海拔',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ]);
  }
}

class _AltitudePainter extends CustomPainter {
  final List<double> distancesKm;
  final List<double> altitudesM;
  final int? selected;

  const _AltitudePainter({
    required this.distancesKm,
    required this.altitudesM,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (altitudesM.length < 2) return;
    const padL = 46.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    var lo = altitudesM.reduce(math.min);
    var hi = altitudesM.reduce(math.max);
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final totalKm = distancesKm.isEmpty ? 0.0 : distancesKm.last;
    double x(int i) => padL + (totalKm > 0 ? w * distancesKm[i] / totalKm : w * i / (altitudesM.length - 1));
    double y(double v) => padT + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final textStyle = const TextStyle(color: Colors.white54, fontSize: 11);
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      final yy = y(v);
      canvas.drawLine(Offset(padL, yy), Offset(padL + w, yy), grid);
      final tp = TextPainter(
          text: TextSpan(text: v.toStringAsFixed(0), style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, yy - 6));
    }
    for (final frac in [0.0, 0.5, 1.0]) {
      final xx = padL + w * frac;
      final label = (totalKm * frac).toStringAsFixed(1);
      final tp = TextPainter(
          text: TextSpan(text: '$label km', style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(xx - tp.width / 2, padT + h + 4));
    }

    final path = Path()..moveTo(x(0), y(altitudesM[0]));
    for (var i = 1; i < altitudesM.length; i++) {
      path.lineTo(x(i), y(altitudesM[i]));
    }
    final fill = Path.from(path)
      ..lineTo(x(altitudesM.length - 1), padT + h)
      ..lineTo(x(0), padT + h)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..color = const Color(0xFF22D3EE).withValues(alpha: 0.18)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF22D3EE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    if (selected != null && selected! >= 0 && selected! < altitudesM.length) {
      final sx = x(selected!);
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + h),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(sx, y(altitudesM[selected!])), 5,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(sx, y(altitudesM[selected!])), 3,
          Paint()..color = const Color(0xFF22D3EE));
    }
  }

  @override
  bool shouldRepaint(_AltitudePainter old) =>
      old.altitudesM != altitudesM ||
      old.distancesKm != distancesKm ||
      old.selected != selected;
}
