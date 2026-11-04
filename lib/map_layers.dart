// 街道模式记录页自绘地图的地理矢量图层：水体 / 绿地 / 建筑 / 山峰。
//
// 只加矢量图层，不换底图、不引瓦片、不做 3D 拉伸：
// - 水体：OSM natural=water、landuse=reservoir、waterway=riverbank 的面，
//   以及 waterway=river/stream 的线；relation 多边形的外环与内环齐全时
//   用 evenOdd 填充（岛上不涂水）。
// - 绿地：leisure=park、landuse=forest/meadow/grass/village_green/
//   recreation_ground 的面。
// - 建筑：building=* 的面，只画扁平 footprint；市区量大，解析时按
//   离中心距离取舍上限，绘制时按缩放/面积门限跳过小 footprint。
// - 山峰：natural=peak 的点，画 HUD 风格小三角 + 名字/海拔文字。
// - 真实地形起伏阴影（等高线 / 山体阴影）需要高程数据源，是另一件
//   大工程，本批不做，只做山峰标记。
//
// 本文件只含纯模型、解析、样式与几何工具，不含网络与 widget；
// 网络拉取与缓存文件读写在 recording_3d_map.dart，绘制在同文件的
// _Recording3dPainter 里。样式全部是暗色调，与现有 #121212 深炭灰
// 底、灰色分级道路协调，不许出现标准地图那种亮色。
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 图层点列：(lat, lon)，与 RoadWay 约定一致。
typedef MapPoint = (double, double);

/// 水体面：外环 + 内环（岛）。way 来源只有外环；relation 来源
/// 外环与内环齐全，绘制时用 evenOdd 填充。
class WaterArea {
  final List<List<MapPoint>> outers;
  final List<List<MapPoint>> inners;
  const WaterArea({required this.outers, this.inners = const []});
  bool get isEmpty => outers.isEmpty;
}

/// 水体线：河流 / 溪流（waterway=river/stream），按线画，不填面。
class WaterLine {
  final List<MapPoint> points;
  const WaterLine(this.points);
}

/// 建筑 / 绿地通用面（无内环；建筑内院、绿地水体洞一律忽略，不挖洞）。
class MapPolygon {
  final List<MapPoint> points;
  const MapPolygon(this.points);
}

/// 山峰点：name 可能为空，eleM 可能为空（无 ele 标签时不编造海拔）。
class MapPeak {
  final double lat;
  final double lon;
  final String name;
  final double? eleM;
  const MapPeak({
    required this.lat,
    required this.lon,
    this.name = '',
    this.eleM,
  });
}

/// 一组地理图层。空对象表示“无图层”（未拉取到或周边确实没有），
/// 与“拉取失败保留旧图层”由调用方区分，本类型不承载失败状态。
class MapLayers {
  final List<WaterArea> waters;
  final List<WaterLine> waterLines;
  final List<MapPolygon> greens;
  final List<MapPolygon> buildings;
  final List<MapPeak> peaks;
  const MapLayers({
    this.waters = const [],
    this.waterLines = const [],
    this.greens = const [],
    this.buildings = const [],
    this.peaks = const [],
  });
  const MapLayers.empty()
      : waters = const [],
        waterLines = const [],
        greens = const [],
        buildings = const [],
        peaks = const [];

