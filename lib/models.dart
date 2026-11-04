import 'dart:math' as math;

import 'photo_points.dart';

/// 出行模式。阈值与指标按模式分开，绝不混用。
enum TripMode { car, moto, bike }

extension TripModeLabel on TripMode {
  String get label => switch (this) {
        TripMode.car => '汽车',
        TripMode.moto => '摩托',
        TripMode.bike => '骑行',
      };
  String get key => name;
  static TripMode fromKey(String k) =>
      TripMode.values.firstWhere((e) => e.name == k, orElse: () => TripMode.car);
}

/// 模式阈值（g）。骑行不套用汽车急加速那套。
class ModeThresholds {
  final double harshAccel;
  final double harshBrake; // 负值
  final double harshCorner;
  const ModeThresholds(this.harshAccel, this.harshBrake, this.harshCorner);
  static const car = ModeThresholds(0.30, -0.35, 0.40);
  static const moto = ModeThresholds(0.35, -0.40, 0.50);
  static const bike = ModeThresholds(0.20, -0.20, 0.30);
  static ModeThresholds of(TripMode m) => switch (m) {
        TripMode.car => car,
        TripMode.moto => moto,
        TripMode.bike => bike,
      };
}

/// 1Hz 轨迹点。速度单位 m/s，G 单位 g，角度单位度。
class TrackPoint {
  final int timeMs;
  final double lat, lon, alt;
  final double speed, bearing;
  final double hAcc, vAcc, speedAcc;
  final String provider;
  final double longG, latG, vertG; // 车身坐标，标定后才有效
  final double pitch, roll, heading;
  final double pressureHpa;
  final bool calibrated;
  final double? powerW; // null=无传感器；实测与估算由 powerEstimated 区分
  final bool powerEstimated;
  final double? cadenceRpm;
  final int? heartRate;
  final String sensorStatus; // ok / disconnected / none
  final int? satCount; // 参与解算的卫星数，JSON 键 'sat'，无数据为 null
  final String locSource; // 定位来源，JSON 键 'locSrc'，默认 ''
  /// 海拔是否可信，JSON 键 'altOk'。false 表示该点没有海拔来源
  /// （如 NETWORK 定位无海拔、旧版 BleDIY 外接点恒写 0），alt 字段
  /// 此时存的 0 只是占位，绝不是海平面 0 米，画剖面/算爬升时必须排除。
  final bool altValid;
  const TrackPoint({
    required this.timeMs,
    required this.lat,
    required this.lon,
    required this.alt,
    required this.speed,
    required this.bearing,
    required this.hAcc,
    required this.vAcc,
    required this.speedAcc,
    required this.provider,
    required this.longG,
    required this.latG,
    required this.vertG,
    required this.pitch,
    required this.roll,
    required this.heading,
    required this.pressureHpa,
    required this.calibrated,
    this.powerW,
    this.powerEstimated = false,
    this.cadenceRpm,
    this.heartRate,
    this.sensorStatus = 'none',
    this.satCount,
    this.locSource = '',
    this.altValid = true,
  });

  Map<String, dynamic> toJson() => {
        't': timeMs, 'lat': lat, 'lon': lon, 'alt': alt, 'v': speed,
        'brg': bearing, 'hAcc': hAcc, 'vAcc': vAcc, 'sAcc': speedAcc,
        'prov': provider, 'lg': longG, 'tg': latG, 'vg': vertG,
        'pitch': pitch, 'roll': roll, 'hdg': heading, 'hpa': pressureHpa,
        'cal': calibrated, 'pw': powerW, 'pwEst': powerEstimated,
        'cad': cadenceRpm, 'hr': heartRate, 'sen': sensorStatus,
        'sat': satCount, 'locSrc': locSource, 'altOk': altValid,
      };

