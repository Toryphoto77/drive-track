import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native.dart';

/// 崩溃 / 未捕获异常落盘（本机文件，不联网、不上传）。
///
/// 目的：后台闪退时不再「没有任何堆栈可查」。设置页可导出该日志。
/// 200KB 上限，超出后只保留最近一半，避免长期占用存储。
/// 原生侧的 `crash_native.log` 由 CrashLogger.kt 写，导出时一并合并。
class CrashLog {
  static const String fileName = 'crash_dart.log';
  static const String nativeFileName = 'crash_native.log';
  static const int maxBytes = 200 * 1024;

  static String? _dir;
  static Future<String?>? _dirLoading;

  static Future<String?> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    return _dirLoading ??= _loadDir();
  }

  static Future<String?> _loadDir() async {
    try {
      final d = await Native.getFilesDir();
      _dir = d;
      return d;
    } catch (_) {
      // 原生通道还没准备好时允许下次重试。
      _dirLoading = null;
      return null;
    }
  }

  /// 记录一条异常。任何情况下都不向外抛，日志失败只落到 logcat。
  static void record(Object error, StackTrace? stack, {String tag = ''}) {
    final when = DateTime.now().toIso8601String();
    final text = '[$when][$tag] $error\n${stack ?? ''}\n';
    unawaited(_write(text));
    if (kDebugMode) debugPrint('CrashLog: $text');
  }

  static Future<void> _write(String text) async {
    try {
      final dir = await _ensureDir();
      if (dir == null) return;
      final f = File('$dir/$fileName');
      if (await f.exists() && await f.length() > maxBytes) {
        final bytes = await f.readAsBytes();
        final from = bytes.length - (maxBytes ~/ 2);
        await f.writeAsBytes(bytes.sublist(from < 0 ? 0 : from), flush: true);
      }
      await f.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      // 日志写失败不能反过来影响业务。
    }
  }

  /// 合并 Dart 与原生两份崩溃日志，供设置页导出 / 分享。
  static Future<String> dump() async {
    final dir = await _ensureDir();
    if (dir == null) return '';
    final buf = StringBuffer();
    for (final name in [fileName, nativeFileName]) {
      final f = File('$dir/$name');
      if (await f.exists()) {
        buf.writeln('===== $name =====');
        buf.writeln(await f.readAsString());
      }
    }
    return buf.toString();
  }
}
