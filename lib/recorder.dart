import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'native.dart';

// ---------- 四元数（w,x,y,z），用于把设备加速度转到车身坐标 ----------
class Quat {
  final double w, x, y, z;
  const Quat(this.w, this.x, this.y, this.z);
  static Quat fromRotationVector(List<double> v) {
    // rotation vector: x,y,z 为轴*角度，另附 w（部分设备给 4 个分量）
    if (v.length >= 4) return Quat(v[3], v[0], v[1], v[2]);
    final angle = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (angle < 1e-6) return const Quat(1, 0, 0, 0);
    final s = math.sin(angle / 2) / angle;
    return Quat(math.cos(angle / 2), v[0] * s, v[1] * s, v[2] * s);
  }

  Quat get inv {
    final n = w * w + x * x + y * y + z * z;
    return Quat(w / n, -x / n, -y / n, -z / n);
  }

  Quat operator *(Quat o) => Quat(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  // 旋转向量 v（世界坐标系 ENU：x 东，y 北，z 上）
  List<double> rotate(List<double> v) {
    final qv = Quat(0, v[0], v[1], v[2]);
    final r = this * qv * inv;
    return [r.x, r.y, r.z];
  }
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

class GSample {
  final int timeMs;
  final double longG, latG;
  const GSample(this.timeMs, this.longG, this.latG);
}

enum RecState { idle, calibrating, recording, paused }

class Recorder extends ChangeNotifier {
  TripMode mode = TripMode.car;
  RecState state = RecState.idle;
  final List<TrackPoint> points = [];
  final List<GSample> gHistory = []; // 最近 60 秒，供波形图
  int startMs = 0;
  int pausedTotalMs = 0;
  int _pauseStartMs = 0;

  // 标定
  bool calibrated = false;
  bool waitingCalibration = false;
  int? calibratedAtMs; // v0.1.3：标定完成时间，供大方块按钮第二行显示
  // v0.1.3 外接 GPS：为 true 时手机定位流只更新显示，不再落点；
  // 轨迹点改由 onExternalFix 注入（provider='external'）。
  bool externalGpsActive = false;
  String calibrationNote = '未标定：开录前点“标定车头方向”，然后直线行驶至 18 km/h 以上';
  // v0.1.9 传感器校准页：零偏记录与罗盘提示状态位。注意：零偏只记录，
  // 不参与 onSensor 的 G 值计算（G 值计算仍只用标定车头方向），
  // 本页绝不在设置侧发明第二套 G 值计算。
  double? zeroBiasAx, zeroBiasAy, zeroBiasAz;
  int? zeroBiasAtMs;
  bool compassHintDone = false;

  /// 记录水平静置校零均值（仅存储与展示，不改 G 值计算）。
  void recordZeroBias(double ax, double ay, double az) {
    zeroBiasAx = ax;
    zeroBiasAy = ay;
    zeroBiasAz = az;
    zeroBiasAtMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  /// 罗盘 8 字提示完成：仅状态位，不代表任何罗盘精度结果。
  void markCompassHintDone() {
    compassHintDone = true;
    notifyListeners();
  }

  Quat? _q0;
  List<double> _forward0 = [0, 1, 0];
  List<double> _right0 = [1, 0, 0];

  // 实时
  double curLongG = 0, curLatG = 0, curVertG = 0;
  // 原始陀螺仪（rad/s，机体系，原生透传；只存诊断与后续融合精修，
  // 不参与 lg/tg 计算——姿态仍走 rotation vector）。
  double curGyroX = 0, curGyroY = 0, curGyroZ = 0;
  double smoothLong = 0, smoothLat = 0;
  double peakHoldLong = 0, peakHoldLat = 0;
  int _peakHoldMs = 0;
  double tripPeakLong = 0, tripPeakLat = 0;
  double pitchDeg = 0, rollDeg = 0; // 相对标定姿态：俯仰 / 横滚（摩托=压弯角）
  double curSpeed = 0, curHeading = 0;
  double curLat = 0, curLon = 0, curHAcc = 999;
  double? powerW;
  bool powerEstimated = false;
  double? cadenceRpm;
  int? heartRate;
  String sensorStatus = 'none';
  String? bleBatteryNote;

  // 1 秒聚合桶
  double _sumLong = 0, _sumLat = 0, _sumVert = 0;
  int _bucketCount = 0;
  Quat? _latestQ;
  double _latestPressure = 0;
  int? _lowSpeedSinceMs;
  int _lastNotifyMs = 0;

  bool get isRecording => state == RecState.recording;
  int get elapsedMs {
    if (state == RecState.idle) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final paused = state == RecState.paused ? now - _pauseStartMs : 0;
    return now - startMs - pausedTotalMs - paused;
  }

  double get distanceM {
    var d = 0.0;
    for (var i = 1; i < points.length; i++) {
      d += haversineM(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
    }
    return d;
  }

  void setMode(TripMode m) {
    if (state == RecState.idle) mode = m;
    notifyListeners();
  }

  void beginCalibration() {
    waitingCalibration = true;
    calibrated = false;
    calibrationNote = '标定中：请直线行驶至 18 km/h 以上，App 会自动锁定车头方向';
    notifyListeners();
  }

  void onSensor(Map<String, dynamic> e) {
    final ax = (e['ax'] as num?)?.toDouble() ?? 0;
    final ay = (e['ay'] as num?)?.toDouble() ?? 0;
    final az = (e['az'] as num?)?.toDouble() ?? 0;
    final rv = ((e['rv'] as List?) ?? []).map((v) => (v as num).toDouble()).toList();
    // 陀螺仪是原始机体系数据，与标定无关，放标定检查之前解析：
    // 即使未标定也照常存（老版本原生不发 gx/gy/gz 时保持旧值）。
    final gx = (e['gx'] as num?)?.toDouble();
    final gy = (e['gy'] as num?)?.toDouble();
    final gz = (e['gz'] as num?)?.toDouble();
    if (gx != null && gy != null && gz != null) {
      curGyroX = gx;
      curGyroY = gy;
      curGyroZ = gz;
    }
    if (rv.length >= 3) _latestQ = Quat.fromRotationVector(rv);
    _latestPressure = (e['pressure'] as num?)?.toDouble() ?? _latestPressure;
    if (_latestQ == null || !calibrated) {
      // 未标定：只显示原始合成 G 的参考值，不进评分（points 里 calibrated=false）
      curLongG = 0;
      curLatG = 0;
      _throttledNotify();
      return;
    }
    final q = _latestQ!;
    final aw = q.rotate([ax, ay, az]);
    final delta = q * _q0!.inv;
    final f = delta.rotate(_forward0);
    final r = delta.rotate(_right0);
    final u = delta.rotate([0, 0, 1]);
    const g = 9.81;
    final lg = (aw[0] * f[0] + aw[1] * f[1] + aw[2] * f[2]) / g;
    final tg = (aw[0] * r[0] + aw[1] * r[1] + aw[2] * r[2]) / g;
    final vg = (aw[0] * u[0] + aw[1] * u[1] + aw[2] * u[2]) / g;
    curLongG = lg;
    curLatG = tg;
    curVertG = vg;
    smoothLong = smoothLong + 0.35 * (lg - smoothLong);
    smoothLat = smoothLat + 0.35 * (tg - smoothLat);
    pitchDeg = math.asin(_clamp(f[2], -1, 1)) * 180 / math.pi;
    rollDeg = -math.asin(_clamp(r[2], -1, 1)) * 180 / math.pi;
    final now = DateTime.now().millisecondsSinceEpoch;
    gHistory.add(GSample(now, smoothLong, smoothLat));
    while (gHistory.isNotEmpty && now - gHistory.first.timeMs > 60000) {
      gHistory.removeAt(0);
    }
    if (smoothLong.abs() > peakHoldLong.abs() || now - _peakHoldMs > 2000) {
      peakHoldLong = smoothLong;
      _peakHoldMs = now;
    }
    if (smoothLat.abs() > peakHoldLat.abs()) peakHoldLat = smoothLat;
    tripPeakLong = tripPeakLong.abs() > lg.abs() ? tripPeakLong : lg;
    tripPeakLat = tripPeakLat.abs() > tg.abs() ? tripPeakLat : tg;
    if (state == RecState.recording) {
      _sumLong += lg;
      _sumLat += tg;
      _sumVert += vg;
      _bucketCount++;
    }
    _throttledNotify();
  }

  void onLocation(Map<String, dynamic> e) {
    final lat = (e['lat'] as num?)?.toDouble() ?? 0;
    final lon = (e['lon'] as num?)?.toDouble() ?? 0;
    if (lat == 0 && lon == 0) return;
    final speed = (e['speed'] as num?)?.toDouble() ?? 0;
    final bearing = (e['bearing'] as num?)?.toDouble() ?? 0;
    final timeMs = (e['timeMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    curLat = lat;
    curLon = lon;
    curSpeed = speed;
    curHeading = bearing;
    curHAcc = (e['hAcc'] as num?)?.toDouble() ?? 999;

    if (waitingCalibration && speed > 5 && _latestQ != null) {
      final br = bearing * math.pi / 180;
      _forward0 = [math.sin(br), math.cos(br), 0];
      _right0 = [_forward0[1], -_forward0[0], 0];
      _q0 = _latestQ;
      calibrated = true;
      calibratedAtMs = DateTime.now().millisecondsSinceEpoch;
      waitingCalibration = false;
      calibrationNote = '已标定：车头方向已锁定，G 值与姿态可信';
    }

    if (externalGpsActive) {
      // 外接 GPS 接管期间：手机定位只更新当前显示，不落点，避免双份轨迹。
      _throttledNotify();
      return;
    }
    if (state != RecState.recording) {
      _throttledNotify();
      return;
    }
    final n = _bucketCount > 0 ? _bucketCount : 1;
    final pt = TrackPoint(
      timeMs: timeMs,
      lat: lat,
      lon: lon,
      // 原生自 v0.1.7 起附带 hasAlt（Location.hasAltitude()）；无海拔
      // 时 alt 仍是占位 0，但 altValid=false，剖面/爬升/GPX 必须排除。
      alt: (e['alt'] as num?)?.toDouble() ?? 0,
      altValid: (e['hasAlt'] as bool?) ?? true,
      speed: speed,
      bearing: bearing,
      hAcc: curHAcc,
      vAcc: (e['vAcc'] as num?)?.toDouble() ?? 999,
      speedAcc: (e['sAcc'] as num?)?.toDouble() ?? 999,
      provider: (e['provider'] as String?) ?? '',
      longG: _sumLong / n,
      latG: _sumLat / n,
      vertG: _sumVert / n,
      pitch: pitchDeg,
      roll: rollDeg,
      heading: bearing,
      pressureHpa: _latestPressure,
      calibrated: calibrated,
      powerW: powerW,
      powerEstimated: powerEstimated,
      cadenceRpm: cadenceRpm,
      heartRate: heartRate,
      sensorStatus: sensorStatus,
      satCount: ((e['satCount'] as num?)?.toInt() ?? -1) < 0 ? null : (e['satCount'] as num?)!.toInt(),
      locSource: (e['provider'] as String?) ?? '',
    );
    points.add(pt);
    _sumLong = 0;
    _sumLat = 0;
    _sumVert = 0;
    _bucketCount = 0;

    // 停车超 5 分钟自动暂停（只暂停，不结束；恢复需手动点恢复）
    final now = DateTime.now().millisecondsSinceEpoch;
    if (speed < 0.5) {
      _lowSpeedSinceMs ??= now;
      if (now - _lowSpeedSinceMs! > 5 * 60 * 1000) {
        pause(auto: true);
      }
    } else {
      _lowSpeedSinceMs = null;
    }
    _throttledNotify();
  }

  /// v0.1.3 外接 GPS（RaceChrono BleDIY 等）注入的轨迹点。
  /// G 值取当前 1 秒聚合桶均值；hAcc 无可靠米值时传 999（界面显示 —）。
  /// v0.1.7：[altM] 为 GGA 海拔（平均海平面以上米数），null 表示
  /// 该路无海拔（RMC 单独定位时），此时 alt 存占位 0 但 altValid=false，
  /// 绝不画进剖面图、绝不计入爬升；旧版恒写 alt: 0 且无标记是 bug。
  void onExternalFix(double lat, double lon, double speed, double bearing, int timeMs, {double? altM}) {
    curLat = lat;
    curLon = lon;
    curSpeed = speed;
    curHeading = bearing;
    if (state != RecState.recording) {
      _throttledNotify();
      return;
    }
    final n = _bucketCount > 0 ? _bucketCount : 1;
    points.add(TrackPoint(
      timeMs: timeMs, lat: lat, lon: lon, alt: altM ?? 0, altValid: altM != null, speed: speed, bearing: bearing,
      hAcc: 999, vAcc: 999, speedAcc: 999, provider: 'external',
      longG: _sumLong / n, latG: _sumLat / n, vertG: _sumVert / n,
      pitch: pitchDeg, roll: rollDeg, heading: bearing, pressureHpa: _latestPressure,
      calibrated: calibrated, powerW: powerW, powerEstimated: powerEstimated,
      cadenceRpm: cadenceRpm, heartRate: heartRate, sensorStatus: sensorStatus,
      satCount: null, locSource: 'external',
    ));
    _sumLong = 0;
    _sumLat = 0;
    _sumVert = 0;
    _bucketCount = 0;
    _throttledNotify();
  }

  void onBleData(Map<String, dynamic> e) {
    final type = e['type'] as String? ?? '';
    switch (type) {
      case 'power':
        powerW = (e['value'] as num?)?.toDouble();
        powerEstimated = false;
        sensorStatus = 'ok';
        break;
      case 'cadence':
        cadenceRpm = (e['value'] as num?)?.toDouble();
        sensorStatus = 'ok';
        break;
      case 'hr':
        heartRate = (e['value'] as num?)?.toInt();
        break;
      case 'battery':
        final v = (e['value'] as num?)?.toInt() ?? 100;
        if (v < 20) bleBatteryNote = '传感器电量低：$v%';
        break;
      case 'disconnected':
        sensorStatus = 'disconnected';
        powerW = null;
        cadenceRpm = null;
        break;
      case 'connected':
        sensorStatus = 'ok';
        break;
    }
    notifyListeners();
  }

  /// 骑行无传感器时的估算功率（界面必须标“估算”）。
  void applyEstimatedPower(double slope, double massKg) {
    if (sensorStatus == 'ok') return;
    if (mode != TripMode.bike) return;
    powerW = estimatePowerW(curSpeed, slope, massKg);
    powerEstimated = true;
  }

  Future<void> start() async {
    points.clear();
    gHistory.clear();
    tripPeakLong = 0;
    tripPeakLat = 0;
    startMs = DateTime.now().millisecondsSinceEpoch;
    pausedTotalMs = 0;
    state = RecState.recording;
    _lowSpeedSinceMs = null;
    await Native.startForeground();
    await Native.startLocation();
    await Native.startSensors();
    notifyListeners();
  }

  Future<void> pause({bool auto = false}) async {
    if (state != RecState.recording) return;
    state = RecState.paused;
    _pauseStartMs = DateTime.now().millisecondsSinceEpoch;
    if (auto) calibrationNote = '已自动暂停：停车超过 5 分钟，点恢复可继续';
    notifyListeners();
  }

  Future<void> resume() async {
    if (state != RecState.paused) return;
    pausedTotalMs += DateTime.now().millisecondsSinceEpoch - _pauseStartMs;
    state = RecState.recording;
    _lowSpeedSinceMs = null;
    notifyListeners();
  }

  Future<void> stop() async {
    state = RecState.idle;
    await Native.stopLocation();
    await Native.stopSensors();
    await Native.stopForeground();
    notifyListeners();
  }

  void _throttledNotify() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotifyMs >= 100) {
      _lastNotifyMs = now;
      notifyListeners();
    }
  }
}
