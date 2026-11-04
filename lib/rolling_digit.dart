import 'package:flutter/material.dart';

/// 视频对齐的滚动数字：用户视频逐帧分析结论（60fps 抽帧 +
/// 数字列逐帧对照）——
/// - 不变位全程静止（分钟位 60 帧质心分毫不差）；
/// - 变化位瞬间换成新数字，无滑动、无缓动、无重影/拖影；
/// - “滚动感”来自数据本身的高刷新率（末位几乎每帧都变），
///   不是滑动动画。
/// 因此本组件不再做 250ms easeOut 滑动：每位仍是一条 0–9 竖条
/// （位身份按“从右数第几位”键控，进位时右边位不重建、不乱跳），
/// 但位置随值瞬间到位，不经过中间帧——滑动反而会在换位时同时
/// 露出两个半截数字，视频里从不出现。`:`、`.`、`-` 等非数字
/// 字符静态渲染。
class RollingNumberText extends StatelessWidget {
  final String value;
  final TextStyle style;
  const RollingNumberText({super.key, required this.value, required this.style});

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < value.length; i++)
          if (_isDigit(value[i]))
            _RollingDigit(
              key: ValueKey('d${value.length - 1 - i}'),
              digit: int.parse(value[i]),
              style: style,
            )
          else
            Text(value[i], style: style),
      ],
    );
  }
}

class _RollingDigit extends StatelessWidget {
  final int digit;
  final TextStyle style;
  const _RollingDigit({super.key, required this.digit, required this.style});

  @override
  Widget build(BuildContext context) {
    final probe = TextPainter(
      text: TextSpan(text: '8', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final h = probe.height;
    final w = probe.width;
    return ClipRect(
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            // 瞬间到位：视频里变化位是干净切换，不用 AnimatedPositioned。
            Positioned(
              top: -digit * h,
              left: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var d = 0; d < 10; d++) Text('$d', style: style),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
