import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/camera_connect_page.dart';
import 'package:drive_track/device_center.dart';
import 'package:drive_track/device_scan_card.dart';

void main() {
  group('v1.2.12 共用扫描卡片（纯 widget）', () {
    testWidgets('空态：静态红圈图标 + 状态行，无波纹', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
          ),
          home: Scaffold(
            body: DeviceScanCard(
              title: '外接 GPS',
              description: '一次扫完周围可适配的 GPS 设备。',
              icon: Icons.satellite_alt,
              scanning: false,
              scanLabel: '扫描适配设备',
              stopLabel: '停止扫描',
              onScanToggle: () {},
              statusLine: '尚未扫描，点「扫描适配设备」。',
              footnote: '示例脚注：设备须开机、蓝牙打开。',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('外接 GPS'), findsOneWidget);
      expect(find.text('扫描适配设备'), findsOneWidget);
      expect(find.text('尚未扫描，点「扫描适配设备」。'), findsOneWidget);
      expect(find.textContaining('示例脚注'), findsOneWidget);
      expect(find.byType(DeviceScanRipple), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('扫描中：波纹动画 + 停止按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
          ),
          home: Scaffold(
            body: DeviceScanCard(
              title: '外接 GPS',
              description: '一次扫完周围可适配的 GPS 设备。',
              icon: Icons.satellite_alt,
              scanning: true,
              scanLabel: '扫描适配设备',
              stopLabel: '停止扫描',
              onScanToggle: () {},
              statusLine: '正在扫描附近 GPS（BLE、经典蓝牙、已配对）…',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DeviceScanRipple), findsOneWidget);
      expect(find.text('停止扫描'), findsOneWidget);
      expect(find.text('扫描适配设备'), findsNothing);
      expect(
          find.text('正在扫描附近 GPS（BLE、经典蓝牙、已配对）…'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('设备行：空闲 / 连接中 / 已连接三种状态', (tester) async {
      Widget row({bool connecting = false, bool connected = false}) {
        return MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
          ),
          home: Scaffold(
            body: DeviceScanRow(
              title: 'DEXIAN D1',
              badgeLabel: 'BLE',
              detail: '名称匹配：DEXIAN D1。',
              meta: '信号 -60 · AA:BB:CC:DD:EE:01',
              actionLabel: '点按连接',
              connectingLabel: '连接中',
              isConnecting: connecting,
              isConnected: connected,
              onTap: () {},
            ),
          ),
        );
      }

      await tester.pumpWidget(row());
      await tester.pump();
      expect(find.text('DEXIAN D1'), findsOneWidget);
      expect(find.text('BLE'), findsOneWidget);
      expect(find.text('点按连接'), findsOneWidget);
      expect(find.text('已连接'), findsNothing);

      await tester.pumpWidget(row(connecting: true));
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(row(connected: true));
      await tester.pump();
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('点按连接'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('相机页用共用卡片：标题与扫描按钮不变',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
          ),
          home: const CameraConnectPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(DeviceScanCard), findsOneWidget);
      expect(find.text('连接运动相机'), findsNWidgets(2));
      expect(find.text('扫描相机'), findsOneWidget);
      // 空态：无波纹。
      expect(find.byType(DeviceScanRipple), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2.12 GPS 动态匹配卡片 widget', () {
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

    testWidgets('空态 → 扫描中（波纹）→ D1 行 → 连接中 → 已连接',
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

      // 空态：共用卡片在位，D1 专属脚注已删（不再有“第一测试目标”文案），
      // 状态行只出现一次。
      expect(find.byType(DeviceScanCard), findsOneWidget);
      expect(find.text('外接 GPS'), findsOneWidget);
      expect(find.textContaining('第一测试目标'), findsNothing);
      expect(find.textContaining('BLE 服务 UUID 仍未知'), findsNothing);
      expect(find.text('尚未扫描，点「扫描适配设备」。'), findsOneWidget);
      expect(find.byType(DeviceScanRipple), findsNothing);
      expect(find.text('可适配设备'), findsOneWidget);
      // 旧的裸按钮 / ListTile 已不在：标题与按钮文案只剩卡片里的一处。
      expect(find.text('扫描适配设备'), findsOneWidget);

      // 点主按钮 → 扫描中：波纹出现，按钮变停止态，状态行只出现一次。
      await tester.tap(find.text('扫描适配设备'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(DeviceScanRipple), findsOneWidget);
      expect(find.text('停止扫描'), findsOneWidget);
      expect(
          find.text('正在扫描附近 GPS（BLE、经典蓝牙、已配对）…'),
          findsOneWidget);

      // 注入 D1：行卡片出现，徽标 BLE、说明为名称匹配提示、点按连接。
      await pushEvent('drivetrack/btGpsDevices', {
        'name': 'DEXIAN D1',
        'address': 'AA:BB:CC:DD:EE:01',
        'type': 'ble',
        'rssi': -60,
        'serviceUuids': <String>[],
      });
      await tester.pump();
      expect(find.byType(DeviceScanRow), findsOneWidget);
      expect(find.text('DEXIAN D1'), findsOneWidget);
      expect(find.text('BLE'), findsOneWidget);
      expect(find.textContaining('名称匹配'), findsOneWidget);
      expect(find.text('点按连接'), findsOneWidget);

      // 点 D1 行 → 连接中（GPS 旧文案，无省略号）。
      await tester.tap(find.text('DEXIAN D1'));
      await tester.pump();
      await tester.pump();
      expect(find.text('连接中'), findsOneWidget);

      // 注入 connected 事件 → 行内已连接（绿字），连接中消失。
      await pushEvent('drivetrack/bleData', {
        'type': 'connected',
        'address': 'AA:BB:CC:DD:EE:01',
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('连接中'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
