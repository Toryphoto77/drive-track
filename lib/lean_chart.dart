/// 摩托压弯图表模块（v0.1.4 新文件，不改动已有文件）。
///
/// 可信门控（硬规则）：
/// - 只有 [isCalibratedAndMounted] 为真才画曲线 / 散点 / 分布 / 榜单。
///   该参数由调用方传入：手机已固定在支架上且已完成标定。
///   本文件不从 Trip 里猜：TrackPoint.calibrated 只是逐点标定标记，
///   是否“固定”不在模型里，调用方必须显式传入，不得默认 true。
/// - 为假时整个模块只显示短标签“仅固定+标定后可信”，不画任何曲线、
///   不显示由 roll 算出的最大倾角等数字，避免把未标定的设备坐标当成压弯角。
/// 倾角符号约定（与 logic.dart 一致）：roll < 0 为左倾，roll > 0 为右倾。
/// 角度单位为度；速度显示为 km/h（TrackPoint.speed 为 m/s，×3.6）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);
const Color _kLeft = Color(0xFF38BDF8); // 左倾
const Color _kRight = Color(0xFFE10600); // 右倾
const String leanNotTrustedLabel = '仅固定+标定后可信';

String _fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

Widget _card({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kBorder),
    ),
    child: child,
  );
}

Widget _title(String t) {
  return Text(t,
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold));
}

const Widget _emptyNote =
    Text('暂无', style: TextStyle(color: Colors.white54, fontSize: 13));

/// 门控占位：未固定 + 标定时只显示这一行短标签。
class LeanNotTrustedNote extends StatelessWidget {
  const LeanNotTrustedNote({super.key});

  @override
  Widget build(BuildContext context) {
    return _card(
      child: const Row(children: [
        Icon(Icons.info_outline, color: Colors.orange, size: 18),
        SizedBox(width: 8),
        Text(leanNotTrustedLabel,
            style: TextStyle(color: Colors.white70, fontSize: 14)),
      ]),
    );
  }
}

/// 倾角-时间曲线：左倾（roll < 0）用蓝色段、右倾（roll > 0）用红色段，
/// 按相邻两点符号分段着色；点击 / 拖动显示该点时刻与倾角（含左右）。
/// 点数 < 2 显示“暂无”。
class LeanTimeChart extends StatefulWidget {
  final List<TrackPoint> points;
  final ValueChanged<int>? onPointSelected;
  const LeanTimeChart({super.key, required this.points, this.onPointSelected});

  @override
  State<LeanTimeChart> createState() => _LeanTimeChartState();
}

class _LeanTimeChartState extends State<LeanTimeChart> {
  int? _sel;

