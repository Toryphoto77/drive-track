import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'models.dart';
import 'photo_points.dart';
import 'store.dart';

/// 录制草稿：记录进行中把已采到的轨迹落盘，进程被杀后可恢复。
///
/// v2 增量格式（默认）：
/// - [metaPath]：模式、起止、照片、圈速等元数据（原子整写）
/// - [pointsPath]：轨迹点 NDJSON，只追加新点，不再每次全量重写
/// - [obdPath]：OBD 样本 NDJSON，只追加
///
/// 仍可读 v1 的整文件 [legacyPath]（recording_draft.json），读到后
/// 下一次保存会迁到 v2。正常结束（_endTrip）后草稿即删除。
class RecordingDraft {
  final TripMode mode;
  final int startMs;
  final int savedAtMs;
  final List<TrackPoint> points;
  final List<Map<String, dynamic>> obdSamples;
  final List<PhotoPoint> photoPoints;
  final bool trimPrivacy;
  final double riderKg;
  final String weatherSummary;
  final bool isTrackMode;
  final String? trackId;
  final String trackName;
  final List<Map<String, dynamic>> lapsJson;
  final String? vehicleId;

  const RecordingDraft({
    required this.mode,
    required this.startMs,
    required this.savedAtMs,
    required this.points,
    this.obdSamples = const [],
    this.photoPoints = const [],
    this.trimPrivacy = true,
    this.riderKg = 85,
    this.weatherSummary = '',
    this.isTrackMode = false,
    this.trackId,
    this.trackName = '',
    this.lapsJson = const [],
    this.vehicleId,
  });

  /// 行程结束时刻：最后一个轨迹点的时间（没有点时用落盘时间）。
  int get endMs => points.isNotEmpty ? points.last.timeMs : savedAtMs;

  /// v1 整文件 JSON（测试 / 迁移兼容）。
  Map<String, dynamic> toJson() => {
        'v': 1,
        'mode': mode.name,
        'start': startMs,
        'saved': savedAtMs,
        'points': points.map((p) => p.toJson()).toList(),
        'obd': obdSamples,
        'photos': photoPoints.map((p) => p.toJson()).toList(),
        'trim': trimPrivacy,
        'kg': riderKg,
        'weather': weatherSummary,
        'trackMode': isTrackMode,
        'trackId': trackId,
        'trackName': trackName,
        'laps': lapsJson,
        'vehicleId': vehicleId,
      };

  /// v2 元数据（不含轨迹点 / OBD，那些走 NDJSON 追加）。
  Map<String, dynamic> toMetaJson({required int pointCount, required int obdCount}) => {
        'v': 2,
        'mode': mode.name,
        'start': startMs,
        'saved': savedAtMs,
        'pointCount': pointCount,
        'obdCount': obdCount,
        'photos': photoPoints.map((p) => p.toJson()).toList(),
        'trim': trimPrivacy,
        'kg': riderKg,
        'weather': weatherSummary,
        'trackMode': isTrackMode,
        'trackId': trackId,
        'trackName': trackName,
        'laps': lapsJson,
        'vehicleId': vehicleId,
      };

