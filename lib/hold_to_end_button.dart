import 'package:flutter/material.dart';

/// 长按结束：按住时红色填充 + 圆环进度，松手取消，按满才结束行程。
class HoldToEndButton extends StatefulWidget {
  const HoldToEndButton({
    super.key,
    required this.label,
    required this.onComplete,
    this.height = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.fontSize = 14,
    this.holdDuration = const Duration(milliseconds: 700),
  });

  final String label;
  final VoidCallback onComplete;
  final double height;
  final BorderRadius borderRadius;
  final double fontSize;
  final Duration holdDuration;

  @override
  State<HoldToEndButton> createState() => _HoldToEndButtonState();
}

class _HoldToEndButtonState extends State<HoldToEndButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addListener(_finishIfFull)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishIfFull();
      });
  }

  void _finishIfFull() {
    if (_fired || _hold.value < 1) return;
    _fired = true;
    widget.onComplete();
  }

  @override
  void didUpdateWidget(covariant HoldToEndButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdDuration != widget.holdDuration) {
      _hold.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    _fired = false;
    _hold.forward(from: 0);
  }

  void _cancel() {
    if (_hold.value >= 1 || _hold.status == AnimationStatus.completed) {
      _finishIfFull();
      return;
    }
    _fired = false;
    _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: AnimatedBuilder(
        animation: _hold,
        builder: (_, __) {
          final p = _hold.value;
          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: SizedBox(
              height: widget.height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF7F1D1D)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: p,
                      heightFactor: 1,
                      child: const ColoredBox(color: Color(0xFFE10600)),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            value: p,
                            strokeWidth: 2.4,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: widget.fontSize,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
