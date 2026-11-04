import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/device_center.dart';

void main() {
  testWidgets('v1.1.0 device center groups: camera / GPS / sensor',
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
    expect(find.text('外接设备中心'), findsOneWidget);
    // 三组标题（不再有重复的 BleDIY 说明区）。
    expect(find.text('运动相机'), findsOneWidget);
    expect(find.text('外接 GPS 模块'), findsOneWidget);
    expect(find.text('传感器：自定义 BLE 设备'), findsOneWidget);
    expect(find.text('RaceChrono BleDIY 外部 GPS'), findsNothing);
    // GoPro 主操作是扫描，不再是“连接（需原生支持）”。
    expect(find.text('扫描 GoPro 设备'), findsOneWidget);
    expect(find.text('连接（需原生支持）'), findsNothing);
    // Dragy / DEXIAN 如实标注未实测（仅选中档案才展开说明，故先点选）。
    expect(find.text('BleDIY（RaceChrono DIY 兼容）'), findsOneWidget);
    // 自定义表单收进展开区：未展开时字段不在树里。
    expect(find.text('名称，如：我的功率计'), findsNothing);
    await tester.tap(find.text('添加自定义传感器'));
    await tester.pumpAndSettle();
    expect(find.text('名称，如：我的功率计'), findsOneWidget);
    expect(find.text('服务 UUID（完整或 4/8 位短 UUID）'), findsOneWidget);
    expect(find.text('特征 UUID（完整或 4/8 位短 UUID）'), findsOneWidget);
    expect(find.text('保存到本机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('v1.1.0 Dragy/DEXIAN profiles carry no UUID and honest badge', () {
    for (final p in externalGpsProfiles) {
      if (p.kind == ExternalGpsKind.dragy ||
          p.kind == ExternalGpsKind.dexian) {
        expect(p.serviceUuid, isNull);
        expect(p.txUuid, isNull);
        expect(p.hasNmeaPath, isFalse);
        expect(p.supportBadge, contains('协议未公开'));
        expect(p.supportBadge, contains('未实测验证'));
      }
    }
    expect(
      externalGpsProfiles
          .firstWhere((p) => p.kind == ExternalGpsKind.blediy)
          .hasNmeaPath,
      isTrue,
    );
  });
}
