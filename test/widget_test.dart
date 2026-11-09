import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/main.dart';
import 'package:drive_track/widgets.dart';

void main() {
  testWidgets('DriveTrack home smoke test', (WidgetTester tester) async {
    // 菜单 ListView 懒加载：默认 600 高视口装不下全部菜单项，
    // 把视口放大到 1600 高，菜单后两项也能直接构建断言。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DriveTrackApp());
    // v0.1.9：启动页约 1.5 秒动画跑完才进首页；用定长 pump 推进，
    // 不用 pumpAndSettle（权限引导页的 CircularProgressIndicator
    // 会无限动画，pumpAndSettle 永远等不到 settle）。
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 顶部居中加粗展示字体 logo（v0.1.2 起为 DriveTrackDisplay 替代衬线体）
    expect(find.text('DriveTrack'), findsOneWidget);
    // 模式横滑三页共用同一份首页主体，故开始记录出现 3 次
    expect(find.text('开始记录'), findsWidgets);
    // v0.1.2 模式图标为自绘矢量（跑车/仿赛/骑行），不再是 Material 通用图标
    expect(find.byType(ModeVehicleIcon), findsNWidgets(3));
    expect(find.byIcon(Icons.directions_car), findsNothing);
    expect(find.byIcon(Icons.motorcycle), findsNothing);
    // 药丸导航 + 滑动菜单各一份，故为多份
    expect(find.byIcon(Icons.home), findsWidgets);
    expect(find.byIcon(Icons.list_alt), findsWidgets);
    expect(find.byIcon(Icons.person), findsWidgets);
    // v1.5.4：设备中心移到第 4 个导航图标（设备），菜单里不再有该项。
    expect(find.byIcon(Icons.devices), findsWidgets);
    // 首页不再有可见权限按钮
    expect(find.text('请求权限'), findsNothing);
    // v0.1.2：首页天气实体按钮、大标定卡、演示入口全部移走/删除
    expect(find.text('获取当前位置天气'), findsNothing);
    expect(find.text('生成演示行程'), findsNothing);
    expect(find.text('标定车头方向'), findsNothing);
    // v0.1.3：标定改为首页下方大方块（标题“标定”+状态“未标定”），旧 chip 已删
    expect(find.text('标定'), findsWidgets);
    expect(find.text('未标定'), findsWidgets);
    expect(find.text('同步视频记录'), findsOneWidget);
    // v0.1.5：药丸开关移到大方块正上方（街道默认，赛道在右）；
    // 卫星快速开关改成紧凑 pill，暂无快照时显示“—”不编数。
    expect(find.text('街道'), findsOneWidget);
    expect(find.text('赛道'), findsOneWidget);
    expect(find.text('直连卫星 · —'), findsWidgets);
    // v0.1.5：侧拉菜单去重——首页/记录/我的不再出现在菜单里
    // （底部药丸导航仍有这三个图标入口，故图标断言仍成立，
    // 但菜单文本入口已删）；工具箱新结构在树里。
    // v0.1.7：菜单再简化去重——配置类入口全部只留设置页，菜单只留
    // 内容类快捷（赛道库/数据导出/备份/免责声明），
    // 旧“工具”/“设置快捷”分组已删，断言同步更新。
    // v1.5.4：设备中心已移出菜单（改走底部导航第 4 项），菜单不再有该项。
    // v1.0.3：关于从设置页移入左拉菜单，菜单新增“关于”一项。
    expect(find.text('首页'), findsNothing);
    expect(find.text('记录'), findsNothing);
    expect(find.text('我的'), findsNothing);
    expect(find.text('工具'), findsNothing);
    expect(find.text('设置快捷'), findsNothing);
    expect(find.text('赛道库'), findsOneWidget);
    expect(find.text('设备中心'), findsNothing);
    expect(find.text('数据导出/备份'), findsOneWidget);
    expect(find.text('免责声明'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });
}
