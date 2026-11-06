// v0.1.8 记录页 3D 黑色风格地图（新建文件，不改 refined_map.dart，
// 行程详情页的 RefinedMap 瓦片地图不受影响）。
//
// 风格化示意，非真实建筑/路网、非真实 3D 城市模型：
// 本文件只用 Flutter CustomPainter 自绘，零 pub 插件，不引入任何需要
// API Key 的第三方 3D 地图 SDK，不画任何真实建筑、真实路网数据。
// 画面元素只有：深炭灰底、远处地平线微光、透视网格地面、风格化暗色
// 光晕块、轨迹线、起点/照片点立体标记、场景中心车标。
// v1.0.4 路网：联网时按当前位置周边向 Overpass API（OpenStreetMap
// 道路数据）拉取并缓存道路线，在透视场景里以暗灰细线 + 微弱发光
// 画出（道路暗、轨迹亮）；无网络或无数据时退回现有网格 + 轨迹，
// 并在地图角落小字注明“路网未加载”。不编造道路、不画真实导航图、
// 不恢复瓦片旋转地图。
// v1.2.0 路网：① 4 个 Overpass 镜像由串行改并行竞速（先到者胜、
// 其余 HttpClient 强制关闭），单站连接 5 秒 + 响应 8 秒 + 整站
// 15 秒兜底，最坏约 15 秒（原串行最坏约 100 秒）；失败原因分档
// 不变（离线/超时/繁忙/空结果/其他），缓存机制与 400 米/30 秒门
// 不变。② 道路按 highway 等级分级加粗着色（见 roadStyleForHighway），
// 透视远处有线宽与亮度下限，不再统一细深灰。③ 车标盒由固定
// 56px 改为 3D 52px（纵向 0.90 压扁贴合地面）/ 2D 48px，缩小后
// 不遮挡轨迹。绝不做目的地、路线规划、转向箭头、剩余里程、ETA。
// 轨迹点复用调用方传入的经纬度 + 速度，不改 Recorder 的数据模型。
//
// 路网修复（待发版，不改版本号）：① 查询收敛（600 米 + 仅可行驶
// 等级 + 服务端 12 秒）；② OSM 主站 /map 作 hedged 兜底（Overpass
// 3 秒未胜出才发出，沙箱实测 1 公里 bbox 约 2.6 秒返回）；③ 缓存
// 升级为 v2（含保存时间）+ 邻格回退（本格无缓存时找最近邻格）；
// ④ 失败文案不再被缓存盖住（缓存路网·服务器繁忙），手动重拉
// 先清失败原因。Overpass 各镜像沙箱实测全部不可达（对照站正常），
// 故本次不新增未经验证的镜像；真机结论以用户手机网络为准。
//
// 地理图层：路网之下叠加 OSM 矢量图层——水体（暗蓝填充 + 河流线）、
// 绿地（暗绿填充）、建筑（深灰扁平 footprint，不做 3D 拉伸）、山峰
// （HUD 风格小三角 + 名字/海拔）。整体风格不改：背景、道路分级着
// 色、3D 透视、HUD 字体原样不动；新图层只用暗色调，与道路走同一套
// 投影/透视变换。真实地形起伏阴影（等高线/山体阴影）需要高程数据
// 源，另算独立工程，本批只做山峰标记。图层拉取与路网独立：
// Overpass 拉不到时图层优雅缺失（只显示路网），高德兜底只覆盖主
// 干路、不提供水体与建筑。
//
// 视角：跟随车头的 3D 俯视透视，俯仰角约 60-70 度（地平线在画面
// 约 16% 高处、车标在约 72% 高处，近大远小）；车头朝上为默认跟随
// 模式（headingUp=true 时场景按车头朝向旋转，车标恒朝上；
// headingUp=false 时北向上，车标按朝向旋转）。
// 2D 俯视是同一场景去掉透视的俯视投影，不是瓦片地图。
//
// 性能：投影是 O(n) 的简单三角运算；绘制前按屏幕距离抽稀
// （相邻保留点 < 7px 时跳过，末点恒保留），并做同侧视野裁剪，
// 不每帧全量绘制全部线段；轨迹点再多也不会逐段画到卡顿。
// 回退：调用方角落有 3D 透视 / 2D 俯视切换按钮；3D 渲染异常时
// 用户切 2D 俯视即可继续记录，不卡死（记录流程与本组件无关）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_layers.dart';
import 'native.dart';
import 'perspective_projection.dart';
import 'photo_points.dart';

/// 3D 地图用的最小轨迹点（经纬度 + 时速），调用方由 TrackPoint 映射，
/// 不依赖 models.dart，避免与详情页耦合。
class Recording3dPoint {
  final double lat;
  final double lon;
  final double speedKmh;
  const Recording3dPoint({required this.lat, required this.lon, this.speedKmh = 0});
}

/// v1.0.4：OpenStreetMap 道路线（Overpass API 拉取结果的折线）。
/// v1.2.0：新增 highway 等级（Overpass tags.highway，原样透传，
/// 无 tag 时为空串，旧缓存无 highway 时同样为空串，不编造）。
class RoadWay {
  final List<(double, double)> points; // (lat, lon)
  final String highway;
  const RoadWay(this.points, {this.highway = ''});
}

/// v1.2.0：按 highway 分级的道路绘制样式（纯函数，可单测）。
/// 等级：0 高速/主干、1 次干/支路（secondary/tertiary）、
/// 2 一般道路（residential/unclassified/service/road/未知）、
/// 3 步行类（footway/path/cycleway/pedestrian/track 等）。
/// 等级越低线越粗越亮；min* 为透视远处的可见性下限。
class RoadStyle {
  final int tier;
  final double mainWidth, glowWidth, minMainWidth, minGlowWidth;
  final Color mainColor;
  final double mainAlpha, glowAlpha, minMainAlpha;
  const RoadStyle({
    required this.tier,
    required this.mainWidth,
    required this.glowWidth,
    required this.minMainWidth,
    required this.minGlowWidth,
    required this.mainColor,
    required this.mainAlpha,
    required this.glowAlpha,
    required this.minMainAlpha,
  });
}

int roadTierForHighway(String highway) {
  switch (highway) {
    case 'motorway':
    case 'motorway_link':
    case 'trunk':
    case 'trunk_link':
    case 'primary':
    case 'primary_link':
      return 0;
    case 'secondary':
    case 'secondary_link':
    case 'tertiary':
    case 'tertiary_link':
      return 1;
    case 'footway':
    case 'path':
    case 'cycleway':
    case 'pedestrian':
    case 'track':
    case 'steps':
    case 'corridor':
    case 'bridleway':
    case 'construction':
      return 3;
    default:
      // residential / unclassified / service / road / 未知（''，含旧缓存）
      // / 其他未列名等级一律走一般道路，不断线、不降级到步行类。
      return 2;
  }
}

RoadStyle roadStyleForHighway(String highway) {
  switch (roadTierForHighway(highway)) {
    case 0:
      return const RoadStyle(
        tier: 0, mainWidth: 4.5, glowWidth: 10, minMainWidth: 2.2, minGlowWidth: 4.0,
        mainColor: Color(0xFFEDEDED), mainAlpha: 0.95, glowAlpha: 0.30, minMainAlpha: 0.80,
      );
    case 1:
      return const RoadStyle(
        tier: 1, mainWidth: 3.5, glowWidth: 8, minMainWidth: 1.8, minGlowWidth: 3.0,
        mainColor: Color(0xFFCFCFCF), mainAlpha: 0.90, glowAlpha: 0.24, minMainAlpha: 0.70,
      );
    case 3:
      return const RoadStyle(
        tier: 3, mainWidth: 1.8, glowWidth: 4.5, minMainWidth: 1.1, minGlowWidth: 2.0,
        mainColor: Color(0xFF7A7A7A), mainAlpha: 0.75, glowAlpha: 0.14, minMainAlpha: 0.50,
      );
    default:
      return const RoadStyle(
        tier: 2, mainWidth: 2.5, glowWidth: 6, minMainWidth: 1.4, minGlowWidth: 2.4,
        mainColor: Color(0xFF9A9A9A), mainAlpha: 0.85, glowAlpha: 0.18, minMainAlpha: 0.60,
      );
  }
}

/// v1.2.0：透视线宽 = base * factor，但不低于 min（远处仍可见），
/// factor 为 1 时等于 base；factor 钳制到 [0, 1]。
double roadWidthFor(double baseWidth, double minWidth, double factor) =>
    (baseWidth * factor.clamp(0.0, 1.0)).clamp(minWidth, baseWidth).toDouble();

