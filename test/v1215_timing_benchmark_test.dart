/// v1.2.15 计时对标补齐测试：预测圈无分段点门控、Delta 指示条对数
/// 缩放、理论最优圈标注与无分段占位。
///
/// 覆盖（均为 v1.2.15 新增/改动行为）：
/// - predictedLapMsVsBest：无真实分段点时恒为 null，不再复读最佳圈；
/// - deltaBarFraction：对数缩放（τ = 500ms、满格 10s），小 Delta
///   可见但始终只占条的一小截，单调递增、超满格钳制；
/// - analysisTheoreticalBestLapMs：与直播页同口径过滤 + 真实分段
///   门控（最佳圈须 ≥ 3 段），半圈拼合一律不显示；
/// - TrackSessionDisplay：目标行标签为“理论最优”，Delta 条按
///   对数比例填充（快为绿在右、慢为红在左），无数据时无填充；
/// - TrackAnalysisPage：2 段半圈行程不显示假理论圈，3 段真实
///   分段行程正常显示理论最佳圈。

import 'dart:math' as math;

import 'package:drive_track/models.dart';
import 'package:drive_track/track_analysis_page.dart';
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

TimedPoint _tpt(int t, double lon) =>
    TimedPoint(timeMs: t, lat: 0, lon: lon, speed: 10);

TrackPoint _pt(int t, double lat, double lon, double speed) {
  return TrackPoint(
    timeMs: t,
    lat: lat,
    lon: lon,
    alt: 0,
    speed: speed,
    bearing: 0,
    hAcc: 0,
    vAcc: 0,
    speedAcc: 0,
    provider: 'gps',
    longG: 0.1,
    latG: 0,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: 0,
    pressureHpa: 0,
    calibrated: false,
    sensorStatus: 'ok',
    altValid: false,
    locSource: '',
  );
}

Trip _trip() => Trip(
      id: 't1',
      mode: TripMode.car,
      startMs: 100000,
      endMs: 300000,
      points: [
        _pt(100000, 31.0, 121.0, 20),
        _pt(150000, 31.01, 121.01, 30),
        _pt(200000, 31.02, 121.02, 25),
        _pt(250000, 31.03, 121.03, 28),
      ],
      events: const [],
      score: 0,
      subScores: const {},
      scoreReasons: const [],
      trackId: 'shanghai',
      trackName: '上海国际赛车场',
      isTrackMode: true,
    );

/// 指示条填充容器：按精确颜色找（分段格用的是带透明度的同色，
/// 不会误命中；Delta 数字是 Text 不是 Container）。
Finder _fillFinder(Color color) => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == color,
    );

