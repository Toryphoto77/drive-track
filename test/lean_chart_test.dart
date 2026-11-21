/// 压弯图表：门控与每弯最大倾角榜排序回归。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/lean_chart.dart';
import 'package:drive_track/models.dart';

TrackPoint _p({required int i, required double roll, double latG = 0}) {
  return TrackPoint(
    timeMs: i * 1000,
    lat: 31.0 + i * 0.0001,
    lon: 121.0,
    alt: 10,
    speed: 20,
    bearing: 0,
    hAcc: 5,
    vAcc: 5,
    speedAcc: 1,
    provider: 'test',
    longG: 0,
    latG: latG,
    vertG: 0,
    pitch: 0,
    roll: roll,
    heading: 0,
    pressureHpa: 1013,
    calibrated: true,
  );
}

TripEvent _corner({required int index, required double left, required double right}) {
  return TripEvent(
    kind: 'corner',
    startMs: index * 1000,
    endMs: index * 1000 + 2000,
    startIndex: index,
    endIndex: index + 2,
    peakLongG: 0,
    peakLatG: 0.6,
    entrySpeed: 20,
    minSpeed: 15,
    exitSpeed: 18,
    maxLeanLeft: left,
    maxLeanRight: right,
  );
}

Trip _trip({required List<TrackPoint> points, required List<TripEvent> events}) {
  return Trip(
    id: 't1',
    mode: TripMode.moto,
    startMs: 0,
    endMs: 10000,
    points: points,
    events: events,
    score: 0,
    subScores: const {},
    scoreReasons: const [],
  );
}

void main() {
  testWidgets('未固定或未标定时只显示门控提示，不画曲线和数字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeanChartSection(
            trip: _trip(
              points: [_p(i: 0, roll: -20), _p(i: 1, roll: 20)],
              events: [_corner(index: 0, left: 40, right: 10)],
            ),
            isCalibratedAndMounted: false,
          ),
        ),
      ),
    );
    expect(find.text(leanNotTrustedLabel), findsOneWidget);
    expect(find.text('压弯'), findsNothing);
    expect(find.text('倾角 - 速度'), findsNothing);
    expect(find.text('每弯最大倾角榜'), findsNothing);
  });

  testWidgets('每弯最大倾角榜按较大一侧倾角降序', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CornerLeanRanking(
            events: [
              _corner(index: 0, left: 20, right: 25),
              _corner(index: 1, left: 50, right: 5),
              _corner(index: 2, left: 5, right: 35),
            ],
          ),
        ),
      ),
    );
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    final first50 = texts.indexWhere((t) => t.contains('50°'));
    final first35 = texts.indexWhere((t) => t.contains('35°'));
    final first25 = texts.indexWhere((t) => t.contains('25°'));
    expect(first50, isNonNegative);
    expect(first50, lessThan(first35));
    expect(first35, lessThan(first25));
  });

  testWidgets('已固定且标定时渲染压弯曲线与倾角速度图', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LeanChartSection(
              trip: _trip(
                points: [
                  _p(i: 0, roll: 0, latG: 0.1),
                  _p(i: 1, roll: 15, latG: 0.4),
                  _p(i: 2, roll: 30, latG: 0.6),
                ],
                events: [_corner(index: 0, left: 10, right: 30)],
              ),
              isCalibratedAndMounted: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('压弯'), findsOneWidget);
    expect(find.text('倾角 - 速度'), findsOneWidget);
    expect(find.text('每弯最大倾角榜'), findsOneWidget);
  });
}
