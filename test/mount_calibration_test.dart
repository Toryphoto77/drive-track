import 'package:drive_track/mount_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('安装补偿角规范化到 (-180, 180]', () {
    expect(normalizeMountAngleDeg(0), 0);
    expect(normalizeMountAngleDeg(190), closeTo(-170, 1e-9));
    expect(normalizeMountAngleDeg(-190), closeTo(170, 1e-9));
    expect(normalizeMountAngleDeg(540), closeTo(180, 1e-9));
  });

  test('补偿角绕竖直轴旋转水平方向', () {
    // ENU：x 东、y 北。车头朝北，设备向右歪 90° 时补偿后仍应朝北。
    final north = rotateHorizontalDeg([0.0, 1.0, 0.0], 0);
    expect(north[0], closeTo(0, 1e-9));
    expect(north[1], closeTo(1, 1e-9));

    final compensated = rotateHorizontalDeg([1.0, 0.0, 0.0], 90);
    expect(compensated[0], closeTo(0, 1e-9));
    expect(compensated[1], closeTo(1, 1e-9));
  });

  test('安装标定 JSON 往返，未知方向回落为长边朝前', () {
    const calibration = MountCalibration(
      orientation: MountOrientation.lateral,
      yawOffsetDeg: 12.5,
      calibratedAtMs: 123,
    );
    final restored = MountCalibration.fromJson(calibration.toJson());
    expect(restored.orientation, MountOrientation.lateral);
    expect(restored.yawOffsetDeg, 12.5);
    expect(restored.calibratedAtMs, 123);
    expect(restored.configured, isTrue);

    final unknown = MountCalibration.fromJson({
      'orientation': 'unknown',
      'yawOffsetDeg': 'bad',
    });
    expect(unknown.orientation, MountOrientation.forward);
    expect(unknown.yawOffsetDeg, 0);
    expect(unknown.configured, isFalse);
  });

  test('未设置安装标定时明确标记未确认', () {
    expect(const MountCalibration().configured, isFalse);
    expect(const MountCalibration().statusLabel, '安装未确认');
  });
}
