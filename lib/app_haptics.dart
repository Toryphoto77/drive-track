import 'package:flutter/services.dart';

/// 全局震动反馈统一入口：按钮与关键交互走 [tap]，开始记录倒数
/// 走 [strong]。无震动马达或系统关闭触感时静默，不抛错、不崩。
class AppHaptics {
  static Future<void> tap() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static Future<void> strong() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
