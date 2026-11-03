import 'package:drive_track/app_icon_choice.dart';
import 'package:drive_track/frosted_nav_bar.dart';
import 'package:drive_track/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('v1.0.9 frosted nav: 216x56, tap switches, icons only, no scale animation widgets, no SafeArea inside pill', (tester) async {
    expect(kPillNavWidth, 216.0);
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
    // 216 宽药丸存在、三个图标都在、只留图标无文字。
    expect(find.byType(FrostedGlassNavBar), findsOneWidget);
    // v1.0.5：药丸内不再用 SafeArea垫空底色区，底部位置由调用方 Positioned 直接算。
    expect(find.byType(SafeArea), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.list_alt), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    // 无任何放大动画组件：滚动放大 AnimatedScale、切换拉伸 TweenAnimationBuilder、
    // 选中弹簧放大 AnimatedScale 均已删除。
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(TweenAnimationBuilder), findsNothing);
    // 点记录图标触发切换回调。
    await tester.tap(find.byIcon(Icons.list_alt));
    await tester.pump();
    expect(selected, 1);
  });

  test('v1.0.3 app icon choice: red default, blue asset/label differ, invalid normalizes to red', () {
    expect(AppIconChoice.normalize(null), AppIconChoice.red);
    expect(AppIconChoice.normalize('bogus'), AppIconChoice.red);
    expect(AppIconChoice.normalize('gray'), AppIconChoice.blue);
    expect(AppIconChoice.assetFor(AppIconChoice.red), 'assets/app_icon_red.png');
    expect(AppIconChoice.assetFor(AppIconChoice.blue), 'assets/app_icon_blue.png');
    expect(AppIconChoice.labelFor(AppIconChoice.red), '红赛车');
    expect(AppIconChoice.labelFor(AppIconChoice.blue), '蓝仪表');
    expect(AppIconChoice.assetFor(AppIconChoice.red),
        isNot(AppIconChoice.assetFor(AppIconChoice.blue)));
  });
}
