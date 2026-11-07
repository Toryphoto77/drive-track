import 'dart:convert';
import 'dart:io';
import 'gps_source.dart';
import 'models.dart';
import 'logic.dart';
import 'native.dart';
import 'photo_points.dart';
import 'track_timing.dart';
import 'vehicle_profile.dart';

class TripMeta {
  final String id;
  final TripMode mode;
  final int startMs, endMs;
  final double distanceM, score;
  final bool demo;
  final bool isPublic;
  final int likes;
  // v1.2.0：赛道 / 车辆绑定（JSON 键见 toJson）。旧索引缺这些键时
  // fromJson 回退为街道 / 未绑定；真正的旧数据回填见
  // migrateIndexTrackFields（读不到时回退全量加载 Trip 判断）。
  final bool isTrackMode;
  final String? trackId;
  final String trackName;
  final String? vehicleId;
  // 高德逆地理编码的起终点中文短地名（空 = 未获取，列表回落日期显示）。
  final String startPlace;
  final String endPlace;
  // v1.2.16：GPS 来源（JSON 键 'gps'，存 enum name）。只在保存新
  // 行程时由轨迹点 provider 统计后写入；旧索引缺键时 fromJson 回退
  // unknown，不回填、不编造来源。
  final GpsSource gpsSource;
  const TripMeta(this.id, this.mode, this.startMs, this.endMs, this.distanceM, this.score, this.demo,
      {this.isPublic = false, this.likes = 0, this.isTrackMode = false, this.trackId, this.trackName = '', this.vehicleId, this.startPlace = '', this.endPlace = '', this.gpsSource = GpsSource.unknown});
  Map<String, dynamic> toJson() => {
        'id': id, 'mode': mode.name, 'start': startMs, 'end': endMs,
        'dist': distanceM, 'score': score, 'demo': demo, 'pub': isPublic, 'likes': likes,
        'trackMode': isTrackMode, 'trackId': trackId, 'trackName': trackName, 'vehicleId': vehicleId,
        'startPlace': startPlace, 'endPlace': endPlace, 'gps': gpsSource.name,
      };
  static TripMeta fromJson(Map<String, dynamic> j) => TripMeta(
        j['id'] as String,
        TripModeLabel.fromKey(j['mode'] as String),
        (j['start'] as num).toInt(),
        (j['end'] as num).toInt(),
        (j['dist'] as num?)?.toDouble() ?? 0,
        (j['score'] as num?)?.toDouble() ?? 0,
        (j['demo'] as bool?) ?? false,
        isPublic: (j['pub'] as bool?) ?? false,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        isTrackMode: (j['trackMode'] as bool?) ?? false,
        trackId: j['trackId'] as String?,
        trackName: (j['trackName'] as String?) ?? '',
        vehicleId: j['vehicleId'] as String?,
        startPlace: (j['startPlace'] as String?) ?? '',
        endPlace: (j['endPlace'] as String?) ?? '',
        gpsSource: GpsSourceLabel.fromKey(j['gps'] as String?),
      );
}

