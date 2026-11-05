import 'package:drive_track/share_card_preview.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Trip _makeTrip({required bool track, required List<Lap> laps}) => Trip(
      id: 't1',
      mode: TripMode.car,
      startMs: 0,
      endMs: 60000,
      points: const [],
      events: const [],
      score: 0,
      subScores: const {},
      scoreReasons: const [],
      isTrackMode: track,
      lapsJson: laps.map((l) => l.toJson()).toList(),
    );

Lap _lap(int number, int durationMs, List<int> sectorsMs,
        {bool dwell = false}) =>
    Lap(
      number: number,
      startMs: 0,
      endMs: durationMs,
      durationMs: durationMs,
      pausedMs: 0,
      dwellNotCounted: dwell,
      sectorsMs: sectorsMs,
    );

Future<void> _pumpCard(WidgetTester tester, Trip trip,
    {ShareCardStyle style = ShareCardStyle.racing,
    bool? hasSectorPoints}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: ShareCardView(
            trip: trip, style: style, hasSectorPoints: hasSectorPoints)),
  ));
  await tester.pump();
}

void main() {
  group('v1.2.18 分享卡分段成绩行', () {
    testWidgets('有分段的最佳圈显示分段行，数字与 formatLapTime 一致',
        (tester) async {
      // 第一圈更慢（不是最佳圈），最佳圈是第二圈：验证取的是
      // sessionBestLap 而非第一圈。
      final trip = _makeTrip(track: true, laps: [
        _lap(1, 100000, [40000, 30000, 30000]),
        _lap(2, 95000, [32451, 28103, 35220]),
      ]);
      await _pumpCard(tester, trip);
      final expected = '最佳圈分段 '
          'S1 ${LapTimer.formatLapTime(32451)} · '
          'S2 ${LapTimer.formatLapTime(28103)} · '
          'S3 ${LapTimer.formatLapTime(35220)}';
      expect(find.text(expected), findsOneWidget);
      expect(find.text('最佳圈分段 S1 0:32.451 · S2 0:28.103 · S3 0:35.220'),
          findsOneWidget);
      // 现有行未被挤掉。
      expect(find.textContaining('里程'), findsOneWidget);
      expect(find.textContaining('时长'), findsOneWidget);
      expect(find.textContaining('最高'), findsOneWidget);
      expect(find.textContaining('最大 G'), findsOneWidget);
    });

    testWidgets('2 段只显示 S1/S2，不补 S3（告知有真实分段点）', (tester) async {
      final trip = _makeTrip(
          track: true, laps: [_lap(1, 65000, [30000, 35000])]);
      // 1 个真实分段点的赛道：调用方告知有分段点，2 段才显示。
      await _pumpCard(tester, trip, hasSectorPoints: true);
      expect(
          find.text('最佳圈分段 S1 ${LapTimer.formatLapTime(30000)} · '
              'S2 ${LapTimer.formatLapTime(35000)}'),
          findsOneWidget);
      expect(find.textContaining('S3'), findsNothing);
    });

    testWidgets('1 段只显示 S1（告知有真实分段点）', (tester) async {
      final trip = _makeTrip(
          track: true, laps: [_lap(1, 45000, [45000])]);
      await _pumpCard(tester, trip, hasSectorPoints: true);
      expect(
          find.text(
              '最佳圈分段 S1 ${LapTimer.formatLapTime(45000)}'),
          findsOneWidget);
      expect(find.textContaining('S2'), findsNothing);
    });

    testWidgets('hasSectorPoints=false 时不显示分段行', (tester) async {
      final trip = _makeTrip(track: true, laps: [
        _lap(1, 95000, [32451, 28103, 35220]),
      ]);
      await _pumpCard(tester, trip, hasSectorPoints: false);
      expect(find.textContaining('最佳圈分段'), findsNothing);
    });

    testWidgets('未告知时 2 段退化半圈不显示、3 段显示', (tester) async {
      // 2 段可能是无分段点的退化半圈：未告知时宁可不显示。
      final halfLap = _makeTrip(
          track: true, laps: [_lap(1, 100000, [50000, 50000])]);
      await _pumpCard(tester, halfLap);
      expect(find.textContaining('最佳圈分段'), findsNothing);
      // 3 段只能来自 2 个真实分段点：未告知也显示。
      final threeSeg = _makeTrip(track: true, laps: [
        _lap(1, 95000, [32451, 28103, 35220]),
      ]);
      await _pumpCard(tester, threeSeg);
      expect(find.textContaining('最佳圈分段'), findsOneWidget);
    });

    testWidgets('无分段点的赛道行程不显示该行', (tester) async {
      // sectorsMs 为空的圈按 lapInvalidReason 不计入，无最佳圈。
      final trip = _makeTrip(track: true, laps: [_lap(1, 60000, [])]);
      await _pumpCard(tester, trip);
      expect(find.textContaining('最佳圈分段'), findsNothing);
    });

    testWidgets('无完成圈的赛道行程不显示该行', (tester) async {
      final trip = _makeTrip(track: true, laps: []);
      await _pumpCard(tester, trip);
      expect(find.textContaining('最佳圈分段'), findsNothing);
    });

    testWidgets('街道行程不显示该行', (tester) async {
      final trip = _makeTrip(track: false, laps: [
        _lap(1, 95000, [32451, 28103, 35220]),
      ]);
      await _pumpCard(tester, trip);
      expect(find.textContaining('最佳圈分段'), findsNothing);
    });

    testWidgets('三种风格下均能渲染出/不出该行', (tester) async {
      final withSectors = _makeTrip(track: true, laps: [
        _lap(1, 95000, [32451, 28103, 35220]),
      ]);
      final withoutSectors = _makeTrip(
          track: true, laps: [_lap(1, 60000, [])]);
      for (final style in ShareCardStyle.values) {
        await _pumpCard(tester, withSectors, style: style);
        expect(find.textContaining('最佳圈分段'), findsOneWidget,
            reason: '有分段时 $style 应显示分段行');
        await _pumpCard(tester, withoutSectors, style: style);
        expect(find.textContaining('最佳圈分段'), findsNothing,
            reason: '无分段时 $style 不应显示分段行');
      }
    });
  });
}
