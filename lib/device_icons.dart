import 'package:flutter/material.dart';

/// 设备线性图标（v1.7.x）：运动相机 / 外接 GPS / OBD / 视频同步，按参考图
/// 的实物轮廓手绘，单色描边、无外框。只做外观还原，不引入图片资源。
enum DeviceGlyphKind { actionCam, gpsModule, obd, video }

class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({
    super.key,
    required this.kind,
    this.size = 24,
    this.color = Colors.white70,
  });

  final DeviceGlyphKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DeviceGlyphPainter(kind, color)),
    );
  }
}

class _DeviceGlyphPainter extends CustomPainter {
  _DeviceGlyphPainter(this.kind, this.color);

  final DeviceGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width, size.height);
    switch (kind) {
      case DeviceGlyphKind.actionCam:
        _paintActionCam(canvas, paint);
        break;
      case DeviceGlyphKind.gpsModule:
        _paintGps(canvas, paint);
        break;
      case DeviceGlyphKind.obd:
        _paintObd(canvas, paint);
        break;
      case DeviceGlyphKind.video:
        _paintVideo(canvas, paint);
        break;
    }
    canvas.restore();
  }

  /// 运动相机：方形机身 + 左侧镜头圆 + 顶部小提手。
  void _paintActionCam(Canvas canvas, Paint paint) {
    final body = RRect.fromLTRBR(0.10, 0.30, 0.90, 0.82, const Radius.circular(0.12));
    canvas.drawRRect(body, paint);
    canvas.drawCircle(const Offset(0.36, 0.56), 0.14, paint);
    // 顶部提手
    final handle = Path()
      ..moveTo(0.26, 0.30)
      ..lineTo(0.26, 0.22)
      ..quadraticBezierTo(0.26, 0.18, 0.32, 0.18)
      ..lineTo(0.52, 0.18)
      ..quadraticBezierTo(0.58, 0.18, 0.58, 0.22)
      ..lineTo(0.58, 0.30);
    canvas.drawPath(handle, paint);
    // 右侧录制指示灯
    canvas.drawCircle(const Offset(0.74, 0.56), 0.05, paint);
  }

  /// 外接 GPS：竖长机身 + 右侧两道信号弧。
  void _paintGps(Canvas canvas, Paint paint) {
    final body = RRect.fromLTRBR(0.18, 0.26, 0.52, 0.84, const Radius.circular(0.10));
    canvas.drawRRect(body, paint);
    canvas.drawCircle(const Offset(0.35, 0.62), 0.06, paint);
    // 信号弧（以机身右侧为圆心，向外扩散）
    const center = Offset(0.54, 0.46);
    final rect1 = Rect.fromCircle(center: center, radius: 0.16);
    final rect2 = Rect.fromCircle(center: center, radius: 0.30);
    canvas.drawArc(rect1, -0.9, 1.8, false, paint);
    canvas.drawArc(rect2, -0.9, 1.8, false, paint);
    // 发射点
    canvas.drawCircle(center, 0.04, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  /// OBD：梯形接口 + 内部三支引脚。
  void _paintObd(Canvas canvas, Paint paint) {
    final shape = Path()
      ..moveTo(0.16, 0.40)
      ..lineTo(0.84, 0.40)
      ..lineTo(0.72, 0.72)
      ..lineTo(0.28, 0.72)
      ..close();
    canvas.drawPath(shape, paint);
    for (final x in <double>[0.38, 0.50, 0.62]) {
      canvas.drawLine(Offset(x, 0.47), Offset(x, 0.63), paint);
    }
  }

  /// 视频同步：圆角画框 + 播放三角 + 右侧胶片齿。
  void _paintVideo(Canvas canvas, Paint paint) {
    final frame =
        RRect.fromLTRBR(0.10, 0.26, 0.74, 0.78, const Radius.circular(0.10));
    canvas.drawRRect(frame, paint);
    final play = Path()
      ..moveTo(0.36, 0.40)
      ..lineTo(0.56, 0.52)
      ..lineTo(0.36, 0.64)
      ..close();
    canvas.drawPath(play, paint);
    for (final y in <double>[0.34, 0.52, 0.70]) {
      canvas.drawLine(Offset(0.80, y), Offset(0.90, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DeviceGlyphPainter old) =>
      old.kind != kind || old.color != color;
}
