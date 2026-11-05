/// v1.2.17 A 路：赛道记录页 UI 重做测试。
///
/// 覆盖（按跨路契约，B/C 路在 lib/track_timing.dart 实现）：
/// - LapKind JSON：toJson 用键 'k'（'flying'/'out'/'in'），
///   缺失时读作 flying；
/// - lapKindTag / formatLapSectorTimes / pitStopSuffix
///  （lib/main.dart 顶层 helper）；
/// - TrackSectorSpeedRow：有真实分段点时每段显示最低–最高，
///   未开始的段显示 '--'；无分段点只显示占位“段速 --”；
///   nextLineDistanceM 有值显示距离，为 null 不显示；
/// - LapTimer 契约 getter：pitIn/pitOut 命名参数、inPit、
///   pitStopMs、sectorSpeeds、nextLineDistanceM。
///
/// 注意：本文件依赖跨路契约成员（LapKind、Lap.kind、
/// LapTimer.pitIn/pitOut/inPit/pitStopMs/sectorSpeeds/
/// nextLineDistanceM、SectorSpeed），在 B/C 路落地
/// lib/track_timing.dart 之前无法编译；落地后应全过。

import 'package:drive_track/main.dart'
    show formatLapSectorTimes, lapKindTag, pitStopSuffix;
import 'package:drive_track/track_session_display.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Lap _lap({required LapKind kind, List<int> sectors = const [65000, 66000, 64000]}) => Lap(
      number: 1,
      startMs: 0,
      endMs: 195000,
      durationMs: 195000,
      pausedMs: 0,
      dwellNotCounted: false,
      sectorsMs: sectors,
      kind: kind,
    );

void main() {
  group('LapKind JSON（键 k）', () {
    test('inLap/outLap/flying 序列化为 in/out/flying', () {
      expect(_lap(kind: LapKind.inLap).toJson()['k'], 'in');
      expect(_lap(kind: LapKind.outLap).toJson()['k'], 'out');
      expect(_lap(kind: LapKind.flying).toJson()['k'], 'flying');
    });

    test('缺失 k 时读作 flying；往返不丢 kind', () {
      final j = _lap(kind: LapKind.inLap).toJson();
      expect(Lap.fromJson(j).kind, LapKind.inLap);
      final noKind = Map<String, dynamic>.from(j)..remove('k');
      expect(Lap.fromJson(noKind).kind, LapKind.flying);
    });
  });

  group('圈标记与分段文案 helper', () {
    test('lapKindTag：进站圈 / 出站圈 / 飞行圈无标记', () {
      expect(lapKindTag(LapKind.inLap), '进站圈');
      expect(lapKindTag(LapKind.outLap), '出站圈');
      expect(lapKindTag(LapKind.flying), '');
    });

    test('formatLapSectorTimes：S1/S2/S3 各段用时', () {
      expect(formatLapSectorTimes(_lap(kind: LapKind.flying)),
          'S1 1:05.000 / S2 1:06.000 / S3 1:04.000');
      expect(formatLapSectorTimes(_lap(kind: LapKind.flying, sectors: [61000])),
          'S1 1:01.000');
    });

    test('pitStopSuffix：维修区内显示停站时长，否则为空串', () {
      expect(pitStopSuffix(inPit: true, pitStopMs: 95000),
          ' · 维修区 · 停站 00:01:35');
      expect(pitStopSuffix(inPit: false, pitStopMs: 95000), '');
      expect(pitStopSuffix(inPit: true, pitStopMs: 0),
          ' · 维修区 · 停站 00:00:00');
    });
  });

  group('TrackSectorSpeedRow', () {
    testWidgets('有真实分段点：每段最低–最高，未开始的段为 --；有距离显示',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSectorSpeedRow(
              sectorSpeeds: [
                SectorSpeed(87, 212),
                SectorSpeed(90, 205),
                null,
              ],
              sectorLabels: ['S1', 'S2', 'S3'],
              hasSectorPoints: true,
              nextLineDistanceM: 123.4,
            ),
          ),
        ),
      );
      expect(find.text('S1 87–212 · S2 90–205 · S3 --'), findsOneWidget);
      expect(find.text('距下一计时线 123 m'), findsOneWidget);
    });

    testWidgets('无真实分段点：只显示占位“段速 --”；无距离不显示',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSectorSpeedRow(
              sectorSpeeds: [null, null, null],
              sectorLabels: ['S1', 'S2', 'S3'],
              hasSectorPoints: false,
              nextLineDistanceM: null,
            ),
          ),
        ),
      );
      expect(find.text('段速 --'), findsOneWidget);
      expect(find.textContaining('距下一计时线'), findsNothing);
    });
  });

  group('LapTimer 维修区 / 段速 / 下一计时线契约', () {
    test('未进维修区：inPit 为 false、pitStopMs 为 0；无中心线时下一计时线距离为 null', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        sectorPoints: const [GeoPoint(0, 0.001), GeoPoint(0, 0.002)],
        pitIn: const GeoPoint(0, 0.003),
        pitOut: const GeoPoint(0, 0.004),
      );
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
      expect(timer.nextLineDistanceM, isNull);
    });

    test('sectorSpeeds 与分段标签等长，未开始的段为 null', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        sectorPoints: const [GeoPoint(0, 0.001), GeoPoint(0, 0.002)],
        pitIn: const GeoPoint(0, 0.003),
        pitOut: const GeoPoint(0, 0.004),
      );
      expect(timer.sectorSpeeds.length, 3);
      expect(timer.sectorSpeeds, everyElement(isNull));
    });
  });
}