/// v1.2.0：透视亮度 = base * (0.55 + 0.45 * factor)，但不低于 min；
/// factor 为 1 时等于 base，远处（factor -> 0）仍有 55% 亮度保底
/// 再叠加 min 下限，双重保底。
double roadAlphaFor(double baseAlpha, double minAlpha, double factor) {
  final f = factor.clamp(0.0, 1.0);
  return math.max(baseAlpha * (0.55 + 0.45 * f), minAlpha);
}

/// v1.2.0：并行竞速全部失败时的原因聚合。单站失败原因互不相同
/// 时优先报服务端侧信号（繁忙 > 超时 > 离线 > 其他），因为“设备
/// 离线”若属实各站应一致报离线；混合时单站离线更可能是该镜像
/// 不可达而非整机断网。
String pickRoadErrorKind(List<String> kinds) {
  if (kinds.contains('busy')) return 'busy';
  if (kinds.contains('timeout')) return 'timeout';
  if (kinds.contains('offline')) return 'offline';
  if (kinds.isEmpty) return 'other';
  return kinds.last;
}

/// v1.2.0：Overpass 响应解析（纯函数，可单测，不含网络）。
/// 只取 type=way 且 geometry >= 2 点的折线，highway 取自 tags，
/// 上限 200 条（与旧逻辑一致）。
List<RoadWay> parseOverpassWays(Map<String, dynamic> data) {
  final elements = (data['elements'] as List?) ?? const [];
  final ways = <RoadWay>[];
  for (final e in elements) {
    if (e is! Map || e['type'] != 'way') continue;
    final geom = (e['geometry'] as List?) ?? const [];
    final pts = <(double, double)>[];
    for (final g in geom) {
      if (g is Map && g['lat'] is num && g['lon'] is num) {
        pts.add(((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()));
      }
    }
    if (pts.length < 2) continue;
    final tags = e['tags'];
    final highway = tags is Map && tags['highway'] is String
        ? tags['highway'] as String
        : '';
    ways.add(RoadWay(pts, highway: highway));
  }
  // 不在此处截断：旧 200 条硬截断按回包顺序取，在稠密城区会随机
  // 丢掉车脚下的路（“乱编”感的来源之一）；取舍统一交给
  // [prioritizeRoadWays]（近处 + 主干优先），调用方在拿到中心
  // 点后做，见 fetchRoadWaysAround。
  return ways;
}

/// v1.2.0：缓存序列化（新格式含 highway）。旧格式（纯点列的
/// List）由 roadWaysFromCacheJson 兼容读取，不丢旧缓存。
List<Map<String, Object>> roadWaysToCacheJson(List<RoadWay> ways) => ways
    .map((w) => <String, Object>{
          'highway': w.highway,
          'points': w.points.map((p) => [p.$1, p.$2]).toList(),
        })
    .toList();

List<RoadWay> roadWaysFromCacheJson(dynamic decoded) {
  if (decoded is! List) return const [];
  final ways = <RoadWay>[];
  for (final w in decoded) {
    if (w is Map) {
      // 新格式：{highway, points}。
      final raw = w['points'];
      if (raw is! List) continue;
      final pts = <(double, double)>[];
      for (final p in raw) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
      if (pts.length < 2) continue;
      final highway = w['highway'] is String ? w['highway'] as String : '';
      ways.add(RoadWay(pts, highway: highway));
    } else if (w is List) {
      // 旧格式：纯点列，无 highway。
      final pts = <(double, double)>[];
      for (final p in w) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        }
      }
      if (pts.length >= 2) ways.add(RoadWay(pts));
    }
  }
  return ways;
}

/// 路网修复：Overpass 查询只取可行驶道路等级（步行类、自行车道、
/// 场地内道路全部排除），范围由 1000 米收为 600 米，服务端超时
/// 由 20 秒收为 12 秒——查询越轻，繁忙镜像越可能在客户端 15 秒
/// 兜底前返回。等值多子句写法，不用正则，避免个别镜像对方言
/// 正则支持不一致导致整站 400。
const drivableHighwayClasses = [
  'motorway',
  'motorway_link',
  'trunk',
  'trunk_link',
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
  'road',
];

String buildOverpassQuery(double lat, double lon) {
  final around = 'around:600,${lat.toString()},${lon.toString()}';
  final clauses = drivableHighwayClasses
      .map((c) => 'way["highway"="$c"]($around);')
      .join();
  return '[out:json][timeout:12];($clauses);out geom;';
}

/// 路网修复：失败原因人话映射（纯函数，可单测）。
String roadErrorText(String kind) => switch (kind) {
      'offline' => '无网络',
      'timeout' => '请求超时',
      'busy' => '服务器繁忙',
      'empty' => '周边无道路数据',
      _ => '拉取失败',
    };

/// 路网修复：左上角路网状态文案（纯函数，可单测）。缓存与新失败
/// 同时存在时两者都写明（缓存路网·服务器繁忙），不再用缓存盖住
/// 失败原因；'empty' 不追加（服务端已答复、只是周边无路，缓存
/// 本身仍有效，追加反而误导）。
String roadStatusLabel({
  required bool loaded,
  required bool fromCache,
  required bool neighborCache,
  required bool hasRoads,
  String? errorKind,
  bool fromAmap = false,
}) {
  // v1.2.5：高德兜底路网必须与 OSM 路网在文案上区分（仅主干路，
  // 非全量路网），不能冒充成 OSM 数据。
  if (loaded) return fromAmap ? '路网：高德兜底（仅主干路）' : '路网：OpenStreetMap';
  if (fromCache && hasRoads) {
    final base = neighborCache ? '附近缓存路网' : '缓存路网';
    final suffix = (errorKind != null && errorKind != 'empty')
        ? '·${roadErrorText(errorKind)}'
        : '';
    return '$base$suffix（点按重拉）';
  }
  if (errorKind != null) return '路网：${roadErrorText(errorKind)}（点按重拉）';
  return '路网加载中…（点按重拉）';
}

/// 路网修复：OSM 主站 /map 兜底的 bbox（总宽 0.01 度，约 1 公里，
/// 与缓存分格对齐），顺序为 minlon,minlat,maxlon,maxlat。
String osmApiBbox(double lat, double lon) {
  final minLat = (lat - 0.005).toStringAsFixed(6);
  final maxLat = (lat + 0.005).toStringAsFixed(6);
  final minLon = (lon - 0.005).toStringAsFixed(6);
  final maxLon = (lon + 0.005).toStringAsFixed(6);
  return '$minLon,$minLat,$maxLon,$maxLat';
}

/// 路网修复：OSM 主站 /map XML 解析（纯函数，可单测，零第三方包）。
/// 只取带 highway 标签的 way，用 <nd> 串起节点坐标；节点解析不到
/// 的 way、少于 2 点的 way 丢弃；按等级倒序（步行类先画、高速后
/// 画压在上层），上限 250 条。
List<RoadWay> parseOsmApiMap(String xml) {
  final nodes = <String, (double, double)>{};
  final nodeTag = RegExp(r'<node\s+([^>]*?)>');
  final attr = RegExp(r'(\w+)="([^"]*)"');
  for (final m in nodeTag.allMatches(xml)) {
    final attrs = <String, String>{};
    for (final a in attr.allMatches(m.group(1)!)) {
      attrs[a.group(1)!] = a.group(2)!;
    }
    final id = attrs['id'];
    final lat = double.tryParse(attrs['lat'] ?? '');
    final lon = double.tryParse(attrs['lon'] ?? '');
    if (id != null && lat != null && lon != null) nodes[id] = (lat, lon);
  }
  final ways = <RoadWay>[];
  final wayBlock = RegExp(r'<way\s[^>]*>(.*?)</way>', dotAll: true);
  final ndRef = RegExp(r'<nd\s+ref="(\d+)"');
  final tagTag = RegExp(r'<tag\s+([^>]*?)/>');
  for (final m in wayBlock.allMatches(xml)) {
    final block = m.group(1)!;
    String? highway;
    for (final t in tagTag.allMatches(block)) {
      final attrs = <String, String>{};
      for (final a in attr.allMatches(t.group(1)!)) {
        attrs[a.group(1)!] = a.group(2)!;
      }
      if (attrs['k'] == 'highway') highway = attrs['v'];
    }
    if (highway == null) continue;
    final pts = <(double, double)>[];
    for (final n in ndRef.allMatches(block)) {
      final p = nodes[n.group(1)!];
      if (p != null) pts.add(p);
    }
    if (pts.length >= 2) ways.add(RoadWay(pts, highway: highway));
  }
  ways.sort((a, b) =>
      roadTierForHighway(b.highway).compareTo(roadTierForHighway(a.highway)));
  // 不在此处截断 250 条：取舍统一交给 [prioritizeRoadWays]，避免
  // 按回包顺序硬截断在稠密城区随机丢路；调用方在拿到中心点后做。
  return ways;
}

