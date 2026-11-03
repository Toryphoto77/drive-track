import 'package:drive_track/satellite_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1.0.0 toggle pills share one width constant', () {
    // 两颗药丸（直连卫星 / 同步视频记录）都走 CompactTogglePill，
    // 宽度只由 kTogglePillWidth 一个常量决定，不再随文字长度伸缩。
    expect(kTogglePillWidth, 280.0);
  });

  testWidgets('v1.0.0 both pills render at the same fixed width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CompactTogglePill(
                icon: Icons.videocam,
                label: '同步视频记录',
                value: false,
                onChanged: (_) {},
              ),
              CompactSatellitePill(
                value: true,
                onChanged: (_) {},
                satelliteCount: 123,
              ),
            ],
          ),
        ),
      ),
    );
    // 最长一颗按“直连卫星 · 123 颗”实测需 255，280 留有余量，
    // 两颗渲染宽度都应等于常量，且互不截断（文字均能找到）。
    expect(find.text('同步视频记录'), findsOneWidget);
    expect(find.text('直连卫星 · 123 颗'), findsOneWidget);
    expect(tester.getSize(find.byType(CompactTogglePill).first).width, kTogglePillWidth);
    expect(tester.getSize(find.byType(CompactSatellitePill)).width, kTogglePillWidth);
  });
}
