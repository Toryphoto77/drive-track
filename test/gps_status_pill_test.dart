/// 首页外接 GPS 状态小药丸测试（v1.5.2，v1.5.4 改纯状态显示）。
///
/// 覆盖：未连接时显示“手机 GPS · 外接未连接”；设备中心写入
/// 已连接状态后药丸显示设备名；断开后恢复未连接态。
/// v1.5.4：药丸不可点、不跳转，不再有“去连接 ›”文案；
/// 状态只看圆点颜色（绿 = 已连接，灰 = 未连接）。
/// 状态源为全局 externalGpsStatus（设备中心唯一写入入口），
/// 测试用例结束时复位，避免污染其它测试。

import 'package:drive_track/camera_connect_page.dart';
import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/device_center.dart';
import 'package:drive_track/gps_source.dart';
import 'package:drive_track/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  debugAllowUnsignedMainUi = true;
  group('首页外接 GPS 状态小药丸', () {
    setUp(() {
      externalGpsStatus.value = ExternalGpsStatus.disconnected;
    });

    tearDown(() {
      externalGpsStatus.value = ExternalGpsStatus.disconnected;
    });

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(const DriveTrackApp());
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('未连接时显示未连接态，无“去连接”文案', (tester) async {
      await pumpHome(tester);
      expect(find.text('手机 GPS · 外接未连接'), findsOneWidget);
      // v1.5.4：两颗药丸都不再带“去连接 ›”，也不再可点跳转。
      expect(find.text('去连接 ›'), findsNothing);
      expect(find.text('开始记录'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('药丸不可点：点按不进设备中心', (tester) async {
      await pumpHome(tester);
      expect(find.text('手机 GPS · 外接未连接'), findsOneWidget);
      await tester.tap(find.text('手机 GPS · 外接未连接'));
      await tester.pump();
      expect(find.text('外接设备中心'), findsNothing);
      expect(find.text('开始记录'), findsWidgets);
      await tester.tap(find.text('未连接运动相机'));
      await tester.pump();
      expect(find.text('外接设备中心'), findsNothing);
      expect(find.text('开始记录'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已连接时显示设备名，断开后恢复', (tester) async {
      await pumpHome(tester);
      updateExternalGpsStatus(const ExternalGpsStatus(
        connected: true,
        deviceName: 'DEXIAN D1',
        channel: 'ble',
      ));
      await tester.pump();
      expect(find.text('外接 GPS · DEXIAN D1 · BLE · 定位中'), findsOneWidget);
      expect(find.text('手机 GPS · 外接未连接'), findsNothing);
      updateExternalGpsStatus(ExternalGpsStatus.disconnected);
      await tester.pump();
      expect(find.text('手机 GPS · 外接未连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('首页运动相机状态小药丸', () {
    setUp(() {
      cameraLinkStatus.value = DeviceLinkStatus.disconnected;
    });

    tearDown(() {
      cameraLinkStatus.value = DeviceLinkStatus.disconnected;
    });

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(const DriveTrackApp());
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('未连接时显示未连接态', (tester) async {
      await pumpHome(tester);
      expect(find.text('未连接运动相机'), findsOneWidget);
      expect(find.text('手机 GPS · 外接未连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已连接时显示已连接，断开后恢复', (tester) async {
      await pumpHome(tester);
      updateCameraLinkStatus(DeviceLinkStatus.connected);
      await tester.pump();
      expect(find.text('运动相机 · 已连接'), findsOneWidget);
      expect(find.text('未连接运动相机'), findsNothing);
      updateCameraLinkStatus(DeviceLinkStatus.disconnected);
      await tester.pump();
      expect(find.text('未连接运动相机'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('连接中与暂不可用各有文案', (tester) async {
      await pumpHome(tester);
      updateCameraLinkStatus(DeviceLinkStatus.connecting);
      await tester.pump();
      expect(find.text('运动相机 · 连接中…'), findsOneWidget);
      updateCameraLinkStatus(DeviceLinkStatus.unavailable);
      await tester.pump();
      expect(find.text('运动相机 · 暂不可用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
