/// 圈速过线辅助判定：IMU 加速度突变 + 姿态 + 气压高度。
///
/// 合成轨迹沿用越线测试约定：计时线在 (0,0)，切线向东，
/// 1 度经度 = 111320 m，1 度纬度 = 110540 m。
import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

TimedPoint _pt(
  int t,
  double eastM, {
  double speed = 30,
  double? longG,
  double? roll,
  double? pitch,
  double? alt,
}) =>
    TimedPoint(
      timeMs: t,
      lat: 0,
      lon: eastM / 111320,
      speed: speed,
      longG: longG,
      rollDeg: roll,
      pitchDeg: pitch,
      altM: alt,
    );

LapTimer _timer() => LapTimer(
      startFinish: const GeoPoint(0, 0),
      centerline: [
        const GeoPoint(0, -200 / 111320),
        const GeoPoint(0, 0),
        const GeoPoint(0, 200 / 111320),
      ],
    );

void main() {
  test('气压高度相对上次过线突变时不关圈', () {
    final timer = _timer();
    timer.addPoint(_pt(0, -15, alt: 100));
    timer.addPoint(_pt(1000, 15, alt: 100)); // 开圈
    expect(timer.currentLapNumber, 1);

    timer.addPoint(_pt(40000, 1200, alt: 100)); // 远离，恢复资格
    timer.addPoint(_pt(41000, -15, alt: 100)); // 回到线前
    timer.addPoint(_pt(42000, 15, alt: 130)); // 高度突变 30 m，疑似多路径
    expect(timer.laps, isEmpty);
    expect(timer.currentLapNumber, 1);
  });

  test('GPS 未变号但贴近计时线且 IMU 加速度突变时补判过线', () {
    final timer = _timer();
    timer.addPoint(_pt(0, -20, longG: 0.1, roll: 0, pitch: 0, alt: 100));
    timer.addPoint(_pt(1000, -5, longG: 0.6, roll: 0, pitch: 0, alt: 100));
    expect(timer.currentLapNumber, 1);
  });

  test('加速度突变不足时不补判', () {
    final timer = _timer();
    timer.addPoint(_pt(0, -20, longG: 0.1, roll: 0, pitch: 0, alt: 100));
    timer.addPoint(_pt(1000, -5, longG: 0.15, roll: 0, pitch: 0, alt: 100));
    expect(timer.currentLapNumber, 0);
    expect(timer.laps, isEmpty);
  });

  test('加速度突变但姿态角跳变过大时不补判', () {
    final timer = _timer();
    timer.addPoint(_pt(0, -20, longG: 0.1, roll: 0, pitch: 0, alt: 100));
    timer.addPoint(_pt(1000, -5, longG: 0.8, roll: 40, pitch: 0, alt: 100));
    expect(timer.currentLapNumber, 0);
    expect(timer.laps, isEmpty);
  });

  test('贴近计时线但不在补判半径内时不补判', () {
    final timer = _timer();
    timer.addPoint(_pt(0, -50, longG: 0.1, alt: 100));
    timer.addPoint(_pt(1000, -30, longG: 0.8, alt: 100));
    expect(timer.currentLapNumber, 0);
    expect(timer.laps, isEmpty);
  });
}
