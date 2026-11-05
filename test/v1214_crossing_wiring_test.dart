/// v1.2.14 越线检测接线测试：lib/main.dart 的接线 + 排空触发。
///
/// 覆盖：
/// - [lapTimerCenterlineForPackage]：有中心线包在 500m 门控内传中心线；
///   无包 / 无起终点 / 离首点 ≥500m / 中心线不足 2 点时返回 null
///   （LapTimer 对应边界回落半径法）；
/// - 接线行为：用 helper 返回的中心线建 LapTimer，沿计时线平行行驶
///   （维修区通道走法）不触发；同一轨迹、无中心线（helper 返回 null）
///   时半径法触发——证明有中心线包确实进了越线模式、无中心线确实回落；
/// - [drainLapTimerPoints]：外接 GPS 25Hz 落点后排空一次即喂到最新点，
///   重复排空只喂新增点、不重喂。
///
/// 注意：_bleDataSub 里的一行触发调用（unawaited(_drainLapTimer())）
/// 本身是状态回调接线，单测覆盖的是它调用的共享排空函数；
/// 25Hz 外接落点本身已由 v1214_lap_feed_rate_test 覆盖。
import 'package:drive_track/main.dart';
import 'package:drive_track/recorder.dart';
import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 东向直道中心线：从 eastM = -200 到 +200（行车方向向东），
/// 与 track_timing_crossing_test 的约定一致（赤道附近，
/// 1 度经度 = 111320 m，1 度纬度 = 110540 m）。
List<GeoPoint> _straightCenterline() => [
      const GeoPoint(0, -200 / 111320),
      const GeoPoint(0, -100 / 111320),
      const GeoPoint(0, 0),
      const GeoPoint(0, 100 / 111320),
      const GeoPoint(0, 200 / 111320),
    ];

TrackPackage _pkg({
  GeoPoint? start = const GeoPoint(0, 0),
  List<GeoPoint> centerline = const [],
}) =>
    TrackPackage(
      id: 'test-track',
      nameCn: '测试赛道',
      nameEn: 'Test Track',
      region: '测试',
      version: 1,
      source: TrackPackageSource.osm,
      verification: TrackPackageVerification.verified,
      start: start,
      centerline: centerline,
    );

/// 沿计时线平行北向行驶的两个点：经度固定在计时线以东 10m，
/// 纬度从 -100m 到 +100m，线段距起终点最近仅 10m。
/// 越线模式：带符号距离恒为 +10m，不变号 → 不触发；
/// 半径法：线段到起终点最短距离 10m < 30m → 触发。
List<TimedPoint> _parallelNorthPoints() => [
      TimedPoint(
          timeMs: 0, lat: -100 / 110540, lon: 10 / 111320, speed: 30),
      TimedPoint(
          timeMs: 1000, lat: 100 / 110540, lon: 10 / 111320, speed: 30),
    ];

