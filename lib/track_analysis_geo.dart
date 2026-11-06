/// v1.3.1（B 路）：赛后分析页卫星底图共用纯逻辑。
///
/// 分析页不能复用编辑页的 [EditorViewTransform]（见
/// lib/track_package_editor.dart 的 satelliteTileScreenRect），
/// 故本文件按自己的 Web Mercator 投影另写落点换算：
/// 轨迹经纬度范围 → 瓦片缩放（[satelliteZoomForMetersPerPixel]）
/// → 瓦片行列范围（[satelliteTileRange]）→ 屏幕坐标。
///
/// 口径：
/// - 瓦片 URL / 换算 / 常量全部复用 lib/satellite_tiles.dart，
///   本文件不另写瓦片 URL 逻辑。
/// - 轨迹只用 GPS 实测点，不插值、不编造；速度取自实测点 speed
///  （m/s → km/h）。
/// - 速度着色用彩虹/热力色阶（蓝→绿→黄→红），卫星底图上白→红
///   可读性差，故不用旧归一化示意图的白→红。
/// - 图例区间取自本节实测最低–最高速度，不得写死固定区间冒充。
/// - 回落门控：瓦片累计失败达到
///   [satelliteFallbackFailureThreshold]（3 张）即回落示意图。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'satellite_tiles.dart';

/// 轨迹经纬度范围（实测点算出）。
typedef GeoBounds = ({
  double minLat,
  double maxLat,
  double minLon,
  double maxLon,
});

/// 由经纬度点列算范围；点不足 2 个或范围退化时返回 null。
GeoBounds? analysisGeoBounds(List<({double lat, double lon})> points) {
  if (points.length < 2) return null;
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLon = points.first.lon;
  var maxLon = points.first.lon;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  if ((maxLat - minLat).abs() < 1e-9 && (maxLon - minLon).abs() < 1e-9) {
    return null;
  }
  return (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon);
}

/// 按画布尺寸与轨迹范围选瓦片缩放：米/像素取横/纵两向中较粗者，
/// 再按 [satelliteMaxTiles] 上限自动降级（超 64 张降一级重算）。
int analysisGeoZoom({
  required GeoBounds bounds,
  required double widthPx,
  required double heightPx,
}) {
  if (widthPx <= 0 || heightPx <= 0) return satelliteMinZoom;
  final midLat = (bounds.minLat + bounds.maxLat) / 2;
  final cosLat = math.cos(midLat * math.pi / 180).abs().clamp(0.01, 1.0);
  final spanXM = (bounds.maxLon - bounds.minLon).abs() * 111320 * cosLat;
  final spanYM = (bounds.maxLat - bounds.minLat).abs() * 110540;
  final mpp = math.max(spanXM / widthPx, spanYM / heightPx);
  var zoom = satelliteZoomForMetersPerPixel(mpp <= 0 ? 10.0 : mpp, midLat);
  while (zoom > satelliteMinZoom) {
    final r = satelliteTileRange(
      minLat: bounds.minLat,
      maxLat: bounds.maxLat,
      minLon: bounds.minLon,
      maxLon: bounds.maxLon,
      zoom: zoom,
    );
    final count = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1);
    if (count <= satelliteMaxTiles) break;
    zoom--;
  }
  return zoom;
}

/// 地理投影：把经纬度落到画布屏幕坐标（等比缩放、居中）。
///
/// 世界像素 = slippy 瓦片坐标 × 256；以瓦片范围左上角为原点，
/// 再按画布等比缩放居中。往返换算见 [unproject]。
class AnalysisGeoProjector {
  final GeoBounds bounds;
  final int zoom;
  final Size size;

  /// 瓦片行列范围（[satelliteTileRange] 算出）。
  final ({int x0, int x1, int y0, int y1}) tileRange;

  /// 世界像素总宽/高（瓦片范围覆盖部分）。
  final double worldWidthPx;
  final double worldHeightPx;

  /// 等比缩放系数与居中偏移。
  final double scale;
  final double offsetX;
  final double offsetY;

  factory AnalysisGeoProjector({
    required GeoBounds bounds,
    required int zoom,
    required Size size,
  }) {
    return AnalysisGeoProjector._(
      bounds: bounds,
      zoom: zoom,
      size: size,
      tileRange: satelliteTileRange(
        minLat: bounds.minLat,
        maxLat: bounds.maxLat,
        minLon: bounds.minLon,
        maxLon: bounds.maxLon,
        zoom: zoom,
      ),
    );
  }

