import 'package:flutter/material.dart';

/// v0.1.1 按钮动画统一封装：全 App 按压反馈只用一种——水波纹（InkWell）。
///
/// 之所以选水波纹而不是按压缩放：Material 按钮（Filled/Outlined/TextButton、
/// ListTile、IconButton）本身就是水波纹；若再给自定义可点元素加缩放，
/// 两种反馈会混用。RippleTap 把原来裸 GestureDetector 的可点元素
/// （开始大钮、模式图标、天气条、G 圆、长按结束）全部改成同一 InkWell，
/// 与原生按钮、抽屉项、详情事件项、授权页次要入口的水波纹完全一致。
/// 另带 350ms 同实例防抖：快速连点只触发一次，防动画叠加与页面叠跳。
/// 注意：模式图标的选中放大（AnimatedScale 1.25）是选中态，不是按压反馈，
/// 与本封装的水波纹不冲突。
class RippleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool circular;
  final BorderRadius? borderRadius;
  const RippleTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.circular = false,
    this.borderRadius,
  });

  @override
  State<RippleTap> createState() => _RippleTapState();
}

class _RippleTapState extends State<RippleTap> {
  DateTime? _lastTap;

  bool get _debounced {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      return true;
    }
    _lastTap = now;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: widget.circular ? const CircleBorder() : null,
        borderRadius: widget.circular
            ? null
            : (widget.borderRadius ?? BorderRadius.circular(12)),
        splashColor: accent.withValues(alpha: 0.25),
        highlightColor: accent.withValues(alpha: 0.08),
        onTap: widget.onTap == null
            ? null
            : () {
                if (_debounced) return;
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (_debounced) return;
                widget.onLongPress!();
              },
        child: widget.child,
      ),
    );
  }
}