/// 路网去“乱编”感：回包顺序与距离无关，旧硬截断会在稠密城区
/// 随机丢掉车脚下的路、留下远处的路。取舍规则（纯函数，可单测）：
/// ① 中心 200 米内的路全留；② 高速/主干（tier 0）全留（定向用）；
/// ③ 其余按离中心从近到远补满上限；最后按等级倒序排回绘制顺序
/// （步行先画、高速压上层，与旧绘制顺序一致）。
List<RoadWay> prioritizeRoadWays(List<RoadWay> ways, double lat, double lon,
    [int limit = 400]) {
  if (ways.length <= limit) {
    final sorted = [...ways];
    sorted.sort((a, b) =>
        roadTierForHighway(b.highway).compareTo(roadTierForHighway(a.highway)));
    return sorted;
  }
  final scored =
      ways.map((w) => (w, _wayMinDistM(w.points, lat, lon))).toList();
  final kept = <RoadWay>[];
  final used = <RoadWay>{};
  void add(RoadWay w) {
    if (kept.length < limit && used.add(w)) kept.add(w);
  }

  for (final (w, d) in scored) {
    if (d <= 200) add(w);
  }
  for (final (w, _) in scored) {
    if (roadTierForHighway(w.highway) == 0) add(w);
  }
  final rest = scored.where((e) => !used.contains(e.$1)).toList()
    ..sort((a, b) => a.$2.compareTo(b.$2));
  for (final (w, _) in rest) {
    add(w);
  }
  kept.sort((a, b) =>
      roadTierForHighway(b.highway).compareTo(roadTierForHighway(a.highway)));
  return kept;
}

double _wayMinDistM(List<(double, double)> pts, double lat, double lon) {
  var best = double.infinity;
  for (final (pLat, pLon) in pts) {
    final dx = (pLon - lon) * math.cos(lat * math.pi / 180) * 111320;
    final dy = (pLat - lat) * 110540;
    final d = dx * dx + dy * dy;
    if (d < best) best = d;
  }
  return math.sqrt(best);
}

/// 路网修复：缓存 v2（{v, savedAt, ways}，savedAt 为毫秒 epoch），
/// 旧格式（纯点列 List）由 parseCachedRoads 兼容读取，不丢旧缓存。
class CachedRoads {
  final List<RoadWay> ways;
  final int? savedAtMs;
  const CachedRoads(this.ways, this.savedAtMs);
}

Map<String, Object> roadCacheFileJson(List<RoadWay> ways, int savedAtMs) => {
      'v': 2,
      'savedAt': savedAtMs,
      'ways': roadWaysToCacheJson(ways),
    };

CachedRoads parseCachedRoads(dynamic decoded) {
  if (decoded is Map && decoded['ways'] != null) {
    final saved = decoded['savedAt'];
    return CachedRoads(
      roadWaysFromCacheJson(decoded['ways']),
      saved is int ? saved : null,
    );
  }
  return CachedRoads(roadWaysFromCacheJson(decoded), null);
}

/// 路网修复：缓存分格键（0.01 度一格，约 1 公里），与旧文件命名一致。
String roadCacheCellKey(double lat, double lon) =>
    'road_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}.json';

/// 路网修复：邻格偏移（环序：先 1 格环 8 格，再 2 格环 16 格，
/// 环内按曼哈顿距离），供无本格缓存时找最近的邻格缓存。
List<(int, int)> neighborCellOffsets() {
  final offsets = <(int, int)>[];
  for (var dLat = -2; dLat <= 2; dLat++) {
    for (var dLon = -2; dLon <= 2; dLon++) {
      if (dLat == 0 && dLon == 0) continue;
      offsets.add((dLat, dLon));
    }
  }
  int ring((int, int) o) => o.$1.abs() > o.$2.abs() ? o.$1.abs() : o.$2.abs();
  offsets.sort((a, b) {
    final ra = ring(a), rb = ring(b);
    if (ra != rb) return ra.compareTo(rb);
    final ma = a.$1.abs() + a.$2.abs(), mb = b.$1.abs() + b.$2.abs();
    if (ma != mb) return ma.compareTo(mb);
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    return a.$2.compareTo(b.$2);
  });
  return offsets;
}

/// v1.0.7：Overpass 拉取结果（含失败分档，绝不编造道路）。
class RoadFetchResult {
  final List<RoadWay> ways;
  /// none=成功有数据，empty=成功但周边无道路，offline=无网络，
  /// timeout=超时，busy=服务器繁忙（HTTP 429/502/503/504），other=其他失败。
  final String errorKind;
  /// v1.2.5：数据来源，'osm'（默认，Overpass / OSM 主站）或
  /// 'amap'（高德交通态势兜底，仅主干路，GCJ-02 已转 WGS-84）。
  final String source;
  const RoadFetchResult(this.ways, this.errorKind, {this.source = 'osm'});
}

/// v1.2.5：高德 Web 服务 Key，构建时经 --dart-define=AMAP_KEY 注入；
/// 未注入时为空串，高德兜底禁用；绝不硬编码进源码。
const String amapKey = String.fromEnvironment('AMAP_KEY', defaultValue: '');

/// v1.0.7：按中心点周边向 Overpass 拉取 highway 道路线。
/// v1.2.0：4 个公开镜像并行竞速、先到者胜（成功有数据或成功空
/// 结果都算胜出，与旧串行“空结果即停”语义一致），其余站的
/// HttpClient 强制关闭；全部失败时按 pickRoadErrorKind 聚合原因。
/// 单站：连接 5 秒、响应头 8 秒、响应体 8 秒，整站 15 秒兜底。
/// 失败原因分档不变（offline/timeout/busy/empty/other），调用方如实显示。
/// 路网修复：查询收敛见 buildOverpassQuery；Overpass 3 秒未胜出
/// 时 hedged 起 OSM 主站 /map 兜底（同为 OpenStreetMap 数据，免
/// key；沙箱实测 1 公里 bbox 约 2.6 秒），镜像全部快速失败时不
/// 等 3 秒、直接起兜底；兜底失败也计入原因聚合。
Future<RoadFetchResult> fetchRoadWaysAround(double lat, double lon) async {
  const mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  final query = buildOverpassQuery(lat, lon);
  final completer = Completer<RoadFetchResult>();
  final clients = <HttpClient>[];
  final failures = <String>[];
  var total = mirrors.length;
  var done = 0;
  var fallbackStarted = false;
  var amapStarted = false;
  // 兜底定时器必须可取消：否则 widget 释放时仍有 pending Timer，
  // widget 测试会因此失败（真实 App 里则是无用的空转回调）。
  Timer? fallbackTimer;
  void cancelFallbackTimer() {
    fallbackTimer?.cancel();
    fallbackTimer = null;
  }

  void closeOthers(HttpClient winner) {
    for (final c in clients) {
      if (!identical(c, winner)) c.close(force: true);
    }
  }

  // Dart 局部函数不能前向引用：先声明 late 变量，handleResult 里
  // 调用它，之后再赋值实现（赋值在 handleResult 声明之后，故闭包
  // 内引用 handleResult 合法）。
  late void Function() startFallback;
  late void Function() startAmap;

  void handleResult(HttpClient client, RoadFetchResult result) {
    if (completer.isCompleted) return;
    if (result.ways.isNotEmpty || result.errorKind == 'empty') {
      // 胜出后才按中心点取舍：近处 + 主干优先，不再按回包顺序硬截断。
      // 来源透传：高德兜底胜出时调用方据此区分文案、不写入缓存。
      completer.complete(RoadFetchResult(
          prioritizeRoadWays(result.ways, lat, lon), result.errorKind,
          source: result.source));
      cancelFallbackTimer();
      closeOthers(client);
      return;
    }
    failures.add(result.errorKind);
    done++;
    if (done >= total) {
      if (!fallbackStarted) {
        // 镜像全部快速失败：不等 3 秒，直接起兜底。
        startFallback();
      } else if (!amapStarted && amapKey.isNotEmpty) {
        // v1.2.5：OSM（含 /map 兜底）全失败，最后才试高德兜底；
        // 无 Key 时直接按旧逻辑报失败，不发无 Key 请求。
        amapStarted = true;
        startAmap();
      } else {
        completer.complete(
            RoadFetchResult(const [], pickRoadErrorKind(failures)));
        cancelFallbackTimer();
        closeOthers(client);
      }
    }
  }

  startFallback = () {
    cancelFallbackTimer();
    if (fallbackStarted || completer.isCompleted) return;
    fallbackStarted = true;
    total++;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    clients.add(client);
    _fetchOsmApiRoads(client, lat, lon)
        .timeout(const Duration(seconds: 20),
            onTimeout: () => const RoadFetchResult([], 'timeout'))
        .then((result) => handleResult(client, result));
  };

  // v1.2.5：高德兜底只在 OSM 全失败后起一次；其结果同样走
  // handleResult（胜出透传 source，失败计入原因聚合后报失败）。
  startAmap = () {
    if (completer.isCompleted) return;
    total++;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    clients.add(client);
    _fetchAmapTrafficRoads(client, lat, lon)
        .timeout(const Duration(seconds: 20),
            onTimeout: () => const RoadFetchResult([], 'timeout'))
        .then((result) => handleResult(client, result));
  };

  for (final base in mirrors) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    clients.add(client);
    // 整站 15 秒兜底：任一阶段卡住都不拖过该上限。
    _fetchOneMirror(client, base, query)
        .timeout(const Duration(seconds: 15),
            onTimeout: () => const RoadFetchResult([], 'timeout'))
        .then((result) => handleResult(client, result));
  }
  // Hedged 兜底：Overpass 3 秒未胜出才发出，避免正常情况多一次请求。
  fallbackTimer = Timer(const Duration(seconds: 3), startFallback);
  return completer.future;
}

