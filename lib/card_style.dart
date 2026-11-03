import 'package:flutter/material.dart';

/// v1.0.3 卡片风格（v1.0.2 的深色大卡外观保留，强调色改回主题色）。
///
/// 外观口径（只定外观，不改任何功能逻辑）：
/// - 大卡底色 #1E1E1E，内卡底色 #2A2A2A；
/// - 大圆角：大卡 26、内卡 24（都在 24–28 区间内）；
/// - 细亮边框：白色 14% 透明、1px；
/// - v1.0.3 改回：选中 / 主操作不再写死截图蓝，一律用当前主题色
///   （见 [accent]，即 Theme.of(context).colorScheme.primary，默认
///   法拉利红，用户在主题设置里换什么色就跟什么色）。
/// 已改用本组件：首页/记录页的 Card（main.dart 的当月汇总、
/// 演示卡、行程列表卡）、我的页 _card（my_page.dart）。
class CardStyle {
  CardStyle._();

  /// 大卡底色（截图深色大卡）。
  static const Color cardColor = Color(0xFF1E1E1E);

  /// 内卡底色（大卡内再套一层时用）。
  static const Color innerCardColor = Color(0xFF2A2A2A);

  /// 细亮边框。
  static Color get borderColor => Colors.white.withValues(alpha: 0.14);

  /// 大卡圆角。
  static const double cardRadius = 26;

  /// 内卡圆角。
  static const double innerRadius = 24;

  /// 选中 / 主操作强调色：当前主题色（默认法拉利红），不写死任何色值。
  /// 调用方在 build 里用它，主题设置换色后自动跟随。
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static BorderRadius get cardBorderRadius =>
      BorderRadius.circular(cardRadius);
  static BorderRadius get innerBorderRadius =>
      BorderRadius.circular(innerRadius);

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cardColor,
        borderRadius: cardBorderRadius,
        border: Border.all(color: borderColor),
      );

  static BoxDecoration get innerCardDecoration => BoxDecoration(
        color: innerCardColor,
        borderRadius: innerBorderRadius,
        border: Border.all(color: borderColor),
      );
}

/// 统一大卡：圆角 26、底色 #1E1E1E、细亮边框。
/// [margin] 由调用方给（列表卡与独立卡的间距不同，不在本组件内写死）。
class DriveTrackCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  const DriveTrackCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: CardStyle.cardColor,
      borderRadius: CardStyle.cardBorderRadius,
      border: Border.all(color: borderColor ?? CardStyle.borderColor),
    );
    final content = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: decoration,
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: CardStyle.cardBorderRadius,
        child: content,
      ),
    );
  }
}

/// 统一内卡：圆角 24、底色 #2A2A2A、细亮边框（套在大卡内时用）。
class DriveTrackInnerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  const DriveTrackInnerCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CardStyle.innerCardColor,
        borderRadius: CardStyle.innerBorderRadius,
        border: Border.all(color: borderColor ?? CardStyle.borderColor),
      ),
      child: child,
    );
  }
}

/// 设置入口列表行。
///
/// 与该页现有 entry(icon, title, subtitle, onTap) 签名一致：
/// 图标 + 标题 + 副标题 + 右侧 chevron，整行包在统一大卡里。
class DriveTrackEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const DriveTrackEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DriveTrackCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
