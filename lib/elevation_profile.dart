/// 赛道高差剖面与坡度分析。
///
/// 只吃“有效海拔”的点：调用方须先过滤 altValid=false，本模块不把缺失
/// 海拔补成 0，否则会凭空画出平地与假坡度。
///
/// 气压高度本身有噪声，直接逐点求差会得到 ±数十 % 的假坡度；这里先按
/// 累积距离做固定窗口平滑（默认 25 m，约两个 GPS 采样间隔），再计算坡度。
import 'dart:math' as math;

class ElevationSample {
  const ElevationSample({required this.distanceM, required this.altitudeM});

  /// 沿轨迹的累计距离（米）。
  final double distanceM;

  /// 平滑后的海拔（米）。
  final double altitudeM;
}

class ElevationProfile {
  const ElevationProfile({
    required this.samples,
    required this.minM,
    required this.maxM,
    required this.totalClimbM,
    required this.totalDescentM,
    required this.maxGradePct,
    required this.minGradePct,
    required this.avgGradePct,
  });

  final List<ElevationSample> samples;
  final double minM;
  final double maxM;
  final double totalClimbM;
  final double totalDescentM;

  /// 最大上坡 / 最大下坡坡度（百分比；下坡为负）。
  final double maxGradePct;
  final double minGradePct;

  /// 全程平均坡度（总爬升 - 总下降）/ 总距离。
  final double avgGradePct;

  double get rangeM => samples.isEmpty ? 0 : maxM - minM;

  static const empty = ElevationProfile(
    samples: [],
    minM: 0,
    maxM: 0,
    totalClimbM: 0,
    totalDescentM: 0,
    maxGradePct: 0,
    minGradePct: 0,
    avgGradePct: 0,
  );

  /// [points] 须按时间顺序排列，且已过滤掉无效海拔。
  static ElevationProfile build(
    List<({double lat, double lon, double alt})> points, {
    double smoothingM = 25,
    double minGradeDistanceM = 5,
  }) {
    if (points.length < 2) return empty;

    final dists = <double>[0];
    for (var i = 1; i < points.length; i++) {
      dists.add(
        dists.last +
            _haversineM(
              points[i - 1].lat,
              points[i - 1].lon,
              points[i].lat,
              points[i].lon,
            ),
      );
    }

    // 按累计距离做移动平均（两侧各半个窗口），不引入未来数据太多：
    // 用对称窗口只是为了离线分析曲线更干净，不用于实时控制。
    final half = math.max(smoothingM / 2, 0.0);
    final smoothed = List<double>.filled(points.length, 0);
    var lo = 0;
    var hi = 0;
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < points.length; i++) {
      while (lo < points.length && dists[lo] < dists[i] - half) {
        lo++;
      }
      while (hi < points.length && dists[hi] <= dists[i] + half) {
        hi++;
      }
      sum = 0;
      count = 0;
      for (var k = lo; k < hi; k++) {
        sum += points[k].alt;
        count++;
      }
      smoothed[i] = count == 0 ? points[i].alt : sum / count;
    }

    var minV = smoothed.first;
    var maxV = smoothed.first;
    var climb = 0.0;
    var descent = 0.0;
    var maxGrade = 0.0;
    var minGrade = 0.0;
    for (var i = 1; i < smoothed.length; i++) {
      final dh = smoothed[i] - smoothed[i - 1];
      if (dh > 0) {
        climb += dh;
      } else {
        descent -= dh;
      }
      final dd = dists[i] - dists[i - 1];
      if (dd >= minGradeDistanceM) {
        final grade = dh / dd * 100;
        if (grade > maxGrade) maxGrade = grade;
        if (grade < minGrade) minGrade = grade;
      }
      if (smoothed[i] < minV) minV = smoothed[i];
      if (smoothed[i] > maxV) maxV = smoothed[i];
    }

    final total = dists.last;
    final avgGrade = total > 0 ? (climb - descent) / total * 100 : 0.0;
    return ElevationProfile(
      samples: [
        for (var i = 0; i < smoothed.length; i++)
          ElevationSample(distanceM: dists[i], altitudeM: smoothed[i]),
      ],
      minM: minV,
      maxM: maxV,
      totalClimbM: climb,
      totalDescentM: descent,
      maxGradePct: maxGrade,
      minGradePct: minGrade,
      avgGradePct: avgGrade,
    );
  }
}

double _haversineM(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}
