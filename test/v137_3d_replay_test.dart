/// v1.3.7 测试：赛后分析页「3D 回放」。
///
/// 覆盖：
/// - 纯函数 replayPointAt / replayPointIndex：按时间取点、二分口径、
///   越界钳制到首/末点；点不足 2 个返回 null / -1（不启动回放）；
/// - 纯函数 replayTotalMs / replayProgressMs /
///   replayElapsedFromProgress：总时长、进度钳制、拖动换算；
/// - 纯函数 replayAdvanceMs / ReplaySpeed：倍速 1x/2x/4x 换算；
/// - 纯函数 replayTimeLabel：m:ss 读数；
/// - 共享 3D 投影（lib/perspective_projection.dart）：
///   forwardRightMeters ↔ forwardRightToLatLon 往返（北向上与
///   车头朝上）、perspectiveFactor 边界（向后钳制 -100 米、
///   远处收束到地平线、2D 退化恒为 1）、perspectiveProject
///   远近点纵向顺序（近点在下、远点在上近地平线）；
/// - 纯函数 replayProjectionCenter / replayPxPerM：投影中心在
///   轨迹南缘外、全部实测点投影落在画布内；点不足/全重合 → null；
/// - widget：点不足占位、播放/暂停切换、播放推进后速度跟随、
///   播到末尾自动停、倍速切换、拖动 Slider 后位置跟随；
/// - TrackAnalysisPage 接线：默认仍是卫星视图、3D 回放 chip
///   存在；切到 3D 回放出现播放条、再切回卫星恢复原视图；
///   点不足的行程切 3D 回放显示占位文案。
///
/// 不测计时判定、圈速口径、预测圈/Delta/最优圈、赛道包数据、
/// GPS 来源徽标、分享导出、离线瓦片（本版不做）。

import 'package:drive_track/models.dart';
import 'package:drive_track/perspective_projection.dart';
import 'package:drive_track/replay_3d.dart';
import 'package:drive_track/track_analysis_page.dart';
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

/// 向东跑的 3 点：31.34°N 附近，lon 每步 +0.001（约东 95m），
/// 速度 10 / 15 / 20 m/s（36 / 54 / 72 km/h），便于跟随断言。
List<TrackPoint> _eastRun() => [
      _pt(1000, 31.34, 121.22, 10),
      _pt(2000, 31.34, 121.221, 15),
      _pt(3000, 31.34, 121.222, 20),
    ];

Trip _tripWithPoints(List<TrackPoint> points) => Trip(
      id: 't137',
      mode: TripMode.car,
      startMs: 1000,
      endMs: 3000,
      points: points,
      events: const [],
      score: 0,
      subScores: const {},
      scoreReasons: const [],
    );

