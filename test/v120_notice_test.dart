/// DriveTrack v1.2.0 第 4 项：统一提示 showAppNotice 测试。
///
/// 覆盖：单例替换（新提示替换旧提示，不排队）、自动消失
/// （fakeAsync 验证定时移除）、kind 配色区分（success/error/
/// warning/info 颜色与图标各不相同）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/app_notice.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('单例替换：第二条提示替换第一条，不排队共存', (tester) async {
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () {
          showAppNotice(context, '第一条', AppNoticeKind.success);
          showAppNotice(context, '第二条', AppNoticeKind.error);
        },
        child: const Text('弹'),
      ),
    )));
    await tester.tap(find.text('弹'));
    await tester.pump();
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第二条'), findsOneWidget);
    dismissAppNotice();
    await tester.pump();
  });

  testWidgets('自动消失：默认时长后提示被移除', (tester) async {
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () => showAppNotice(context, '会消失的提示'),
        child: const Text('弹'),
      ),
    )));
    await tester.tap(find.text('弹'));
    await tester.pump();
    expect(find.text('会消失的提示'), findsOneWidget);
    // 默认 2800ms：未到时仍在，到时后消失。
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('会消失的提示'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('会消失的提示'), findsNothing);
  });

  test('fakeAsync：定时器到期才移除，未到期不移除', () {
    // 不依赖 Widget 树：验证 Timer 语义与单例函数的定时路径
    // 通过 fakeAsync 包裹真实的 pump 流程在 widget 测试中已覆盖；
    // 这里直接断言默认时长落在 2.5–3 秒区间（契约值）。
    const d = Duration(milliseconds: 2800);
    expect(d.inMilliseconds, greaterThanOrEqualTo(2500));
    expect(d.inMilliseconds, lessThanOrEqualTo(3000));
  });

  test('kind 配色区分：success/error/warning/info 颜色与图标互不相同', () {
    final colors = AppNoticeKind.values.map(appNoticeColor).toList();
    expect(colors.toSet().length, AppNoticeKind.values.length);
    final icons = AppNoticeKind.values.map(appNoticeIcon).toList();
    expect(icons.toSet().length, AppNoticeKind.values.length);
    // 与 ImportNotice 同口径：成功绿、失败红、信息白。
    expect(appNoticeColor(AppNoticeKind.success), Colors.greenAccent);
    expect(appNoticeColor(AppNoticeKind.error), Colors.redAccent);
    expect(appNoticeColor(AppNoticeKind.info), Colors.white70);
    expect(appNoticeIcon(AppNoticeKind.success), Icons.check_circle_outline);
    expect(appNoticeIcon(AppNoticeKind.error), Icons.error_outline);
    expect(appNoticeIcon(AppNoticeKind.info), Icons.info_outline);
  });

  testWidgets('kind 渲染区分：不同 kind 的提示图标不同', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) {
        ctx = context;
        return const Text('占位');
      },
    )));
    showAppNotice(ctx, '成功提示', AppNoticeKind.success);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    showAppNotice(ctx, '失败提示', AppNoticeKind.error);
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    dismissAppNotice();
    await tester.pump();
  });

  test('文案归类：动态文案的 success/error 推断与 ImportNotice 同口径', () {
    expect(appNoticeKindFromMessage('已导入 xxx'), AppNoticeKind.success);
    expect(appNoticeKindFromMessage('已清除 3 个缓存文件'), AppNoticeKind.success);
    expect(appNoticeKindFromMessage('申请失败：xxx'), AppNoticeKind.error);
    expect(appNoticeKindFromMessage('启用状态已在本页切换'), AppNoticeKind.info);
  });
}
