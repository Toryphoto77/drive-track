/// 汽车 / 摩托加速度模块（v0.1.4 新文件，不改动已有文件）。
///
/// 单位换算：TrackPoint.longG 单位为 g，m/s² = g × 9.81，界面同时显示
/// 两个单位，不只给其一。
/// 0-100 km/h 用时（硬门控）：
/// - 仅当轨迹里存在一次“从静止起步”并随后达到 100 km/h 时才算：
///   起步点 = 速度 ≤ 0.5 m/s 的点，之后第一个达到 ≥ 27.78 m/s（100 km/h）
///   的点之间用线性插值算出恰好 100 km/h 的时刻，用时 = 该时刻 - 起步时刻。
/// - 不满足时 [AccelStats.zeroToHundredMs] 为 null，界面不显示该项，
///   不把 GPS 噪声、半程起步或未达 100 km/h 的行程算成百公里加速。
/// - 算出时也必须标注“基于 1Hz GPS + IMU 估算，非专业计时”。
/// 最大加速 / 最大减速取 longG 的最大正值 / 最小负值（绝对值最大的减速）。
/// 数据全部来自传入的 TrackPoint；点数不足显示“暂无”，不画假曲线。
/// 提醒：longG 仅在标定后为车身坐标；若传入点全部未标定，界面会
/// 额外显示“未标定”提示，但不擅自丢弃数据（是否采用由调用方决定）。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

const double _kG = 9.81;
const double _kHundredMs = 100 / 3.6; // 27.78 m/s

const Color _kRed = Color(0xFFE10600);
const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);

/// 加速度统计结果（纯数据，可单测）。
class AccelStats {
  /// 最大加速（g，正值）；无数据时为 null。
  final double? maxAccelG;

  /// 最大减速（g，负值，取 longG 最小值）；无数据时为 null。
  final double? maxDecelG;

  /// 0-100 km/h 用时（ms）；不满足门控时为 null。
  final int? zeroToHundredMs;

  /// 是否满足 0-100 门控。
  final bool zeroToHundredEligible;

  /// 门控未满足时的原因（供界面或日志用，不编造用时）。
  final String zeroToHundredReason;

  /// 传入点中是否有标定点。
  final bool hasCalibratedPoint;

  const AccelStats({
    required this.maxAccelG,
    required this.maxDecelG,
    required this.zeroToHundredMs,
    required this.zeroToHundredEligible,
    required this.zeroToHundredReason,
    required this.hasCalibratedPoint,
  });

  double? get maxAccelMs2 =>
      maxAccelG == null ? null : maxAccelG! * _kG;
  double? get maxDecelMs2 =>
      maxDecelG == null ? null : maxDecelG! * _kG;
}

/// 由轨迹点算加速度统计。起步判定与插值规则见文件头注释。
AccelStats computeAccelStats(List<TrackPoint> points) {
  final hasCal = points.any((p) => p.calibrated);
  if (points.isEmpty) {
    return const AccelStats(
      maxAccelG: null,
      maxDecelG: null,
      zeroToHundredMs: null,
      zeroToHundredEligible: false,
      zeroToHundredReason: '暂无轨迹数据',
      hasCalibratedPoint: false,
    );
  }
  final maxAccel = points.map((p) => p.longG).reduce(math.max);
  final maxDecel = points.map((p) => p.longG).reduce(math.min);
  int? launchIdx;
  for (var i = 0; i < points.length; i++) {
    if (points[i].speed <= 0.5) {
      launchIdx = i;
      break;
    }
  }
  if (launchIdx == null) {
    return AccelStats(
      maxAccelG: maxAccel,
      maxDecelG: maxDecel,
      zeroToHundredMs: null,
      zeroToHundredEligible: false,
      zeroToHundredReason: '未找到从静止起步的点（行程开始时已在行驶）',
      hasCalibratedPoint: hasCal,
    );
  }
  int? reachIdx;
  for (var i = launchIdx + 1; i < points.length; i++) {
    if (points[i].speed >= _kHundredMs) {
      reachIdx = i;
      break;
    }
  }
  if (reachIdx == null) {
    return AccelStats(
      maxAccelG: maxAccel,
      maxDecelG: maxDecel,
      zeroToHundredMs: null,
      zeroToHundredEligible: false,
      zeroToHundredReason: '起步后未达到 100 km/h',
      hasCalibratedPoint: hasCal,
    );
  }
  // 线性插值：上一采样点 → 达标点之间恰好 100 km/h 的时刻。
  final prev = points[reachIdx - 1];
  final cur = points[reachIdx];
  final frac = (cur.speed - prev.speed).abs() < 1e-9
      ? 1.0
      : ((_kHundredMs - prev.speed) / (cur.speed - prev.speed))
          .clamp(0.0, 1.0);
  final crossMs =
      prev.timeMs + ((cur.timeMs - prev.timeMs) * frac).round();
  return AccelStats(
    maxAccelG: maxAccel,
    maxDecelG: maxDecel,
    zeroToHundredMs: crossMs - points[launchIdx].timeMs,
    zeroToHundredEligible: true,
    zeroToHundredReason: '',
    hasCalibratedPoint: hasCal,
  );
}

String _fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

String _fmtSec(int ms) => '${(ms / 1000).toStringAsFixed(2)} 秒';

