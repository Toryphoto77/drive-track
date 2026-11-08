import 'dart:math' as math;

import 'models.dart';

/// 街道模式实时贴路（v1.5.3 攒版）：把定位点贴到行进方向一致的
/// 最近道路上，避免双向路中间有隔离带时轨迹飘到对向车道。
///
/// 诚实规则：无路网 / 无可用路段 / 投影距离超限时原样返回，
/// 绝不编一个假位置；贴路只改经纬度，不改速度、航向与时间戳。

/// 贴路最大距离（米）：超出则认为不在路上，不贴。
const double maxSnapDistanceM = 30;

/// 路段方向与行进方向的最大夹角（度）：超出则不贴——双向路的
/// 对向车道方向差约 180°，第一遍一定会被排除。
const double maxSnapHeadingDiffDeg = 45;

/// 路网缓存有效半径（米）/ 有效期：移出范围或过期才重拉。
const double roadCacheRadiusM = 300;
const int roadCacheTtlMs = 120000;

double _angleDiffDeg(double a, double b) {
  var d = (a - b).abs() % 360;
  if (d > 180) d = 360 - d;
  return d;
}

double _segmentBearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = (lon2 - lon1) * math.pi / 180;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final y = math.sin(dLon) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// 把一点贴到给定路网中与 [headingDeg] 同向的最近路段上。
/// 两遍挑路：第一遍只认方向差 ≤45° 的路段（双向路对向车道
/// 方向差约 180°，直接排除）；第一遍无可用路段时，第二遍按
/// 路段直线方向认路（方向差 ≤45° 或 ≥135°），覆盖单线双向路
/// 的节点顺序与行进方向相反的情况。两遍都无可用路段、或投影
/// 距离超 [maxSnapM] 时原样返回。
({double lat, double lon}) snapToRoad({
  required double lat,
  required double lon,
  required double headingDeg,
  required List<List<(double, double)>> ways,
  double maxSnapM = maxSnapDistanceM,
  double maxHeadingDiffDeg = maxSnapHeadingDiffDeg,
}) {
  ({double lat, double lon})? pick(bool Function(double diff) accept) {
    var bestLat = lat;
    var bestLon = lon;
    var bestD = double.infinity;
    for (final way in ways) {
      for (var i = 0; i < way.length - 1; i++) {
        final a = way[i];
        final b = way[i + 1];
        final segBrg = _segmentBearing(a.$1, a.$2, b.$1, b.$2);
        if (!accept(_angleDiffDeg(segBrg, headingDeg))) continue;
        // 等距圆柱近似投影（街道尺度下足够，与 tunnel_gap 一致）。
        final dx = (b.$2 - a.$2) * math.cos(a.$1 * math.pi / 180);
        final dy = b.$1 - a.$1;
        final px = (lon - a.$2) * math.cos(a.$1 * math.pi / 180);
        final py = lat - a.$1;
        final len2 = dx * dx + dy * dy;
        final t =
            len2 <= 0 ? 0.0 : ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
        final candLat = a.$1 + dy * t;
        final candLon = a.$2 + (dx * t) / math.cos(a.$1 * math.pi / 180);
        final d = haversineM(lat, lon, candLat, candLon);
        if (d < bestD) {
          bestD = d;
          bestLat = candLat;
          bestLon = candLon;
        }
      }
    }
    if (bestD <= maxSnapM) return (lat: bestLat, lon: bestLon);
    return null;
  }

  return pick((diff) => diff <= maxHeadingDiffDeg) ??
      pick((diff) => diff <= maxHeadingDiffDeg || diff >= 180 - maxHeadingDiffDeg) ??
      (lat: lat, lon: lon);
}

/// 路网缓存 + 贴路入口：缓存按中心点 300 米 / 120 秒失效；
/// 取数失败不抛错，只沿用旧缓存、无缓存时不贴。
class RoadSnapper {
  List<List<(double, double)>> _ways = const [];
  double? _cacheLat, _cacheLon;
  int _fetchedAtMs = 0;
  bool _fetching = false;

  bool get hasRoads => _ways.isNotEmpty;

  /// 测试注入路网（跳过网络）。仅供测试经 Recorder.setRoadWaysForTest 调用。
  void setWaysForTest(List<List<(double, double)>> ways,
      {double lat = 0, double lon = 0}) {
    _ways = ways;
    _cacheLat = lat;
    _cacheLon = lon;
    _fetchedAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// 缓存失效时拉一次路网（调用方注入 fetcher；未注入 = 无路网）。
  /// 进行中重复调用直接返回，不并发；失败沿用旧缓存。
  Future<void> refreshIfNeeded(
    double lat,
    double lon,
    Future<List<List<(double, double)>>?> Function(double, double)? fetcher,
  ) async {
    if (fetcher == null || _fetching) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cacheLat != null &&
        now - _fetchedAtMs < roadCacheTtlMs &&
        haversineM(lat, lon, _cacheLat!, _cacheLon!) < roadCacheRadiusM) {
      return;
    }
    _fetching = true;
    try {
      final ways = await fetcher(lat, lon);
      if (ways != null && ways.isNotEmpty) {
        _ways = ways;
        _cacheLat = lat;
        _cacheLon = lon;
        _fetchedAtMs = now;
      }
    } catch (_) {
      // 取数失败：沿用旧缓存，不贴坏轨迹。
    } finally {
      _fetching = false;
    }
  }

  /// 用缓存路网贴路；无缓存时原样返回。
  ({double lat, double lon}) snap(double lat, double lon, double headingDeg) {
    if (_ways.isEmpty) return (lat: lat, lon: lon);
    return snapToRoad(
        lat: lat, lon: lon, headingDeg: headingDeg, ways: _ways);
  }

  void reset() {
    _ways = const [];
    _cacheLat = null;
    _cacheLon = null;
    _fetchedAtMs = 0;
  }
}
