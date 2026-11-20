import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/device_center.dart';

void main() {
  const nativeChannel = MethodChannel('drivetrack/native');
  late Directory tempDir;

  Future<void> pushBleData(Map<String, dynamic> event) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'drivetrack/bleData',
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dt_autosave');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
      switch (call.method) {
        case 'getFilesDir':
          return tempDir.path;
        case 'checkPermissions':
          return {
            'bluetooth': true,
            'location': true,
            'foreground': true,
            'background': true,
            'notifications': true,
            'permanentlyDenied': <String>[],
          };
        case 'listBondedSppDevices':
          return <Map<String, dynamic>>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets(
      'v1.7.9 连接成功后自动加入「我的设备」，并按地址去重',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
        ),
        home: const Scaffold(body: DeviceCenterPage()),
      ),
    );
    await tester.pump();

    // 初始：我的设备空态，目标设备不存在。
    expect(find.text('尚未连接设备'), findsOneWidget);
    expect(find.text('Test GPS'), findsNothing);

    // 注入原生 connected 事件（带 address + name）。
    await pushBleData({
      'type': 'connected',
      'address': 'AA:BB:CC:DD:EE:01',
      'name': 'Test GPS',
    });
    await tester.pump();

    // 设备出现在「我的设备」（_saved 被写入并刷新）。
    expect(find.text('Test GPS'), findsOneWidget);
    expect(find.text('尚未连接设备'), findsNothing);

    // 同地址再次 connected：不应产生重复条目。
    await pushBleData({
      'type': 'connected',
      'address': 'AA:BB:CC:DD:EE:01',
      'name': 'Test GPS',
    });
    await tester.pump();
    expect(find.text('Test GPS'), findsOneWidget);
  });
}
