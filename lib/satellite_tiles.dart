/// 卫星瓦片共用模块（Esri World Imagery，免 Key 公开影像瓦片）。
///
/// 从 lib/track_package_editor.dart 抽出：编辑页与分析页共用同一套
/// 常量与纯函数，不再各写一套。
///
/// 口径（与编辑页原实现一字不动）：
/// - 瓦片源：Esri World Imagery（https://server.arcgisonline.com，
///   免 Key；2026-11-05 沙箱 curl 核对瓦片返回 200 / image/jpeg）。
/// - 换算为 Web Mercator slippy-map（与 widgets.dart 的 DarkTileMap
///   同口径）。
/// - [satelliteTilesForBounds] 与 [satelliteTileScreenRect] 不在此
///   文件：前者拼瓦片列表、后者依赖编辑页的 EditorViewTransform，
///   仍留在 lib/track_package_editor.dart。

import 'dart:math' as math;

/// 卫星影像来源署名（开关行开启时显示）。
const String satelliteTileAttribution = '影像 © Esri World Imagery';

/// 卫星瓦片缩放范围（Esri World Imagery 常用范围）。
const int satelliteMinZoom = 10;
const int satelliteMaxZoom = 19;

/// 单次视图最多拼的瓦片数；超限时自动降一级缩放重算。
const int satelliteMaxTiles = 64;

/// 回落阈值：累计失败瓦片达到该数即判卫星图未加载，回落示意图。
const int satelliteFallbackFailureThreshold = 3;

/// Esri World Imagery 瓦片 URL（注意 Esri 顺序为 z/y/x）。
String satelliteTileUrl(int z, int x, int y) =>
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x';

/// Web Mercator slippy-map 换算（与 widgets.dart 的 DarkTileMap 同口径）。
double satelliteTileX(double lon, int z) => (lon + 180) / 360 * math.pow(2, z);

double satelliteTileY(double lat, int z) {
  final r = lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * math.pow(2, z);
}

/// 瓦片西边经度 / 北边纬度（瓦片角点反算）。
double satelliteTileWestLon(int x, int z) => x / math.pow(2, z) * 360 - 180;

double satelliteTileNorthLat(int y, int z) {
  final n = math.pi * (1 - 2 * y / math.pow(2, z));
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

/// 按画布米 / 像素选瓦片缩放：取瓦片分辨率不粗于画布的那一级
///（瓦片米 / 像素 = 156543.03392 × cos(纬度) / 2^z），钳制到
/// [satelliteMinZoom]–[satelliteMaxZoom]。
int satelliteZoomForMetersPerPixel(double metersPerPixel, double latitude) {
  if (!metersPerPixel.isFinite || metersPerPixel <= 0) {
    return satelliteMinZoom;
  }
  final cosLat = math.cos(latitude * math.pi / 180).abs().clamp(0.01, 1.0);
  final z = (math.log(156543.03392 * cosLat / metersPerPixel) / math.ln2).ceil();
  return z.clamp(satelliteMinZoom, satelliteMaxZoom);
}

/// 可见经纬度范围覆盖的瓦片行列范围（x、y 均已钳制到合法范围）。
({int x0, int x1, int y0, int y1}) satelliteTileRange({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  required int zoom,
}) {
  final n = 1 << zoom;
  final x0 = satelliteTileX(minLon, zoom).floor().clamp(0, n - 1);
  final x1 = satelliteTileX(maxLon, zoom).floor().clamp(0, n - 1);
  final y0 = satelliteTileY(maxLat, zoom).floor().clamp(0, n - 1);
  final y1 = satelliteTileY(minLat, zoom).floor().clamp(0, n - 1);
  return (x0: x0, x1: x1, y0: y0, y1: y1);
}
