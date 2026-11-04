/// RaceChrono BleDIY 协议 GPS 的纯 Dart 逻辑：NMEA 语句解析与合并。
///
/// 不依赖 Flutter widget，可直接单元测试。传输层不在本文件：
/// BleDIY 类设备走 BLE 串口（Nordic UART 风格），订阅后把字节流按行
/// 交给 [BleDiyGpsFeed] 即可；字节从哪来、特征订阅怎么做，见回执里的
/// 原生方法规格表（现有 MainActivity.kt 没有 UART 订阅能力）。
///
/// UUID 说明（须如实标注）：
/// - 下面三个 UUID 是标准的 Nordic UART Service（NUS）值，是“Nordic
///   UART 风格串口”的默认值，不是 RaceChrono 官方为 BleDIY 公布的专属
///   UUID。本文件未找到 RaceChrono 公开的 BleDIY 专属 UUID 文档，
///   因此实际设备若广播了别的服务 UUID，调用方必须以设备实际广播
///   为准（可用 device_center.dart 的通用 BLE 表单登记），不得硬说
///   NUS 就是 BleDIY 的官方值。
/// - 解析本身与传输无关：只要拿到的是 NMEA 文本行，下面逻辑就适用。
const String nordicUartServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca';
const String nordicUartRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca';
const String nordicUartTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca';

/// 外部 GPS 输出的统一结构。速度单位统一为米/秒，方向为真北度数。
class ExternalGpsFix {
  const ExternalGpsFix({
    required this.lat,
    required this.lon,
    this.speedMps,
    this.bearingDeg,
    this.satellites,
    this.hdop,
    this.timestampUtc,
    this.hz,
    this.altitudeM,
    this.fixQuality,
    this.fixMode,
    this.usedSatellites,
  });

  final double lat;
  final double lon;
  final double? speedMps;
  final double? bearingDeg;
  final int? satellites;

  /// GGA 定位质量：1=GPS、2=DGPS、4=RTK 固定、5=RTK 浮动、6=估算；
  /// null = 本次定位无 GGA 质量（如仅 RMC 定位且此前无 GGA）。
  final int? fixQuality;

  /// GSA 定位模式：2=2D、3=3D；1=无定位时不由 GSA 单独造点，
  /// 只记模式供下一次位置合并；null = 尚未收到 GSA。
  final int? fixMode;

  /// GSA 参与解算卫星数（12 个 PRN 槽位里非空个数）；null = 未收到 GSA。
  final int? usedSatellites;

  /// GGA 第 9 字段海拔（平均海平面以上，米）。null = 本次定位
  /// 无海拔（如仅 RMC 定位），调用方必须按“无海拔”处理，绝不
  /// 把它当 0 米画进剖面图。v0.1.7 前解析器丢弃了该字段，是
  /// 外接路无海拔的根因。
  final double? altitudeM;

  /// 水平精度因子（HDOP，无量纲）。注意：HDOP 不是米，
  /// 绝不能直接当作米级精度用，因此 [hAcc] 恒为 null。
  final double? hdop;
  double? get hAcc => null;

  /// RMC 提供的 UTC 时间（无日期/时间字段的语句则为 null）。
  final DateTime? timestampUtc;

  /// 最近 1 秒内被接受的定位点数（近似输出频率，非设备标称频率）。
  final double? hz;

  /// 固定标记，供调用方与手机 GPS 区分，绝不混标。
  String get source => 'external';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'lat': lat,
        'lon': lon,
        'speed': speedMps,
        'bearing': bearingDeg,
        'satellites': satellites,
        'hdop': hdop,
        'altitudeM': altitudeM,
        'hAcc': hAcc,
        'timestampUtc': timestampUtc?.toIso8601String(),
        'hz': hz,
        'fixQuality': fixQuality,
        'fixMode': fixMode,
        'usedSatellites': usedSatellites,
        'source': source,
      };
}

/// GGA 语句解析结果（位置 + 卫星数 + HDOP + 海拔）。
class GgaData {
  const GgaData({
    required this.lat,
    required this.lon,
    required this.fixQuality,
    this.satellites,
    this.hdop,
    this.altitudeM,
  });
  final double lat;
  final double lon;
  final int fixQuality;
  final int? satellites;
  final double? hdop;
  final double? altitudeM;
}

