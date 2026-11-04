import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_haptics.dart';

/// 毛玻璃圆形按钮（v0.1.4 外壳 UI 分工）。
///
/// 供顶部菜单钮、设置钮、各页返回钮复用，统一外观与手感：
/// - 44×44 圆（[size] 可覆盖，但顶部栏/返回钮请保持默认 44）；
/// - [BackdropFilter] 模糊 + 半透明黑底 + 白 12% 细边框；
/// - [highlighted] 为真时底色改用主题色 22% 透明 + 主题色边框
///   （与现有底部药丸导航的选中态同一种透明度约定）；
/// - 统一水波纹：[Material] + [InkWell] + 圆形 [borderRadius]，
///   禁用时（[onPressed] 为 null）不响应、不出水波纹。
///
/// 注意：模糊只对按钮背后的内容生效。放在不透明纯黑 AppBar 上时
/// 几乎看不到模糊，半透明黑底 + 边框仍保证外观一致，这是预期行为，
/// 不是 bug；放在地图 / 照片等有内容的上方时模糊才可见。
/// 本文件不引用 main.dart，不做任何存储。
class GlassButton extends StatelessWidget {
  /// 图标（必填，如 Icons.menu / Icons.settings / Icons.arrow_back）。
  final IconData icon;

  /// 点击回调；为 null 时按钮置灰禁用。
  final VoidCallback? onPressed;

  /// 高亮态（选中 / 当前页等），默认 false。
  final bool highlighted;

  /// 高亮色与图标选中色；不传时取 Theme.colorScheme.primary。
  final Color? accentColor;

  /// 直径，默认 44。
  final double size;

  /// 无障碍语义标签，如 '菜单' / '设置' / '返回'。
  /// 只供读屏使用，不包 Tooltip，长按不再弹文本。
  final String? tooltip;

  const GlassButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
    this.accentColor,
    this.size = 44,
    this.tooltip,
  });

  /// 返回钮快捷构造：图标固定为 arrow_back，其余与主构造一致。
  const GlassButton.back({
    super.key,
    required this.onPressed,
    this.highlighted = false,
    this.accentColor,
    this.size = 44,
    this.tooltip = '返回',
  }) : icon = Icons.arrow_back;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final enabled = onPressed != null;
    final bg = highlighted
        ? accent.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.45);
    final border = highlighted
        ? accent.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = highlighted ? accent : Colors.white;
    final button = ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed == null
                  ? null
                  : () {
                      AppHaptics.tap();
                      onPressed!();
                    },
              child: Icon(
                icon,
                size: 22,
                color: enabled ? iconColor : Colors.white38,
              ),
            ),
          ),
        ),
      ),
    );
    // 长按不弹文本：不用 Tooltip，语义标签只给读屏。
    if (tooltip == null || tooltip!.isEmpty) return button;
    return Semantics(label: tooltip, child: button);
  }
}

/// 用法示例（仅注释，不执行；总协调接线时按此替换现有 IconButton）：
///
/// ```dart
/// // AppBar leading（菜单）：
/// leading: GlassButton(icon: Icons.menu, tooltip: '菜单', onPressed: _toggleMenu),
/// // AppBar actions（设置）：
/// actions: [GlassButton(icon: Icons.settings, tooltip: '设置', onPressed: _openSettings)],
/// // 子页 AppBar leading（返回）：
/// leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
/// // 高亮态（例如当前已选中）：
/// GlassButton(icon: Icons.map, highlighted: true, accentColor: accent, onPressed: () {}),
/// ```