/// v1.2.0：单站拉取（供并行竞速调用；失败原因分档，不抛异常）。
Future<RoadFetchResult> _fetchOneMirror(
    HttpClient client, String base, String query) async {
  try {
    final req = await client.postUrl(Uri.parse(base));
    req.headers.set('User-Agent', 'DriveTrack');
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write('data=${Uri.encodeQueryComponent(query)}');
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body =
        await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    if (resp.statusCode == 429 ||
        resp.statusCode == 502 ||
        resp.statusCode == 503 ||
        resp.statusCode == 504) {
      return const RoadFetchResult([], 'busy');
    }
    if (resp.statusCode != 200) {
      return const RoadFetchResult([], 'other');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final ways = parseOverpassWays(data);
    return RoadFetchResult(ways, ways.isEmpty ? 'empty' : 'none');
  } on SocketException {
    return const RoadFetchResult([], 'offline');
  } on TimeoutException {
    return const RoadFetchResult([], 'timeout');
  } catch (_) {
    return const RoadFetchResult([], 'other');
  } finally {
    client.close();
  }
}

/// 路网修复：OSM 主站 /map 兜底（bbox 1 公里，只取 highway way，
/// 失败分档与 Overpass 一致，不抛异常）。仅在 Overpass 慢/死时
/// 由 hedged 逻辑触发，不做常规数据源。
Future<RoadFetchResult> _fetchOsmApiRoads(
    HttpClient client, double lat, double lon) async {
  try {
    final uri = Uri.parse(
        'https://api.openstreetmap.org/api/0.6/map?bbox=${osmApiBbox(lat, lon)}');
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent', 'DriveTrack');
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body =
        await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    if (resp.statusCode == 429 ||
        resp.statusCode == 509 ||
        resp.statusCode == 502 ||
        resp.statusCode == 503 ||
        resp.statusCode == 504) {
      return const RoadFetchResult([], 'busy');
    }
    if (resp.statusCode != 200) {
      return const RoadFetchResult([], 'other');
    }
    final ways = parseOsmApiMap(body);
    return RoadFetchResult(ways, ways.isEmpty ? 'empty' : 'none');
  } on SocketException {
    return const RoadFetchResult([], 'offline');
  } on TimeoutException {
    return const RoadFetchResult([], 'timeout');
  } catch (_) {
    return const RoadFetchResult([], 'other');
  } finally {
    client.close();
  }
}

/// v1.2.5：高德交通态势矩形接口的 bbox（与 osmApiBbox 同范围，
/// 约 1 公里），格式为 minLon,minLat;maxLon,maxLat。
String amapTrafficRectangle(double lat, double lon) {
  final minLat = (lat - 0.005).toStringAsFixed(6);
  final maxLat = (lat + 0.005).toStringAsFixed(6);
  final minLon = (lon - 0.005).toStringAsFixed(6);
  final maxLon = (lon + 0.005).toStringAsFixed(6);
  return '$minLon,$minLat;$maxLon,$maxLat';
}

/// v1.2.5：GCJ-02 → WGS-84 逆转换（公开标准近似算法，误差米级；
/// 不是编造数据：高德坐标系与 GPS 坐标系的系统性偏移必须消除，
/// 否则兜底路网会整体偏移几百米）。中国境外直接返回原值。
(double, double) gcj02ToWgs84(double gcjLat, double gcjLon) {
  if (gcjLon < 72.004 ||
      gcjLon > 137.8347 ||
      gcjLat < 0.8293 ||
      gcjLat > 55.8271) {
    return (gcjLat, gcjLon);
  }
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  double transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y * math.pi / 3.0)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y * math.pi / 12.0) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x * math.pi / 3.0)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x * math.pi / 12.0) +
            300 * math.sin(x * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  final dLat = transformLat(gcjLon - 105.0, gcjLat - 35.0);
  final dLon = transformLon(gcjLon - 105.0, gcjLat - 35.0);
  final radLat = gcjLat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final dLatDeg =
      dLat * 180.0 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final dLonDeg =
      dLon * 180.0 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (gcjLat - dLatDeg, gcjLon - dLonDeg);
}

/// v1.2.5：高德交通态势响应解析（纯函数，可单测，不含网络）。
/// 只取 roads[].polyline（GCJ-02 的 lng,lat 串），逐点转 WGS-84；
/// 少于 2 点的折线丢弃；status != '1'、无 roads 时返回空。
/// highway 置空（交通态势不给等级，不冒充分类，绘制走一般道路）。
List<RoadWay> parseAmapTrafficRoads(Map<String, dynamic> data) {
  if (data['status']?.toString() != '1') return const [];
  final traffic = data['trafficinfo'];
  final roads = traffic is Map ? (traffic['roads'] as List?) : null;
  if (roads == null) return const [];
  final ways = <RoadWay>[];
  for (final r in roads) {
    if (r is! Map) continue;
    final polyline = r['polyline'];
    if (polyline is! String) continue;
    final pts = <(double, double)>[];
    for (final pair in polyline.split(';')) {
      final parts = pair.split(',');
      if (parts.length != 2) continue;
      final lng = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lng == null || lat == null) continue;
      pts.add(gcj02ToWgs84(lat, lng));
    }
    if (pts.length >= 2) ways.add(RoadWay(pts));
  }
  return ways;
}

/// v1.2.5：高德交通态势兜底（bbox 约 1 公里，只取主干路折线，
/// 失败分档与 OSM 一致，不抛异常）。仅在 OSM（含 /map 兜底）
/// 全失败时由 fetchRoadWaysAround 触发，不做常规数据源；
/// 无 Key 时不发请求，直接返回 other。
Future<RoadFetchResult> _fetchAmapTrafficRoads(
    HttpClient client, double lat, double lon) async {
  if (amapKey.isEmpty) return const RoadFetchResult([], 'other');
  try {
    final uri = Uri.parse(
        'https://restapi.amap.com/v3/traffic/status/rectangle?rectangle=${amapTrafficRectangle(lat, lon)}&extensions=all&key=$amapKey');
    final req = await client.getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body =
        await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    if (resp.statusCode == 429 ||
        resp.statusCode == 502 ||
        resp.statusCode == 503 ||
        resp.statusCode == 504) {
      return const RoadFetchResult([], 'busy');
    }
    if (resp.statusCode != 200) {
      return const RoadFetchResult([], 'other');
    }
    final ways =
        parseAmapTrafficRoads(jsonDecode(body) as Map<String, dynamic>);
    return RoadFetchResult(ways, ways.isEmpty ? 'empty' : 'none',
        source: 'amap');
  } on SocketException {
    return const RoadFetchResult([], 'offline');
  } on TimeoutException {
    return const RoadFetchResult([], 'timeout');
  } catch (_) {
    return const RoadFetchResult([], 'other');
  } finally {
    client.close();
  }
}

/// v1.0.7：路网缓存文件（按经纬度取 2 位小数分格，约 1km 一格）。
Future<String?> _roadCachePath(double lat, double lon) async {
  try {
    final dir = await Native.getCacheDir();
    return '$dir/${roadCacheCellKey(lat, lon)}';
  } catch (_) {
    return null;
  }
}

