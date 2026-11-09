/// 高德 Web 服务客户端（第一批三件：轨迹纠偏 + 逆地理编码 + 静态地图）。
///
/// Key 来源：与路网高德兜底（recording_3d_map.dart 的 `amapKey`）同一处，
/// 构建时经 --dart-define=AMAP_KEY 注入；未注入时为空串，本文件所有
/// 调用直接返回 null（不发无 Key 请求）。Key 绝不硬编码进源码与测试。
///
/// 坐标系不对称（必须写明，不要假装全换了）：
/// - WGS-84 → GCJ-02：走高德官方坐标转换接口（v3/assistant/coordinate/convert，
///   coordsys=gps）。纠偏入参、逆地理编码入参、静态地图坐标全部经此接口。
/// - GCJ-02 → WGS-84：高德官方不提供反向接口，仍用本地逆推公式
///   [gcjToWgsLocal]（与 recording_3d_map.dart 的 gcj02ToWgs84 同算法；
///   该文件本批禁动，故此处独立一份，不跨文件 import 地图页）。
/// 交通回包、纠偏回包的 GCJ-02 坐标一律经此逆推公式转回 WGS-84 再存。
///
/// 通用失败口径：所有公开异步函数失败时返回 null，绝不抛错、不阻塞
/// 调用方；调用方按“回落原始/原有显示”处理。网络层可注入（见
/// [AmapJsonFetcher] 等 typedef，默认实现走 HttpClient；测试用 fake
/// 覆盖分段拼接、解析与回落，不发真实请求、不用真实 Key）。
/// 中国境外行程一律跳过高德调用（见 [isInChina]，起终点粗判）。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

/// 高德 Web 服务 Key（构建时 --dart-define=AMAP_KEY 注入）。
const String amapWebKey =
    String.fromEnvironment('AMAP_KEY', defaultValue: '');

/// 中国范围粗框（与 widgets.dart / recording_3d_map.dart 的 GCJ 偏移
/// 守卫同一组边界值）：lon 72.004~137.8347，lat 0.8293~55.8271。
/// 只做“境内/境外”粗判，不做精确国界判断。
bool isInChina(double lat, double lon) =>
    lon >= 72.004 &&
    lon <= 137.8347 &&
    lat >= 0.8293 &&
    lat <= 55.8271;

/// 行程是否可走高德：起终点都在中国粗框内才调（任一在外即跳过）。
bool tripInChina(List<TrackPoint> points) {
  if (points.isEmpty) return false;
  return isInChina(points.first.lat, points.first.lon) &&
      isInChina(points.last.lat, points.last.lon);
}

// ---------------------------------------------------------------------------
// 网络注入点（默认实现走 HttpClient；测试注入 fake，不发真实请求）。
// ---------------------------------------------------------------------------

/// GET → 解析后 JSON，失败（网络/超时/非 200/解析失败）返回 null。
typedef AmapJsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);

/// POST JSON → 解析后 JSON，失败返回 null。
typedef AmapPostFetcher = Future<Map<String, dynamic>?> Function(
    Uri uri, String body);

/// GET → 原始字节（静态地图图片），失败或服务端回 JSON 报错时返回 null。
typedef AmapBytesFetcher = Future<Uint8List?> Function(Uri uri);

Future<Map<String, dynamic>?> _defaultJsonFetcher(Uri uri,
    {HttpClient? client}) async {
  final owned = client == null;
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(body);
    if (j is! Map<String, dynamic>) return null;
    return j;
  } catch (_) {
    return null;
  } finally {
    if (owned) c.close(force: true);
  }
}

Future<Map<String, dynamic>?> _defaultPostFetcher(Uri uri, String body,
    {HttpClient? client}) async {
  final owned = client == null;
  final c = client ?? HttpClient();
  try {
    final req = await c.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(body);
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) return null;
    return j;
  } catch (_) {
    return null;
  } finally {
    if (owned) c.close(force: true);
  }
}

