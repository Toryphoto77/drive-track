/// 赛道知识库测试（v1.5.2）：内容结构 + 列表页/目录抽屉交互。
/// 内容是静态数据，结构错了（空标题、空要点）页面就会缺一块，
/// 所以结构用例逐项断言；页面用例泵 TrackKnowledgePage（纯静态页，
/// 无 IO、无全局状态，可直接泵）。

import 'package:drive_track/track_knowledge.dart';
import 'package:drive_track/track_knowledge_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('赛道知识库内容结构', () {
    test('9 个分类、34 篇文章', () {
      expect(trackKnowledge.length, 9);
      final total =
          trackKnowledge.fold<int>(0, (n, c) => n + c.articles.length);
      expect(total, 34);
    });

    test('赛事架构 11 篇、规则 4 篇', () {
      final byTitle = {
        for (final c in trackKnowledge) c.title: c.articles.length
      };
      expect(byTitle['赛事架构'], 11);
      expect(byTitle['规则'], 4);
    });

    test('每分类至少 2 篇，每篇有标题、导读与至少 2 条要点', () {
      for (final c in trackKnowledge) {
        expect(c.title.isNotEmpty, true, reason: '分类标题为空');
        expect(c.subtitle.isNotEmpty, true, reason: '${c.title} 副标题为空');
        expect(c.articles.length, greaterThanOrEqualTo(2),
            reason: '${c.title} 文章少于 2 篇');
        for (final a in c.articles) {
          expect(a.title.isNotEmpty, true,
              reason: '${c.title} 有文章标题为空');
          expect(a.intro.isNotEmpty, true, reason: '${a.title} 导读为空');
          expect(a.bullets.length, greaterThanOrEqualTo(2),
              reason: '${a.title} 要点少于 2 条');
          for (final b in a.bullets) {
            expect(b.trim().isNotEmpty, true, reason: '${a.title} 有空要点');
          }
        }
      }
    });

    test('参考来源非空', () {
      expect(trackKnowledgeSources.length, greaterThanOrEqualTo(5));
      for (final s in trackKnowledgeSources) {
        expect(s.trim().isNotEmpty, true);
      }
    });
  });

  group('赛道知识库列表页', () {
    testWidgets('目录形式：分类与文章直接列出，点文章进详情页',
        (tester) async {
      // 列表共 9 张分类卡 + 来源卡，用高视口一次全显，免滚动
      // （ListView 懒加载，默认 600 高视口下底部卡不在树里）。
      tester.view.physicalSize = const Size(800, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: TrackKnowledgePage()),
      );
      await tester.pumpAndSettle();

      expect(find.text('赛道知识库'), findsOneWidget);
      expect(find.text('赛道旗语'), findsOneWidget);
      expect(find.text('参考来源'), findsOneWidget);
      // 目录形式：文章直接列出，不用先展开分类。
      expect(find.text('旗语怎么看'), findsOneWidget);
      // 扩充的新文章也在目录里。
      expect(find.text('勒芒 24 小时：为什么特殊'), findsOneWidget);
      expect(find.text('一套规则，多项赛事：通用与特有'), findsOneWidget);

      await tester.tap(find.text('旗语怎么看'));
      await tester.pumpAndSettle();
      expect(find.text('旗语是赛道上的语言，看不懂旗就等于闭着眼睛开车。'),
          findsOneWidget);
      // 要点是 RichText（要点名加粗 + 正文），用包含匹配并搜 RichText。
      expect(find.textContaining('谁挥旗', findRichText: true),
          findsOneWidget);
    });

    testWidgets('左侧目录抽屉：点文章直接跳转', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: TrackKnowledgePage()),
      );
      await tester.pumpAndSettle();

      // 左上角目录钮打开抽屉。
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('目录 · 9 个分类 · 34 篇文章'), findsOneWidget);
      // 抽屉是可滚动目录，赛事架构在第 7 个分类，需往下滚才可见
      // （ListView 懒加载，未滚到时不在树里）。
      final drawerList = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(ListView),
      );
      for (var i = 0;
          i < 5 && find.text('赛事架构').evaluate().isEmpty;
          i++) {
        await tester.drag(drawerList, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text('赛事架构'), findsOneWidget);
      // 勒芒是赛事架构里的第 7 篇，继续滚到它出现再点。
      final leMans = find.text('勒芒 24 小时：为什么特殊');
      for (var i = 0; i < 5 && leMans.evaluate().isEmpty; i++) {
        await tester.drag(drawerList, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(leMans, findsWidgets);

      // 抽屉里点一篇赛事架构的新文章，直接进详情页。
      await tester.tap(leMans.last);
      await tester.pumpAndSettle();
      expect(find.text('耐力赛的皇冠，一天一夜比谁跑得最远，规则处处与普通分站不同。'),
          findsOneWidget);
    });
  });
}
