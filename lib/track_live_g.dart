/// 赛道面板实时 G 值行（职业计时页内，新增文件）。
///
/// 样式按专业赛道软件的做法：
/// G 圆（摩擦圆 / G-ball）+ 实时纵向/横向 G 数值 + 本节峰值，深色
/// HUD 底子与职业计时页一致。圆点位置 = 当前合成 G 矢量（与数值
/// 同源），圆点与数值同步刷新；峰值以坐标轴上的刻度 + 文字两种
/// 形式给出（见 [_GVectorCircle] 与 [TrackLiveGRow]）。
///
/// 数据链路（复用已有链路，不另起传感器采集）：
/// - 纵向/横向 G 取调用方传入的 [LiveGSource]，接线时应指向
///   Recorder.smoothLong / smoothLat——与街道页 G 值显示同一来源，
///   两处数值一致。smooth 是 onSensor 里对原始 lg/tg 做 0.35 系数
///   指数平滑的结果，不是另算的一套 G。
/// - 峰值取 Recorder.tripPeakLong / tripPeakLat（本节峰值，自开录
///   起的原始 lg/tg 极值）。注意：峰值是原始采样极值，实时值是平
///   滑值，两者口径不同是既有数据的本来面貌，不在此处互相折算。
/// - 六轴 IMU 链路（见 MainActivity.kt 与 recorder.dart）：
///   原生同时注册 TYPE_LINEAR_ACCELERATION（已扣重力的线加速度，
///   Android 内部融合）、TYPE_ROTATION_VECTOR（姿态：加速度计 +
///   陀螺仪 + 磁力计的系统融合输出）、TYPE_GYROSCOPE（原始角速度，
///   本次补进透传，见下）与 TYPE_PRESSURE；Dart 侧 onSensor 用
///   rotation vector 四元数把线加速度转到世界系，再投影到标定好的
///   水平车头/右侧方向上得到 lg/tg——重力分量一是被线加速度传感
///   器本身扣掉，二是水平投影不再含垂直分量。原始陀螺仪值
///   （gx/gy/gz，rad/s，机体系）只存入 Recorder.curGyroX/Y/Z 供
///   诊断与后续融合精修，不参与 lg/tg 计算：姿态仍走经过验证的
///   rotation vector，不在此处自造一套 Dart 端融合算法替代它。
/// - 校准（既有机制，复用不改）：G 值只在“标定车头方向”完成后
///   有效（未标定时 onSensor 置 curLongG/curLatG 为 0，本行显示
///   “未标定”）；静止零偏（recordZeroBias）只记录与展示，按既有
///   设计不参与 G 值计算。手机是消费级 IMU：数值是指示性的，
///   不包装成赛车级精度；安装不牢、路面振动、rotation vector
///   航向漂移都会让数值抖动或漂移。
///
/// 刷新方式：[TrackLiveGRow] 内部用 [ListenableBuilder] 只订阅
/// [LiveGSource.listenable]（接线时即 Recorder，其通知经
/// _throttledNotify 节流到 100ms），只重建 G 值行本身，不重建
/// 整个赛道页、不干扰大计时 ticker；不另起定时器。
///
/// 正负约定（与既有代码一致）：
/// - 纵向 longG：正 = 加速（logic.dart 里 longG > harshAccel 即
///   急加速），负 = 刹车（longG < harshBrake 即急刹车）。
/// - 横向 latG：正 = 右（向右的侧向加速度，即右转时为正），
///   负 = 左。推导：latG 是世界系加速度在标定右侧方向上的投影
///   （onSensor 里 tg = aw·r，r 为右侧单位矢量）；右转时向心
///   加速度指向右侧，投影为正；与街道页 GCirlce 圆点方向一致
///   （latG 为正时圆点向右），亦与倾角符号约定一致（roll > 0
///   为右倾）。代码库里没有对 latG 本身写过左/右文字标签，
///   上述方向以投影定义为准，圆点方向与数值符号互相印证。

import 'package:flutter/material.dart';

/// 实时 G 值数据源：一个 [Listenable]（通知时只刷新 G 值行）+
/// 读取当前值的回调。调用方（main.dart 接线时）应传 Recorder
/// 本身作 listenable，longG/latG 取 smoothLong/smoothLat，
/// peakLong/peakLat 取 tripPeakLong/tripPeakLat，calibrated 取
/// rec.calibrated；peak 回调不传时峰值行不显示。
class LiveGSource {
  final Listenable listenable;
  final double Function() longG;
  final double Function() latG;
  final bool Function()? calibrated;
  final double Function()? peakLong;
  final double Function()? peakLat;

  const LiveGSource({
    required this.listenable,
    required this.longG,
    required this.latG,
    this.calibrated,
    this.peakLong,
    this.peakLat,
  });
}

