import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/device_center.dart';
import 'package:drive_track/native.dart';

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

  testWidgets('v1.7.9 连接成功后自动加入「我的设备」，并按地址去重', (WidgetTester tester) async {
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

    // “我的设备”不能只有名字：类型 / 连接状态 / 地址都要能看到。
    expect(find.textContaining('外接GPS'), findsOneWidget);
    expect(find.textContaining('已连接'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:01'), findsOneWidget);
  });

  testWidgets('v1.7.14 已连接设备是大卡片，点按进入完整管理页', (WidgetTester tester) async {
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
    await pushBleData({
      'type': 'connected',
      'address': 'AA:BB:CC:DD:56:F6',
      'name': 'DriveTrack-56F6',
    });
    await tester.pump();

    // 不再只是一个带重连 / 删除按钮的小长条。
    expect(find.text('查看设备详情与管理'), findsOneWidget);
    await tester.tap(find.text('查看设备详情与管理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('设备管理'), findsOneWidget);
    expect(find.text('连接与信号'), findsOneWidget);
    expect(find.text('传感器状态'), findsOneWidget);
    expect(find.text('卫星与定位'), findsOneWidget);
    expect(find.text('固件信息'), findsOneWidget);
    expect(find.text('硬件存储'), findsOneWidget);
    expect(find.text('更改配对密码'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  test('自动重连显式关闭系统配对请求，手动连接仍默认请求配对', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          calls.add(call);
          return null;
        });

    await Native.connectBle('AA:BB:CC:DD:56:F6', requestBond: false);
    await Native.connectBle('AA:BB:CC:DD:56:F6');

    expect(calls, hasLength(2));
    expect(calls[0].arguments, {
      'address': 'AA:BB:CC:DD:56:F6',
      'requestBond': false,
    });
    expect(calls[1].arguments, {
      'address': 'AA:BB:CC:DD:56:F6',
      'requestBond': true,
    });

    final mainSource = File('lib/main.dart').readAsStringSync();
    final autoStart = mainSource.indexOf(
      'Future<void> _autoReconnectSavedDevice()',
    );
    final autoEnd = mainSource.indexOf('/// 过线反馈', autoStart);
    final autoBlock = mainSource.substring(autoStart, autoEnd);
    expect(autoBlock, contains('requestBond: false'));
  });

  testWidgets('自研硬件手动重连也不主动请求系统配对', (WidgetTester tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          calls.add(call);
          if (call.method == 'getFilesDir') return tempDir.path;
          return null;
        });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DeviceCenterPage())),
    );
    await tester.pump();
    await pushBleData({
      'type': 'connected',
      'address': 'AA:BB:CC:DD:56:F6',
      'name': 'DriveTrack-56F6',
    });
    await tester.pump();
    await pushBleData({'type': 'disconnected'});
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '连接'));
    await tester.pump();

    final connect = calls.lastWhere((call) => call.method == 'connectBle');
    expect(connect.arguments, {
      'address': 'AA:BB:CC:DD:56:F6',
      'requestBond': false,
    });
  });

  test('设备管理页能读取已连接 BLE 的真实 RSSI', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'readBleRssi') return -57;
          return null;
        });
    expect(await Native.readBleRssi(), -57);
  });

  test('RSSI 无回调时超时返回 null，不阻塞设备状态刷新', () async {
    final neverCompletes = Completer<dynamic>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'readBleRssi') return neverCompletes.future;
          return null;
        });

    final value = await Native.readBleRssi().timeout(
      const Duration(seconds: 3),
      onTimeout: () => -999,
    );
    expect(value, isNull);
  });

  test('EventChannel 流缓存为单实例广播流，多页面不会互相顶掉原生订阅', () {
    // 每次 getter 都新建 receiveBroadcastStream 会覆盖原生消息处理器，
    // 后挂的页面顶掉先挂的页面（设备中心打开后全局 NMEA 断流）。
    expect(identical(Native.bleDataStream, Native.bleDataStream), isTrue);
    expect(Native.bleDataStream.isBroadcast, isTrue);
    expect(identical(Native.bleDeviceStream, Native.bleDeviceStream), isTrue);
    expect(Native.bleDeviceStream.isBroadcast, isTrue);
    expect(identical(Native.locationStream, Native.locationStream), isTrue);
    expect(Native.locationStream.isBroadcast, isTrue);
    expect(
      identical(Native.btGpsDeviceStream, Native.btGpsDeviceStream),
      isTrue,
    );
  });
}