Future<CachedRoads?> _readRoadCacheFile(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    final cached = parseCachedRoads(jsonDecode(await f.readAsString()));
    return cached.ways.isEmpty ? null : cached;
  } catch (_) {
    return null;
  }
}

/// 路网修复：先本格、再邻格（环序）找最近的非空缓存；都没有返回空。
Future<({List<RoadWay> ways, int? savedAtMs, bool neighbor})>
    _loadBestCachedRoads(double lat, double lon) async {
  const empty = (ways: <RoadWay>[], savedAtMs: null, neighbor: false);
  try {
    final dir = await Native.getCacheDir();
    final baseLat = double.parse(lat.toStringAsFixed(2));
    final baseLon = double.parse(lon.toStringAsFixed(2));
    String keyFor(int dLat, int dLon) => roadCacheCellKey(
        baseLat + dLat * 0.01, baseLon + dLon * 0.01);
    final self = await _readRoadCacheFile('$dir/${keyFor(0, 0)}');
    if (self != null) {
      return (ways: self.ways, savedAtMs: self.savedAtMs, neighbor: false);
    }
    for (final (dLat, dLon) in neighborCellOffsets()) {
      final hit = await _readRoadCacheFile('$dir/${keyFor(dLat, dLon)}');
      if (hit != null) {
        return (ways: hit.ways, savedAtMs: hit.savedAtMs, neighbor: true);
      }
    }
    return empty;
  } catch (_) {
    return empty;
  }
}

Future<void> _saveCachedRoads(double lat, double lon, List<RoadWay> ways) async {
  try {
    final path = await _roadCachePath(lat, lon);
    if (path == null || ways.isEmpty) return;
    await File(path).writeAsString(jsonEncode(roadCacheFileJson(
        ways, DateTime.now().millisecondsSinceEpoch)));
  } catch (_) {}
}

/// 地理图层拉取结果：ok=true 表示某镜像 HTTP 200 且解析完成
/// （即使周边确实无图层、layers 为空也算成功，调用方据此覆盖旧
/// 图层）；ok=false 表示全部镜像失败，调用方保留旧图层、不记位置。
class LayerFetchResult {
  final MapLayers layers;
  final bool ok;
  const LayerFetchResult(this.layers, this.ok);
}

/// 按中心点周边向 Overpass 拉取地理图层（水体/绿地/建筑/山峰）。
/// 与路网管线独立：同 4 个镜像并行竞速（先成功者胜，成功空结果
/// 同样胜出）、单站连接 5 秒 + 响应 8 秒 + 整站 15 秒兜底；无 hedged
/// /map 兜底、无高德兜底（高德交通态势只给主干路，不提供水体与
/// 建筑）；全部失败返回 ok=false。无 Timer，widget 测试里无
/// pending 回调。
Future<LayerFetchResult> fetchMapLayersAround(double lat, double lon) async {
  const mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.nchc.org.tw/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  final query = buildLayerOverpassQuery(lat, lon);
  final completer = Completer<LayerFetchResult>();
  var failures = 0;
  void handle(LayerFetchResult result) {
    if (completer.isCompleted) return;
    if (result.ok) {
      completer.complete(result);
      return;
    }
    failures++;
    if (failures >= mirrors.length) {
      completer.complete(const LayerFetchResult(MapLayers.empty(), false));
    }
  }

  for (final base in mirrors) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    _fetchOneLayerMirror(client, base, query, lat, lon)
        .timeout(const Duration(seconds: 15),
            onTimeout: () => const LayerFetchResult(MapLayers.empty(), false))
        .then(handle);
  }
  return completer.future;
}

/// 单站图层拉取（供并行竞速调用；失败原因不分档、不抛异常，
/// 调用方只区分成功与失败，失败时图层静默缺失）。
Future<LayerFetchResult> _fetchOneLayerMirror(HttpClient client, String base,
    String query, double lat, double lon) async {
  try {
    final req = await client.postUrl(Uri.parse(base));
    req.headers.set('User-Agent', 'DriveTrack');
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    req.write('data=${Uri.encodeQueryComponent(query)}');
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body =
        await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    if (resp.statusCode == 429 ||
        resp.statusCode == 502 ||
        resp.statusCode == 503 ||
        resp.statusCode == 504) {
      return const LayerFetchResult(MapLayers.empty(), false);
    }
    if (resp.statusCode != 200) {
      return const LayerFetchResult(MapLayers.empty(), false);
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final layers =
        parseOverpassLayers(data, centerLat: lat, centerLon: lon);
    return LayerFetchResult(layers, true);
  } on SocketException {
    return const LayerFetchResult(MapLayers.empty(), false);
  } on TimeoutException {
    return const LayerFetchResult(MapLayers.empty(), false);
  } catch (_) {
    return const LayerFetchResult(MapLayers.empty(), false);
  } finally {
    client.close();
  }
}

/// 地理图层缓存文件：与道路缓存同分格（0.01 度一格），但文件名前
/// 缀不同（layer_ vs road_）且内容版本为 v3，旧缓存绝不串味。
String layerCacheCellKey(double lat, double lon) =>
    'layer_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}.json';

Future<String?> _layerCachePath(double lat, double lon) async {
  try {
    final dir = await Native.getCacheDir();
    return '$dir/${layerCacheCellKey(lat, lon)}';
  } catch (_) {
    return null;
  }
}

Future<MapLayers?> _readLayerCacheFile(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    final layers = mapLayersFromCacheJson(jsonDecode(await f.readAsString()));
    return layers.isEmpty ? null : layers;
  } catch (_) {
    return null;
  }
}

