/// v1.3.4 测试：参考圈 / 幽灵车叠加。
///
/// 覆盖：
/// - 纯函数 ghostPositionAt / ghostPositionForLap（中点插值、超尾钳制、
///   首点前 / 空点 / 圈内无点返回 null、朝向计算）；
/// - 分析页叠加门控（无参照圈不出现开关 / 不画线、参照圈 = 分析圈
///   时速度曲线只一条线、切换分析圈后出现第二条线与图例、关开关后
///   走线图例消失）；
/// - Map 页 widget：幽灵车空心箭头出现 / 缺失（painter.hasGhost +
///   左上角图例 chip）。
///
/// 不测计时判定、圈速统计口径、预测圈 / Delta / 最优圈（本版不动）。

import 'package:drive_track/amap_service.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/recording_map_page.dart';
import 'package:drive_track/track_analysis_page.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _pt(int t, double lat, double lon, double speedMs) {
  return TrackPoint(
    timeMs: t,
    lat: lat,
    lon: lon,
    alt: 10,
    speed: speedMs,
    bearing: 0,
    hAcc: 5,
    vAcc: 5,
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

/// 幽灵车纯函数用折线：先向北、再向东（每段 10 秒）。
List<TrackPoint> _ghostLine() => [
      _pt(0, 31.0000, 121.0000, 20),
      _pt(10000, 31.0010, 121.0000, 20),
      _pt(20000, 31.0010, 121.0010, 20),
    ];

/// 两圈行程：第 1 圈 60 秒（最佳圈）、第 2 圈 70 秒；点每 5 秒一个，
/// 沿对角线单调前进（速度 15–30 m/s 不等）。
Trip _twoLapTrip() {
  final pts = <TrackPoint>[];
  for (var i = 0; i <= 26; i++) {
    pts.add(_pt(
      i * 5000,
      31.3380 + 0.0002 * i,
      121.2180 + 0.0004 * i,
      15 + (i % 5) * 3,
    ));
  }
  return Trip(
    id: 't134',
    mode: TripMode.car,
    startMs: 0,
    endMs: 130000,
    points: pts,
    events: const [],
    score: 0,
    subScores: const {},
    scoreReasons: const [],
    trackId: 'shanghai',
    trackName: '上海',
    isTrackMode: true,
  );
}

Lap _lap1({bool dwell = false}) => Lap(
      number: 1,
      startMs: 0,
      endMs: 60000,
      durationMs: 60000,
      pausedMs: 0,
      dwellNotCounted: dwell,
      sectorsMs: const [20000, 20000, 20000],
    );

Lap _lap2({bool dwell = false}) => Lap(
      number: 2,
      startMs: 60000,
      endMs: 130000,
      durationMs: 70000,
      pausedMs: 0,
      dwellNotCounted: dwell,
      sectorsMs: const [23000, 23000, 24000],
    );

Future<void> _pumpAnalysis(WidgetTester tester, List<Lap> laps) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TrackAnalysisPage(trip: _twoLapTrip(), laps: laps),
    ),
  );
  await tester.pumpAndSettle();
}

const _p1 = GeoPoint(31.3380, 121.2180);
const _p2 = GeoPoint(31.3420, 121.2280);
const _p3 = GeoPoint(31.3400, 121.2230);

Future<void> _pumpMap(WidgetTester tester, RecordingMapPage page) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, height: 480, child: page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RecordingMapPainter _overlayPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('recording-map-overlay')),
  );
  return paint.painter as RecordingMapPainter;
}

