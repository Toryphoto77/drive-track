import 'dart:io';

import 'package:drive_track/app_icon_choice.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1.2.3 紧急修复回归测试：v1.2.2 删掉 LauncherBlue alias 后，旧蓝仪表
/// 用户升级后没有任何 alias 处于启用状态，App 启动不了、启动迁移也跑不到，
/// 桌面残留图标只能进应用详情。本版把 LauncherBlue 作为启动兼容垫片恢复
/// （图标用红赛车），但它绝不是可选项：主题页仍只有五项，存量 blue/gray
/// 选择启动后必须回落红赛车，且原生禁用清单必须含垫片（原生代码以
/// allComponents 显式补上，见 MainActivity setAppIcon；此处校验 Manifest
/// 文本，防垫片被再次误删）。
void main() {
  test('v1.2.3 blue/gray stored choice falls back to red, blue is not valid', () {
    expect(AppIconChoice.normalize('blue'), AppIconChoice.red);
    expect(AppIconChoice.normalize('gray'), AppIconChoice.red);
    expect(AppIconChoice.isValid('blue'), isFalse);
    expect(AppIconChoice.assetFor('blue'), 'assets/app_icon_red.png');
    expect(AppIconChoice.labelFor('blue'), '红赛车');
  });

  test('v1.2.3 theme options are exactly five, no blue', () {
    const options = [
      AppIconChoice.red,
      AppIconChoice.rb17,
      AppIconChoice.valkyrie,
      AppIconChoice.steering,
      AppIconChoice.checkered,
    ];
    expect(options.length, 5);
    expect(options.toSet().length, 5);
    for (final key in options) {
      expect(AppIconChoice.isValid(key), isTrue);
    }
    expect(options, isNot(contains('blue')));
  });

  test('v1.2.3 manifest keeps LauncherBlue shim with red icon, not blue art', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    // 6 个 alias：5 项可选项 + Blue 垫片。
    for (final alias in [
      'LauncherRed',
      'LauncherRb17',
      'LauncherValkyrie',
      'LauncherSteering',
      'LauncherCheckered',
      'LauncherBlue',
    ]) {
      expect(manifest, contains('android:name=".$alias"'));
    }
    expect(manifest, isNot(contains('ic_launcher_blue')));
    // Blue 垫片块内必须是红赛车图标，且带 LAUNCHER 过滤器。
    final blueAt = manifest.indexOf('android:name=".LauncherBlue"');
    expect(blueAt, greaterThan(0));
    final blueBlock = manifest.substring(blueAt, blueAt + 800);
    expect(blueBlock, contains('@mipmap/ic_launcher_red'));
    expect(blueBlock, contains('android.intent.action.MAIN'));
    expect(blueBlock, contains('android.intent.category.LAUNCHER'));
    expect(blueBlock, contains('android:targetActivity=".MainActivity"'));
  });

  test('v1.2.3 native setAppIcon disable list includes LauncherBlue shim', () {
    final kt = File(
      'android/app/src/main/kotlin/com/chixi/drive_track/MainActivity.kt',
    ).readAsStringSync();
    expect(kt, contains('LauncherBlue'));
    // 禁用循环走的全部件列表必须显式含垫片，不能只靠选择映射去重。
    expect(kt, contains('allComponents'));
  });
}
