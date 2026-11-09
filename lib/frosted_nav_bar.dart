/// v1.0.9 方案 A 深色炭灰玻璃底部导航栏（v1.0.8 白色玻璃的问题：
/// 白药丸在 #121212 深色底上像一张贴纸，白边 0.40 过硬，透过的
/// 内容还会跟深色图标打架；176 宽塞 3 图标也显挤）。
///
/// 规格：
/// - 独立悬浮药丸：288px 宽、56px 高、全圆角（圆角 = 高 / 2）；
///   v1.5.4：4 项（首页 / 设备 / 记录 / 我的），216 宽塞 4 图标
///   显挤，加宽到 288（每项 72 节距，与 3 项时的 216 同口径）；
/// - BackdropFilter 高斯模糊 28 + 深色炭灰渐变（#2A2A2A，顶部
///   alpha 0.68、底部 alpha 0.62，约 0.65——比 #121212 背景亮一档，
///   是深色玻璃，不是白玻璃也不是纯黑块）+ 白色细边框
///   （透明度 0.14、宽 1px）与弱化顶部高光；
/// - 图标随玻璃改色：未选中白色 70%（深色玻璃上可读，v1.0.8 的
///   黑 87% 已删——在深色玻璃上看不见），选中主题色法拉利红，
///   选中圆底主题色 22% + 主题色光晕；
/// - 绝无液态玻璃行为：无滚动放大、无切换拉伸、无选中放大；
/// - 图标只留图标无文字；悬浮位置由调用方 Positioned 直接定
///   （底部 12px + 系统底部 inset），本组件内不再用 SafeArea，
///   不在药丸下方垫出空底色区；
/// - 内容不再为药丸留空：内容从药丸下方划过、透过毛玻璃模糊可见，
///   药丸周边不再是空黑条；
/// - 记录中由调用方隐藏本组件。
/// - 无任何放大动画：不跟随滚动放大、不做切换拉伸回弹、
///   选中图标不放大；选中态只用主题色药丸高光
///   （主题色 22% 底 + 主题色光晕，图标变主题色）。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_haptics.dart';
import 'app_locale.dart';
import 'home_layout.dart';

/// 选中圆左边缘，使圆心落在第 [index] 个等分槽的中心。
///
/// [AnimatedAlign] 的 Alignment 把子组件中心映射到
/// `(parentSize - childSize)` 的剩余空间里，不是父级全宽。
/// `alignX = -1 + (2i+1)/n` 因此会把 48px 选中圆往中间拽：
/// 288 宽、4 项时两端差约 18px、中间两项差约 6px，图标和
/// 圆点看起来错开。槽宽中心与图标、点击区用同一套除法。
double navSelectionLeft({
  required double barWidth,
  required int index,
  required int count,
  double indicatorSize = 48,
}) {
  if (count <= 0 || barWidth <= 0) return 0;
  final slot = barWidth / count;
  final i = index.clamp(0, count - 1);
  return i * slot + (slot - indicatorSize) / 2;
}

class FrostedGlassNavBar extends StatelessWidget {
  const FrostedGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (Icons.home, '首页'),
    // 第 2 项：设备中心（与首页/记录/我的同为底栏页，选中态与切换动画一致）。
    (Icons.devices, '设备'),
    (Icons.list_alt, '记录'),
    (Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final labels = [
      s.t('首页', 'Home'),
      s.t('设备', 'Devices'),
      s.t('记录', 'Trips'),
      s.t('我的', 'Me'),
    ];
    final n = _tabs.length;
    final index = selectedIndex.clamp(0, n - 1);
    // v1.0.5：删掉 SafeArea，底部位置由调用方 Positioned 直接算，
    // 本组件只输出药丸本身，不带任何背景容器。
    return Center(
      child: SizedBox(
          width: kPillNavWidth,
          height: kPillNavHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kPillNavHeight / 2),
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF2A2A2A).withValues(alpha: 0.68),
                          const Color(0xFF2A2A2A).withValues(alpha: 0.62),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // 顶部高光：弱化到与深色玻璃协调（v1.0.8 的 0x33 过亮
                // 显硬边，改 0x14），静态装饰，无动画。
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Color(0x14FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final left = navSelectionLeft(
                          barWidth: constraints.maxWidth,
                          index: index,
                          count: n,
                        );
                        return Stack(
                          children: [
                            // 选中圆只做水平滑动，圆心与槽位中心重合。
                            AnimatedPositioned(
                              key: const Key('nav-selection-indicator'),
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              left: left,
                              top: 0,
                              width: 48,
                              height: 48,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.22),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < _tabs.length; i++)
                                  Expanded(
                                    // 整槽可点，图标在槽中心，与选中圆同一中心。
                                    child: Semantics(
                                      label: labels[i],
                                      button: true,
                                      child: InkWell(
                                        onTap: () {
                                          AppHaptics.tap();
                                          onTap(i);
                                        },
                                        child: Center(
                                          child: Icon(
                                            _tabs[i].$1,
                                            color: index == i
                                                ? accent
                                                : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
