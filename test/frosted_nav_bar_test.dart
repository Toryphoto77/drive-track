import 'package:drive_track/app_icon_choice.dart';
import 'package:drive_track/frosted_nav_bar.dart';
import 'package:drive_track/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('v1.7.4 frosted nav: 4 tabs with icon + label, tap switches, no scale animation widgets, no SafeArea inside pill', (tester) async {
    // v1.5.4：4 项（首页 / 设备 / 记录 / 我的），每项 72 节距。
    // v1.7.4：加文字标签，药丸高度 56 → 68。
    expect(kPillNavWidth, 288.0);
    expect(kPillNavHeight, 68.0);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FrostedGlassNavBar(
                selectedIndex: selected,
                onTap: (i) => selected = i,
              ),
            ],
          ),
        ),
      ),
    );
    // 288 宽药丸存在、四个图标都在，图标下方带文字标签。
    expect(find.byType(FrostedGlassNavBar), findsOneWidget);
    // v1.0.5：药丸内不再用 SafeArea垫空底色区，底部位置由调用方 Positioned 直接算。
    expect(find.byType(SafeArea), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.sensors), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    // 无任何放大动画组件：滚动放大 AnimatedScale、切换拉伸 TweenAnimationBuilder、
    // 选中弹簧放大 AnimatedScale 均已删除。
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(TweenAnimationBuilder), findsNothing);
    // v1.7.2：药丸是自绘玻璃、不在 Material 上，点击区若沿用默认水波/
    // 高光会画到页面 Material 上，透过玻璃看就是一圈灰白底框。
    // 每个槽必须用透明 Material + 全透明高光色。
    final inks = tester.widgetList<InkWell>(find.byType(InkWell)).toList();
    expect(inks, hasLength(4));
    for (final ink in inks) {
      expect(ink.splashColor, Colors.transparent);
      expect(ink.highlightColor, Colors.transparent);
    }
    // 点记录图标触发切换回调（记录是第 3 项，下标 2）。
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
    expect(selected, 2);
    // 点设备图标触发第 2 项回调（下标 1，main 侧打开设备中心）。
    await tester.tap(find.byIcon(Icons.sensors));
    await tester.pump();
    expect(selected, 1);
  });

  test('navSelectionLeft puts the 48px circle on each slot center', () {
    const width = 288.0;
    for (var i = 0; i < 4; i++) {
      final left = navSelectionLeft(barWidth: width, index: i, count: 4);
      expect(left + 24, closeTo((i + 0.5) * width / 4, 0.01));
    }
  });

  testWidgets('selection circle shares a center with each tab icon', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const icons = [Icons.home, Icons.sensors, Icons.list_alt, Icons.person];
    for (var i = 0; i < icons.length; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FrostedGlassNavBar(selectedIndex: i, onTap: (_) {}),
          ),
        ),
      );
      await tester.pump();
      // v1.7.4：Q 弹缓动 320ms，等动画完全结束再测同心。
      await tester.pump(const Duration(milliseconds: 400));
      // v1.7.3：药丸宽度 = 屏幕宽 - 32（左右与内容卡 16 留白对齐）。
      expect(
        tester.getSize(find.byType(ClipRRect)).width,
        closeTo(360 - 32, 0.1),
      );
      final icon = tester.getCenter(find.byIcon(icons[i]));
      // v1.7.4：图标 + 文字整列居中，选中药丸与整槽（InkWell）同心。
      final slot = tester.getCenter(find.byType(InkWell).at(i));
      final circle = tester.getCenter(find.byKey(const Key('nav-selection-indicator')));
      expect((slot.dx - circle.dx).abs(), lessThan(1.0), reason: 'tab $i dx');
      expect((slot.dy - circle.dy).abs(), lessThan(1.0), reason: 'tab $i dy');
      expect((icon.dx - slot.dx).abs(), lessThan(1.0), reason: 'tab $i icon dx');
    }
  });

  test('app icon choice: steering default, legacy keys fall back to steering', () {
    expect(AppIconChoice.normalize(null), AppIconChoice.steering);
    expect(AppIconChoice.normalize('bogus'), AppIconChoice.steering);
    expect(AppIconChoice.normalize('gray'), AppIconChoice.steering);
    expect(AppIconChoice.normalize('blue'), AppIconChoice.steering);
    expect(AppIconChoice.isValid('blue'), isFalse);
    expect(AppIconChoice.isValid('gray'), isFalse);
    expect(AppIconChoice.assetFor(AppIconChoice.steering), 'assets/app_icon_steering.png');
    expect(AppIconChoice.assetFor('blue'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.labelFor(AppIconChoice.steering), '方向盘');
    expect(AppIconChoice.labelFor('blue'), '方向盘');
  });

  test('v1.2.2 app icon choice: steering and checkered keys valid, distinct assets/labels', () {
    expect(AppIconChoice.isValid('steering'), isTrue);
    expect(AppIconChoice.isValid('checkered'), isTrue);
    expect(AppIconChoice.normalize('steering'), 'steering');
    expect(AppIconChoice.normalize('checkered'), 'checkered');
    expect(AppIconChoice.assetFor('steering'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.assetFor('checkered'), 'assets/app_icon_checkered.png');
    expect(AppIconChoice.labelFor('steering'), '方向盘');
    expect(AppIconChoice.labelFor('checkered'), '方格旗');
    expect(AppIconChoice.assetFor('steering'),
        isNot(AppIconChoice.assetFor('checkered')));
  });

  test('app icon choice: deleted rb17/valkyrie/red keys fall back to steering', () {
    expect(AppIconChoice.isValid('rb17'), isFalse);
    expect(AppIconChoice.isValid('valkyrie'), isFalse);
    expect(AppIconChoice.isValid('red'), isFalse);
    expect(AppIconChoice.normalize('rb17'), 'steering');
    expect(AppIconChoice.normalize('valkyrie'), 'steering');
    expect(AppIconChoice.normalize('red'), 'steering');
    expect(AppIconChoice.assetFor('rb17'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.assetFor('valkyrie'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.assetFor('red'), 'assets/app_icon_steering.png');
    expect(AppIconChoice.labelFor('rb17'), '方向盘');
    expect(AppIconChoice.labelFor('valkyrie'), '方向盘');
    expect(AppIconChoice.labelFor('red'), '方向盘');
  });
}
