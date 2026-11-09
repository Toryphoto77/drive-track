import 'package:drive_track/app_icon_choice.dart';
import 'package:drive_track/frosted_nav_bar.dart';
import 'package:drive_track/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('v1.0.9 frosted nav: 288x56, tap switches, icons only, no scale animation widgets, no SafeArea inside pill', (tester) async {
    // v1.5.4：4 项（首页 / 设备 / 记录 / 我的），288x56，每项 72 节距。
    expect(kPillNavWidth, 288.0);
    expect(kPillNavHeight, 56.0);
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
    // 288 宽药丸存在、四个图标都在、只留图标无文字。
    expect(find.byType(FrostedGlassNavBar), findsOneWidget);
    // v1.0.5：药丸内不再用 SafeArea垫空底色区，底部位置由调用方 Positioned 直接算。
    expect(find.byType(SafeArea), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.byIcon(Icons.devices), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.text('设备'), findsNothing);
    // 无任何放大动画组件：滚动放大 AnimatedScale、切换拉伸 TweenAnimationBuilder、
    // 选中弹簧放大 AnimatedScale 均已删除。
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(TweenAnimationBuilder), findsNothing);
    // 点记录图标触发切换回调（记录是第 3 项，下标 2）。
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
    expect(selected, 2);
    // 点设备图标触发第 2 项回调（下标 1，main 侧打开设备中心）。
    await tester.tap(find.byIcon(Icons.devices));
    await tester.pump();
    expect(selected, 1);
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
