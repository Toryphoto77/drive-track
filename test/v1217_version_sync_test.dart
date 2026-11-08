/// v1.5.2 版本同步测试：pubspec、UpdateService、打包脚本三处
/// 版本号必须一致为 1.5.2+57（版本升级时同步更新本文件钉死的版本号）。
///
/// 本文件不依赖跨路契约（不碰 Lap / LapTimer 新 API），
/// 可独立编译运行.

import 'dart:io';

import 'package:drive_track/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UpdateService 当前版本为 1.5.2+57', () {
    expect(UpdateService.currentVersionName, '1.5.2');
    expect(UpdateService.currentVersionCode, 57);
  });

  test('pubspec.yaml 版本为 1.5.2+57', () {
    final content = File('pubspec.yaml').readAsStringSync();
    expect(content, contains('version: 1.5.2+57'));
    expect(content, isNot(contains('1.3.7')));
  });

  test('打包脚本产物名为 DriveTrack-v<版本>-release-arm64-v8a.apk', () {
    final content = File('build-apk-release.sh').readAsStringSync();
    // 文件名由脚本从 pubspec 动态读 VERSION 拼出，脚本里是模板不是字面量。
    expect(content, contains('DriveTrack-v\${VERSION}-release-arm64-v8a.apk'));
    expect(content, isNot(contains('1.3.7')));
  });

  test('关于页版本号与 UpdateService 一致（main.dart）', () {
    final content = File('lib/main.dart').readAsStringSync();
    expect(content, contains("versionName: '1.5.2'"));
  });
}