  static TrackPoint fromJson(Map<String, dynamic> j) => TrackPoint(
        timeMs: (j['t'] as num).toInt(),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        alt: (j['alt'] as num?)?.toDouble() ?? 0,
        speed: (j['v'] as num?)?.toDouble() ?? 0,
        bearing: (j['brg'] as num?)?.toDouble() ?? 0,
        hAcc: (j['hAcc'] as num?)?.toDouble() ?? 999,
        vAcc: (j['vAcc'] as num?)?.toDouble() ?? 999,
        speedAcc: (j['sAcc'] as num?)?.toDouble() ?? 999,
        provider: (j['prov'] as String?) ?? '',
        longG: (j['lg'] as num?)?.toDouble() ?? 0,
        latG: (j['tg'] as num?)?.toDouble() ?? 0,
        vertG: (j['vg'] as num?)?.toDouble() ?? 0,
        pitch: (j['pitch'] as num?)?.toDouble() ?? 0,
        roll: (j['roll'] as num?)?.toDouble() ?? 0,
        heading: (j['hdg'] as num?)?.toDouble() ?? 0,
        pressureHpa: (j['hpa'] as num?)?.toDouble() ?? 0,
        calibrated: (j['cal'] as bool?) ?? false,
        powerW: (j['pw'] as num?)?.toDouble(),
        powerEstimated: (j['pwEst'] as bool?) ?? false,
        cadenceRpm: (j['cad'] as num?)?.toDouble(),
        heartRate: (j['hr'] as num?)?.toInt(),
        sensorStatus: (j['sen'] as String?) ?? 'none',
        satCount: (j['sat'] as num?)?.toInt(),
        locSource: (j['locSrc'] as String?) ?? '',
        // 旧数据无 'altOk' 键时做遗留推断：旧版外接点与 NETWORK 点
        // 的 alt 恒为占位 0，一律判为无效；新数据一律带 'altOk'，
        // 不走这条启发式（沿海真 0 米的新点不会被误杀）。
        altValid: (j['altOk'] as bool?) ??
            !(((j['alt'] as num?)?.toDouble() ?? 0) == 0 &&
                ((j['prov'] as String?) == 'network' ||
                    (j['prov'] as String?) == 'external' ||
                    (j['locSrc'] as String?) == 'external')),
      );

  double get combinedG => math.sqrt(longG * longG + latG * latG);
}

/// 事件：弯 / 急加速 / 急刹车 / 断线（传感器）。
class TripEvent {
  final String kind; // corner / harshAccel / harshBrake / sensorDrop
  final int startMs, endMs;
  final int startIndex, endIndex;
  final double peakLongG, peakLatG;
  final double entrySpeed, minSpeed, exitSpeed;
  final double maxLeanLeft, maxLeanRight, leanAtApex;
  final String note;
  const TripEvent({
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.startIndex,
    required this.endIndex,
    required this.peakLongG,
    required this.peakLatG,
    required this.entrySpeed,
    required this.minSpeed,
    required this.exitSpeed,
    this.maxLeanLeft = 0,
    this.maxLeanRight = 0,
    this.leanAtApex = 0,
    this.note = '',
  });
  String get label => switch (kind) {
        'corner' => '过弯',
        'harshAccel' => '急加速',
        'harshBrake' => '急刹车',
        'sensorDrop' => '传感器断线',
        _ => kind,
      };
  Map<String, dynamic> toJson() => {
        'kind': kind, 's': startMs, 'e': endMs, 'si': startIndex, 'ei': endIndex,
        'plg': peakLongG, 'ptg': peakLatG, 'vIn': entrySpeed,
        'vMin': minSpeed, 'vOut': exitSpeed, 'leanL': maxLeanLeft,
        'leanR': maxLeanRight, 'leanApex': leanAtApex, 'note': note,
      };
  static TripEvent fromJson(Map<String, dynamic> j) => TripEvent(
        kind: j['kind'] as String,
        startMs: (j['s'] as num).toInt(),
        endMs: (j['e'] as num).toInt(),
        startIndex: (j['si'] as num).toInt(),
        endIndex: (j['ei'] as num).toInt(),
        peakLongG: (j['plg'] as num?)?.toDouble() ?? 0,
        peakLatG: (j['ptg'] as num?)?.toDouble() ?? 0,
        entrySpeed: (j['vIn'] as num?)?.toDouble() ?? 0,
        minSpeed: (j['vMin'] as num?)?.toDouble() ?? 0,
        exitSpeed: (j['vOut'] as num?)?.toDouble() ?? 0,
        maxLeanLeft: (j['leanL'] as num?)?.toDouble() ?? 0,
        maxLeanRight: (j['leanR'] as num?)?.toDouble() ?? 0,
        leanAtApex: (j['leanApex'] as num?)?.toDouble() ?? 0,
        note: (j['note'] as String?) ?? '',
      );
}

