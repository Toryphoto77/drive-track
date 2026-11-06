/// v1.3.1（B 路）测试：分析页卫星底图 + 速度着色轨迹 + 区块隐藏。
///
/// 覆盖：地理投影换算（经纬度→屏幕坐标往返）、速度→颜色映射
/// （含最低 = 最高速度的退化分支）、图例区间取自实测速度范围、
/// 回落门控（失败计数达阈值切示意图）；widget 测试覆盖卫星/示意
/// 切换与区块隐藏开关。
///
/// 每圈走线图保持现有归一化示意图不动（本版不做每圈卫星图），
/// 故此处不测每圈卫星图。

import 'package:drive_track/models.dart';
import 'package:drive_track/satellite_tiles.dart';
import 'package:drive_track/track_analysis_geo.dart';
import 'package:drive_track/track_analysis_page.dart';
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

Trip _trip() {
  // 上赛附近小环线：8 个实测点，速度 10–50 m/s（36–180 km/h）。
  final pts = [
    _pt(0, 31.3380, 121.2180, 10),
    _pt(1000, 31.3380, 121.2280, 20),
    _pt(2000, 31.3420, 121.2280, 30),
    _pt(3000, 31.3420, 121.2180, 40),
    _pt(4000, 31.3400, 121.2130, 50),
    _pt(5000, 31.3360, 121.2130, 45),
    _pt(6000, 31.3360, 121.2180, 25),
    _pt(7000, 31.3380, 121.2180, 15),
  ];
  return Trip(
    id: 't1',
    mode: TripMode.car,
    startMs: 0,
    endMs: 7000,
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

void main() {
  group('地理投影换算', () {
    test('经纬度→屏幕坐标往返误差小于 1e-4 度', () {
      final bounds = analysisGeoBounds([
        (lat: 31.3380, lon: 121.2180),
        (lat: 31.3420, lon: 121.2280),
      ])!;
      final zoom = analysisGeoZoom(
        bounds: bounds,
        widthPx: 320,
        heightPx: 220,
      );
      final projector = AnalysisGeoProjector(
        bounds: bounds,
        zoom: zoom,
        size: const Size(320, 220),
      );
      for (final p in [
        (lat: 31.3380, lon: 121.2180),
        (lat: 31.3400, lon: 121.2230),
        (lat: 31.3420, lon: 121.2280),
      ]) {
        final back = projector.unproject(projector.project(p.lat, p.lon));
        expect((back.lat - p.lat).abs(), lessThan(1e-4));
        expect((back.lon - p.lon).abs(), lessThan(1e-4));
      }
    });

    test('投影点落在画布内', () {
      final bounds = analysisGeoBounds([
        (lat: 31.3380, lon: 121.2180),
        (lat: 31.3420, lon: 121.2280),
      ])!;
      final zoom = analysisGeoZoom(
        bounds: bounds,
        widthPx: 320,
        heightPx: 220,
      );
      final projector = AnalysisGeoProjector(
        bounds: bounds,
        zoom: zoom,
        size: const Size(320, 220),
      );
      final o = projector.project(31.3400, 121.2230);
      expect(o.dx, greaterThanOrEqualTo(0));
      expect(o.dx, lessThanOrEqualTo(320));
      expect(o.dy, greaterThanOrEqualTo(0));
      expect(o.dy, lessThanOrEqualTo(220));
    });

    test('点不足 2 个或范围退化时范围为 null', () {
      expect(analysisGeoBounds([]), isNull);
      expect(
        analysisGeoBounds([(lat: 31.0, lon: 121.0)]),
        isNull,
      );
      expect(
        analysisGeoBounds([
          (lat: 31.0, lon: 121.0),
          (lat: 31.0, lon: 121.0),
        ]),
        isNull,
      );
    });

    test('瓦片数超 64 张时自动降级', () {
      // 大画布 + 中等范围：米/像素初选缩放较高，瓦片数超 64，
      // 须降级到 64 张以内。
      final bounds = analysisGeoBounds([
        (lat: 31.1000, lon: 121.1000),
        (lat: 31.5000, lon: 121.6000),
      ])!;
      final zoom = analysisGeoZoom(
        bounds: bounds,
        widthPx: 2560,
        heightPx: 1440,
      );
      final r = satelliteTileRange(
        minLat: bounds.minLat,
        maxLat: bounds.maxLat,
        minLon: bounds.minLon,
        maxLon: bounds.maxLon,
        zoom: zoom,
      );
      final count = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
      expect(count, lessThanOrEqualTo(satelliteMaxTiles));
    });
  });

  group('速度→颜色映射', () {
    test('最低速为蓝、最高速为红，中间色不同', () {
      final low = speedToRainbowColor(36, 36, 180);
      final mid = speedToRainbowColor(108, 36, 180);
      final high = speedToRainbowColor(180, 36, 180);
      expect(low, const Color(0xFF2563EB));
      expect(high, const Color(0xFFE10600));
      expect(mid, isNot(low));
      expect(mid, isNot(high));
    });

    test('最低 = 最高速度时退化为中间色，不除以零', () {
      final c = speedToRainbowColor(60, 60, 60);
      expect(c, const Color(0xFFFACC15));
    });

    test('图例区间取自实测速度范围，四段连续覆盖', () {
      final segs = speedLegendSegments(36, 180);
      expect(segs.length, 4);
      expect(segs.first.fromKmh, 36);
      expect(segs.last.toKmh, 180);
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].fromKmh, segs[i - 1].toKmh);
      }
    });

    test('图例在最低 = 最高时只给一段', () {
      final segs = speedLegendSegments(60, 60);
      expect(segs.length, 1);
      expect(segs.first.fromKmh, 60);
      expect(segs.first.toKmh, 60);
    });
  });

  group('回落门控', () {
    test('失败 2 张不回落，达 3 张回落', () {
      expect(shouldFallbackToSchematic(0), isFalse);
      expect(shouldFallbackToSchematic(2), isFalse);
      expect(shouldFallbackToSchematic(3), isTrue);
      expect(shouldFallbackToSchematic(5), isTrue);
      expect(
        satelliteFallbackFailureThreshold,
        3,
      );
    });
  });

  group('分析页 widget：卫星/示意切换与区块隐藏', () {
    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackAnalysisPage(trip: _trip(), laps: const []),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认卫星地图；测试环境瓦片失败达阈值后回落示意图',
        (tester) async {
      await pumpPage(tester);
      // 默认卫星模式：卫星 chip 存在；瓦片加载失败达阈值后回落，
      // 状态行写明回落原因，不白屏。
      expect(
        find.byKey(const ValueKey('analysis-map-satellite')),
        findsOneWidget,
      );
      expect(find.text('卫星图未加载，已显示示意图'), findsOneWidget);
      expect(find.text('暂无轨迹点，走线为空'), findsNothing);
    });

    testWidgets('切到示意地图后显示归一化走线文案', (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(
          find.byKey(const ValueKey('analysis-map-schematic')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-map-schematic')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('走线为实测轨迹归一化显示，按速度着色（白→红）'),
        findsOneWidget,
      );
      expect(find.text('卫星图未加载，已显示示意图'), findsNothing);
    });

    testWidgets('速度曲线区块隐藏开关隐藏卡片', (tester) async {
      await pumpPage(tester);
      expect(find.text('速度'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hide-speed')));
      await tester.pump();
      expect(find.text('速度'), findsNothing);
      // 标题行仍在，可再展开。
      expect(find.text('速度曲线'), findsOneWidget);
    });

    testWidgets('走线图区块隐藏开关隐藏卫星/示意切换', (tester) async {
      await pumpPage(tester);
      expect(
        find.byKey(const ValueKey('analysis-map-satellite')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('hide-track-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hide-track-line')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('analysis-map-satellite')),
        findsNothing,
      );
      expect(find.text('轨迹走线图'), findsOneWidget);
    });

    testWidgets('总览隐藏开关隐藏总览卡片', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('hide-overview')));
      await tester.pump();
      // 总览卡片标题（含行程模式）消失，标题行仍在。
      expect(find.text('总览'), findsOneWidget);
      expect(find.text('关键极值'), findsNothing);
    });
  });
}
