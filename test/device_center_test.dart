import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/bt_gps_receiver.dart';
import 'package:drive_track/device_center.dart';

void main() {
  testWidgets('v1.7.1 device center: 我的设备 + 可添加设备两张卡',
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
        home: const DeviceCenterPage(),
      ),
    );
    await tester.pump();
    expect(find.text('设备中心'), findsOneWidget);
    // 两段：我的设备（空态）+ 可添加设备（三行）。
    expect(find.text('我的设备'), findsOneWidget);
    expect(find.text('尚未连接设备'), findsOneWidget);
    expect(find.text('连接传感器或外接 GPS 后在这里管理'), findsOneWidget);
    expect(find.text('可添加设备'), findsOneWidget);
    expect(find.text('运动相机'), findsOneWidget);
    expect(find.text('GoPro · Insta360 · DJI'), findsOneWidget);
    expect(find.text('外接 GPS 模块'), findsOneWidget);
    expect(find.text('OBD（ELM327）'), findsOneWidget);
    expect(find.text('敬请期待'), findsOneWidget);
    // 相机入口就在行内，不再有旧的整卡按钮。
    expect(find.text('打开连接运动相机'), findsNothing);
    // 扫描长列表与手动表单已收进扫描面板，不在页面里。
    expect(find.text('传感器：附近扫描结果'), findsNothing);
    expect(find.text('开始扫描'), findsNothing);
    expect(find.text('传感器：已保存设备（点重连）'), findsNothing);
    expect(find.text('传感器：自定义 BLE 设备'), findsNothing);
    expect(find.text('扫描适配设备'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v1.5.4 OBD 占位行：点按弹「敬请期待」，不走真实连接',
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
        home: const DeviceCenterPage(),
      ),
    );
    await tester.pump();
    expect(find.text('OBD（ELM327）'), findsOneWidget);
    await tester.tap(find.text('OBD（ELM327）'));
    await tester.pump();
    expect(find.text('OBD · 敬请期待'), findsOneWidget);
    expect(find.textContaining('正在路上'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    expect(find.text('OBD · 敬请期待'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v1.7.2 GPS 行拉起底部面板：标题为 GPS，可关闭',
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
        home: const DeviceCenterPage(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('外接 GPS 模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GPS'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('取消'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('Dragy 档案无 UUID、私有协议 stub；DEXIAN D1 服务 UUID 已验证、二进制协议', () {
    final dragy = externalGpsProfiles
        .firstWhere((p) => p.kind == ExternalGpsKind.dragy);
    expect(dragy.serviceUuid, isNull);
    expect(dragy.txUuid, isNull);
    expect(dragy.hasNmeaPath, isFalse);
    expect(dragy.supportBadge, contains('协议未公开'));
    expect(dragy.supportBadge, contains('未实测验证'));
    final dexian = externalGpsProfiles
        .firstWhere((p) => p.kind == ExternalGpsKind.dexian);
    expect(dexian.name, 'DEXIAN D1');
    expect(dexian.serviceUuid, dexianServiceUuid);
    expect(dexian.txUuid, isNull);
    expect(dexian.hasNmeaPath, isFalse);
    expect(dexian.binaryProtocol, isTrue);
    expect(dexian.supportBadge, contains('二进制协议'));
    expect(dexian.supportBadge, contains('待实测'));
    expect(
      externalGpsProfiles
          .firstWhere((p) => p.kind == ExternalGpsKind.blediy)
          .hasNmeaPath,
      isTrue,
    );
  });

  testWidgets(
      'embedded tab chrome: no back AppBar, no in-page title, matches list page pattern',
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
          backgroundColor: Color(0xFF121212),
          body: DeviceCenterPage(embedded: true),
        ),
      ),
    );
    await tester.pump();
    // v1.7.4：左上角不再画“设备中心”大标题，直接进卡片。
    expect(find.text('设备中心'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('运动相机'), findsOneWidget);
    // v1.7.2：页内不再有右上角 + 号，卡片里也不再放“扫描设备”按钮。
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.text('扫描设备'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