void main() {
  group('v1.2.14 接线：lapTimerCenterlineForPackage', () {
    test('有中心线包、首点在门控内 → 传包中心线', () {
      final pkg = _pkg(centerline: _straightCenterline());
      final cl = lapTimerCenterlineForPackage(pkg, const GeoPoint(0, 0));
      expect(cl, isNotNull);
      expect(cl, pkg.centerline);
    });

    test('首点离包起终点 110m（门控内）→ 传中心线', () {
      final pkg = _pkg(centerline: _straightCenterline());
      // 北向 0.001 度 ≈ 110m < 500m。
      final cl = lapTimerCenterlineForPackage(
          pkg, const GeoPoint(0.001, 0));
      expect(cl, isNotNull);
    });

    test('无包 → null，回落半径法', () {
      expect(
          lapTimerCenterlineForPackage(null, const GeoPoint(0, 0)), isNull);
    });

    test('包无起终点 → null，回落半径法', () {
      final pkg = _pkg(start: null, centerline: _straightCenterline());
      expect(lapTimerCenterlineForPackage(pkg, const GeoPoint(0, 0)),
          isNull);
    });

    test('首点离包起终点 1105m（门控外）→ null，不传远处赛道中心线', () {
      final pkg = _pkg(centerline: _straightCenterline());
      // 北向 0.01 度 ≈ 1105m ≥ 500m：包未被采用，其中心线也不传，
      // 否则远处中心线的切线方向会污染回落起终点的穿越判定。
      final cl = lapTimerCenterlineForPackage(
          pkg, const GeoPoint(0.01, 0));
      expect(cl, isNull);
    });

    test('中心线不足 2 点 → null，回落半径法', () {
      final pkgEmpty = _pkg(centerline: const []);
      expect(lapTimerCenterlineForPackage(pkgEmpty, const GeoPoint(0, 0)),
          isNull);
      final pkgOne = _pkg(centerline: [const GeoPoint(0, 0)]);
      expect(lapTimerCenterlineForPackage(pkgOne, const GeoPoint(0, 0)),
          isNull);
    });
  });

  group('v1.2.14 接线行为：helper 返回值进 LapTimer 的判定', () {
    test('有中心线包：沿计时线平行行驶不触发（越线模式）', () {
      final pkg = _pkg(centerline: _straightCenterline());
      final cl =
          lapTimerCenterlineForPackage(pkg, const GeoPoint(0, 0));
      final timer = LapTimer(
          startFinish: const GeoPoint(0, 0), centerline: cl);
      for (final p in _parallelNorthPoints()) {
        timer.addPoint(p);
      }
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });

    test('有中心线包：正向过线触发（越线模式 sanity）', () {
      final pkg = _pkg(centerline: _straightCenterline());
      final cl =
          lapTimerCenterlineForPackage(pkg, const GeoPoint(0, 0));
      final timer = LapTimer(
          startFinish: const GeoPoint(0, 0), centerline: cl);
      timer.addPoint(
          TimedPoint(timeMs: 0, lat: 0, lon: -100 / 111320, speed: 30));
      timer.addPoint(
          TimedPoint(timeMs: 1000, lat: 0, lon: 100 / 111320, speed: 30));
      expect(timer.currentLapNumber, 1);
    });

    test('无中心线包：同一平行轨迹半径法触发（回落）', () {
      final pkg = _pkg(centerline: const []);
      final cl =
          lapTimerCenterlineForPackage(pkg, const GeoPoint(0, 0));
      expect(cl, isNull);
      final timer = LapTimer(
          startFinish: const GeoPoint(0, 0), centerline: cl);
      for (final p in _parallelNorthPoints()) {
        timer.addPoint(p);
      }
      expect(timer.currentLapNumber, 1);
    });
  });

  group('v1.2.14 排空触发：drainLapTimerPoints', () {
    test('外接 GPS 25Hz 落点后排空一次 → 计时器已喂到最新点', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      for (var i = 0; i < 25; i++) {
        rec.onExternalFix(
            30.0 + i * 0.0001, 120.0, 10.0, 90.0, 1000 + i * 40);
      }
      expect(rec.points.length, 25);
      final timer = LapTimer(startFinish: const GeoPoint(30.0, 120.0));
      final fed = drainLapTimerPoints(timer, rec.points, 0);
      expect(fed, 25);
      expect(fed, rec.points.length);
      expect(timer.pointLapNumbers.length, 25);
    });

    test('第二次排空只喂新增点、不重喂、不丢点', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      for (var i = 0; i < 25; i++) {
        rec.onExternalFix(
            30.0 + i * 0.0001, 120.0, 10.0, 90.0, 1000 + i * 40);
      }
      final timer = LapTimer(startFinish: const GeoPoint(30.0, 120.0));
      var fed = drainLapTimerPoints(timer, rec.points, 0);
      expect(fed, 25);
      // 又一秒 25Hz 外接落点。
      for (var i = 25; i < 50; i++) {
        rec.onExternalFix(
            30.0 + i * 0.0001, 120.0, 10.0, 90.0, 1000 + i * 40);
      }
      fed = drainLapTimerPoints(timer, rec.points, fed);
      expect(fed, 50);
      expect(timer.pointLapNumbers.length, 50);
      // 无新点时排空是空操作。
      fed = drainLapTimerPoints(timer, rec.points, fed);
      expect(fed, 50);
      expect(timer.pointLapNumbers.length, 50);
    });
  });
}