class Trip {
  final String id;
  final TripMode mode;
  final int startMs, endMs;
  final List<TrackPoint> points;
  final List<TripEvent> events;
  final double score;
  final Map<String, double> subScores;
  final List<String> scoreReasons;
  final bool trimPrivacy; // 默认 true：分享时截掉首尾
  final double riderBikeKg; // 骑行估算功率用
  final String weatherSummary; // 结束时天气一句话（分享卡用）
  // v0.1.2 社交骨架：视频路径、公开标记、本机点赞计数/是否已点赞。
  // 公开仅指本机标记 + 对外分享，不宣称有服务器社区。
  final List<String> videoPaths;
  final bool isPublic;
  final int likes;
  final bool liked;
  // v0.1.3 赛道模式：null/空 = 非赛道行程；lapsJson 为 Lap.toJson() 列表。
  final String? trackId;
  final String trackName;
  final bool isTrackMode;
  final List<Map<String, dynamic>> lapsJson;
  // v0.1.7 沿途照片打点：默认空列表；旧行程 JSON 缺 'photos' 键时
  // fromJson 读空，不破坏旧数据；照片只存本机路径，见 photo_points.dart。
  final List<PhotoPoint> photoPoints;
  // v1.2.0：绑定车辆 id（JSON 键 'vehicleId'）；缺键 = null =
  // 回退全局油耗/油价。排量/车重绝不参与油耗计算（见 vehicle_profile）。
  final String? vehicleId;
  final double? startFinishLat;
  final double? startFinishLon;
  // 高德第一批（纠偏 + 逆地理编码）：派生层单独存，绝不覆盖 points。
  // correctedPoints 为纠偏后轨迹（WGS-84 经纬度对列）；correctionStatus：
  // none=未尝试、pending=进行中、done=已完成、failed=失败、skipped=不适用
  // （骑行/赛道/境外/无 Key 时不纠偏）；startPlace/endPlace 为逆地理
  // 编码的中文短地名（空 = 未获取，界面回落坐标显示）。旧 JSON 缺键时
  // 读默认值，不破坏旧数据。
  final List<(double lat, double lon)> correctedPoints;
  final String correctionStatus;
  final String startPlace;
  final String endPlace;
  const Trip({
    required this.id,
    required this.mode,
    required this.startMs,
    required this.endMs,
    required this.points,
    required this.events,
    required this.score,
    required this.subScores,
    required this.scoreReasons,
    this.trimPrivacy = true,
    this.riderBikeKg = 85,
    this.weatherSummary = '',
    this.videoPaths = const [],
    this.isPublic = false,
    this.likes = 0,
    this.liked = false,
    this.trackId,
    this.trackName = '',
    this.isTrackMode = false,
    this.lapsJson = const [],
    this.photoPoints = const [],
    this.vehicleId,
    this.startFinishLat,
    this.startFinishLon,
    this.correctedPoints = const [],
    this.correctionStatus = 'none',
    this.startPlace = '',
    this.endPlace = '',
  });