/// 加速度-时间曲线：纵轴 longG（g），点击 / 拖动显示该点时刻与加速度
/// （同时显示 g 与 m/s²）。点数 < 2 显示“暂无”。
class AccelTimeChart extends StatefulWidget {
  final List<TrackPoint> points;
  final ValueChanged<int>? onPointSelected;
  const AccelTimeChart({super.key, required this.points, this.onPointSelected});

  @override
  State<AccelTimeChart> createState() => _AccelTimeChartState();
}

class _AccelTimeChartState extends State<AccelTimeChart> {
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
    if (pts.length < 2) {
      return const Text('暂无',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    }
    final sel = _sel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                painter: _AccelTimePainter(points: pts, selected: sel)),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(
        sel != null
            ? '${_fmtClock(pts[sel].timeMs)} · 纵向 '
                '${pts[sel].longG.toStringAsFixed(2)}g '
                '（${(pts[sel].longG * _kG).toStringAsFixed(2)} m/s²）'
            : '点击或拖动曲线查看该点加速度',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ]);
  }
}

class _AccelTimePainter extends CustomPainter {
  final List<TrackPoint> points;
  final int? selected;
  const _AccelTimePainter({required this.points, this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 52.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    var lo = points.map((p) => p.longG).reduce(math.min);
    var hi = points.map((p) => p.longG).reduce(math.max);
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
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
          text: TextSpan(text: '${v.toStringAsFixed(2)}g', style: textStyle),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(2, yy - 6));
    }
    canvas.drawLine(Offset(padL, y(0)), Offset(padL + w, y(0)),
        Paint()..color = Colors.white.withValues(alpha: 0.35));
    final path = Path()..moveTo(x(0), y(points[0].longG));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i].longG));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = _kRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    if (selected != null) {
      final sx = x(selected!);
      canvas.drawLine(Offset(sx, padT), Offset(sx, padT + h),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
      canvas.drawCircle(Offset(sx, y(points[selected!].longG)), 5,
          Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_AccelTimePainter old) =>
      old.points != points || old.selected != selected;
}

/// 加速度-速度散点：横轴速度（km/h），纵轴纵向加速度（g），
/// 每点为一秒轨迹点；散点不连线，避免暗示速度与加速度是单值函数。
/// 点数 < 2 显示“暂无”。
class AccelSpeedChart extends StatelessWidget {
  final List<TrackPoint> points;
  const AccelSpeedChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const Text('暂无',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    }
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: CustomPaint(painter: _AccelScatterPainter(points: points)),
    );
  }
}

class _AccelScatterPainter extends CustomPainter {
  final List<TrackPoint> points;
  const _AccelScatterPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 52.0, padR = 10.0, padT = 10.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final maxV = points.map((p) => p.speed * 3.6).reduce(math.max);
    var lo = points.map((p) => p.longG).reduce(math.min);
    var hi = points.map((p) => p.longG).reduce(math.max);
    lo = math.min(lo, 0);
    hi = math.max(hi, 0);
    if ((hi - lo).abs() < 1e-9) hi = lo + 1;
    final spanV = maxV <= 0 ? 1 : maxV;
    double x(TrackPoint p) => padL + w * (p.speed * 3.6) / spanV;
    double y(TrackPoint p) => padT + h * (1 - (p.longG - lo) / (hi - lo));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final yy = padT + h * k / 4;
      canvas.drawLine(Offset(padL, yy), Offset(padL + w, yy), grid);
    }
    for (final p in points) {
      canvas.drawCircle(Offset(x(p), y(p)), 3.5, Paint()..color = _kRed);
    }
  }

  @override
  bool shouldRepaint(_AccelScatterPainter old) => old.points != points;
}

/// 加速度组合卡：最大加速 / 最大减速（g 与 m/s² 双显示）、
/// 加速度-时间曲线、加速度-速度散点、门控通过时才显示的 0-100 用时。
class AccelSection extends StatelessWidget {
  final List<TrackPoint> points;
  final ValueChanged<int>? onPointSelected;
  const AccelSection({super.key, required this.points, this.onPointSelected});

  @override
  Widget build(BuildContext context) {
    final stats = computeAccelStats(points);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('加速度',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (points.isEmpty)
          const Text('暂无',
              style: TextStyle(color: Colors.white54, fontSize: 13))
        else ...[
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat(
                '最大加速',
                stats.maxAccelG == null
                    ? '暂无'
                    : '${stats.maxAccelG!.toStringAsFixed(2)}g · '
                        '${stats.maxAccelMs2!.toStringAsFixed(2)} m/s²'),
            _stat(
                '最大减速',
                stats.maxDecelG == null
                    ? '暂无'
                    : '${stats.maxDecelG!.toStringAsFixed(2)}g · '
                        '${stats.maxDecelMs2!.toStringAsFixed(2)} m/s²'),
            if (stats.zeroToHundredEligible && stats.zeroToHundredMs != null)
              _stat('0-100 km/h', _fmtSec(stats.zeroToHundredMs!)),
          ]),
          if (stats.zeroToHundredEligible)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('估算值，非专业计时',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          if (!stats.hasCalibratedPoint)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('未标定：纵向加速度仅供参考',
                  style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          const Text('加速度 - 时间',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          AccelTimeChart(points: points, onPointSelected: onPointSelected),
          const SizedBox(height: 16),
          const Text('加速度 - 速度',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          AccelSpeedChart(points: points),
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
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
    ]);
  }
}