void main() {
  group('幽灵车插值纯函数', () {
    test('中点插值：位置与朝向取该段时间', () {
      final g = ghostPositionAt(_ghostLine(), 5000)!;
      expect(g.lat, closeTo(31.0005, 1e-9));
      expect(g.lon, closeTo(121.0, 1e-9));
      expect(g.headingDeg, closeTo(0, 1e-9));
    });

    test('第二段中点插值：朝向为东', () {
      final g = ghostPositionAt(_ghostLine(), 15000)!;
      expect(g.lat, closeTo(31.0010, 1e-9));
      expect(g.lon, closeTo(121.0005, 1e-9));
      expect(g.headingDeg, closeTo(90, 1e-6));
    });

    test('超尾钳制到最后一个点，朝向取末段', () {
      final g = ghostPositionAt(_ghostLine(), 30000)!;
      expect(g.lat, closeTo(31.0010, 1e-9));
      expect(g.lon, closeTo(121.0010, 1e-9));
      expect(g.headingDeg, closeTo(90, 1e-6));
    });

    test('首点前（elapsed < 0）返回 null', () {
      expect(ghostPositionAt(_ghostLine(), -1), isNull);
    });

    test('点数 < 2 返回 null', () {
      expect(ghostPositionAt([], 1000), isNull);
      expect(ghostPositionAt([_pt(0, 31.0, 121.0, 20)], 0), isNull);
    });

    test('朝向计算：北 0 / 东 90 / 南 180 / 西 270', () {
      expect(ghostBearingDeg(31.0, 121.0, 31.001, 121.0), closeTo(0, 1e-6));
      expect(ghostBearingDeg(31.0, 121.0, 31.0, 121.001), closeTo(90, 1e-6));
      expect(ghostBearingDeg(31.001, 121.0, 31.0, 121.0),
          closeTo(180, 1e-6));
      expect(ghostBearingDeg(31.0, 121.001, 31.0, 121.0),
          closeTo(270, 1e-6));
    });

    test('ghostPositionForLap：只切圈内点，圈外点不参与', () {
      final all = [
        _pt(-5000, 30.0, 120.0, 20),
        ..._ghostLine(),
        _pt(30000, 32.0, 122.0, 20),
      ];
      final lap = Lap(
        number: 1,
        startMs: 0,
        endMs: 20000,
        durationMs: 20000,
        pausedMs: 0,
        dwellNotCounted: false,
        sectorsMs: const [10000, 10000],
      );
      final g = ghostPositionForLap(all, lap, 5000)!;
      expect(g.lat, closeTo(31.0005, 1e-9));
      expect(g.lon, closeTo(121.0, 1e-9));
    });

    test('ghostPositionForLap：圈内无点返回 null', () {
      final lap = Lap(
        number: 9,
        startMs: 50000,
        endMs: 60000,
        durationMs: 10000,
        pausedMs: 0,
        dwellNotCounted: false,
        sectorsMs: const [5000, 5000],
      );
      expect(ghostPositionForLap(_ghostLine(), lap, 1000), isNull);
    });
  });

  group('分析页参考圈叠加门控', () {
    testWidgets('无计入圈：开关不出现、两处都不画第二条线', (tester) async {
      await _pumpAnalysis(
          tester, [_lap1(dwell: true), _lap2(dwell: true)]);
      expect(
        find.byKey(const ValueKey('reference-overlay-toggle')),
        findsNothing,
      );
      expect(find.textContaining('青色 = 参照圈'), findsNothing);
      expect(find.textContaining('红色 = 第'), findsNothing);
    });

    testWidgets('默认参照圈 = 分析圈：速度曲线只一条线，走线叠加仍显示',
        (tester) async {
      await _pumpAnalysis(tester, [_lap1(), _lap2()]);
      expect(
        find.byKey(const ValueKey('reference-overlay-toggle')),
        findsOneWidget,
      );
      // 走线图例：参照圈为默认最佳圈（第 1 圈）。
      expect(find.text('青色 = 参照圈（第 1 圈）'), findsOneWidget);
      // 速度曲线：参照圈就是分析圈，只画一条红线，无双线图例。
      expect(find.textContaining('红色 = 第'), findsNothing);
    });

    testWidgets('切换分析圈后速度曲线出现参照圈第二条线与图例',
        (tester) async {
      await _pumpAnalysis(tester, [_lap1(), _lap2()]);
      // 顶栏半透后，滚到视口顶端的内容会滑到栏下、点按被顶栏拦截，
      // 故先把目标滚到视口中部再点（模拟真实使用）。
      await Scrollable.ensureVisible(
          tester.element(find.text('第 2 圈').first),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 2 圈').first);
      await tester.pumpAndSettle();
      expect(
        find.text('红色 = 第 2 圈 · 青色 = 参照圈（第 1 圈）'),
        findsOneWidget,
      );
    });

    testWidgets('关闭叠加开关后走线图例消失，开关本身仍在', (tester) async {
      await _pumpAnalysis(tester, [_lap1(), _lap2()]);
      expect(find.text('青色 = 参照圈（第 1 圈）'), findsOneWidget);
      await Scrollable.ensureVisible(
          tester.element(
              find.byKey(const ValueKey('reference-overlay-toggle'))),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reference-overlay-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('青色 = 参照圈'), findsNothing);
      expect(
        find.byKey(const ValueKey('reference-overlay-toggle')),
        findsOneWidget,
      );
    });
  });

  group('Map 页幽灵车 widget', () {
    testWidgets('传幽灵车参数时出现空心箭头与图例', (tester) async {
      await _pumpMap(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [_p1, _p3, _p2],
          start: _p1,
          finish: _p2,
          sectorPoints: [],
          trail: [_p1, _p3],
          curLat: 31.3400,
          curLon: 121.2230,
          curHeading: 90,
          ghostLat: 31.3390,
          ghostLon: 121.2210,
          ghostHeading: 45,
          statusLine: '第 2 圈 · 当前圈 01:23',
        ),
      );
      expect(find.byKey(const ValueKey('ghost-legend')), findsOneWidget);
      expect(find.text('◇ 幽灵车 · 参考圈'), findsOneWidget);
      final painter = _overlayPainter(tester);
      expect(painter.hasGhost, isTrue);
      // 幽灵车以 GCJ-02 交给 painter（WGS-84 入参 31.3390, 121.2210）。
      expect(painter.ghostLat,
          closeTo(wgsToGcjLocal(31.3390, 121.2210).$1, 1e-9));
      expect(painter.ghostHeading, 45);
    });

    testWidgets('不传幽灵车参数时无图例、无箭头', (tester) async {
      await _pumpMap(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [_p1, _p3, _p2],
          start: _p1,
          finish: _p2,
          sectorPoints: [],
          trail: [_p1, _p3],
          curLat: 31.3400,
          curLon: 121.2230,
          curHeading: 90,
          statusLine: '第 2 圈 · 当前圈 01:23',
        ),
      );
      expect(find.byKey(const ValueKey('ghost-legend')), findsNothing);
      expect(find.text('◇ 幽灵车 · 参考圈'), findsNothing);
      final painter = _overlayPainter(tester);
      expect(painter.hasGhost, isFalse);
    });

    testWidgets('只传部分幽灵车参数时不画（缺一不可）', (tester) async {
      await _pumpMap(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [_p1, _p3, _p2],
          start: _p1,
          finish: _p2,
          sectorPoints: [],
          trail: [_p1, _p3],
          curLat: 31.3400,
          curLon: 121.2230,
          curHeading: 90,
          ghostLat: 31.3390,
          ghostLon: 121.2210,
          statusLine: '第 2 圈 · 当前圈 01:23',
        ),
      );
      expect(find.byKey(const ValueKey('ghost-legend')), findsNothing);
      final painter = _overlayPainter(tester);
      expect(painter.hasGhost, isFalse);
    });
  });
}
