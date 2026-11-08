import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/bt_gps_receiver.dart';
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
    expect(find.text('BleDIY 外部 GPS'), findsNothing);
    // 档案卡扩至兼容清单后页面变长，传感器区需滚动才进入
    // 懒加载 ListView 的视口；功能仍在，只是测试要按页顺序滚动断言。
    await tester.scrollUntilVisible(
      find.text('传感器：自定义 BLE 设备'),
      300,
    );
    await tester.pump();
    expect(find.text('传感器：自定义 BLE 设备'), findsOneWidget);
    // 旧的按品牌三张卡已删：设备中心里「高级 / 按品牌」整个区不在，
    // 相机唯一入口是「打开连接运动相机」（统一页覆盖 GoPro 直连与
    // Insta360 / DJI 向导）。先断言主入口，再断言旧区与旧操作全不在树里。
    expect(find.text('打开连接运动相机'), findsOneWidget);
    expect(find.text('高级 / 按品牌'), findsNothing);
    expect(find.text('扫描 GoPro 设备'), findsNothing);
    expect(find.text('连接（需原生支持）'), findsNothing);
    // 单入口主按钮在顶部；档案卡收进「高级 / 手动添加」，
    // 默认收起时不在树里，先展开再断言。
    expect(find.text('扫描适配设备'), findsOneWidget);
    expect(find.text('BleDIY'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('高级 / 手动添加'),
      300,
    );
    await tester.pump();
    await tester.tap(find.text('高级 / 手动添加'));
    await tester.pumpAndSettle();
    expect(find.text('BleDIY'), findsOneWidget);
    // 自定义表单收进展开区：未展开时字段不在树里。
    expect(find.text('名称，如：我的功率计'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('添加自定义传感器'),
      300,
    );
    await tester.pump();
    await tester.tap(find.text('添加自定义传感器'));
    await tester.pumpAndSettle();
    expect(find.text('名称，如：我的功率计'), findsOneWidget);
    expect(find.text('服务 UUID（完整或 4/8 位短 UUID）'), findsOneWidget);
    expect(find.text('特征 UUID（完整或 4/8 位短 UUID）'), findsOneWidget);
    expect(find.text('保存到本机'), findsOneWidget);
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
}
