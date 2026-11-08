/// 压弯倾角融合估计器测试（v1.5.3）。
///
/// 覆盖：静止正直读 0°；静止侧倾收敛到已知角；压弯时加速度计
/// 单独会读错（离心力掩盖倾角）而融合估计器仍跟住真实倾角；
/// 可信度标志；非法输入与 dt 边界。
import 'dart:math' as math;

import 'package:drive_track/lean_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

const double _g = 9.81;

/// 车把正装示例坐标：前进为设备 -z，重力（正直时）为设备 -y。
/// 与 Recorder 标定建立的设备系约定一致。
final List<double> _forward = [0, 0, -1];
final List<double> _gravityRef = [0, -1, 0];

/// 仅用加速度计估的横滚角（度）：把加速度矢量当重力方向，
/// 取其与参考下方向在 x-y 平面内的夹角。压弯时该值趋近 0（错误）。
double _accelOnlyRollDeg(List<double> accel) {
  final n = math.sqrt(
      accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
  if (n < 1e-6) return 0;
  // 下方向 = -accel/|accel|；与参考下方向 [0,-1,0] 的夹角。
  final dx = -accel[0] / n;
  final dy = -accel[1] / n;
  return math.atan2(dx, -dy) * 180 / math.pi;
}

void main() {
  group('LeanEstimator', () {
    test('静止正直：读 0°，可信度 good', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      for (var i = 0; i < 50; i++) {
        est.update([0, -_g, 0], [0, 0, 0], 0.02);
      }
      expect(est.leanDeg, closeTo(0, 1.0));
      expect(est.quality, LeanQuality.good);
    });

    test('静止左倾 20°：加速度计纠漂收敛到 -20°', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      // 设备静止左倾 20°：加速度计读 [sin20, cos20, 0] * g。
      final ax = _g * math.sin(20 * math.pi / 180);
      final ay = _g * math.cos(20 * math.pi / 180);
      for (var i = 0; i < 150; i++) {
        est.update([ax, ay, 0], [0, 0, 0], 0.02);
      }
      expect(est.leanDeg, closeTo(-20, 2.5));
      expect(est.quality, LeanQuality.good);
    });

    test('压弯 40°：加速度计单独读 0°，融合估计器跟住 40°', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      const dt = 0.02;
      // A) 正直 1 秒。
      for (var i = 0; i < 50; i++) {
        est.update([0, -_g, 0], [0, 0, 0], dt);
      }
      expect(est.leanDeg, closeTo(0, 1.0));
      // B) 0.4 秒压入 40° 右倾：陀螺绕前进轴 100°/s，
      // 加速度计始终沿设备 +y（合力与车身正下方对齐）。
      const leanRate = 100 * math.pi / 180; // rad/s
      for (var i = 0; i < 20; i++) {
        final theta = 40 * (i + 1) / 20 * math.pi / 180;
        final aMag = _g / math.cos(theta);
        est.update(
            [0, aMag, 0], [0, 0, -leanRate], dt);
      }
      // C) 稳定压弯 2 秒：陀螺为 0，加速度计仍沿设备 +y。
      final aCorner = _g / math.cos(40 * math.pi / 180);
      for (var i = 0; i < 100; i++) {
        est.update([0, aCorner, 0], [0, 0, 0], dt);
      }
      // 融合估计器应保持在 40° 附近（陀螺积分主导）。
      expect(est.leanDeg, closeTo(40, 8.0));
      // 而同一时刻的加速度计单独读数接近 0°（错误示范）。
      expect(_accelOnlyRollDeg([0, aCorner, 0]), closeTo(0, 2.0));
    });

    test('可信度：无采样为 unreliable；长期纯陀螺为 degraded', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      expect(est.quality, LeanQuality.unreliable);
      expect(est.leanDeg, closeTo(0, 0.5));
      // 先喂正常数据 → good。
      for (var i = 0; i < 50; i++) {
        est.update([0, -_g, 0], [0, 0, 0], 0.02);
      }
      expect(est.quality, LeanQuality.good);
      // 再喂 6 秒“加速度远离 1g、陀螺为 0”的数据：无纠漂 → degraded。
      for (var i = 0; i < 300; i++) {
        est.update([0, -20, 0], [0, 0, 0], 0.02);
      }
      expect(est.quality, LeanQuality.degraded);
    });

    test('非法输入与 dt 边界：NaN 与无效 dt 被忽略，不崩', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      for (var i = 0; i < 50; i++) {
        est.update([0, -_g, 0], [0, 0, 0], 0.02);
      }
      final before = est.leanDeg;
      est.update([double.nan, -_g, 0], [0, 0, 0], 0.02);
      est.update([0, -_g, 0], [0, 0, 0], 0); // dt = 0
      est.update([0, -_g, 0], [0, 0, 0], 2.0); // dt 过大
      expect(est.leanDeg, closeTo(before, 0.001));
      expect(est.quality, LeanQuality.good);
    });

    test('reset：回到标定姿态，恢复 unreliable', () {
      final est = LeanEstimator(
          forward: _forward, gravityRef: _gravityRef);
      for (var i = 0; i < 50; i++) {
        est.update([0, -_g, 0], [0, 0, 0], 0.02);
      }
      expect(est.quality, LeanQuality.good);
      est.reset();
      expect(est.leanDeg, closeTo(0, 0.5));
      expect(est.quality, LeanQuality.unreliable);
    });
  });
}
