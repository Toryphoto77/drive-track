/// v1.0.5 毛玻璃底部导航栏：改回最初版药丸毛玻璃，无液态玻璃动画。
///
/// 规格：
/// - 独立悬浮药丸：176px 宽、52px 高、全圆角；
/// - BackdropFilter 高斯模糊 28 + 半透明深色渐变（顶部 0.45、底部 0.35）
///   + 细亮边框（透明度 0.18、宽 1px）与顶部高光；
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
    (Icons.list_alt, '记录'),
    (Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
                          const Color(0xFF1A1A1A).withValues(alpha: 0.45),
                          const Color(0xFF121212).withValues(alpha: 0.35),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // 顶部高光：上沿一道微亮渐变，玻璃感更明显（静态装饰，无动画）。
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
                        Color(0x33FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                color: selectedIndex == i
                                    ? accent.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                boxShadow: selectedIndex == i
                                    ? [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              // v1.0.5 收尾：长按提示去掉。导航栏不用 IconButton
                              //（其 tooltip 长按会弹出“首页/记录/我的”文本框），
                              //改用无 Tooltip 的 InkWell + Icon，真正不弹任何提示框；
                              //名称只作无障碍语义标签，不显示。顶部菜单/设置
                              //按钮的 tooltip 按要求不动。
                              child: Semantics(
                                label: _tabs[i].$2,
                                button: true,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => onTap(i),
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
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