  static RecordingDraft fromJson(Map<String, dynamic> j) => RecordingDraft(
        mode: TripModeLabel.fromKey(j['mode'] as String),
        startMs: (j['start'] as num).toInt(),
        savedAtMs: (j['saved'] as num).toInt(),
        points: ((j['points'] as List?) ?? [])
            .map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        obdSamples: ((j['obd'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        photoPoints: ((j['photos'] as List?) ?? [])
            .map((e) => PhotoPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        trimPrivacy: (j['trim'] as bool?) ?? true,
        riderKg: (j['kg'] as num?)?.toDouble() ?? 85,
        weatherSummary: (j['weather'] as String?) ?? '',
        isTrackMode: (j['trackMode'] as bool?) ?? false,
        trackId: j['trackId'] as String?,
        trackName: (j['trackName'] as String?) ?? '',
        lapsJson: ((j['laps'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        vehicleId: j['vehicleId'] as String?,
      );

  static RecordingDraft fromMetaAndPoints(
    Map<String, dynamic> meta,
    List<TrackPoint> points,
    List<Map<String, dynamic>> obd,
  ) =>
      RecordingDraft(
        mode: TripModeLabel.fromKey(meta['mode'] as String),
        startMs: (meta['start'] as num).toInt(),
        savedAtMs: (meta['saved'] as num).toInt(),
        points: points,
        obdSamples: obd,
        photoPoints: ((meta['photos'] as List?) ?? [])
            .map((e) => PhotoPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        trimPrivacy: (meta['trim'] as bool?) ?? true,
        riderKg: (meta['kg'] as num?)?.toDouble() ?? 85,
        weatherSummary: (meta['weather'] as String?) ?? '',
        isTrackMode: (meta['trackMode'] as bool?) ?? false,
        trackId: meta['trackId'] as String?,
        trackName: (meta['trackName'] as String?) ?? '',
        lapsJson: ((meta['laps'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        vehicleId: meta['vehicleId'] as String?,
      );
}

/// 能救回成行程的最少轨迹点数（与正常结束时“少于 10 点不保存”同口径）。
const int kMinRecoverablePoints = 10;

/// 原生 TrackService 在 Activity 销毁后继续写入的 GPS 侧车文件名。
const String kNativePointsFileName = 'recording_native_points.ndjson';

class RecordingDraftStore {
  final String dir;
  RecordingDraftStore(this.dir);

  /// v1 整文件（只读兼容）。
  String get legacyPath => '$dir/recording_draft.json';
  String get metaPath => '$dir/recording_draft_meta.json';
  String get pointsPath => '$dir/recording_draft_points.ndjson';
  String get obdPath => '$dir/recording_draft_obd.ndjson';
  String get nativePointsPath => '$dir/$kNativePointsFileName';

  /// 上次成功落盘的点数 / OBD 条数（进程内），用于只追加增量。
  int _persistedPoints = 0;
  int _persistedObd = 0;

  int get persistedPointCount => _persistedPoints;
  int get persistedObdCount => _persistedObd;

  /// 全量保存（首次 / 元数据变更 / 测试）。轨迹点与 OBD 走 NDJSON 重写。
  Future<void> save(RecordingDraft d) async {
    await writeStringAtomic(
        metaPath,
        jsonEncode(d.toMetaJson(
            pointCount: d.points.length, obdCount: d.obdSamples.length)));
    await _rewriteNdjson(pointsPath, d.points.map((p) => jsonEncode(p.toJson())));
    await _rewriteNdjson(obdPath, d.obdSamples.map(jsonEncode));
    _persistedPoints = d.points.length;
    _persistedObd = d.obdSamples.length;
    // 迁到 v2 后清掉 v1 整文件，避免下次 load 读到旧副本。
    try {
      final legacy = File(legacyPath);
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {}
  }

  /// 增量追加：只写 [points] / [obd] 里尚未落盘的尾部，并刷新元数据。
  /// 若尚未有 meta（第一次），退化为 [save]。
  Future<void> saveIncremental(RecordingDraft d) async {
    if (!await File(metaPath).exists() && _persistedPoints == 0) {
      await save(d);
      return;
    }
    final newPts = d.points.length > _persistedPoints
        ? d.points.sublist(_persistedPoints)
        : const <TrackPoint>[];
    final newObd = d.obdSamples.length > _persistedObd
        ? d.obdSamples.sublist(_persistedObd)
        : const <Map<String, dynamic>>[];
    if (newPts.isNotEmpty) {
      await _appendNdjson(pointsPath, newPts.map((p) => jsonEncode(p.toJson())));
      _persistedPoints = d.points.length;
    }
    if (newObd.isNotEmpty) {
      await _appendNdjson(obdPath, newObd.map(jsonEncode));
      _persistedObd = d.obdSamples.length;
    }
    await writeStringAtomic(
        metaPath,
        jsonEncode(d.toMetaJson(
            pointCount: d.points.length, obdCount: d.obdSamples.length)));
  }

  Future<void> _rewriteNdjson(String path, Iterable<String> lines) async {
    final tmp = '$path.tmp';
    final f = File(tmp);
    final sink = f.openWrite();
    try {
      for (final line in lines) {
        sink.writeln(line);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await File(tmp).rename(path);
  }

  Future<void> _appendNdjson(String path, Iterable<String> lines) async {
    final f = File(path);
    final sink = f.openWrite(mode: FileMode.append);
    try {
      for (final line in lines) {
        sink.writeln(line);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<List<TrackPoint>> _readPointsFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return [];
    final out = <TrackPoint>[];
    await for (final line in f
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final s = line.trim();
      if (s.isEmpty) continue;
      try {
        out.add(TrackPoint.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _readObdFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return [];
    final out = <Map<String, dynamic>>[];
    await for (final line in f
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final s = line.trim();
      if (s.isEmpty) continue;
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    return out;
  }

  /// 合并原生侧车点（TrackService 在 Activity 销毁后写入）。
  /// 按 timeMs 去重，已有 Flutter 点优先。
  static List<TrackPoint> mergeNativePoints(
      List<TrackPoint> flutterPts, List<TrackPoint> nativePts) {
    if (nativePts.isEmpty) return flutterPts;
    final seen = <int>{for (final p in flutterPts) p.timeMs};
    final merged = List<TrackPoint>.from(flutterPts);
    for (final p in nativePts) {
      if (seen.add(p.timeMs)) merged.add(p);
    }
    merged.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return merged;
  }

  /// 读草稿；不存在返回 null。损坏时改名留底，返回 null。
  /// 同时合并原生侧车点（若有）。
  Future<RecordingDraft?> load() async {
    try {
      RecordingDraft? d;
      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        final meta =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        final pts = await _readPointsFile(pointsPath);
        final obd = await _readObdFile(obdPath);
        d = RecordingDraft.fromMetaAndPoints(meta, pts, obd);
        _persistedPoints = pts.length;
        _persistedObd = obd.length;
      } else {
        final legacy = File(legacyPath);
        if (await legacy.exists()) {
          d = RecordingDraft.fromJson(
              jsonDecode(await legacy.readAsString()) as Map<String, dynamic>);
          _persistedPoints = d.points.length;
          _persistedObd = d.obdSamples.length;
        }
      }
      if (d == null) {
        // 仅有原生侧车、没有 Flutter 草稿时，也尽量救回。
        final nativeOnly = await _readPointsFile(nativePointsPath);
        if (nativeOnly.length < kMinRecoverablePoints) return null;
        return RecordingDraft(
          mode: TripMode.car,
          startMs: nativeOnly.first.timeMs,
          savedAtMs: nativeOnly.last.timeMs,
          points: nativeOnly,
        );
      }
      final native = await _readPointsFile(nativePointsPath);
      if (native.isEmpty) return d;
      return RecordingDraft(
        mode: d.mode,
        startMs: d.startMs,
        savedAtMs: d.savedAtMs,
        points: mergeNativePoints(d.points, native),
        obdSamples: d.obdSamples,
        photoPoints: d.photoPoints,
        trimPrivacy: d.trimPrivacy,
        riderKg: d.riderKg,
        weatherSummary: d.weatherSummary,
        isTrackMode: d.isTrackMode,
        trackId: d.trackId,
        trackName: d.trackName,
        lapsJson: d.lapsJson,
        vehicleId: d.vehicleId,
      );
    } catch (_) {
      try {
        final f = File(metaPath);
        if (await f.exists()) {
          await f.rename(
              '$dir/recording_draft_meta.corrupt-${DateTime.now().millisecondsSinceEpoch}.json');
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> clear() async {
    _persistedPoints = 0;
    _persistedObd = 0;
    for (final p in [legacyPath, metaPath, pointsPath, obdPath, nativePointsPath]) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// 把草稿存成正式行程（与正常结束同一个 saveTrip 入口），成功后删草稿。
  Future<Trip?> recoverInto(Store store, RecordingDraft d) async {
    if (d.points.length < kMinRecoverablePoints) return null;
    final trip = await store.saveTrip(d.mode, d.startMs, d.endMs, d.points,
        trim: d.trimPrivacy,
        riderKg: d.riderKg,
        weatherSummary: d.weatherSummary,
        trackId: d.isTrackMode ? d.trackId : null,
        trackName: d.isTrackMode ? d.trackName : '',
        isTrackMode: d.isTrackMode,
        lapsJson: d.lapsJson,
        photoPoints: d.photoPoints,
        obdSamples: d.obdSamples,
        vehicleId: d.vehicleId,
        startFinishLat: d.isTrackMode ? d.points.first.lat : null,
        startFinishLon: d.isTrackMode ? d.points.first.lon : null);
    await clear();
    return trip;
  }
}
