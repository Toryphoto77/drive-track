import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'models.dart';

/// 行程点超过此数量时，轨迹点改存 NDJSON 侧车，主 JSON 只留摘要。
/// 旧版 trip_*.json（points 内联）仍可直接 load，无需迁移。
const int kTripPointsSidecarThreshold = 2000;

/// 行程文件的可扩展存储：
/// - 小行程：`trip_{id}.json` 内联 points（与历史格式完全一致）
/// - 大行程：主 JSON 的 `points` 为空列表，另写 `trip_{id}.points.ndjson`，
///   主 JSON 带 `"pointsFile": "trip_{id}.points.ndjson"` 与 `"pointCount"`。
///
/// 迁移路径（未自动跑全量迁移，避免一次改写用户全部数据）：
/// 1. 新保存的大行程自动走侧车；
/// 2. 旧大行程仍以内联形式可读；
/// 3. 用户下次编辑/重新保存该行程时会按阈值改写为侧车。
String tripJsonPath(String dir, String id) => '$dir/trip_$id.json';
String tripPointsPath(String dir, String id) => '$dir/trip_$id.points.ndjson';

/// 是否应把轨迹点拆到侧车。
bool shouldUsePointsSidecar(int pointCount) =>
    pointCount >= kTripPointsSidecarThreshold;

Future<void> writeTripPointsNdjson(String path, List<TrackPoint> points) async {
  final tmp = '$path.tmp';
  final sink = File(tmp).openWrite();
  try {
    for (final p in points) {
      sink.writeln(jsonEncode(p.toJson()));
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  await File(tmp).rename(path);
}

Future<List<TrackPoint>> readTripPointsNdjson(String path) async {
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

/// 把 Trip 写成磁盘格式（可能拆侧车），返回写入的主 JSON 字符串（便于测试）。
Future<String> encodeTripForDisk(String dir, Trip trip) async {
  final j = trip.toJson();
  if (shouldUsePointsSidecar(trip.points.length)) {
    final ptsName = 'trip_${trip.id}.points.ndjson';
    await writeTripPointsNdjson('$dir/$ptsName', trip.points);
    j['points'] = <Map<String, dynamic>>[];
    j['pointsFile'] = ptsName;
    j['pointCount'] = trip.points.length;
  } else {
    j.remove('pointsFile');
    j.remove('pointCount');
    // 小行程若曾有侧车，清掉以免 load 时误合并旧点。
    try {
      final side = File(tripPointsPath(dir, trip.id));
      if (await side.exists()) await side.delete();
    } catch (_) {}
  }
  final body = jsonEncode(j);
  await writeStringAtomic(tripJsonPath(dir, trip.id), body);
  return body;
}

/// 从磁盘读 Trip：主 JSON + 可选侧车。纯内联旧文件原样工作。
Future<Trip?> decodeTripFromDisk(String dir, String id) async {
  final f = File(tripJsonPath(dir, id));
  if (!await f.exists()) return null;
  try {
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final sideName = j['pointsFile'] as String?;
    if (sideName != null && sideName.isNotEmpty) {
      final pts = await readTripPointsNdjson('$dir/$sideName');
      j['points'] = pts.map((p) => p.toJson()).toList();
    }
    return Trip.fromJson(j);
  } catch (_) {
    return null;
  }
}

/// 删除行程时一并删侧车。
Future<void> deleteTripFiles(String dir, String id) async {
  for (final p in [tripJsonPath(dir, id), tripPointsPath(dir, id)]) {
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
