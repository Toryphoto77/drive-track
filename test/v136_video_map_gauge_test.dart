/// v1.3.6 测试：视频回顾页地图仪表。
///
/// 覆盖：
/// - 纯函数 videoGaugeBounds：点不足 2 个 / 全部重合 → null（不画假线）；
///   正常点列算出正确范围；
/// - 纯函数 videoGaugeProject：投影点全部落在画布内、东西/南北顺序
///   不颠倒；单向跨度为 0 时不除零、该向居中；
/// - 纯函数 videoGaugePointIndex：与回顾页 `_pointAt` 同口径的二分取点；
/// - 纯函数 videoGaugeHeadingDeg：东/北/南/西四向角度；相邻点重合
///   或单点时返回 null（不编方向）；
/// - 纯函数 videoGaugeSpeedKmh：m/s → km/h；NaN / 负值 → null（不编数），
///   0 是合法静止速度；
/// - VideoGaugePosition.next：右上 → 右下 → 左上 → 右上循环；
/// - widget：正常轨迹显示“轨迹地图”与速度小字；点不足显示占位文案；
///   速度无效时不显示速度；
/// - VideoReviewPage 接线：仪表默认出现；点隐藏后消失、点恢复后重现；
///   点切换位置三档循环不崩、不丢仪表。
///
/// 不测计时判定、圈速口径、烧录（本版不做烧录）、离线瓦片与 3D 回放。

import 'package:drive_track/models.dart';
import 'package:drive_track/video_map_gauge.dart';
import 'package:drive_track/video_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _pt(int timeMs, double lat, double lon, [double speed = 15]) =>
    TrackPoint(
      timeMs: timeMs,
      lat: lat,
      lon: lon,
      alt: 10,
      speed: speed,
      bearing: 0,
      hAcc: 5,
      vAcc: 8,
      speedAcc: 0.5,
      provider: 'gps',
      longG: 0,
      latG: 0,
      vertG: 0,
      pitch: 0,
      roll: 0,
      heading: 0,
      pressureHpa: 1013,
      calibrated: true,
    );

/// 向东跑的 3 点：31.34°N 附近，lon 每步 +0.001（约东 95m）。
List<TrackPoint> _eastRun() => [
      _pt(1000, 31.34, 121.22, 10),
      _pt(2000, 31.34, 121.221, 15),
      _pt(3000, 31.34, 121.222, 20),
    ];

Trip _tripWithPoints(List<TrackPoint> points) => Trip(
      id: 't136',
      mode: TripMode.car,
      startMs: 1000,
      endMs: 4000,
      points: points,
      events: const [],
      score: 0,
      subScores: const {},
      scoreReasons: const [],
    );

