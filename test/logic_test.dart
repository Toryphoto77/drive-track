import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/logic.dart';

TrackPoint pt(int i, {double lat = 31.23, double lon = 121.47, double speed = 15, double heading = 0, double longG = 0, double latG = 0, double roll = 0}) {
  return TrackPoint(
    timeMs: 1000000 + i * 1000,
    lat: lat + i * 0.0001,
    lon: lon + i * 0.0001,
    alt: 10,
    speed: speed,
    bearing: heading,
    hAcc: 5,
    vAcc: 8,
    speedAcc: 0.5,
    provider: 'gps',
    longG: longG,
    latG: latG,
    vertG: 0,
    pitch: 0,
    roll: roll,
    heading: heading,
    pressureHpa: 1013,
    calibrated: true,
  );
}

void main() {
  test('corner and harsh brake are detected, scoring runs', () {
    final pts = <TrackPoint>[];
    for (var i = 0; i < 10; i++) {
      pts.add(pt(i));
    }
    // 过弯段：横向 G 0.5，航向累计转 50 度
    for (var i = 0; i < 6; i++) {
      pts.add(pt(10 + i, speed: 10, heading: (i + 1) * 10.0, latG: 0.5));
    }
    // 急刹车：纵向 -0.55，速度从 15 掉到 8
    pts.add(pt(16, speed: 15, longG: 0));
    pts.add(pt(17, speed: 8, longG: -0.55));
    pts.add(pt(18, speed: 8));
    for (var i = 0; i < 10; i++) {
      pts.add(pt(19 + i, speed: 8));
    }
    final events = detectEvents(pts, TripMode.car);
    expect(events.any((e) => e.kind == 'corner'), isTrue);
    expect(events.any((e) => e.kind == 'harshBrake'), isTrue);
    final sc = scoreTrip(TripMode.car, pts, events);
    expect(sc.total, greaterThan(0));
    expect(sc.total, lessThanOrEqualTo(100));
    expect(sc.reasons.isNotEmpty, isTrue);
  });

  test('bike pace splits are computed', () {
    final pts = <TrackPoint>[];
    // 每点约 111 米（0.001 度纬度），10 点约 1 公里，60 秒
    for (var i = 0; i < 20; i++) {
      pts.add(TrackPoint(
        timeMs: 1000000 + i * 6000,
        lat: 31.23 + i * 0.001,
        lon: 121.47,
        alt: 10,
        speed: 3,
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
      ));
    }
    final splits = paceSplitsKm(pts);
    expect(splits.isNotEmpty, isTrue);
    expect(estimatePowerW(8, 0.02, 85), greaterThan(0));
  });
}