void main() {
  group('预测圈无分段点门控（v1.2.15）', () {
    test('无分段点：已有最佳圈时预测圈仍为 null，不复读最佳圈', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_tpt(0, -0.001));
      timer.addPoint(_tpt(1000, 0)); // 第 1 圈开始
      // 中间点距起终点 55m（< 60m），不恢复穿越资格，避免起终点
      // 线上的出发段被误判为再次穿越（见 v120 测试同款时序）。
      timer.addPoint(_tpt(11000, 0.0005));
      timer.addPoint(_tpt(31000, 0.001));
      timer.addPoint(_tpt(61000, 0)); // 完圈，圈速 60000
      expect(timer.bestLap!.durationMs, 60000);
      timer.addPoint(_tpt(71000, 0.0005)); // 第 2 圈进行中
      expect(timer.predictedLapMsVsBest, isNull);
    });

    test('有分段点：已有最佳圈时预测圈正常出数', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        sectorPoints: const [GeoPoint(0, 0.001), GeoPoint(0, 0.002)],
      );
      timer.addPoint(_tpt(0, -0.001));
      timer.addPoint(_tpt(1000, 0));
      timer.addPoint(_tpt(21000, 0.001));
      timer.addPoint(_tpt(41000, 0.002));
      timer.addPoint(TimedPoint(timeMs: 46000, lat: 0.002, lon: 0.002, speed: 10));
      timer.addPoint(TimedPoint(timeMs: 51000, lat: 0.002, lon: 0, speed: 10));
      timer.addPoint(_tpt(61000, 0)); // 完圈，第 2 圈开始
      expect(timer.bestLap!.durationMs, 60000);
      // 刚开第 2 圈：无已完成分段，预测圈即参照圈圈速。
      expect(timer.predictedLapMsVsBest, 60000);
    });
  });

  group('Delta 指示条对数缩放 deltaBarFraction', () {
    test('null / 0 时为 0，只画底条', () {
      expect(deltaBarFraction(null), 0);
      expect(deltaBarFraction(0), 0);
    });

    test('对数刻度：τ = 500ms、满格 10s', () {
      // ln(1 + |d| / 500) / ln(1 + 10000 / 500)
      double expected(int d) =>
          math.log(1 + d / 500) / math.log(1 + 10000 / 500);
      expect(deltaBarFraction(100), closeTo(expected(100), 0.001));
      expect(deltaBarFraction(500), closeTo(expected(500), 0.001));
      expect(deltaBarFraction(1000), closeTo(expected(1000), 0.001));
      expect(deltaBarFraction(5000), closeTo(expected(5000), 0.001));
      expect(deltaBarFraction(10000), closeTo(1.0, 0.001));
    });

    test('小 Delta 始终只占一小截，不夸大', () {
      expect(deltaBarFraction(100), lessThan(0.1)); // 100ms 仅约 6%
      expect(deltaBarFraction(500), lessThan(0.3));
      expect(deltaBarFraction(1000), lessThan(0.5)); // 1s 不到半条
    });

    test('单调递增、正负对称、超满格钳制', () {
      expect(deltaBarFraction(100), lessThan(deltaBarFraction(500)));
      expect(deltaBarFraction(500), lessThan(deltaBarFraction(1000)));
      expect(deltaBarFraction(1000), lessThan(deltaBarFraction(5000)));
      expect(deltaBarFraction(5000), lessThan(deltaBarFraction(10000)));
      expect(deltaBarFraction(-2500), deltaBarFraction(2500));
      expect(deltaBarFraction(60000), 1.0);
      expect(deltaBarFraction(-60000), 1.0);
    });
  });

  group('分析页理论最优圈 analysisTheoreticalBestLapMs', () {
    test('3 段真实分段：各段最快相加，与直播页口径一致', () {
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
        _lap(3, 80000, [10000, 10000, 10000], dwell: true),
      ];
      expect(analysisTheoreticalBestLapMs(laps), 87000);
      expect(analysisTheoreticalBestLapMs(laps),
          sessionOptimalLapMs(laps));
    });

    test('2 段半圈行程：一律为 null，不拼假理论圈', () {
      final laps = [
        _lap(1, 60000, [30000, 30000]),
        _lap(2, 60000, [28000, 32000]),
      ];
      expect(analysisTheoreticalBestLapMs(laps), isNull);
    });

    test('混合口径：2 段圈不混进 3 段拼合', () {
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
        // 2 段圈：总时长更慢（不是最佳圈），但首段极快；
        // 若混进拼合，S1 最佳会被拉到 10000，理论圈成 69000。
        _lap(3, 95000, [10000, 85000]),
      ];
      expect(analysisTheoreticalBestLapMs(laps), 87000);
    });

    test('最佳圈本身只有 2 段时为 null（无法确认真实分段）', () {
      // 2 段圈跑得最快成为最佳圈：无法区分“1 个真实分段点”
      // 与“无分段点半圈切分”，保守返回 null；直播页同场景下
      // sessionOptimalLapMs 仍按 2 段拼合（口径不同，见
      // track_pro_panel_test），分析页不跟。
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
        _lap(3, 87000, [10000, 77000]),
      ];
      expect(analysisTheoreticalBestLapMs(laps), isNull);
    });

    test('无计入圈 / 只有无效圈时为 null', () {
      expect(analysisTheoreticalBestLapMs([]), isNull);
      expect(
        analysisTheoreticalBestLapMs(
            [_lap(1, 80000, [10000, 10000, 10000], dwell: true)]),
        isNull,
      );
    });
  });

  group('直播面板：理论最优标签与 Delta 条', () {
    testWidgets('目标行标签为“理论最优”，无数据时显示占位', (tester) async {
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
      expect(find.text('理论最优'), findsOneWidget);
      expect(find.text('最优圈'), findsNothing);
      expect(find.text('--:--.---'), findsWidgets);
      // 无 Delta 时指示条无填充。
      expect(_fillFinder(const Color(0xFF22C55E)), findsNothing);
      expect(_fillFinder(const Color(0xFFE10600)), findsNothing);
    });

    testWidgets('Delta 为负：绿条在右，宽度按对数比例', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 2,
              currentLapMs: 61234,
              sectorDeltasMs: const [],
              liveDeltaMs: -2500,
              bestLapMs: 88000,
              predictedLapMs: 85500,
              optimalLapMs: 87000,
            ),
          ),
        ),
      );
      expect(find.text('-0:02.500'), findsOneWidget);
      expect(find.text('理论最优'), findsOneWidget);
      expect(find.text('1:27.000'), findsOneWidget);
      // 测试视口宽 800，面板内边距 14 → 条宽 772，半条 386；
      // -2500ms 对数比例 ln(6)/ln(21) ≈ 0.589，填充约 227。
      final green = _fillFinder(const Color(0xFF22C55E));
      expect(green, findsOneWidget);
      expect(tester.getSize(green).width, closeTo(227.2, 3.0));
      expect(_fillFinder(const Color(0xFFE10600)), findsNothing);
    });

    testWidgets('Delta 为正：红条在左，宽度按对数比例', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 2,
              currentLapMs: 61234,
              sectorDeltasMs: const [],
              liveDeltaMs: 5000,
              bestLapMs: 88000,
              predictedLapMs: 93000,
              optimalLapMs: 87000,
            ),
          ),
        ),
      );
      expect(find.text('+0:05.000'), findsOneWidget);
      // +5000ms 对数比例 ln(11)/ln(21) ≈ 0.788，填充约 304。
      final red = _fillFinder(const Color(0xFFE10600));
      expect(red, findsOneWidget);
      expect(tester.getSize(red).width, closeTo(304.0, 3.0));
      expect(_fillFinder(const Color(0xFF22C55E)), findsNothing);
    });
  });

  group('分析页：理论最佳圈按真实分段门控显示', () {
    testWidgets('2 段半圈行程：不出现假理论圈数值', (tester) async {
      final laps = [
        _lap(1, 60000, [30000, 30000]),
        _lap(2, 60000, [28000, 32000]),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: TrackAnalysisPage(trip: _trip(), laps: laps),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('理论最佳圈'), findsOneWidget);
      // 旧口径会拼出 28000 + 30000 = 58000，新口径须为占位。
      expect(find.text('0:58.000'), findsNothing);
    });

    testWidgets('3 段真实分段行程：理论最佳圈正常显示', (tester) async {
      final laps = [
        _lap(1, 90000, [30000, 30000, 30000]),
        _lap(2, 88000, [28000, 31000, 29000]),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: TrackAnalysisPage(trip: _trip(), laps: laps),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('理论最佳圈'), findsOneWidget);
      expect(find.text('1:27.000'), findsOneWidget);
    });
  });
}
