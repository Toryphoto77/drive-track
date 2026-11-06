/// v1.3.7：3D 透视投影共享纯函数。
///
/// 来源：从 `lib/recording_3d_map.dart` 的 `_Recording3dPainter`
/// 私有方法原样抽出（`_toForwardRight` / `_project` / `_factorFor`），
/// 常量与公式一字不动，记录页画笔改为委托本文件——同一套数学只
/// 有一处实现，3D 回放复用它，不另写一套 3D 渲染。
///
/// 口径（与记录页 v0.1.8 起一致）：
/// - 相机高度约 140 米，地平线在画面 16% 高处、车标在 72% 高处；
/// - 透视因子 factor = camH / (camH + 前向距离)，近大远小，
///   远处收束到地平线；前向距离向后超过 100 米时按 -100 米钳制；
/// - headingUp=false 为北向上（前向 = 北向米、右向 = 东向米），
///   headingUp=true 为车头朝上（场景按车头朝向旋转）；
/// - is3d=false 时退化为 2D 俯视投影（与记录页 2D 模式同式）。
///
/// 本文件只做纯数学，不画任何东西、不碰网络、不读缓存；
/// 绘制（网格/轨迹/标记）仍由各调用方自己的 CustomPainter 做。

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 透视相机高度（米）。
const double perspectiveCameraHeightM = 140.0;

/// 地平线在画面高度中的占比。
const double perspectiveHorizonFraction = 0.16;

/// 车标（场景中心）在画面高度中的占比。
const double perspectiveVehicleFraction = 0.72;

/// 向后钳制：前向距离小于该值时按该值算（与记录页一致）。
const double perspectiveMinForwardM = -100.0;

/// 经纬度 → 以中心为原点的（前向，右向）米制坐标。
/// 与 `_Recording3dPainter._toForwardRight` 同式。
(double, double) forwardRightMeters({
  required double centerLat,
  required double centerLon,
  required double headingDeg,
  required bool headingUp,
  required double lat,
  required double lon,
}) {
  final dx =
      (lon - centerLon) * math.cos(centerLat * math.pi / 180) * 111320;
  final dy = (lat - centerLat) * 110540;
  if (!headingUp) return (dy, dx);
  final h = headingDeg * math.pi / 180;
  final forward = dx * math.sin(h) + dy * math.cos(h);
  final right = dx * math.cos(h) - dy * math.sin(h);
  return (forward, right);
}

/// （前向，右向）米制坐标 → 经纬度（[forwardRightMeters] 的逆运算）。
/// headingUp=false 时前向 = 北向米、右向 = 东向米；headingUp=true
/// 时按车头朝向旋转的逆矩阵还原。
({double lat, double lon}) forwardRightToLatLon({
  required double centerLat,
  required double centerLon,
  required double headingDeg,
  required bool headingUp,
  required double forward,
  required double right,
}) {
  final double dx, dy;
  if (!headingUp) {
    dy = forward;
    dx = right;
  } else {
    final h = headingDeg * math.pi / 180;
    dx = forward * math.sin(h) + right * math.cos(h);
    dy = forward * math.cos(h) - right * math.sin(h);
  }
  final lat = centerLat + dy / 110540;
  final lon = centerLon +
      dx / (111320 * math.cos(centerLat * math.pi / 180));
  return (lat: lat, lon: lon);
}

/// 透视因子：近大远小（1 为车标处，→0 收束到地平线）。
/// 与 `_Recording3dPainter._factorFor` 同式。
double perspectiveFactor(double forward, {bool is3d = true}) {
  if (!is3d) return 1;
  final d =
      forward < perspectiveMinForwardM ? perspectiveMinForwardM : forward;
  return perspectiveCameraHeightM / (perspectiveCameraHeightM + d);
}

/// （前向，右向）米制坐标 → 屏幕坐标（3D 透视 / 2D 俯视）。
/// 与 `_Recording3dPainter._project` 同式。
Offset perspectiveProject({
  required Size size,
  required double forward,
  required double right,
  required double pxPerM,
  bool is3d = true,
}) {
  if (!is3d) {
    return Offset(size.width / 2 + right * pxPerM,
        size.height / 2 - forward * pxPerM);
  }
  final factor = perspectiveFactor(forward, is3d: true);
  final horizonY = size.height * perspectiveHorizonFraction;
  final vehY = size.height * perspectiveVehicleFraction;
  return Offset(size.width / 2 + right * pxPerM * factor,
      horizonY + (vehY - horizonY) * factor);
}

/// 经纬度 → 屏幕坐标（[forwardRightMeters] + [perspectiveProject]
/// 的组合，供调用方一行调用）。
Offset perspectiveProjectLatLon({
  required Size size,
  required double centerLat,
  required double centerLon,
  required double headingDeg,
  required bool headingUp,
  required double lat,
  required double lon,
  required double pxPerM,
  bool is3d = true,
}) {
  final fr = forwardRightMeters(
    centerLat: centerLat,
    centerLon: centerLon,
    headingDeg: headingDeg,
    headingUp: headingUp,
    lat: lat,
    lon: lon,
  );
  return perspectiveProject(
    size: size,
    forward: fr.$1,
    right: fr.$2,
    pxPerM: pxPerM,
    is3d: is3d,
  );
}
