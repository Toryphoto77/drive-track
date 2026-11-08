import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/device_center.dart';

void main() {
  group('单入口过滤与档案推导（纯函数）', () {
    test('档案名录匹配进主列表，耳机不进', () {
      expect(
          gpsDeviceIsAdaptable({
            'name': 'DEXIAN D1',
            'address': 'AA:BB:CC:DD:EE:01',
            'serviceUuids': <String>[],
          }),
          isTrue);
      expect(
          gpsDeviceIsAdaptable({
            'name': 'My Headphones',
            'address': 'AA:BB:CC:DD:EE:02',
            'serviceUuids': <String>[],
          }),
          isFalse);
    });

    test('广播 NUS / SPP 服务进主列表', () {
      expect(
          gpsDeviceIsAdaptable({
            'name': 'Unknown Box',
            'address': 'AA:BB:CC:DD:EE:03',
            'serviceUuids': ['6e400001-b5a3-f393-e0a9-e50e24dcca9e'],
          }),
          isTrue);
      expect(
          gpsDeviceIsAdaptable({
            'name': 'Unknown SPP',
            'address': 'AA:BB:CC:DD:EE:04',
            'serviceUuids': ['00001101-0000-1000-8000-00805f9b34fb'],
          }),
          isTrue);
    });

    test('D1 服务 UUID 进主列表：无名称证据也进（服务 UUID 优先）', () {
      expect(
          gpsDeviceIsAdaptable({
            'name': 'Unknown Box',
            'address': 'AA:BB:CC:DD:EE:05',
            'serviceUuids': ['00000003-0000-1000-8000-00805f9b34fb'],
          }),
          isTrue);
      expect(
          gpsDeviceIsAdaptable({
            'name': 'Unknown Box',
            'address': 'AA:BB:CC:DD:EE:06',
            'serviceUuids': ['00000004-0000-1000-8000-00805f9b34fb'],
          }),
          isFalse);
    });

    test('D1 广播名模式进主列表：dexian D1-XXXX（大小写不敏感）', () {
      expect(
          gpsDeviceIsAdaptable({
            'name': 'dexian D1-AB12',
            'address': 'AA:BB:CC:DD:EE:07',
            'serviceUuids': <String>[],
          }),
          isTrue);
      expect(
          gpsDeviceIsAdaptable({
            'name': 'DEXIAN D1',
            'address': 'AA:BB:CC:DD:EE:08',
            'serviceUuids': <String>[],
          }),
          isTrue);
    });

    test('档案推导：D1 名称 → dexian，RaceBox 服务 → racebox，其余 → 通用',
        () {
      expect(
          gpsProfileKindForDevice({
            'name': 'DEXIAN D1',
            'serviceUuids': <String>[],
          }),
          ExternalGpsKind.dexian);
      expect(
          gpsProfileKindForDevice({
            'name': 'Some Box',
            'serviceUuids': [
              '00001101-0000-1000-8000-00805f9b34fb',
              '00001103-0000-1000-8000-00805f9b34fb',
            ],
          }),
          ExternalGpsKind.racebox);
      expect(
          gpsProfileKindForDevice({
            'name': 'Some Box',
            'serviceUuids': <String>[],
          }),
          ExternalGpsKind.genericNmea);
    });

    test('档案推导：D1 服务 UUID 优先于名称（无名设备也认 dexian）', () {
      expect(
          gpsProfileKindForDevice({
            'name': 'Some Box',
            'serviceUuids': ['00000003-0000-1000-8000-00805f9b34fb'],
          }),
          ExternalGpsKind.dexian);
      expect(
          gpsProfileKindForDevice({
            'name': 'dexian D1-AB12',
            'serviceUuids': <String>[],
          }),
          ExternalGpsKind.dexian);
    });
  });

  group('单入口流程 widget', () {
    const nativeChannel = MethodChannel('drivetrack/native');

    Future<void> pushEvent(
        String channel, Map<String, dynamic> event) async {
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
    }

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel,
              (MethodCall call) async {
        switch (call.method) {
          case 'checkPermissions':
            return {
              'bluetooth': true,
              'location': true,
              'foreground': true,
              'background': true,
              'notifications': true,
              'permanentlyDenied': <String>[],
            };
          case 'scanBleWithServices':
            return null;
          case 'scanBleUnfiltered':
            return true;
          case 'startClassicDiscovery':
            return true;
          case 'listBondedSppDevices':
            return <Map<String, dynamic>>[];
          case 'stopBleScan':
          case 'stopClassicDiscovery':
          case 'setBleAutoReconnect':
          case 'connectBle':
            return null;
          case 'subscribeBleCharacteristic':
            return {'ok': true};
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null);
    });

    testWidgets('点主按钮 → 合并列表出现 → 点设备 → 连接状态变化',
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
          home: const Scaffold(
            body: SingleChildScrollView(child: ExternalGpsSection()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // 初始：主按钮可见，高级区收起、档案卡不在树里。
      expect(find.text('扫描适配设备'), findsOneWidget);
      expect(find.text('高级 / 手动添加'), findsOneWidget);
      expect(find.text('BleDIY'), findsNothing);
      expect(find.text('尚未扫描：点上方「扫描适配设备」开始。'),
          findsOneWidget);

      // 点主按钮 → 停止态 + 扫描提示。
      await tester.tap(find.text('扫描适配设备'));
      await tester.pump();
      await tester.pump();
      expect(find.text('停止扫描'), findsOneWidget);
      expect(
          find.text('正在扫描周围可适配的 GPS 设备（BLE + 经典蓝牙 + 已配对）…'),
          findsOneWidget);

      // 注入发现事件：D1（名称匹配）进主列表，耳机只进高级区。
      await pushEvent('drivetrack/btGpsDevices', {
        'name': 'DEXIAN D1',
        'address': 'AA:BB:CC:DD:EE:01',
        'type': 'ble',
        'rssi': -60,
        'serviceUuids': <String>[],
      });
      await tester.pump();
      expect(find.text('DEXIAN D1'), findsOneWidget);
      await pushEvent('drivetrack/btGpsDevices', {
        'name': 'My Headphones',
        'address': 'AA:BB:CC:DD:EE:02',
        'type': 'ble',
        'rssi': -70,
        'serviceUuids': <String>[],
      });
      await tester.pump();
      expect(find.text('My Headphones'), findsNothing);

      // 点 D1 行 → 连接中。
      await tester.tap(find.text('DEXIAN D1'));
      await tester.pump();
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);

      // 注入 connected 事件 → 行内已连接。
      await pushEvent('drivetrack/bleData', {
        'type': 'connected',
        'address': 'AA:BB:CC:DD:EE:01',
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('连接中'), findsNothing);

      // 展开高级区：全部结果里耳机也在，数据没丢。
      // 注意：此时合并扫描仍在进行，共用扫描卡片的波纹动画（1800ms 循环）
      // 在持续调度帧，pumpAndSettle 永远等不到静止；展开动画只需 pump
      // 几帧即可断言，不用 pumpAndSettle。
      await tester.tap(find.text('高级 / 手动添加'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('My Headphones'), findsOneWidget);
      expect(find.text('BleDIY'), findsOneWidget);
      // 合并扫描进行中时，旧分别扫描按钮的文案本来就是“停止扫描”
      //（与合并扫描共享底层 BLE 扫描状态），故断言静态文案的按钮。
      expect(find.text('已配对 SPP'), findsOneWidget);
      expect(find.text('订阅 NMEA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
