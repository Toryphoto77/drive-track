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
    // 4 等分槽位的中心：-1 + (2i+1)/n，与 ModeSwitch 一样用对齐做滑动。
    final n = _tabs.length;
    final alignX = -1 + (2 * selectedIndex + 1) / n;
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
                    child: Stack(
                      children: [
                        // 选中圆只做水平滑动，不缩放、不拉伸。
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment(alignX, 0),
                          child: Container(
                            width: 48,
                            height: 48,
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
                        Row(
                          children: [
                            for (var i = 0; i < _tabs.length; i++)
                              Expanded(
                                child: Center(
                                  // 名称只作无障碍语义，不显示文字。
                                  child: Semantics(
                                    label: labels[i],
                                    button: true,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        AppHaptics.tap();
                                        onTap(i);
                                      },
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Icon(
                                          _tabs[i].$1,
                                          color: selectedIndex == i
                                              ? accent
                                              : Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
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
