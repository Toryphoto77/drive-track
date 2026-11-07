import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native.dart';

/// 直连卫星定位服务（v0.1.4 新增文件）。
///
/// 术语（不要夸大）：
/// - “直连卫星”只表示：位置来源只用 GPS Provider 的卫星定位，不再用
///   网络定位出位置（网络仅用于辅助星历 A-GPS，不直接出位置）。
///   它不等于厘米级精度，不提供 RTK 差分，精度上限由手机硬件决定。
/// - 卫星数：`usedCount` 为参与定位解算的卫星数，`visibleCount` 为
///   当前历元可见的卫星总数；行程点标注用 `usedCount`（见文末接线说明）。

/// 直连模式开关说明文案：总协调原样展示给用户，UI 不得自己另编、
/// 不得删掉限制句。包含任务要求的全部限制点。
const String kDirectSatelliteLimitations = '直连卫星模式：开启后位置只用卫星定位，网络仅辅助星历。' '精度上限由手机硬件决定，不等于厘米级精度，不提供 RTK 差分校正。' '室内、隧道、高楼遮挡下首次定位可能比融合定位更慢。关闭后恢复融合定位。';

/// 定位来源。行程点标注就用这组取值，不要另造字符串。
enum LocSource {
  gps,
  network,
  fused,
  external,
  unknown,
}

extension LocSourceLabel on LocSource {
  String get key => name;
  String get label => switch (this) {
        LocSource.gps => '卫星',
        LocSource.network => '网络',
        LocSource.fused => '融合',
        LocSource.external => '外接',
        LocSource.unknown => '未知',
      };

  /// Android Location.getProvider() 的原始值 -> 本枚举。
  /// 原生 location 事件的 provider 字段就是这个原始值。
  static LocSource fromProvider(String? provider) => switch (provider) {
        'gps' => LocSource.gps,
        'network' => LocSource.network,
        'fused' => LocSource.fused,
        'external' => LocSource.external,
        _ => LocSource.unknown,
      };
}

/// 星座。QZSS / IRNSS / SBAS 统一归为 other，不单独宣称支持某星座。
enum GnssConstellation { gps, beidou, galileo, glonass, other }

extension GnssConstellationLabel on GnssConstellation {
  String get key => name;
  String get label => switch (this) {
        GnssConstellation.gps => 'GPS',
        GnssConstellation.beidou => '北斗',
        GnssConstellation.galileo => 'Galileo',
        GnssConstellation.glonass => 'GLONASS',
        GnssConstellation.other => '其他',
      };
  static GnssConstellation fromKey(String k) =>
      GnssConstellation.values.firstWhere((e) => e.name == k,
          orElse: () => GnssConstellation.other);
}

/// 一次 GNSS 历元快照（原生 GnssStatus.Callback 上报，原样转发，不加工）。
class GnssSnapshot {
  /// 可见卫星总数。
  final int visibleCount;

  /// 参与定位解算的卫星数（行程点标注用这个数）。
  final int usedCount;

  /// 按星座分的可见卫星数。
  final Map<GnssConstellation, int> visibleByConstellation;

  /// 按星座分的参与解算卫星数。
  final Map<GnssConstellation, int> usedByConstellation;

  /// 平均载波噪声密度 CN0（dB-Hz，Android 10+ 才有；无数据时为 null，
  /// 不要拿 -1 冒充数值）。
  final double? avgCn0DbHz;

  /// 本历元是否观测到 L5 频点信号。注意：这只是“本历元见过 L5”，
  /// 不是机型双频能力的鉴定结论，不得在界面上写成“支持双频”。
  final bool l5Seen;

  final int timeMs;

  const GnssSnapshot({
    required this.visibleCount,
    required this.usedCount,
    required this.visibleByConstellation,
    required this.usedByConstellation,
    required this.avgCn0DbHz,
    required this.l5Seen,
    required this.timeMs,
  });

  static GnssSnapshot fromMap(Map<String, dynamic> m) {
    Map<GnssConstellation, int> parse(String key) {
      final raw = m[key];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(
          GnssConstellationLabel.fromKey(k.toString()),
          (v as num).toInt()));
    }

