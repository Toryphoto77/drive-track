/// v1.2.0 第 6 项测试：扇区数据合法性、理论最佳圈、无效圈标注、
/// 方案 A 赛中显示与赛道分析页冒烟。

import 'package:drive_track/models.dart';
import 'package:drive_track/rolling_digit.dart';
import 'package:drive_track/track_analysis_page.dart';
import 'package:drive_track/track_sector_data.dart';
import 'package:drive_track/track_session_display.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _kTrackIds = [
  'shanghai',
  'zhuhai',
  'ningbo',
  'zhejiang',
  'tianma',
  'ordos',
  'nordschleife',
  'spa',
  'silverstone',
  'monza',
  'suzuka',
  'laguna_seca',
  'cota',
  'fuji',
  'chengdu_tianfu',
  'goldenport',
  'guangdong_gic',
  'monaco',
  'le_mans',
  'sepang',
  'bathurst',
];

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
    latG: 0.2,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: 0,
    pressureHpa: 1013,
    calibrated: true,
  );
}

void main() {
  group('扇区数据合法性', () {
    test('覆盖图鉴 21 条，一条不多一条不少', () {
      expect(trackSectorData.keys.toSet(), _kTrackIds.toSet());
      expect(trackSectorData.length, 21);
    });

    test('全部条目合法：分界点单调、标注齐全、note 非空', () {
      for (final entry in trackSectorData.entries) {
        final d = entry.value;
        expect(d.trackId, entry.key);
        expect(d.isValid, isTrue, reason: d.trackId);
        expect(d.note, isNotEmpty, reason: d.trackId);
        if (d.source == TrackSectorSource.pending) {
          expect(d.boundaries, isEmpty, reason: d.trackId);
          expect(d.sectorLabels, isEmpty, reason: d.trackId);
        } else {
          expect(d.boundaries.length, 2, reason: d.trackId);
          expect(d.boundaries[0], greaterThan(0));
          expect(d.boundaries[0], lessThan(d.boundaries[1]));
          expect(d.boundaries[1], lessThan(1));
          expect(d.sectorLabels, ['S1', 'S2', 'S3']);
        }
      }
    });

    test('本轮无官方标注：目录分段点已声明为示意，不得冒充官方', () {
      expect(
        trackSectorData.values
            .where((d) => d.source == TrackSectorSource.official),
        isEmpty,
      );
      // 待核清单恰好为无轮廓依据的 5 条。
      final pending = trackSectorData.values
          .where((d) => d.source == TrackSectorSource.pending)
          .map((d) => d.trackId)
          .toSet();
      expect(pending, {
        'nordschleife',
        'chengdu_tianfu',
        'goldenport',
        'guangdong_gic',
        'le_mans',
      });
    });

    test('分界点换算值：目录示意点换算的 6 条分数与脚本输出一致', () {
      expect(trackSectorData['shanghai']!.boundaries, [0.512, 0.836]);
      expect(trackSectorData['spa']!.boundaries, [0.453, 0.776]);
      expect(trackSectorData['monza']!.boundaries, [0.507, 0.697]);
      expect(trackSectorData['suzuka']!.boundaries, [0.318, 0.623]);
      expect(trackSectorData['cota']!.boundaries, [0.444, 0.849]);
    });

    test('sectorIndexForFraction 按分界点分段，待核返回 -1', () {
      final sh = trackSectorData['shanghai']!;
      expect(sectorIndexForFraction(sh, 0.1), 0);
      expect(sectorIndexForFraction(sh, 0.6), 1);
      expect(sectorIndexForFraction(sh, 0.9), 2);
      expect(
          sectorIndexForFraction(trackSectorData['le_mans']!, 0.5), -1);
      expect(sectorFractionRange(trackSectorData['le_mans']!, 0), isNull);
      expect(sectorFractionRange(sh, 1), isNotNull);
    });
  });

  group('理论最佳圈与无效圈标注', () {
    test('理论最佳圈 = 各分段最佳相加，无效圈不进统计', () {
      final laps = [
        _lap(1, 100000, [30000, 40000, 30000]),
        _lap(2, 101000, [28000, 42000, 31000]),
        // 停留不计圈：即使分段极快也不进统计。
        _lap(3, 30000, [10000, 10000, 10000], dwell: true),
      ];
      expect(bestSectorMs(laps), [28000, 40000, 30000]);
      expect(theoreticalBestLapMs(laps), 98000);
      expect(sessionBestLap(laps)!.number, 1);
    });

    test('任一段无数据时理论最佳圈为 null，不拼假圈', () {
      final laps = [_lap(1, 60000, [])];
      expect(theoreticalBestLapMs(laps), isNull);
      expect(bestSectorMs(laps), isEmpty);
      expect(sessionBestLap(laps), isNull);
    });

    test('无效圈标注逻辑', () {
      expect(lapInvalidReason(_lap(1, 100000, [30000, 40000, 30000])),
          isNull);
      expect(lapInvalidReason(_lap(2, 30000, [10000, 10000, 10000],
          dwell: true)), contains('无效圈'));
      expect(lapInvalidReason(_lap(3, 60000, [])), contains('分段缺失'));
    });
  });

  group('方案 A 赛中显示', () {
    testWidgets('大数字计时 + 带正负号 delta，不写快/慢中文', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 2,
              currentLapMs: 61234,
              sectorDeltasMs: [-1234, null, 2500],
              sectorTimesMs: [30000],
              liveDeltaMs: -500,
              bestLapMs: 88000,
              predictedLapMs: 89500,
              optimalLapMs: 87000,
              sectorSourceNote: '估算分段',
            ),
          ),
        ),
      );
      // 大数字计时现为里程表式滚动组件，不再是单支 Text。
      expect(
          tester
              .widget<RollingNumberText>(find.byType(RollingNumberText))
              .value,
          '1:01.234');
      expect(find.text('-0:01.234'), findsOneWidget);
      expect(find.text('+0:02.500'), findsOneWidget);
      expect(find.text('--'), findsNWidgets(3)); // 未完成分段的用时与 delta
      expect(find.text('实时 Delta'), findsOneWidget);
      expect(find.text('-0:00.500'), findsOneWidget);
      expect(find.text('0:30.000'), findsOneWidget); // 已完成分段的绝对用时
      expect(find.text('最优圈'), findsOneWidget);
      expect(find.text('1:27.000'), findsOneWidget);
      expect(find.text('参照圈：本节最佳圈'), findsOneWidget);
      expect(find.text('估算分段'), findsOneWidget);
      expect(find.textContaining('快'), findsNothing);
      expect(find.textContaining('慢'), findsNothing);
    });
  });

  group('赛道分析页冒烟', () {
    testWidgets('总览 + OBD 未连接提示 + 无效圈标注 + 不评分', (tester) async {
      final laps = [
        _lap(1, 100000, [30000, 40000, 30000]),
        _lap(2, 101000, [28000, 42000, 31000]),
        _lap(3, 30000, [10000, 10000, 10000], dwell: true),
      ];
      // 轨迹点落在第 1 圈时间区间内（100000~200000）。
      final trip = Trip(
        id: 't1',
        mode: TripMode.car,
        startMs: 100000,
        endMs: 200000,
        points: [
          _pt(100000, 31.0, 121.0, 20),
          _pt(150000, 31.01, 121.01, 30),
          _pt(200000, 31.02, 121.02, 25),
        ],
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
        trackId: 'shanghai',
        trackName: '上海国际赛车场',
        isTrackMode: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrackAnalysisPage(trip: trip, laps: laps),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('赛道模式不评分'), findsOneWidget);
      // v1.2.1：OBD 占位行改版——通道列明油门/刹车/转速三项，
      // 未连接时以“未连接 OBD，暂无此通道”统一占位（旧文案只提
      // 油门/刹车，未覆盖转速）。
      expect(find.text('未连接 OBD，暂无此通道'), findsOneWidget);
      expect(find.text('理论最佳圈'), findsOneWidget);
      expect(find.textContaining('无效圈'), findsWidgets);
      // 第一版不做视频联动：页内仅有声明脚注，无视频同步入口。
      expect(find.text('第一版不做视频联动'), findsOneWidget);
    });
  });
}
