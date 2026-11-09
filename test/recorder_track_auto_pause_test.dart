/// v1.5.4 赛道自动暂停测试（Recorder 侧）。
///
/// 覆盖：
/// - 赛道模式：动过一次、计时开始后，停车低于 2 km/h 满 3 秒自动暂停，
///   车速回升到 5 km/h 以上自动恢复；暂停期间定位点继续落点不断流；
/// - 未动过一次不暂停；计时未开始不暂停；
/// - 街道模式（开关关着）同样停车不自动暂停；
/// - 手动暂停不是自动暂停（isAutoPaused 为假）。
import 'package:drive_track/recorder.dart';
import 'package:flutter_test/flutter_test.dart';

Recorder _trackRecorder({bool timingStarted = true}) {
  final rec = Recorder();
  rec.state = RecState.recording;
  rec.trackAutoPauseEnabled = true;
  rec.trackTimingStarted = timingStarted;
  return rec;
}

void _feed(Recorder rec,
    {required double lat,
    required double lon,
    required double speed,
    required int t}) {
  rec.onLocation({
    'lat': lat,
    'lon': lon,
    'speed': speed,
    'bearing': 90.0,
    'timeMs': t,
    'hAcc': 5.0,
  });
}

void main() {
  group('Recorder 赛道自动暂停', () {
    test('停车满 3 秒自动暂停，起步自动恢复，暂停时定位不断流', () {
      final rec = _trackRecorder();
      // 先动起来（10 m/s，3 个点）。
      _feed(rec, lat: 39.0, lon: 116.0, speed: 10, t: 1000);
      _feed(rec, lat: 39.0, lon: 116.0001, speed: 10, t: 2000);
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 10, t: 3000);
      expect(rec.isAutoPaused, isFalse);
      // 停车：t=4000 起速度 0。
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 4000);
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 5000);
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 6000);
      expect(rec.state, RecState.recording);
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 7000);
      expect(rec.state, RecState.paused);
      expect(rec.isAutoPaused, isTrue);
      expect(rec.calibrationNote, '已自动暂停 · 等待起步');
      // 暂停时定位点继续落点。
      final pointsWhilePaused = rec.points.length;
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 8000);
      _feed(rec, lat: 39.0, lon: 116.0002, speed: 0, t: 9000);
      expect(rec.state, RecState.paused);
      expect(rec.points.length, pointsWhilePaused + 2);
      // 2 m/s（7.2 km/h）起步即恢复。
      _feed(rec, lat: 39.0, lon: 116.0003, speed: 2, t: 10000);
      expect(rec.state, RecState.recording);
      expect(rec.isAutoPaused, isFalse);
    });

    test('未动过一次不自动暂停', () {
      final rec = _trackRecorder();
      for (var t = 1000; t <= 10000; t += 1000) {
        _feed(rec, lat: 39.0, lon: 116.0, speed: 0, t: t);
      }
      expect(rec.state, RecState.recording);
      expect(rec.isAutoPaused, isFalse);
    });

    test('计时未开始不自动暂停', () {
      final rec = _trackRecorder(timingStarted: false);
      _feed(rec, lat: 39.0, lon: 116.0, speed: 10, t: 1000);
      _feed(rec, lat: 39.0, lon: 116.0001, speed: 10, t: 2000);
      for (var t = 3000; t <= 10000; t += 1000) {
        _feed(rec, lat: 39.0, lon: 116.0001, speed: 0, t: t);
      }
      expect(rec.state, RecState.recording);
      expect(rec.isAutoPaused, isFalse);
    });

    test('街道模式不自动暂停', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      rec.trackAutoPauseEnabled = false;
      rec.trackTimingStarted = true;
      _feed(rec, lat: 39.0, lon: 116.0, speed: 10, t: 1000);
      _feed(rec, lat: 39.0, lon: 116.0001, speed: 10, t: 2000);
      for (var t = 3000; t <= 10000; t += 1000) {
        _feed(rec, lat: 39.0, lon: 116.0001, speed: 0, t: t);
      }
      expect(rec.state, RecState.recording);
      expect(rec.isAutoPaused, isFalse);
    });

    test('手动暂停不是自动暂停', () async {
      final rec = _trackRecorder();
      _feed(rec, lat: 39.0, lon: 116.0, speed: 10, t: 1000);
      await rec.pause();
      expect(rec.state, RecState.paused);
      expect(rec.isAutoPaused, isFalse);
      await rec.resume();
      expect(rec.state, RecState.recording);
    });
  });
}
