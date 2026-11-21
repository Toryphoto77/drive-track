/// 多传感器融合（互补滤波 + 垂直通道 ESKF）。
///
/// 关键约束：
/// - 所有输入都带设备统一时基 [tsUs]（固件 esp_timer 微秒），不用本地
///   到达时间冒充采样时间；时间对不齐的融合输出一律不采信。
/// - GPS 与 IMU 之间存在解算/传输延时，调用方用 [gpsLatencyUs] 补偿。
/// - 缺数据的通道保持 null/不更新，绝不把“没读到”当成 0。
import 'dart:math' as math;

const double standardAirDensityKgM3 = 1.225;

/// 干空气密度（kg/m³）：ρ = p / (R·T)。未测湿度时不猜湿度。
double airDensityKgM3({
  required double pressurePa,
  required double temperatureC,
}) {
  final temperatureK = temperatureC + 273.15;
  if (pressurePa <= 0 || temperatureK <= 0) return 0;
  return pressurePa / (287.053 * temperatureK);
}

/// 密度高度：把实测干空气密度换算到 ISA 标准大气的对应高度。
/// 与只使用气压的几何气压高度不同，高温会正确表现为更高密度高度。
double densityAltitudeM({
  required double pressurePa,
  required double temperatureC,
}) {
  final density = airDensityKgM3(
    pressurePa: pressurePa,
    temperatureC: temperatureC,
  );
  if (density <= 0) return 0;
  const temperature0K = 288.15;
  const lapse = 0.0065;
  const g = 9.80665;
  const r = 287.053;
  final densityExponent = g / (r * lapse) - 1;
  final ratio = density / standardAirDensityKgM3;
  return temperature0K /
      lapse *
      (1 - math.pow(ratio, 1 / densityExponent));
}

class ImuSample {
  const ImuSample({
    required this.tsUs,
    required this.ax,
    required this.ay,
    required this.az,
    this.gx,
    this.gy,
    this.gz,
    this.rollDeg,
    this.pitchDeg,
  });

  final int tsUs;

  /// 加速度，单位 g。
  final double ax;
  final double ay;
  final double az;

  /// 角速度，单位 deg/s。
  final double? gx;
  final double? gy;
  final double? gz;

  final double? rollDeg;
  final double? pitchDeg;

  double get accelMagnitudeG => math.sqrt(ax * ax + ay * ay + az * az);
}

class BaroSample {
  const BaroSample({
    required this.tsUs,
    required this.temperatureC,
    required this.pressurePa,
    required this.altitudeM,
    this.relativeAltitudeM,
    this.calibrated = false,
  });

  final int tsUs;
  final double temperatureC;
  final double pressurePa;
  final double altitudeM;

  /// 相对开机自动零点的高差；未完成标定时为 null。
  final double? relativeAltitudeM;
  final bool calibrated;
}

/// 一次腾空事件。
class JumpEvent {
  const JumpEvent({
    required this.startTsUs,
    required this.endTsUs,
    required this.heightM,
  });

  final int startTsUs;
  final int endTsUs;

  /// 估算腾空高度（米）。
  final double heightM;
}

/// 垂直通道误差状态卡尔曼滤波。
///
/// 状态：[高度, 垂直速度, 加速度零偏]；过程用 IMU 垂直加速度预测，
/// 观测用气压高度与（延时补偿后的）GPS 海拔。只用 3 维状态，
/// 在手机上点运算量可接受。
class VerticalEkf {
  VerticalEkf({
    this.accelNoise = 0.08,
    this.baroNoise = 0.35,
    this.gpsNoise = 3.0,
  }) {
    // 初始协方差：高度/速度未知，零偏先按 0 信任。
    _p[0][0] = 4.0;
    _p[1][1] = 1.0;
    _p[2][2] = 0.01;
  }

  final double accelNoise;
  final double baroNoise;
  final double gpsNoise;

  double? _h;
  double _v = 0;
  double _b = 0;
  int? _lastTsUs;

