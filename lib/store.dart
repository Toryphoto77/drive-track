import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'models.dart';
import 'logic.dart';
import 'native.dart';
import 'photo_points.dart';

class TripMeta {
  final String id;
  final TripMode mode;
  final int startMs, endMs;
  final double distanceM, score;
  final bool demo;
  final bool isPublic;
  final int likes;
  const TripMeta(this.id, this.mode, this.startMs, this.endMs, this.distanceM, this.score, this.demo, [this.isPublic = false, this.likes = 0]);
  Map<String, dynamic> toJson() => {
        'id': id, 'mode': mode.name, 'start': startMs, 'end': endMs,
        'dist': distanceM, 'score': score, 'demo': demo, 'pub': isPublic, 'likes': likes,
      };
  static TripMeta fromJson(Map<String, dynamic> j) => TripMeta(
        j['id'] as String,
        TripModeLabel.fromKey(j['mode'] as String),
        (j['start'] as num).toInt(),
        (j['end'] as num).toInt(),
        (j['dist'] as num?)?.toDouble() ?? 0,
        (j['score'] as num?)?.toDouble() ?? 0,
        (j['demo'] as bool?) ?? false,
        (j['pub'] as bool?) ?? false,
        (j['likes'] as num?)?.toInt() ?? 0,
      );
}

class Store {
  String _dir = '';
  Future<void> init() async {
    _dir = await Native.getFilesDir();
  }

  String get dir => _dir;
  Future<String> cacheDir() => Native.getCacheDir();

