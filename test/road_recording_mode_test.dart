import 'package:drive_track/mode_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只有赛道档启用圈速计时，自定义道路记录不生成单圈', () {
    expect(surfaceUsesLapTiming(DriveSurface.track), isTrue);
    expect(surfaceUsesLapTiming(DriveSurface.street), isFalse);
    expect(surfaceUsesLapTiming(DriveSurface.custom), isFalse);
  });

  testWidgets('v1.8.3 首页不再提供自定义档，只剩街道/赛道且赛道档显示选择器', (tester) async {
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

    // 首页第二个「自定义」入口已下线。
    expect(find.text('自定义'), findsNothing);
    expect(find.text('测试赛道选择器'), findsNothing);

    await tester.tap(find.text('赛道'));
    await tester.pumpAndSettle();

    expect(surface, DriveSurface.track);
    expect(find.text('测试赛道选择器'), findsOneWidget);
  });
}
