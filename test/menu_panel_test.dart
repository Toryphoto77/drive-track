import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/main.dart';

void main() {
  debugAllowUnsignedMainUi = true;
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
    await tester.pump(const Duration(milliseconds: 1600));
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
    // v1.5.2：菜单由 6 项增至 7 项（新增“赛道知识库”），小屏 + 大字体
    // 下最后一项需滚动才可见——列表本身就是可滚动的 ListView（见
    // main.dart 菜单面板注释）。注意：本测试里点汉堡钮并不能真正打
    // 开菜单（点按落不到按钮上，面板只是以关闭态躺在树里做布局），
    // 手势拖拽同样落不到列表上，所以直接用 jumpTo 把列表滚到底：
    // 面板布局与菜单开闭无关，断言的仍是真实排版。
    final menuList = find.ancestor(
      of: find.text('赛道库'),
      matching: find.byType(ListView),
    );
    final scrollable =
        find.descendant(of: menuList, matching: find.byType(Scrollable));
    final scrollState = tester.state<ScrollableState>(scrollable.first);
    scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 100));
    // 底部菜单项的副标题在面板内完整排版：其右边缘不超过面板右边缘。
    final subtitle = find.text('版本号、在线更新、反馈与备份');
    expect(subtitle, findsOneWidget);
    final subBox = tester.getTopLeft(subtitle);
    final subSize = tester.getSize(subtitle);
    expect(subBox.dx + subSize.width, lessThanOrEqualTo(280.0 + 0.5));
    expect(tester.takeException(), isNull);
  });
}