  Future<List<TripMeta>> loadIndex() async {
    try {
      final f = File('$_dir/trips_index.json');
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => TripMeta.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndex(List<TripMeta> metas) async {
    await File('$_dir/trips_index.json')
        .writeAsString(jsonEncode(metas.map((m) => m.toJson()).toList()));
  }

  Future<Trip?> loadTrip(String id) async {
    try {
      final f = File('$_dir/trip_$id.json');
      if (!await f.exists()) return null;
      return Trip.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<Trip> saveTrip(TripMode mode, int startMs, int endMs, List<TrackPoint> points,
      {bool demo = false, double riderKg = 85, bool trim = true, String weatherSummary = '', List<String> videoPaths = const [],
      String? trackId, String trackName = '', bool isTrackMode = false, List<Map<String, dynamic>> lapsJson = const [],
      List<PhotoPoint> photoPoints = const [],
      double? startFinishLat, double? startFinishLon}) async {
    final events = detectEvents(points, mode);
    final sc = isTrackMode
        ? ScoreResult(0, {'圈速稳定性': 0.0}, ['赛道模式不评分，看圈速与稳定性'])
        : scoreTrip(mode, points, events);
    final id = '${demo ? 'demo-' : ''}${DateTime.now().millisecondsSinceEpoch}';
    final trip = Trip(
      id: id, mode: mode, startMs: startMs, endMs: endMs, points: points,
      events: events, score: sc.total, subScores: sc.sub, scoreReasons: sc.reasons,
      trimPrivacy: trim, riderBikeKg: riderKg, weatherSummary: weatherSummary,
      videoPaths: videoPaths, trackId: trackId, trackName: trackName,
      isTrackMode: isTrackMode, lapsJson: lapsJson,
      photoPoints: photoPoints,
      startFinishLat: startFinishLat, startFinishLon: startFinishLon,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    final metas = await loadIndex();
    metas.insert(0, TripMeta(id, mode, startMs, endMs, trip.distanceM, sc.total, demo));
    await _saveIndex(metas);
    return trip;
  }

  /// 改写行程的公开/点赞字段（本机 JSON，不走服务器）。
  Future<Trip?> updateTripSocial(String id, {bool? isPublic, bool? toggleLike}) async {
    final old = await loadTrip(id);
    if (old == null) return null;
    var likes = old.likes;
    var liked = old.liked;
    if (toggleLike == true) {
      liked = !liked;
      likes = (likes + (liked ? 1 : -1)).clamp(0, 1000000);
    }
    final trip = Trip(
      id: old.id, mode: old.mode, startMs: old.startMs, endMs: old.endMs,
      points: old.points, events: old.events, score: old.score,
      subScores: old.subScores, scoreReasons: old.scoreReasons,
      trimPrivacy: old.trimPrivacy, riderBikeKg: old.riderBikeKg,
      weatherSummary: old.weatherSummary, videoPaths: old.videoPaths,
      trackId: old.trackId, trackName: old.trackName, isTrackMode: old.isTrackMode,
      lapsJson: old.lapsJson, startFinishLat: old.startFinishLat, startFinishLon: old.startFinishLon,
      photoPoints: old.photoPoints,
      isPublic: isPublic ?? old.isPublic, likes: likes, liked: liked,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    final metas = await loadIndex();
    final idx = metas.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      metas[idx] = TripMeta(id, trip.mode, trip.startMs, trip.endMs, trip.distanceM, trip.score, metas[idx].demo, trip.isPublic, trip.likes);
      await _saveIndex(metas);
    }
    return trip;
  }

  /// v0.1.7 照片打点：改写行程的 photoPoints（相册附照片 / 改备注 /
  /// 删点后调用方经此落盘）。只换 photoPoints，其余字段原样保留；
  /// 换图 / 删点时旧副本由调用方（相册页）按守卫删除，本方法不猜路径。
  Future<Trip?> updateTripPhotoPoints(String id, List<PhotoPoint> photoPoints) async {
    final old = await loadTrip(id);
    if (old == null) return null;
    final trip = Trip(
      id: old.id, mode: old.mode, startMs: old.startMs, endMs: old.endMs,
      points: old.points, events: old.events, score: old.score,
      subScores: old.subScores, scoreReasons: old.scoreReasons,
      trimPrivacy: old.trimPrivacy, riderBikeKg: old.riderBikeKg,
      weatherSummary: old.weatherSummary, videoPaths: old.videoPaths,
      trackId: old.trackId, trackName: old.trackName, isTrackMode: old.isTrackMode,
      lapsJson: old.lapsJson, startFinishLat: old.startFinishLat, startFinishLon: old.startFinishLon,
      photoPoints: photoPoints,
      isPublic: old.isPublic, likes: old.likes, liked: old.liked,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    return trip;
  }

  /// v0.1.7 删行程：删行程 JSON + 索引条目，并删该行程照片点的
  /// 本 App 副本。只删 photo_points/ 目录下的路径（守卫见
  /// photo_points.dart），用户相册原图、头像、视频一律不动。
  /// 注意：此前 App 内没有删除行程入口，本方法为删行程行为预留的
  /// 唯一钩子，调用方接删除 UI 时必须走它，不得只删 JSON。
  Future<void> deleteTrip(String id) async {
    final old = await loadTrip(id);
    try {
      final f = File('$_dir/trip_$id.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    final metas = await loadIndex();
    metas.removeWhere((m) => m.id == id);
    await _saveIndex(metas);
    if (old == null) return;
    for (final p in old.photoPoints) {
      await deleteManagedPhotoCopy(p.photoPath, _dir);
    }
  }

  /// 收藏是用户本机的一组行程 id（favorites.json），不混进行程文件。
  Future<Set<String>> loadFavorites() async {
    try {
      final f = File('$_dir/favorites.json');
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> toggleFavorite(String id) async {
    final fav = await loadFavorites();
    if (fav.contains(id)) {
      fav.remove(id);
    } else {
      fav.add(id);
    }
    await File('$_dir/favorites.json').writeAsString(jsonEncode(fav.toList()));
    return fav;
  }

  /// 分享时默认截掉首尾各约 400 米（按累计里程切），不显示具体家庭地址。
  List<TrackPoint> trimmedPoints(Trip trip) {
    if (!trip.trimPrivacy || trip.points.length < 10) return trip.points;
    var total = 0.0;
    final dists = <double>[0];
    for (var i = 1; i < trip.points.length; i++) {
      total += haversineM(trip.points[i - 1].lat, trip.points[i - 1].lon, trip.points[i].lat, trip.points[i].lon);
      dists.add(total);
    }
    var s = 0, e = trip.points.length - 1;
    while (s < dists.length && dists[s] < 400) {
      s++;
    }
    while (e > 0 && total - dists[e] < 400) {
      e--;
    }
    if (e - s < 10) return trip.points;
    return trip.points.sublist(s, e + 1);
  }

  String toGpx(Trip trip, {bool trimmed = true}) {
    final pts = trimmed ? trimmedPoints(trip) : trip.points;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="DriveTrack" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('<trk><name>${trip.mode.label} ${DateTime.fromMillisecondsSinceEpoch(trip.startMs)}</name><trkseg>');
    for (final p in pts) {
      // v0.1.7：无海拔点不写 <ele>，不把占位 0 导出成海平面数据。
      final ele = p.altValid ? '<ele>${p.alt.toStringAsFixed(1)}</ele>' : '';
      b.writeln('<trkpt lat="${p.lat}" lon="${p.lon}">$ele'
          '<time>${DateTime.fromMillisecondsSinceEpoch(p.timeMs).toUtc().toIso8601String()}</time></trkpt>');
    }
    b.writeln('</trkseg></trk></gpx>');
    return b.toString();
  }

  String toCsv(Trip trip, {bool trimmed = false}) {
    final pts = trimmed ? trimmedPoints(trip) : trip.points;
    final b = StringBuffer()
      ..writeln('time,lat,lon,alt_m,speed_kmh,bearing,hAcc_m,longG,latG,pitch_deg,roll_deg,powerW,powerEstimated,cadenceRpm,heartRate,sensorStatus');
    for (final p in pts) {
      b.writeln('${DateTime.fromMillisecondsSinceEpoch(p.timeMs).toIso8601String()},${p.lat},${p.lon},'
          '${p.alt.toStringAsFixed(1)},${(p.speed * 3.6).toStringAsFixed(1)},${p.bearing.toStringAsFixed(0)},'
          '${p.hAcc.toStringAsFixed(1)},${p.longG.toStringAsFixed(3)},${p.latG.toStringAsFixed(3)},'
          '${p.pitch.toStringAsFixed(1)},${p.roll.toStringAsFixed(1)},${p.powerW ?? ''},${p.powerEstimated},'
          '${p.cadenceRpm ?? ''},${p.heartRate ?? ''},${p.sensorStatus}');
    }
    return b.toString();
  }

  /// 演示行程：合成数据，仅用于无实测时体验界面，列表里明确标“演示”。
  Future<Trip> makeDemo(TripMode mode) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pts = <TrackPoint>[];
    var lat = 31.2304, lon = 121.4737, heading = 0.0;
    for (var i = 0; i < 240; i++) {
      // 一段带弯的路线：前直后弯再直，中间安排一次急刹
      if (i > 80 && i < 130) heading += 1.6;
      if (i > 170 && i < 210) heading -= 1.2;
      var speed = 14.0;
      if (i > 80 && i < 130) speed = 9.0;
      if (i == 150) speed = 4.0; // 急刹点附近
      if (i > 150 && i < 160) speed = 6.0;
      var longG = 0.0, latG = 0.0, roll = 0.0;
      if (i == 150) longG = -0.55;
      if (i > 80 && i < 130) {
        latG = 0.48;
        roll = mode == TripMode.moto ? 28 : 4;
      }
      if (mode == TripMode.bike) {
        speed = 7.0;
        latG = 0.1;
        roll = 0;
      }
      final br = heading * math.pi / 180;
      lat += math.cos(br) * speed / 111320;
      lon += math.sin(br) * speed / (111320 * math.cos(lat * math.pi / 180));
      pts.add(TrackPoint(
        timeMs: now - (240 - i) * 1000,
        lat: lat, lon: lon, alt: 10 + math.sin(i / 20) * 3, speed: speed,
        bearing: heading % 360, hAcc: 5, vAcc: 8, speedAcc: 0.5,
        provider: 'gps', longG: longG, latG: latG, vertG: 0,
        pitch: 0, roll: roll, heading: heading % 360, pressureHpa: 1013,
        calibrated: true,
        powerW: mode == TripMode.bike ? 150 + math.sin(i / 10) * 30 : null,
        powerEstimated: mode == TripMode.bike,
        cadenceRpm: mode == TripMode.bike ? 85.0 : null,
        sensorStatus: mode == TripMode.bike ? 'estimated' : 'none',
      ));
    }
    return saveTrip(mode, pts.first.timeMs, pts.last.timeMs, pts, demo: true);
  }
}

// ---------- 天气（Open-Meteo，无需 key） ----------
class WeatherInfo {
  final double temp, windSpeed, windDir, visibility;
  final int code;
  final double precipProb;
  final String summary;
  const WeatherInfo(this.temp, this.windSpeed, this.windDir, this.visibility, this.code, this.precipProb, this.summary);
  static String codeText(int c) {
    if (c == 0) return '晴';
    if (c == 1 || c == 2) return '多云';
    if (c == 3) return '阴';
    if (c == 45 || c == 48) return '雾';
    if (c >= 51 && c <= 67) return '雨';
    if (c >= 71 && c <= 77) return '雪';
    if (c >= 80 && c <= 82) return '阵雨';
    if (c >= 95) return '雷阵雨';
    return '未知';
  }

  String get alert {
    if (code >= 71 && code <= 77) return '降雪预警';
    if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return '降雨预警';
    if (code == 45 || code == 48) return '大雾预警';
    if (windSpeed >= 50) return '大风预警';
    if (precipProb >= 70) return '降水概率高';
    return '';
  }
}

Future<WeatherInfo?> fetchWeather(double lat, double lon) async {
  try {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,visibility'
        '&hourly=precipitation_probability&forecast_days=1');
    final req = await HttpClient().getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
    final hourly = j['hourly'] as Map<String, dynamic>?;
    double prob = 0;
    final probs = hourly?['precipitation_probability'] as List?;
    if (probs != null && probs.isNotEmpty) {
      prob = (probs.first as num?)?.toDouble() ?? 0;
    }
    final text = WeatherInfo.codeText(code);
    return WeatherInfo(
      (cur['temperature_2m'] as num?)?.toDouble() ?? 0,
      (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0,
      (cur['wind_direction_10m'] as num?)?.toDouble() ?? 0,
      (cur['visibility'] as num?)?.toDouble() ?? 0,
      code,
      prob,
      '$text ${(cur['temperature_2m'] as num?)?.toDouble() ?? 0}°C',
    );
  } catch (_) {
    return null;
  }
}
