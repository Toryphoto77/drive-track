import 'package:drive_track/card_style.dart';
import 'package:drive_track/trip_analytics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('analytics page uses cards, bilingual title, and no raw gap copy', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: TripAnalyticsPage(metas: const [], loadTrip: (_) async => null),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('行程分析'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.byType(DriveTrackCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
