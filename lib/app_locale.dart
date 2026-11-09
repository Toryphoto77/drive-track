import 'dart:io';

import 'package:flutter/material.dart';

import 'card_style.dart';
import 'native.dart';

/// 界面语言。没有已保存的选择时用中文。
enum AppLang { zh, en }

/// 语言选择：内存里立即生效，并写入 filesDir/app_language.txt。
/// 文件缺失、读失败或内容不是 `en` 时一律保持中文。
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  AppLang lang = AppLang.zh;

  bool get isZh => lang == AppLang.zh;

  Future<void> load() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/app_language.txt');
      if (await f.exists()) {
        final raw = (await f.readAsString()).trim().toLowerCase();
        lang = raw == 'en' ? AppLang.en : AppLang.zh;
      } else {
        lang = AppLang.zh;
      }
    } catch (_) {
      lang = AppLang.zh;
    }
    notifyListeners();
  }

  Future<void> setLang(AppLang next) async {
    if (lang == next) return;
    lang = next;
    notifyListeners();
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/app_language.txt')
          .writeAsString(next == AppLang.en ? 'en' : 'zh');
    } catch (_) {}
  }
}

/// 挂在 MaterialApp.builder 上，语言变化时重建已订阅的界面。
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static LocaleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    return scope?.notifier ?? LocaleController.instance;
  }
}

/// 主界面文案。中文在前，英文在后；无偏好时走中文。
class S {
  final bool zh;
  const S(this.zh);

  static S of(BuildContext context) => S(LocaleScope.of(context).isZh);

  static S get current => S(LocaleController.instance.isZh);

  String t(String zhText, String enText) => zh ? zhText : enText;
}

/// 我的 / 设置里的语言开关。两个标签固定写「中文 / English」，
/// 不随当前语言改名，避免找不到切回去的入口。
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lang = LocaleScope.of(context).lang;
    final accent = CardStyle.accent(context);

    Widget chip(String label, AppLang value) {
      final selected = lang == value;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => LocaleController.instance.setLang(value),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.black54,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? accent : CardStyle.borderColor,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.t('语言', 'Language'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            s.t('立即切换界面文字', 'Switches the interface immediately'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(children: [
            chip('中文', AppLang.zh),
            const SizedBox(width: 8),
            chip('English', AppLang.en),
          ]),
        ],
      ),
    );
  }
}