  final List<List<double>> _p = [
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0],
  ];

  double? get altitudeM => _h;
  double get verticalSpeedMps => _v;
  double get accelBiasMps2 => _b;

  /// 用 IMU 做预测。[azMps2] 为机体 Z 轴加速度（m/s²，已含重力）。
  void predict({
    required int tsUs,
    required double azMps2,
    required double pitchRad,
    required double rollRad,
  }) {
    final last = _lastTsUs;
    _lastTsUs = tsUs;
    if (last == null) return;
    final dt = (tsUs - last) / 1e6;
    if (dt <= 0 || dt > 0.5) return;

    // 投影到地理垂直方向：车体 Z 轴读数按姿态修正重力分量。
    final vertical =
        azMps2 * math.cos(rollRad) * math.cos(pitchRad) - 9.80665;
    final acc = vertical - _b;
    if (_h != null) {
      _h = _h! + _v * dt + 0.5 * acc * dt * dt;
    }
    _v += acc * dt;

    // 状态转移 F = [[1, dt, -dt²/2], [0, 1, -dt], [0, 0, 1]]
    final f = [
      [1.0, dt, -0.5 * dt * dt],
      [0.0, 1.0, -dt],
      [0.0, 0.0, 1.0],
    ];
    _pMultiply(f);
    // 过程噪声：位置/速度/零偏各自随 dt 增长。
    final q = accelNoise * accelNoise;
    _p[0][0] += q * dt * dt * dt / 3;
    _p[0][1] += q * dt * dt / 2;
    _p[1][0] += q * dt * dt / 2;
    _p[1][1] += q * dt;
    _p[2][2] += 1e-6 * dt;
  }

  /// 气压高度观测（短时高频，权重高）。
  void updateBaro(double altitudeM) {
    if (_h == null) {
      _h = altitudeM;
      _p[0][0] = baroNoise * baroNoise;
      return;
    }
    _scalarUpdate(altitudeM - _h!, baroNoise * baroNoise, 0);
  }

  /// GPS 海拔观测（低频、垂直精度差，权重低）。
  void updateGpsAltitude(double altitudeM) {
    if (_h == null) {
      _h = altitudeM;
      _p[0][0] = gpsNoise * gpsNoise;
      return;
    }
    _scalarUpdate(altitudeM - _h!, gpsNoise * gpsNoise, 0);
  }

  void _scalarUpdate(double innovation, double r, int row) {
    final s = _p[row][row] + r;
    if (s <= 0) return;
    final k0 = _p[0][row] / s;
    final k1 = _p[1][row] / s;
    final k2 = _p[2][row] / s;
    if (_h != null) _h = _h! + k0 * innovation;
    _v += k1 * innovation;
    _b += k2 * innovation;
    // P = (I - K H) P
    for (var j = 0; j < 3; j++) {
      _p[0][j] -= k0 * _p[row][j];
      _p[1][j] -= k1 * _p[row][j];
      _p[2][j] -= k2 * _p[row][j];
    }
  }

  void _pMultiply(List<List<double>> f) {
    final out = List.generate(3, (_) => List<double>.filled(3, 0));
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += f[i][k] * _p[k][j];
        }
        out[i][j] = sum;
      }
    }
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        _p[i][j] = out[i][j];
      }
    }
  }
}

/// 腾空/落地检测：失重窗口 + 垂直速度回落。
///
/// 判定条件（同时满足）：
/// 1. 加速度模长显著低于 1 g（失重）；
/// 2. 持续超过 [minAirMs]；
/// 3. 窗口内垂直速度方向发生一次“上抛→回落”。
/// 用滞回避免落地弹跳重复计数。
class JumpDetector {
  JumpDetector({
    this.freeFallThresholdG = 0.55,
    this.minAirMs = 120,
    this.maxAirMs = 4000,
  });

  final double freeFallThresholdG;
  final int minAirMs;
  final int maxAirMs;

  int? _startUs;
  double _peakV = 0;
  bool _rising = false;
  final List<JumpEvent> events = [];

  /// 返回本次调用是否产生了一个事件。
  JumpEvent? update({
    required ImuSample imu,
    required double verticalSpeedMps,
  }) {
    final airborne = imu.accelMagnitudeG < freeFallThresholdG;
    if (airborne) {
      _startUs ??= imu.tsUs;
      if (verticalSpeedMps > _peakV) _peakV = verticalSpeedMps;
      if (_peakV > 0.3 && verticalSpeedMps < 0.05) _rising = true;
      final durationUs = imu.tsUs - _startUs!;
      if (durationUs > maxAirMs * 1000) {
        _reset();
      }
      return null;
    }
    if (_startUs == null) return null;
    final durationUs = imu.tsUs - _startUs!;
    final ok = durationUs >= minAirMs * 1000 && _rising;
    final start = _startUs!;
    final height = math.max(0.0, _peakV * _peakV / (2 * 9.80665));
    _reset();
    if (!ok) return null;
    final e = JumpEvent(startTsUs: start, endTsUs: imu.tsUs, heightM: height);
    events.add(e);
    return e;
  }

  void _reset() {
    _startUs = null;
    _peakV = 0;
    _rising = false;
  }
}

/// 把 NDJSON 的 imu/baro/gps 帧喂给融合器，并把统一时基换算成秒。
class SensorFusion {
  SensorFusion({VerticalEkf? ekf, JumpDetector? jumpDetector})
      : ekf = ekf ?? VerticalEkf(),
        jumpDetector = jumpDetector ?? JumpDetector();

  final VerticalEkf ekf;
  final JumpDetector jumpDetector;

  ImuSample? latestImu;
  BaroSample? latestBaro;
  double? densityAltitude;

  /// GPS 到达延时估计（微秒）：收到时刻 - 采样时刻，用于回推观测时间。
  int gpsLatencyUs = 0;

  void onImu(ImuSample imu) {
    latestImu = imu;
    final pitch = (imu.pitchDeg ?? 0) * math.pi / 180;
    final roll = (imu.rollDeg ?? 0) * math.pi / 180;
    ekf.predict(
      tsUs: imu.tsUs,
      azMps2: imu.az * 9.80665,
      pitchRad: pitch,
      rollRad: roll,
    );
    jumpDetector.update(imu: imu, verticalSpeedMps: ekf.verticalSpeedMps);
  }

  void onBaro(BaroSample baro) {
    latestBaro = baro;
    ekf.updateBaro(baro.altitudeM);
    densityAltitude = densityAltitudeM(
      pressurePa: baro.pressurePa,
      temperatureC: baro.temperatureC,
    );
  }

  void onGpsAltitude({required int tsUs, required double altitudeM}) {
    // 采样时刻早于到达时刻，按延时回推后再作为观测；不回推就相当于
    // 用未来的 IMU 状态去对过去的 GPS，垂直方向会明显滞后。
    final sampleTs = tsUs - gpsLatencyUs;
    final now = latestImu?.tsUs;
    if (now != null && (now - sampleTs).abs() > 2000000) return;
    ekf.updateGpsAltitude(altitudeM);
  }
}
