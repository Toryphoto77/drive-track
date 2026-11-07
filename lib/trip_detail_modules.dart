/// 行程详情模块化卡片（v0.1.4 新文件，不改动已有文件）。
///
/// 全部数据来自调用方传入的 Trip / TrackPoint / TripEvent，不自己读 store、
/// 不读全局状态、不编造数据。点数不足时显示“暂无”，不画假曲线。
/// 速度单位换算：TrackPoint.speed 为 m/s，界面一律显示 km/h（×3.6）。
/// G 值单位为 g，取自 TrackPoint.longG / latG / combinedG。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fuel_page.dart';
import 'altitude_profile.dart';
import 'models.dart';
import 'photo_points.dart';

const Color _kRed = Color(0xFFE10600);
const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);

String _fmtDur(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:'
      '${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}月${d.day}日 '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kBorder),
    ),
    child: child,
  );
}

Widget _cardTitle(String title) {
  return Text(title,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold));
}

const Widget _emptyNote = Text('暂无',
    style: TextStyle(color: Colors.white54, fontSize: 13));

/// v1.0.7 遥测关键数据条：里程 / 时长 / 最高时速 / 平均时速 /
/// 最大 G / 评分，大字一行（小屏自动换行），全部来自实测 trip。
class TelemetryKpiStrip extends StatelessWidget {
  final Trip trip;
  const TelemetryKpiStrip({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final durH = (trip.endMs - trip.startMs) / 3600000.0;
    final avg = durH > 0 ? (trip.distanceM / 1000) / durH : 0.0;
    Widget kpi(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE10600).withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        Row(children: [
          kpi('里程', '${(trip.distanceM / 1000).toStringAsFixed(2)} km'),
          kpi('时长', _fmtDur(trip.endMs - trip.startMs)),
          kpi('最高时速', '${(trip.maxSpeed * 3.6).toStringAsFixed(0)} km/h'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          kpi('平均时速', '${avg.toStringAsFixed(0)} km/h'),
          kpi('最大 G', trip.points.isEmpty ? '暂无' : '${trip.maxG.toStringAsFixed(2)}g'),
          kpi('评分', trip.score.toStringAsFixed(0)),
        ]),
      ]),
    );
  }
}