/// RMC 语句解析结果（位置 + 速度 + 方向 + 时间）。
class RmcData {
  const RmcData({
    required this.lat,
    required this.lon,
    this.speedMps,
    this.bearingDeg,
    this.timestampUtc,
  });
  final double lat;
  final double lon;
  final double? speedMps;
  final double? bearingDeg;
  final DateTime? timestampUtc;
}

/// VTG 语句解析结果（速度 + 方向，无位置，单独出现时绝不造点）。
class VtgData {
  const VtgData({this.speedMps, this.bearingDeg});
  final double? speedMps;
  final double? bearingDeg;
}

const double _knotsToMps = 0.514444;

/// 校验 NMEA 校验和：`$...*HH` 中 `*` 前所有字符的异或等于 HH。
/// 无 `*` 校验段的语句不因此丢弃（部分 DIY 固件会省略），但仍须通过
/// 后续的字段、定位有效性检查；校验段存在且不符时一律丢弃。
bool verifyNmeaChecksum(String line) {
  final star = line.indexOf('*');
  if (star < 0) return true;
  if (star + 3 != line.length && star + 3 < line.length) {
    // 允许行尾空白，但校验段必须是 2 位十六进制。
    final tail = line.substring(star + 1).trim();
    if (tail.length != 2) return false;
    return _checksumMatches(line, star, tail);
  }
  if (line.length - star - 1 != 2) return false;
  return _checksumMatches(line, star, line.substring(star + 1));
}

bool _checksumMatches(String line, int star, String hex) {
  var sum = 0;
  for (var i = 1; i < star; i++) {
    sum ^= line.codeUnitAt(i);
  }
  final expected = int.tryParse(hex, radix: 16);
  return expected != null && sum == expected;
}

List<String> _fields(String line) {
  final star = line.indexOf('*');
  final body = star >= 0 ? line.substring(0, star) : line;
  return body.split(',');
}

double? _parseCoord(String raw, String hemi, bool isLat) {
  final v = double.tryParse(raw);
  if (v == null || v < 0) return null;
  final deg = (v / 100).floorToDouble();
  final min = v - deg * 100;
  if (min >= 60) return null;
  var out = deg + min / 60;
  if (hemi == 'S' || hemi == 'W') out = -out;
  if (isLat && (out < -90 || out > 90)) return null;
  if (!isLat && (out < -180 || out > 180)) return null;
  return out;
}

double? _normalizeBearing(double? v) {
  if (v == null || v.isNaN) return null;
  var b = v % 360;
  if (b < 0) b += 360;
  return b;
}

/// 解析 GGA：定位质量 0（无效定位）返回 null；经纬度非法返回 null。
GgaData? parseGga(String line) {
  if (!line.startsWith(r'$') || !line.contains('GGA')) return null;
  if (!verifyNmeaChecksum(line)) return null;
  final f = _fields(line);
  if (f.length < 9) return null;
  final fix = int.tryParse(f[6]);
  if (fix == null || fix == 0) return null;
  final lat = _parseCoord(f[2], f[3], true);
  final lon = _parseCoord(f[4], f[5], false);
  if (lat == null || lon == null) return null;
  return GgaData(
    lat: lat,
    lon: lon,
    fixQuality: fix,
    satellites: int.tryParse(f[7]),
    hdop: double.tryParse(f[8]),
    // GGA 字段 9 为海拔（米，平均海平面以上），字段 10 为单位 M；
    // 字段不足或解析失败时为 null（无海拔），不得补 0。
    altitudeM: f.length > 9 ? double.tryParse(f[9]) : null,
  );
}

