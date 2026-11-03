import 'package:flutter/material.dart';

/// 黑白格小旗（v0.1.5 新增共享组件）。
///
/// 药丸开关的赛道侧动画与开始记录大方块的右上角角标共用同一
/// 画法，不各自画一套，避免两处格子对不齐。只画格面，不带旗杆：
/// 4 列 × 3 行，左上角为黑格，黑白交错。
class CheckeredFlag extends StatelessWidget {
  final double width;
  final double height;

  const CheckeredFlag({super.key, this.width = 22, this.height = 15});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _CheckeredFlagPainter(),
    );
  }
}

class _CheckeredFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cols = 4;
    const rows = 3;
    final cw = size.width / cols;
    final ch = size.height / rows;
    final black = Paint()..color = Colors.black;
    final white = Paint()..color = Colors.white;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cw, r * ch, cw, ch),
          (r + c) % 2 == 0 ? black : white,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