/// 总览卡：里程 / 时长 / 最高速度 / 最大 G / 爬升 / 模式 / 日期。
/// 全部由 [trip] 的 getter 算出（distanceM / maxSpeed / maxG / climbM），
/// 不另传手工数字。
class TripOverviewCard extends StatelessWidget {
  final Trip trip;
  const TripOverviewCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _cardTitle('${trip.mode.label}行程')),
          Text(_fmtDate(trip.startMs),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stat('里程', '${(trip.distanceM / 1000).toStringAsFixed(2)} km'),
          _stat('时长', _fmtDur(trip.endMs - trip.startMs)),
          _stat('最高速度', '${(trip.maxSpeed * 3.6).toStringAsFixed(0)} km/h'),
          _stat('最大 G', trip.points.isEmpty ? '暂无' : trip.maxG.toStringAsFixed(2)),
          _stat('爬升', '${trip.climbM.toStringAsFixed(0)} m'),
          if (trip.isTrackMode && trip.trackName.isNotEmpty)
            _stat('赛道', trip.trackName),
        ]),
        if (trip.weatherSummary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('天气：${trip.weatherSummary}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// 可点查的折线图基类：点击 / 拖动时按横坐标找最近点，回传下标。
/// [values] 与 [points] 等长；纵轴按 values 的最小 / 最大值自适应，
/// 含 0 基线参考；点数 < 2 时调用方应先显示“暂无”，不进本 widget。
class _InspectableChart extends StatefulWidget {
  final List<TrackPoint> points;
  final List<double> values;
  final List<double>? secondValues;
  final String unit;
  final Color color;
  final Color? secondColor;
  final String Function(TrackPoint point, int index) tooltip;
  final ValueChanged<int>? onPointSelected;
  final int? selectedIndex;
  /// v1.0.7：曲线上的事件标记（点下标 + 颜色），画在曲线顶部。
  final List<(int, Color)>? markers;

  const _InspectableChart({
    required this.points,
    required this.values,
    required this.unit,
    required this.color,
    required this.tooltip,
    this.secondValues,
    this.secondColor,
    this.onPointSelected,
    this.selectedIndex,
    this.markers,
  });

  @override
  State<_InspectableChart> createState() => _InspectableChartState();
}

class _InspectableChartState extends State<_InspectableChart> {
  int? _sel;

  int? get _selected => widget.selectedIndex ?? _sel;

  void _pick(Offset local, Size size) {
    final n = widget.points.length;
    if (n < 2 || size.width <= 0) return;
    final frac = (local.dx / size.width).clamp(0.0, 1.0);
    final idx = (frac * (n - 1)).round().clamp(0, n - 1);
    setState(() => _sel = idx);
    widget.onPointSelected?.call(idx);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 240,
        width: double.infinity,
        child: LayoutBuilder(builder: (_, constraints) {
          final size = Size(constraints.maxWidth, 240);
          return GestureDetector(
            onTapDown: (d) => _pick(d.localPosition, size),
            onPanUpdate: (d) => _pick(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: _LineChartPainter(
                values: widget.values,
                secondValues: widget.secondValues,
                color: widget.color,
                secondColor: widget.secondColor,
                selected: sel,
                markers: widget.markers,
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(
        sel != null && sel >= 0 && sel < widget.points.length
            ? widget.tooltip(widget.points[sel], sel)
            : '点击或拖动曲线查看该点数值',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ]);
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<double>? secondValues;
  final Color color;
  final Color? secondColor;
  final int? selected;
  final List<(int, Color)>? markers;

  const _LineChartPainter({
    required this.values,
    required this.color,
    this.secondValues,
    this.secondColor,
    this.selected,
    this.markers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const padL = 44.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (secondValues != null && secondValues!.isNotEmpty) {
      lo = math.min(lo, secondValues!.reduce(math.min));
      hi = math.max(hi, secondValues!.reduce(math.max));
    }
    if ((hi - lo).abs() < 1e-9) {
      hi = lo + 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    double x(int i) => padL + w * i / (values.length - 1);
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
          text: TextSpan(text: v.toStringAsFixed(1), style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, yy - 6));
    }
    Path line(List<double> vs) {
      final p = Path()..moveTo(x(0), y(vs[0]));
      for (var i = 1; i < vs.length; i++) {
        p.lineTo(x(i), y(vs[i]));
      }
      return p;
    }

    canvas.drawPath(
        line(values),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    if (secondValues != null && secondValues!.length == values.length) {
      canvas.drawPath(
          line(secondValues!),
          Paint()
            ..color = secondColor ?? Colors.white54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round);
    }
    if (markers != null) {
      for (final m in markers!) {
        if (m.$1 < 0 || m.$1 >= values.length) continue;
        final mx = x(m.$1);
        canvas.drawLine(Offset(mx, padT), Offset(mx, padT + h),
            Paint()..color = m.$2.withValues(alpha: 0.45)..strokeWidth = 1.5);
        final tri = Path()
          ..moveTo(mx - 5, padT)
          ..lineTo(mx + 5, padT)
          ..lineTo(mx, padT + 8)
          ..close();
        canvas.drawPath(tri, Paint()..color = m.$2);
      }
    }
    if (selected != null && selected! >= 0 && selected! < values.length) {
      final sx = x(selected!);
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + h),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(sx, y(values[selected!])),
          5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(sx, y(values[selected!])),
          3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.values != values ||
      old.secondValues != secondValues ||
      old.selected != selected ||
      old.markers != markers;
}

/// 速度大图卡：速度-时间曲线，高度 240px，网格与 11px 以上轴字，
/// 点击 / 拖动显示该点时刻与速度。点数 < 2 显示“暂无”。
class TripSpeedChartCard extends StatelessWidget {
  final List<TrackPoint> points;
  final ValueChanged<int>? onPointSelected;
  final int? selectedIndex;
  /// v1.0.7：标在速度曲线上的事件（急加速绿 / 急刹红 / 弯道黄）。
  final List<TripEvent>? events;

  const TripSpeedChartCard({
    super.key,
    required this.points,
    this.onPointSelected,
    this.selectedIndex,
    this.events,
  });

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('速度'),
        const SizedBox(height: 8),
        if (points.length < 2)
          _emptyNote
        else
          _InspectableChart(
            points: points,
            values: points.map((p) => p.speed * 3.6).toList(),
            unit: 'km/h',
            color: _kRed,
            onPointSelected: onPointSelected,
            selectedIndex: selectedIndex,
            markers: events
                ?.map((e) => (e.startIndex,
                    e.kind == 'harshAccel'
                        ? Colors.greenAccent
                        : e.kind == 'harshBrake'
                            ? Colors.redAccent
                            : e.kind == 'corner'
                                ? Colors.amber
                                : Colors.white54))
                .toList(),
            tooltip: (p, _) =>
                '${_fmtClock(p.timeMs)} · ${(p.speed * 3.6).toStringAsFixed(0)} km/h',
          ),
      ]),
    );
  }
}

/// G 值大图卡：纵向 G（青）与横向 G（品红）双曲线，高度 240px，
/// 点击 / 拖动显示该点时刻、纵向 / 横向 / 合成 G。点数 < 2 显示“暂无”。
/// 注意：未标定点的 longG / latG 为设备坐标而非车身坐标，调用方
/// 若需门控，应先过滤 calibrated 点再传入。
/// G 值数据分析页（v1.0.4 重做：专业赛车队数据分析风格，仅呈现，
/// 不冒充任何车队官方分析页；全部数据来自行程实测 G 值，不编造）。
///
/// 深色底 + 网格 + 红白配色，包含：
/// - G-G 散点图（横向/纵向 G 分布，含 1g 参考圆）；
/// - 纵向与横向 G 随时间曲线（复用可点查折线图）；
/// - 最大 G、最大刹车/加速/横向 G 统计；
/// - 刹车/加速/弯道区段标注（连续区段计数与峰值）；
/// - G 值直方图（合成 G 区间分布）。
class TripGChartCard extends StatelessWidget {
  final List<TrackPoint> points;
  final ValueChanged<int>? onPointSelected;
  final int? selectedIndex;

  const TripGChartCard({
    super.key,
    required this.points,
    this.onPointSelected,
    this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    final maxCombined =
        points.isEmpty ? 0.0 : points.map((p) => p.combinedG).reduce(math.max);
    final maxAccel =
        points.isEmpty ? 0.0 : points.map((p) => p.longG).reduce(math.max);
    final maxBrake = points.isEmpty
        ? 0.0
        : -points.map((p) => p.longG).reduce(math.min);
    final maxLat =
        points.isEmpty ? 0.0 : points.map((p) => p.latG.abs()).reduce(math.max);
    // 区段：连续同类点算一段；刹车 longG<=-0.3，加速 longG>=0.3，
    // 弯道 |latG|>=0.3（刹车/加速优先于弯道，避免一段被重复计数）。
    var brakeSegs = 0, accelSegs = 0, cornerSegs = 0;
    var prev = '';
    for (final p in points) {
      final t = p.longG <= -0.3
          ? 'brake'
          : (p.longG >= 0.3 ? 'accel' : (p.latG.abs() >= 0.3 ? 'corner' : ''));
      if (t.isNotEmpty && t != prev) {
        if (t == 'brake') brakeSegs++;
        if (t == 'accel') accelSegs++;
        if (t == 'corner') cornerSegs++;
      }
      prev = t;
    }
    // 直方图：合成 G 六档。
    const bins = <(double, double, String)>[
      (0, 0.2, '<0.2'),
      (0.2, 0.4, '0.2-0.4'),
      (0.4, 0.6, '0.4-0.6'),
      (0.6, 0.8, '0.6-0.8'),
      (0.8, 1.0, '0.8-1.0'),
      (1.0, double.infinity, '>1.0'),
    ];
    final counts = List<int>.filled(bins.length, 0);
    for (final p in points) {
      for (var i = 0; i < bins.length; i++) {
        if (p.combinedG >= bins[i].$1 && p.combinedG < bins[i].$2) {
          counts[i]++;
          break;
        }
      }
    }
    final maxCount = counts.isEmpty ? 0 : counts.reduce(math.max);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('G 值'),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stat('最大合成 G', '${maxCombined.toStringAsFixed(2)}g'),
          _stat('最大加速 G', '${maxAccel.toStringAsFixed(2)}g'),
          _stat('最大刹车 G', '${maxBrake.toStringAsFixed(2)}g'),
          _stat('最大横向 G', '${maxLat.toStringAsFixed(2)}g'),
          _stat('样本点', '${points.length}'),
        ]),
        const SizedBox(height: 12),
        const Text('G-G 散点图（红圈为 1g）',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        if (points.length < 2)
          _emptyNote
        else
          SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: _GGScatterPainter(points: points),
            ),
          ),
        const SizedBox(height: 12),
        const Row(children: [
          _LegendDot(Colors.white, '纵向'),
          SizedBox(width: 12),
          _LegendDot(Color(0xFFE10600), '横向'),
        ]),
        const SizedBox(height: 8),
        if (points.length < 2)
          _emptyNote
        else
          _InspectableChart(
            points: points,
            values: points.map((p) => p.longG).toList(),
            secondValues: points.map((p) => p.latG).toList(),
            unit: 'g',
            color: Colors.white,
            secondColor: const Color(0xFFE10600),
            onPointSelected: onPointSelected,
            selectedIndex: selectedIndex,
            tooltip: (p, _) => '${_fmtClock(p.timeMs)} · 纵向 '
                '${p.longG.toStringAsFixed(2)}g · 横向 '
                '${p.latG.toStringAsFixed(2)}g · 合成 '
                '${p.combinedG.toStringAsFixed(2)}g',
          ),
        const SizedBox(height: 12),
        const Text('区段标注',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stat('刹车区段', '$brakeSegs 段 · 峰值 ${maxBrake.toStringAsFixed(2)}g'),
          _stat('加速区段', '$accelSegs 段 · 峰值 ${maxAccel.toStringAsFixed(2)}g'),
          _stat('弯道区段', '$cornerSegs 段 · 峰值 ${maxLat.toStringAsFixed(2)}g'),
        ]),
        const SizedBox(height: 12),
        const Text('G 值直方图',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        if (points.isEmpty)
          _emptyNote
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < bins.length; i++)
                Expanded(
                  child: Column(children: [
                    Text('${counts[i]}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 2),
                    Container(
                      height: maxCount == 0
                          ? 4
                          : 8 + 72 * counts[i] / maxCount,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      color: i >= 4 ? const Color(0xFFE10600) : Colors.white70,
                    ),
                    const SizedBox(height: 4),
                    Text(bins[i].$3,
                        style: const TextStyle(color: Colors.white54, fontSize: 9)),
                  ]),
                ),
            ],
          ),
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// G-G 散点图画笔：深色底 + 网格 + 红白配色；横轴横向 G、纵轴纵向 G，
/// 量程取实测最大绝对值（下限 0.5g），红圈为 1g 参考（量程 >=1g 时画）。
class _GGScatterPainter extends CustomPainter {
  final List<TrackPoint> points;
  const _GGScatterPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101010));
    var range = 0.5;
    for (final p in points) {
      range = math.max(range, p.longG.abs());
      range = math.max(range, p.latG.abs());
    }
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = math.min(size.width, size.height) / 2 / range;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final f in [-1.0, -0.5, 0.5, 1.0]) {
      canvas.drawLine(Offset(cx + f * range * s, 0), Offset(cx + f * range * s, size.height), grid);
      canvas.drawLine(Offset(0, cy - f * range * s), Offset(size.width, cy - f * range * s), grid);
    }
    final axis = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), axis);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axis);
    if (range >= 1) {
      canvas.drawCircle(Offset(cx, cy), s,
          Paint()..color = const Color(0xFFE10600).withValues(alpha: 0.6)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final p in points) {
      canvas.drawCircle(Offset(cx + p.latG * s, cy - p.longG * s), 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _GGScatterPainter old) => old.points != points;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}

/// 事件列表卡：按开始时间排序显示；点某条通过 [onEventTap] 回传该事件，
/// 调用方可用它定位回放（例如把详情页 scrub 置为 event.startIndex）。
/// 事件为空显示“暂无”。
class TripEventListCard extends StatelessWidget {
  final List<TripEvent> events;
  final TripMode mode;
  final TripEvent? selectedEvent;
  final ValueChanged<TripEvent>? onEventTap;

  const TripEventListCard({
    super.key,
    required this.events,
    required this.mode,
    this.selectedEvent,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = List<TripEvent>.from(events)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('事件（${sorted.length}）'),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          _emptyNote
        else
          for (final e in sorted)
            _eventTile(e, e == selectedEvent),
      ]),
    );
  }

  Widget _eventTile(TripEvent e, bool selected) {
    final secs = ((e.endMs - e.startMs) / 1000).round();
    final lean = mode == TripMode.moto
        ? ' · 左倾 ${e.maxLeanLeft.toStringAsFixed(0)}° '
            '右倾 ${e.maxLeanRight.toStringAsFixed(0)}°'
        : '';
    return Material(
      color: selected ? _kRed.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onEventTap == null ? null : () => onEventTap!(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${e.label} · ${_fmtClock(e.startMs)} · $secs 秒',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                    '纵向 ${e.peakLongG.toStringAsFixed(2)}g · '
                    '横向 ${e.peakLatG.toStringAsFixed(2)}g · '
                    '速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)} → '
                    '${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h$lean',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                if (e.note.isNotEmpty)
                  Text(e.note,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
            if (onEventTap != null)
              const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// 评分卡（静态摘要版；带动画圆环与点按过滤的版本见 score_module.dart
/// 的 DrivingScoreCard，详情页二选一接入，不要同时放两张评分卡）。
/// 总分取 [trip.score]，分项取 [trip.subScores]，理由取 [trip.scoreReasons]；
/// 赛道模式（isTrackMode）下显示“赛道模式不评分”，不把街道评分混进来。
class TripScoreSummaryCard extends StatelessWidget {
  final Trip trip;
  const TripScoreSummaryCard({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(trip.isTrackMode
            ? '赛道模式不评分'
            : '驾驶习惯评分 ${trip.score.toStringAsFixed(0)} 分'),
        const SizedBox(height: 8),
        if (!trip.isTrackMode) ...[
          if (trip.subScores.isEmpty)
            _emptyNote
          else
            for (final e in trip.subScores.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text(e.key,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Text('${e.value.toStringAsFixed(0)} 分',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
          for (final r in trip.scoreReasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $r',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('注：无可靠限速源时不算超速分',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ]),
    );
  }
}

/// 油耗模块（v0.1.7 追加项 4）：仅汽车 / 摩托显示，骑行模式
/// 本 widget 直接返回空占位（调用方也可再用 if 门控，双保险）。
/// 里程复用 [trip.distanceM]（轨迹点 haversine 累加），不另算；
/// 计算复用 fuel_page.dart 的 estimateFuel；未填两项时显示
/// “未填写油耗/油价”，不显示 0；算出时明确标“按填写油耗估算”，
/// 不是加油实测。
class TripFuelCard extends StatelessWidget {
  final Trip trip;
  final double? consumptionLPer100Km;
  final double? fuelPricePerLiter;
  // v1.2.0：每车油耗与实测（均可空）。有效油耗 = 每车油耗（有值
  // 时）否则全局值；实测有值时与估算并列显示并标注“实测（满油区间）”，
  // 无实测时不显示实测行。油价一律用全局油价（车辆档案无油价字段）。
  final double? vehicleConsumptionLPer100Km;
  final double? measuredConsumptionLPer100Km;
  final String? vehicleName;
  const TripFuelCard({
    super.key,
    required this.trip,
    this.consumptionLPer100Km,
    this.fuelPricePerLiter,
    this.vehicleConsumptionLPer100Km,
    this.measuredConsumptionLPer100Km,
    this.vehicleName,
  });

  @override
  Widget build(BuildContext context) {
    if (trip.mode == TripMode.bike) return const SizedBox.shrink();
    final distanceKm = trip.distanceM / 1000;
    final effectiveConsumption =
        (vehicleConsumptionLPer100Km != null && vehicleConsumptionLPer100Km! > 0)
            ? vehicleConsumptionLPer100Km
            : consumptionLPer100Km;
    final est = estimateFuel(
      distanceKm: distanceKm,
      consumptionLPer100Km: effectiveConsumption,
      fuelPricePerLiter: fuelPricePerLiter,
    );
    // 实测油量 = 里程 × 实测油耗 / 100；实测油钱按全局油价折算。
    final measuredLiters = (measuredConsumptionLPer100Km != null && measuredConsumptionLPer100Km! > 0)
        ? distanceKm * measuredConsumptionLPer100Km! / 100
        : null;
    final measuredCost = (measuredLiters != null && fuelPricePerLiter != null && fuelPricePerLiter! > 0)
        ? measuredLiters * fuelPricePerLiter!
        : null;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('油耗费用'),
        const SizedBox(height: 8),
        if (vehicleName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('车辆：$vehicleName', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        if (est == null) ...[
          const Text('未填写油耗/油价',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('去设置 > 油耗费用填写百公里油耗与油价。',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ] else ...[
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat('油耗量', '${est.liters.toStringAsFixed(2)} L'),
            _stat('油钱', '${est.cost.toStringAsFixed(2)} 元'),
            _stat('里程', '${distanceKm.toStringAsFixed(2)} km'),
            _stat('百公里油耗', '${effectiveConsumption!.toStringAsFixed(2)} L/100km'),
            _stat('油价', '${fuelPricePerLiter!.toStringAsFixed(2)} 元/L'),
          ]),
          const SizedBox(height: 6),
          Text(
            vehicleConsumptionLPer100Km != null && vehicleConsumptionLPer100Km! > 0
                ? '按每车油耗估算，非加油实测。'
                : '按填写油耗估算，非加油实测。',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
        if (measuredLiters != null) ...[
          const SizedBox(height: 10),
          const Text('实测（满油区间）',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat('实测油量', '${measuredLiters.toStringAsFixed(2)} L'),
            if (measuredCost != null) _stat('实测油钱', '${measuredCost.toStringAsFixed(2)} 元'),
            _stat('实测油耗', '${measuredConsumptionLPer100Km!.toStringAsFixed(2)} L/100km'),
          ]),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// 行程相册卡（v0.1.7 追加项 2）：详情页内的相册入口，不另起一级导航。
/// 只展示调用方传入的 [trip] 数据，不读 store、不编造点；
/// 附照片 / 打开相册 / 点某张缩略图的动作全部由调用方回调注入，
/// 落盘由详情页经 Store.updateTripPhotoPoints 完成。
/// 地图为示意轨迹 + 照片点（见 photo_points.dart 的画笔），
/// 不是瓦片地图；无照片点时说明打点路径，不画假点。
class TripPhotoAlbumCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback? onOpenAlbum;
  final ValueChanged<PhotoPoint>? onPhotoTap;
  final VoidCallback? onAttachToLatestUnphotographed;
  // v1.2.0：上次落盘被 50 条上限截断时为 true，卡片须明示，
  // 不得当作全部保存成功。
  final bool photoPointsTruncated;

  const TripPhotoAlbumCard({
    super.key,
    required this.trip,
    this.onOpenAlbum,
    this.onPhotoTap,
    this.onAttachToLatestUnphotographed,
    this.photoPointsTruncated = false,
  });

  bool get _hasUnphotographed =>
      trip.photoPoints.any((p) => !p.hasPhoto);

  @override
  Widget build(BuildContext context) {
    final photos = trip.photoPoints;
    final withPhoto = photos.where((p) => p.hasPhoto).toList();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _cardTitle(
                  '事件标记（${photos.length} 个标记 · ${withPhoto.length} 张照片）')),
          if (onOpenAlbum != null)
            TextButton(
                onPressed: onOpenAlbum, child: const Text('打开时间线')),
        ]),
        if (photoPointsTruncated)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('一趟最多保留前 50 条标记。',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          const Text('暂无标记：记录中点“标记事件”添加。',
              style: TextStyle(color: Colors.white70, fontSize: 13))
        else ...[
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: const Size(double.infinity, 140),
              painter: PhotoPointsMapPainter(
                track: trip.points
                    .map((p) => (lat: p.lat, lon: p.lon))
                    .toList(),
                photos: photos,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('示意地图：白线为轨迹，彩点为事件',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              itemBuilder: (_, i) {
                final p = photos[i];
                final f =
                    p.photoPath == null ? null : File(p.photoPath!);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap:
                        onPhotoTap == null ? null : () => onPhotoTap!(p),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: f != null && f.existsSync()
                          ? Image.file(f,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              cacheWidth: 144,
                              errorBuilder: (_, __, ___) =>
                                  _thumbPlaceholder(i))
                          : _thumbPlaceholder(i),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_hasUnphotographed && onAttachToLatestUnphotographed != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera, size: 18),
            label: const Text('给未附照片的标记附照片'),
            onPressed: onAttachToLatestUnphotographed,
          ),
        ],
        const Text('照片只存本机，不上传；删行程时副本随之删除，不删相册原图。',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }

  Widget _thumbPlaceholder(int i) => Container(
        width: 72,
        height: 72,
        color: Colors.white.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.photo_camera, color: Colors.white54, size: 20),
          Text('${i + 1}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );
}

/// 海拔模块（v0.1.7 追加项 5）：剖面图 + 累计爬升 + 最高 / 最低点。
/// 只用 altValid 的点；无海拔点排除并在页面注明数量，0 米占位
/// 绝不画进图、绝不计入爬升。累计爬升口径：5 点平滑 + 3.0 米阈值
/// 分段累计（见 altitude_profile.dart），是保守下限，不是精确值。
/// 有效点 < 2 时显示“暂无”，不画假曲线。
class TripAltitudeCard extends StatelessWidget {
  final List<TrackPoint> points;
  const TripAltitudeCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final data = computeAltitudeProfile(points);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('海拔'),
        const SizedBox(height: 8),
        if (!data.hasCurve) ...[
          _emptyNote,
          const SizedBox(height: 4),
          Text(
            points.isEmpty
                ? '本行程无轨迹点。'
                : '有效海拔点不足（有效 ${data.validCount} 点，已排除 '
                    '${data.excludedCount} 点）。',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ] else ...[
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat('累计爬升', '${data.climbM.toStringAsFixed(0)} m'),
            _stat('最高点', '${data.maxAltM!.toStringAsFixed(0)} m'),
            _stat('最低点', '${data.minAltM!.toStringAsFixed(0)} m'),
          ]),
          const SizedBox(height: 8),
          AltitudeProfileChart(data: data),
          const SizedBox(height: 6),
          Text(
            '累计爬升只计上升 ≥ 3 米的段，为保守下限。'
            '${data.excludedCount > 0 ? '已排除无海拔点 ${data.excludedCount} 点。' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 2),
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// 道路类型模块（v0.1.7 追加项 5）——结论只能是“估算”，不是实测。
/// 本 App 底图（高德 / OSM / CARTO）只是栅格瓦片，不提供结构化
/// 道路等级或路名，离线导入也不含道路属性，因此无法给出真实道路
/// 类型；本卡按速度区间统计里程占比，每行均标“（估算）”。
/// 口径：相邻点间里程按终点速度分桶（<10 低速 / 停车、
/// 10–<40、40–<80、≥ 80 km/h）。高速堵车会落入低速桶，城市快速路
/// 低速行驶会被判为城市道路，骑行模式下高速桶通常为 0，均属正常。
class TripRoadTypeCard extends StatelessWidget {
  final List<TrackPoint> points;
  const TripRoadTypeCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final buckets = estimateRoadMix(points);
    final totalM = buckets.fold(0.0, (a, b) => a + b.distanceM);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle('道路类型（估算，非实测）'),
        const SizedBox(height: 8),
        if (points.length < 2 || totalM <= 0)
          _emptyNote
        else
          for (final b in buckets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(b.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13))),
                  Text(
                      '${(b.distanceM / 1000).toStringAsFixed(2)} km · '
                      '${(b.share * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: b.share,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        b.isRoadType ? _kRed : Colors.white38),
                  ),
                ),
              ]),
            ),
        const SizedBox(height: 6),
        const Text(
          '仅按速度区间估算，非真实道路等级；高速拥堵、低速行驶时可能误判。',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
