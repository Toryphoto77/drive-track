import 'dart:math' as math;

import 'package:drive_track/corner_analysis.dart';
import 'package:drive_track/lap_speed_delta.dart';
import 'package:drive_track/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _p({
  required double lat,
  required double lon,
  double speed = 20,
  double bearing = 0,
  int timeMs = 0,
  bool calibrated = false,
  double latG = 0,
  double longG = 0,
}) =>
    TrackPoint(
      timeMs: timeMs,
      lat: lat,
      lon: lon,
      alt: 0,
      speed: speed,
      bearing: bearing,
      hAcc: 3,
      vAcc: 3,
      speedAcc: 0.5,
      provider: 'gps',
      longG: longG,
      latG: latG,
      vertG: 0,
      pitch: 0,
      roll: 0,
      heading: bearing,
      pressureHpa: 0,
      calibrated: calibrated,
    );

/// 圆形轨迹：半径 [radius] 米，逆时针一圈，每点间隔 [stepRad]。
List<TrackPoint> _circle({
  double radius = 40,
  int count = 24,
  double speed = 20,
  bool calibrated = false,
}) {
  const centerLat = 30.0;
  const centerLon = 120.0;
  final cosLat = math.cos(centerLat * math.pi / 180);
  return List.generate(count, (i) {
    final a = i * 2 * math.pi / count;
    final lat = centerLat + (radius * math.sin(a)) / 110540;
    final lon = centerLon + (radius * math.cos(a)) / (111320 * cosLat);
    var brg = (a * 180 / math.pi) + 90;
    if (brg < 0) brg += 360;
    if (brg >= 360) brg -= 360;
    return _p(
      lat: lat,
      lon: lon,
      speed: speed,
      bearing: brg,
      timeMs: i * 1000,
      calibrated: calibrated,
      latG: calibrated ? 1.2 : 0,
      longG: calibrated ? 0.3 : 0,
    );
  });
}

void main() {
  group('弯角分析', () {
    test('直道不产生弯角', () {
      final pts = List.generate(
        30,
        (i) => _p(lat: 30.0 + i * 0.0001, lon: 120.0, timeMs: i * 1000),
      );
      expect(analyzeCorners(pts), isEmpty);
    });

    test('点数不足直接返回空，不硬算', () {
      final pts = List.generate(
        4,
        (i) => _p(lat: 30.0, lon: 120.0 + i * 0.0001, timeMs: i * 1000),
      );
      expect(analyzeCorners(pts), isEmpty);
    });

    test('圆形轨迹识别到弯角，速度与横向 G 来自实测', () {
      final corners = analyzeCorners(_circle(calibrated: true));
      expect(corners, isNotEmpty);
      final c = corners.first;
      expect(c.minKmh, closeTo(72, 0.5));
      expect(c.maxLateralG, closeTo(1.2, 0.001));
      expect(c.lineSpanM, greaterThan(0));
      expect(c.entryIndex, lessThanOrEqualTo(c.apexIndex));
      expect(c.apexIndex, lessThanOrEqualTo(c.exitIndex));
    });

    test('未标定传感器时横向 G 为 null，不冒充 0', () {
      final corners = analyzeCorners(_circle());
      expect(corners, isNotEmpty);
      expect(corners.first.maxLateralG, isNull);
    });
  });

  group('速度差分析', () {
    test('完全相同 → 平均差 0', () {
      final d = compareLapSpeeds(
        selDistances: const [0, 50, 100, 150],
        selSpeedsKmh: const [80, 90, 100, 110],
        refDistances: const [0, 50, 100, 150],
        refSpeedsKmh: const [80, 90, 100, 110],
      );
      expect(d, isNotNull);
      expect(d!.avgDeltaKmh, closeTo(0, 1e-9));
      expect(d.maxGainKmh, closeTo(0, 1e-9));
      expect(d.maxLossKmh, closeTo(0, 1e-9));
      expect(d.pointCount, 4);
    });

    test('分析圈全程快 5 km/h → 平均 +5 且最大领先在起点', () {
      final d = compareLapSpeeds(
        selDistances: const [0, 50, 100],
        selSpeedsKmh: const [85, 95, 105],
        refDistances: const [0, 50, 100],
        refSpeedsKmh: const [80, 90, 100],
      );
      expect(d!.avgDeltaKmh, closeTo(5, 1e-9));
      expect(d.maxGainKmh, closeTo(5, 1e-9));
      expect(d.maxGainFraction, closeTo(0, 1e-9));
      expect(d.maxLossKmh, closeTo(0, 1e-9));
    });

    test('距离区间不重叠 → 无法比较', () {
      final d = compareLapSpeeds(
        selDistances: const [0, 50],
        selSpeedsKmh: const [80, 90],
        refDistances: const [200, 250],
        refSpeedsKmh: const [80, 90],
      );
      expect(d, isNull);
    });

    test('距离轴为空 / 长度不一致 → null', () {
      expect(
        compareLapSpeeds(
          selDistances: const [],
          selSpeedsKmh: const [],
          refDistances: const [0, 10],
          refSpeedsKmh: const [80, 90],
        ),
        isNull,
      );
      expect(
        compareLapSpeeds(
          selDistances: const [0, 10],
          selSpeedsKmh: const [80],
          refDistances: const [0, 10],
          refSpeedsKmh: const [80, 90],
        ),
        isNull,
      );
    });

    test('评级与格式化只映射事实', () {
      expect(speedDeltaVerdict(3.2), '整体明显更快');
      expect(speedDeltaVerdict(-1.4), '整体略慢');
      expect(speedDeltaVerdict(0.2), '整体基本持平');
      expect(formatDeltaSeconds(0.123), '+0.123s');
      expect(formatDeltaSeconds(-0.5), '-0.500s');
      expect(formatPercent(0.5), '50%');
    });
  });
}
