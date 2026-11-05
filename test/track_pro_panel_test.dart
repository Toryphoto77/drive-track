/// 职业赛道面板单测：实时 Delta 口径、最优圈布局过滤、新显示字段。
///
/// 诚实口径的测试锚点：
/// - 实时 Delta 只在有真实扇区点时才出数，否则为 null（不拿
///   “当前圈已用 - 最佳圈总时长”冒充）。
/// - 最优圈按最佳圈的分段长度过滤后再拼合，退化半圈不与真实分段混算。

import 'package:drive_track/track_sector_data.dart';
import 'package:drive_track/track_session_display.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Lap _lap(int n, int duration, List<int> sectors, {bool dwell = false}) {
  return Lap(
    number: n,
    startMs: n * 100000,
    endMs: n * 100000 + duration,
    durationMs: duration,
    pausedMs: 0,
    dwellNotCounted: dwell,
    sectorsMs: sectors,
  );
}

void main() {
  group('liveDeltaMsFor（分段级实时 Delta）', () {
    test('无扇区点时为 null，不冒充', () {
      expect(
        liveDeltaMsFor(
          predictedLapMs: 90000,
          bestLapMs: 88000,
          hasSectorPoints: false,
        ),
        isNull,
      );
    });

    test('预测圈或最佳圈为空时为 null', () {
      expect(
        liveDeltaMsFor(
          predictedLapMs: null,
          bestLapMs: 88000,
          hasSectorPoints: true,
        ),
        isNull,
      );
      expect(
        liveDeltaMsFor(
          predictedLapMs: 90000,
          bestLapMs: null,
          hasSectorPoints: true,
        ),
        isNull,
      );
    });

    test('有扇区点时 = 预测圈 - 最佳圈（负为更快）', () {
      expect(
        liveDeltaMsFor(
          predictedLapMs: 86500,
          bestLapMs: 88000,
          hasSectorPoints: true,
        ),
        -1500,
      );
      expect(
        liveDeltaMsFor(
          predictedLapMs: 88000,
          bestLapMs: 88000,
          hasSectorPoints: true,
        ),
        0,
      );
    });
  });

  group('sessionOptimalLapMs（布局过滤后的最优圈）', () {
    test('各段最快相加，停留不计圈的圈不进统计', () {
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
        _lap(3, 80000, [10000, 10000, 10000], dwell: true),
      ];
      // 最佳圈是第 2 圈（88000，3 段）；最优 = 28000+30000+29000。
      expect(sessionOptimalLapMs(laps), 87000);
    });

    test('退化半圈不与真实 3 段混算：按最佳圈长度过滤', () {
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
        // 退化半圈：半段极快，但长度为 2，不应混进 3 段拼合。
        _lap(3, 87000, [10000, 77000]),
      ];
      // 最佳圈是第 3 圈（87000，2 段），故只按 2 段拼合：
      // 该组只有第 3 圈，最优 = 其自身 87000。
      expect(sessionOptimalLapMs(laps), 87000);
    });

    test('无计入圈时为 null', () {
      expect(sessionOptimalLapMs([]), isNull);
      expect(
        sessionOptimalLapMs([_lap(1, 80000, [10000, 10000], dwell: true)]),
        isNull,
      );
    });
  });

  group('职业面板新显示字段', () {
    testWidgets('实时 Delta 着色、分段用时、理论最优均渲染', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 3,
              currentLapMs: 61234,
              sectorDeltasMs: [-2000, 1500, null],
              sectorTimesMs: [28000, 41000],
              currentSectorIndex: 2,
              liveDeltaMs: -2500,
              bestLapMs: 88000,
              predictedLapMs: 89500,
              optimalLapMs: 87000,
            ),
          ),
        ),
      );
      expect(find.text('实时 Delta'), findsOneWidget);
      final deltaText =
          tester.widget<Text>(find.text('-0:02.500'));
      expect(deltaText.style?.color, const Color(0xFF22C55E));
      expect(find.text('0:28.000'), findsOneWidget);
      expect(find.text('0:41.000'), findsOneWidget);
      expect(find.text('理论最优'), findsOneWidget);
      expect(find.text('1:27.000'), findsOneWidget);
      // 第三段未完成：用时与 delta 均为 '--'。
      expect(find.text('--'), findsNWidgets(2));
    });

    testWidgets('无 Delta 与理论最优时显示占位，不编数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 1,
              currentLapMs: 30000,
              sectorDeltasMs: const [],
              bestLapMs: null,
              predictedLapMs: null,
            ),
          ),
        ),
      );
      expect(find.text('实时 Delta'), findsOneWidget);
      expect(find.text('理论最优'), findsOneWidget);
      expect(find.text('--:--.---'), findsWidgets);
    });
  });
}