  AnalysisGeoProjector._({
    required this.bounds,
    required this.zoom,
    required this.size,
    required this.tileRange,
  })  : worldWidthPx = (tileRange.x1 - tileRange.x0 + 1) * 256.0,
        worldHeightPx = (tileRange.y1 - tileRange.y0 + 1) * 256.0,
        scale = math.min(
          size.width / ((tileRange.x1 - tileRange.x0 + 1) * 256.0),
          size.height / ((tileRange.y1 - tileRange.y0 + 1) * 256.0),
        ),
        offsetX = (size.width -
                math.min(
                      size.width / ((tileRange.x1 - tileRange.x0 + 1) * 256.0),
                      size.height /
                          ((tileRange.y1 - tileRange.y0 + 1) * 256.0),
                    ) *
                    ((tileRange.x1 - tileRange.x0 + 1) * 256.0)) /
            2,
        offsetY = (size.height -
                math.min(
                      size.width / ((tileRange.x1 - tileRange.x0 + 1) * 256.0),
                      size.height /
                          ((tileRange.y1 - tileRange.y0 + 1) * 256.0),
                    ) *
                    ((tileRange.y1 - tileRange.y0 + 1) * 256.0)) /
            2;

  /// 经纬度 → 屏幕坐标。
  Offset project(double lat, double lon) {
    final wx = satelliteTileX(lon, zoom) * 256 - tileRange.x0 * 256;
    final wy = satelliteTileY(lat, zoom) * 256 - tileRange.y0 * 256;
    return Offset(offsetX + wx * scale, offsetY + wy * scale);
  }

  /// 屏幕坐标 → 经纬度（[project] 的逆运算，用于往返测试）。
  /// 用分数瓦片坐标直接反算（[satelliteTileWestLon] /
  /// [satelliteTileNorthLat] 只接受整数瓦片号，此处不适用）。
  ({double lat, double lon}) unproject(Offset offset) {
    final wx = (offset.dx - offsetX) / scale + tileRange.x0 * 256;
    final wy = (offset.dy - offsetY) / scale + tileRange.y0 * 256;
    final n = math.pow(2, zoom).toDouble();
    final lon = wx / 256 / n * 360 - 180;
    final m = math.pi * (1 - 2 * (wy / 256) / n);
    final lat =
        180 / math.pi * math.atan(0.5 * (math.exp(m) - math.exp(-m)));
    return (lat: lat, lon: lon);
  }

  /// 某瓦片在画布上的屏幕矩形（Positioned 拼贴用）。
  Rect tileScreenRect(int x, int y) {
    final left = offsetX + (x - tileRange.x0) * 256 * scale;
    final top = offsetY + (y - tileRange.y0) * 256 * scale;
    return Rect.fromLTWH(left, top, 256 * scale, 256 * scale);
  }
}

/// 速度（km/h）→ 彩虹/热力色：蓝→绿→黄→红。
///
/// 最低 = 最高时无区间可分，退化为中间色（黄），不除以零、不冒充
/// 渐变。
Color speedToRainbowColor(double speedKmh, double minKmh, double maxKmh) {
  if (maxKmh <= minKmh) return const Color(0xFFFACC15);
  final t = ((speedKmh - minKmh) / (maxKmh - minKmh)).clamp(0.0, 1.0);
  const stops = <Color>[
    Color(0xFF2563EB), // 蓝：低速
    Color(0xFF22C55E), // 绿
    Color(0xFFFACC15), // 黄
    Color(0xFFE10600), // 红：高速
  ];
  final scaled = t * (stops.length - 1);
  final i = scaled.floor().clamp(0, stops.length - 2);
  final f = scaled - i;
  return Color.lerp(stops[i], stops[i + 1], f) ?? stops[i];
}

/// 图例一段：起止速度（km/h）与对应色块颜色。
typedef SpeedLegendSegment = ({double fromKmh, double toKmh, Color color});

/// 按实测最低–最高速度四等分图例；最低 = 最高时只给一段。
List<SpeedLegendSegment> speedLegendSegments(double minKmh, double maxKmh) {
  if (maxKmh <= minKmh) {
    return [
      (fromKmh: minKmh, toKmh: maxKmh, color: const Color(0xFFFACC15)),
    ];
  }
  final step = (maxKmh - minKmh) / 4;
  return [
    for (var i = 0; i < 4; i++)
      (
        fromKmh: minKmh + step * i,
        toKmh: minKmh + step * (i + 1),
        color: speedToRainbowColor(minKmh + step * (i + 0.5), minKmh, maxKmh),
      ),
  ];
}

/// 回落门控：瓦片累计失败数达到阈值即切示意图。
bool shouldFallbackToSchematic(int failureCount) =>
    failureCount >= satelliteFallbackFailureThreshold;
