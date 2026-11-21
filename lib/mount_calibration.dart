import 'dart:math' as math;

/// 设备安装方向。
///
/// 只区分两种实际安装姿态，避免让用户面对一堆看不懂的选项：
/// - [forward]：设备长边（充电口/摄像头朝上那端）沿车头方向；
/// - [lateral]：设备横装，长边垂直于车头方向。
/// 倒装、轻微歪斜不用另设枚举，直接用安装补偿角修正。
enum MountOrientation { forward, lateral }

extension MountOrientationLabel on MountOrientation {
  String get label => switch (this) {
        MountOrientation.forward => '长边朝车头',
        MountOrientation.lateral => '横装（长边垂直车头）',
      };
}

/// 把角度规范化到 (-180, 180]，避免存储值无限累加。
double normalizeMountAngleDeg(double deg) {
  var d = deg % 360;
  if (d <= -180) d += 360;
  if (d > 180) d -= 360;
  return d;
}

/// 绕竖直轴旋转一个水平方向向量（ENU：x 东、y 北、z 上）。
/// 正角度为从上方看逆时针；z 分量原样保留。
List<double> rotateHorizontalDeg(List<double> v, double deg) {
  final rad = normalizeMountAngleDeg(deg) * math.pi / 180;
  final c = math.cos(rad);
  final s = math.sin(rad);
  return [
    v[0] * c - v[1] * s,
    v[0] * s + v[1] * c,
    v.length > 2 ? v[2] : 0.0,
  ];
}

/// 安装标定：方向 + 补偿角 + 完成时间。
///
/// 只描述“设备怎么装在车上”，不参与 GPS 定位；姿态解算在
/// Recorder.onSensor 里应用本对象，避免出现第二套 G 值/姿态计算。
class MountCalibration {
  const MountCalibration({
    this.orientation = MountOrientation.forward,
    this.yawOffsetDeg = 0,
    this.calibratedAtMs,
  });

  final MountOrientation orientation;

  /// 安装补偿角（度，正值把车头方向向左修正，范围 (-180, 180]）。
  final double yawOffsetDeg;

  /// 用户确认安装标定的时间；null = 尚未确认。
  final int? calibratedAtMs;

  bool get configured => calibratedAtMs != null;

  String get statusLabel => configured ? '安装已确认' : '安装未确认';

  String get summary =>
      '${orientation.label} · 补偿角 ${yawOffsetDeg.toStringAsFixed(1)}°';

  MountCalibration copyWith({
    MountOrientation? orientation,
    double? yawOffsetDeg,
    int? calibratedAtMs,
  }) =>
      MountCalibration(
        orientation: orientation ?? this.orientation,
        yawOffsetDeg: normalizeMountAngleDeg(yawOffsetDeg ?? this.yawOffsetDeg),
        calibratedAtMs: calibratedAtMs ?? this.calibratedAtMs,
      );

  Map<String, Object?> toJson() => {
        'orientation': orientation.name,
        'yawOffsetDeg': yawOffsetDeg,
        'calibratedAtMs': calibratedAtMs,
      };

  /// 容错读取：旧版本没有该键、字段类型不对或方向未知时，
  /// 一律回落到“未确认 + 长边朝前 + 0°”，绝不猜一个已标定状态。
  static MountCalibration fromJson(Object? raw) {
    if (raw is! Map) return const MountCalibration();
    final orientation = MountOrientation.values.firstWhere(
      (o) => o.name == raw['orientation'],
      orElse: () => MountOrientation.forward,
    );
    final offset = raw['yawOffsetDeg'];
    final at = raw['calibratedAtMs'];
    return MountCalibration(
      orientation: orientation,
      yawOffsetDeg:
          offset is num ? normalizeMountAngleDeg(offset.toDouble()) : 0,
      calibratedAtMs: at is int ? at : null,
    );
  }
}