/// 解析 RMC：状态不是 A（有效）返回 null；经纬度非法返回 null。
RmcData? parseRmc(String line) {
  if (!line.startsWith(r'$') || !line.contains('RMC')) return null;
  if (!verifyNmeaChecksum(line)) return null;
  final f = _fields(line);
  if (f.length < 10) return null;
  if (f[2] != 'A') return null;
  final lat = _parseCoord(f[3], f[4], true);
  final lon = _parseCoord(f[5], f[6], false);
  if (lat == null || lon == null) return null;
  final knots = double.tryParse(f[7]);
  final course = double.tryParse(f[8]);
  DateTime? ts;
  final time = f[1];
  final date = f[9];
  if (time.length >= 6 && date.length == 6) {
    final hh = int.tryParse(time.substring(0, 2));
    final mm = int.tryParse(time.substring(2, 4));
    final ss = int.tryParse(time.substring(4, 6));
    final dd = int.tryParse(date.substring(0, 2));
    final mo = int.tryParse(date.substring(2, 4));
    final yy = int.tryParse(date.substring(4, 6));
    if (hh != null && mm != null && ss != null && dd != null && mo != null && yy != null) {
      try {
        ts = DateTime.utc(2000 + yy, mo, dd, hh, mm, ss);
      } catch (_) {
        ts = null;
      }
    }
  }
  return RmcData(
    lat: lat,
    lon: lon,
    speedMps: knots == null ? null : knots * _knotsToMps,
    bearingDeg: _normalizeBearing(course),
    timestampUtc: ts,
  );
}

/// 解析 VTG：优先真北方向，其次磁北方向；优先 km/h 速度，其次节。
/// 速度、方向都解析不出时返回 null（调用方不得用它造点）。
VtgData? parseVtg(String line) {
  if (!line.startsWith(r'$') || !line.contains('VTG')) return null;
  if (!verifyNmeaChecksum(line)) return null;
  final f = _fields(line);
  if (f.length < 8) return null;
  final courseTrue = double.tryParse(f[1]);
  final courseMag = double.tryParse(f[3]);
  final kmh = double.tryParse(f[7]);
  final knots = double.tryParse(f[5]);
  final speed = kmh != null ? kmh / 3.6 : (knots == null ? null : knots * _knotsToMps);
  final bearing = _normalizeBearing(courseTrue ?? courseMag);
  if (speed == null && bearing == null) return null;
  return VtgData(speedMps: speed, bearingDeg: bearing);
}

/// GSA 解析结果：定位模式与参与解算卫星数；GSA 本身无位置，
/// 只给下一次位置合并补充模式 / 星数 / HDOP（GGA 的 HDOP 优先）。
class GsaData {
  const GsaData({
    required this.fixType,
    required this.usedSatellites,
    this.pdop,
    this.hdop,
    this.vdop,
  });

  /// 1=无定位、2=2D、3=3D（其它值一律视为非法）。
  final int fixType;
  final int usedSatellites;
  final double? pdop;
  final double? hdop;
  final double? vdop;
}

/// 解析 GSA（$--GSA,a,m,prn×12,pdop,hdop,vdop*hh）。
///
/// 字段 ≥15 才解析（否则是残缺句，返回 null 供调用方丢弃计数）；
/// 校验段语义与其它语句一致：无校验段不丢弃，有校验段不符丢弃；
/// VDOP 缺失（17 字段）容忍为 null；fixType 不在 1/2/3 视为非法。
GsaData? parseGsa(String line) {
  final raw = line.trim();
  if (!raw.startsWith(r'$') || !raw.contains('GSA')) return null;
  if (!verifyNmeaChecksum(raw)) return null;
  final body =
      raw.substring(1, raw.contains('*') ? raw.indexOf('*') : raw.length);
  final f = body.split(',');
  if (f.length < 15) return null;
  final fixType = int.tryParse(f[2]);
  if (fixType == null || fixType < 1 || fixType > 3) return null;
  var used = 0;
  for (var i = 3; i <= 14; i++) {
    if (f[i].trim().isNotEmpty) used++;
  }
  return GsaData(
    fixType: fixType,
    usedSatellites: used,
    pdop: f.length > 15 ? double.tryParse(f[15]) : null,
    hdop: f.length > 16 ? double.tryParse(f[16]) : null,
    vdop: f.length > 17 ? double.tryParse(f[17]) : null,
  );
}

