/// 压弯倾角实时读数（记录页 HUD，与 G 值显示并排的风格）。
///
/// 大号度数 + 左倾 / 右倾 + 一条横向倾角条（中线为正直，圆点随倾角
/// 左右移动，满刻度 ±60°，超量程时圆点钳制在条边、数值本身不受钳制）。
/// 颜色与既有压弯图表一致：左倾青（0xFF38BDF8）、右倾红（0xFFE10600）。
/// 未标定时显示“未标定”；可信度 degraded 时数值旁标“信号弱”；
/// unreliable 时只显示“—”，不编数字。
import 'package:flutter/material.dart';

import 'card_style.dart';
import 'lean_estimator.dart';

const Color _kLeft = Color(0xFF38BDF8); // 左倾
const Color _kRight = Color(0xFFE10600); // 右倾

class LeanAngleReadout extends StatelessWidget {
  final double leanDeg;
  final LeanQuality quality;
  final bool calibrated;

  const LeanAngleReadout({
    super.key,
    required this.leanDeg,
    required this.quality,
    required this.calibrated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CardStyle.innerCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CardStyle.borderColor),
      ),
      child: _body(),
    );
  }

  Widget _body() {
    if (!calibrated) {
      return const Text('倾角：未标定',
          style: TextStyle(color: Colors.white54, fontSize: 13));
    }
    if (quality == LeanQuality.unreliable) {
      return const Text('倾角：—',
          style: TextStyle(color: Colors.white54, fontSize: 13));
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
    // 满刻度 ±60°，圆点钳制在条边。
    final x = (lean / 60).clamp(-1.0, 1.0);
    return Row(children: [
      const Text('左',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(width: 6),
      Expanded(
        child: SizedBox(
          height: 18,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // 中线（正直）。
            Container(width: 2, height: 14, color: Colors.white38),
            Align(
              alignment: Alignment(x, 0),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 6),
      const Text('右',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(width: 12),
      Text('${lean.abs().toStringAsFixed(0)}°',
          style: TextStyle(
              color: color, fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(width: 6),
      Text(side,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      if (quality == LeanQuality.degraded) ...[
        const SizedBox(width: 8),
        const Text('信号弱',
            style: TextStyle(color: Colors.orange, fontSize: 11)),
      ],
    ]);
  }
}
