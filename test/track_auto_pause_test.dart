/// v1.5.4 赛道自动暂停测试（LapTimer 侧）。
///
/// 覆盖（与 Recorder 侧的赛道自动暂停同口径，见 track_timing.dart）：
/// - 停车低于 2 km/h 满 3 秒自动暂停计时，圈速扣除暂停时长；
/// - 车速回升到 5 km/h 以上才恢复，2–5 km/h 之间不恢复（迟滞）；
/// - 计时未开始（未过起终点线）时停车不暂停；
/// - 短暂停圈仍计成绩（不停留不计圈），长停满 30 秒才标 dwell；
/// - 2 秒短停不暂停。
///
/// 合成轨迹约定与 track_timing_crossing_test.dart 一致：赤道附近，
/// 1 度经度 = 111320 m；默认车速 30 m/s；计时线在 (0, 0)，切线向东。
import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 东向偏移 eastM（米）、北向偏移 northM（米）的轨迹点。
TimedPoint _pt(int t, double eastM, [double northM = 0, double speed = 30]) =>
    TimedPoint(
      timeMs: t,
      lat: northM / 110540,
      lon: eastM / 111320,
      speed: speed,
    );

/// 东向直道中心线：从 eastM = -200 到 +200（行车方向向东）。
List<GeoPoint> _straightCenterline() => [
      const GeoPoint(0, -200 / 111320),
      const GeoPoint(0, -100 / 111320),
      const GeoPoint(0, 0),
      const GeoPoint(0, 100 / 111320),
      const GeoPoint(0, 200 / 111320),
    ];

/// 赛道自动暂停计时器：停车 < 2 km/h 满 3 秒暂停，> 5 km/h 恢复。
LapTimer _autoPauseTimer() => LapTimer(
      startFinish: const GeoPoint(0, 0),
      centerline: _straightCenterline(),
      autoPauseThresholdMs: 3000,
      autoPauseSpeedMs: 2 / 3.6,
      autoResumeSpeedMs: 5 / 3.6,
    );

/// 开圈：t=500 过起终点线（与既有 dwell 测试同一走法）。
void _openLap(LapTimer timer) {
  timer.addPoint(_pt(0, -15));
  timer.addPoint(_pt(1000, 15));
  expect(timer.currentLapNumber, 1);
}

/// 关圈：跳回线西再正向过线，过线时刻 t=61500。
void _closeLap(LapTimer timer) {
  timer.addPoint(_pt(61000, -15));
  timer.addPoint(_pt(62000, 15));
  expect(timer.laps.length, 1);
}

void main() {
  group('赛道自动暂停（LapTimer）', () {
    test('停车满 3 秒暂停，起步恢复，圈速扣除暂停时长', () {
      final timer = _autoPauseTimer();
      _openLap(timer);
      // 开到 300 m 处停车（t=10000 起速度 0）。
      timer.addPoint(_pt(10000, 300, 0, 0));
      timer.addPoint(_pt(11000, 300, 0, 0));
      timer.addPoint(_pt(12000, 300, 0, 0));
      expect(timer.isPaused, isFalse);
      timer.addPoint(_pt(13000, 300, 0, 0));
      expect(timer.isPaused, isTrue);
      // 暂停中圈时冻结：再停 2 秒，当前圈已用不再涨。
      final frozen = timer.currentLapMs;
      timer.addPoint(_pt(15000, 300, 0, 0));
      expect(timer.currentLapMs, frozen);
      // 2 m/s（7.2 km/h）起步即恢复。
      timer.addPoint(_pt(20000, 330, 0, 2));
      expect(timer.isPaused, isFalse);
      _closeLap(timer);
      final lap = timer.laps.first;
      // 暂停 7000 ms（13000→20000），圈速 61500 - 500 - 7000。
      expect(lap.pausedMs, 7000);
      expect(lap.durationMs, 54000);
      expect(lap.dwellNotCounted, isFalse);
    });

    test('迟滞：2–5 km/h 低速不恢复，5 km/h 以上才恢复', () {
      final timer = _autoPauseTimer();
      _openLap(timer);
      for (var t = 10000; t <= 13000; t += 1000) {
        timer.addPoint(_pt(t, 300, 0, 0));
      }
      expect(timer.isPaused, isTrue);
      // 1.0 m/s（3.6 km/h）：高于停车门槛、低于恢复门槛，仍停着。
      timer.addPoint(_pt(14000, 300, 0, 1.0));
      expect(timer.isPaused, isTrue);
      // 1.5 m/s（5.4 km/h）：高于恢复门槛，恢复。
      timer.addPoint(_pt(15000, 310, 0, 1.5));
      expect(timer.isPaused, isFalse);
    });

    test('计时未开始时停车不暂停', () {
      final timer = _autoPauseTimer();
      // 未过起终点线：原地停 10 秒也不暂停。
      for (var t = 0; t <= 10000; t += 1000) {
        timer.addPoint(_pt(t, -100, 0, 0));
      }
      expect(timer.isPaused, isFalse);
      expect(timer.currentLapNumber, 0);
    });

    test('2 秒短停不暂停', () {
      final timer = _autoPauseTimer();
      _openLap(timer);
      timer.addPoint(_pt(10000, 300, 0, 0));
      timer.addPoint(_pt(11000, 300, 0, 0));
      timer.addPoint(_pt(12000, 300, 0, 30));
      expect(timer.isPaused, isFalse);
    });

    test('长停满 30 秒才标 dwell：短暂停圈仍计成绩', () {
      final timer = _autoPauseTimer();
      _openLap(timer);
      for (var t = 10000; t <= 45000; t += 1000) {
        timer.addPoint(_pt(t, 300, 0, 0));
      }
      expect(timer.isPaused, isTrue);
      timer.addPoint(_pt(46000, 330, 0, 30));
      expect(timer.isPaused, isFalse);
      _closeLap(timer);
      final lap = timer.laps.first;
      // 暂停 33000 ms（13000→46000），停车总时长 36 秒 ≥ 30 秒，标 dwell。
      expect(lap.pausedMs, 33000);
      expect(lap.dwellNotCounted, isTrue);
      expect(lap.durationMs, 61500 - 500 - 33000);
    });

    test('未启用自动暂停时走旧 dwell 规则（停车 30 秒才暂停）', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        centerline: _straightCenterline(),
      );
      _openLap(timer);
      for (var t = 10000; t <= 39000; t += 1000) {
        timer.addPoint(_pt(t, 300, 0, 0));
      }
      expect(timer.isPaused, isFalse);
      timer.addPoint(_pt(40000, 300, 0, 0));
      expect(timer.isPaused, isTrue);
    });
  });
}
