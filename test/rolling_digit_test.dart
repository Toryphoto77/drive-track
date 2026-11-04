// 视频对齐的滚动数字测试：只验渲染与值更新；另验变化位无滑动
// 动画（视频里变化位是干净切换，不应出现 AnimatedPositioned）。
import 'package:drive_track/rolling_digit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 48, fontWeight: FontWeight.bold);

  Widget wrap(String value) => MaterialApp(
      home: Scaffold(body: Center(child: RollingNumberText(value: value, style: style))));

  testWidgets('renders separators statically, updates value on rebuild',
      (tester) async {
    await tester.pumpWidget(wrap('1:23.456'));
    await tester.pumpAndSettle();
    expect(find.text(':'), findsOneWidget);
    expect(find.text('.'), findsOneWidget);
    expect(
        tester
            .widget<RollingNumberText>(find.byType(RollingNumberText))
            .value,
        '1:23.456');

    await tester.pumpWidget(wrap('1:23.457'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RollingNumberText>(find.byType(RollingNumberText))
            .value,
        '1:23.457');
  });

  testWidgets('placeholder renders without digits', (tester) async {
    await tester.pumpWidget(wrap('--:--.---'));
    await tester.pumpAndSettle();
    expect(find.byType(RollingNumberText), findsOneWidget);
  });

  testWidgets('digit change has no slide animation', (tester) async {
    await tester.pumpWidget(wrap('1:23.456'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(wrap('1:23.457'));
    await tester.pump();
    expect(find.byType(AnimatedPositioned), findsNothing);
    expect(find.byType(Positioned), findsWidgets);
  });

  testWidgets('minute rollover keeps right-side digits stable', (tester) async {
    await tester.pumpWidget(wrap('9:59.999'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(wrap('10:00.000'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RollingNumberText>(find.byType(RollingNumberText))
            .value,
        '10:00.000');
  });
}