/// NMEA 行流合并器：GGA/RMC 给位置，RMC/VTG 给速度与方向，
/// GSA 只给定位模式 / 参与解算星数 / HDOP 兜底（不单独成点、
/// 不刷新定位时间戳、不计入 accepted）。
/// VTG 先于任何位置到达时只暂存速度/方向，等第一个有效位置到达后再合并，
/// 绝不凭速度语句单独输出一个点。
class BleDiyGpsFeed {
  /// 断线/超时判定默认窗口：超过该时长无新定位即视为外部源失效。
  static const Duration defaultStaleTimeout = Duration(seconds: 5);

  ExternalGpsFix? _latest;
  double? _pendingSpeedMps;
  double? _pendingBearingDeg;
  DateTime? _lastFixAt;
  int? _lastFixQuality;
  int? _lastFixMode;
  int? _lastUsedSats;
  double? _lastGsaHdop;
  final List<DateTime> _acceptedAt = [];
  // GGA 计次点：Hz 以定位周期计（GGA 每周期一句话）；从未收到 GGA
  // 的设备（如只发 RMC）以 RMC 计次，避免读数恒为 0。
  final List<DateTime> _ggaAt = [];
  final StringBuffer _buffer = StringBuffer();

  int droppedCount = 0;
  int acceptedCount = 0;

  ExternalGpsFix? get latest => _latest;
  DateTime? get lastFixAt => _lastFixAt;

  void _pruneHz(DateTime at) {
    _acceptedAt.removeWhere((t) => at.difference(t).inMilliseconds > 1000);
    _ggaAt.removeWhere((t) => at.difference(t).inMilliseconds > 1000);
  }

  /// 最近 1 秒内定位周期数（近似 Hz）：GGA 每周期一句话，以 GGA 计；
  /// 无 GGA 时以 RMC 计；VTG 不计次——同一周期 GGA+RMC+VTG 三句
  /// 都 emit 时，不得把 25Hz 读成 50/75Hz。显示层只做取整，不封顶、
  /// 不截断，25Hz 可直接显示。
  double get hz {
    _pruneHz(DateTime.now());
    return _acceptedAt.length.toDouble();
  }

  /// 是否应回落手机 GPS：从未拿到有效位置，或超过超时无新定位。
  /// 回落逻辑（调用方责任，见下方说明）：
  /// 1. 一旦本方法为 true，调用方应立即切回手机 GPS 轨迹源，并把
  ///    之后轨迹点的 source 标记为 'phone'，不得继续贴 'external'；
  /// 2. 外部源恢复后（[latest] 更新且未超时），调用方可切回，但
  ///    切换点要在轨迹里留档（避免一段轨迹混用两种精度还看不出来）；
  /// 3. 断线（BLE disconnected 事件）时调用方应立即调用 [reset]，
  ///    不要等超时窗口耗尽。
  bool shouldFallbackToPhoneGps({
    Duration timeout = defaultStaleTimeout,
    DateTime? now,
  }) {
    final at = _lastFixAt;
    if (at == null) return true;
    return (now ?? DateTime.now()).difference(at) > timeout;
  }

  bool isStale({Duration timeout = defaultStaleTimeout, DateTime? now}) =>
      shouldFallbackToPhoneGps(timeout: timeout, now: now);

  /// 喂入一段原始字节（BLE 通知常按 20 字节分片），按行切分后逐行处理。
  void feedBytes(List<int> bytes) {
    final text = String.fromCharCodes(bytes);
    _buffer.write(text);
    final all = _buffer.toString();
    final parts = all.split('\n');
    _buffer.clear();
    // 最后一部分可能是不完整的行，留到下次补齐。
    _buffer.write(parts.removeLast());
    for (final line in parts) {
      feedLine(line);
    }
  }

