import 'package:flutter/material.dart';

/// v1.0.2 统一导入 UI（只管外观与文案排版，不管导入逻辑），
/// v1.0.3 强调色改回主题色。
///
/// 画风约定：
/// - 大卡 #1E1E1E、内卡 #2A2A2A、大圆角（卡 16、内卡 12、按钮 12）；
/// - 有边框输入框：默认白 24% 细边框、聚焦时主题色边框、
///   填充内卡色；
/// - 主操作一律主题色白字、次操作为描边按钮；
/// - 成功 / 失败 / 提示一律走 [ImportNotice]，不再各页自写颜色。
/// 主题色取 Theme.of(context).colorScheme.primary（默认法拉利红），
/// 不再写死任何强调色值。
///
/// 使用范围（本轮已接入，见各页文件头）：
/// 字体导入（settings_page.dart）、地图资源导入（map_import_page.dart）、
/// 设置备份恢复（data_export_page.dart）、自定义语音服务
/// （voice_settings_page.dart）、照片导入相关入口（photo_points.dart）。
/// 各页只把旧 Card / TextField / FilledButton / 裸 Text 提示换成
/// 本文件组件；回调、校验、白名单、文件格式、存储路径一律未动。

/// 大卡底色。
const Color importCardColor = Color(0xFF1E1E1E);

/// 内卡底色（输入框填充、次级块共用）。
const Color importInnerCardColor = Color(0xFF2A2A2A);

/// 卡片边框色。
const Color importBorderColor = Color(0xFF3A3A3A);

/// 主操作强调色：当前主题色（默认法拉利红），调用方在 build 里取。

/// 大卡：深色 + 细边框 + 16 大圆角。
class ImportCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const ImportCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: importCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: importBorderColor),
      ),
      child: child,
    );
  }
}

/// 内卡：比大卡浅一档的 #2A2A2A 块，用于分组或输入区背景。
class ImportInnerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ImportInnerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: importInnerCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: importBorderColor),
      ),
      child: child,
    );
  }
}

/// 有边框输入框：label + 描边 + 内卡填充，聚焦变主题色边。
class ImportBorderedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;

  const ImportBorderedTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color),
        );
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: importInnerCardColor,
        border: border(Colors.white24),
        enabledBorder: border(Colors.white24),
        focusedBorder: border(accent),
      ),
    );
  }
}

/// 主题色主按钮：主题色白字、12 圆角、48 高，默认撑满宽度。
class ImportPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  const ImportPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final button = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: accent.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: icon == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
            ),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// 次按钮：描边、白字，与主按钮同高同圆角。
class ImportSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool expanded;

  const ImportSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// 文件选择行：文件名（未选时显示占位）+ 右侧主题色“选择文件”钮，
/// 可选的清除钮只清界面显示，删文件与否由调用方原逻辑决定。
class ImportFileRow extends StatelessWidget {
  final String? fileName;
  final String placeholder;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final String pickLabel;

  const ImportFileRow({
    super.key,
    required this.fileName,
    this.placeholder = '未选择文件',
    required this.onPick,
    this.onClear,
    this.pickLabel = '选择文件',
  });

  @override
  Widget build(BuildContext context) {
    return ImportInnerCard(
      child: Row(children: [
        const Icon(Icons.insert_drive_file_outlined, color: Colors.white54),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            fileName == null || fileName!.isEmpty ? placeholder : fileName!,
            style: TextStyle(
              color: fileName == null || fileName!.isEmpty ? Colors.white54 : Colors.white,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 20, color: Colors.white54),
            tooltip: '清除',
            onPressed: onClear,
          ),
        ImportPrimaryButton(label: pickLabel, onPressed: onPick, expanded: false),
      ]),
    );
  }
}

enum ImportNoticeKind { success, error, info }

/// 成功 / 失败 / 提示条：带左边色块与细边框，不再各页自写颜色。
class ImportNotice extends StatelessWidget {
  final String message;
  final ImportNoticeKind kind;

  const ImportNotice({
    super.key,
    required this.message,
    this.kind = ImportNoticeKind.info,
  });

  /// 按文案自动归类：含“失败 / 不是有效 / 未恢复 / 已取消”判失败，
  /// 含“已导出 / 已恢复 / 已导入 / 成功 / 已保存”判成功，其余为提示。
  /// 仅用于旧文案复用；新代码请直接传 kind。
  static ImportNoticeKind kindFromMessage(String message) {
    if (message.contains('失败') ||
        message.contains('不是有效') ||
        message.contains('未恢复') ||
        message.contains('已取消') ||
        message.contains('不支持')) {
      return ImportNoticeKind.error;
    }
    if (message.contains('已导出') ||
        message.contains('已恢复') ||
        message.contains('已导入') ||
        message.contains('成功') ||
        message.contains('已保存')) {
      return ImportNoticeKind.success;
    }
    return ImportNoticeKind.info;
  }

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (kind) {
      ImportNoticeKind.success => (Colors.greenAccent, Icons.check_circle_outline),
      ImportNoticeKind.error => (Colors.redAccent, Icons.error_outline),
      ImportNoticeKind.info => (Colors.white70, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: importInnerCardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 13)),
        ),
      ]),
    );
  }
}