/// 赛道面板内的实时 G 值行：G 圆 + 纵向/横向数值 + 本节峰值。
/// 未标定时只显示“未标定”，不编数字。
class TrackLiveGRow extends StatelessWidget {
  final LiveGSource source;
  const TrackLiveGRow({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: source.listenable,
      builder: (context, _) {
        if (!(source.calibrated?.call() ?? true)) {
          return const Text(
            'G 值：未标定',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          );
        }
        final lo = source.longG();
        final la = source.latG();
        final peakLo = source.peakLong?.call();
        final peakLa = source.peakLat?.call();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TrackGVectorCircle(
              longG: lo,
              latG: la,
              peakLong: peakLo,
              peakLat: peakLa,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 横屏窄栏：两个 G 数值（17 号粗体）并排在 210 宽内
                  // 会溢出，各包 Flexible + scaleDown，极窄/大字体
                  // 时数字等比缩小不断行、不溢出（与大计时同款处理）。
                  Row(
                    children: [
                      const Text('纵向',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${formatSignedG(lo)}g',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text('横向',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${formatSignedG(la)}g',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (peakLo != null && peakLa != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '峰值 纵向 ${formatSignedG(peakLo)}g · '
                      '横向 ${formatSignedG(peakLa)}g',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    '纵向 +加速 -刹车 · 横向 +右 -左',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 带正负号的 G 值文本：正显 '+'，负显 '-'，保留两位小数。
/// 与 LapTimer.formatDelta 的符号风格一致（'+'/'-' ASCII）。
String formatSignedG(double v) =>
    '${v < 0 ? '-' : '+'}${v.abs().toStringAsFixed(2)}';

/// G 圆（摩擦圆 / G-ball）：圆点 = 当前合成 G 矢量，刻度环 =
/// 0.5g / 1.0g（满量程 1.5g，超量程的圆点钳制在圆边上，数值
/// 本身不受钳制）；坐标轴上的短刻度 = 本节峰值在该轴上的位置
/// （纵向峰值画在竖轴上下、横向峰值画在横轴左右，峰值是分轴
/// 极值、不同时出现，故不画一个合成的“峰值圆点”冒充某时刻
/// 真实出现过的矢量）。
class TrackGVectorCircle extends StatelessWidget {
  final double longG;
  final double latG;
  final double? peakLong;
  final double? peakLat;

  /// 满量程：圆边 = 1.5g。
  static const double fullScaleG = 1.5;

  const TrackGVectorCircle({
    super.key,
    required this.longG,
    required this.latG,
    this.peakLong,
    this.peakLat,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(88, 88),
      painter: _GVectorCirclePainter(
        longG: longG,
        latG: latG,
        peakLong: peakLong,
        peakLat: peakLat,
      ),
    );
  }
}

class _GVectorCirclePainter extends CustomPainter {
  final double longG;
  final double latG;
  final double? peakLong;
  final double? peakLat;

  _GVectorCirclePainter({
    required this.longG,
    required this.latG,
    this.peakLong,
    this.peakLat,
  });

  double _clampG(double v) => v.clamp(-TrackGVectorCircle.fullScaleG,
      TrackGVectorCircle.fullScaleG);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    // 外圈 + 0.5g / 1.0g 刻度环 + 十字线。
    canvas.drawCircle(c, r - 1, ringPaint);
    canvas.drawCircle(c, (r - 1) / 3, ringPaint);
    canvas.drawCircle(c, (r - 1) * 2 / 3, ringPaint);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), crossPaint);
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), crossPaint);
    // 峰值刻度：分轴画在坐标轴上（纵向竖轴、横向横轴），
    // 超量程同样钳制在圆边上。
    final peakPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    void peakTick(double along, bool vertical) {
      final d = _clampG(along) / TrackGVectorCircle.fullScaleG * (r - 1);
      if (vertical) {
        final y = c.dy - d;
        canvas.drawLine(Offset(c.dx - 4, y), Offset(c.dx + 4, y), peakPaint);
      } else {
        final x = c.dx + d;
        canvas.drawLine(Offset(x, c.dy - 4), Offset(x, c.dy + 4), peakPaint);
      }
    }

    if (peakLong != null) {
      // 纵向峰值是单值极值（tripPeak 取绝对值最大者，本身带符号）：
      // 只在符号对应的一侧画一道刻度。
      peakTick(peakLong!, true);
    }
    if (peakLat != null) {
      peakTick(peakLat!, false);
    }
    // 当前矢量圆点：横向 → x（右正），纵向 → y（上正，即加速向上），
    // 与街道页 GCirlce 的圆点方向约定一致。
    final dx = _clampG(latG) / TrackGVectorCircle.fullScaleG * (r - 1);
    final dy = _clampG(longG) / TrackGVectorCircle.fullScaleG * (r - 1);
    final dot = Offset(
      (c.dx + dx).clamp(0.0, size.width),
      (c.dy - dy).clamp(0.0, size.height),
    );
    canvas.drawCircle(
      dot,
      6,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      dot,
      6,
      Paint()
        ..color = const Color(0xFFE10600)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_GVectorCirclePainter old) =>
      old.longG != longG ||
      old.latG != latG ||
      old.peakLong != peakLong ||
      old.peakLat != peakLat;
}