  /// 喂入一行 NMEA 语句。返回合并后的最新定位；解析失败返回 null
  /// 并计入 [droppedCount]，绝不输出造假点。空行不计数。
  ExternalGpsFix? feedLine(String rawLine, {DateTime? now}) {
    final line = rawLine.trim();
    if (line.isEmpty) return _latest;
    final at = now ?? DateTime.now();
    _pruneHz(at);
    if (line.contains('GGA')) {
      final gga = parseGga(line);
      if (gga == null) {
        droppedCount++;
        return null;
      }
      _lastFixQuality = gga.fixQuality;
      return _emit(
        lat: gga.lat,
        lon: gga.lon,
        speedMps: _pendingSpeedMps,
        bearingDeg: _pendingBearingDeg,
        satellites: gga.satellites,
        hdop: gga.hdop ?? _lastGsaHdop,
        altitudeM: gga.altitudeM,
        at: at,
        isGga: true,
        countForHz: true,
      );
    }
    if (line.contains('RMC')) {
      final rmc = parseRmc(line);
      if (rmc == null) {
        droppedCount++;
        return null;
      }
      return _emit(
        lat: rmc.lat,
        lon: rmc.lon,
        speedMps: rmc.speedMps,
        bearingDeg: rmc.bearingDeg,
        satellites: _latest?.satellites,
        hdop: _latest?.hdop,
        // RMC 本身无海拔，沿用上一次 GGA 海拔；从未收到 GGA 时为 null。
        altitudeM: _latest?.altitudeM,
        timestampUtc: rmc.timestampUtc,
        at: at,
        // 无 GGA 的设备以 RMC 计次；有 GGA 时 RMC 不重复计次。
        countForHz: _ggaAt.isEmpty,
      );
    }
    if (line.contains('VTG')) {
      final vtg = parseVtg(line);
      if (vtg == null) {
        droppedCount++;
        return null;
      }
      _pendingSpeedMps = vtg.speedMps ?? _pendingSpeedMps;
      _pendingBearingDeg = vtg.bearingDeg ?? _pendingBearingDeg;
      if (_latest == null) return null; // 无位置时只暂存，不造点。
      return _emit(
        lat: _latest!.lat,
        lon: _latest!.lon,
        speedMps: _pendingSpeedMps,
        bearingDeg: _pendingBearingDeg,
        satellites: _latest!.satellites,
        hdop: _latest!.hdop,
        altitudeM: _latest!.altitudeM,
        timestampUtc: _latest!.timestampUtc,
        at: at,
      );
    }
    if (line.contains('GSA')) {
      final gsa = parseGsa(line);
      if (gsa == null) {
        droppedCount++;
        return null;
      }
      // GSA 无位置：只记模式 / 星数 / HDOP，不 emit、不刷新定位时间戳。
      _lastFixMode = gsa.fixType;
      _lastUsedSats = gsa.usedSatellites;
      _lastGsaHdop = gsa.hdop ?? _lastGsaHdop;
      return _latest;
    }
    // GGA/RMC/VTG/GSA 之外的语句（如 GSV/GLL）不在本期处理范围，
    // 直接忽略，不计入丢弃（它们不是错误语句）。
    return _latest;
  }

  ExternalGpsFix _emit({
    required double lat,
    required double lon,
    double? speedMps,
    double? bearingDeg,
    int? satellites,
    double? hdop,
    double? altitudeM,
    DateTime? timestampUtc,
    required DateTime at,
    bool isGga = false,
    bool countForHz = false,
  }) {
    if (isGga) {
      _acceptedAt.add(at);
      _ggaAt.add(at);
    } else if (countForHz) {
      _acceptedAt.add(at);
    }
    acceptedCount++;
    _lastFixAt = at;
    _pendingSpeedMps = null;
    _pendingBearingDeg = null;
    _latest = ExternalGpsFix(
      lat: lat,
      lon: lon,
      speedMps: speedMps,
      bearingDeg: bearingDeg,
      satellites: satellites,
      hdop: hdop,
      altitudeM: altitudeM,
      timestampUtc: timestampUtc,
      hz: hz,
      fixQuality: _lastFixQuality,
      fixMode: _lastFixMode,
      usedSatellites: _lastUsedSats,
    );
    return _latest!;
  }

  void reset() {
    _latest = null;
    _pendingSpeedMps = null;
    _pendingBearingDeg = null;
    _lastFixAt = null;
    _lastFixQuality = null;
    _lastFixMode = null;
    _lastUsedSats = null;
    _lastGsaHdop = null;
    _acceptedAt.clear();
    _ggaAt.clear();
    _buffer.clear();
  }
}
