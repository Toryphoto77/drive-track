/// 弯段坡度与地形分享文本（纯函数，便于回归）。
///
/// 口径：弯段坡度只用入弯—出弯两端的有效海拔，缺海拔时跳过，
/// 绝不用 0 米占位值编造坡度。
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/corner_analysis.dart';
import 'package:drive_track/elevation_profile.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/terrain_analysis.dart';

TrackPoint _p({
  required int i,
  required double alt,
  bool altValid = true,
  double speed = 20,
  double stepDeg = 0.0001,
}) {
  return TrackPoint(
    timeMs: i * 1000,
    lat: 31.0 + i * stepDeg, // 默认每点约 11.1 m
    lon: 121.0,
    alt: alt,
    speed: speed,
    bearing: 0,
    hAcc: 5,
    vAcc: 5,
    speedAcc: 1,
    provider: 'test',
    longG: 0,
    latG: 0,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: 0,
    pressureHpa: 1013,
    calibrated: false,
    altValid: altValid,
  );
}

CornerAnalysis _corner({
  required int entry,
  required int exit,
  required double lengthM,
}) {
  return CornerAnalysis(
    index: 1,
    direction: CornerDirection.left,
    entryIndex: entry,
    apexIndex: (entry + exit) ~/ 2,
    exitIndex: exit,
    entryKmh: 80,
    apexKmh: 60,
    exitKmh: 70,
    minKmh: 60,
    durationMs: (exit - entry) * 1000,
    lengthM: lengthM,
    lineSpanM: 2,
    apexDistanceM: 100,
  );
}

void main() {
  test('上坡弯段按入弯—出弯海拔差给出正坡度', () {
    final points = [
      for (var i = 0; i <= 20; i++) _p(i: i, alt: i.toDouble()),
    ];
    final grades = buildCornerGrades(
      points,
      [_corner(entry: 10, exit: 20, lengthM: 111.1)],
    );
    expect(grades, hasLength(1));
    // 10 m / 111.1 m ≈ 9.0%
    expect(grades.first.gradePct, closeTo(9.0, 0.5));
    expect(grades.first.altChangeM, closeTo(10, 0.01));
    expect(grades.first.distanceM, closeTo(111.1, 1));
    expect(grades.first.cornerIndex, 1);
  });

  test('下端海拔无效时跳过，不用 0 米占位编造坡度', () {
    final points = [
      for (var i = 0; i <= 20; i++) _p(i: i, alt: i.toDouble()),
    ];
    points[20] = _p(i: 20, alt: 0, altValid: false);
    final grades = buildCornerGrades(
      points,
      [_corner(entry: 10, exit: 20, lengthM: 111.1)],
    );
    expect(grades, isEmpty);
  });

  test('弯段太短不计坡度，避免噪声放大', () {
    // 点距约 1.1 m，入弯到出弯仅 1.1 m，低于 5 m 门槛。
    final points = [
      for (var i = 0; i <= 20; i++)
        _p(i: i, alt: i.toDouble(), stepDeg: 0.00001),
    ];
    final grades = buildCornerGrades(
      points,
      [_corner(entry: 10, exit: 11, lengthM: 1.1)],
    );
    expect(grades, isEmpty);
  });

  test('分享文本包含高差、爬升、坡度与弯段坡度', () {
    final points = [
      for (var i = 0; i <= 20; i++) _p(i: i, alt: i.toDouble()),
    ];
    final profile = ElevationProfile.build([
      for (final p in points) (lat: p.lat, lon: p.lon, alt: p.alt),
    ]);
    final grades = buildCornerGrades(
      points,
      [_corner(entry: 10, exit: 20, lengthM: 111.1)],
    );
    final text = terrainShareText(
      title: '天马山',
      profile: profile,
      corners: grades,
    );
    expect(text, contains('天马山'));
    expect(text, contains('高差'));
    expect(text, contains('累计爬升'));
    expect(text, contains('弯 1'));
    expect(text, contains('+9.0%'));
  });

  test('没有弯段数据时分享文本不编造弯段行', () {
    final profile = ElevationProfile.build([
      (lat: 31.0, lon: 121.0, alt: 10),
      (lat: 31.001, lon: 121.0, alt: 20),
    ]);
    final text = terrainShareText(
      title: '测试',
      profile: profile,
      corners: const [],
    );
    expect(text, isNot(contains('弯 ')));
  });
}
