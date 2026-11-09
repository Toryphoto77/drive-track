/// 个人页分段控件与资料卡合并测试（v1.5.1）。
///
/// 覆盖：行程/动态/收藏/成就四段均渲染，标签与数字分开显示
/// （居中、无混排错位）；关注/粉丝/获赞已并进资料卡（不再是
/// 独立卡片）；点“动态”切换分区。

import 'package:drive_track/app_locale.dart';
import 'package:drive_track/home_layout.dart';
import 'package:drive_track/my_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page({List<MyTripItem> trips = const [], VoidCallback? onShareInvite}) {
  return MaterialApp(
    home: Scaffold(
      body: MyPage(
        username: '柴西',
        userId: 'DT-1234',
        bio: 'hello',
        stats: const [],
        following: 0,
        followers: 0,
        likes: 0,
        trips: trips,
        posts: const [],
        favorites: const [],
        achievements: const [],
        onShareInvite: onShareInvite,
      ),
    ),
  );
}

void main() {
  group('MyPage 分段控件与资料卡', () {
    testWidgets('四段 + 数字分开渲染，社交数字在资料卡内', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pump();
      expect(find.text('行程'), findsOneWidget);
      expect(find.text('动态'), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('成就'), findsOneWidget);
      // 数字与标签分开两个 Text：行程 0 段的 '0' 至少出现一次。
      expect(find.text('0'), findsWidgets);
      // 社交行已并进资料卡：关注/粉丝/获赞与用户名同页。
      expect(find.text('柴西'), findsOneWidget);
      expect(find.text('关注'), findsOneWidget);
      expect(find.text('粉丝'), findsOneWidget);
      expect(find.text('获赞'), findsOneWidget);
      expect(find.text('暂无'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点“动态”切换分区', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pump();
      await tester.tap(find.text('动态'));
      await tester.pump();
      expect(find.textContaining('暂无动态'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('个人页没有语言开关，行程区打开记录页并保留公开开关', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      var toggled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MyPage(
            username: '柴西',
            userId: 'DT-1234',
            bio: 'hello',
            stats: const [],
            following: 0,
            followers: 0,
            likes: 0,
            trips: [
              MyTripItem(
                id: 't1',
                title: '汽车 · 1.20 km',
                subtitle: '今天',
                onTogglePublic: () => toggled++,
              ),
            ],
            posts: const [],
            favorites: const [],
            achievements: const [],
            onOpenTripsTab: () => opened++,
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(LanguageSwitch), findsNothing);
      expect(find.text('语言'), findsNothing);
      expect(find.text('打开行程记录'), findsOneWidget);
      await tester.tap(find.text('打开行程记录'));
      expect(opened, 1);
      expect(find.text('仅自己'), findsOneWidget);
      await tester.tap(find.text('仅自己'));
      expect(toggled, 1);
      final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
      final pad = scroll.padding! as EdgeInsets;
      expect(pad.bottom, greaterThanOrEqualTo(kPillNavHeight + 12));
      expect(tester.takeException(), isNull);
    });

    testWidgets('v1.5.2 资料卡：分享改小图标钮放旁边，通栏分享按钮已删', (tester) async {
      await tester.pumpWidget(_page(onShareInvite: () {}));
      await tester.pump();
      // 分享是头行右侧的小图标钮，不再是通栏大按钮。
      expect(find.byIcon(Icons.share), findsOneWidget);
      expect(find.text('通过分享邀请'), findsNothing);
      expect(find.text('编辑'), findsOneWidget);
      // 头行：头像 + 名字/ID；简介移到头行下方通栏。
      expect(find.text('柴西'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
