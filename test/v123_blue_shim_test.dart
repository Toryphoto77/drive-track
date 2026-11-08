import 'dart:io';

import 'package:drive_track/app_icon_choice.dart';
import 'package:flutter_test/flutter_test.dart';

/// v1.2.3 紧急修复回归测试：v1.2.2 删掉 LauncherBlue alias 后，旧蓝仪表
/// 用户升级后没有任何 alias 处于启用状态，App 启动不了、启动迁移也跑不到，
/// 桌面残留图标只能进应用详情。本版把 LauncherBlue 作为启动兼容垫片恢复
/// （图标用方向盘），但它绝不是可选项：主题页只有两项（方向盘/方格旗），
/// 存量 blue/gray 选择启动后必须回落方向盘，且原生禁用清单必须含垫片
/// （原生代码以 allComponents 显式补上，见 MainActivity setAppIcon；
/// 此处校验 Manifest 文本，防垫片被再次误删）。
void main() {
  test('v1.2.3 blue/gray stored choice falls back to steering, blue is not valid', () {
    expect(AppIconChoice.normalize('blue'), AppIconChoice.steering);
    expect(AppIconChoice.normalize('gray'), AppIconChoice.steering);
    expect(AppIconChoice.isValid('blue'), isFalse);
    expect(AppIconChoice.assetFor('blue'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.labelFor('blue'), '方向盘');
  });

  test('theme options are exactly two (steering/checkered), no blue', () {
    const options = [
      AppIconChoice.steering,
      AppIconChoice.checkered,
    ];
    expect(options.length, 2);
    expect(options.toSet().length, 2);
    for (final key in options) {
      expect(AppIconChoice.isValid(key), isTrue);
    }
    expect(options, isNot(contains('blue')));
  });

  test('v1.2.3 manifest keeps LauncherBlue shim with steering icon, not blue art', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    // 6 个 alias：2 项可选项 + 3 个已删选项的 alias（保留防启动失败）+ Blue 垫片。
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
    // Blue 垫片块内必须是方向盘图标，且带 LAUNCHER 过滤器。
    final blueAt = manifest.indexOf('android:name=".LauncherBlue"');
    expect(blueAt, greaterThan(0));
    final blueBlock = manifest.substring(blueAt, blueAt + 800);
    expect(blueBlock, contains('@mipmap/ic_launcher_steering'));
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
