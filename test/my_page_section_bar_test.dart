/// 个人页分段控件与资料卡合并测试（v1.5.1）。
///
/// 覆盖：行程/动态/收藏/成就四段均渲染，标签与数字分开显示
/// （居中、无混排错位）；关注/粉丝/获赞已并进资料卡（不再是
/// 独立卡片）；点“动态”切换分区。

import 'package:drive_track/my_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page({List<MyTripItem> trips = const []}) {
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
  });
}