void main() {
  group('replayPointIndex / replayPointAt', () {
    test('按时间取点，越界钳制到首/末点', () {
      final pts = _eastRun();
      expect(replayPointIndex(pts, 0), 0);
      expect(replayPointIndex(pts, 500), 0);
      expect(replayPointIndex(pts, 1000), 1);
      expect(replayPointIndex(pts, 1500), 1);
      expect(replayPointIndex(pts, 2000), 2);
      expect(replayPointIndex(pts, 99999), 2);
      expect(replayPointIndex(pts, -500), 0);
      expect(replayPointAt(pts, 1500), pts[1]);
      expect(replayPointAt(pts, 99999), pts[2]);
    });

    test('点不足 2 个返回 -1 / null，不启动回放', () {
      expect(replayPointIndex([], 0), -1);
      expect(replayPointIndex([_pt(1000, 31.34, 121.22)], 0), -1);
      expect(replayPointAt([], 0), isNull);
      expect(replayPointAt([_pt(1000, 31.34, 121.22)], 0), isNull);
    });
  });

  group('replayTotalMs / replayProgressMs / replayElapsedFromProgress', () {
    test('总时长 = 末点 − 首点；点不足时为 0', () {
      expect(replayTotalMs(_eastRun()), 2000);
      expect(replayTotalMs([]), 0);
      expect(replayTotalMs([_pt(1000, 31.34, 121.22)]), 0);
    });

    test('进度钳制 0..1；总时长 ≤ 0 时为 0', () {
      expect(replayProgressMs(1000, 2000), 0.5);
      expect(replayProgressMs(-100, 2000), 0);
      expect(replayProgressMs(9999, 2000), 1);
      expect(replayProgressMs(100, 0), 0);
    });

    test('拖动换算：进度 → 已播毫秒，越界钳制', () {
      expect(replayElapsedFromProgress(0.5, 2000), 1000);
      expect(replayElapsedFromProgress(0, 2000), 0);
      expect(replayElapsedFromProgress(1, 2000), 2000);
      expect(replayElapsedFromProgress(-0.5, 2000), 0);
      expect(replayElapsedFromProgress(1.5, 2000), 2000);
      expect(replayElapsedFromProgress(0.5, 0), 0);
    });
  });

  group('ReplaySpeed 倍速换算', () {
    test('1x/2x/4x 因子与推进毫秒', () {
      expect(ReplaySpeed.x1.factor, 1);
      expect(ReplaySpeed.x2.factor, 2);
      expect(ReplaySpeed.x4.factor, 4);
      expect(ReplaySpeed.x1.label, '1x');
      expect(ReplaySpeed.x2.label, '2x');
      expect(ReplaySpeed.x4.label, '4x');
      expect(replayAdvanceMs(100, ReplaySpeed.x1), 100);
      expect(replayAdvanceMs(100, ReplaySpeed.x2), 200);
      expect(replayAdvanceMs(100, ReplaySpeed.x4), 400);
    });
  });

  test('replayTimeLabel：m:ss 读数', () {
    expect(replayTimeLabel(0), '0:00');
    expect(replayTimeLabel(7000), '0:07');
    expect(replayTimeLabel(65000), '1:05');
    expect(replayTimeLabel(3723000), '1:02:03');
  });

  group('共享 3D 投影往返与边界', () {
    test('forwardRightMeters ↔ forwardRightToLatLon 往返（北向上）', () {
      const centerLat = 31.34;
      const centerLon = 121.22;
      const lat = 31.341;
      const lon = 121.221;
      final fr = forwardRightMeters(
        centerLat: centerLat,
        centerLon: centerLon,
        headingDeg: 0,
        headingUp: false,
        lat: lat,
        lon: lon,
      );
      // 北向上：前向 ≈ 北 110.5m，右向 ≈ 东 95m。
      expect(fr.$1, closeTo(110.54, 0.5));
      expect(fr.$2, closeTo(95.2, 0.5));
      final back = forwardRightToLatLon(
        centerLat: centerLat,
        centerLon: centerLon,
        headingDeg: 0,
        headingUp: false,
        forward: fr.$1,
        right: fr.$2,
      );
      expect(back.lat, closeTo(lat, 1e-9));
      expect(back.lon, closeTo(lon, 1e-9));
    });

    test('forwardRightMeters ↔ forwardRightToLatLon 往返（车头朝上 90°）', () {
      const centerLat = 31.34;
      const centerLon = 121.22;
      const lat = 31.341;
      const lon = 121.221;
      final fr = forwardRightMeters(
        centerLat: centerLat,
        centerLon: centerLon,
        headingDeg: 90,
        headingUp: true,
        lat: lat,
        lon: lon,
      );
      final back = forwardRightToLatLon(
        centerLat: centerLat,
        centerLon: centerLon,
        headingDeg: 90,
        headingUp: true,
        forward: fr.$1,
        right: fr.$2,
      );
      expect(back.lat, closeTo(lat, 1e-9));
      expect(back.lon, closeTo(lon, 1e-9));
    });

    test('perspectiveFactor 边界：向后钳制、远处收束、2D 恒为 1', () {
      // 前向 -100 与 -200 同因子（钳制）。
      expect(perspectiveFactor(-200), perspectiveFactor(-100));
      expect(perspectiveFactor(-100), closeTo(140 / 40, 1e-9));
      // 车标处因子为 1，越远越小、趋近 0。
      expect(perspectiveFactor(0), 1);
      expect(perspectiveFactor(1000), lessThan(0.2));
      expect(perspectiveFactor(1000), greaterThan(0));
      expect(perspectiveFactor(100), greaterThan(perspectiveFactor(1000)));
      // 2D 退化恒为 1。
      expect(perspectiveFactor(-500, is3d: false), 1);
      expect(perspectiveFactor(5000, is3d: false), 1);
    });

    test('perspectiveProject：近点在下、远点在上近地平线', () {
      const size = Size(400, 300);
      const pxPerM = 1.0;
      final near = perspectiveProject(
          size: size, forward: 0, right: 0, pxPerM: pxPerM);
      final far = perspectiveProject(
          size: size, forward: 800, right: 0, pxPerM: pxPerM);
      // 近点在车标线（72% 高），远点逼近地平线（16% 高）。
      expect(near.dy, closeTo(size.height * 0.72, 0.01));
      expect(far.dy, greaterThan(size.height * 0.16));
      expect(far.dy, lessThan(size.height * 0.30));
      expect(far.dy, lessThan(near.dy));
      // 2D 退化：中心点在画面中央。
      final flat = perspectiveProject(
          size: size, forward: 0, right: 0, pxPerM: pxPerM, is3d: false);
      expect(flat.dx, size.width / 2);
      expect(flat.dy, size.height / 2);
    });
  });

  group('replayProjectionCenter / replayPxPerM', () {
    test('投影中心在轨迹南缘外，全部实测点投影落在画布内', () {
      final pts = _eastRun();
      final center = replayProjectionCenter(pts)!;
      expect(center.centerLat, lessThan(31.34));
      expect(center.centerLat, closeTo(31.34 - 0.0005, 1e-9));
      expect(center.centerLon, closeTo(121.221, 1e-9));
      const size = Size(400, 260);
      final pxPerM = replayPxPerM(
        size: size,
        points: pts,
        centerLat: center.centerLat,
        centerLon: center.centerLon,
      );
      expect(pxPerM, greaterThan(0));
      for (final p in pts) {
        final o = perspectiveProjectLatLon(
          size: size,
          centerLat: center.centerLat,
          centerLon: center.centerLon,
          headingDeg: 0,
          headingUp: false,
          lat: p.lat,
          lon: p.lon,
          pxPerM: pxPerM,
          is3d: true,
        );
        expect(o.dx, greaterThanOrEqualTo(0));
        expect(o.dx, lessThanOrEqualTo(size.width));
        expect(o.dy, greaterThanOrEqualTo(0));
        expect(o.dy, lessThanOrEqualTo(size.height));
      }
    });

    test('点不足 / 全部重合 → null', () {
      expect(replayProjectionCenter([]), isNull);
      expect(replayProjectionCenter([_pt(1000, 31.34, 121.22)]), isNull);
      expect(
          replayProjectionCenter(
              [_pt(1000, 31.34, 121.22), _pt(2000, 31.34, 121.22)]),
          isNull);
    });
  });

  group('Replay3dView widget', () {
    testWidgets('轨迹点不足显示占位，不启动回放', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: []),
          ),
        ),
      );
      expect(find.text('轨迹点不足，无法 3D 回放'), findsOneWidget);
      expect(find.byKey(const ValueKey('replay-3d-play-pause')),
          findsNothing);
    });

    testWidgets('正常轨迹显示播放条与读数（首点速度 36 km/h）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: _eastRun()),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('replay-3d-play-pause')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('replay-3d-slider')), findsOneWidget);
      expect(find.text('0:00 / 0:02'), findsOneWidget);
      expect(find.text('36 km/h'), findsOneWidget);
    });

    testWidgets('播放/暂停切换：播放后推进，暂停后停住', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: _eastRun()),
          ),
        ),
      );
      // 播放。
      await tester.tap(find.byKey(const ValueKey('replay-3d-play-pause')));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
      // 推进 1.2 秒（1x）：到第 2 点，速度 54 km/h。
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('54 km/h'), findsOneWidget);
      expect(find.text('0:01 / 0:02'), findsOneWidget);
      // 暂停：再过 1 秒也不动。
      await tester.tap(find.byKey(const ValueKey('replay-3d-play-pause')));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('54 km/h'), findsOneWidget);
    });

    testWidgets('播到末尾自动停回播放态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: _eastRun()),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('replay-3d-play-pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('0:02 / 0:02'), findsOneWidget);
      expect(find.text('72 km/h'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('倍速切换：2x 下 600 毫秒即到第 2 点', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: _eastRun()),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('replay-3d-speed-2x')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('replay-3d-play-pause')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('54 km/h'), findsOneWidget);
      // 4x chip 同样可点，不崩。
      await tester.tap(find.byKey(const ValueKey('replay-3d-speed-4x')));
      await tester.pump();
      expect(find.text('54 km/h'), findsOneWidget);
    });

    testWidgets('拖动 Slider 后位置跟随（速度与时间都变）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: _eastRun()),
          ),
        ),
      );
      await tester.drag(
          find.byKey(const ValueKey('replay-3d-slider')),
          const Offset(500, 0));
      await tester.pump();
      expect(find.text('72 km/h'), findsOneWidget);
      expect(find.text('0:02 / 0:02'), findsOneWidget);
      await tester.drag(
          find.byKey(const ValueKey('replay-3d-slider')),
          const Offset(-500, 0));
      await tester.pump();
      expect(find.text('36 km/h'), findsOneWidget);
      expect(find.text('0:00 / 0:02'), findsOneWidget);
    });

    testWidgets('速度无效时不显示速度，不编数', (tester) async {
      final pts = [
        _pt(1000, 31.34, 121.22, double.nan),
        _pt(2000, 31.34, 121.221, double.nan),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Replay3dView(points: pts),
          ),
        ),
      );
      expect(find.textContaining('km/h'), findsNothing);
      expect(find.text('0:00 / 0:01'), findsOneWidget);
    });
  });

  group('TrackAnalysisPage 接线', () {
    Future<void> pumpPage(WidgetTester tester, Trip trip) async {
      await tester.pumpWidget(
        MaterialApp(home: TrackAnalysisPage(trip: trip, laps: const [])),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认仍是卫星视图，3D 回放 chip 存在', (tester) async {
      await pumpPage(tester, _tripWithPoints(_eastRun()));
      expect(find.byKey(const ValueKey('analysis-map-3d-replay')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('replay-3d-play-pause')),
          findsNothing);
    });

    testWidgets('切到 3D 回放出现播放条，再切回卫星恢复原视图',
        (tester) async {
      await pumpPage(tester, _tripWithPoints(_eastRun()));
      // 顶栏半透后，滚到视口顶端的内容会滑到栏下、点按被顶栏拦截，
      // 故先把目标滚到视口中部再点（模拟真实使用）。
      await Scrollable.ensureVisible(
          tester.element(
              find.byKey(const ValueKey('analysis-map-3d-replay'))),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-map-3d-replay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('replay-3d-play-pause')),
          findsOneWidget);
      expect(find.text('36 km/h'), findsOneWidget);
      expect(find.textContaining('3D 透视回放'), findsOneWidget);
      await Scrollable.ensureVisible(
          tester.element(
              find.byKey(const ValueKey('analysis-map-satellite'))),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-map-satellite')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('replay-3d-play-pause')),
          findsNothing);
    });

    testWidgets('点不足的行程切 3D 回放显示占位文案', (tester) async {
      await pumpPage(
          tester, _tripWithPoints([_pt(1000, 31.34, 121.22)]));
      await tester.ensureVisible(
          find.byKey(const ValueKey('analysis-map-3d-replay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analysis-map-3d-replay')));
      await tester.pumpAndSettle();
      expect(find.text('轨迹点不足，无法 3D 回放'), findsOneWidget);
    });
  });
}
