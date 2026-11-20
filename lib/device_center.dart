import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'card_style.dart';
import 'device_hardware_card.dart';

import 'app_bar_style.dart';
import 'home_layout.dart';
import 'blediy_gps.dart';
import 'bt_gps_receiver.dart';
import 'camera_connect_page.dart';
import 'device_icons.dart';
import 'device_scan_card.dart';
import 'firmware_update_service.dart';
import 'gps_source.dart';
import 'native.dart';
import 'obd_service.dart';
import 'store.dart';
import 'video_import_match.dart';

/// 外接设备中心：运动相机 + 其他传感器 + BleDIY GPS。
///
/// 本页是独立 widget，构造函数只用回调参数，绝不引用 main.dart 的类，
/// 总协调集成时只需在导航里 push 本页即可。
/// 黑底 + 主题色（默认法拉利红，随 App 主题预设走），零新增 pub 插件。

enum DeviceLinkStatus { disconnected, connecting, connected, unavailable }

extension DeviceLinkStatusLabel on DeviceLinkStatus {
  String get label => switch (this) {
    DeviceLinkStatus.disconnected => '未连接',
    DeviceLinkStatus.connecting => '连接中…',
    DeviceLinkStatus.connected => '已连接',
    DeviceLinkStatus.unavailable => '暂不可用',
  };
}

/// 本机保存的一台通用传感器。地址可选：没填地址就无法下次重连，
/// 界面会明说，而不是假装能重连。
class SavedDevice {
  const SavedDevice({
    required this.name,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.type,
    this.address,
  });

  final String name;
  final String serviceUuid;
  final String characteristicUuid;
  final String type;
  final String? address;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'serviceUuid': serviceUuid,
    'characteristicUuid': characteristicUuid,
    'type': type,
    if (address != null && address!.isNotEmpty) 'address': address,
  };

  static SavedDevice fromJson(Map<String, dynamic> json) => SavedDevice(
    name: (json['name'] ?? '').toString(),
    serviceUuid: (json['serviceUuid'] ?? '').toString(),
    characteristicUuid: (json['characteristicUuid'] ?? '').toString(),
    type: (json['type'] ?? '其他').toString(),
    address: (json['address'] as String?)?.isEmpty == true
        ? null
        : json['address'] as String?,
  );
}

/// UUID 校验与归一化：接受完整 128-bit，或 4/8 位短 UUID（按蓝牙
/// base UUID 展开）。格式不对返回 null，调用方拒绝保存并提示。
String? normalizeUuid(String input) {
  final v = input.trim().toLowerCase();
  final full = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (full.hasMatch(v)) return v;
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(v)) {
    return '0000$v-0000-1000-8000-00805f9b34fb';
  }
  if (RegExp(r'^[0-9a-f]{8}$').hasMatch(v)) {
    return '$v-0000-1000-8000-00805f9b34fb';
  }
  return null;
}

/// 已保存设备的本机存储：Native.getFilesDir() 下的 JSON 文件。
/// 注意：这是 Dart 侧自行读写的文件，与原生层无关；文件名固定，
/// 总协调不要另起一个名字造成两份清单。
class DeviceCenterStore {
  static const String fileName = 'device_center_devices.json';

