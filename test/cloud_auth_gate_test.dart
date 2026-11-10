import 'dart:io';

import 'package:drive_track/cloud_auth_page.dart';
import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    debugAllowUnsignedMainUi = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drivetrack/native'),
      (call) async {
        if (call.method == 'getFilesDir' || call.method == 'getCacheDir') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('drivetrack/native'), null);
  });

  testWidgets('没有正式会话时启动后停在登录页，不进入记录界面', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => CloudService.instance.init());
    await tester.pumpWidget(const DriveTrackApp());
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('开始记录'), findsNothing);
    expect(find.text('手机号登录'), findsWidgets);
    expect(find.text('手机号注册'), findsWidgets);
    expect(find.text('使用微信登录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('登录页默认是手机号，区号可选可填，没有微信入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CloudAuthPage(gate: true),
    ));
    await tester.pump();
    expect(find.text('手机号登录'), findsWidgets);
    expect(find.text('中国大陆 +86'), findsOneWidget);
    expect(find.text('使用微信登录'), findsNothing);
    expect(find.textContaining('AppID'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
