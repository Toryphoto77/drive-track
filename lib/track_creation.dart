import 'blediy_gps.dart';
import 'models.dart';
import 'track_library.dart';
import 'track_timing.dart';

export 'track_timing.dart' show GeoPoint;

enum CustomTrackMethod { measured, satellite }

/// 现场实测只接受三秒内、坐标有效且 GSA 明确为 3D 的外接定位。
bool external3DFixReady(ExternalGpsFix? fix, int lastFixAtMs, {int? nowMs}) {
  if (fix == null || fix.fixMode != 3 || fix.fixQuality == 0) return false;
  if (!fix.lat.isFinite ||
      !fix.lon.isFinite ||
      fix.lat.abs() > 90 ||
      fix.lon.abs() > 180) {
    return false;
  }
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final age = now - lastFixAtMs;
  return lastFixAtMs > 0 && age >= 0 && age <= 3000;
}

/// 卡丁车开录前使用的赛道完整性门槛。
String? kartTrackProblem(TrackPackage? package) {
  if (package == null) return '请先选择卡丁车赛道';
  if (!package.hasCenterline) return '当前赛道缺少有效中心线';
  if (package.start == null || package.finish == null) {
    return '当前赛道缺少起点或终点，请先编辑补全';
  }
  return null;
}

List<GeoPoint> _geoPoints(List<TrackPoint> points) =>
    points.map((p) => GeoPoint(p.lat, p.lon)).toList();

/// 实测草稿需至少 30 点、100 米，并回到起点 100 米范围内。
String? measuredTrackProblem(List<TrackPoint> points) {
  if (points.length < 30) return '实测点不足 30 个，请继续沿赛道行驶';
  final geo = _geoPoints(points);
  if (polylineLengthM(geo) < 100) return '实测轨迹不足 100 米，请完成整圈';
  if (polylineLengthM([geo.first, geo.last]) > 100) {
    return '起点与终点相距超过 100 米，请回到起点附近再完成';
  }
  return null;
}

/// 复用行程导入的中心线简化逻辑，再明确闭合现场实测草稿。
TrackPackage measuredTrackPackage({
  required String id,
  required String name,
  required List<TrackPoint> points,
}) {
  final problem = measuredTrackProblem(points);
  if (problem != null) throw ArgumentError(problem);
  final startMs = points.first.timeMs;
  final trip = Trip(
    id: id,
    mode: TripMode.kart,
    startMs: startMs,
    endMs: points.last.timeMs,
    points: points,
    events: const [],
    score: 0,
    subScores: const {},
    scoreReasons: const [],
    trackName: name,
    isTrackMode: true,
  );
  final built = packageFromTrip(trip, name: name.trim())!;
  final centerline = List<GeoPoint>.of(built.centerline);
  final first = centerline.first;
  if (centerline.last.lat == first.lat && centerline.last.lon == first.lon) {
    centerline[centerline.length - 1] = first;
  } else {
    centerline.add(first);
  }
  return built.copyWith(
    id: id,
    nameCn: name.trim(),
    source: TrackPackageSource.measured,
    sourceDetail: '现场外接 GNSS 3D 定位实测',
    verification: TrackPackageVerification.pending,
    verificationNote: '中心线与起终点来自现场实测；分段点请在编辑器中补录',
    centerline: centerline,
    lengthM: polylineLengthM(centerline).round(),
    start: first,
    finish: first,
    startNote: '现场实测轨迹首点，完成整圈后闭合',
    userModified: true,
    isUserTrack: true,
  );
}

/// 手动绘制只创建空草稿；定位锚点仅用于初始视口，不伪造赛道点。
TrackPackage emptyTrackPackageAt({
  required String id,
  required String name,
  required GeoPoint anchor,
}) {
  return TrackPackage(
    id: id,
    nameCn: name.trim(),
    nameEn: '',
    region: '',
    version: 1,
    source: TrackPackageSource.user,
    sourceDetail: '用户基于 Esri 卫星图手动绘制；初始中心来自当前定位',
    verification: TrackPackageVerification.pending,
    verificationNote: '用户手动绘制，中心线、起终点与分段待核对',
    userModified: true,
    isUserTrack: true,
  );
}