  bool get isEmpty =>
      waters.isEmpty &&
      waterLines.isEmpty &&
      greens.isEmpty &&
      buildings.isEmpty &&
      peaks.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

// ---------------------------------------------------------------------------
// 样式：暗色调常量（可单测；绘制层直接引用，不在绘制处现写色值）。
// ---------------------------------------------------------------------------

/// 水体填充：暗蓝，压在道路层之下、绿地之上。
const Color waterFillColor = Color(0xFF1E3E5C);
const double waterFillAlpha = 0.80;

/// 水体线：稍亮的暗蓝描边。
const Color waterLineColor = Color(0xFF3A6A94);
const double waterLineAlpha = 0.70;
const double waterLineWidth = 2.0;
const double waterLineMinWidth = 1.0;

/// 建筑 footprint：深灰，比底色 #121212 稍亮、比道路灰暗。
const Color buildingFillColor = Color(0xFF2A2A30);
const double buildingFillAlpha = 0.90;

/// 绿地填充：暗绿，压在道路层之下、水体之下。
const Color greenFillColor = Color(0xFF1E3A26);
const double greenFillAlpha = 0.75;

/// 山峰三角：近白灰；名字 / 海拔文字：白 70%、10px，与左上角
/// 路网状态小字（白 54%、10px）同一字号体系。
const Color peakTriangleColor = Color(0xFFE8E8E8);
const double peakTriangleAlpha = 0.90;
const Color peakLabelColor = Colors.white70;
const double peakLabelFontSize = 10;

/// 图层绘制顺序（绿地 → 水体 → 建筑 → 道路 → 山峰标记）：
/// 水体与绿地、建筑一律压在道路之下；山峰是 HUD 风格小标记，
/// 与照片点同级，画在轨迹之后。绘制代码必须按此顺序，不得调换。
enum MapLayerKind { green, water, building, road, peak }

const List<MapLayerKind> mapLayerDrawOrder = [
  MapLayerKind.green,
  MapLayerKind.water,
  MapLayerKind.building,
  MapLayerKind.road,
  MapLayerKind.peak,
];

// ---------------------------------------------------------------------------
// Overpass 查询：与道路查询同口径（600 米、服务端 12 秒、等值子句，
// 不用正则，避免个别镜像对方言正则支持不一致导致整站 400）。
// ---------------------------------------------------------------------------

const _greenLanduses = [
  'forest',
  'meadow',
  'grass',
  'village_green',
  'recreation_ground',
];

String buildLayerOverpassQuery(double lat, double lon) {
  final around = 'around:600,${lat.toString()},${lon.toString()}';
  final clauses = <String>[
    // 水体面。
    'way["natural"="water"]($around);',
    'way["landuse"="reservoir"]($around);',
    'way["waterway"="riverbank"]($around);',
    // 水体线。
    'way["waterway"="river"]($around);',
    'way["waterway"="stream"]($around);',
    // 建筑面（key-only 子句，任意 building=* 值都算）。
    'way["building"]($around);',
    // 绿地面。
    'way["leisure"="park"]($around);',
    for (final lu in _greenLanduses) 'way["landuse"="$lu"]($around);',
    // 山峰点。
    'node["natural"="peak"]($around);',
    // 水体 relation（大湖常以多边形 relation 存在，只取外环与内环）。
    'relation["natural"="water"]($around);',
    'relation["landuse"="reservoir"]($around);',
  ];
  return '[out:json][timeout:12];(${clauses.join()});out geom;';
}

// ---------------------------------------------------------------------------
// 解析：Overpass JSON → MapLayers（纯函数，可单测，不含网络）。
// ---------------------------------------------------------------------------

/// 建筑解析上限：与道路上限 400 条同口径；超限时按离中心距离取舍
/// （近处优先），避免稠密城区回包几千栋建筑拖垮解析与绘制。
const int maxBuildings = 400;

/// 面环点数上限：建筑环通常不到 20 点，湖岸与绿地环可能上百点；
/// 超限按步长抽稀（保持闭合），避免逐点投影拖垮绘制。
const int maxBuildingRingPoints = 48;
const int maxAreaRingPoints = 256;

List<MapPoint> _geomPoints(Map element) {
  final geom = (element['geometry'] as List?) ?? const [];
  final pts = <MapPoint>[];
  for (final g in geom) {
    if (g is Map && g['lat'] is num && g['lon'] is num) {
      pts.add(((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()));
    }
  }
  return pts;
}

/// 闭合环：首尾不相等时补首点；不足 3 点不成面，返回原列。
List<MapPoint> closeRing(List<MapPoint> pts) {
  if (pts.length < 3) return pts;
  if (pts.first != pts.last) return [...pts, pts.first];
  return pts;
}

/// 步长抽稀：超限时按步长取点（保持闭合）；未超限原样返回。
List<MapPoint> simplifyRing(List<MapPoint> ring, int maxPoints) {
  if (ring.length <= maxPoints) return ring;
  final closed = ring.length >= 2 && ring.first == ring.last;
  final body = closed ? ring.sublist(0, ring.length - 1) : ring;
  final step = (body.length / maxPoints).ceil();
  final out = <MapPoint>[];
  for (var i = 0; i < body.length; i += step) {
    out.add(body[i]);
  }
  if (closed) out.add(out.first);
  return out;
}

/// ele 标签解析：纯数字直接取；带单位（如 "1234 m"）取前导数字；
/// 无法解析返回 null，不编造海拔。
double? parseEleTag(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  final direct = double.tryParse(trimmed);
  if (direct != null) return direct;
  final m = RegExp(r'^-?\d+(\.\d+)?').firstMatch(trimmed);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// 山峰标记文字：名 + 海拔（有则拼 "名 1234m"）；两者皆无返回空串，
/// 绘制时只画三角、不画文字。
String peakLabelText(MapPeak peak) {
  final name = peak.name.trim();
  final ele = peak.eleM == null ? '' : '${peak.eleM!.round()}m';
  if (name.isEmpty) return ele;
  if (ele.isEmpty) return name;
  return '$name $ele';
}

double _pointDistM(MapPoint p, double lat, double lon) {
  final dx = (p.$2 - lon) * math.cos(lat * math.pi / 180) * 111320;
  final dy = (p.$1 - lat) * 110540;
  return math.sqrt(dx * dx + dy * dy);
}

double _ringMinDistM(List<MapPoint> ring, double lat, double lon) {
  var best = double.infinity;
  for (final p in ring) {
    final d = _pointDistM(p, lat, lon);
    if (d < best) best = d;
  }
  return best;
}

/// 建筑取舍（纯函数，可单测）：超限时按离中心最近优先保留；
/// 未超限原样返回。无中心点时按回包顺序截断。
List<MapPolygon> capBuildings(
    List<MapPolygon> buildings, double? lat, double? lon,
    [int limit = maxBuildings]) {
  if (buildings.length <= limit) return buildings;
  if (lat == null || lon == null) return buildings.sublist(0, limit);
  final sorted = [...buildings];
  sorted.sort((a, b) => _ringMinDistM(a.points, lat, lon)
      .compareTo(_ringMinDistM(b.points, lat, lon)));
  return sorted.sublist(0, limit);
}

MapLayers parseOverpassLayers(Map<String, dynamic> data,
    {double? centerLat, double? centerLon}) {
  final waters = <WaterArea>[];
  final waterLines = <WaterLine>[];
  final greens = <MapPolygon>[];
  final buildings = <MapPolygon>[];
  final peaks = <MapPeak>[];
  final elements = (data['elements'] as List?) ?? const [];
  for (final e in elements) {
    if (e is! Map) continue;
    final type = e['type'];
    final tags = e['tags'];
    final tagMap = tags is Map ? tags : const {};
    if (type == 'node') {
      // 山峰点：node 自带 lat/lon，不走 geometry。
      if (tagMap['natural'] != 'peak') continue;
      final lat = e['lat'];
      final lon = e['lon'];
      if (lat is! num || lon is! num) continue;
      final name = tagMap['name'];
      peaks.add(MapPeak(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        name: name is String ? name : '',
        eleM: parseEleTag(tagMap['ele'] is String ? tagMap['ele'] as String : null),
      ));
      continue;
    }
    if (type == 'way') {
      final pts = _geomPoints(e);
      final natural = tagMap['natural'];
      final landuse = tagMap['landuse'];
      final waterway = tagMap['waterway'];
      final leisure = tagMap['leisure'];
      if (natural == 'water' || landuse == 'reservoir' || waterway == 'riverbank') {
        // 水体面。
        if (pts.length < 3) continue;
        final ring = simplifyRing(closeRing(pts), maxAreaRingPoints);
        waters.add(WaterArea(outers: [ring]));
      } else if (waterway == 'river' || waterway == 'stream') {
        // 水体线。
        if (pts.length < 2) continue;
        waterLines.add(WaterLine(pts));
      } else if (tagMap.containsKey('building')) {
        // 建筑面（任意 building=* 值）。
        if (pts.length < 3) continue;
        buildings.add(MapPolygon(simplifyRing(closeRing(pts), maxBuildingRingPoints)));
      } else if (leisure == 'park' || _greenLanduses.contains(landuse)) {
        // 绿地面。
        if (pts.length < 3) continue;
        greens.add(MapPolygon(simplifyRing(closeRing(pts), maxAreaRingPoints)));
      }
      // 其他 way（道路等）一律忽略：图层查询只取本文件关心的标签，
      // 道路仍由道路管线负责，不在此处重复。
      continue;
    }
    if (type == 'relation') {
      // 水体 relation：只认外环与内环 way 成员；无外环不成面。
      final natural = tagMap['natural'];
      final landuse = tagMap['landuse'];
      if (natural != 'water' && landuse != 'reservoir') continue;
      final members = (e['members'] as List?) ?? const [];
      final outers = <List<MapPoint>>[];
      final inners = <List<MapPoint>>[];
      for (final m in members) {
        if (m is! Map || m['type'] != 'way') continue;
        final pts = _geomPoints(m);
        if (pts.length < 3) continue;
        final ring = simplifyRing(closeRing(pts), maxAreaRingPoints);
        if (m['role'] == 'inner') {
          inners.add(ring);
        } else if (m['role'] == 'outer') {
          outers.add(ring);
        }
      }
      if (outers.isNotEmpty) waters.add(WaterArea(outers: outers, inners: inners));
      continue;
    }
  }
  return MapLayers(
    waters: waters,
    waterLines: waterLines,
    greens: greens,
    buildings: capBuildings(buildings, centerLat, centerLon),
    peaks: peaks,
  );
}

// ---------------------------------------------------------------------------
// 几何工具（纯函数，可单测）。
// ---------------------------------------------------------------------------

/// 环面积（平方米，球面近似：经纬度转米制后鞋带公式；以环首点为
/// 原点，避免绝对坐标大数相减的精度损失）。
double ringAreaM2(List<MapPoint> ring, double refLat) {
  if (ring.length < 3) return 0;
  final kx = math.cos(refLat * math.pi / 180) * 111320;
  const ky = 110540.0;
  final ox = ring.first.$2 * kx;
  final oy = ring.first.$1 * ky;
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ax = a.$2 * kx - ox;
    final ay = a.$1 * ky - oy;
    final bx = b.$2 * kx - ox;
    final by = b.$1 * ky - oy;
    sum += ax * by - bx * ay;
  }
  return sum.abs() / 2;
}

/// 建筑绘制门限：缩得越远，只画越大的 footprint，避免市区成千
/// 上万个小面拖垮绘制。zoom 为 widget 的 zoom（12~19）。
bool buildingVisibleAtZoom(double areaM2, double zoom) {
  if (zoom >= 17) return true;
  if (zoom >= 16) return areaM2 >= 60;
  if (zoom >= 15) return areaM2 >= 150;
  if (zoom >= 14) return areaM2 >= 400;
  return areaM2 >= 900;
}

// ---------------------------------------------------------------------------
// 缓存序列化：图层缓存 v3（{v, savedAt, waters, waterLines, greens,
// buildings, peaks}），与道路缓存 v2 文件名不同（layer_*.json vs
// road_*.json）且版本号不同，旧缓存绝不串味。v != 3 一律作废。
// ---------------------------------------------------------------------------

const int layerCacheVersion = 3;

List<List<double>> _pointsToJson(List<MapPoint> pts) =>
    pts.map((p) => [p.$1, p.$2]).toList();

List<MapPoint> _pointsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final pts = <MapPoint>[];
  for (final p in raw) {
    if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
      pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
    }
  }
  return pts;
}

