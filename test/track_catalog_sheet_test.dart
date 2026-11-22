import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/main.dart';

/// v1.8.3 回归：切换模式 / 表面后，「选择赛道」必须仍然可用。
///
/// 修复前：点击后先 `await TrackLibraryService.loadAll()` 才弹表，加载期间
/// 没有任何反馈，加载失败时回调直接中断——表现就是“按钮完全失效”。
/// 修复后：点击立即弹表，加载 / 失败重试都在表内呈现。
///
/// 注意：
/// - PermissionGate 在自检未完成前用 IgnorePointer 盖住首页，必须 mock
///   `checkPermissions` 返回已授权，否则整页点不动。
/// - 首页含常驻动画，本测试一律定时 pump，不用 pumpAndSettle。
void main() {
  debugAllowUnsignedMainUi = true;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drivetrack/native'),
      (call) async {
        switch (call.method) {
          case 'getFilesDir':
          case 'getCacheDir':
            return Directory.systemTemp.path;
          case 'checkPermissions':
            return <String, dynamic>{'foreground': true, 'location': true};
          case 'requestStep':
            return <String, dynamic>{'foreground': true};
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drivetrack/native'),
      null,
    );
  });

  Future<void> settleApp(
    WidgetTester tester, [
    Duration duration = const Duration(milliseconds: 500),
  ]) async {
    await tester.pump(duration);
    await tester.pump();
  }

  testWidgets('切换模式与表面后点击选择赛道，立即弹出赛道库底部表', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 跳过外接硬件门槛（等价于设置页的自用调试模式）。
    appPrefs.debugMode = true;
    addTearDown(() => appPrefs.debugMode = false);

    await tester.pumpWidget(const DriveTrackApp());
    // 启动页约 1.5s + 权限自检 / 首页初始化。
    await settleApp(tester, const Duration(milliseconds: 2200));
    await settleApp(tester, const Duration(milliseconds: 400));

    // 1) 切到赛道表面，让「选择赛道」出现在首页。
    // 首页 PageView 里有多份 ModeSwitch 副本，只点当前可见的那一份。
    final trackSegment = find.text('赛道').hitTestable().first;
    expect(trackSegment, findsOneWidget, reason: '首页应可见街道/赛道分段控件');
    await tester.tap(trackSegment);
    await settleApp(tester, const Duration(milliseconds: 300));

    expect(
      find.text('选择赛道').hitTestable(),
      findsOneWidget,
      reason: '赛道表面下应出现「选择赛道」按钮',
    );

    // 2) 来回切换模式（汽车 / 摩托 / 卡丁），复现用户描述的操作顺序。
    // 模式切换有 900ms 防误触延迟，这里给足 1s。
    for (final icon in [
      Icons.two_wheeler,
      Icons.directions_car,
      Icons.sports_motorsports,
      Icons.directions_car,
    ]) {
      final target = find.byIcon(icon).hitTestable();
      if (target.evaluate().isNotEmpty) {
        await tester.tap(target.first);
        await settleApp(tester, const Duration(milliseconds: 1000));
      }
    }
    await settleApp(tester, const Duration(milliseconds: 300));

    // 3) 切换模式后按钮仍必须能立即弹出底部表。
    final selectButton = find.text('选择赛道').hitTestable();
    expect(selectButton, findsOneWidget);
    await tester.tap(selectButton);
    await tester.pump(); // 只推一帧：弹表本身不得依赖任何 await

    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: '点击「选择赛道」后应立即弹出底部表，而不是静默无响应',
    );

    await settleApp(tester, const Duration(milliseconds: 600));
    // 表内最终应给出可交互内容：赛道分组、空态、失败重试或正在读取
    // （widget 测试里真实磁盘 IO 不随假时钟推进，停留在加载态也算表内有反馈）。
    final hasContent =
        find.text('国内').evaluate().isNotEmpty ||
        find.text('我的赛道').evaluate().isNotEmpty ||
        find.text('暂无赛道包').evaluate().isNotEmpty ||
        find.text('赛道库读取失败').evaluate().isNotEmpty ||
        find.textContaining('正在读取赛道库').evaluate().isNotEmpty;
    expect(hasContent, isTrue, reason: '底部表应呈现赛道库内容、加载态或明确的失败重试');
    expect(tester.takeException(), isNull);
  });
}
