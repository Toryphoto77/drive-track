/// 横屏整 App 冒烟测试（800×360）。
///
/// 整 App 在 800×360 横屏下进首页不溢出、不抛错（首页横屏改整页
/// 滚动、PageView 给定高 220 的回归锚点）。记录页分栏本身需进入
/// 记录态（依赖原生定位/传感器），不在 widget 测试覆盖内，见
/// 汇报里的尺寸推演。赛道面板窄栏测试见
/// landscape_track_session_test.dart（不依赖 main.dart）。
///
/// 注意：本文件 import main.dart；当前另一子代理的
/// lib/app_bar_style.dart:54 有编译错误（const 构造调了 AppBar
/// 的非 const 超构造），会拦住本文件加载，等该文件修好后再跑。

import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  debugAllowUnsignedMainUi = true;
  testWidgets('横屏 800x360 整 App 进首页不溢出、不抛错', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DriveTrackApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DriveTrack'), findsOneWidget);
    expect(find.text('开始记录'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