  void _pick(Offset local, double width) {
    final n = widget.points.length;
    if (n < 2 || width <= 0) return;
    final idx = ((local.dx / width).clamp(0.0, 1.0) * (n - 1))
        .round()
        .clamp(0, n - 1);
    setState(() => _sel = idx);
    widget.onPointSelected?.call(idx);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < 2) return _emptyNote;
    final sel = _sel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        _LegendDot(_kLeft, '左倾'),
        SizedBox(width: 12),
        _LegendDot(_kRight, '右倾'),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 240,
        width: double.infinity,
        child: LayoutBuilder(builder: (_, c) {
          final size = Size(c.maxWidth, 240);
          return GestureDetector(
            onTapDown: (d) => _pick(d.localPosition, size.width),
            onPanUpdate: (d) => _pick(d.localPosition, size.width),
            child: CustomPaint(
                size: size,
                painter: _LeanTimePainter(points: pts, selected: sel)),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(
        sel != null
            ? '${_fmtClock(pts[sel].timeMs)} · '
                '${pts[sel].roll < 0 ? '左倾' : pts[sel].roll > 0 ? '右倾' : '直立'} '
                '${pts[sel].roll.abs().toStringAsFixed(0)}°'
            : '点击或拖动曲线查看该点倾角',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ]);
  }
}

class _LeanTimePainter extends CustomPainter {
  final List<TrackPoint> points;
  final int? selected;
  const _LeanTimePainter({required this.points, this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    var lo = points.map((p) => p.roll).reduce(math.min);
    var hi = points.map((p) => p.roll).reduce(math.max);
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if ((hi - lo).abs() < 1e-9) {
      hi = lo + 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    double x(int i) => padL + w * i / (points.length - 1);
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
          text: TextSpan(text: '${v.toStringAsFixed(0)}°', style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, yy - 6));
    }
    // 零线（直立）加粗。
    canvas.drawLine(Offset(padL, y(0)), Offset(padL + w, y(0)),
        Paint()..color = Colors.white.withValues(alpha: 0.35));
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      // 段颜色按段中点符号定：跨零段按终点符号，避免一段两种色不断裂。
      final color = b.roll < 0 ? _kLeft : _kRight;
      canvas.drawLine(
          Offset(x(i - 1), y(a.roll)),
          Offset(x(i), y(b.roll)),
          Paint()
            ..color = color
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
    }
    if (selected != null) {
      final sx = x(selected!);
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + h),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(sx, y(points[selected!].roll)), 5,
          Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_LeanTimePainter old) =>
      old.points != points || old.selected != selected;
}

/// 倾角-速度散点：横轴速度（km/h），纵轴倾角（度，负左 / 正右），
/// 左倾蓝点、右倾红点；直立点（0°）为灰点。点数 < 2 显示“暂无”。
class LeanSpeedScatter extends StatelessWidget {
  final List<TrackPoint> points;
  const LeanSpeedScatter({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return _emptyNote;
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: CustomPaint(painter: _LeanScatterPainter(points: points)),
    );
  }
}

class _LeanScatterPainter extends CustomPainter {
  final List<TrackPoint> points;
  const _LeanScatterPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 44.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final maxV = points.map((p) => p.speed * 3.6).reduce(math.max);
    var lo = points.map((p) => p.roll).reduce(math.min);
    var hi = points.map((p) => p.roll).reduce(math.max);
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
    final spanV = maxV <= 0 ? 1 : maxV;
    double x(TrackPoint p) => padL + w * (p.speed * 3.6) / spanV;
    double y(TrackPoint p) => padT + h * (1 - (p.roll - lo) / (hi - lo));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final yy = padT + h * k / 4;
      canvas.drawLine(Offset(padL, yy), Offset(padL + w, yy), grid);
    }
    canvas.drawLine(Offset(padL, y(_zeroRollPoint(lo, hi))), Offset(padL + w, y(_zeroRollPoint(lo, hi))),
        Paint()..color = Colors.white.withValues(alpha: 0.35));
    for (final p in points) {
      final color = p.roll < 0 ? _kLeft : (p.roll > 0 ? _kRight : Colors.white38);
      canvas.drawCircle(Offset(x(p), y(p)), 3.5, Paint()..color = color);
    }
  }

  // 仅为画零线构造一个 roll=0 的点（不参与数据统计）。
  TrackPoint _zeroRollPoint(double lo, double hi) => TrackPoint(
        timeMs: 0, lat: 0, lon: 0, alt: 0, speed: 0, bearing: 0, hAcc: 0,
        vAcc: 0, speedAcc: 0, provider: '', longG: 0, latG: 0, vertG: 0,
        pitch: 0, roll: 0, heading: 0, pressureHpa: 0, calibrated: false,
      );

  @override
  bool shouldRepaint(_LeanScatterPainter old) => old.points != points;
}