/// 先本格、再邻格（与路网同环序）找最近的非空图层缓存；都没有返回 null。
Future<MapLayers?> _loadBestCachedLayers(double lat, double lon) async {
  try {
    final dir = await Native.getCacheDir();
    final baseLat = double.parse(lat.toStringAsFixed(2));
    final baseLon = double.parse(lon.toStringAsFixed(2));
    String keyFor(int dLat, int dLon) => layerCacheCellKey(
        baseLat + dLat * 0.01, baseLon + dLon * 0.01);
    final self = await _readLayerCacheFile('$dir/${keyFor(0, 0)}');
    if (self != null) return self;
    for (final (dLat, dLon) in neighborCellOffsets()) {
      final hit = await _readLayerCacheFile('$dir/${keyFor(dLat, dLon)}');
      if (hit != null) return hit;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> _saveCachedLayers(
    double lat, double lon, MapLayers layers) async {
  try {
    final path = await _layerCachePath(lat, lon);
    if (path == null || layers.isEmpty) return;
    await File(path).writeAsString(jsonEncode(
        mapLayersToCacheJson(layers, DateTime.now().millisecondsSinceEpoch)));
  } catch (_) {}
}

class Recording3dMap extends StatefulWidget {
  final double centerLat;
  final double centerLon;
  final double headingDeg;
  final List<Recording3dPoint> points;
  final List<PhotoPoint> photoPoints;
  final bool is3d;
  final ValueChanged<bool> onModeChanged;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool headingUp;
  final VoidCallback onCompassTap;
  final Color accentColor;
  final Color vehicleColor;
  // v1.0.2：新 3D 车标画笔（调用方用 markerPainterFor 传入，headingDeg=0，
  // 外层已按朝向旋转，避免双重旋转）；为空时回落旧三角车体。
  final CustomPainter? vehicleMarkerPainter;

  const Recording3dMap({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.headingDeg,
    required this.points,
    this.photoPoints = const [],
    required this.is3d,
    required this.onModeChanged,
    required this.zoom,
    required this.onZoomChanged,
    required this.headingUp,
    required this.onCompassTap,
    required this.accentColor,
    required this.vehicleColor,
    this.vehicleMarkerPainter,
  });

  @override
  State<Recording3dMap> createState() => _Recording3dMapState();
}

class _Recording3dMapState extends State<Recording3dMap> {
  List<RoadWay> _roads = const [];
  bool _roadLoaded = false;
  bool _roadFromCache = false;
  bool _roadNeighborCache = false;
  // v1.2.5：当前显示的路网是否来自高德兜底（仅主干路），文案区分用。
  bool _roadFromAmap = false;
  String? _roadError;
  bool _fetching = false;
  double? _fetchLat;
  double? _fetchLon;
  DateTime? _lastAttempt;
  // 地理图层：与路网独立的状态与门限追踪（路网失败不拖住图层、
  // 图层失败不影响路网；失败不记位置，30 秒后可重试）。
  MapLayers _layers = const MapLayers.empty();
  bool _layersLoaded = false;
  bool _fetchingLayers = false;
  double? _layerFetchLat;
  double? _layerFetchLon;
  DateTime? _layerLastAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetch());
  }

  @override
  void didUpdateWidget(covariant Recording3dMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeFetch();
  }

  double _distM(double lat1, double lon1, double lat2, double lon2) {
    final dx = (lon2 - lon1) * math.cos(lat1 * math.pi / 180) * 111320;
    final dy = (lat2 - lat1) * 110540;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _maybeFetch({bool force = false}) {
    if (!mounted) return;
    if (widget.centerLat == 0 && widget.centerLon == 0) return;
    // 图层与路网独立触发：路网拉取进行中也不挡住图层。
    _maybeFetchLayers(force: force);
    if (_fetching) return;
    // v1.0.7：失败不记 _fetchLat；成功有数据才记位置。静止时只要距
    // 上次尝试超过 30 秒就重试，不再出现“失败一次、400 米内永不重拉”。
    if (!force && _fetchLat != null &&
        _distM(_fetchLat!, _fetchLon!, widget.centerLat, widget.centerLon) <= 400) {
      return;
    }
    if (!force && _lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!) < const Duration(seconds: 30)) {
      return;
    }
    _fetching = true;
    _lastAttempt = DateTime.now();
    final lat = widget.centerLat;
    final lon = widget.centerLon;
    // 先读缓存（本格无缓存时找邻格）：网络不行时也能先显示上次
    // 成功的路网；缓存与新失败并存时文案两者都写明。
    _loadBestCachedRoads(lat, lon).then((cached) {
      if (!mounted) return;
      if (cached.ways.isNotEmpty && !_roadLoaded) {
        setState(() {
          _roads = cached.ways;
          _roadFromCache = true;
          _roadNeighborCache = cached.neighbor;
        });
      }
    });
    fetchRoadWaysAround(lat, lon).then((result) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        if (result.ways.isNotEmpty) {
          _fetchLat = lat;
          _fetchLon = lon;
          _roads = result.ways;
          _roadLoaded = true;
          _roadFromCache = false;
          _roadNeighborCache = false;
          _roadFromAmap = result.source == 'amap';
          _roadError = null;
          // v1.2.5：高德兜底是仅主干路的补充，不写入 OSM 缓存格，
          // 否则日后断网会把主干路当成缓存路网误标。
          if (result.source != 'amap') _saveCachedRoads(lat, lon, result.ways);
        } else {
          // 失败不记 _fetchLat（下次 30 秒后可重试）；成功但无道路时
          // 同样不记位置，避免把“无数据”误当成已拉取。失败原因存
          // 原始分档，文案由 roadStatusLabel 统一映射，不被缓存盖住。
          _roadError = result.errorKind;
          if (!_roadLoaded) {
            _roadFromCache = _roads.isNotEmpty;
            if (_roads.isEmpty) _roadNeighborCache = false;
          }
        }
      });
    });
  }

  /// 地理图层拉取：与路网同一套 400 米 / 30 秒门限，但独立追踪。
  /// 成功（含成功空结果）即覆盖旧图层并记位置；失败保留旧图层、
  /// 不记位置（30 秒后可重试），且图层无状态文案、不干扰路网文案。
  void _maybeFetchLayers({bool force = false}) {
    if (!mounted) return;
    if (_fetchingLayers) return;
    final lat = widget.centerLat;
    final lon = widget.centerLon;
    if (!force && _layerFetchLat != null &&
        _distM(_layerFetchLat!, _layerFetchLon!, lat, lon) <= 400) {
      return;
    }
    if (!force && _layerLastAttempt != null &&
        DateTime.now().difference(_layerLastAttempt!) <
            const Duration(seconds: 30)) {
      return;
    }
    _fetchingLayers = true;
    _layerLastAttempt = DateTime.now();
    // 先读缓存（本格无缓存时找邻格）：网络不行时也能先显示上次
    // 成功的图层；缓存只在首载时应用，避免新格缓存盖掉已显示的
    // 新数据（与路网 _roadLoaded 门一致）。
    _loadBestCachedLayers(lat, lon).then((cached) {
      if (!mounted) return;
      if (cached != null && !_layersLoaded) {
        setState(() => _layers = cached);
      }
    });
    fetchMapLayersAround(lat, lon).then((result) {
      if (!mounted) return;
      setState(() {
        _fetchingLayers = false;
        if (result.ok) {
          _layerFetchLat = lat;
          _layerFetchLon = lon;
          _layers = result.layers;
          _layersLoaded = true;
          if (result.layers.isNotEmpty) {
            _saveCachedLayers(lat, lon, result.layers);
          }
        }
      });
    });
  }

  void _manualRefresh() {
    _fetchLat = null;
    _lastAttempt = null;
    // 手动重拉先清失败原因，重拉过程中文案显示“加载中”，而不是
    // 一直挂着旧失败；已显示的道路（缓存或旧数据）保留不清空。
    setState(() => _roadError = null);
    _maybeFetch(force: true);
  }

  String get _roadLabel => roadStatusLabel(
        loaded: _roadLoaded,
        fromCache: _roadFromCache,
        neighborCache: _roadNeighborCache,
        hasRoads: _roads.isNotEmpty,
        errorKind: _roadError,
        fromAmap: _roadFromAmap,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _Recording3dPainter(
            centerLat: widget.centerLat,
            centerLon: widget.centerLon,
            headingDeg: widget.headingDeg,
            points: widget.points,
            photoPoints: widget.photoPoints,
            roadWays: _roads,
            layers: _layers,
            roadsDimmed: _roadNeighborCache,
            is3d: widget.is3d,
            headingUp: widget.headingUp,
            zoom: widget.zoom,
            accentColor: widget.accentColor,
            vehicleColor: widget.vehicleColor,
            vehicleMarkerPainter: widget.vehicleMarkerPainter,
          ),
        ),
      ),
      // 左上角：路网状态小字，点按可手动重拉；失败原因分档显示，
      // 不再只写“路网未加载”。缓存路网时注明“缓存路网”，邻格
      // 缓存注明“附近缓存路网”，缓存与新失败并存时两者都写明。
      Positioned(
        top: 12,
        left: 12,
        child: GestureDetector(
          onTap: _manualRefresh,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(6))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(_roadLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ),
          ),
        ),
      ),
      // 右上角控制：指南针 / 缩放 / 3D-2D 切换（回退开关）。
      Positioned(
        top: 12,
        right: 12,
        child: Column(children: [
          _ctlButton(
            onTap: widget.onCompassTap,
            child: Transform.rotate(
              angle: widget.headingUp ? -widget.headingDeg * math.pi / 180 : 0,
              child: const Icon(Icons.navigation, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onZoomChanged((widget.zoom + 1).clamp(12, 19)),
            child: const Icon(Icons.add, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onZoomChanged((widget.zoom - 1).clamp(12, 19)),
            child: const Icon(Icons.remove, size: 20, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _ctlButton(
            onTap: () => widget.onModeChanged(!widget.is3d),
            child: Text(widget.is3d ? '3D' : '2D',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
      ),
      // 左下角：风格化声明小字。
      const Positioned(
        left: 12,
        bottom: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(6))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('风格化示意，非真实 3D 城市模型；路网来自 OpenStreetMap',
                style: TextStyle(color: Colors.white54, fontSize: 10)),
          ),
        ),
      ),
    ]);
  }

  Widget _ctlButton({required VoidCallback onTap, required Widget child}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
  }
}

class _Proj {
  final Offset p;
  final double speedKmh;
  final double factor; // 透视缩放因子（2D 时为 1）
  const _Proj(this.p, this.speedKmh, this.factor);
}

class _Recording3dPainter extends CustomPainter {
  final double centerLat, centerLon, headingDeg, zoom;
  final List<Recording3dPoint> points;
  final List<PhotoPoint> photoPoints;
  final List<RoadWay> roadWays;
  final MapLayers layers;

  /// 邻格缓存路网是否正被显示：为 true 时道路画暗一档，与实时
  /// 拉取的路网肉眼可分，避免把 1~2 公里外邻格的路当成本地路。
  final bool roadsDimmed;
  final bool is3d, headingUp;
  final Color accentColor, vehicleColor;
  final CustomPainter? vehicleMarkerPainter;

  _Recording3dPainter({
    required this.centerLat,
    required this.centerLon,
    required this.headingDeg,
    required this.points,
    required this.photoPoints,
    this.roadWays = const [],
    this.layers = const MapLayers.empty(),
    this.roadsDimmed = false,
    required this.is3d,
    required this.headingUp,
    required this.zoom,
    required this.accentColor,
    required this.vehicleColor,
    this.vehicleMarkerPainter,
  });

  // 经纬度 -> 以中心为原点的东/北米制坐标，再按跟随模式转成
  // 前向（forward）/ 右向（right）米制坐标。
  // v1.3.7：投影数学抽到 lib/perspective_projection.dart，
  // 本方法只做委托，公式与常量与旧实现一字相同（3D 回放复用
  // 同一套投影，不另写一套）。
  (double, double) _toForwardRight(double lat, double lon) =>
      forwardRightMeters(
        centerLat: centerLat,
        centerLon: centerLon,
        headingDeg: headingDeg,
        headingUp: headingUp,
        lat: lat,
        lon: lon,
      );

  Offset _project(Size size, double forward, double right, double pxPerM) =>
      perspectiveProject(
        size: size,
        forward: forward,
        right: right,
        pxPerM: pxPerM,
        is3d: is3d,
      );

  double _factorFor(double forward) =>
      perspectiveFactor(forward, is3d: is3d);

  Color _speedColor(double kmh) {
    final t = (kmh / 120).clamp(0.0, 1.0);
    const stops = [
      (0.0, Color(0xFF22D3EE)),
      (0.33, Color(0xFF22C55E)),
      (0.66, Color(0xFFF59E0B)),
      (1.0, Color(0xFFEF4444)),
    ];
    for (var i = 0; i < stops.length - 1; i++) {
      final a = stops[i], b = stops[i + 1];
      if (t <= b.$1) {
        final f = (t - a.$1) / (b.$1 - a.$1);
        return Color.lerp(a.$2, b.$2, f)!;
      }
    }
    return stops.last.$2;
  }

  bool _sameSideOutside(Offset a, Offset b, Size size) {
    const m = 60.0;
    if (a.dx < -m && b.dx < -m) return true;
    if (a.dx > size.width + m && b.dx > size.width + m) return true;
    if (a.dy < -m && b.dy < -m) return true;
    if (a.dy > size.height + m && b.dy > size.height + m) return true;
    return false;
  }

  // 立体标记：底座光晕椭圆 + 阴影椭圆 + 竖杆 + 顶部圆点（不是平面贴图）。
  void _drawMarker(Canvas canvas, Offset p, Color color, double r) {
    final halo = Paint()..color = color.withValues(alpha: 0.25);
    canvas.drawOval(Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.7), width: r * 3.2, height: r * 1.2), halo);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset(p.dx + 2, p.dy + r * 0.9), width: r * 2.2, height: r * 0.8), shadow);
    final stem = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(p.dx, p.dy), Offset(p.dx, p.dy - r * 2.2), stem);
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(p.dx, p.dy - r * 2.2), r * 0.9, dot);
    canvas.drawCircle(Offset(p.dx, p.dy - r * 2.2), r * 0.4, Paint()..color = Colors.white);
  }

  // 静态图层 Picture 缓存：单条目（最新视口），键含尺寸、中心、
  // 朝向、跟随模式、3D/2D、缩放与图层对象身份；视口或图层一变
  // 即重录，静止时复用。Picture 是矢量命令表而非位图，内存有界；
  // 旧图在替换时 dispose（widget 释放时残留一张单图，可接受）。
  static ui.Picture? _staticLayerPicture;
  static String? _staticLayerKey;

  String _staticLayerKeyFor(Size size) =>
      '${size.width}x${size.height}|$centerLat|$centerLon|$headingDeg|$headingUp|$is3d|$zoom|${identityHashCode(layers)}';

  void _drawStaticLayers(Canvas canvas, Size size, double pxPerM) {
    if (layers.isEmpty) return;
    final key = _staticLayerKeyFor(size);
    if (_staticLayerPicture != null && _staticLayerKey == key) {
      canvas.drawPicture(_staticLayerPicture!);
      return;
    }
    final recorder = ui.PictureRecorder();
    _paintLayerGeometries(Canvas(recorder), size, pxPerM);
    final pic = recorder.endRecording();
    _staticLayerPicture?.dispose();
    _staticLayerPicture = pic;
    _staticLayerKey = key;
    canvas.drawPicture(pic);
  }

  /// 绿地 → 水体 → 建筑（与 mapLayerDrawOrder 一致），只画地面
  /// 填充与水体线；山峰标记不在此（量小，直接画在轨迹之后）。
  void _paintLayerGeometries(Canvas canvas, Size size, double pxPerM) {
    // 绿地。
    final greenPaint = Paint()
      ..color = greenFillColor.withValues(alpha: greenFillAlpha)
      ..style = PaintingStyle.fill;
    for (final g in layers.greens) {
      _fillPolygon(canvas, size, g.points, pxPerM, greenPaint);
    }
    // 水体面（evenOdd：岛上不涂水）。
    final waterPaint = Paint()
      ..color = waterFillColor.withValues(alpha: waterFillAlpha)
      ..style = PaintingStyle.fill;
    for (final w in layers.waters) {
      _fillWaterArea(canvas, size, w, pxPerM, waterPaint);
    }
    // 水体线。
    for (final line in layers.waterLines) {
      final proj = <(Offset, double)>[];
      for (final (lat, lon) in line.points) {
        final fr = _toForwardRight(lat, lon);
        proj.add((_project(size, fr.$1, fr.$2, pxPerM), _factorFor(fr.$1)));
      }
      for (var i = 1; i < proj.length; i++) {
        final a = proj[i - 1], b = proj[i];
        if (_sameSideOutside(a.$1, b.$1, size)) continue;
        final factor = (a.$2 + b.$2) / 2;
        canvas.drawLine(
            a.$1,
            b.$1,
            Paint()
              ..color = waterLineColor.withValues(alpha: waterLineAlpha)
              ..strokeWidth =
                  roadWidthFor(waterLineWidth, waterLineMinWidth, factor)
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke);
      }
    }
    // 建筑：缩放/面积门限过滤 + 同侧视野外跳过；只画扁平 footprint。
    final buildingPaint = Paint()
      ..color = buildingFillColor.withValues(alpha: buildingFillAlpha)
      ..style = PaintingStyle.fill;
    for (final b in layers.buildings) {
      if (!buildingVisibleAtZoom(ringAreaM2(b.points, centerLat), zoom)) {
        continue;
      }
      _fillPolygon(canvas, size, b.points, pxPerM, buildingPaint);
    }
  }

  /// 环整体同侧出视野时跳过（有一个点在屏内或环抱屏幕时照常画）。
  bool _polygonOutside(Size size, List<Offset> pts) {
    const m = 60.0;
    var allLeft = true, allRight = true, allTop = true, allBottom = true;
    for (final p in pts) {
      if (p.dx >= -m) allLeft = false;
      if (p.dx <= size.width + m) allRight = false;
      if (p.dy >= -m) allTop = false;
      if (p.dy <= size.height + m) allBottom = false;
    }
    return allLeft || allRight || allTop || allBottom;
  }

  List<Offset> _projectRing(Size size, List<MapPoint> ring, double pxPerM) {
    final out = <Offset>[];
    for (final (lat, lon) in ring) {
      final fr = _toForwardRight(lat, lon);
      out.add(_project(size, fr.$1, fr.$2, pxPerM));
    }
    return out;
  }

  void _fillPolygon(Canvas canvas, Size size, List<MapPoint> ring,
      double pxPerM, Paint paint) {
    if (ring.length < 3) return;
    final pts = _projectRing(size, ring, pxPerM);
    if (_polygonOutside(size, pts)) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _fillWaterArea(Canvas canvas, Size size, WaterArea area, double pxPerM,
      Paint paint) {
    final path = Path()..fillType = PathFillType.evenOdd;
    var drew = false;
    for (final ring in [...area.outers, ...area.inners]) {
      if (ring.length < 3) continue;
      final pts = _projectRing(size, ring, pxPerM);
      if (_polygonOutside(size, pts)) continue;
      path.moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      drew = true;
    }
    if (drew) canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // v1.0.4：深炭灰底（纯黑底除外项，与主框架 #121212 同步）。
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF121212));
    final zoomScale = math.pow(2, zoom - 16).toDouble();
    final pxPerM = (is3d ? size.width / 170 : size.width / 300) * zoomScale;

    // 远处地平线微光 + 风格化暗色光晕（固定屏幕位置的装饰，
    // 不是真实建筑；透视模式下只画在地平线附近）。
    if (is3d) {
      final horizonY = size.height * 0.16;
      final glow = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, accentColor.withValues(alpha: 0.18), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, horizonY - 30, size.width, 60));
      canvas.drawRect(Rect.fromLTWH(0, horizonY - 30, size.width, 60), glow);
    }

    // 透视网格地面（风格化网格线，非路网）。
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    if (is3d) {
      for (final d in [0.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0]) {
        final y = _project(size, d, 0, pxPerM).dy;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
      for (final r in [-200.0, -100.0, -50.0, 0.0, 50.0, 100.0, 200.0]) {
        final path = Path();
        var first = true;
        for (var d = 0.0; d <= 1000; d += 100) {
          final p = _project(size, d, r, pxPerM);
          if (first) {
            path.moveTo(p.dx, p.dy);
            first = false;
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, gridPaint);
      }
    } else {
      // 2D 俯视网格：每 100 米一条线（相对中心，不依赖任何瓦片）。
      for (var m = -400.0; m <= 400; m += 100) {
        canvas.drawLine(Offset(size.width / 2 + m * pxPerM, 0),
            Offset(size.width / 2 + m * pxPerM, size.height), gridPaint);
        canvas.drawLine(Offset(0, size.height / 2 - m * pxPerM),
            Offset(size.width, size.height / 2 - m * pxPerM), gridPaint);
      }
    }

    // 地理图层：绿地 → 水体 → 建筑（见 mapLayerDrawOrder），一律
    // 压在道路之下；静态面进 Picture 缓存（视口变化才重绘，不逐
    // 帧重画全部面），山峰标记量小、直接逐帧画在轨迹之后。
    _drawStaticLayers(canvas, size, pxPerM);

    // v1.2.0 路网：按 highway 等级分级加粗着色（高速/主干更粗
    // 更亮，次干/支路居中，一般/步行类细暗），逐段按透视因子
    // 缩放线宽与亮度但不低于下限，远处压缩处仍可见；道路仍暗
    // 于亮红轨迹带（轨迹在后绘制，压在道路之上）；无数据时
    // 本段自然不画。出视野同侧的段跳过。
    // 邻格缓存时整体画暗一档（alpha × 0.55），与实时路网肉眼可分。
    final dim = roadsDimmed ? 0.55 : 1.0;
    for (final way in roadWays) {
      final style = roadStyleForHighway(way.highway);
      final proj = <(Offset, double)>[];
      for (final (lat, lon) in way.points) {
        final fr = _toForwardRight(lat, lon);
        proj.add((_project(size, fr.$1, fr.$2, pxPerM), _factorFor(fr.$1)));
      }
      for (var i = 1; i < proj.length; i++) {
        final a = proj[i - 1], b = proj[i];
        if (_sameSideOutside(a.$1, b.$1, size)) continue;
        final factor = (a.$2 + b.$2) / 2;
        final glowW = roadWidthFor(style.glowWidth, style.minGlowWidth, factor);
        final mainW = roadWidthFor(style.mainWidth, style.minMainWidth, factor);
        final mainAlpha = roadAlphaFor(style.mainAlpha, style.minMainAlpha, factor);
        canvas.drawLine(
            a.$1,
            b.$1,
            Paint()
              ..color =
                  style.mainColor.withValues(alpha: style.glowAlpha * dim)
              ..strokeWidth = glowW
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke);
        canvas.drawLine(
            a.$1,
            b.$1,
            Paint()
              ..color = style.mainColor.withValues(alpha: mainAlpha * dim)
              ..strokeWidth = mainW
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke);
      }
    }

    // 轨迹：先投影 + 按屏幕距离抽稀，再分段绘制（同侧出视野跳过）。
    final projected = <_Proj>[];
    for (final p in points) {
      final fr = _toForwardRight(p.lat, p.lon);
      projected.add(_Proj(_project(size, fr.$1, fr.$2, pxPerM), p.speedKmh, _factorFor(fr.$1)));
    }
    final kept = <_Proj>[];
    for (var i = 0; i < projected.length; i++) {
      final cur = projected[i];
      if (i == projected.length - 1 || kept.isEmpty || (cur.p - kept.last.p).distance >= 7) {
        kept.add(cur);
      }
    }
    // 发光底：先画一遍宽半透明（红色主色发光感），再画速度渐变色主线。
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 1; i < kept.length; i++) {
        final a = kept[i - 1], b = kept[i];
        if (_sameSideOutside(a.p, b.p, size)) continue;
        final w = pass == 0
            ? (16 * ((a.factor + b.factor) / 2)).clamp(3.0, 18.0).toDouble()
            : (9 * ((a.factor + b.factor) / 2)).clamp(1.5, 10.0).toDouble();
        final paint = Paint()
          ..color = pass == 0 ? Colors.red.withValues(alpha: 0.22) : _speedColor((a.speedKmh + b.speedKmh) / 2)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(a.p, b.p, paint);
      }
    }

    // 山峰标记：HUD 风格小三角 + 名字/海拔（无名无海拔只画三角），
    // 与照片点同级、画在轨迹之后；出视野的跳过。
    for (final peak in layers.peaks) {
      final fr = _toForwardRight(peak.lat, peak.lon);
      final p = _project(size, fr.$1, fr.$2, pxPerM);
      if (p.dx < -40 ||
          p.dx > size.width + 40 ||
          p.dy < -40 ||
          p.dy > size.height + 40) {
        continue;
      }
      final tri = Path()
        ..moveTo(p.dx, p.dy - 8)
        ..lineTo(p.dx - 6, p.dy + 4)
        ..lineTo(p.dx + 6, p.dy + 4)
        ..close();
      canvas.drawPath(
          tri,
          Paint()
            ..color =
                peakTriangleColor.withValues(alpha: peakTriangleAlpha));
      final label = peakLabelText(peak);
      if (label.isEmpty) continue;
      final labelPainter = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(
                color: peakLabelColor, fontSize: peakLabelFontSize)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      labelPainter.paint(
          canvas,
          Offset(p.dx - labelPainter.width / 2,
              p.dy - 8 - labelPainter.height - 2));
    }

    // 起点 / 照片点立体标记（终点即当前车标，不另画）。
    if (projected.isNotEmpty) _drawMarker(canvas, projected.first.p, Colors.greenAccent, 7);
    for (final pp in photoPoints) {
      final fr = _toForwardRight(pp.lat, pp.lon);
      final p = _project(size, fr.$1, fr.$2, pxPerM);
      if (p.dx < -20 || p.dx > size.width + 20 || p.dy < -20 || p.dy > size.height + 20) continue;
      _drawMarker(canvas, p, Colors.amber, 6);
    }

    // 场景中心车标：阴影 + 朝向锥 + 车体（朝向跟随 headingDeg；
    // headingUp 时场景已旋转故车标恒朝上，否则按朝向旋转）。
    // v1.2.0：车标盒不再固定 56px——3D 时 52px 且纵向 0.90 压扁
    // （贴合透视地面、前大后小方向与场景一致），2D 时 48px 方形；
    // 盒子缩小 + 朝向锥减淡（0.25 -> 0.18），轨迹先画、车标后画
    // 但不遮挡轨迹。画笔调用约定不变（headingDeg=0，外层旋转）。
    final veh = is3d ? Offset(size.width / 2, size.height * 0.72) : Offset(size.width / 2, size.height / 2);
    final markerSize = is3d ? 52.0 : 48.0;
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawOval(Rect.fromCenter(center: Offset(veh.dx + 3, veh.dy + 12), width: 40, height: 14), shadow);
    canvas.save();
    canvas.translate(veh.dx, veh.dy);
    canvas.rotate(headingUp ? 0 : headingDeg * math.pi / 180);
    if (is3d) canvas.scale(1.04, 0.90);
    final cone = Path()
      ..moveTo(-12, 6)
      ..lineTo(0, -50)
      ..lineTo(12, 6)
      ..close();
    canvas.drawPath(cone, Paint()..color = accentColor.withValues(alpha: 0.18));
    // v1.0.2：新 3D 车标（画笔版，外层已旋转故画笔朝向为 0）。
    if (vehicleMarkerPainter != null) {
      canvas.save();
      canvas.translate(-markerSize / 2, -markerSize / 2);
      vehicleMarkerPainter!.paint(canvas, Size(markerSize, markerSize));
      canvas.restore();
    } else {
      final body = Path()
        ..moveTo(0, -20)
        ..lineTo(12, 12)
        ..lineTo(6, 18)
        ..lineTo(-6, 18)
        ..lineTo(-12, 12)
        ..close();
      canvas.drawPath(body, Paint()..color = vehicleColor);
      canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Recording3dPainter old) =>
      old.centerLat != centerLat ||
      old.centerLon != centerLon ||
      old.headingDeg != headingDeg ||
      old.roadWays != roadWays ||
      old.layers != layers ||
      old.roadsDimmed != roadsDimmed ||
      old.points != points ||
      old.photoPoints != photoPoints ||
      old.is3d != is3d ||
      old.headingUp != headingUp ||
      old.vehicleMarkerPainter != vehicleMarkerPainter ||
      old.zoom != zoom;
}
