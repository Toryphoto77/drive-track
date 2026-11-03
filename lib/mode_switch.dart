import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'checkered_flag.dart';

/// 街道 / 赛道分段控件（v0.1.5 重做：药丸开关 + 方格旗动画）。
///
/// 布局约定（v0.1.5 起，不要再放回旧位置）：
/// 首页正常流里，放在标定与开始记录两个大方块的正上方、紧贴
/// 大方块（_buildModePages 里，PageView 之后、BigActionButtons
/// 之前），与大方块的左右边距一致；街道为默认。
/// 骑行模式下调用方不渲染本组件（赛道选择对骑行无意义）。
///
/// - 药丸开关：圆角胶囊分段控件，高 48，左“街道”右“赛道”，
///   滑块用 AnimatedAlign 做 200ms easeOutCubic 滑动，选中态主题色；
///   行程中禁用切换（[enabled]=false 时置灰且不触发回调）。
/// - 方格旗动画：仅当 surface 从街道切到赛道时播一次——黑白格
///   旗面从小到大弹入并轻微挥动，约 450ms，不循环、不常驻闪烁；
///   切回街道时旗面淡出（200ms）。只播一次的机制：动画由
///   didUpdateWidget 里“旧值街道 → 新值赛道”这一变化触发，
///   build 里不启动任何动画；反复渲染不会重播。初始即为赛道态
///   时旗面静态显示，不播入场动画（那不是一次“切换”）。
/// - 赛道选择器：赛道态下展开在分段控件正下方（间距 8），由
///   调用方以 [trackSelector] 传入，本组件只负责切换本身。

/// 街道 / 赛道：一段式，不与汽车 / 摩托 / 骑行（TripMode）混淆。
enum DriveSurface { street, track }

extension DriveSurfaceLabel on DriveSurface {
  String get label => switch (this) {
        DriveSurface.street => '街道',
        DriveSurface.track => '赛道',
      };
}

/// “街道 | 赛道”药丸开关（不含赛道选择器本身）。
class ModeSwitch extends StatefulWidget {
  final DriveSurface surface;
  final ValueChanged<DriveSurface>? onSurfaceChanged;

  /// false = 录制中，禁用切换（置灰，不触发回调）。
  final bool enabled;
  final Color? accentColor;

  const ModeSwitch({
    super.key,
    required this.surface,
    required this.onSurfaceChanged,
    this.enabled = true,
    this.accentColor,
  });

  @override
  State<ModeSwitch> createState() => _ModeSwitchState();
}

class _ModeSwitchState extends State<ModeSwitch>
    with SingleTickerProviderStateMixin {
  /// 方格旗入场动画：450ms，弹入 + 衰减挥动，只由切换触发一次。
  late final AnimationController _flagAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  /// 旗面是否在树里：切到赛道时置 true；切回街道时先淡出，
  /// 淡出完成后再置 false（淡出由 AnimatedOpacity 的 duration
  /// 与 onEnd 回调配合，见 build）。
  bool _flagVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.surface == DriveSurface.track) {
      _flagVisible = true;
      _flagAnim.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ModeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surface == widget.surface) return;
    if (widget.surface == DriveSurface.track) {
      // 街道 → 赛道：唯一触发入场动画的路径。
      setState(() => _flagVisible = true);
      _flagAnim.forward(from: 0);
    }
    // 赛道 → 街道：不立即摘掉旗面，靠 AnimatedOpacity 淡出，
    // onEnd 里再把 _flagVisible 置 false。
  }

  @override
  void dispose() {
    _flagAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final isTrack = widget.surface == DriveSurface.track;
    Widget segment(DriveSurface s) {
      final selected = widget.surface == s;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.enabled ? () => widget.onSurfaceChanged?.call(s) : null,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    color: widget.enabled
                        ? (selected ? Colors.white : Colors.white70)
                        : Colors.white38,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                if (s == DriveSurface.track && _flagVisible) ...[
                  const SizedBox(width: 6),
                  // 旗面：赛道态淡入/弹入，街道态 200ms 淡出。
                  AnimatedOpacity(
                    opacity: isTrack ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    onEnd: () {
                      if (!isTrack && mounted) {
                        setState(() => _flagVisible = false);
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _flagAnim,
                      builder: (_, child) {
                        final p = Curves.easeOutCubic.transform(_flagAnim.value);
                        final scale = 0.3 + 0.7 * p;
                        // 轻微挥动：振幅随进度衰减到 0，收尾时旗面端正。
                        final wave = math.sin(_flagAnim.value * math.pi * 3) *
                            0.12 *
                            (1 - _flagAnim.value);
                        return Transform.scale(
                          scale: scale,
                          child: Transform.rotate(angle: wave, child: child),
                        );
                      },
                      child: const CheckeredFlag(width: 22, height: 15),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: widget.enabled ? 1 : 0.5,
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            // 滑动滑块：200ms easeOutCubic，左右两段各占一半。
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: isTrack ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent),
                  ),
                ),
              ),
            ),
            Row(children: [
              segment(DriveSurface.street),
              segment(DriveSurface.track),
            ]),
          ],
        ),
      ),
    );
  }
}

/// 大方块正上方的一段式布局：分段控件 + 赛道选择器紧随其下。
///
/// - 街道态：只显示 [ModeSwitch]，[trackSelector] 不渲染、不占位；
/// - 赛道态：[trackSelector] 展开在分段控件正下方（间距 8）；
/// - 骑行模式下调用方请不要渲染本组件，本组件不替调用方判断 TripMode。
/// - [trackSelector] 为 null 时赛道态下显示一行占位提示，不谎称已选赛道。
class ModeSwitchSection extends StatelessWidget {
  final DriveSurface surface;
  final ValueChanged<DriveSurface>? onSurfaceChanged;
  final bool enabled;
  final Color? accentColor;

  /// 赛道态下紧随分段控件下方展开的选择器（调用方传入）。
  final Widget? trackSelector;

  const ModeSwitchSection({
    super.key,
    required this.surface,
    required this.onSurfaceChanged,
    this.enabled = true,
    this.accentColor,
    this.trackSelector,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return Padding(
      // 与下方大方块行的顶部间距（4）合计 12，与大方块行内
      // 左右两块的中间间距（12）一致，视觉上“紧贴”且不挤。
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModeSwitch(
            surface: surface,
            onSurfaceChanged: onSurfaceChanged,
            enabled: enabled,
            accentColor: accent,
          ),
          if (surface == DriveSurface.track) ...[
            const SizedBox(height: 8),
            trackSelector ??
                const Text(
                  '未传入赛道选择器：总协调需把现有赛道选择入口传给 trackSelector。',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
          ],
          if (surface == DriveSurface.track)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '示意轮廓，非官方测绘',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}