/// 左右倾角分布条：按 1Hz 点数统计 |roll| ≥ 10° 的左倾秒数 / 右倾秒数 / 其余
/// （直立或小倾角）秒数；三段按占比画一条。无倾角点（全部 |roll| < 10°）
/// 时显示“暂无”（不把直立画成压弯分布）。
class LeanDistributionBar extends StatelessWidget {
  final List<TrackPoint> points;
  const LeanDistributionBar({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    var left = 0, right = 0, rest = 0;
    for (final p in points) {
      if (p.roll <= -10) {
        left++;
      } else if (p.roll >= 10) {
        right++;
      } else {
        rest++;
      }
    }
    final total = left + right + rest;
    if (total == 0 || (left == 0 && right == 0)) return _emptyNote;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          if (left > 0)
            Expanded(
                flex: left,
                child: Container(height: 18, color: _kLeft)),
          if (rest > 0)
            Expanded(
                flex: rest,
                child: Container(height: 18, color: Colors.white24)),
          if (right > 0)
            Expanded(
                flex: right,
                child: Container(height: 18, color: _kRight)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
          '左倾 $left 秒（${(left / total * 100).toStringAsFixed(0)}%） · '
          '直立 / 小倾角 $rest 秒 · '
          '右倾 $right 秒（${(right / total * 100).toStringAsFixed(0)}%）',
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
      const Text('统计口径：|倾角| ≥ 10° 才计入左右倾，1Hz 一点计 1 秒',
          style: TextStyle(color: Colors.white54, fontSize: 11)),
    ]);
  }
}

/// 每弯最大倾角榜：取 kind == 'corner' 的事件，按左右最大倾角的较大值
/// 降序排列；点某条通过 [onEventTap] 回传事件供详情页定位。
/// 无过弯事件显示“暂无”。
class CornerLeanRanking extends StatelessWidget {
  final List<TripEvent> events;
  final ValueChanged<TripEvent>? onEventTap;
  const CornerLeanRanking({super.key, required this.events, this.onEventTap});

  @override
  Widget build(BuildContext context) {
    final corners = events.where((e) => e.kind == 'corner').toList()
      ..sort((a, b) => math
          .max(b.maxLeanLeft, b.maxLeanRight)
          .compareTo(math.max(a.maxLeanLeft, a.maxLeanRight)));
    if (corners.isEmpty) return _emptyNote;
    return Column(children: [
      for (var i = 0; i < corners.length; i++)
        _row(i + 1, corners[i]),
    ]);
  }

  Widget _row(int rank, TripEvent e) {
    final maxLean = math.max(e.maxLeanLeft, e.maxLeanRight);
    final side = e.maxLeanLeft >= e.maxLeanRight ? '左' : '右';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEventTap == null ? null : () => onEventTap!(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: Text('$rank',
                  style: TextStyle(
                      color: rank == 1 ? _kRight : Colors.white70,
                      fontSize: 14,
                      fontWeight:
                          rank == 1 ? FontWeight.bold : FontWeight.normal)),
            ),
            Expanded(
              child: Text(
                  '${_fmtClock(e.startMs)} · $side倾 ${maxLean.toStringAsFixed(0)}° '
                  '（左 ${e.maxLeanLeft.toStringAsFixed(0)}° / '
                  '右 ${e.maxLeanRight.toStringAsFixed(0)}°）',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            Text(
                '${(e.entrySpeed * 3.6).toStringAsFixed(0)} → '
                '${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// 压弯图表组合卡：门控 + 倾角-时间曲线 + 倾角-速度散点 + 分布条 + 每弯榜。
/// [isCalibratedAndMounted] 为假时只出门控标签，不渲染任何子图与数字。
class LeanChartSection extends StatelessWidget {
  final Trip trip;
  final bool isCalibratedAndMounted;
  final ValueChanged<TripEvent>? onEventTap;
  final ValueChanged<int>? onPointSelected;

  const LeanChartSection({
    super.key,
    required this.trip,
    required this.isCalibratedAndMounted,
    this.onEventTap,
    this.onPointSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCalibratedAndMounted) return const LeanNotTrustedNote();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('压弯'),
        const SizedBox(height: 8),
        LeanTimeChart(points: trip.points, onPointSelected: onPointSelected),
        const SizedBox(height: 16),
        _title('倾角 - 速度'),
        const SizedBox(height: 8),
        LeanSpeedScatter(points: trip.points),
        const SizedBox(height: 16),
        _title('左右倾角分布'),
        const SizedBox(height: 8),
        LeanDistributionBar(points: trip.points),
        const SizedBox(height: 16),
        _title('每弯最大倾角榜'),
        const SizedBox(height: 8),
        CornerLeanRanking(events: trip.events, onEventTap: onEventTap),
      ]),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ]);
  }
}