  static Future<List<SavedDevice>> load() async {
    try {
      final dir = await Native.getFilesDir();
      final file = File('$dir/$fileName');
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => SavedDevice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> save(List<SavedDevice> devices) async {
    try {
      final dir = await Native.getFilesDir();
      final file = File('$dir/$fileName');
      await file.writeAsString(
        jsonEncode(devices.map((d) => d.toJson()).toList()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 外接 GPS 模块的设备类别（v1.0.2，第 6 项；后扩至兼容清单，
/// 每设备只出现一次，绝不平行建第二张表）。
///
/// 支持程度必须如实标注，绝不冒充，分三档：
/// - 已实现通用 NMEA 解析（blediy_gps.dart 的 GGA / RMC / VTG / GSA），
///   且服务 / 特征 UUID 已确认 → 正常订阅解析；
/// - 服务 UUID 已验证、但协议是二进制且包格式未验证（如 DEXIAN D1，
///   官方 App 拆包实锤）→ 只连通、不订阅、不解析，[binaryProtocol]
///   为 true，[txUuid] 保持 null，绝不硬编特征 UUID 与解析逻辑；
/// - 其余厂商私有协议只要没公开文档、没实测设备，一律标“协议未公开 /
///   未实测验证，仅通用 NMEA 兼容”，且 [serviceUuid] / [txUuid] 保持 null，
///   绝不凭猜测填一个 UUID。无 UUID 不再等于“无法连接”：无 UUID 的
///   类别走名称匹配 + 通用 NUS 订阅尝试 + SPP 连接尝试（见本区连接逻辑）。
///   二进制协议类别不走 NUS 订阅尝试（见 _connectScanned）。
enum ExternalGpsKind {
  blediy,
  garminGlo,
  dualXgps,
  qstarz,
  columbus,
  vboxSport,
  racebox,
  dexian,
  digspice,
  dragy,
  genericBt,
  genericNmea,
}

/// 一类外接 GPS 的档案。serviceUuid / txUuid 为 null = 该厂商
/// 没有公开可确认的 BLE 服务 / 特征 UUID，本 App 不按 UUID 自动订阅它
///（改走名称匹配 / NUS 尝试 / SPP，见本区连接逻辑）。
/// [nameHints]：扫描行名称匹配用（仅提示，不作身份断言；短提示词
/// 按整词匹配，见 bt_gps_receiver.dart）；[namePattern]：官方广播名
/// 模式字符串（如 D1 的 ^dexian\s+(\w+)-(\w+)$），命中即名称证据，优先于
/// 短提示词兜底。
/// [binaryProtocol]：二进制协议（非 NMEA），服务 UUID 已验证但包格式
/// 未验证：只连通、不订阅、不解析定位，绝不落入通用 NUS 的 NMEA 订阅。
/// [adapterId]：私有协议 stub 的注册表 id（bt_gps_receiver.dart），
/// null = 无私有协议 stub、只走通用 NMEA。
class ExternalGpsProfile {
  const ExternalGpsProfile({
    required this.kind,
    required this.name,
    required this.note,
    this.serviceUuid,
    this.txUuid,
    this.nameHints = const [],
    this.namePattern,
    this.binaryProtocol = false,
    this.adapterId,
  });

  final ExternalGpsKind kind;
  final String name;
  final String note;
  final String? serviceUuid;
  final String? txUuid;
  final List<String> nameHints;
  final String? namePattern;
  final bool binaryProtocol;
  final String? adapterId;

  /// 是否有可确认的 NMEA 订阅路径（不是“厂商已完整支持”）。
  bool get hasNmeaPath => serviceUuid != null && txUuid != null;

  /// 页面上的支持程度徽标文案。
  String get supportBadge {
    if (binaryProtocol) return '二进制协议（包格式待实测）';
    return hasNmeaPath ? '通用 NMEA 兼容' : '协议未公开 / 未实测验证，仅通用 NMEA 兼容';
  }
}

/// 四类外接 GPS 档案。调研结论（2026-11-03 公开搜索，见回执）：
/// - BleDIY：已有 blediy_gps.dart 解析；NUS UUID 是 Nordic 通用
///   默认值，非 BleDIY 专属值（blediy_gps.dart 已注明）。
/// - Dragy（DRG70 / DRG70-C / Pro DRG71）：公开资料只确认蓝牙
///   连接、10Hz（Pro 25Hz）与 u-blox 芯片，未找到官方 BLE 服务 /
///   特征 UUID 与数据格式文档；本 App 不解析该设备私有数据流。
/// - DEXIAN D1：Dexian Timer 官方 App（1.3.2）拆包实锤（2026-11-06）：
///   BLE 服务 UUID 为 00000003-0000-1000-8000-00805f9b34fb，官方 App
///   扫描即按此服务过滤；设备广播名匹配 ^dexian\s+(\w+)-(\w+)$（如
///   dexian D1-XXXX，大小写不敏感）；25Hz（用户确认）。D1 走二进制协议
///   （非 NMEA），官方 App 里无任何 NMEA 句标识，位置数据是二进制包经
///   ByteData 解析，订阅分 GPS 数据 / GPS 时间 / 电池三路；数据特征候选
///   为 00000004-…与 00001ff8-…（哪路对应哪个未确认），包格式待实测抓包，
///   本档案不硬编特征 UUID 与解析逻辑。BleDIY 服务 UUID
///   （00001ff8-…）是 DIY 设备的公开规范，不是 D1 的实测值，绝不能硬说成
///   D1 的值。
/// - 通用 NMEA BLE UART：默认 Nordic UART，可改填设备实际广播值。
const List<ExternalGpsProfile> externalGpsProfiles = [
  ExternalGpsProfile(
    kind: ExternalGpsKind.blediy,
    name: 'BleDIY',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    nameHints: ['blediy'],
    note: 'NMEA 文本经 BLE UART 推送时可订阅解析；服务 / 特征以设备实际广播为准。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.garminGlo,
    name: 'Garmin GLO',
    nameHints: ['garmin', 'glo'],
    note: '需输出标准 NMEA；请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dualXgps,
    name: 'Dual XGPS 150 / 160',
    nameHints: ['dual', 'xgps'],
    note: '需输出标准 NMEA；请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.qstarz,
    name: 'Qstarz BL-818GT / BL-1000GT / LT-8000GT',
    nameHints: ['qstarz', 'bl-818', 'bl-1000', 'lt-8000'],
    note: '需输出标准 NMEA（LT-8000GT 另可试 BLE 名称匹配）；请先在系统蓝牙里配对。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.columbus,
    name: 'Columbus P-9 Race',
    nameHints: ['columbus', 'p-9'],
    note: '需输出标准 NMEA；请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.vboxSport,
    name: 'VBOX Sport',
    nameHints: ['vbox'],
    note: '需输出标准 NMEA；请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.racebox,
    name: 'RaceBox Mini / Mini S / Micro',
    serviceUuid: raceboxNmeaServiceUuid,
    txUuid: raceboxNmeaTxUuid,
    nameHints: ['racebox'],
    adapterId: 'racebox_ubx',
    note: '固件 3.3+ 提供标准 NMEA UART 服务，可按此订阅。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dexian,
    name: 'DEXIAN D1',
    serviceUuid: dexianServiceUuid,
    namePattern: dexianBroadcastNamePattern,
    nameHints: ['dexian'],
    binaryProtocol: true,
    note: 'D1 走二进制协议，本版只连接，不出定位。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.digspice,
    name: 'DigSpice IV',
    nameHints: ['digspice'],
    note: '按标准 NMEA 实现（BLE 名称匹配 + SPP 兜底）。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dragy,
    name: 'Dragy Pro / DRG70 / DRG70-C / Lite',
    nameHints: ['dragy', 'drg'],
    adapterId: 'dragy_proprietary',
    note: '本 App 不解析厂商私有数据流；设备输出标准 NMEA 即可工作，否则暂不支持。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.genericBt,
    name: '通用蓝牙 GPS（SPP）',
    note: '请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”或“经典蓝牙搜索”连接；只解析标准 NMEA 文本。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.genericNmea,
    name: '通用 NMEA BLE UART',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    note: '下方可改填设备实际广播的服务 / 特征 UUID；只解析标准 NMEA 文本。',
  ),
];

/// 档案的名称证据：官方广播名模式（如 D1 的 ^dexian\s+(\w+)-(\w+)$）
/// 命中即名称证据；模式未命中时短提示词兜底（见 btGpsNameMatches）。
bool _profileNameMatches(ExternalGpsProfile p, String name) {
  final pattern = p.namePattern;
  if (pattern != null && RegExp(pattern, caseSensitive: false).hasMatch(name)) {
    return true;
  }
  return btGpsNameMatches(name, p.nameHints);
}

/// 单入口“可适配设备”过滤（纯函数，可单测）：服务 UUID 证据优先——
/// 档案里有已确认服务 UUID 的设备（如 DEXIAN D1 的 00000003-…、
/// NMEA UART 的 00001101），广播到即进主列表；其次是档案名录的
/// 名称证据（官方广播名模式 / 提示词）；最后是通用 NUS / SPP 服务
/// 广播。名称与服务证据都没有的设备（如耳机）不进主列表；
/// v1.5.4 高级区已删，不可适配的设备不再于本页另行列出。
bool gpsDeviceIsAdaptable(Map<String, dynamic> dev) {
  final name = (dev['name'] ?? '').toString();
  final uuids = ((dev['serviceUuids'] as List?) ?? [])
      .map((e) => e.toString().toLowerCase())
      .toList();
  for (final p in externalGpsProfiles) {
    final s = p.serviceUuid?.toLowerCase();
    if (s != null && uuids.contains(s)) return true;
  }
  for (final p in externalGpsProfiles) {
    if (_profileNameMatches(p, name)) return true;
  }
  if (uuids.any((u) => u.contains('6e400001'))) return true;
  if (uuids.any((u) => u.contains('00001101'))) return true;
  return false;
}

/// 单入口自动连接的档案推导（纯函数，可单测）：D1 服务 UUID 证据优先
///（00000003-…只可能是 DEXIAN D1）；其次名称证据（官方广播名模式 /
/// 提示词）；NMEA UART 服务广播排在名称之后——00001101 也是通用
/// SPP 服务 UUID，先按名称会误把 SPP 设备认成 NMEA 设备；其余一律走
/// 通用 NMEA（NUS 默认值），由连接逻辑按广播事实订阅。
ExternalGpsKind gpsProfileKindForDevice(Map<String, dynamic> dev) {
  final name = (dev['name'] ?? '').toString();
  final uuids = ((dev['serviceUuids'] as List?) ?? [])
      .map((e) => e.toString().toLowerCase())
      .toList();
  if (uuids.contains(dexianServiceUuid.toLowerCase())) {
    return ExternalGpsKind.dexian;
  }
  for (final p in externalGpsProfiles) {
    if (_profileNameMatches(p, name)) return p.kind;
  }
  if (uuids.contains(raceboxNmeaServiceUuid.toLowerCase())) {
    return ExternalGpsKind.racebox;
  }
  return ExternalGpsKind.genericNmea;
}

/// 外接 GPS 模块区（v1.0.2，第 6 项），供 DeviceCenterPage 嵌入。
/// 本区是 App 内唯一的蓝牙 GPS 连接入口，不另起平行入口。
///
/// 单入口主流程（像系统蓝牙连接页）：顶部「扫描适配设备」一键扫完
/// 全渠道（NUS / D1 服务过滤扫描、无过滤 BLE 扫描、经典蓝牙发现、已配对 SPP），
/// 结果按地址去重合并；主列表只显示过滤后的可适配设备（档案名录匹配、
/// 广播已验证的厂商服务如 DEXIAN D1 的 00000003，或广播 NMEA UART / SPP 服务），
/// 点行即自动连接（BLE 优先、只有 SPP 通道时走 SPP，档案由设备推导、
/// 不再要求先选档案卡）。行内显示连接中 → 已连接 → 定位状态 / 卫星数 / 更新率。
/// v1.5.4：原高级 / 手动添加区已删（档案卡浏览、自定义 UUID、分别
/// 扫描、全部扫描结果均不在此页；扫描只走「扫描适配设备」）。
///
/// 定位源切换复用现有链路，不另造一套：本区做扫描 → 连接 → 订阅 /
/// 直读 NMEA；BLE 通知（NMEA 特征）与 SPP 文本（sppNmea）都经
/// main.dart 已有的全局 bleData 监听喂给 BleDiyGpsFeed，有效定位
/// 注入 Recorder：externalGpsActive = true，行程落点改走
/// Recorder.onExternalFix；外部源 5 秒无新定位或断线时，main.dart
/// 的回落逻辑自动切回手机 GPS。本区不直接持有 Recorder。
///
/// 单点连接状态（不两处各管各）：
/// - [_connectedAddress] + [_connectedChannel]（'ble' / 'spp'）是唯一
///   连接状态；切通道、连新设备时先断开旧连接；页级传感器连接
///   不再误翻本区状态（connected 事件只认本区发起的 [_connectingAddress]）。
/// - 扫描列表 [_scanned] 全渠道合并：BLE NUS 扫描、无过滤 BLE 扫描
///   （名称匹配）、经典蓝牙发现、已配对 SPP 列表全部按地址去重，
///   一设备一行；主列表自动选通道，点行即连。
/// - 无过滤扫描与经典发现走 btGpsDeviceStream，不进页级 bleDeviceStream，
///   页级“附近扫描结果”不会因此多出重复设备。
///
/// 原生层限制（必须如实显示，不假装全量扫描）：
/// - NUS / D1 服务过滤扫描：不广播这两个服务的设备扫不到，须用无过滤扫描
///   （名称匹配）或经典蓝牙 / 已配对 SPP 路径；主按钮已一次全扫。
/// - 原生单 GATT：一次只能连一台 BLE 设备，连新设备会断开旧的；
///   SPP 不占 GATT 名额，可与 BLE 传感器共存。
class ExternalGpsSection extends StatefulWidget {
  const ExternalGpsSection({super.key, this.onPaired});

  /// 设备真正连上（BLE / SPP）时回调一次：把这次连接的服务 / 特征
  /// UUID 与名称交给设备中心落盘，供“我的设备”展示和开机自动重连。
  /// 设备中心是唯一的持久化写入方，本区不自己写文件。
  final void Function(SavedDevice device)? onPaired;

  @override
  State<ExternalGpsSection> createState() => _ExternalGpsSectionState();
}

class _ExternalGpsSectionState extends State<ExternalGpsSection> {
  ExternalGpsKind _kind = ExternalGpsKind.blediy;
  final _customServiceCtrl = TextEditingController(text: nordicUartServiceUuid);
  final _customTxCtrl = TextEditingController(text: nordicUartTxUuid);
  final List<Map<String, dynamic>> _scanned = [];
  // 单入口主按钮的合并扫描状态；停任一 BLE 扫描即清零（stopBleScan
  // 同时停过滤与无过滤扫描），经典发现结束不单独清零（BLE 部分仍在扫）。
  bool _adaptScanning = false;
  String? _notice;
  String? _permNotice;
  String? _connectedAddress;
  // 已连接外置 GPS 的广播名（供共享状态显示用，见 _publishGpsStatus）。
  String? _connectedName;
  // 本区唯一的连接通道：'ble' | 'spp'；null = 未连接。
  String? _connectedChannel;
  // 本区正在发起连接的地址：connected / sppConnected 事件只认它，
  // 页级传感器连接不再误翻本区状态。
  String? _connectingAddress;
  String? _subscribeError;
  // 已连接后待订阅的 (address, service, tx)；GATT 服务发现是异步的，
  // 连接事件到达时若立即订阅报 characteristic_not_found，会在
  // connected 事件里再试一次（见 _dataSub）。
  ({String address, String service, String tx})? _pendingSubscribe;

  /// v1.7.0：连上自研硬件后，本卡切换为硬件管理界面（电量、固件、
  /// 实时状态、圈速导入、关机）。判定条件：设备热点 /api/info 可达，
  /// 或广播名带 DriveTrack 前缀。第三方 GPS 不会误进管理界面。
  bool _showHardwareCard = false;

  final BleDiyGpsFeed _feed = BleDiyGpsFeed();
  StreamSubscription<Map<String, dynamic>>? _devSub;
  StreamSubscription<Map<String, dynamic>>? _dataSub;
  StreamSubscription<Map<String, dynamic>>? _btGpsSub;

  /// 全渠道扫描列表按地址合并：一设备一行，通道取并集；已配对标记
  /// 透传保留（主列表用它显示“已配对”，未配对的经典发现不冒充）。
  void _mergeScanned(
    Map<String, dynamic> e,
    String channel, {
    bool bonded = false,
  }) {
    final addr = (e['address'] ?? '').toString();
    if (addr.isEmpty) return;
    final merged = <String, dynamic>{...e};
    final channels = <String>{channel};
    var wasBonded = bonded;
    final oldIndex = _scanned.indexWhere((d) => d['address'] == addr);
    if (oldIndex >= 0) {
      final old = _scanned[oldIndex];
      for (final c in (old['channels'] as List? ?? <dynamic>[])) {
        channels.add(c.toString());
      }
      if ((merged['serviceUuids'] as List?)?.isEmpty ?? true) {
        merged['serviceUuids'] = old['serviceUuids'];
      }
      if ((merged['name'] ?? '').toString().isEmpty) {
        merged['name'] = old['name'];
      }
      if (old['bonded'] == true) wasBonded = true;
      _scanned.removeAt(oldIndex);
    }
    merged['channels'] = channels.toList();
    if (wasBonded) merged['bonded'] = true;
    _scanned.insert(0, merged);
  }

  ExternalGpsProfile get _profile =>
      externalGpsProfiles.firstWhere((p) => p.kind == _kind);

  /// 通用 NMEA 类当前生效的服务 / 特征：通用类用下方输入框的值
  ///（归一化失败时回落 NUS 默认值并在界面提示），其余有 UUID 的
  /// 类用档案值，无 UUID 的类返回 null。
  ({String service, String tx})? get _effectiveUuids {
    if (_kind == ExternalGpsKind.genericNmea) {
      final s = normalizeUuid(_customServiceCtrl.text) ?? nordicUartServiceUuid;
      final t = normalizeUuid(_customTxCtrl.text) ?? nordicUartTxUuid;
      return (service: s, tx: t);
    }
    final p = _profile;
    if (p.serviceUuid == null || p.txUuid == null) return null;
    return (service: p.serviceUuid!, tx: p.txUuid!);
  }

  @override
  void initState() {
    super.initState();
    _devSub = Native.bleDeviceStream.listen((e) {
      if (!mounted) return;
      setState(() => _mergeScanned(e, 'ble'));
    }, onError: (_) {});
    // GPS 专用发现流：无过滤 BLE 扫描与经典蓝牙发现，不进页级列表。
    _btGpsSub = Native.btGpsDeviceStream.listen((e) {
      if (!mounted) return;
      final type = (e['type'] ?? '').toString();
      if (type == 'classicDiscoveryFinished') {
        setState(() => _notice = '经典蓝牙搜索完成。');
        return;
      }
      if (type == 'bleScanFailed') {
        setState(() => _notice = '蓝牙 GPS 扫描失败。');
        return;
      }
      setState(() => _mergeScanned(e, type == 'classic' ? 'spp' : 'ble'));
    }, onError: (_) {});
    _dataSub = Native.bleDataStream.listen((e) async {
      final type = (e['type'] ?? '').toString();
      if (!mounted) return;
      if (type == 'connected') {
        final addr = (e['address'] ?? '').toString();
        // 只认本区发起的连接：页级传感器连接不再误翻本区状态。
        if (_connectingAddress != null && _connectingAddress != addr) return;
        setState(() {
          _connectedAddress = addr.isEmpty ? null : addr;
          _connectedChannel = addr.isEmpty ? null : 'ble';
          _connectingAddress = null;
        });
        _publishGpsStatus();
        _notifyPaired();
        _detectHardware();
        final pending = _pendingSubscribe;
        if (pending != null && pending.address == addr) {
          await _doSubscribe(pending.address, pending.service, pending.tx);
        }
      } else if (type == 'servicesDiscovered') {
        // GATT 服务发现完成：connected 时立刻订阅通常拿不到特征
        //（characteristic_not_found），在这里重试一次即可成功。
        final pending = _pendingSubscribe;
        if (pending != null) {
          await _doSubscribe(pending.address, pending.service, pending.tx);
        }
      } else if (type == 'disconnected') {
        if (_connectedChannel != 'ble') return;
        setState(() {
          _connectedAddress = null;
          _connectedChannel = null;
          _pendingSubscribe = null;
          _connectingAddress = null;
          _notice = '外接 GPS 已断开，行程定位已回落手机 GPS。';
          _showHardwareCard = false;
        });
        _connectedName = null;
        _publishGpsStatus();
        _feed.reset();
      } else if (type == 'sppConnected') {
        final addr = (e['address'] ?? '').toString();
        if (_connectingAddress != null && _connectingAddress != addr) return;
        setState(() {
          _connectedAddress = addr.isEmpty ? null : addr;
          _connectedChannel = addr.isEmpty ? null : 'spp';
          _connectingAddress = null;
          _notice = 'SPP 已连接，行程改用外接 GPS。';
        });
        _publishGpsStatus();
        _notifyPaired();
        _detectHardware();
      } else if (type == 'sppDisconnected') {
        if (_connectedChannel != 'spp') return;
        setState(() {
          _connectedAddress = null;
          _connectedChannel = null;
          _pendingSubscribe = null;
          _connectingAddress = null;
          _notice = 'SPP 已断开（${e['reason'] ?? ''}），行程定位回落手机 GPS。';
          _showHardwareCard = false;
        });
        _connectedName = null;
        _publishGpsStatus();
        _feed.reset();
      } else if (type == 'sppNmea') {
        final line = (e['line'] ?? '').toString();
        if (line.isEmpty) return;
        _feed.feedLine(line);
        if (!mounted) return;
        setState(() {});
      } else if (type == 'bleNotification') {
        // 二进制协议设备（如 DEXIAN D1）：通知字节不进 NMEA 解析器，
        // 在门口直接丢弃（现有丢弃规则），绝不解析成定位、绝不出假定位。
        // 正常路径仍只喂 NMEA 特征的通知进 GPS 解析器：页级传感器通知
        //（功率计 / 踏频 / 心率）不再误喂，避免二进制数据污染解析。
        if (_profile.binaryProtocol) return;
        final cu = (e['characteristicUuid'] ?? '').toString().toLowerCase();
        final tx = _effectiveUuids?.tx.toLowerCase() ?? '';
        final isNmea =
            cu.contains('0003') || (tx.isNotEmpty && cu.contains(tx));
        if (!isNmea) return;
        final bytes =
            (e['bytes'] as List?)?.map((v) => (v as num).toInt()).toList() ??
            <int>[];
        if (bytes.isEmpty) return;
        _feed.feedBytes(bytes);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _devSub?.cancel();
    _dataSub?.cancel();
    _btGpsSub?.cancel();
    _customServiceCtrl.dispose();
    _customTxCtrl.dispose();
    super.dispose();
  }

  /// 判断刚连上的设备是否自研硬件：设备热点 /api/info 可达，
  /// 或广播名以 DriveTrack 开头。命中才把扫描卡换成硬件管理卡；
  /// 第三方 GPS（Garmin / RaceBox 等）保持原界面。
  Future<void> _detectHardware() async {
    final name = (_connectedName ?? '').toLowerCase();
    final looksOwn =
        name.startsWith('drivetrack') || name.contains('drivetrack');
    FirmwareUpdateService? service;
    try {
      service = FirmwareUpdateService();
      final info = await service.probeDevice(
        timeout: const Duration(seconds: 2),
      );
      if (!mounted) return;
      if (info != null || looksOwn) {
        setState(() => _showHardwareCard = true);
      }
    } catch (_) {
      if (mounted && looksOwn) setState(() => _showHardwareCard = true);
    } finally {
      service?.close();
    }
  }

  /// 蓝牙 + 定位权限按系统流程申请（分步 requestStep），拒绝时
  /// 给明确提示 + 系统设置入口，不崩溃、不静默失败。
  Future<bool> _ensureBtPermissions() async {
    try {
      final snap = await Native.checkPermissions();
      var btOk = snap['bluetooth'] == true;
      var locOk = snap['location'] == true;
      if (!btOk) {
        final r = await Native.requestStep('extras');
        btOk = r['bluetooth'] == true;
      }
      if (!locOk) {
        final r2 = await Native.requestStep('foreground');
        locOk = r2['location'] == true;
      }
      if (!mounted) return false;
      setState(
        () => _permNotice = (btOk && locOk)
            ? null
            : '蓝牙 GPS 需要蓝牙与定位权限，请在系统设置里打开后重试。',
      );
      return btOk && locOk;
    } catch (e) {
      if (mounted) setState(() => _permNotice = '权限检查失败：$e');
      return false;
    }
  }

  /// 把刚连上的设备交给设备中心落盘（“我的设备”）。
  /// BLE 保存当前生效的服务 / 特征 UUID，SPP 没有 UUID 只存地址；
  /// 这样下次开机自动重连时能直接订阅 NMEA，不必再走一遍配对。
  void _notifyPaired() {
    final addr = _connectedAddress;
    if (addr == null || addr.isEmpty) return;
    final uuids = _effectiveUuids;
    final rawName = _connectedName?.trim() ?? '';
    final tail = addr.length >= 5 ? addr.substring(addr.length - 5) : addr;
    widget.onPaired?.call(
      SavedDevice(
        name: rawName.isNotEmpty ? rawName : 'GPS $tail',
        serviceUuid: uuids?.service ?? '',
        characteristicUuid: uuids?.tx ?? '',
        type: '外接GPS',
        address: addr,
      ),
    );
  }

  /// 把本区连接状态同步到共享源（gps_source.dart 的
  /// externalGpsStatus），供赛道设置页等处只读显示。唯一写入方
  /// 在这里；状态只在内存里，不持久化。D1 这类二进制协议设备
  /// binaryOnly 为 true：已连通但不出定位。
  void _publishGpsStatus() {
    final addr = _connectedAddress;
    if (addr == null) {
      updateExternalGpsStatus(ExternalGpsStatus.disconnected);
      return;
    }
    updateExternalGpsStatus(
      ExternalGpsStatus(
        connected: true,
        deviceName: _connectedName ?? addr,
        channel: _connectedChannel ?? 'ble',
        binaryOnly: _profile.binaryProtocol,
      ),
    );
  }

  /// 连新设备前若已连其它地址，先静默断开旧连接（单点状态）。
  Future<void> _disconnectCurrentQuietlyIfOther(String addr) async {
    if (_connectedAddress != null && _connectedAddress != addr) {
      try {
        if (_connectedChannel == 'spp') {
          await Native.disconnectSpp();
        } else {
          await Native.disconnectBle();
        }
      } catch (_) {}
      _feed.reset();
      if (!mounted) return;
      setState(() {
        _connectedAddress = null;
        _connectedChannel = null;
        _pendingSubscribe = null;
        _connectingAddress = null;
      });
      _connectedName = null;
      _publishGpsStatus();
    }
  }

  /// 手动断开当前已连的外接 GPS（v1.5.4：高级区删除后，本方法是
  /// 页内唯一的 GPS 显式断开入口；不断开则换设备时仍由
  /// _connectAdaptable 经 _disconnectCurrentQuietlyIfOther 静默
  /// 断开旧连接）。按当前通道断开（SPP 走 disconnectSpp，其余
  /// 走 disconnectBle），清状态并回落手机 GPS。
  Future<void> _disconnectGps() async {
    if (_connectedAddress == null) return;
    try {
      if (_connectedChannel == 'spp') {
        await Native.disconnectSpp();
      } else {
        await Native.disconnectBle();
      }
    } catch (_) {}
    _feed.reset();
    if (!mounted) return;
    setState(() {
      _connectedAddress = null;
      _connectedChannel = null;
      _pendingSubscribe = null;
      _connectingAddress = null;
      _notice = '外接 GPS 已断开，行程定位已回落手机 GPS。';
    });
    _connectedName = null;
    _publishGpsStatus();
  }

  /// 单入口主按钮：一次扫完可适配 GPS 全渠道（NUS 过滤扫描、
  /// 无过滤 BLE 扫描、经典蓝牙发现、已配对 SPP），结果进同一合并列表；
  /// 主列表只显示过滤后的可适配设备。再点一次则全部停掉。
  /// 原生层：过滤扫描与无过滤扫描是两个独立回调，可并存；stopBleScan
  /// 同时停掉两者。经典发现结束不单独清合并状态（BLE 部分仍在扫）。
  Future<void> _toggleAdaptScan() async {
    if (_adaptScanning) {
      try {
        await Native.stopBleScan();
      } catch (_) {}
      try {
        await Native.stopClassicDiscovery();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _adaptScanning = false;
        _notice = '已停止扫描。';
      });
      return;
    }
    if (!await _ensureBtPermissions()) return;
    try {
      // 服务过滤扫描同时带 NUS 与 DEXIAN D1 服务（00000003-…，官方 App
      // 拆包已验证）：D1 广播该服务即被过滤扫描直接命中，不靠名称猜。
      await Native.scanBleWithServices([
        nordicUartServiceUuid,
        dexianServiceUuid,
      ]);
      await Native.scanBleUnfiltered();
      await Native.startClassicDiscovery();
      final bonded = await Native.listBondedSppDevices();
      if (!mounted) return;
      setState(() {
        _adaptScanning = true;
        for (final d in bonded) {
          _mergeScanned(d, 'spp', bonded: true);
        }
        _notice = S.current.t(
          '正在扫描附近 GPS（BLE、经典蓝牙、已配对）…',
          'Scanning nearby GPS (BLE, classic, paired)…',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = '扫描失败：$e');
    }
  }

  /// 单入口自动连接：通道自动选（BLE 优先；只有 SPP 通道时走 SPP），
  /// 档案由设备推导（名称匹配优先，否则 NMEA UART 服务、否则通用 NMEA），
  /// 不再要求用户先选档案卡。已连接的设备点按不重复连接。
  Future<void> _connectAdaptable(Map<String, dynamic> dev) async {
    final addr = (dev['address'] ?? '').toString();
    if (addr.isEmpty) return;
    if (_connectedAddress == addr) return;
    final channels = (dev['channels'] as List? ?? <dynamic>[])
        .map((e) => e.toString())
        .toList();
    final hasBle = channels.isEmpty || channels.contains('ble');
    if (!mounted) return;
    setState(() => _kind = gpsProfileKindForDevice(dev));
    if (hasBle) {
      await _connectScanned(dev);
    } else {
      await _connectSppDevice(dev);
    }
  }

  Future<void> _connectScanned(Map<String, dynamic> dev) async {
    final addr = (dev['address'] ?? '').toString();
    if (addr.isEmpty) return;
    _connectedName = (dev['name'] ?? '').toString();
    if (!await _ensureBtPermissions()) return;
    await _disconnectCurrentQuietlyIfOther(addr);
    final uuids = _effectiveUuids;
    if (uuids == null) {
      if (_profile.binaryProtocol) {
        // 二进制协议设备（如 DEXIAN D1）：服务 UUID 已验证，但数据特征
        // 未确认、包格式待实测抓包。本版只连通 GATT，不订阅任何特征、
        // 不解析定位；绝不落入通用 NUS 的 NMEA 订阅当 NMEA 设备用。
        // 订阅按钮已随高级区删除，通知字节即使到达
        // 也不进解析器（见 bleNotification 分支的丢弃守卫）。
        try {
          setState(() {
            _notice = '正在连接“${dev['name']}”…本版只连接，不出定位。';
            _connectingAddress = addr;
            _pendingSubscribe = null;
          });
          await Native.setBleAutoReconnect(true);
          await Native.connectBle(addr);
        } catch (e) {
          setState(() {
            _connectingAddress = null;
            _pendingSubscribe = null;
            _notice = '连接失败：$e';
          });
        }
        return;
      }
      // 无公开 UUID 的类别：不猜 UUID。先连 GATT，连接成功后由
      // connected 事件自动尝试通用 NUS 订阅（设备实际广播为准）；
      // 若设备不广播 NUS 且支持经典蓝牙，请改用 SPP 连接。
      try {
        setState(() {
          _notice = '正在连接“${dev['name']}”…';
          _connectingAddress = addr;
          _pendingSubscribe = (
            address: addr,
            service: nordicUartServiceUuid,
            tx: nordicUartTxUuid,
          );
        });
        await Native.setBleAutoReconnect(true);
        await Native.connectBle(addr);
      } catch (e) {
        setState(() {
          _connectingAddress = null;
          _pendingSubscribe = null;
          _notice = '连接失败：$e';
        });
      }
      return;
    }
    try {
      setState(() {
        _notice = '正在连接“${dev['name']}”…';
        _connectingAddress = addr;
        _pendingSubscribe = (
          address: addr,
          service: uuids.service,
          tx: uuids.tx,
        );
      });
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(addr);
      // GATT 服务发现完成前订阅可能报 not_found，connected 事件里会再试一次。
      await _doSubscribe(addr, uuids.service, uuids.tx);
    } catch (e) {
      setState(() {
        _connectingAddress = null;
        _notice = '连接失败：$e';
      });
    }
  }

  /// SPP 连接：确认走 sppConnected 事件；10 秒未确认提示超时，
  /// 不静默挂起。SPP 不占 GATT 名额，可与 BLE 传感器共存。
  Future<void> _connectSppDevice(Map<String, dynamic> dev) async {
    final addr = (dev['address'] ?? '').toString();
    if (addr.isEmpty) return;
    _connectedName = (dev['name'] ?? '').toString();
    if (!await _ensureBtPermissions()) return;
    await _disconnectCurrentQuietlyIfOther(addr);
    try {
      setState(() {
        _connectingAddress = addr;
        _notice = '正在通过 SPP 连接“${dev['name']}”…';
      });
      await Native.connectSpp(addr);
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        if (_connectingAddress == addr && _connectedAddress != addr) {
          setState(() {
            _connectingAddress = null;
            _notice =
                'SPP 连接超时：请确认设备已开机、在系统蓝牙里已配对，'
                '且未被其它 App 占用。';
          });
        }
      });
    } catch (e) {
      setState(() {
        _connectingAddress = null;
        _notice = 'SPP 连接失败：$e';
      });
    }
  }

  Future<void> _doSubscribe(String addr, String service, String tx) async {
    try {
      final r = await Native.subscribeBleCharacteristic(addr, service, tx);
      final ok = (r['ok'] as bool?) == true;
      if (!mounted) return;
      setState(() {
        _subscribeError = ok ? null : (r['error']?.toString() ?? 'unknown');
        _notice = ok
            ? '已订阅 NMEA 特征，行程改用外接 GPS；5 秒无新定位自动回落手机 GPS。'
            : '订阅失败：${_subscribeError}（请核对设备实际广播的服务 / 特征 UUID）。';
      });
      if (ok) _pendingSubscribe = null;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = '订阅失败：$e';
      });
    }
  }

  /// 扫描行的提示：先看广播事实，再看名称字样；名称含厂商字样
  /// 不等于身份断言，绝不把名称当作协议证据。
  String _guessHint(Map<String, dynamic> dev) {
    final s = S.of(context);
    final uuids = ((dev['serviceUuids'] as List?) ?? [])
        .map((e) => e.toString().toLowerCase())
        .toList();
    if (uuids.contains(dexianServiceUuid.toLowerCase())) {
      return s.t(
        'DEXIAN D1 服务：二进制，暂不解析定位。',
        'DEXIAN D1 service: binary, no fix yet.',
      );
    }
    if (uuids.any((u) => u.contains('6e400001'))) {
      return s.t('Nordic UART，可试 NMEA。', 'Nordic UART. NMEA may work.');
    }
    if (uuids.contains(raceboxNmeaServiceUuid.toLowerCase())) {
      return s.t('NMEA UART，可试订阅。', 'NMEA UART. Try subscribe.');
    }
    if (uuids.any((u) => u.contains('00001101'))) {
      return s.t('含 00001101（可能是 SPP）。', 'Has 00001101 (maybe SPP).');
    }
    final name = (dev['name'] ?? '').toString();
    for (final p in externalGpsProfiles) {
      if (_profileNameMatches(p, name)) {
        if (p.binaryProtocol) {
          return s.t(
            '名称匹配：${p.name}（二进制，暂不解析）。',
            'Name match: ${p.name} (binary, no fix).',
          );
        }
        return s.t(
          '名称匹配：${p.name}（仅名称）。',
          'Name match: ${p.name} (name only).',
        );
      }
    }
    final channels = (dev['channels'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (channels.contains('spp')) {
      return s.t('经典蓝牙，可试 SPP。', 'Classic Bluetooth. Try SPP.');
    }
    return s.t('未见 NMEA 服务。', 'No NMEA service advertised.');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fix = _feed.latest;
    // 扫描卡片状态行（三种状态共用一处文案来源）：
    // 空态 / 扫描中 / 有结果（无可适配时也在这里说清，不另起文案）。
    final adaptable = _scanned.where(gpsDeviceIsAdaptable).toList();
    final scanStatusLine = _adaptScanning
        ? s.t(
            '正在扫描附近的 GPS 模块…',
            'Scanning nearby GPS modules…',
          )
        : _scanned.isEmpty
        ? s.t('尚未扫描，点「扫描适配设备」。', 'Not scanned. Tap Scan devices.')
        : adaptable.isEmpty
        ? s.t(
            '已扫 ${_scanned.length} 台，没有可适配 GPS。',
            'Scanned ${_scanned.length}. No compatible GPS.',
          )
        : s.t(
            '已扫 ${_scanned.length} 台，${adaptable.length} 台可连，点行即连。',
            'Scanned ${_scanned.length}. ${adaptable.length} ready. Tap a row.',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 动态匹配卡片：与相机页同一套共用组件（device_scan_card.dart），
        // 只换外衣——扫描 / 去重 / 连接逻辑一律不动（见 _toggleAdaptScan /
        // _connectAdaptable）。v1.7.0：连上自研硬件后本卡切换为硬件管理
        // 界面（电量 / 固件 / 实时状态 / 圈速导入 / 关机），第三方 GPS
        // 仍显示扫描卡。
        if (_showHardwareCard)
          const DeviceHardwareCard()
        else
          DeviceScanCard(
            title: s.t('外接 GPS', 'External GPS'),
            description: s.t(
              '点扫描后点设备即连。SPP 须先在系统蓝牙配对。',
              'Scan, then tap a device. Pair SPP in system Bluetooth first.',
            ),
            icon: Icons.satellite_alt,
            scanning: _adaptScanning,
            scanLabel: s.t('扫描适配设备', 'Scan devices'),
            stopLabel: s.t('停止扫描', 'Stop'),
            onScanToggle: _toggleAdaptScan,
            statusLine: scanStatusLine,
            scanButtonIcon: Icons.bluetooth_searching,
            footnote: s.t(
              '找不到？确认设备已开机并处于可发现状态。',
              'Not found? Make sure the device is on and discoverable.',
            ),
            permNotice: _permNotice,
            onOpenSettings: () => Native.openAppSettings(),
          ),
        // 已连接状态行（v1.5.4）：绿点 + 已连设备名 + 断开连接按钮，
        // 只在已连外接 GPS 时出现；样式沿用 OBD 区状态行（绿点 +
        // 状态 + 断开按钮）。高级区删除后，这是页内唯一的 GPS
        // 显式断开入口。
        if (_connectedAddress != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.t(
                      '已连接：${_connectedName ?? _connectedAddress}',
                      'Connected: ${_connectedName ?? _connectedAddress}',
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _disconnectGps,
                  child: Text(s.t('断开连接', 'Disconnect')),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          s.t('可适配设备', 'Compatible'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_scanned.isEmpty)
          Text(
            s.t(
              '还没有设备。点扫描；打开设备与蓝牙。SPP 须先配对。',
              'No devices yet. Tap Scan. Device and Bluetooth on. Pair SPP first.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        for (final dev in adaptable)
          Builder(
            builder: (context) {
              final channels = (dev['channels'] as List? ?? <dynamic>[])
                  .map((e) => e.toString())
                  .toList();
              final hasBle = channels.isEmpty || channels.contains('ble');
              final hasSpp = channels.contains('spp');
              final channelLabel = hasBle && hasSpp
                  ? 'BLE+SPP'
                  : hasSpp
                  ? 'SPP'
                  : 'BLE';
              final addr = (dev['address'] ?? '').toString();
              final isConnecting = _connectingAddress == addr;
              final isConnected = _connectedAddress == addr;
              final rssi = dev['rssi'];
              final signal = rssi != null
                  ? '信号 $rssi'
                  : (dev['bonded'] == true ? '已配对' : '');
              return DeviceScanRow(
                title: (dev['name'] ?? '').toString().isEmpty
                    ? '未命名设备'
                    : (dev['name'] ?? '').toString(),
                badgeLabel: channelLabel,
                detail: _guessHint(dev),
                meta: isConnected && fix != null
                    ? '${btGpsFixStatusLabel(fix)} · '
                          '卫星 ${fix.satellites ?? '—'} · '
                          '更新率 ${fix.hz?.toStringAsFixed(0) ?? '—'} Hz'
                          '${signal.isEmpty ? '' : ' · $signal'}'
                    : (signal.isEmpty ? addr : '$signal · $addr'),
                actionLabel: dev['bonded'] == true
                    ? s.t('连接', 'Connect')
                    : s.t('去配对', 'Pair first'),
                actionIsOutline: dev['bonded'] != true,
                connectingLabel: s.t('连接中', 'Connecting'),
                isConnecting: isConnecting,
                isConnected: isConnected,
                onTap: () => _connectAdaptable(dev),
              );
            },
          ),
        const SizedBox(height: 8),
        // v1.5.4：高级 / 手动添加区已删（档案卡、自定义 UUID、分别
        // 扫描、全部扫描结果均不在此页；扫描只走上方「扫描适配设备」）。
        const SizedBox(height: 8),
        // （高级区其余内容——自定义 UUID、分别扫描、全部扫描结果——
        // 随高级区一并删除，见上方注释。）
        const SizedBox(height: 8),
        // （高级区全部扫描结果列表随高级区一并删除。）
        const SizedBox(height: 8),
        const SizedBox(height: 8),
        // _notice 与卡片状态行同文时只在卡片里出现一次（扫描中提示），
        // 避免同一文案在页面上出现两处；其余提示（连接 / 断开 / 停止等）
        // 仍在这里显示。权限提示已收进卡片，不再另起一块。
        if (_notice != null && _notice != scanStatusLine)
          Text(
            _notice!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        const SizedBox(height: 8),
        // v1.5.4：「外接 GPS：未连接」状态卡已删（连接状态只看首页
        // 状态药丸与上方主列表，不在此页另起一块；「保存到本机清单」
        // 按钮随卡一并删除）。
        const SizedBox(height: 8),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// OBD（ELM327）模块区，供 DeviceCenterPage 嵌入。
///
/// 连接入口只认系统蓝牙已配对设备：点“载入已配对设备”，点行即连
/// 任意一台（ELM327 须先在系统蓝牙里配对，见下方说明）。连接后
/// 显示实时车速 / 转速 / 油门 / 水温；未连接时读数一律为“—”，
/// 绝不拿旧值冒充实时值。录制时每秒存一条实测采样进本趟行程，
/// 隧道推算用 OBD 车速；断开即清 OBD 速度、回落衰减模型。
/// 蓝牙权限复用外接 GPS 区的分步流程（requestStep('extras')）。
class ObdSection extends StatefulWidget {
  /// 默认用全局 [obdService]；测试可注入带 fake 平台的 service。
  final ObdService? service;

  const ObdSection({super.key, this.service});

  @override
  State<ObdSection> createState() => _ObdSectionState();
}

class _ObdSectionState extends State<ObdSection> {
  ObdService get _service => widget.service ?? obdService;

  List<Map<String, dynamic>> _paired = [];
  bool _loadingPaired = false;
  String? _notice;
  String? _permNotice;
  String? _connectingAddress;
  // 本区已连 OBD 的地址（ObdStatus 只带设备名，不带地址；行内
  // “已连接”判定以地址为准，设备名为空时也不误判）。
  String? _connectedAddress;

  @override
  void initState() {
    super.initState();
    _loadPaired();
  }

  Future<bool> _ensureBtPermissions() async {
    try {
      final snap = await Native.checkPermissions();
      var btOk = snap['bluetooth'] == true;
      if (!btOk) {
        final r = await Native.requestStep('extras');
        btOk = r['bluetooth'] == true;
      }
      if (!mounted) return false;
      setState(() => _permNotice = btOk ? null : 'OBD 需要蓝牙权限，请在系统设置里打开后重试。');
      return btOk;
    } catch (e) {
      if (mounted) setState(() => _permNotice = '权限检查失败：$e');
      return false;
    }
  }

  Future<void> _loadPaired() async {
    if (!await _ensureBtPermissions()) return;
    if (!mounted) return;
    setState(() => _loadingPaired = true);
    try {
      final list = await _service.platform.listPaired();
      if (!mounted) return;
      setState(() {
        _paired = list;
        _loadingPaired = false;
        _notice = list.isEmpty
            ? '未找到已配对经典蓝牙设备：请先在系统蓝牙设置里与 ELM327 配对。'
            : '已载入 ${list.length} 台已配对经典蓝牙设备，点行即连。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPaired = false;
        _notice = '读取已配对设备失败：$e';
      });
    }
  }

  Future<void> _connect(Map<String, dynamic> dev) async {
    final addr = (dev['address'] ?? '').toString();
    if (addr.isEmpty) return;
    final name = (dev['name'] ?? '').toString();
    if (!await _ensureBtPermissions()) return;
    if (!mounted) return;
    setState(() {
      _connectingAddress = addr;
      _notice = '正在连接“${name.isEmpty ? addr : name}”…';
    });
    final ok = await _service.connect(addr, deviceName: name);
    if (!mounted) return;
    setState(() {
      _connectingAddress = null;
      if (ok) _connectedAddress = addr;
      _notice = ok
          ? 'OBD 已连接，行程记录时每秒存一条实测采样。'
          : (_service.status.error.isEmpty
                ? '连接失败：请确认 ELM327 已开机且未被其它 App 占用。'
                : _service.status.error);
    });
  }

  Future<void> _disconnect() async {
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connectedAddress = null;
      _notice = '已断开 OBD，隧道推算回落衰减模型。';
    });
  }

  Widget _reading(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ObdStatus>(
      valueListenable: _service.statusNotifier,
      builder: (context, st, _) {
        final connected = st.connected;
        final connecting = st.connecting;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_permNotice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _permNotice!,
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Native.openAppSettings(),
                      child: const Text('去设置'),
                    ),
                  ],
                ),
              ),
            // 状态行：绿点 + 状态 + 断开按钮。
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected
                        ? Colors.green
                        : (connecting ? Colors.orange : Colors.white38),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    obdStatusLabel(st),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (connected)
                  TextButton(onPressed: _disconnect, child: const Text('断开')),
              ],
            ),
            const SizedBox(height: 4),
            if (!connected && !connecting)
              const Text(
                '未连接 OBD。先在系统蓝牙里配对 ELM327，再来这里连接；'
                '未连接时不显示任何读数、不存采样。',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              )
            else if (connected) ...[
              const Text(
                '实时读数（ELM327 实测，1 秒采样进本趟行程）：',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _reading(
                    '车速',
                    st.speedKmh == null
                        ? '—'
                        : '${st.speedKmh!.toStringAsFixed(0)} km/h',
                  ),
                  _reading(
                    '转速',
                    st.rpm == null ? '—' : '${st.rpm!.toStringAsFixed(0)} rpm',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _reading(
                    '油门',
                    st.throttlePct == null
                        ? '—'
                        : '${st.throttlePct!.toStringAsFixed(0)} %',
                  ),
                  _reading(
                    '水温',
                    st.coolantC == null
                        ? '—'
                        : '${st.coolantC!.toStringAsFixed(0)} ℃',
                  ),
                ],
              ),
            ],
            if (st.error.isNotEmpty && !connected)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  st.error,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _loadingPaired ? null : _loadPaired,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: Text(_loadingPaired ? '载入中…' : '载入已配对设备'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_paired.isEmpty)
              const Text(
                '尚未载入已配对设备：点上方按钮载入；ELM327 须开机、'
                '且先在系统蓝牙里配对。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            for (final dev in _paired)
              Builder(
                builder: (context) {
                  final addr = (dev['address'] ?? '').toString();
                  final name = (dev['name'] ?? '').toString();
                  final isConnecting = _connectingAddress == addr;
                  final isThisConnected =
                      connected && _connectedAddress == addr;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isThisConnected
                            ? Colors.green.withValues(alpha: 0.6)
                            : Colors.white12,
                      ),
                    ),
                    // ListTile 的墨水效果要画在 Material 祖先上：
                    // 直接放带底色的 Container 里会触发 debug 断言。
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        title: Text(
                          name.isEmpty ? '未命名设备' : name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          addr,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isThisConnected
                            ? const Text(
                                '已连接',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : isConnecting
                            ? const Text(
                                '连接中…',
                                style: TextStyle(color: Colors.orangeAccent),
                              )
                            : const Text(
                                '点按连接',
                                style: TextStyle(color: Colors.white70),
                              ),
                        onTap: (isThisConnected || isConnecting)
                            ? null
                            : () => _connect(dev),
                      ),
                    ),
                  );
                },
              ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _notice!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

class DeviceCenterPage extends StatefulWidget {
  const DeviceCenterPage({
    super.key,
    this.onBack,
    this.onSavedDeviceConnected,
    this.embedded = false,
    this.store,
  });

  /// 返回上一页的回调；不传则用 Navigator.maybePop。
  /// [embedded] 为 true 时（底部导航页）不显示返回钮。
  final VoidCallback? onBack;

  /// 作为底部导航页嵌入主壳：无独立 AppBar/返回钮，页内标题与
  /// 记录页同口径，底部为药丸留白；切换动画走主壳 AnimatedSwitcher。
  final bool embedded;

  /// 已保存设备通过现有 BLE 通道连上时通知调用方（仅通知，不回传轨迹）。
  final void Function(SavedDevice device)? onSavedDeviceConnected;

  /// 行程库（视频同步入口需要读写行程）。不传时本页自行创建一个。
  final Store? store;

  @override
  State<DeviceCenterPage> createState() => _DeviceCenterPageState();
}

class _DeviceCenterPageState extends State<DeviceCenterPage> {
  List<SavedDevice> _saved = [];
  final Map<String, DeviceLinkStatus> _statusByAddress = {};
  String? _notice;

  /// 从“我的设备”点重连时记下待订阅的服务 / 特征；连接与
  /// 服务发现事件到达后自动订阅，避免重连后仍无定位。
  ({String address, String service, String tx})? _resubscribe;

  StreamSubscription<Map<String, dynamic>>? _dataSub;

  final BleDiyGpsFeed _gpsFeed = BleDiyGpsFeed();

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _dataSub = Native.bleDataStream.listen((e) {
      final type = (e['type'] ?? '').toString();
      final addr = (e['address'] ?? '').toString();
      if (type == 'connected' && addr.isNotEmpty) {
        connectedExternalGpsAddress.value = addr;
        SavedDevice? newlySaved;
        setState(() {
          _statusByAddress[addr] = DeviceLinkStatus.connected;
          // v1.7.9：连接成功即加入「我的设备」，按地址去重后持久化，
          // 下次进页面可直接点重连。无 name 时用地址尾段兜底显示。
          if (_saved.every((d) => d.address != addr)) {
            final rawName = (e['name'] ?? '').toString();
            final tail = addr.length >= 5
                ? addr.substring(addr.length - 5)
                : addr;
            newlySaved = SavedDevice(
              name: rawName.isNotEmpty ? rawName : 'GPS $tail',
              serviceUuid: '',
              characteristicUuid: '',
              type: '外接GPS',
              address: addr,
            );
            _saved = [..._saved, newlySaved!];
          }
        });
        if (newlySaved != null) {
          _persist(silent: true);
          widget.onSavedDeviceConnected?.call(newlySaved!);
        } else {
          final hit = _saved.where((d) => d.address == addr);
          if (hit.isNotEmpty) widget.onSavedDeviceConnected?.call(hit.first);
        }
        unawaited(_tryResubscribe(addr));
      } else if (type == 'servicesDiscovered') {
        // GATT 服务发现完成：连接瞬间订阅常报 not_found，这里再试一次。
        unawaited(_tryResubscribe((e['address'] ?? '').toString()));
      } else if (type == 'disconnected') {
        connectedExternalGpsAddress.value = null;
        setState(() {
          for (final k in _statusByAddress.keys) {
            _statusByAddress[k] = DeviceLinkStatus.disconnected;
          }
          _gpsFeed.reset();
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = await DeviceCenterStore.load();
    if (!mounted) return;
    setState(() => _saved = list);
    // 开机自动重连等连接可能发生在本页创建之前：进页按共享地址
    // 恢复一次“已连接”标记，不必再等下一次连接事件。
    final live = connectedExternalGpsAddress.value;
    if (live != null && live.isNotEmpty) {
      setState(() => _statusByAddress[live] = DeviceLinkStatus.connected);
    }
  }

  /// 把刚配对成功的设备并入“我的设备”（按地址去重）。
  /// 同一台设备重连时用新拿到的名称 / UUID 补全旧记录的空字段，
  /// 绝不新增重复行。
  void _rememberDevice(SavedDevice device) {
    final addr = device.address;
    if (addr == null || addr.isEmpty) return;
    final index = _saved.indexWhere((d) => d.address == addr);
    setState(() {
      if (index < 0) {
        _saved = [..._saved, device];
      } else {
        final old = _saved[index];
        final next = [..._saved];
        next[index] = SavedDevice(
          name: old.name.isNotEmpty ? old.name : device.name,
          serviceUuid: device.serviceUuid.isNotEmpty
              ? device.serviceUuid
              : old.serviceUuid,
          characteristicUuid: device.characteristicUuid.isNotEmpty
              ? device.characteristicUuid
              : old.characteristicUuid,
          type: old.type.isNotEmpty ? old.type : device.type,
          address: addr,
        );
        _saved = next;
      }
    });
    unawaited(_persist(silent: true));
  }

  Future<void> _persist({bool silent = false}) async {
    final ok = await DeviceCenterStore.save(_saved);
    if (!mounted) return;
    if (silent && ok) return;
    setState(() => _notice = ok ? '已保存到本机。' : '保存失败：本机文件写入失败。');
  }

  Future<void> _connectSaved(SavedDevice device) async {
    final addr = device.address;
    if (addr == null || addr.isEmpty) {
      setState(() => _notice = '“${device.name}”未保存蓝牙地址，无法重连，请重新扫描连接。');
      return;
    }
    final service = device.serviceUuid.isNotEmpty
        ? device.serviceUuid
        : nordicUartServiceUuid;
    final tx = device.characteristicUuid.isNotEmpty
        ? device.characteristicUuid
        : nordicUartTxUuid;
    try {
      setState(() => _statusByAddress[addr] = DeviceLinkStatus.connecting);
      // 记下待订阅的 UUID：connected / servicesDiscovered 事件到达时
      // 自动订阅 NMEA 特征，重连后直接出定位，不再要求去扫描页手工订阅。
      _resubscribe = (address: addr, service: service, tx: tx);
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(addr);
      setState(() => _notice = '正在连接“${device.name}”…');
    } catch (e) {
      setState(() {
        _statusByAddress[addr] = DeviceLinkStatus.disconnected;
        _notice = '连接失败：$e';
      });
    }
  }

  /// 连上（或服务发现完成）后按待订阅项自动订阅 NMEA 特征。
  Future<void> _tryResubscribe(String addr) async {
    final pending = _resubscribe;
    if (pending == null || pending.address != addr) return;
    try {
      final r = await Native.subscribeBleCharacteristic(
        pending.address,
        pending.service,
        pending.tx,
      );
      if ((r['ok'] as bool?) == true) {
        _resubscribe = null;
        if (!mounted) return;
        setState(() => _notice = '已连接并订阅定位数据。');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final s = S.of(context);
    final bottomPad = widget.embedded
        ? (kPillNavHeight + 12 + MediaQuery.of(context).padding.bottom + 16)
        : 16.0;
    final list = ListView(
      padding: widget.embedded
          ? EdgeInsets.fromLTRB(16, appBarTopInset(context) + 8, 16, bottomPad)
          : withAppBarTopInset(
              context,
              EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
            ),
      children: [
        if (_notice != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _notice!,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        // 三张卡：我的设备（已连/已保存）+ 视频与赛道记录 + 可添加设备。
        _sectionTitle(s.t('我的设备', 'My devices')),
        _myDevicesCard(),
        const SizedBox(height: 18),
        _sectionTitle(s.t('视频与赛道记录', 'Video & trips')),
        _videoSyncCard(),
        const SizedBox(height: 18),
        _sectionTitle(s.t('可添加设备', 'Add devices')),
        _addDevicesCard(),
        const SizedBox(height: 12),
        Text(
          s.t(
            '外接 GPS 断线或 5 秒无新定位时，自动回落手机 GPS。',
            'If external GPS drops or is silent for 5s, phone GPS takes over.',
          ),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
    if (widget.embedded) {
      // Material 底色：与记录页同为 #121212，避免 ColoredBox 挡住 ListTile 水波纹。
      return Material(color: const Color(0xFF121212), child: list);
    }
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          s.t('设备中心', 'Devices'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: list,
    );
  }

  /// “我的设备”卡：已保存的 BLE 设备（传感器 / GPS）。
  Widget _myDevicesCard() {
    final s = S.of(context);
    if (_saved.isEmpty) {
      return _panel(
        child: Row(
          children: [
            _iconTile(Icons.bluetooth_disabled),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.t('尚未连接设备', 'No devices yet'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.t(
                      '连接传感器或外接 GPS 后在这里管理',
                      'Connected sensors and GPS show up here',
                    ),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return ValueListenableBuilder<ExternalGpsStatus>(
      valueListenable: externalGpsStatus,
      builder: (context, st, _) => _panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < _saved.length; i++) ...[
              if (i > 0) _dividerLine(left: 62),
              _savedDeviceTile(_saved[i], st),
            ],
          ],
        ),
      ),
    );
  }

  /// 视频与赛道记录：选视频 → 选行程 → 进视频编辑页（画面对齐 / HUD / 圈）。
  /// 相机 / GPS 是否已连接不影响入口：素材可在相册里，连上相机只决定
  /// 后续录像来源；这里不伪造“已从相机下载”。
  Widget _videoSyncCard() {
    final s = S.of(context);
    return _panel(
      padding: EdgeInsets.zero,
      child: _deviceEntry(
        glyph: DeviceGlyphKind.video,
        title: s.t('视频同步', 'Video sync'),
        subtitle: s.t(
          '读取相册视频，关联赛道记录并添加 HUD',
          'Link gallery clips to a trip and add HUD',
        ),
        trailing: s.t('进入', 'Open'),
        onTap: _openVideoSync,
      ),
    );
  }

  Future<void> _openVideoSync() async {
    final store = widget.store ?? Store();
    if (widget.store == null) await store.init();
    if (!mounted) return;
    await openVideoSyncFlow(context, store: store);
  }

  /// 可添加设备：相机 / 外接 GPS / OBD 三行，点行进入各自的连接流程。
  Widget _addDevicesCard() {
    final s = S.of(context);
    return _panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _deviceEntry(
            glyph: DeviceGlyphKind.actionCam,
            title: s.t('运动相机', 'Action cam'),
            subtitle: 'GoPro · Insta360 · DJI',
            trailing: s.t('连接', 'Connect'),
            onTap: _openCameraSheet,
          ),
          _dividerLine(),
          _deviceEntry(
            glyph: DeviceGlyphKind.gpsModule,
            title: s.t('外接 GPS 模块', 'External GPS'),
            subtitle: s.t(
              '断线自动回落手机 GPS',
              'Falls back to phone GPS on disconnect',
            ),
            trailing: s.t('扫描', 'Scan'),
            onTap: _openGpsSheet,
          ),
          _dividerLine(),
          _deviceEntry(
            glyph: DeviceGlyphKind.obd,
            title: s.t('OBD（ELM327）', 'OBD (ELM327)'),
            subtitle: s.t('车速 / 转速 / 油门 / 水温', 'Speed / rpm / throttle'),
            trailing: s.t('敬请期待', 'Soon'),
            enabled: false,
            onTap: _showObdComingSoon,
          ),
        ],
      ),
    );
  }

  Widget _deviceEntry({
    required DeviceGlyphKind glyph,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              // 无外框：直接画设备线性图标（参考图样式）。
              SizedBox(
                width: 38,
                height: 38,
                child: Center(
                  child: DeviceGlyph(
                    kind: glyph,
                    size: 28,
                    color: enabled ? Colors.white : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled ? Colors.white : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(
                  color: enabled ? Colors.white54 : Colors.white30,
                  fontSize: 13,
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white30,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 扫描底部面板：打开即扫描，关闭即停止；结果直接可连。
  /// 运动相机按 GoPro BLE 直连（紧凑版相机页内嵌），外接 GPS 打开配对面板。
  Future<void> _openCameraSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, controller) {
          final s = S.of(ctx);
          return Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t(
                          '扫描设备',
                          'Scan devices',
                        ),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(s.t('取消', 'Cancel')),
                    ),
                  ],
                ),
              ),
              const Expanded(child: CameraConnectPage(compact: true)),
            ],
          );
        },
      ),
    );
  }

  /// 外接 GPS 面板：保留完整的 ExternalGpsSection（扫描 / 配对 /
  /// 硬件管理都在里面），只是从页面内嵌改成点“扫描”拉起。
  Future<void> _openGpsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, controller) {
          final s = S.of(ctx);
          return Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('扫描设备', 'Scan devices'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(s.t('取消', 'Cancel')),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: ExternalGpsSection(onPaired: _rememberDevice),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return DriveTrackCard(padding: padding, child: child);
  }

  /// 设备图标：统一单色线性图标，不跟主题色着色，**不加外框**（v1.7.x）。
  Widget _iconTile(IconData icon, {double size = 40, bool dimmed = false}) {
    final tint = dimmed ? Colors.white24 : Colors.white70;
    return SizedBox(
      width: size,
      height: size,
      child: Icon(icon, size: size * 0.62, color: tint),
    );
  }

  /// 行间分隔线：不划到头，左边与文字起始对齐（附图样式）。
  Widget _dividerLine({double left = 64}) => Padding(
    padding: EdgeInsets.only(left: left, right: 16),
    child: Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
  );

  /// OBD「敬请期待」彩蛋弹窗：App 通用 AlertDialog 样式（见
  /// gps_source_badge.dart 的来源详情弹窗），点「知道了」关闭。
  Future<void> _showObdComingSoon() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final s = S.of(ctx);
        return AlertDialog(
          title: Text(s.t('OBD · 敬请期待', 'OBD · Coming soon')),
          content: Text(
            s.t(
              '行车电脑数据（车速 / 转速 / 油门 / 水温）正在路上，等硬件就绪就和大家见面，敬请期待。',
              'Speed, rpm, throttle, and coolant are on the way.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.t('知道了', 'OK')),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  /// 我的设备行摘要：连接状态之外，已连接时补上定位是否在出数，
  /// 避免“只看到名字，其它信息都没有”。
  String _savedDeviceDetail(
    SavedDevice device,
    DeviceLinkStatus status,
    ExternalGpsStatus st,
  ) {
    final parts = <String>[device.type, status.label];
    if (status == DeviceLinkStatus.connected && st.connected) {
      final ageMs = st.lastFixAtMs > 0
          ? DateTime.now().millisecondsSinceEpoch - st.lastFixAtMs
          : -1;
      if (st.binaryOnly) {
        parts.add('不出定位');
      } else if (ageMs >= 0 && ageMs <= 5000) {
        final hz = st.sampleRateHz > 0
            ? ' ${st.sampleRateHz.toStringAsFixed(0)}Hz'
            : '';
        parts.add('定位中$hz');
      } else {
        parts.add('等待定位');
      }
    }
    final addr = device.address;
    if (addr != null && addr.isNotEmpty) parts.add(addr);
    return parts.join(' · ');
  }

  Widget _savedDeviceTile(SavedDevice device, ExternalGpsStatus st) {
    final s = S.of(context);
    final addr = device.address;
    final status = addr == null
        ? DeviceLinkStatus.disconnected
        : (_statusByAddress[addr] ?? DeviceLinkStatus.disconnected);
    final connected = status == DeviceLinkStatus.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          _iconTile(Icons.sensors, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: connected
                            ? const Color(0xFF34C759)
                            : Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _savedDeviceDetail(device, status, st),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: addr == null ? null : () => _connectSaved(device),
            child: Text(
              connected
                  ? s.t('重连', 'Reconnect')
                  : s.t('连接', 'Connect'),
            ),
          ),
          IconButton(
            tooltip: s.t('删除', 'Delete'),
            onPressed: () async {
              setState(
                () => _saved = _saved.where((d) => d != device).toList(),
              );
              await _persist();
            },
            icon: const Icon(Icons.close, size: 16, color: Colors.white30),
          ),
        ],
      ),
    );
  }
}

/// 底部面板顶部的拖拽提示条（两张面板共用）。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
