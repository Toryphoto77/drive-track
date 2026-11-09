import 'models.dart';

/// 隐私截首尾的默认距离（米），与分享 / GPX 导出同一口径。
const double kPrivacyTrimM = 400;

/// 截首尾的结果：保留区间 [start, end]（含），[ok]=false 表示轨迹太短，
/// 截不出足够的中段（调用方自行决定回落策略）。
class TrimRange {
  final int start;
  final int end;
  final bool ok;
  const TrimRange(this.start, this.end, this.ok);
}

/// 按累计里程截掉首尾各 [trimM] 米（纯函数）。
TrimRange privacyTrimRange(List<TrackPoint> points, {double trimM = kPrivacyTrimM}) {
  if (points.length < 10) return TrimRange(0, points.length - 1, false);
  var total = 0.0;
  final dists = <double>[0];
  for (var i = 1; i < points.length; i++) {
    total += haversineM(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
    dists.add(total);
  }
  var s = 0, e = points.length - 1;
  while (s < dists.length && dists[s] < trimM) {
    s++;
  }
  while (e > 0 && total - dists[e] < trimM) {
    e--;
  }
  if (e - s < 10) return TrimRange(0, points.length - 1, false);
  return TrimRange(s, e, true);
}

/// 公开发布用的行程副本（上传到公开读的 public-files 桶前必须经过这里）。
///
/// - 一律去掉本机路径：视频路径清空，照片点只留坐标 / 时间 / 备注，
///   不带手机里的文件路径；
/// - 行程开了隐私截首尾（[Trip.trimPrivacy]，默认开）时：轨迹点截掉首尾
///   各 400 米；轨迹太短截不出中段时不公开任何轨迹点（宁缺勿露起终点）；
///   同时丢掉保留区间外的照片点 / 事件 / OBD 采样，事件下标重新对齐，
///   起终点地名清空，纠偏轨迹（无时间戳、无法按区间截）不公开；
/// - 用户关掉截首尾时尊重其选择，只做路径清理。
///
/// 私有备份（trip-files 私有桶）仍上传完整行程，不经过本函数。
Trip publicTripCopy(Trip trip, {double trimM = kPrivacyTrimM}) {
  final photos = trip.photoPoints
      .map((p) => p.copyWith(type: p.effectiveType, clearPhoto: true))
      .toList();
  var out = trip.copyWith(videoPaths: const [], photoPoints: photos);
  if (!trip.trimPrivacy) return out;

  final r = privacyTrimRange(trip.points, trimM: trimM);
  if (!r.ok) {
    return out.copyWith(
      points: const [],
      events: const [],
      photoPoints: const [],
      obdSamples: const [],
      correctedPoints: const [],
      correctionStatus: 'none',
      startPlace: '',
      endPlace: '',
    );
  }
  final kept = trip.points.sublist(r.start, r.end + 1);
  final t0 = kept.first.timeMs, t1 = kept.last.timeMs;
  bool inWindow(int t) => t >= t0 && t <= t1;
  // 事件下标基于实测点列表（saveTrip 里 detectEvents(measured)）：
  // 按时间窗筛选，再减去被截掉的前段实测点数重新对齐。
  final measuredBefore =
      trip.points.sublist(0, r.start).where((p) => !p.estimated).length;
  final measuredKept = kept.where((p) => !p.estimated).length;
  final events = <TripEvent>[];
  for (final e in trip.events) {
    if (!inWindow(e.startMs) || !inWindow(e.endMs)) continue;
    final si = e.startIndex - measuredBefore, ei = e.endIndex - measuredBefore;
    if (si < 0 || ei >= measuredKept || ei < si) continue;
    events.add(TripEvent.fromJson({...e.toJson(), 'si': si, 'ei': ei}));
  }
  return out.copyWith(
    points: kept,
    events: events,
    photoPoints: photos.where((p) => inWindow(p.timeMs)).toList(),
    obdSamples: trip.obdSamples.where((m) {
      final t = (m['t'] as num?)?.toInt();
      return t != null && inWindow(t);
    }).toList(),
    correctedPoints: const [],
    correctionStatus: 'none',
    startPlace: '',
    endPlace: '',
  );
}
