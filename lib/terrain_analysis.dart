/// 赛道地形分析：弯段坡度与可分享的地形摘要。
///
/// 只看实测有效海拔：入弯或出弯端点没有可信海拔时直接跳过该弯，
/// 不把 0 米占位值当成海平面算坡度。弯段距离用轨迹点实际累计距离，
/// 不用赛道目录里的长度，保证和剖面横轴同一口径。
import 'dart:math' as math;

import 'corner_analysis.dart';
import 'elevation_profile.dart';
import 'models.dart';

/// 单个弯段的坡度：正值为上坡，负值为下坡。
class CornerGrade {
  const CornerGrade({
    required this.cornerIndex,
    required this.gradePct,
    required this.altChangeM,
    required this.distanceM,
  });

  /// 从 1 开始的弯序（与弯角分析一致）。
  final int cornerIndex;
  final double gradePct;
  final double altChangeM;
  final double distanceM;
}

/// 少于这个长度的弯段不算坡度：距离太短时海拔噪声会被放大成几十 %。
const double _kMinCornerGradeDistanceM = 5;

/// 逐个弯段计算平均坡度。缺有效海拔的弯不返回，界面据此显示“—”或不显示。
List<CornerGrade> buildCornerGrades(
  List<TrackPoint> points,
  List<CornerAnalysis> corners,
) {
  if (points.length < 2 || corners.isEmpty) return const [];

  final dists = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    dists[i] =
        dists[i - 1] +
        _haversineM(
          points[i - 1].lat,
          points[i - 1].lon,
          points[i].lat,
          points[i].lon,
        );
  }

  final out = <CornerGrade>[];
  for (final corner in corners) {
    final a = corner.entryIndex;
    final b = corner.exitIndex;
    if (a < 0 || b >= points.length || b <= a) continue;
    final distance = dists[b] - dists[a];
    if (distance < _kMinCornerGradeDistanceM) continue;
    final start = points[a];
    final end = points[b];
    if (!start.altValid || !end.altValid) continue;
    final altChange = end.alt - start.alt;
    out.add(
      CornerGrade(
        cornerIndex: corner.index,
        gradePct: altChange / distance * 100,
        altChangeM: altChange,
        distanceM: distance,
      ),
    );
  }
  out.sort((x, y) => x.cornerIndex.compareTo(y.cornerIndex));
  return out;
}

/// 可复制的赛道地形摘要：只写实测高差、爬升、坡度与逐弯坡度。
/// [title] 为赛道或行程名；不含坐标与账号信息，可直接分享。
String terrainShareText({
  required String title,
  required ElevationProfile profile,
  required List<CornerGrade> corners,
}) {
  final buffer = StringBuffer()
    ..writeln('赛道地形 · $title')
    ..writeln(
      '高差 ${profile.rangeM.toStringAsFixed(0)} m · '
      '累计爬升 ${profile.totalClimbM.toStringAsFixed(0)} m · '
      '累计下降 ${profile.totalDescentM.toStringAsFixed(0)} m',
    )
    ..writeln(
      '最大上坡 ${_signed(profile.maxGradePct)} · '
      '最大下坡 ${_signed(profile.minGradePct)} · '
      '平均坡度 ${_signed(profile.avgGradePct)}',
    );
  if (corners.isNotEmpty) {
    buffer.writeln(
      '弯段坡度：${corners.map((c) => '弯 ${c.cornerIndex} ${_signed(c.gradePct)}').join(' · ')}',
    );
  }
  buffer.write('来自来驰迹 DriveTrack · 本机实测数据');
  return buffer.toString();
}

String _signed(double pct) =>
    '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';

double _haversineM(double lat1, double lon1, double lat2, double lon2) {
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
