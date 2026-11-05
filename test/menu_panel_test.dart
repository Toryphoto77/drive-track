import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/main.dart';

void main() {
  testWidgets('v1.1.0 menu panel is exactly 280 wide, subtitles wrap inside it',
      (WidgetTester tester) async {
    // 小屏 + 大字体：复现用户实测的菜单底部描述溢出场景。
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: const DriveTrackApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pump(const Duration(milliseconds: 300));
    // 面板 Material 是“赛道库”菜单项的 Material 祖先。
    final panel = find.ancestor(
      of: find.text('赛道库'),
      matching: find.byType(Material),
    );
    expect(panel, findsOneWidget);
    final panelSize = tester.getSize(panel);
    expect(panelSize.width, 280.0);
    // 底部菜单项的副标题在面板内完整排版：其右边缘不超过面板右边缘。
    final subtitle = find.text('版本号、在线更新、反馈与备份');
    expect(subtitle, findsOneWidget);
    final subBox = tester.getTopLeft(subtitle);
    final subSize = tester.getSize(subtitle);
    expect(subBox.dx + subSize.width, lessThanOrEqualTo(280.0 + 0.5));
    expect(tester.takeException(), isNull);
  });
}
