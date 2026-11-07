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
/// 下一版·第 3 条（俯仰角可调的伪 3D，不是真 3D 模型）：
/// - 俯仰角 pitchDeg 默认 65°，此时与上面旧口径一字相同
///   （相机高 140 米、地平线 16%、车标 72%），旧调用不传
///   pitchDeg 时行为不变；回放页不传，仍走默认 65°；
/// - pitchDeg 越大（相机压得越低、看得越平），等效相机高度
///   越小、透视越强，地平线与车标位置随之微移；越小越接近俯视；
/// - 这仍是 CustomPainter 在地面平面上做的俯仰透视 + 车标
///   压扁/挤出/阴影，不是带网格与材质的真 3D 模型实时渲染：
///   离线构建拿不到新的 3D 模型渲染包，本文件不假装它是真 3D。
///   多角度预渲染图同样不可行——离线拿不到模型库、也没有
///   角度连续的渲染管线；伪 3D 是现有条件下唯一可行的档位。
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

/// 默认俯仰角（度）：65° 时与 v1.3.7 旧常量一字相同，旧调用
/// 不传 pitchDeg 时行为不变。
const double perspectiveDefaultPitchDeg = 65.0;

/// 俯仰角可调范围（度）：低于 20° 接近俯视、透视几乎消失；
/// 高于 75° 地平线压得过低、远处挤成一条线，故钳制在此区间。
const double perspectiveMinPitchDeg = 20.0;
const double perspectiveMaxPitchDeg = 75.0;

/// 俯仰角钳制到可调范围。
double clampPitchDeg(double pitchDeg) =>
    pitchDeg.clamp(perspectiveMinPitchDeg, perspectiveMaxPitchDeg).toDouble();

/// 俯仰角 → 等效相机高度（米）：65° 时为 140 米（旧值）；
/// 角度越大等效高度越小、透视越强，角度越小越接近俯视
/// （高度 → 大，透视因子 → 1）。
double perspectiveCameraHeightForPitch(double pitchDeg) {
  final p = clampPitchDeg(pitchDeg) * math.pi / 180;
  final ref = perspectiveDefaultPitchDeg * math.pi / 180;
  return perspectiveCameraHeightM * math.tan(ref) / math.tan(p);
}

/// 俯仰角 → 地平线在画面高度中的占比：65° 时为 0.16（旧值）；
/// 角度越小（越俯视）地平线越往上移。
double perspectiveHorizonFractionForPitch(double pitchDeg) {
  final p = clampPitchDeg(pitchDeg);
  return (perspectiveHorizonFraction +
          (p - perspectiveDefaultPitchDeg) * 0.001)
      .clamp(0.0, 0.30);
}

/// 俯仰角 → 车标在画面高度中的占比：65° 时为 0.72（旧值）；
/// 角度越小（越俯视）车标越往画面中心移（0° 时为 0.50）。
double perspectiveVehicleFractionForPitch(double pitchDeg) {
  final p = clampPitchDeg(pitchDeg);
  return 0.50 +
      p * (perspectiveVehicleFraction - 0.50) / perspectiveDefaultPitchDeg;
}

/// 车标俯仰压扁（横向，纵向）：65° 时为 (1.04, 0.90)，与记录页
/// 旧值一致；俯视（pitchDeg <= 0）时不压扁。车标画笔与记录页
/// 画笔共用此式，不各写一套。
(double, double) perspectiveMarkerScale(double pitchDeg) {
  if (pitchDeg <= 0) return (1.0, 1.0);
  final t = (clampPitchDeg(pitchDeg) / perspectiveDefaultPitchDeg)
      .clamp(0.0, 1.2);
  return (1 + 0.04 * t, 1 - 0.10 * t);
}

/// 车标侧壁挤出倍率：俯视时为 1（旧值），65° 时约 1.7——角度
/// 越大、侧壁越可见，挤出层越厚。车标画笔内部用。
double perspectiveExtrudeFactor(double pitchDeg) {
  if (pitchDeg <= 0) return 1.0;
  final t = (clampPitchDeg(pitchDeg) / perspectiveDefaultPitchDeg)
      .clamp(0.0, 1.2);
  return 1 + 0.7 * t;
}

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
/// pitchDeg 不传时为默认 65°，即旧相机高 140 米的因子。
double perspectiveFactor(double forward,
    {bool is3d = true, double pitchDeg = perspectiveDefaultPitchDeg}) {
  if (!is3d) return 1;
  final d =
      forward < perspectiveMinForwardM ? perspectiveMinForwardM : forward;
  final camH = perspectiveCameraHeightForPitch(pitchDeg);
  return camH / (camH + d);
}

/// （前向，右向）米制坐标 → 屏幕坐标（3D 透视 / 2D 俯视）。
/// 与 `_Recording3dPainter._project` 同式。
/// pitchDeg 不传时为默认 65°，即旧地平线 16% / 车标 72%。
Offset perspectiveProject({
  required Size size,
  required double forward,
  required double right,
  required double pxPerM,
  bool is3d = true,
  double pitchDeg = perspectiveDefaultPitchDeg,
}) {
  if (!is3d) {
    return Offset(size.width / 2 + right * pxPerM,
        size.height / 2 - forward * pxPerM);
  }
  final factor = perspectiveFactor(forward, is3d: true, pitchDeg: pitchDeg);
  final horizonY =
      size.height * perspectiveHorizonFractionForPitch(pitchDeg);
  final vehY = size.height * perspectiveVehicleFractionForPitch(pitchDeg);
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
  double pitchDeg = perspectiveDefaultPitchDeg,
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
    pitchDeg: pitchDeg,
  );
}
