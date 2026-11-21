/// 按当前定位自动匹配最近赛道。
///
/// 到达场地后不必再在长列表里翻找：用定位点到各赛道中心线顶点的
/// 最近距离做匹配，只在 [maxDistanceM] 内、且带完整中心线与起终点的
/// 赛道参与，避免误选缺少几何的草稿或远处赛道。
import 'models.dart';
import 'track_creation.dart' show GeoPoint;
import 'track_library.dart';

class TrackMatch {
  const TrackMatch({required this.package, required this.distanceM});

  final TrackPackage package;

  /// 定位点到该赛道中心线的最近距离（米）。
  final double distanceM;
}

/// [here] 为 null（无有效定位）时返回 null，绝不猜测。
TrackMatch? matchTrackAt(
  GeoPoint? here,
  List<TrackPackage> packages, {
  double maxDistanceM = 300,
}) {
  if (here == null) return null;
  TrackMatch? best;
  for (final pkg in packages) {
    if (!pkg.hasCenterline || pkg.start == null || pkg.finish == null) {
      continue;
    }
    var min = double.infinity;
    for (final p in pkg.centerline) {
      final d = haversineM(here.lat, here.lon, p.lat, p.lon);
      if (d < min) min = d;
    }
    if (min > maxDistanceM) continue;
    if (best == null || min < best.distanceM) {
      best = TrackMatch(package: pkg, distanceM: min);
    }
  }
  return best;
}