/// v1.2.0：照片点落盘结果。超限时 [truncated] 为 true，保存的
/// 只是输入的前 50 条；调用方不得把 truncated 的结果报成全部保存。
class PhotoPointsUpdate {
  final Trip? trip;
  final int inputCount;
  final int savedCount;
  const PhotoPointsUpdate({required this.trip, required this.inputCount, required this.savedCount});
  bool get truncated => savedCount < inputCount;
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
      double? startFinishLat, double? startFinishLon, String? vehicleId}) async {
    final events = detectEvents(points, mode);
    final sc = isTrackMode
        ? ScoreResult(0, {'圈速稳定性': 0.0}, ['赛道模式不评分'])
        : scoreTrip(mode, points, events);
    final id = '${demo ? 'demo-' : ''}${DateTime.now().millisecondsSinceEpoch}';
    // v1.2.0 store 层 50 条上限：超限保留前 50 条（输入顺序），不静默
    // 丢弃之外的部分——调用方以返回 Trip.photoPoints.length 与输入
    // 长度对比即可发现截断；详情页用 updateTripPhotoPointsChecked
    // 拿显式的 truncated 标志展示。
    final cappedPhotoPoints = photoPoints.length > kMaxPhotoPointsPerTrip
        ? photoPoints.sublist(0, kMaxPhotoPointsPerTrip)
        : photoPoints;
    final trip = Trip(
      id: id, mode: mode, startMs: startMs, endMs: endMs, points: points,
      events: events, score: sc.total, subScores: sc.sub, scoreReasons: sc.reasons,
      trimPrivacy: trim, riderBikeKg: riderKg, weatherSummary: weatherSummary,
      videoPaths: videoPaths, trackId: trackId, trackName: trackName,
      isTrackMode: isTrackMode, lapsJson: lapsJson,
      photoPoints: cappedPhotoPoints, vehicleId: vehicleId,
      startFinishLat: startFinishLat, startFinishLon: startFinishLon,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    // v1.2.16：GPS 来源由本次轨迹点的 provider 统计后存入索引；
    // 老行程不回填（索引缺 'gps' 键时读作 unknown）。
    final gpsSource = classifyGpsSource(points.map((p) => p.provider));
    final metas = await loadIndex();
    metas.insert(0, TripMeta(id, mode, startMs, endMs, trip.distanceM, sc.total, demo,
        isTrackMode: isTrackMode, trackId: trackId, trackName: trackName, vehicleId: vehicleId, gpsSource: gpsSource));
    await _saveIndex(metas);
    return trip;
  }

  /// 旧索引迁移：只对索引 JSON 里既无 'trackMode' 又无 'trackId' 键
  /// 的条目回退全量加载对应 Trip 文件，用 Trip 的真实字段回填
  /// isTrackMode/trackId/trackName/vehicleId；其余条目原样保留，
  /// 不丢旧数据。回填后把索引写回（一次性），返回回填后的列表。
  /// 任一步失败时回退到普通 loadIndex，不抛错、不丢索引。
  Future<List<TripMeta>> migrateIndexTrackFields() async {
    try {
      final f = File('$_dir/trips_index.json');
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      var changed = false;
      final metas = <TripMeta>[];
      for (final e in raw) {
        final j = e as Map<String, dynamic>;
        var meta = TripMeta.fromJson(j);
        if (!j.containsKey('trackMode') && !j.containsKey('trackId')) {
          final t = await loadTrip(meta.id);
          if (t != null) {
            meta = TripMeta(meta.id, meta.mode, meta.startMs, meta.endMs,
                meta.distanceM, meta.score, meta.demo,
                isPublic: meta.isPublic, likes: meta.likes,
                isTrackMode: t.isTrackMode, trackId: t.trackId,
                trackName: t.trackName, vehicleId: t.vehicleId,
                startPlace: meta.startPlace, endPlace: meta.endPlace,
                gpsSource: meta.gpsSource);
            changed = true;
          }
        }
        metas.add(meta);
      }
      if (changed) await _saveIndex(metas);
      return metas;
    } catch (_) {
      return loadIndex();
    }
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
      photoPoints: old.photoPoints, vehicleId: old.vehicleId,
      isPublic: isPublic ?? old.isPublic, likes: likes, liked: liked,
      correctedPoints: old.correctedPoints,
      correctionStatus: old.correctionStatus,
      startPlace: old.startPlace, endPlace: old.endPlace,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    final metas = await loadIndex();
    final idx = metas.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      metas[idx] = TripMeta(id, trip.mode, trip.startMs, trip.endMs, trip.distanceM, trip.score, metas[idx].demo,
          isPublic: trip.isPublic, likes: trip.likes,
          isTrackMode: trip.isTrackMode, trackId: trip.trackId, trackName: trip.trackName, vehicleId: trip.vehicleId,
          gpsSource: metas[idx].gpsSource);
      await _saveIndex(metas);
    }
    return trip;
  }

  /// 高德第一批：改写行程的高德派生层（纠偏轨迹、纠偏状态、起终点
  /// 地名），其余字段原样保留。纠偏轨迹只写 'corrPts'，绝不碰
  /// 'points' 原始轨迹；地名同时写回索引（列表显示用）。未传的
  /// 字段保持旧值；行程不存在时返回 null。
  Future<Trip?> updateTripEnrichment(String id,
      {List<(double lat, double lon)>? correctedPoints,
      String? correctionStatus,
      String? startPlace,
      String? endPlace}) async {
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
      photoPoints: old.photoPoints, vehicleId: old.vehicleId,
      isPublic: old.isPublic, likes: old.likes, liked: old.liked,
      correctedPoints: correctedPoints ?? old.correctedPoints,
      correctionStatus: correctionStatus ?? old.correctionStatus,
      startPlace: startPlace ?? old.startPlace,
      endPlace: endPlace ?? old.endPlace,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    final metas = await loadIndex();
    final idx = metas.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      final m = metas[idx];
      metas[idx] = TripMeta(m.id, m.mode, m.startMs, m.endMs, m.distanceM,
          m.score, m.demo,
          isPublic: m.isPublic, likes: m.likes,
          isTrackMode: m.isTrackMode, trackId: m.trackId,
          trackName: m.trackName, vehicleId: m.vehicleId,
          startPlace: startPlace ?? m.startPlace,
          endPlace: endPlace ?? m.endPlace,
          gpsSource: m.gpsSource);
      await _saveIndex(metas);
    }
    return trip;
  }

  /// v0.1.7 照片打点：改写行程的 photoPoints（相册附照片 / 改备注 /
  /// 删点后调用方经此落盘）。只换 photoPoints，其余字段原样保留；
  /// 换图 / 删点时旧副本由调用方（相册页）按守卫删除，本方法不猜路径。
  /// v1.2.0 store 层 50 条上限（显式报告版）：超限保留前 50 条
  /// （输入顺序），[truncated] 为 true 时调用方必须向用户说明
  /// “只保留了前 50 条”，不得当作全部保存成功。
  Future<PhotoPointsUpdate> updateTripPhotoPointsChecked(String id, List<PhotoPoint> photoPoints) async {
    final old = await loadTrip(id);
    if (old == null) return PhotoPointsUpdate(trip: null, inputCount: photoPoints.length, savedCount: 0);
    final capped = photoPoints.length > kMaxPhotoPointsPerTrip
        ? photoPoints.sublist(0, kMaxPhotoPointsPerTrip)
        : photoPoints;
    final trip = Trip(
      id: old.id, mode: old.mode, startMs: old.startMs, endMs: old.endMs,
      points: old.points, events: old.events, score: old.score,
      subScores: old.subScores, scoreReasons: old.scoreReasons,
      trimPrivacy: old.trimPrivacy, riderBikeKg: old.riderBikeKg,
      weatherSummary: old.weatherSummary, videoPaths: old.videoPaths,
      trackId: old.trackId, trackName: old.trackName, isTrackMode: old.isTrackMode,
      lapsJson: old.lapsJson, startFinishLat: old.startFinishLat, startFinishLon: old.startFinishLon,
      photoPoints: capped, vehicleId: old.vehicleId,
      isPublic: old.isPublic, likes: old.likes, liked: old.liked,
      correctedPoints: old.correctedPoints,
      correctionStatus: old.correctionStatus,
      startPlace: old.startPlace, endPlace: old.endPlace,
    );
    await File('$_dir/trip_$id.json').writeAsString(jsonEncode(trip.toJson()));
    return PhotoPointsUpdate(trip: trip, inputCount: photoPoints.length, savedCount: capped.length);
  }

  Future<Trip?> updateTripPhotoPoints(String id, List<PhotoPoint> photoPoints) async {
    final r = await updateTripPhotoPointsChecked(id, photoPoints);
    return r.trip;
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
    // v1.2.0：同步清理 favorites.json 里的孤儿 id，不留死收藏。
    final fav = await loadFavorites();
    if (fav.remove(id)) await _saveFavorites(fav);
    if (old == null) return;
    for (final p in old.photoPoints) {
      await deleteManagedPhotoCopy(p.photoPath, _dir);
    }
  }

  /// v1.2.0 批量删除：逐条走 deleteTrip（索引 + 收藏孤儿清理 +
  /// 照片副本清理同一口径），返回去重后的处理 id 列表。
  /// 视频文件保留：deleteTrip 本来就不删视频，本方法同样不删。
  Future<List<String>> deleteTrips(List<String> ids) async {
    final unique = ids.toSet().toList();
    for (final id in unique) {
      await deleteTrip(id);
    }
    return unique;
  }

  /// v1.2.0 车辆档案持久化：vehicles.json，与 trips_index.json
  /// 同目录，内容即 VehicleLibrary.toJson()；无旧文件返回空集合。
  Future<VehicleLibrary> loadVehicleLibrary() async {
    try {
      final f = File('$_dir/vehicles.json');
      if (!await f.exists()) return const VehicleLibrary();
      return VehicleLibrary.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const VehicleLibrary();
    }
  }

  Future<void> saveVehicleLibrary(VehicleLibrary library) async {
    await File('$_dir/vehicles.json').writeAsString(jsonEncode(library.toJson()));
  }

  /// 删除车辆后批量回退绑定行程：vehicleId 等于被删车辆的行程
  /// 改为 null（回退全局油耗/油价），行程本身不删除、不转给别的车；
  /// 索引同步改写。返回回退的行程数。
  Future<int> rebindTripsAfterVehicleDeleted(String deletedVehicleId) async {
    final metas = await loadIndex();
    var changed = 0;
    for (var i = 0; i < metas.length; i++) {
      final m = metas[i];
      final next = tripVehicleIdAfterVehicleDeleted(deletedVehicleId, m.vehicleId);
      if (next != m.vehicleId) {
        final t = await loadTrip(m.id);
        if (t != null && t.vehicleId == deletedVehicleId) {
          final nt = Trip(
            id: t.id, mode: t.mode, startMs: t.startMs, endMs: t.endMs,
            points: t.points, events: t.events, score: t.score,
            subScores: t.subScores, scoreReasons: t.scoreReasons,
            trimPrivacy: t.trimPrivacy, riderBikeKg: t.riderBikeKg,
            weatherSummary: t.weatherSummary, videoPaths: t.videoPaths,
            trackId: t.trackId, trackName: t.trackName, isTrackMode: t.isTrackMode,
            lapsJson: t.lapsJson, startFinishLat: t.startFinishLat, startFinishLon: t.startFinishLon,
            photoPoints: t.photoPoints, vehicleId: null,
            isPublic: t.isPublic, likes: t.likes, liked: t.liked,
            correctedPoints: t.correctedPoints,
            correctionStatus: t.correctionStatus,
            startPlace: t.startPlace, endPlace: t.endPlace,
          );
          await File('$_dir/trip_${m.id}.json').writeAsString(jsonEncode(nt.toJson()));
        }
        metas[i] = TripMeta(m.id, m.mode, m.startMs, m.endMs, m.distanceM, m.score, m.demo,
            isPublic: m.isPublic, likes: m.likes,
            isTrackMode: m.isTrackMode, trackId: m.trackId, trackName: m.trackName, vehicleId: next,
            startPlace: m.startPlace, endPlace: m.endPlace,
            gpsSource: m.gpsSource);
        changed++;
      }
    }
    if (changed > 0) await _saveIndex(metas);
    return changed;
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

  Future<void> _saveFavorites(Set<String> fav) async {
    await File('$_dir/favorites.json').writeAsString(jsonEncode(fav.toList()));
  }

  Future<Set<String>> toggleFavorite(String id) async {
    final fav = await loadFavorites();
    if (fav.contains(id)) {
      fav.remove(id);
    } else {
      fav.add(id);
    }
    await _saveFavorites(fav);
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

  /// v1.2.18：赛道分段航点。调用方仅在查到赛道包且包有起终点 /
  /// 分段点时传 [startFinish]/[sectorPoints]；默认不传 = 老行为
  /// （不加任何航点）。航点按 GPX 1.1 XSD 顺序写在 <trk> 之前；
  /// 命名只用“起终点/S1/S2”，不写来源字样；分段点按传入顺序编号
  /// S1、S2…。无航点时输出与改前逐字节一致。
  String toGpx(Trip trip,
      {bool trimmed = true,
      GeoPoint? startFinish,
      List<GeoPoint> sectorPoints = const []}) {
    final pts = trimmed ? trimmedPoints(trip) : trip.points;
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="DriveTrack" xmlns="http://www.topografix.com/GPX/1/1">');
    if (startFinish != null) {
      b.writeln('<wpt lat="${startFinish.lat}" lon="${startFinish.lon}"><name>起终点</name></wpt>');
    }
    for (var i = 0; i < sectorPoints.length; i++) {
      final p = sectorPoints[i];
      b.writeln('<wpt lat="${p.lat}" lon="${p.lon}"><name>S${i + 1}</name></wpt>');
    }
    b.writeln('<trk><name>${trip.mode.label} ${DateTime.fromMillisecondsSinceEpoch(trip.startMs)}</name><trkseg>');
    for (final p in pts) {
      // v0.1.7：无海拔点不写 <ele>，不把占位 0 导出成海平面数据。
      final ele = p.altValid ? '<ele>${p.alt.toStringAsFixed(1)}</ele>' : '';
      b.writeln('<trkpt lat="${p.lat}" lon="${p.lon}">$ele'
          '<time>${DateTime.fromMillisecondsSinceEpoch(p.timeMs).toUtc().toIso8601String()}</time></trkpt>');
    }
    b.writeln('</trkseg></trk></gpx>');
    return b.toString();
  }

  /// v1.2.18：赛道行程（isTrackMode 且 lapsJson 非空）时，在逐点行
  /// 末尾追加分段小节（空行 + 表头 + 每圈一行；圈号从 1 起按
  /// lapsJson 顺序；缺失的段留空，绝不填 0、绝不估算）。街道行程
  /// 与无 laps 的行程输出字节级不变。
  /// [hasSectorPoints] 为调用方告知的“该行程赛道包有无真实分段点”：
  /// false 时三列一律留空（无分段点的圈在 Lap 层仍带 2 段退化半圈，
  /// 见 track_timing.dart，不得把半圈当分段成绩导出）；null（未告
  /// 知）时只在 sectorsMs 长度 ≥3 时写值（3 段只能来自 2 个真实
  /// 分段点），2 段一律留空，宁可少写也不冒充；true 时按实际长度写。
  String toCsv(Trip trip, {bool trimmed = false, bool? hasSectorPoints}) {
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
    if (trip.isTrackMode && trip.lapsJson.isNotEmpty) {
      b.writeln();
      b.writeln('lap,total_ms,s1_ms,s2_ms,s3_ms');
      for (var i = 0; i < trip.lapsJson.length; i++) {
        final lap = Lap.fromJson(trip.lapsJson[i]);
        final showSectors = hasSectorPoints == true ||
            (hasSectorPoints == null && lap.sectorsMs.length >= 3);
        String sec(int idx) => showSectors &&
                idx < lap.sectorsMs.length
            ? '${lap.sectorsMs[idx]}'
            : '';
        b.writeln('${i + 1},${lap.durationMs},${sec(0)},${sec(1)},${sec(2)}');
      }
    }
    return b.toString();
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

/// v1.2.0 天气新鲜度口径（纯函数，可单测）：10 分钟内且位置
/// 移动不超过 10 km 时算新鲜，不重拉；无旧天气、超 10 分钟、
/// 或移动超 10 km 时需要重拉。旧天气坐标为空时只看时间。
const int kWeatherFreshMs = 10 * 60 * 1000;
const double kWeatherMoveM = 10000;

bool weatherNeedsRefresh({
  required bool hasWeather,
  required int weatherMs,
  required int nowMs,
  double? cachedLat,
  double? cachedLon,
  double? lat,
  double? lon,
}) {
  if (!hasWeather) return true;
  if (nowMs - weatherMs > kWeatherFreshMs) return true;
  if (cachedLat != null && cachedLon != null && lat != null && lon != null) {
    if (haversineM(cachedLat, cachedLon, lat, lon) > kWeatherMoveM) return true;
  }
  return false;
}

Future<WeatherInfo?> fetchWeather(double lat, double lon) async {
  // v1.2.0：超时包住整个请求（建连 + 发请求 + 读 body），不再只
  // 包 close()；弱网下 10 秒必返回 null，不拖住调用方。client
  // 在 finally 里关闭，避免泄漏。
  final client = HttpClient();
  try {
    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,visibility'
        '&hourly=precipitation_probability&forecast_days=1');
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
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
  } finally {
    client.close();
  }
}