List<List<MapPoint>> _ringsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  final rings = <List<MapPoint>>[];
  for (final r in raw) {
    final pts = _pointsFromJson(r);
    if (pts.length >= 3) rings.add(pts);
  }
  return rings;
}

Map<String, Object> mapLayersToCacheJson(MapLayers layers, int savedAtMs) => {
      'v': layerCacheVersion,
      'savedAt': savedAtMs,
      'waters': layers.waters
          .map((w) => {
                'o': w.outers.map(_pointsToJson).toList(),
                'i': w.inners.map(_pointsToJson).toList(),
              })
          .toList(),
      'waterLines': layers.waterLines.map((l) => _pointsToJson(l.points)).toList(),
      'greens': layers.greens.map((g) => _pointsToJson(g.points)).toList(),
      'buildings': layers.buildings.map((b) => _pointsToJson(b.points)).toList(),
      'peaks': layers.peaks
          .map((p) => {
                'lat': p.lat,
                'lon': p.lon,
                'name': p.name,
                if (p.eleM != null) 'ele': p.eleM,
              })
          .toList(),
    };

MapLayers mapLayersFromCacheJson(dynamic decoded) {
  if (decoded is! Map || decoded['v'] != layerCacheVersion) {
    return const MapLayers.empty();
  }
  final waters = <WaterArea>[];
  final rawWaters = decoded['waters'];
  if (rawWaters is List) {
    for (final w in rawWaters) {
      if (w is! Map) continue;
      final outers = _ringsFromJson(w['o']);
      if (outers.isEmpty) continue;
      waters.add(WaterArea(outers: outers, inners: _ringsFromJson(w['i'])));
    }
  }
  List<WaterLine> linesFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <WaterLine>[];
    for (final l in raw) {
      final pts = _pointsFromJson(l);
      if (pts.length >= 2) out.add(WaterLine(pts));
    }
    return out;
  }

  List<MapPolygon> polysFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <MapPolygon>[];
    for (final p in raw) {
      final pts = _pointsFromJson(p);
      if (pts.length >= 3) out.add(MapPolygon(pts));
    }
    return out;
  }

  final peaks = <MapPeak>[];
  final rawPeaks = decoded['peaks'];
  if (rawPeaks is List) {
    for (final p in rawPeaks) {
      if (p is! Map) continue;
      final lat = p['lat'];
      final lon = p['lon'];
      if (lat is! num || lon is! num) continue;
      final ele = p['ele'];
      peaks.add(MapPeak(
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        name: p['name'] is String ? p['name'] as String : '',
        eleM: ele is num ? ele.toDouble() : null,
      ));
    }
  }
  return MapLayers(
    waters: waters,
    waterLines: linesFrom(decoded['waterLines']),
    greens: polysFrom(decoded['greens']),
    buildings: polysFrom(decoded['buildings']),
    peaks: peaks,
  );
}
