/// 赛道高差剖面与坡度分析（纯函数，便于回归）。
///
/// 输入按时间排序的轨迹点（含海拔），输出：
/// - 累计距离坐标下的海拔剖面（平滑后，避免气压噪声画出锯齿）
/// - 最高/最低/高差、累计爬升/下降
/// - 最大上坡/下坡坡度与平均坡度
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/elevation_profile.dart';

typedef P = ({double lat, double lon, double alt});

void main() {
  test('平面直线上的高差与坡度', () {
    // 纬度每 0.0001°≈11.1m；从 0m 均匀升到 100m，全程约 1.11km。
    final pts = <P>[];
    for (var i = 0; i <= 100; i++) {
      pts.add((lat: 31.0 + i * 0.0001, lon: 121.0, alt: i.toDouble()));
    }
    final p = ElevationProfile.build(pts);
    expect(p.minM, closeTo(0, 1));
    expect(p.maxM, closeTo(100, 1));
    expect(p.rangeM, closeTo(100, 1));
    expect(p.totalClimbM, closeTo(100, 3));
    expect(p.totalDescentM, closeTo(0, 3));
    expect(p.maxGradePct, greaterThan(5));
    expect(p.maxGradePct, lessThan(15));
    expect(p.samples.first.distanceM, closeTo(0, 0.01));
    expect(p.samples.last.distanceM, greaterThan(1000));
  });

  test('先升后降：爬升与下降分别累计', () {
    final pts = <P>[];
    for (var i = 0; i <= 50; i++) {
      pts.add((lat: 31.0 + i * 0.0001, lon: 121.0, alt: i.toDouble() * 2));
    }
    for (var i = 1; i <= 50; i++) {
      pts.add((lat: 31.0 + (50 + i) * 0.0001, lon: 121.0, alt: 100 - i * 2.0));
    }
    final p = ElevationProfile.build(pts);
    expect(p.totalClimbM, closeTo(100, 3));
    expect(p.totalDescentM, closeTo(100, 3));
    expect(p.maxGradePct, greaterThan(0));
    expect(p.minGradePct, lessThan(0));
  });

  test('少于两个有效点时不编造剖面', () {
    final p = ElevationProfile.build(const []);
    expect(p.samples, isEmpty);
    expect(p.rangeM, 0);
    expect(p.maxGradePct, 0);
    expect(p.minGradePct, 0);
  });

  test('海拔为 0 或缺失的点不参与，避免伪造平地', () {
    // altValid=false 由调用方过滤；这里验证重复平稳段不产坡度尖峰。
    final pts = <P>[];
    for (var i = 0; i <= 20; i++) {
      pts.add((lat: 31.0 + i * 0.0001, lon: 121.0, alt: 10));
    }
    final p = ElevationProfile.build(pts);
    expect(p.maxGradePct.abs(), lessThan(0.5));
    expect(p.totalClimbM, lessThan(1));
  });
}
