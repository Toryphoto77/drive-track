// 赛道大计时独立 ticker 测试：显示刷新与权威计时严格分工。
// - 纯函数：暂停冻结、插值、空锚点、下限钳制；
// - widget：ticker 在无父重建时推进显示、暂停停走、恢复续走
//   （暂停时长不计入）、完成一圈归零、新锚点以权威值校正、
//   非直播不插值。数值仍瞬间切换，不加回滑动动画。
import 'package:drive_track/live_lap_timer_text.dart';
import 'package:drive_track/rolling_digit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 48, fontWeight: FontWeight.bold);

  group('interpolatedLapMs', () {
    test('null anchor stays placeholder', () {
      expect(
          interpolatedLapMs(
              anchorMs: null,
              elapsedMs: 1000,
              anchorElapsedMs: 0,
              paused: false),
          isNull);
    });

    test('paused freezes at anchor', () {
      expect(
          interpolatedLapMs(
              anchorMs: 60000,
              elapsedMs: 5000,
              anchorElapsedMs: 0,
              paused: true),
          60000);
    });

    test('running advances by ticker elapsed delta', () {
      expect(
          interpolatedLapMs(
              anchorMs: 60000,
              elapsedMs: 1500,
              anchorElapsedMs: 1000,
              paused: false),
          60500);
    });

    test('negative result clamps to zero', () {
      expect(
          interpolatedLapMs(
              anchorMs: 100,
              elapsedMs: 0,
              anchorElapsedMs: 500,
              paused: false),
          0);
    });
  });

  group('LiveLapTimeText widget', () {
    Widget wrap({
      int? anchorMs,
      int lapNumber = 1,
      bool paused = false,
      bool live = true,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LiveLapTimeText(
                anchorMs: anchorMs,
                lapNumber: lapNumber,
                paused: paused,
                live: live,
                style: style,
              ),
            ),
          ),
        );

    String shownValue(WidgetTester tester) => tester
        .widget<RollingNumberText>(find.byType(RollingNumberText))
        .value;

    testWidgets('ticker advances display without parent rebuild',
        (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: 60000, lapNumber: 1, paused: false));
      await tester.pump();
      expect(shownValue(tester), '1:00.000');
      // 父级不重建：只推进 fake 时间，ticker 即应推进显示。
      await tester.pump(const Duration(milliseconds: 500));
      expect(shownValue(tester), '1:00.500');
    });

    testWidgets('paused display stays frozen', (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: 60000, lapNumber: 1, paused: true));
      await tester.pump();
      expect(shownValue(tester), '1:00.000');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(shownValue(tester), '1:00.000');
    });

    testWidgets('resume continues from frozen value, pause excluded',
        (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: 60000, lapNumber: 1, paused: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(shownValue(tester), '1:00.000');
      // 恢复：同一锚点、暂停翻转，插值从恢复时刻起算，
      // 暂停的 1000ms 不得算进去。
      await tester.pumpWidget(
          wrap(anchorMs: 60000, lapNumber: 1, paused: false));
      await tester.pump();
      expect(shownValue(tester), '1:00.000');
      await tester.pump(const Duration(milliseconds: 300));
      expect(shownValue(tester), '1:00.300');
    });

    testWidgets('lap number change resets display to new lap',
        (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: 90000, lapNumber: 1, paused: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(shownValue(tester), '1:30.500');
      // 完成一圈：圈号变化 + 新锚点，显示从新圈起点开始，
      // 不是旧值 + 流逝。
      await tester.pumpWidget(
          wrap(anchorMs: 0, lapNumber: 2, paused: false));
      await tester.pump();
      expect(shownValue(tester), '0:00.000');
      await tester.pump(const Duration(milliseconds: 200));
      expect(shownValue(tester), '0:00.200');
    });

    testWidgets('new anchor corrects display to authoritative value',
        (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: 60000, lapNumber: 1, paused: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(shownValue(tester), '1:00.500');
      // 新 GPS 点到达：锚点更新为权威值，显示立即校正。
      await tester.pumpWidget(
          wrap(anchorMs: 61000, lapNumber: 1, paused: false));
      await tester.pump();
      expect(shownValue(tester), '1:01.000');
    });

    testWidgets('non-live display never interpolates', (tester) async {
      await tester.pumpWidget(wrap(
          anchorMs: 60000, lapNumber: 1, paused: false, live: false));
      await tester.pump();
      expect(shownValue(tester), '1:00.000');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(shownValue(tester), '1:00.000');
    });

    testWidgets('null anchor shows placeholder and does not tick',
        (tester) async {
      await tester.pumpWidget(
          wrap(anchorMs: null, lapNumber: 0, paused: false));
      await tester.pump();
      expect(shownValue(tester), '--:--.---');
      await tester.pump(const Duration(milliseconds: 1000));
      expect(shownValue(tester), '--:--.---');
    });
  });
}
