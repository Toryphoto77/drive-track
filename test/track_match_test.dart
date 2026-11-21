/// 按精确定位自动匹配赛道。
///
/// 到达场地后不再要求用户在列表里翻找：用当前定位与各赛道中心线的
/// 最近距离做匹配，只有带中心线和起终点、且在半径内的赛道才参与。
import 'package:drive_track/track_creation.dart' show GeoPoint;
import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_match.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPackage _pkg(
  String id, {
  required double lat,
  required double lon,
  bool geometry = true,
}) {
  return TrackPackage(
    id: id,
    nameCn: id,
    nameEn: id,
    region: '测试',
    version: 1,
    source: TrackPackageSource.official,
    verification: TrackPackageVerification.verified,
    centerline: geometry
        ? [
            GeoPoint(lat, lon),
            GeoPoint(lat + 0.0005, lon),
            GeoPoint(lat + 0.001, lon),
          ]
        : const [],
    start: geometry ? GeoPoint(lat, lon) : null,
    finish: geometry ? GeoPoint(lat + 0.001, lon) : null,
  );
}

void main() {
  test('命中半径内最近的赛道', () {
    const here = GeoPoint(31.2304, 121.4737);
    final near = _pkg('near', lat: 31.2305, lon: 121.4738);
    final far = _pkg('far', lat: 31.2600, lon: 121.4737);
    final m = matchTrackAt(here, [far, near], maxDistanceM: 300);
    expect(m, isNotNull);
    expect(m!.package.id, 'near');
    expect(m.distanceM, lessThan(50));
  });

  test('超出半径不匹配，避免误选远处赛道', () {
    const here = GeoPoint(31.2304, 121.4737);
    final far = _pkg('far', lat: 31.2600, lon: 121.4737);
    expect(matchTrackAt(here, [far], maxDistanceM: 300), isNull);
  });

  test('无中心线或未闭环的赛道不参与匹配', () {
    const here = GeoPoint(31.2304, 121.4737);
    final noGeometry = _pkg('draft', lat: 31.2304, lon: 121.4737, geometry: false);
    final open = TrackPackage(
      id: 'open',
      nameCn: 'open',
      nameEn: 'open',
      region: '测试',
      version: 1,
      source: TrackPackageSource.user,
      verification: TrackPackageVerification.pending,
      centerline: const [
        GeoPoint(31.2304, 121.4737),
        GeoPoint(31.2305, 121.4737),
      ],
      start: const GeoPoint(31.2304, 121.4737),
      finish: const GeoPoint(31.2305, 121.4737),
    );
    expect(matchTrackAt(here, [noGeometry, open], maxDistanceM: 300), isNull);
  });

  test('没有定位时不猜测赛道', () {
    final near = _pkg('near', lat: 31.2304, lon: 121.4737);
    expect(matchTrackAt(null, [near], maxDistanceM: 300), isNull);
  });
}
