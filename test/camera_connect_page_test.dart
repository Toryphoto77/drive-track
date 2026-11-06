import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/camera_connect_page.dart';
import 'package:drive_track/camera_guide.dart';
import 'package:drive_track/device_center.dart';

void main() {
  group('v1.2.12 camera brand identification (pure)', () {
    test('FEA6 broadcast identifies GoPro', () {
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:01',
          'name': 'GP-1234',
          'serviceUuids': ['0000fea6-0000-1000-8000-00805f9b34fb'],
        }),
        CameraBrand.gopro,
      );
      // 大小写不敏感。
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:01',
          'name': '',
          'serviceUuids': ['0000FEA6-0000-1000-8000-00805F9B34FB'],
        }),
        CameraBrand.gopro,
      );
    });

    test('name identifies GoPro / Insta360 / DJI without FEA6', () {
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:02',
          'name': 'GoPro Hero 12',
          'serviceUuids': <String>[],
        }),
        CameraBrand.gopro,
      );
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:03',
          'name': 'Insta360 X4',
          'serviceUuids': <String>[],
        }),
        CameraBrand.insta360,
      );
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:04',
          'name': 'DJI Osmo Action 5',
          'serviceUuids': <String>[],
        }),
        CameraBrand.dji,
      );
    });

    test('unrecognized device is unknown and never a camera', () {
      expect(
        identifyCameraBrand({
          'address': 'AA:BB:CC:DD:EE:05',
          'name': 'AirPods Pro',
          'serviceUuids': <String>[],
        }),
        CameraBrand.unknown,
      );
      expect(
        ScannedCamera.fromScan({
          'address': 'AA:BB:CC:DD:EE:05',
          'name': 'AirPods Pro',
          'serviceUuids': <String>[],
        }).brand,
        CameraBrand.unknown,
      );
    });

    test('connection labels never fake direct connect for guide brands', () {
      expect(cameraConnectionLabel(CameraBrand.gopro), 'BLE 直连');
      expect(cameraConnectionLabel(CameraBrand.insta360), '向导连接');
      expect(cameraConnectionLabel(CameraBrand.dji), '向导连接');
      expect(cameraBrandIsGuideOnly(CameraBrand.gopro), isFalse);
      expect(cameraBrandIsGuideOnly(CameraBrand.insta360), isTrue);
      expect(cameraBrandIsGuideOnly(CameraBrand.dji), isTrue);
      expect(cameraGuideBrandFor(CameraBrand.gopro), isNull);
      expect(
        cameraGuideBrandFor(CameraBrand.insta360),
        CameraGuideBrand.insta360,
      );
      expect(cameraGuideBrandFor(CameraBrand.dji), CameraGuideBrand.dji);
      expect(cameraBrandLabel(CameraBrand.insta360), 'Insta360');
      expect(cameraBrandLabel(CameraBrand.dji), 'DJI');
    });

    test('guide summaries state no direct connect (verbatim source)', () {
      expect(
        cameraGuides[CameraGuideBrand.insta360]!.connectionSummary,
        contains('本 App 目前不直连相机'),
      );
      expect(
        cameraGuides[CameraGuideBrand.dji]!.connectionSummary,
        contains('本 App 目前不直连相机'),
      );
    });

    test('ScannedCamera.fromScan keeps address / name / rssi', () {
      final cam = ScannedCamera.fromScan({
        'address': 'AA:BB:CC:DD:EE:06',
        'name': 'Insta360 X4',
        'rssi': -55,
        'serviceUuids': <String>[],
      });
      expect(cam.address, 'AA:BB:CC:DD:EE:06');
      expect(cam.name, 'Insta360 X4');
      expect(cam.brand, CameraBrand.insta360);
      expect(cam.rssi, -55);
    });
  });

  testWidgets('v1.2.12 camera connect page renders one big scan card',
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
    // AppBar 标题与大卡片标题同名，共 2 处。
    expect(find.text('连接运动相机'), findsNWidgets(2));
    expect(find.text('扫描相机'), findsOneWidget);
    expect(find.text('搜到的相机'), findsOneWidget);
    // 大卡片说明：GoPro 直连、Insta360 / DJI 向导，不用先选品牌。
    expect(find.textContaining('GoPro 走 BLE 直连'), findsOneWidget);
    expect(find.textContaining('不用先选品牌'), findsOneWidget);
    // 未扫描时不出现假的已连接 / 假的同步录像入口。
    expect(find.text('已连接相机'), findsNothing);
    expect(find.text('开始同步录像（待接入）'), findsNothing);
    // 扫描按钮在测试环境（无原生通道）下点按不抛异常，只提示权限失败。
    await tester.tap(find.text('扫描相机'));
    await tester.pump();
    expect(find.text('扫描相机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v1.2.12 device center entry opens the unified page',
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
    // 主入口在顶部；旧的按品牌卡片已删，设备中心里只有一个相机入口。
    expect(find.text('打开连接运动相机'), findsOneWidget);
    expect(find.text('扫描 GoPro 设备'), findsNothing);
    await tester.tap(find.text('打开连接运动相机'));
    await tester.pumpAndSettle();
    expect(find.text('扫描相机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
