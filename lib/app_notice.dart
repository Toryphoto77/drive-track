/// DriveTrack v1.2.0 第 4 项：统一非模态提示（替代全部 SnackBar）。
///
/// 设计要点（不改任何业务逻辑与提示文案原意）：
/// - 顶部位置：`MediaQuery.viewPadding.top + 12`，避开刘海；只占一条
///   提示的区域，不铺满屏幕、不阻塞下方操作，录制页同样适用。
/// - 非模态：不用 showDialog / BottomSheet；OverlayEntry 只覆盖提示
///   本身的矩形，点提示可手动关闭，其余区域照常可点。
/// - 单例不排队：新提示先移除旧提示（并取消旧定时器）再插入，
///   连续提示不会像 SnackBar 那样排队积压。
/// - 自动消失：默认 2800ms（约 2.5–3 秒）后移除；期间插新提示会
///   重置计时。
/// - 根 Overlay：用 `Overlay.of(context, rootOverlay: true)`，提示不
///   依附于当前页面的 Scaffold/Route。fuel_page 先提示后 pop 的
///   顺序因此不会被页面销毁吞掉：提示在 pop 前发出、挂在根
///   Overlay 上，pop 后仍可见直至定时消失。
/// - 配色语义借用 import_style.dart 的 ImportNotice：
///   success = greenAccent / check_circle_outline，
///   error = redAccent / error_outline，info = white70 / info_outline；
///   warning 为新增档（amberAccent / warning_amber_outlined），用于
///   “需用户先补齐 / 暂无 / 已达上限”类提醒，与失败区分。
import 'dart:async';

import 'package:flutter/material.dart';

enum AppNoticeKind { success, error, warning, info }

Color appNoticeColor(AppNoticeKind kind) => switch (kind) {
      AppNoticeKind.success => Colors.greenAccent,
      AppNoticeKind.error => Colors.redAccent,
      AppNoticeKind.warning => Colors.amberAccent,
      AppNoticeKind.info => Colors.white70,
    };

IconData appNoticeIcon(AppNoticeKind kind) => switch (kind) {
      AppNoticeKind.success => Icons.check_circle_outline,
      AppNoticeKind.error => Icons.error_outline,
      AppNoticeKind.warning => Icons.warning_amber_outlined,
      AppNoticeKind.info => Icons.info_outline,
    };

/// 按文案自动归类（与 ImportNotice.kindFromMessage 同口径，另加
/// warning 档）：含失败/未授予/未保存/打不开/无法判 error，含已
/// 导入/已清除/已复制/已保存/成功/已标记判 success，其余为 info。
/// 仅用于动态文案调用点（map_import、about）；静态文案调用点
/// 请直接传明确的 kind，不走推断。
AppNoticeKind appNoticeKindFromMessage(String message) {
  if (message.contains('失败') ||
      message.contains('不是有效') ||
      message.contains('未恢复') ||
      message.contains('已取消') ||
      message.contains('不支持') ||
      message.contains('未授予') ||
      message.contains('无法') ||
      message.contains('打不开')) {
    return AppNoticeKind.error;
  }
  if (message.contains('已导出') ||
      message.contains('已恢复') ||
      message.contains('已导入') ||
      message.contains('成功') ||
      message.contains('已保存') ||
      message.contains('已清除') ||
      message.contains('已复制') ||
      message.contains('已标记')) {
    return AppNoticeKind.success;
  }
  return AppNoticeKind.info;
}

OverlayEntry? _currentEntry;
Timer? _currentTimer;

/// 移除当前提示（若有），并取消其自动消失定时器。手动点提示
/// 关闭与新提示替换旧提示都走这里。
void dismissAppNotice() {
  _currentTimer?.cancel();
  _currentTimer = null;
  final entry = _currentEntry;
  _currentEntry = null;
  try {
    entry?.remove();
  } catch (_) {
    // Overlay 已随页面销毁时 remove 会抛，忽略即可。
  }
}

/// 显示一条顶部非模态提示。调用前请先检查 `mounted` /
/// `context.mounted`（本函数对已失效的 context 只做静默返回，
/// 不抛异常，但不替代调用点的守卫）。
void showAppNotice(
  BuildContext context,
  String message, [
  AppNoticeKind kind = AppNoticeKind.info,
  Duration duration = const Duration(milliseconds: 2800),
]) {
  if (message.isEmpty) return;
  // 先替换旧提示：单例，不排队。
  dismissAppNotice();
  OverlayState? overlay;
  try {
    overlay = Overlay.of(context, rootOverlay: true);
  } catch (_) {
    return;
  }
  final topPadding = MediaQuery.viewPaddingOf(context).top;
  final color = appNoticeColor(kind);
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: dismissAppNotice,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xE61E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(appNoticeIcon(kind), size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: color, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  _currentEntry = entry;
  try {
    overlay.insert(entry);
  } catch (_) {
    _currentEntry = null;
    return;
  }
  _currentTimer = Timer(duration, dismissAppNotice);
}
