import 'package:drive_track/mode_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只有赛道档启用圈速计时，自定义道路记录不生成单圈', () {
    expect(surfaceUsesLapTiming(DriveSurface.track), isTrue);
    expect(surfaceUsesLapTiming(DriveSurface.street), isFalse);
    expect(surfaceUsesLapTiming(DriveSurface.custom), isFalse);
  });

  testWidgets('自定义档显示跑山连续记录说明且不显示赛道选择器', (tester) async {
    var surface = DriveSurface.street;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ModeSwitchSection(
            surface: surface,
            trackSelector: const Text('测试赛道选择器'),
            onSurfaceChanged: (value) => setState(() => surface = value),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(surface, DriveSurface.custom);
    expect(find.text('跑山 / 道路连续记录 · 不生成单圈'), findsOneWidget);
    expect(find.text('测试赛道选择器'), findsNothing);
  });
}
