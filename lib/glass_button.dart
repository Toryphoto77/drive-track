import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_haptics.dart';

/// 毛玻璃圆形按钮（v0.1.4 外壳 UI 分工）。
///
/// 供顶部菜单钮、设置钮复用；各页返回钮走 [GlassButton.back]
///（无圆底箭头，见下方 v1.4.2 注释），统一外观与手感：
/// - 44×44 圆（[size] 可覆盖，但顶部栏/返回钮请保持默认 44）；
/// - [BackdropFilter] 模糊 + 半透明黑底 + 白 12% 细边框；
/// - [highlighted] 为真时底色改用主题色 22% 透明 + 主题色边框
///   （与现有底部药丸导航的选中态同一种透明度约定）；
/// - 统一水波纹：[Material] + [InkWell] + 圆形 [borderRadius]，
///   禁用时（[onPressed] 为 null）不响应、不出水波纹。
///
/// 注意：模糊只对按钮背后的内容生效。v1.4.2 起 AppBar 已改深色
/// 半透磨砂（65% 黑 + 模糊 28，见 app_bar_style.dart），圆底按钮
/// 放在 AppBar 上也能透出模糊；放在地图 / 照片等有内容的上方时
/// 模糊同样可见。本文件不引用 main.dart，不做任何存储。
///
/// v1.4.2：[GlassButton.back] 不再画圆形磨砂框，只留一个平台默认
/// 样式的返回箭头。当时根因：本 App 全部 AppBar 都是不透明底色，
/// 模糊在上面不可见，44px 圆底只剩一圈白 12% 细边框；钻进三级
/// 菜单时父页（设备中心 / 车辆档案）是普通箭头，子页突然多出
/// 一个圆形外框，看起来像多余的装饰。v1.4.2 后 AppBar 已改半透
/// 磨砂，但 back 仍保持普通箭头（与系统默认返回钮同一外观，
/// 不改回圆形）。圆底只保留给真正浮在地图 / 照片上的按钮
/// （主构造 [GlassButton] 默认仍画圆）。
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

  /// 是否画圆形磨砂底。主构造默认 true（浮在地图 / 照片上的按钮）；
  /// [GlassButton.back] 固定为 false（见文件头注释：返回钮保持
  /// 平台默认普通箭头，不画圆底）。
  final bool circular;

  const GlassButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
    this.accentColor,
    this.size = 44,
    this.tooltip,
    this.circular = true,
  });

  /// 返回钮快捷构造：图标固定为 arrow_back，其余与主构造一致。
  /// 不画圆形底，只留返回箭头（AppBar leading 用，与主题 / 赛道 /
  /// 地图导入等页的系统默认返回箭头同一外观）。
  const GlassButton.back({
    super.key,
    required this.onPressed,
    this.highlighted = false,
    this.accentColor,
    this.size = 44,
    this.tooltip = '返回',
  })  : icon = Icons.arrow_back,
        circular = false;

  @override
  Widget build(BuildContext context) {
    // 不画圆底时（GlassButton.back，AppBar leading 用）：只留一个
    // 返回箭头，外观与系统默认返回按钮一致；点击仍走统一震动。
    if (!circular) {
      final plain = IconButton(
        icon: Icon(icon),
        onPressed: onPressed == null
            ? null
            : () {
                AppHaptics.tap();
                onPressed!();
              },
      );
      // 长按不弹文本：不用 Tooltip，语义标签只给读屏。
      if (tooltip == null || tooltip!.isEmpty) return plain;
      return Semantics(label: tooltip, child: plain);
    }
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
