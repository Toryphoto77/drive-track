/// 摩托压弯倾角融合估计器（纯 Dart，可单测，不含任何 UI）。
///
/// 融合手机原始加速度计 + 陀螺仪，输出实时横滚 / 压弯角。
/// 关键点：压弯时加速度计单独算不准——转弯的离心力叠加重力，
/// 让“加速度计看到的重力方向”偏向车身正下方，算出的倾角趋近 0。
/// 因此本估计器以陀螺仪积分为主（动态时只信陀螺），只在实测加速度
/// 接近 1g（低动态、加速度计基本只量重力）时才用加速度计纠漂。
/// 这是互补滤波：陀螺高频可信、加速度计低频可信。
///
/// 符号约定（与既有 roll 一致）：lean > 0 为右倾，lean < 0 为左倾，单位度。
/// 坐标：[forward] 与 [gravityRef] 均为标定时刻的单位矢量（设备系），
/// 由调用方（Recorder）在标定完成时传入；估计器内部只做设备系运算。
/// 结构上可直接换外部 IMU 数据源：只要按同样约定喂 accel/gyro 即可。
import 'dart:math' as math;

/// 倾角估计可信度。
enum LeanQuality {
  /// 数据正常：近期有加速度计纠漂，估计可信。
  good,

  /// 陀螺单独积分过久（持续动态、加速度计长期不可信），可能已漂移。
  degraded,

  /// 无有效采样或输入非法，数值不可信。
  unreliable,
}

class LeanEstimator {
  static const double _g = 9.81;

  /// 加速度计可信门控：|a| 与 g 的偏差 <= 该值全信，>= [_accelTrustNone]
  /// 全不信，中间线性过渡。
  static const double _accelTrustFull = 0.3;
  static const double _accelTrustNone = 2.0;

  /// 纠漂时间常数（秒）：加速度计以该速度把估计拉回重力方向。
  static const double _tauS = 1.0;

  /// 陀螺单独积分超过该时长仍无可信加速度纠漂 → degraded。
  static const double _gyroOnlyDegradedMs = 5000;

  /// 设备系，前进方向单位矢量（标定时刻）。
  final List<double> _forward;

  /// 设备系，标定时刻的重力方向单位矢量。
  final List<double> _gravityRef;

  /// 估计的重力方向（设备系，单位矢量）。
  List<double> _gEst;

  /// 自上次可信加速度纠漂以来的毫秒数（陀螺单独积分时长）。
  double _gyroOnlyMs = 0;
  bool _hasSample = false;

  LeanEstimator({
    required List<double> forward,
    required List<double> gravityRef,
  })  : _forward = _normalized(forward),
        _gravityRef = _normalized(gravityRef),
        _gEst = _normalized(gravityRef);

  static List<double> _normalized(List<double> v) {
    if (v.length < 3) return [0, 0, -1];
    final n =
        math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (n < 1e-9) return [0, 0, -1];
    return [v[0] / n, v[1] / n, v[2] / n];
  }

  /// 喂一帧 IMU 采样。
  ///
  /// [accel] 原始加速度计 [ax, ay, az]（m/s²，设备系，含重力）。
  /// [gyro] 角速度 [gx, gy, gz]（rad/s，设备系）。
  /// [dt] 距上一帧的秒数；<= 0 或 > 0.5 视为无效帧（跳过）。
  void update(List<double> accel, List<double> gyro, double dt) {
    if (accel.length < 3 || gyro.length < 3) return;
    if (accel.any((v) => v.isNaN || v.isInfinite) ||
        gyro.any((v) => v.isNaN || v.isInfinite)) {
      return;
    }
    if (dt <= 0 || dt > 0.5) return;
    _hasSample = true;

    // 1) 陀螺积分：设备系里的重力矢量随设备旋转，导数 dg/dt = -ω × g。
    final w = gyro;
    final g = _gEst;
    final cx = w[2] * g[1] - w[1] * g[2];
    final cy = w[0] * g[2] - w[2] * g[0];
    final cz = w[1] * g[0] - w[0] * g[1];
    _gEst = _normalized([g[0] + cx * dt, g[1] + cy * dt, g[2] + cz * dt]);

    // 2) 加速度计纠漂：只在 |a| 接近 1g 时信任（低动态）。
    final aMag = math.sqrt(
        accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
    double trust = 0;
    if (aMag > 1e-6) {
      final dev = (aMag - _g).abs();
      trust = (( _accelTrustNone - dev) /
              (_accelTrustNone - _accelTrustFull))
          .clamp(0.0, 1.0);
      if (trust > 0) {
        final gAcc = [-accel[0] / aMag, -accel[1] / aMag, -accel[2] / aMag];
        final k = (dt / _tauS) * trust;
        _gEst = _normalized([
          _gEst[0] + k * (gAcc[0] - _gEst[0]),
          _gEst[1] + k * (gAcc[1] - _gEst[1]),
          _gEst[2] + k * (gAcc[2] - _gEst[2]),
        ]);
      }
    }
    if (trust >= 0.5) {
      _gyroOnlyMs = 0;
    } else {
      _gyroOnlyMs += dt * 1000;
    }
  }

  /// 当前压弯角（度）：> 0 右倾，< 0 左倾。
  ///
  /// 把估计重力与标定重力投影到垂直于前进方向的平面上，
  /// 取两者绕前进轴的有符号夹角（右倾为正）。
  double get leanDeg {
    final f = _forward;
    final r = _gravityRef;
    final e = _gEst;
    final dr = r[0] * f[0] + r[1] * f[1] + r[2] * f[2];
    final de = e[0] * f[0] + e[1] * f[1] + e[2] * f[2];
    final rp = [r[0] - dr * f[0], r[1] - dr * f[1], r[2] - dr * f[2]];
    final ep = [e[0] - de * f[0], e[1] - de * f[1], e[2] - de * f[2]];
    final nr =
        math.sqrt(rp[0] * rp[0] + rp[1] * rp[1] + rp[2] * rp[2]);
    final ne =
        math.sqrt(ep[0] * ep[0] + ep[1] * ep[1] + ep[2] * ep[2]);
    if (nr < 1e-6 || ne < 1e-6) return 0;
    final rpn = [rp[0] / nr, rp[1] / nr, rp[2] / nr];
    final epn = [ep[0] / ne, ep[1] / ne, ep[2] / ne];
    final ccx = rpn[1] * epn[2] - rpn[2] * epn[1];
    final ccy = rpn[2] * epn[0] - rpn[0] * epn[2];
    final ccz = rpn[0] * epn[1] - rpn[1] * epn[0];
    final s = ccx * f[0] + ccy * f[1] + ccz * f[2];
    final c = rpn[0] * epn[0] + rpn[1] * epn[1] + rpn[2] * epn[2];
    return -math.atan2(s, c) * 180 / math.pi;
  }

  /// 当前可信度。
  LeanQuality get quality {
    if (!_hasSample) return LeanQuality.unreliable;
    if (_gyroOnlyMs > _gyroOnlyDegradedMs) return LeanQuality.degraded;
    return LeanQuality.good;
  }

  /// 回到标定姿态（重标定时调用）。
  void reset() {
    _gEst = List.of(_gravityRef);
    _gyroOnlyMs = 0;
    _hasSample = false;
  }
}
