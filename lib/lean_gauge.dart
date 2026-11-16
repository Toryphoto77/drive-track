/// 压弯倾角可视化（只给摩托用）。
///
/// v1.6.0：
/// - 倾角只服务摩托，街道记录页与赛道横屏仪表都只在摩托模式显示；
///   其他车型不再出现倾角读数。
/// - 可视化加强：大号度数 + 左/右倾文字 + ±60° 刻度条（15° 一格、
///   30° 高亮刻度、中心正直线、从中线到当前倾角的彩色填充、带光圈圆点），
///   比原来一根细条 + 小圆点更容易在骑行中一眼读出压弯深度。
/// - 颜色沿用既有压弯图表：左倾青（0xFF38BDF8）、右倾红（0xFFE10600）。
/// - 未标定显示“未标定”；degraded 标“信号弱”；unreliable 只显示“—”，
///   绝不编数字。
import 'package:flutter/material.dart';

import 'card_style.dart';
import 'lean_estimator.dart';

const Color _kLeft = Color(0xFF38BDF8); // 左倾
const Color _kRight = Color(0xFFE10600); // 右倾

/// 倾角条：横向 ±maxDeg 刻度，圆点钳制在两端，数值本身不钳制。
class LeanBar extends StatelessWidget {
  const LeanBar({
    super.key,
    required this.leanDeg,
    this.height = 34,
    this.maxDeg = 60,
    this.compact = false,
  });

  final double leanDeg;
  final double height;
  final double maxDeg;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LeanBarPainter(
          lean: leanDeg,
          maxDeg: maxDeg,
          compact: compact,
        ),
      ),
    );
  }
}

class _LeanBarPainter extends CustomPainter {
  _LeanBarPainter({
    required this.lean,
    required this.maxDeg,
    required this.compact,
  });

  final double lean;
  final double maxDeg;
  final bool compact;

  double _xFor(double deg, double width) =>
      (deg / maxDeg).clamp(-1.0, 1.0).toDouble() * (width / 2) + width / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackH = compact ? 6.0 : 8.0;

    // 底槽
    final track = Rect.fromLTWH(0, cy - trackH / 2, size.width, trackH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, Radius.circular(trackH / 2)),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );

    // 刻度：15° 一格，30° / 60° 长刻度
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = 1;
    for (var d = -maxDeg; d <= maxDeg; d += 15) {
      if (d == 0) continue;
      final x = _xFor(d.toDouble(), size.width);
      final h = d.abs() % 30 == 0 ? 10.0 : 6.0;
      canvas.drawLine(
        Offset(x, cy - h / 2 - 2),
        Offset(x, cy + h / 2 + 2),
        tickPaint,
      );
    }

    // 中心（正直）线
    canvas.drawLine(
      Offset(size.width / 2, cy - trackH / 2 - 4),
      Offset(size.width / 2, cy + trackH / 2 + 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
    );

    final l = lean.clamp(-maxDeg, maxDeg).toDouble();
    final x0 = _xFor(0, size.width);
    final x = _xFor(l, size.width);

    // 从中线到当前倾角的填充
    if (l.abs() > 0.5) {
      final rect = Rect.fromLTRB(
        x0 < x ? x0 : x,
        cy - trackH / 2,
        x0 < x ? x : x0,
        cy + trackH / 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(trackH / 2)),
        Paint()..color = (l > 0 ? _kRight : _kLeft).withValues(alpha: 0.85),
      );
    }

    // 圆点 + 光圈
    final color = l > 1
        ? _kRight
        : l < -1
            ? _kLeft
            : Colors.white;
    final dotR = compact ? 4.5 : 6.0;
    canvas.drawCircle(
      Offset(x, cy),
      dotR + (compact ? 1.5 : 2.5),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    canvas.drawCircle(Offset(x, cy), dotR, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LeanBarPainter old) =>
      old.lean != lean || old.maxDeg != maxDeg || old.compact != compact;
}

/// 街道记录页的倾角卡（摩托模式专享）。
class LeanAngleReadout extends StatelessWidget {
  const LeanAngleReadout({
    super.key,
    required this.leanDeg,
    required this.quality,
    required this.calibrated,
  });

  final double leanDeg;
  final LeanQuality quality;
  final bool calibrated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CardStyle.innerCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CardStyle.borderColor),
      ),
      child: _body(),
    );
  }

  Widget _body() {
    // 未标定：说明怎么标定，不画假刻度。
    if (!calibrated) {
      return Row(
        children: const [
          Icon(Icons.screen_rotation_alt, size: 16, color: Colors.white38),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '倾角：未标定。固定手机后做一次水平标定即可读数',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      );
    }
    if (quality == LeanQuality.unreliable) {
      return Row(
        children: const [
          Icon(Icons.two_wheeler, size: 16, color: Colors.white38),
          SizedBox(width: 8),
          Text('倾角：—', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      );
    }
    final lean = leanDeg;
    final side = lean > 1
        ? '右倾'
        : lean < -1
            ? '左倾'
            : '正直';
    final color = lean > 1
        ? _kRight
        : lean < -1
            ? _kLeft
            : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.two_wheeler, size: 16, color: Colors.white54),
            const SizedBox(width: 6),
            const Text(
              '压弯倾角',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Spacer(),
            if (quality == LeanQuality.degraded)
              const Text(
                '信号弱',
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              lean.abs().toStringAsFixed(0),
              style: TextStyle(
                color: color,
                fontSize: 42,
                height: 1.0,
                fontWeight: FontWeight.w800,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '°',
                style: TextStyle(color: color, fontSize: 18),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                side,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                '${lean > 0 ? '+' : ''}${lean.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LeanBar(leanDeg: lean),
        const SizedBox(height: 4),
        const Row(
          children: [
            Text('左 60°', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Spacer(),
            Text('0°', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Spacer(),
            Text('右 60°', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
