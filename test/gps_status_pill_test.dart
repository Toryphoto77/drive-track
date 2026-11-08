/// 首页外接 GPS 状态小药丸测试（v1.5.2）。
///
/// 覆盖：未连接时显示“未连接外接 GPS · 去连接”；设备中心写入
/// 已连接状态后药丸显示设备名；断开后恢复未连接态。
/// 状态源为全局 externalGpsStatus（设备中心唯一写入入口），
/// 测试用例结束时复位，避免污染其它测试。

import 'package:drive_track/gps_source.dart';
import 'package:drive_track/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    testWidgets('未连接时显示未连接态', (tester) async {
      await pumpHome(tester);
      expect(find.text('未连接外接 GPS'), findsOneWidget);
      expect(find.text('去连接 ›'), findsOneWidget);
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
      expect(find.text('外接 GPS · DEXIAN D1'), findsOneWidget);
      expect(find.text('未连接外接 GPS'), findsNothing);
      updateExternalGpsStatus(ExternalGpsStatus.disconnected);
      await tester.pump();
      expect(find.text('未连接外接 GPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