void main() {
  group('videoGaugeBounds', () {
    test('点不足 2 个 → null，不画假线', () {
      expect(videoGaugeBounds([]), isNull);
      expect(videoGaugeBounds([_pt(1000, 31.34, 121.22)]), isNull);
    });

    test('全部重合 → null', () {
      final pts = [_pt(1000, 31.34, 121.22), _pt(2000, 31.34, 121.22)];
      expect(videoGaugeBounds(pts), isNull);
    });

    test('正常点列算出范围', () {
      final b = videoGaugeBounds(_eastRun());
      expect(b, isNotNull);
      expect(b!.minLat, 31.34);
      expect(b.maxLat, 31.34);
      expect(b.minLon, 121.22);
      expect(b.maxLon, 121.222);
    });
  });

  group('videoGaugeProject', () {
    test('投影点全部落在画布内、东西顺序不颠倒', () {
      final pts = _eastRun();
      final b = videoGaugeBounds(pts)!;
      const size = Size(140, 76);
      final projected = pts
          .map((p) => videoGaugeProject(
              bounds: b, lat: p.lat, lon: p.lon, size: size))
          .toList();
      for (final o in projected) {
        expect(o.dx, greaterThanOrEqualTo(0));
        expect(o.dx, lessThanOrEqualTo(size.width));
        expect(o.dy, greaterThanOrEqualTo(0));
        expect(o.dy, lessThanOrEqualTo(size.height));
      }
      expect(projected[0].dx, lessThan(projected[1].dx));
      expect(projected[1].dx, lessThan(projected[2].dx));
    });

    test('南北向：北边点 y 更小', () {
      final pts = [_pt(1000, 31.34, 121.22), _pt(2000, 31.341, 121.22)];
      final b = videoGaugeBounds(pts)!;
      const size = Size(140, 76);
      final south = videoGaugeProject(
          bounds: b, lat: 31.34, lon: 121.22, size: size);
      final north = videoGaugeProject(
          bounds: b, lat: 31.341, lon: 121.22, size: size);
      expect(north.dy, lessThan(south.dy));
    });

    test('单向跨度为 0 时不除零、该向居中', () {
      // 全在同一纬度上：纵向跨度为 0，y 应居中。
      final pts = _eastRun();
      final b = videoGaugeBounds(pts)!;
      const size = Size(140, 76);
      final o = videoGaugeProject(
          bounds: b, lat: 31.34, lon: 121.221, size: size);
      expect(o.dy, closeTo(size.height / 2, 0.01));
      expect(o.dx, greaterThan(0));
      expect(o.dx, lessThan(size.width));
    });
  });

  group('videoGaugePointIndex', () {
    test('二分取 timeMs ≤ 目标的最后一点', () {
      final pts = _eastRun();
      expect(videoGaugePointIndex(pts, 500), 0);
      expect(videoGaugePointIndex(pts, 1000), 0);
      expect(videoGaugePointIndex(pts, 2500), 1);
      expect(videoGaugePointIndex(pts, 9999), 2);
      expect(videoGaugePointIndex([], 1000), -1);
    });
  });

  group('videoGaugeHeadingDeg', () {
    test('东 90 / 北 0 / 南 180 / 西 270', () {
      final east = [
        _pt(1000, 31.34, 121.22),
        _pt(2000, 31.34, 121.221),
        _pt(3000, 31.34, 121.222),
      ];
      expect(videoGaugeHeadingDeg(east, 1), closeTo(90, 0.5));
      final north = [
        _pt(1000, 31.34, 121.22),
        _pt(2000, 31.341, 121.22),
        _pt(3000, 31.342, 121.22),
      ];
      expect(videoGaugeHeadingDeg(north, 1), closeTo(0, 0.5));
      final south = [
        _pt(1000, 31.342, 121.22),
        _pt(2000, 31.341, 121.22),
        _pt(3000, 31.34, 121.22),
      ];
      expect(videoGaugeHeadingDeg(south, 1), closeTo(180, 0.5));
      final west = [
        _pt(1000, 31.34, 121.222),
        _pt(2000, 31.34, 121.221),
        _pt(3000, 31.34, 121.22),
      ];
      expect(videoGaugeHeadingDeg(west, 1), closeTo(270, 0.5));
    });

    test('相邻点重合 / 单点 → null，不编方向', () {
      final same = [_pt(1000, 31.34, 121.22), _pt(2000, 31.34, 121.22)];
      expect(videoGaugeHeadingDeg(same, 0), isNull);
      expect(videoGaugeHeadingDeg(same, 1), isNull);
      expect(videoGaugeHeadingDeg([_pt(1000, 31.34, 121.22)], 0), isNull);
      expect(videoGaugeHeadingDeg(_eastRun(), 99), isNull);
    });
  });

  group('videoGaugeSpeedKmh', () {
    test('m/s → km/h；NaN / 负值 → null；0 为合法静止速度', () {
      expect(videoGaugeSpeedKmh(_pt(1000, 31.34, 121.22, 15)), 54);
      expect(videoGaugeSpeedKmh(_pt(1000, 31.34, 121.22, 0)), 0);
      expect(videoGaugeSpeedKmh(_pt(1000, 31.34, 121.22, double.nan)),
          isNull);
      expect(videoGaugeSpeedKmh(_pt(1000, 31.34, 121.22, -1)), isNull);
    });
  });

  test('VideoGaugePosition.next 三档循环', () {
    expect(VideoGaugePosition.topRight.next,
        VideoGaugePosition.bottomRight);
    expect(VideoGaugePosition.bottomRight.next,
        VideoGaugePosition.topLeft);
    expect(
        VideoGaugePosition.topLeft.next, VideoGaugePosition.topRight);
  });

  group('VideoMapGauge widget', () {
    testWidgets('正常轨迹显示标题与速度小字', (tester) async {
      final pts = _eastRun();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMapGauge(points: pts, current: pts[1]),
          ),
        ),
      );
      expect(find.text('轨迹地图'), findsOneWidget);
      expect(find.text('54 km/h'), findsOneWidget);
      expect(find.text('轨迹点不足，无法画地图'), findsNothing);
    });

    testWidgets('轨迹点不足显示占位，不画假线', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMapGauge(
              points: [_pt(1000, 31.34, 121.22)],
              current: null,
            ),
          ),
        ),
      );
      expect(find.text('轨迹点不足，无法画地图'), findsOneWidget);
      expect(find.text('轨迹地图'), findsOneWidget);
    });

    testWidgets('速度无效时不显示速度，不编数', (tester) async {
      final pts = _eastRun();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMapGauge(
              points: pts,
              current: _pt(2000, 31.34, 121.221, double.nan),
            ),
          ),
        ),
      );
      expect(find.text('轨迹地图'), findsOneWidget);
      expect(find.textContaining('km/h'), findsNothing);
    });
  });

  group('VideoReviewPage 接线', () {
    Future<void> pumpPage(WidgetTester tester, Trip trip) async {
      await tester.pumpWidget(
        MaterialApp(home: VideoReviewPage(trip: trip)),
      );
      await tester.pump();
    }

    testWidgets('仪表默认出现（右上）', (tester) async {
      await pumpPage(tester, _tripWithPoints(_eastRun()));
      expect(find.text('轨迹地图'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('隐藏后消失、点恢复按钮后重现', (tester) async {
      await pumpPage(tester, _tripWithPoints(_eastRun()));
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(find.text('轨迹地图'), findsNothing);
      expect(find.byIcon(Icons.map), findsOneWidget);
      await tester.tap(find.byIcon(Icons.map));
      await tester.pump();
      expect(find.text('轨迹地图'), findsOneWidget);
    });

    testWidgets('切换位置三档循环不崩、不丢仪表', (tester) async {
      await pumpPage(tester, _tripWithPoints(_eastRun()));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.swap_horiz));
        await tester.pump();
        expect(find.text('轨迹地图'), findsOneWidget);
      }
    });

    testWidgets('轨迹点不足时仪表显示占位', (tester) async {
      await pumpPage(
          tester, _tripWithPoints([_pt(1000, 31.34, 121.22)]));
      expect(find.text('轨迹点不足，无法画地图'), findsOneWidget);
    });
  });
}
