/// 启动图标默认方向盘回归测试（v1.5.2）。
///
/// 根因：v1.5.0 之前默认启动图标是红赛车——AndroidManifest 的
/// application 图标、默认启用的 LauncherRed alias、LauncherBlue 垫片
/// 与 Android 12+ 系统启动画面（values-v31 的
/// windowSplashScreenAnimatedIcon）全都指向 @mipmap/ic_launcher_red。
/// 后果有两处：① 更新/安装时系统显示红赛车图标；② 冷启动时系统启动
/// 画面在 Flutter 首帧之前全屏闪过一帧红赛车（OnePlus 13 / Android 15
/// 实测）。v1.5.2 起四处统一改为方向盘 @mipmap/ic_launcher_steering，
/// 红赛车 PNG（5 个密度）已删除；此处校验 Manifest 与 v31 样式文本，
/// 防红赛车图标以任何一处回来。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认启动图标是方向盘：application 图标与默认 alias 均指向 steering', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    // application 图标。
    expect(manifest, contains('android:icon="@mipmap/ic_launcher_steering"'));
    expect(manifest,
        contains('android:roundIcon="@mipmap/ic_launcher_steering"'));
    // 默认启用的 LauncherRed alias（名字保留，组件身份跨升级粘性，
    // 见 Manifest 注释）图标也是方向盘。
    final redAt = manifest.indexOf('android:name=".LauncherRed"');
    expect(redAt, greaterThan(0));
    final redBlock = manifest.substring(redAt, redAt + 600);
    expect(redBlock, contains('@mipmap/ic_launcher_steering'));
    expect(redBlock, contains('android:enabled="true"'));
    // 全文不再出现红赛车图标引用。
    expect(manifest, isNot(contains('ic_launcher_red')));
  });

  test('冷启动系统启动画面图标是方向盘，不是红赛车', () {
    final styles = File('android/app/src/main/res/values-v31/styles.xml')
        .readAsStringSync();
    expect(
      styles,
      contains(
          '<item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_steering</item>'),
    );
    expect(styles, isNot(contains('ic_launcher_red')));
    expect(styles,
        contains('<item name="android:windowSplashScreenBackground">@android:color/black</item>'));
  });

  test('红赛车启动图标 PNG 已从各密度 mipmap 目录删除', () {
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final file = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher_red.png');
      expect(file.existsSync(), isFalse,
          reason: 'mipmap-$density/ic_launcher_red.png 仍在');
      // 方向盘图标各密度齐全。
      final steering = File(
          'android/app/src/main/res/mipmap-$density/ic_launcher_steering.png');
      expect(steering.existsSync(), isTrue,
          reason: 'mipmap-$density/ic_launcher_steering.png 缺失');
    }
  });
}