  double get distanceM {
    var d = 0.0;
    for (var i = 1; i < points.length; i++) {
      d += haversineM(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
    }
    return d;
  }

  double get maxSpeed => points.isEmpty ? 0 : points.map((p) => p.speed).reduce(math.max);
  double get maxG => points.isEmpty ? 0 : points.map((p) => p.combinedG).reduce(math.max);
  double get maxLean {
    var m = 0.0;
    for (final p in points) {
      m = math.max(m, p.roll.abs());
    }
    return m;
  }

  /// 累计爬升（去噪口径，v0.1.7 起取代原始逐点正差求和）：
  /// 只取 altValid 点，先 5 点滑动平均平滑，再按阈值分段累计
  /// （见 thresholdClimbM）。旧口径会把 GPS 垂直抖动与“手机 GPS
  /// 有海拔 → 旧外接点占位 0 → 手机 GPS”的人为跳变全算成爬升。
  double get climbM {
    final valid = points.where((p) => p.altValid).map((p) => p.alt).toList();
    return thresholdClimbM(smoothAltitudes(valid));
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'mode': mode.name, 'start': startMs, 'end': endMs,
        'score': score, 'sub': subScores, 'reasons': scoreReasons,
        'trim': trimPrivacy, 'kg': riderBikeKg, 'weather': weatherSummary,
        'videos': videoPaths, 'pub': isPublic, 'likes': likes, 'liked': liked,
        'trackId': trackId, 'trackName': trackName, 'trackMode': isTrackMode,
        'laps': lapsJson, 'photos': photoPoints.map((p) => p.toJson()).toList(),
        'vehicleId': vehicleId,
        'sfLat': startFinishLat, 'sfLon': startFinishLon,
        'corrPts': correctedPoints.map((p) => [p.$1, p.$2]).toList(),
        'corrStatus': correctionStatus,
        'startPlace': startPlace, 'endPlace': endPlace,
        'points': points.map((p) => p.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
      };
  static Trip fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        mode: TripModeLabel.fromKey(j['mode'] as String),
        startMs: (j['start'] as num).toInt(),
        endMs: (j['end'] as num).toInt(),
        score: (j['score'] as num?)?.toDouble() ?? 0,
        subScores: ((j['sub'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
        scoreReasons: ((j['reasons'] as List?) ?? []).map((e) => e.toString()).toList(),
        trimPrivacy: (j['trim'] as bool?) ?? true,
        riderBikeKg: (j['kg'] as num?)?.toDouble() ?? 85,
        weatherSummary: (j['weather'] as String?) ?? '',
        videoPaths: ((j['videos'] as List?) ?? []).map((e) => e.toString()).toList(),
        trackId: j['trackId'] as String?,
        trackName: (j['trackName'] as String?) ?? '',
        isTrackMode: (j['trackMode'] as bool?) ?? false,
        lapsJson: ((j['laps'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        photoPoints: ((j['photos'] as List?) ?? []).map((e) => PhotoPoint.fromJson(e as Map<String, dynamic>)).toList(),
        vehicleId: j['vehicleId'] as String?,
        startFinishLat: (j['sfLat'] as num?)?.toDouble(),
        startFinishLon: (j['sfLon'] as num?)?.toDouble(),
        correctedPoints: ((j['corrPts'] as List?) ?? []).map((e) {
          final pair = e as List;
          return ((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
        }).toList(),
        correctionStatus: (j['corrStatus'] as String?) ?? 'none',
        startPlace: (j['startPlace'] as String?) ?? '',
        endPlace: (j['endPlace'] as String?) ?? '',
        isPublic: (j['pub'] as bool?) ?? false,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        liked: (j['liked'] as bool?) ?? false,
        points: ((j['points'] as List?) ?? []).map((e) => TrackPoint.fromJson(e as Map<String, dynamic>)).toList(),
        events: ((j['events'] as List?) ?? []).map((e) => TripEvent.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

double _rad(double d) => d * math.pi / 180;

/// 海拔平滑：居中 5 点滑动平均（1Hz 采样 ≈ 5 秒窗口），边缘窗口
/// 缩小。只压单点毛刺，不改变趋势；剖面图与爬升共用同一序列，
/// 图上峰值与统计数字一致。调用方须先过滤掉 altValid=false 的点。
List<double> smoothAltitudes(List<double> values, {int window = 5}) {
  if (values.length < 2) return List<double>.from(values);
  final half = window ~/ 2;
  final out = <double>[];
  for (var i = 0; i < values.length; i++) {
    var sum = 0.0;
    var n = 0;
    for (var k = i - half; k <= i + half; k++) {
      if (k >= 0 && k < values.length) {
        sum += values[k];
        n++;
      }
    }
    out.add(sum / n);
  }
  return out;
}

/// 阈值累计爬升：把平滑序列切成上升段 / 下降段，只累计总上升量
/// ≥ [thresholdM] 的上升段；不足阈值的起伏视为 GPS 抖动丢弃。
/// 阈值 3.0 米：消费级 GPS 垂直误差常在数米量级，平路 1Hz 抖动
/// 的单段起伏多在 3 米内；代价是真实小起伏（< 3 米的坡）也会被
/// 丢弃，累计值是保守下限，不是精确爬升。下降段不计入、不抵扣。
double thresholdClimbM(List<double> smoothed, {double thresholdM = 3.0}) {
  if (smoothed.length < 2) return 0;
  var climb = 0.0;
  var runStart = smoothed[0];
  var runPeak = smoothed[0];
  var rising = false;
  for (var i = 1; i < smoothed.length; i++) {
    final v = smoothed[i];
    if (v > smoothed[i - 1]) {
      if (!rising) {
        runStart = smoothed[i - 1];
        runPeak = v;
        rising = true;
      } else if (v > runPeak) {
        runPeak = v;
      }
    } else if (v < smoothed[i - 1] && rising) {
      if (runPeak - runStart >= thresholdM) climb += runPeak - runStart;
      rising = false;
    }
  }
  if (rising && runPeak - runStart >= thresholdM) climb += runPeak - runStart;
  return climb;
}

/// 骑行估算功率（明确标注“估算”，不是实测）。
/// 模型：空气阻力 + 滚动阻力 + 坡度做功，除以传动效率。
double estimatePowerW(double speedMs, double slope, double massKg) {
  const rho = 1.225, cdA = 0.32, crr = 0.004, g = 9.81;
  final v = speedMs;
  final p = 0.5 * rho * cdA * v * v * v + crr * massKg * g * v + massKg * g * v * slope;
  return (p / 0.97).clamp(0, 2000).toDouble();
}