Future<Uint8List?> _defaultBytesFetcher(Uri uri, {HttpClient? client}) async {
  final owned = client == null;
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final type = resp.headers.contentType?.mimeType ?? '';
    // 静态地图报错时服务端回 JSON（application/json），不是图片。
    if (type.contains('json')) return null;
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return null;
    return Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  } finally {
    if (owned) c.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// 坐标转换：WGS-84 → GCJ-02 走官方接口；GCJ-02 → WGS-84 本地逆推。
// ---------------------------------------------------------------------------

/// 官方坐标转换单次请求点数上限（保守分段值；超过即分段，不依赖
/// 未证实的更大上限）。
const int kConvertChunkSize = 40;

/// 转换接口 URL（coordsys=gps 表示输入为 GPS/WGS-84 坐标）。
Uri buildConvertUrl(String key, List<(double lat, double lon)> points) {
  final locs = points
      .map((p) =>
          '${p.$2.toStringAsFixed(6)},${p.$1.toStringAsFixed(6)}')
      .join('|');
  return Uri.parse(
      'https://restapi.amap.com/v3/assistant/coordinate/convert?key=$key&locations=$locs&coordsys=gps');
}

/// 解析转换回包：status=1 且 locations 为 "lon,lat;lon,lat" 时返回
/// GCJ-02 点列（顺序与入参一致），否则 null。
List<(double lat, double lon)>? parseConvertResponse(
    Map<String, dynamic> json) {
  if (json['status']?.toString() != '1') return null;
  final locs = json['locations'];
  if (locs is! String || locs.isEmpty) return null;
  final out = <(double lat, double lon)>[];
  for (final pair in locs.split(';')) {
    final parts = pair.split(',');
    if (parts.length != 2) return null;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) return null;
    out.add((lat, lon));
  }
  return out;
}

/// WGS-84 → GCJ-02（官方接口，分段请求再拼接；任一段失败即整体 null）。
/// 入参少于 1 点时返回空列（不发请求）。
Future<List<(double lat, double lon)>?> convertWgsToGcj(
  List<(double lat, double lon)> points, {
  String? key,
  AmapJsonFetcher? jsonFetcher,
  HttpClient? httpClient,
}) async {
  if (points.isEmpty) return [];
  final k = key ?? amapWebKey;
  if (k.isEmpty) return null;
  final fetch = jsonFetcher ?? (Uri u) => _defaultJsonFetcher(u, client: httpClient);
  final out = <(double lat, double lon)>[];
  for (var i = 0; i < points.length; i += kConvertChunkSize) {
    final chunk = points.sublist(
        i, math.min(i + kConvertChunkSize, points.length));
    final json = await fetch(buildConvertUrl(k, chunk));
    if (json == null) return null;
    final parsed = parseConvertResponse(json);
    if (parsed == null || parsed.length != chunk.length) return null;
    out.addAll(parsed);
  }
  return out;
}