    final cn0 = (m['avgCn0'] as num?)?.toDouble();
    return GnssSnapshot(
      visibleCount: (m['visible'] as num?)?.toInt() ?? 0,
      usedCount: (m['used'] as num?)?.toInt() ?? 0,
      visibleByConstellation: parse('byConstellation'),
      usedByConstellation: parse('usedByConstellation'),
      avgCn0DbHz: (cn0 == null || cn0 < 0) ? null : cn0,
      l5Seen: (m['l5Seen'] as bool?) ?? false,
      timeMs: (m['timeMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  int visibleOf(GnssConstellation c) => visibleByConstellation[c] ?? 0;
  int usedOf(GnssConstellation c) => usedByConstellation[c] ?? 0;
}

class SatelliteService extends ChangeNotifier {
  SatelliteService._();
  static final SatelliteService instance = SatelliteService._();

  GnssSnapshot? _latest;
  LocSource _source = LocSource.unknown;
  bool _directMode = false;
  bool _listening = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  GnssSnapshot? get latest => _latest;
  LocSource get source => _source;
  bool get directMode => _directMode;

  int get visibleCount => _latest?.visibleCount ?? 0;
  int get usedCount => _latest?.usedCount ?? 0;
  double? get avgCn0DbHz => _latest?.avgCn0DbHz;

  /// 开始监听原生 GNSS 事件流（drivetrack/gnss）。重复调用无副作用。
  void start() {
    if (_listening) return;
    _listening = true;
    _sub = Native.gnssStream.listen((e) {
      _latest = GnssSnapshot.fromMap(e);
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _listening = false;
  }

  /// 开启/关闭直连模式。原生侧行为（见 MainActivity.setDirectSatelliteMode）：
  /// - 开启：若正在定位，先 removeUpdates 再只注册 GPS_PROVIDER；
  ///   同时注册 GnssStatus.Callback 上报卫星信息；
  /// - 关闭：恢复 GPS + NETWORK 双 Provider（即现有 startLocation 行为）。
  /// 返回原生回执；定位权限未授予时返回 ok=false + error，不假装已切换。
  Future<Map<String, dynamic>> setDirectMode(bool enabled) async {
    final r = await Native.setDirectSatelliteMode(enabled);
    if ((r['ok'] as bool?) == true) {
      _directMode = enabled;
      _source = enabled ? LocSource.gps : LocSource.fused;
      notifyListeners();
    }
    return r;
  }

  /// 取一次原生快照（无事件流时也能拿到最后一次历元；从未收到过时
  /// 返回 available=false，调用方显示“暂无卫星数据”，不要编数字）。
  Future<GnssSnapshot?> refreshSnapshot() async {
    try {
      final r = await Native.getGnssStatus();
      if ((r['available'] as bool?) != true) return null;
      _latest = GnssSnapshot.fromMap(r);
      notifyListeners();
      return _latest;
    } catch (_) {
      return null;
    }
  }

  /// 供行程记录接线：把一次定位事件的来源归一化。
  /// 原生 location 事件的 provider 字段直接传进来即可。
  void noteLocationProvider(String? provider) {
    final s = LocSourceLabel.fromProvider(provider);
    if (s != LocSource.unknown) {
      _source = _directMode ? LocSource.gps : s;
      notifyListeners();
    }
  }
}

/// ---- 给 Recorder / TrackPoint 的接线字段说明（本文件不改那两个文件） ----
///
/// 总协调需做的两处改动（缺一不可，否则行程点标不上卫星信息）：
/// 1) models.dart 的 TrackPoint 新增两个字段（其余构造/序列化照旧）：
///      final int? satCount;    // 参与解算的卫星数，JSON 键 'sat'
///      final String locSource; // LocSource.key，JSON 键 'locSrc'，默认 ''
///    注意：外接 GPS 注入点（provider='external'）的 satCount 由 BleDIY
///    的 GGA 句卫星数填，locSource='external'，不要填手机 GNSS 的数。
/// 2) recorder.dart 的 onLocation() 里，构造 TrackPoint 时新增：
///      satCount: (e['satCount'] as num?)?.toInt(),   // 原生已随定位事件下发
///      locSource: (e['provider'] as String?) ?? '',
///    原生侧 MainActivity.onLocationChanged 已把最近一次 Gnss 回调的
///    usedCount 放进定位事件的 'satCount' 键（从未收到 GNSS 回调时为 -1，
///    Recorder 收到 -1 应存 null，不要把 -1 写进轨迹文件）。
///    直连模式下 provider 恒为 'gps'，locSource 自然就是 'gps'。