/// GCJ-02 → WGS-84 本地逆推公式（与 recording_3d_map.dart 的
/// gcj02ToWgs84 同算法；官方无反向接口，故保留此公式并明示）。
/// 框外坐标返回原值（与正向守卫一致）。
(double, double) gcjToWgsLocal(double gcjLat, double gcjLon) {
  if (gcjLon < 72.004 ||
      gcjLon > 137.8347 ||
      gcjLat < 0.8293 ||
      gcjLat > 55.8271) {
    return (gcjLat, gcjLon);
  }
  double transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(y / 12.0 * math.pi) + 300.0 * math.sin(y / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x * math.pi / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  const a = 6378245.0, ee = 0.00669342162296594323;
  final dLat = transformLat(gcjLon - 105.0, gcjLat - 35.0);
  final dLon = transformLon(gcjLon - 105.0, gcjLat - 35.0);
  final radLat = gcjLat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final dLatDeg = dLat * 180.0 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final dLonDeg = dLon * 180.0 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (gcjLat - dLatDeg, gcjLon - dLonDeg);
}

/// WGS-84 → GCJ-02 本地正向公式（与 [gcjToWgsLocal] 同一套标准
/// 偏移算法、方向镜像；变换函数逐字一致，保证往返一致）。
/// 记录页高德栅格瓦片是 GCJ-02，叠加层（中心线 / 轨迹 / 当前位置 /
/// 幽灵车 / 起终点 / 分段点）为 WGS-84，画之前必须经此转换，
/// 否则叠加层与道路错位可达约 500 米。
/// 框外坐标返回原值（与逆推守卫一致）。
(double, double) wgsToGcjLocal(double wgsLat, double wgsLon) {
  if (wgsLon < 72.004 ||
      wgsLon > 137.8347 ||
      wgsLat < 0.8293 ||
      wgsLat > 55.8271) {
    return (wgsLat, wgsLon);
  }
  double transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(y / 12.0 * math.pi) + 300.0 * math.sin(y / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x * math.pi / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  const a = 6378245.0, ee = 0.00669342162296594323;
  final dLat = transformLat(wgsLon - 105.0, wgsLat - 35.0);
  final dLon = transformLon(wgsLon - 105.0, wgsLat - 35.0);
  final radLat = wgsLat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final dLatDeg = dLat * 180.0 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final dLonDeg = dLon * 180.0 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (wgsLat + dLatDeg, wgsLon + dLonDeg);
}

// ---------------------------------------------------------------------------
// 记录页高德栅格瓦片（免 Key 标准路网，style=7）。
// ---------------------------------------------------------------------------

/// 高德栅格瓦片署名（记录页右下角显示）。
const String amapTileAttribution = '© 高德地图';

/// 高德标准路网栅格瓦片 URL（免 Key 端点 webrd01，style=7；
/// 换算与 Esri 瓦片同一套 Web Mercator slippy-map 公式）。
/// 只供记录页（lib/recording_map_page.dart）使用；编辑页与分析页
/// 仍用 Esri 卫星瓦片，不动。
String amapTileUrl(int z, int x, int y) =>
    'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x=$x&y=$y&z=$z';

// ---------------------------------------------------------------------------
// 轨迹纠偏（v4/grasproad/driving，POST JSON 数组）。
// ---------------------------------------------------------------------------

/// 纠偏单次请求点数上限：接口文档为 500，本实现取 400 留余量。
const int kCorrectionChunkSize = 400;

/// 纠偏分段重叠点数：相邻段共用 1 个边界输入点，拼接时去重，
/// 保证拼接处不断线（两段对同一输入点的纠偏输出至多差几米）。
const int kCorrectionChunkOverlap = 1;

/// 纠偏前抽稀：相邻点时间间隔下限（秒）。接口文档称 5~10 秒间隔
/// 效果最优；手机 GPS 约 1Hz、外接可达 25Hz，不抽稀会烧掉大量
/// 额度且无助于贴合。首尾点恒保留。
const int kCorrectionMinGapSeconds = 4;

/// 纠偏抽稀：按时间间隔取点，首尾恒保留（纯函数，可单测）。
List<TrackPoint> thinPointsForCorrection(List<TrackPoint> points) {
  if (points.length <= 2) return List<TrackPoint>.of(points);
  final out = <TrackPoint>[points.first];
  var lastKept = points.first;
  for (var i = 1; i < points.length - 1; i++) {
    if (points[i].timeMs - lastKept.timeMs >=
        kCorrectionMinGapSeconds * 1000) {
      out.add(points[i]);
      lastKept = points[i];
    }
  }
  out.add(points.last);
  return out;
}

/// 带重叠的分段（纯函数，可单测）：段长 [size]，相邻段共用 [overlap]
/// 个输入点；不足一段时只一段。
List<List<T>> chunkWithOverlap<T>(List<T> items, int size,
    {int overlap = 1}) {
  if (items.isEmpty) return [];
  if (size <= overlap) return [List<T>.of(items)];
  final out = <List<T>>[];
  var start = 0;
  while (start < items.length) {
    final end = math.min(start + size, items.length);
    out.add(items.sublist(start, end));
    if (end >= items.length) break;
    start = end - overlap;
  }
  return out;
}

/// 由前后点方向算纠偏角度 ag（正北 0°、顺时针 0~360）。
/// 零长段沿用上一个角度；首点无方向时返回 0.5（接口文档称 ag=0
/// 易判失败，故精确 0°（正北）也按 0.5° 送，偏差可忽略）。
double correctionAngleFor(List<TrackPoint> points, int index) {
  double angleBetween(TrackPoint a, TrackPoint b) {
    final dx = (b.lon - a.lon) * math.cos(a.lat * math.pi / 180);
    final dy = b.lat - a.lat;
    if (dx == 0 && dy == 0) return double.nan;
    return (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
  }

  double? prev;
  for (var i = 0; i < points.length - 1; i++) {
    final a = angleBetween(points[i], points[i + 1]);
    if (!a.isNaN) {
      if (i == index) return a == 0 ? 0.5 : a;
      prev = a;
    } else if (i == index) {
      return prev ?? 0.5;
    }
  }
  if (points.length >= 2) {
    final a = angleBetween(points[points.length - 2], points.last);
    if (index == points.length - 1) {
      if (!a.isNaN) return a == 0 ? 0.5 : a;
      return prev ?? 0.5;
    }
  }
  return 0.5;
}

/// 纠偏请求体（纯函数，可单测）：抽稀后点列 → JSON 数组字符串。
/// - x=经度、y=纬度（GCJ-02，小数点后 6 位，接口要求）；
/// - ag=方向角（见 correctionAngleFor 的 0° 处理）；
/// - tm=秒：首点为 epoch 秒，其余为相对首点的偏移秒；
/// - sp=km/h；静止内点（<2 km/h）剔除（贴合不需要静止点，且
///   不合理速度易致整段失败），首尾点恒保留且 sp 下限 5。
String buildCorrectionRequestBody(List<TrackPoint> thinned) {
  final kept = <TrackPoint>[];
  for (var i = 0; i < thinned.length; i++) {
    final p = thinned[i];
    final first = i == 0, last = i == thinned.length - 1;
    if (!first && !last && p.speed * 3.6 < 2) continue;
    kept.add(p);
  }
  final t0 = kept.first.timeMs ~/ 1000;
  final arr = <Map<String, dynamic>>[];
  for (var i = 0; i < kept.length; i++) {
    final p = kept[i];
    final sp = math.max(5.0, p.speed * 3.6);
    arr.add({
      'x': double.parse(p.lon.toStringAsFixed(6)),
      'y': double.parse(p.lat.toStringAsFixed(6)),
      'ag': double.parse(correctionAngleFor(kept, i).toStringAsFixed(1)),
      'tm': p.timeMs ~/ 1000 - t0,
      'sp': double.parse(sp.toStringAsFixed(1)),
    });
  }
  return jsonEncode(arr);
}

/// 解析纠偏回包：errcode=0 且 data.points 为 [{x,y}] 时返回
/// GCJ-02 点列，否则 null（errcode 30001=纠偏失败、点过少/过稀）。
List<(double lat, double lon)>? parseCorrectionResponse(
    Map<String, dynamic> json) {
  final err = json['errcode'];
  if (err != 0 && err != '0') return null;
  final data = json['data'];
  if (data is! Map<String, dynamic>) return null;
  final pts = data['points'];
  if (pts is! List) return null;
  final out = <(double lat, double lon)>[];
  for (final e in pts) {
    if (e is! Map) return null;
    final x = e['x'] is num
        ? (e['x'] as num).toDouble()
        : double.tryParse('${e['x']}');
    final y = e['y'] is num
        ? (e['y'] as num).toDouble()
        : double.tryParse('${e['y']}');
    if (x == null || y == null) return null;
    out.add((y, x));
  }
  return out;
}

/// 轨迹纠偏全流程：WGS-84 原始点 → 抽稀 → 官方转换 → 分段纠偏 →
/// 逆推回 WGS-84 → 拼接。任一步失败返回 null（调用方显示原始轨迹）。
/// 入参须为已过滤 0,0 的有效点列；少于 2 点直接返回 null。
Future<List<(double lat, double lon)>?> correctTrackPoints(
  List<TrackPoint> points, {
  String? key,
  AmapJsonFetcher? jsonFetcher,
  AmapPostFetcher? postFetcher,
  HttpClient? httpClient,
}) async {
  final k = key ?? amapWebKey;
  if (k.isEmpty) return null;
  final valid = points.where((p) => p.lat != 0 || p.lon != 0).toList();
  if (valid.length < 2) return null;
  final thinned = thinPointsForCorrection(valid);
  if (thinned.length < 2) return null;
  // 请求体先算（剔除静止内点后的点列才是真正送纠偏的点列）；
  // 转换只转这些点，避免多烧额度。
  final body = buildCorrectionRequestBody(thinned);
  final reqPts = <(double lat, double lon)>[];
  for (final e in jsonDecode(body) as List) {
    final m = e as Map<String, dynamic>;
    reqPts.add(((m['y'] as num).toDouble(), (m['x'] as num).toDouble()));
  }
  if (reqPts.length < 2) return null;
  final gcj = await convertWgsToGcj(reqPts,
      key: k, jsonFetcher: jsonFetcher, httpClient: httpClient);
  if (gcj == null) return null;
  // 按 GCJ 点列重建请求体（x/y 换成转换后的值，其余字段不变）。
  final reqArr = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  for (var i = 0; i < reqArr.length; i++) {
    reqArr[i]['x'] = double.parse(gcj[i].$2.toStringAsFixed(6));
    reqArr[i]['y'] = double.parse(gcj[i].$1.toStringAsFixed(6));
  }
  final post = postFetcher ??
      (Uri u, String b) => _defaultPostFetcher(u, b, client: httpClient);
  final url =
      Uri.parse('https://restapi.amap.com/v4/grasproad/driving?key=$k');
  final chunks = chunkWithOverlap<Map<String, dynamic>>(reqArr,
      kCorrectionChunkSize,
      overlap: kCorrectionChunkOverlap);
  final correctedGcj = <(double lat, double lon)>[];
  for (var ci = 0; ci < chunks.length; ci++) {
    final json = await post(url, jsonEncode(chunks[ci]));
    if (json == null) return null;
    final parsed = parseCorrectionResponse(json);
    if (parsed == null || parsed.isEmpty) return null;
    // 拼接去重：后续段的首点与上一段末点对应同一输入点，只留一个。
    if (ci > 0) parsed.removeAt(0);
    correctedGcj.addAll(parsed);
  }
  if (correctedGcj.isEmpty) return null;
  return correctedGcj
      .map((p) => gcjToWgsLocal(p.$1, p.$2))
      .toList();
}

// ---------------------------------------------------------------------------
// 逆地理编码（v3/geocode/regeo，extensions=base）。
// ---------------------------------------------------------------------------

/// 逆地理编码结果：短地名（列表/详情显示）+ 完整格式化地址。
class AmapPlaceName {
  final String shortName;
  final String formattedAddress;
  const AmapPlaceName(this.shortName, this.formattedAddress);
}

/// 由 addressComponent 拼短地名：区县 + 乡镇/街道 + 街道名门牌号，
/// 空段跳过；全空时返回 null（调用方回落 formatted_address）。
String? buildRegeoShortName(Map<String, dynamic> comp) {
  final parts = <String>[];
  for (final k in ['district', 'township']) {
    final v = comp[k];
    if (v is String && v.isNotEmpty) parts.add(v);
  }
  final sn = comp['streetNumber'];
  if (sn is Map<String, dynamic>) {
    final street = sn['street'];
    final number = sn['number'];
    var s = '';
    if (street is String) s += street;
    if (number is String && number.isNotEmpty) s += number;
    if (s.isNotEmpty) parts.add(s);
  }
  if (parts.isEmpty) return null;
  return parts.join(' ');
}

/// 解析逆地理编码回包：status=1 且 regeocode 存在时返回地名，
/// 否则 null。短地名拼不出时用 formatted_address 兜底。
AmapPlaceName? parseRegeoResponse(Map<String, dynamic> json) {
  if (json['status']?.toString() != '1') return null;
  final re = json['regeocode'];
  if (re is! Map<String, dynamic>) return null;
  final formatted = re['formatted_address'];
  final comp = re['addressComponent'];
  var short = comp is Map<String, dynamic> ? buildRegeoShortName(comp) : null;
  short ??= formatted is String && formatted.isNotEmpty ? formatted : null;
  if (short == null) return null;
  return AmapPlaceName(
      short, formatted is String ? formatted : short);
}

/// 单点逆地理编码：WGS-84 入参先经官方接口转 GCJ-02 再调 regeo。
/// 失败返回 null（调用方回落坐标显示）。
Future<AmapPlaceName?> reverseGeocode(
  double lat,
  double lon, {
  String? key,
  AmapJsonFetcher? jsonFetcher,
  HttpClient? httpClient,
}) async {
  final k = key ?? amapWebKey;
  if (k.isEmpty) return null;
  final fetch = jsonFetcher ?? (Uri u) => _defaultJsonFetcher(u, client: httpClient);
  final gcj = await convertWgsToGcj([(lat, lon)],
      key: k, jsonFetcher: fetch, httpClient: httpClient);
  if (gcj == null || gcj.isEmpty) return null;
  final uri = Uri.parse(
      'https://restapi.amap.com/v3/geocode/regeo?key=$k&location=${gcj.first.$2.toStringAsFixed(6)},${gcj.first.$1.toStringAsFixed(6)}&extensions=base');
  final json = await fetch(uri);
  if (json == null) return null;
  return parseRegeoResponse(json);
}

// ---------------------------------------------------------------------------
// 静态地图（v3/staticmap）：分享时才生成，只用于分享卡片，绝不进记录页。
// ---------------------------------------------------------------------------

/// 静态地图图片尺寸（宽*高，接口上限 1024*1024）与高清倍数。
const String kStaticMapSize = '1024*512';
const int kStaticMapScale = 2;

/// 静态地图 URL 长度上限：抽稀与缩点以此为准（接口与服务端对超长
/// GET 的容忍度有限，6000 字符内留足余量）。
const int kStaticMapMaxUrlLength = 6000;

/// 静态地图轨迹简化：道格拉斯-普克容差（米）与最大点数上限。
const double kStaticMapToleranceM = 50;
const int kStaticMapMaxPoints = 150;

/// 道格拉斯-普克简化（迭代实现，避免长轨迹递归栈溢出）。
/// 输入输出均为 (lat, lon)；首尾恒保留。
List<(double lat, double lon)> simplifyPolyline(
    List<(double lat, double lon)> points, double toleranceM) {
  if (points.length <= 2) return List<(double lat, double lon)>.of(points);
  final meanLat =
      points.map((p) => p.$1).reduce((a, b) => a + b) / points.length;
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  double perpDist(int i, int a, int b) {
    final ax = points[a].$2 * math.cos(meanLat * math.pi / 180) * 111320;
    final ay = points[a].$1 * 110540;
    final bx = points[b].$2 * math.cos(meanLat * math.pi / 180) * 111320;
    final by = points[b].$1 * 110540;
    final px = points[i].$2 * math.cos(meanLat * math.pi / 180) * 111320;
    final py = points[i].$1 * 110540;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0;
    var maxI = -1;
    for (var i = a + 1; i < b; i++) {
      final d = perpDist(i, a, b);
      if (d > maxD) {
        maxD = d;
        maxI = i;
      }
    }
    if (maxI >= 0 && maxD > toleranceM) {
      keep[maxI] = true;
      stack.add((a, maxI));
      stack.add((maxI, b));
    }
  }
  final out = <(double lat, double lon)>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

/// 静态图用轨迹抽稀：先道格拉斯-普克，再按步长压到最大点数
/// （首尾恒保留）。纯函数，可单测。
List<(double lat, double lon)> simplifyForStaticMap(
    List<(double lat, double lon)> points) {
  var simplified = simplifyPolyline(points, kStaticMapToleranceM);
  if (simplified.length > kStaticMapMaxPoints) {
    final step =
        (simplified.length / kStaticMapMaxPoints).ceil();
    final capped = <(double lat, double lon)>[];
    for (var i = 0; i < simplified.length; i += step) {
      capped.add(simplified[i]);
    }
    if (capped.last != simplified.last) capped.add(simplified.last);
    simplified = capped;
  }
  return simplified;
}

/// 由包围盒估算静态图 zoom（3~17）：世界宽在 zoom z 时为
/// 256·2^z 像素对应 360 经度；纬度跨度按 1.5 倍折算（与详情页
/// _fitZoom 同口径）。跨度越大 zoom 越小；纯函数，可单测。
int fitZoomForStaticMap({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  int widthPx = 1024,
  int heightPx = 512,
}) {
  final lonSpan = math.max(1e-6, maxLon - minLon);
  final latSpan = math.max(1e-6, maxLat - minLat) * 1.5;
  double zoomFor(double span, int px) =>
      math.log(px * 0.9 * 360 / (256 * span)) / math.ln2;
  final z = math
      .min(zoomFor(lonSpan, widthPx), zoomFor(latSpan, heightPx))
      .floor();
  return z.clamp(3, 17);
}

/// 构建静态地图 URL（纯函数，可单测）：GCJ-02 点列 + 中心 + zoom。
/// paths 为轨迹折线（红、宽 5），markers 为起终点标注（A 红起、B 绿终）。
/// 坐标一律 lon,lat 顺序、小数点后 6 位（接口要求）。
String buildStaticMapUrl({
  required String key,
  required List<(double lat, double lon)> gcjPoints,
  required double centerLat,
  required double centerLon,
  required int zoom,
}) {
  final path = gcjPoints
      .map((p) =>
          '${p.$2.toStringAsFixed(6)},${p.$1.toStringAsFixed(6)}')
      .join(';');
  final start = gcjPoints.first;
  final end = gcjPoints.last;
  final markers =
      'mid,0xFF0000,A:${start.$2.toStringAsFixed(6)},${start.$1.toStringAsFixed(6)}|mid,0x00AA00,B:${end.$2.toStringAsFixed(6)},${end.$1.toStringAsFixed(6)}';
  return 'https://restapi.amap.com/v3/staticmap?key=$key'
      '&location=${centerLon.toStringAsFixed(6)},${centerLat.toStringAsFixed(6)}'
      '&zoom=$zoom&size=$kStaticMapSize&scale=$kStaticMapScale'
      '&paths=5,0xFF0000,1,,:$path'
      '&markers=$markers';
}

/// 静态地图图片全流程：WGS-84 原始点 → 抽稀 → 官方转换 →
/// 建 URL（超长则对半缩点直至起终点）→ 取图。失败返回 null
/// （调用方回落现有分享卡片轨迹，不堵住分享）。
Future<Uint8List?> fetchStaticMapImage(
  List<(double lat, double lon)> wgsPoints, {
  String? key,
  AmapJsonFetcher? jsonFetcher,
  AmapBytesFetcher? bytesFetcher,
  HttpClient? httpClient,
}) async {
  final k = key ?? amapWebKey;
  if (k.isEmpty || wgsPoints.length < 2) return null;
  var pts = simplifyForStaticMap(wgsPoints);
  if (pts.length < 2) return null;
  final gcjAll = await convertWgsToGcj(pts,
      key: k, jsonFetcher: jsonFetcher, httpClient: httpClient);
  if (gcjAll == null || gcjAll.length != pts.length) return null;
  // 注意：缩点时 WGS 点列与 GCJ 点列按同一索引同步缩减。
  var gcj = gcjAll;
  var cur = pts;
  String? url;
  while (true) {
    var minLat = gcj.first.$1,
        maxLat = gcj.first.$1,
        minLon = gcj.first.$2,
        maxLon = gcj.first.$2;
    for (final p in gcj) {
      minLat = math.min(minLat, p.$1);
      maxLat = math.max(maxLat, p.$1);
      minLon = math.min(minLon, p.$2);
      maxLon = math.max(maxLon, p.$2);
    }
    final zoom = fitZoomForStaticMap(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon);
    url = buildStaticMapUrl(
        key: k,
        gcjPoints: gcj,
        centerLat: (minLat + maxLat) / 2,
        centerLon: (minLon + maxLon) / 2,
        zoom: zoom);
    if (url.length <= kStaticMapMaxUrlLength || gcj.length <= 2) break;
    // 对半缩点（首尾恒保留），GCJ 与 WGS 同步。
    final nextGcj = <(double lat, double lon)>[];
    final nextCur = <(double lat, double lon)>[];
    for (var i = 0; i < gcj.length; i += 2) {
      nextGcj.add(gcj[i]);
      nextCur.add(cur[i]);
    }
    if (nextGcj.last != gcj.last) {
      nextGcj.add(gcj.last);
      nextCur.add(cur.last);
    }
    if (nextGcj.length >= gcj.length) break;
    gcj = nextGcj;
    cur = nextCur;
  }
  final fetch =
      bytesFetcher ?? (Uri u) => _defaultBytesFetcher(u, client: httpClient);
  return fetch(Uri.parse(url));
}
