import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'blediy_gps.dart';
import 'bt_gps_receiver.dart';
import 'camera_guide.dart';
import 'gopro_protocol.dart';
import 'native.dart';
import 'satellite_settings_page.dart';

/// 外接设备中心：运动相机 + 其他传感器 + RaceChrono BleDIY GPS。
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

/// 通用 BLE 添加表单的类型下拉选项。
const List<String> customSensorTypes = [
  '功率计',
  '踏频/速度传感器',
  '心率带',
  '外部 GPS（RaceChrono BleDIY）',
  '其他',
];

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
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
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
          .map((e) =>
              SavedDevice.fromJson(Map<String, dynamic>.from(e)))
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
          jsonEncode(devices.map((d) => d.toJson()).toList()));
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// 外接 GPS 模块的设备类别（v1.0.2，第 6 项；后扩至 RaceChrono
/// 支持清单，每设备只出现一次，绝不平行建第二张表）。
///
/// 支持程度必须如实标注，绝不冒充：只有“通用 NMEA 解析”本身是
/// 已实现的（blediy_gps.dart 的 GGA / RMC / VTG / GSA）；厂商私有协议
/// 只要没公开文档、没实测设备，一律标“协议未公开 / 未实测验证，
/// 仅通用 NMEA 兼容”，且 [serviceUuid] / [txUuid] 保持 null，
/// 绝不凭猜测填一个 UUID。无 UUID 不再等于“无法连接”：无 UUID 的
/// 类别走名称匹配 + 通用 NUS 订阅尝试 + SPP 连接尝试（见本区连接逻辑）。
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
/// 按整词匹配，见 bt_gps_receiver.dart）。
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
    this.adapterId,
  });

  final ExternalGpsKind kind;
  final String name;
  final String note;
  final String? serviceUuid;
  final String? txUuid;
  final List<String> nameHints;
  final String? adapterId;

  /// 是否有可确认的 NMEA 订阅路径（不是“厂商已完整支持”）。
  bool get hasNmeaPath => serviceUuid != null && txUuid != null;

  /// 页面上的支持程度徽标文案。
  String get supportBadge => hasNmeaPath
      ? '通用 NMEA 兼容（GGA / RMC / VTG / GSA 解析已实现）'
      : '协议未公开 / 未实测验证，仅通用 NMEA 兼容';
}

/// 四类外接 GPS 档案。调研结论（2026-11-03 公开搜索，见回执）：
/// - BleDIY：已有 blediy_gps.dart 解析；NUS UUID 是 Nordic 通用
///   默认值，非 RaceChrono 官方专属值（blediy_gps.dart 已注明）。
/// - Dragy（DRG70 / DRG70-C / Pro DRG71）：公开资料只确认蓝牙
///   连接、10Hz（Pro 25Hz）与 u-blox 芯片，未找到官方 BLE 服务 /
///   特征 UUID 与数据格式文档；RaceChrono 支持 Dragy 是其自有
///   集成，不是公开协议。本 App 不解析 Dragy 私有数据流。
/// - DEXIAN Timer（D1）：Dexian Timer 应用介绍称兼容 D1 25Hz GPS
///   且支持 RaceChrono DIY 协议设备，RaceChrono 更新日志亦称已
///   支持 Dexian D1；但未找到 D1 本身公开的 BLE 服务 / 特征 UUID
///   与数据格式。RaceChrono BLE DIY 服务 UUID（00001ff8-…）是
///   DIY 设备的公开规范，不是 D1 的实测值，绝不能硬说成 D1 的值，
///   因此本档案不填它。2026-11-05 用户亲自确认 D1 兼容 25Hz
///   （BLE 服务 UUID 仍未知，连接与定位仍待真机验证）。
/// - 通用 NMEA BLE UART：默认 Nordic UART，可改填设备实际广播值。
const List<ExternalGpsProfile> externalGpsProfiles = [
  ExternalGpsProfile(
    kind: ExternalGpsKind.blediy,
    name: 'BleDIY（RaceChrono DIY 兼容）',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    nameHints: ['blediy'],
    note: 'NMEA 文本经 BLE UART 推送时可订阅解析；服务 / 特征为 '
        'Nordic UART 通用默认值，非 RaceChrono 官方专属值，实际设备以广播为准。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.garminGlo,
    name: 'Garmin GLO',
    nameHints: ['garmin', 'glo'],
    note: '标准 NMEA 输出为前提、待真机验证：经典蓝牙 SPP 为主连接路径；'
        '请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dualXgps,
    name: 'Dual XGPS 150 / 160',
    nameHints: ['dual', 'xgps'],
    note: '标准 NMEA 输出为前提、待真机验证：经典蓝牙 SPP 为主连接路径；'
        '请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.qstarz,
    name: 'Qstarz BL-818GT / BL-1000GT / LT-8000GT',
    nameHints: ['qstarz', 'bl-818', 'bl-1000', 'lt-8000'],
    note: '标准 NMEA 输出为前提、待真机验证：经典蓝牙 SPP 为主连接路径'
        '（LT-8000GT 另可试 BLE 名称匹配）；请先在系统蓝牙里配对。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.columbus,
    name: 'Columbus P-9 Race',
    nameHints: ['columbus', 'p-9'],
    note: '标准 NMEA 输出为前提、待真机验证：经典蓝牙 SPP 为主连接路径；'
        '请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.vboxSport,
    name: 'VBOX Sport',
    nameHints: ['vbox'],
    note: '标准 NMEA 输出为前提、待真机验证：经典蓝牙 SPP 为主连接路径；'
        '请先在系统蓝牙里配对，再用下方“已配对 SPP 设备”连接。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.racebox,
    name: 'RaceBox Mini / Mini S / Micro',
    serviceUuid: raceboxNmeaServiceUuid,
    txUuid: raceboxNmeaTxUuid,
    nameHints: ['racebox'],
    adapterId: 'racebox_ubx',
    note: '公开 BLE 协议文档值、待真机验证：固件 3.3+ 提供标准 NMEA UART 服务'
        '（本卡 UUID 即文档值），可按此订阅；主 UART 走 U-Blox UBX 二进制私有协议，'
        '本 App 暂不实现（适配器口子已留），且不要同时订阅两种协议（官方文档警告会高丢包）。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dexian,
    name: 'DEXIAN D1（第一测试目标）',
    nameHints: ['dexian', 'd1'],
    note: '25Hz（用户确认）；BLE 服务 UUID 仍未知、连接与定位仍待真机验证：'
        '公开渠道无 D1 服务 UUID；RaceChrono v10.3.0 加入 D1 支持的同版把 BLE '
        '优先级设为高，推测 D1 走 BLE。本 App 按标准 NMEA over Bluetooth 实现，'
        '不硬编任何未证实的协议细节：点「扫描适配设备」按名称匹配走 BLE'
        '（无 UUID 时自动尝试通用 NUS 订阅），不行再试 SPP；连接与定位均待真机验证。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.digspice,
    name: 'DigSpice IV',
    nameHints: ['digspice'],
    note: 'RaceChrono v10.3.0 同版新增支持，但公开渠道无详细规格，待真机验证：'
        '按标准 NMEA over Bluetooth 实现（BLE 名称匹配 + SPP 兜底），不硬编协议细节。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dragy,
    name: 'Dragy Pro / DRG70 / DRG70-C / Lite',
    nameHints: ['dragy', 'drg'],
    adapterId: 'dragy_proprietary',
    note: '协议未公开 / 未实测验证：官方只说明蓝牙连接与官方 App，'
        '未公开 BLE 服务 / 特征 UUID 与数据格式，RaceChrono 支持系其自有集成；'
        '本 App 不解析 Dragy 私有数据流。通用兜底：SPP 连接尝试 + BLE NUS 订阅尝试，'
        '若设备输出标准 NMEA 即可工作，否则暂不支持。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.genericBt,
    name: '通用蓝牙 GPS（SPP）',
    note: '不区分厂商的经典蓝牙 SPP 路径：请先在系统蓝牙里配对，'
        '再用下方“已配对 SPP 设备”或“经典蓝牙搜索”连接；只解析标准 NMEA 文本。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.genericNmea,
    name: '通用 NMEA BLE UART',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    note: '默认 Nordic UART；下方可改填设备实际广播的服务 / 特征 UUID。'
        '只解析 NMEA 文本（GGA / RMC / VTG / GSA），非 NMEA 二进制流一律丢弃计数。',
  ),
];

/// 单入口“可适配设备”过滤（纯函数，可单测）：名录匹配 12 张档案卡
/// 的名称提示，或广播 NMEA UART / SPP 服务（NUS 6e400001、
/// RaceBox NMEA、SPP 00001101）。名称与服务证据都没有的设备
///（如耳机）不进主列表，只在高级区全部结果里出现；过滤不丢数据。
bool gpsDeviceIsAdaptable(Map<String, dynamic> dev) {
  final name = (dev['name'] ?? '').toString();
  for (final p in externalGpsProfiles) {
    if (btGpsNameMatches(name, p.nameHints)) return true;
  }
  final uuids = ((dev['serviceUuids'] as List?) ?? [])
      .map((e) => e.toString().toLowerCase())
      .toList();
  if (uuids.any((u) => u.contains('6e400001'))) return true;
  if (uuids.any((u) => u.contains('00001101'))) return true;
  return false;
}

/// 单入口自动连接的档案推导（纯函数，可单测）：名称匹配优先；
/// RaceBox NMEA 服务广播 → RaceBox 档案；其余一律走通用 NMEA
///（NUS 默认值），由连接逻辑按广播事实订阅。
ExternalGpsKind gpsProfileKindForDevice(Map<String, dynamic> dev) {
  final name = (dev['name'] ?? '').toString();
  for (final p in externalGpsProfiles) {
    if (btGpsNameMatches(name, p.nameHints)) return p.kind;
  }
  final uuids = ((dev['serviceUuids'] as List?) ?? [])
      .map((e) => e.toString().toLowerCase())
      .toList();
  if (uuids.contains(raceboxNmeaServiceUuid.toLowerCase())) {
    return ExternalGpsKind.racebox;
  }
  return ExternalGpsKind.genericNmea;
}

/// 外接 GPS 模块区（v1.0.2，第 6 项），供 DeviceCenterPage 嵌入。
/// 本区是 App 内唯一的蓝牙 GPS 连接入口，不另起平行入口。
///
/// 单入口主流程（像系统蓝牙连接页）：顶部「扫描适配设备」一键扫完
/// 全渠道（NUS 过滤扫描、无过滤 BLE 扫描、经典蓝牙发现、已配对 SPP），
/// 结果按地址去重合并；主列表只显示过滤后的可适配设备（档案名录匹配
/// 或广播 NMEA UART / SPP 服务），点行即自动连接（BLE 优先、只有 SPP
/// 通道时走 SPP，档案由设备推导、不再要求先选档案卡）。行内显示
/// 连接中 → 已连接 → 定位状态 / 卫星数 / 更新率。原有高级 / 手动能力
///（档案卡浏览、自定义 UUID、分别扫描、SPP 说明、全部扫描结果）收进
/// 默认收起的「高级 / 手动添加」区，主流程看不到它们。
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
///   一设备一行；主列表自动选通道，高级区全部结果里仍保留
///   “连接 / SPP 连接”两个手动按钮。
/// - 无过滤扫描与经典发现走 btGpsDeviceStream，不进页级 bleDeviceStream，
///   页级“附近扫描结果”不会因此多出重复设备。
///
/// 原生层限制（必须如实显示，不假装全量扫描）：
/// - NUS 扫描带服务过滤：不广播 NUS 的设备扫不到，须用无过滤扫描
///   （名称匹配）或经典蓝牙 / 已配对 SPP 路径；主按钮已一次全扫。
/// - 原生单 GATT：一次只能连一台 BLE 设备，连新设备会断开旧的；
///   SPP 不占 GATT 名额，可与 BLE 传感器共存。
class ExternalGpsSection extends StatefulWidget {
  const ExternalGpsSection({super.key});

  @override
  State<ExternalGpsSection> createState() => _ExternalGpsSectionState();
}

class _ExternalGpsSectionState extends State<ExternalGpsSection> {
  ExternalGpsKind _kind = ExternalGpsKind.blediy;
  final _customServiceCtrl =
      TextEditingController(text: nordicUartServiceUuid);
  final _customTxCtrl = TextEditingController(text: nordicUartTxUuid);
  final List<Map<String, dynamic>> _scanned = [];
  bool _scanning = false;
  bool _bleGpsScanning = false;
  bool _classicScanning = false;
  // 单入口主按钮的合并扫描状态；停任一 BLE 扫描即清零（stopBleScan
  // 同时停过滤与无过滤扫描），经典发现结束不单独清零（BLE 部分仍在扫）。
  bool _adaptScanning = false;
  bool _advancedExpanded = false;
  String? _notice;
  String? _permNotice;
  String? _connectedAddress;
  // 本区唯一的连接通道：'ble' | 'spp'；null = 未连接。
  String? _connectedChannel;
  // 本区正在发起连接的地址：connected / sppConnected 事件只认它，
  // 页级传感器连接不再误翻本区状态。
  String? _connectingAddress;
  bool _subscribed = false;
  String? _subscribeError;
  // 已连接后待订阅的 (address, service, tx)；GATT 服务发现是异步的，
  // 连接事件到达时若立即订阅报 characteristic_not_found，会在
  // connected 事件里再试一次（见 _dataSub）。
  ({String address, String service, String tx})? _pendingSubscribe;

  final BleDiyGpsFeed _feed = BleDiyGpsFeed();
  StreamSubscription<Map<String, dynamic>>? _devSub;
  StreamSubscription<Map<String, dynamic>>? _dataSub;
  StreamSubscription<Map<String, dynamic>>? _btGpsSub;

  /// 当前类别是否可用 SPP（SPP 为主或兜底路径）。
  bool get _sppCapable {
    switch (_kind) {
      case ExternalGpsKind.garminGlo:
      case ExternalGpsKind.dualXgps:
      case ExternalGpsKind.qstarz:
      case ExternalGpsKind.columbus:
      case ExternalGpsKind.vboxSport:
      case ExternalGpsKind.dexian:
      case ExternalGpsKind.digspice:
      case ExternalGpsKind.dragy:
      case ExternalGpsKind.genericBt:
        return true;
      case ExternalGpsKind.blediy:
      case ExternalGpsKind.racebox:
      case ExternalGpsKind.genericNmea:
        return false;
    }
  }

  /// 全渠道扫描列表按地址合并：一设备一行，通道取并集；已配对标记
  /// 透传保留（主列表用它显示“已配对”，未配对的经典发现不冒充）。
  void _mergeScanned(Map<String, dynamic> e, String channel,
      {bool bonded = false}) {
    final addr = (e['address'] ?? '').toString();
    if (addr.isEmpty) return;
    final merged = <String, dynamic>{...e};
    final channels = <String>{channel};
    var wasBonded = bonded;
    final oldIndex =
        _scanned.indexWhere((d) => d['address'] == addr);
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
        setState(() {
          _classicScanning = false;
          _notice = '经典蓝牙搜索完成。';
        });
        return;
      }
      if (type == 'bleScanFailed') {
        setState(() => _notice = '蓝牙 GPS 扫描失败（原生错误码 ${e['errorCode']}）。');
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
        final pending = _pendingSubscribe;
        if (pending != null && pending.address == addr) {
          await _doSubscribe(pending.address, pending.service, pending.tx);
        }
      } else if (type == 'disconnected') {
        if (_connectedChannel != 'ble') return;
        setState(() {
          _connectedAddress = null;
          _connectedChannel = null;
          _subscribed = false;
          _pendingSubscribe = null;
          _connectingAddress = null;
          _notice = '外接 GPS 已断开：解析器已重置，行程定位由 main.dart 回落逻辑切回手机 GPS。';
        });
        _feed.reset();
      } else if (type == 'sppConnected') {
        final addr = (e['address'] ?? '').toString();
        if (_connectingAddress != null && _connectingAddress != addr) return;
        setState(() {
          _connectedAddress = addr.isEmpty ? null : addr;
          _connectedChannel = addr.isEmpty ? null : 'spp';
          _connectingAddress = null;
          _subscribed = false;
          _notice = 'SPP 已连接：NMEA 文本经串口直达解析器，有效定位自动注入 Recorder。';
        });
      } else if (type == 'sppDisconnected') {
        if (_connectedChannel != 'spp') return;
        setState(() {
          _connectedAddress = null;
          _connectedChannel = null;
          _subscribed = false;
          _pendingSubscribe = null;
          _connectingAddress = null;
          _notice = 'SPP 已断开（${e['reason'] ?? ''}）：解析器已重置，行程定位回落手机 GPS。';
        });
        _feed.reset();
      } else if (type == 'sppNmea') {
        final line = (e['line'] ?? '').toString();
        if (line.isEmpty) return;
        _feed.feedLine(line);
        if (!mounted) return;
        setState(() {});
      } else if (type == 'bleNotification') {
        // 只喂 NMEA 特征的通知进 GPS 解析器：页级传感器通知
        //（功率计 / 踏频 / 心率）不再误喂，避免二进制数据污染解析。
        final cu = (e['characteristicUuid'] ?? '').toString().toLowerCase();
        final tx = _effectiveUuids?.tx.toLowerCase() ?? '';
        final isNmea =
            cu.contains('0003') || (tx.isNotEmpty && cu.contains(tx));
        if (!isNmea) return;
        final bytes = (e['bytes'] as List?)
                ?.map((v) => (v as num).toInt())
                .toList() ??
            <int>[];
        if (bytes.isEmpty) return;
        _feed.feedBytes(bytes);
        if (!mounted) return;
        setState(() => _subscribed = true);
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
      setState(() => _permNotice = (btOk && locOk)
          ? null
          : '蓝牙 GPS 需要蓝牙与定位权限：当前未获授权，扫描与连接不可用。'
              '请在系统设置里为本 App 打开蓝牙与定位权限后重试。');
      return btOk && locOk;
    } catch (e) {
      if (mounted) setState(() => _permNotice = '权限检查失败：$e');
      return false;
    }
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
        _subscribed = false;
        _pendingSubscribe = null;
        _connectingAddress = null;
      });
    }
  }

  Future<void> _toggleScan() async {
    if (!await _ensureBtPermissions()) return;
    try {
      if (_scanning) {
        await Native.stopBleScan();
        setState(() {
          _scanning = false;
          // stopBleScan 同时停过滤与无过滤扫描，合并扫描随之结束。
          _adaptScanning = false;
          _notice = '已停止扫描。';
        });
      } else {
        // 只扫广播 NUS 的设备；不广播 NUS 的设备不会出现在这里，
        // 请改用下方“扫描蓝牙 GPS”（无过滤 + 名称匹配）。
        await Native.scanBleWithServices([nordicUartServiceUuid]);
        setState(() {
          _scanning = true;
          _notice = '正在扫描广播 Nordic UART 服务的设备…注意：原生扫描带服务过滤，'
              '不广播 NUS 的设备不会出现在这里。';
        });
      }
    } catch (e) {
      setState(() => _notice = '扫描失败：$e');
    }
  }

  /// 无过滤 BLE 扫描：按设备名发现不广播 NUS 的 GPS 接收器。
  /// 结果走 btGpsDeviceStream，只进本区列表，不污染页级列表。
  Future<void> _toggleBleGpsScan() async {
    if (!await _ensureBtPermissions()) return;
    try {
      if (_bleGpsScanning) {
        await Native.stopBleScan();
        setState(() {
          _bleGpsScanning = false;
          // stopBleScan 同时停过滤与无过滤扫描，合并扫描随之结束。
          _adaptScanning = false;
          _notice = '已停止蓝牙 GPS 扫描。';
        });
      } else {
        final ok = await Native.scanBleUnfiltered();
        setState(() {
          _bleGpsScanning = ok;
          _notice = ok
              ? '正在无过滤扫描蓝牙设备（按名称匹配 GPS 接收器；不广播 NUS 的设备也能出现）…'
              : '无过滤扫描启动失败：请确认蓝牙已打开且权限已授予。';
        });
      }
    } catch (e) {
      setState(() => _notice = '扫描失败：$e');
    }
  }

  /// 已配对经典蓝牙设备（SPP 连接候选），按地址合并进同一列表。
  Future<void> _loadBondedSpp() async {
    if (!await _ensureBtPermissions()) return;
    try {
      final list = await Native.listBondedSppDevices();
      if (!mounted) return;
      setState(() {
        for (final d in list) {
          _mergeScanned(d, 'spp', bonded: true);
        }
        _notice = list.isEmpty
            ? '未找到已配对经典蓝牙设备：请先在系统蓝牙设置里与 GPS 接收器配对。'
            : '已载入 ${list.length} 台已配对经典蓝牙设备（SPP 连接）。';
      });
    } catch (e) {
      setState(() => _notice = '读取已配对设备失败：$e');
    }
  }

  /// 经典蓝牙发现：找未配对的 SPP 候选设备，结果同样进同一列表。
  Future<void> _toggleClassicDiscovery() async {
    if (!await _ensureBtPermissions()) return;
    try {
      if (_classicScanning) {
        await Native.stopClassicDiscovery();
        setState(() {
          _classicScanning = false;
          _notice = '已停止经典蓝牙搜索。';
        });
      } else {
        final ok = await Native.startClassicDiscovery();
        setState(() {
          _classicScanning = ok;
          _notice = ok
              ? '正在搜索经典蓝牙设备（SPP 候选）…'
              : '经典蓝牙搜索启动失败：请确认蓝牙已打开且权限已授予。';
        });
      }
    } catch (e) {
      setState(() => _notice = '搜索失败：$e');
    }
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
        _scanning = false;
        _bleGpsScanning = false;
        _classicScanning = false;
        _notice = '已停止扫描。';
      });
      return;
    }
    if (!await _ensureBtPermissions()) return;
    try {
      await Native.scanBleWithServices([nordicUartServiceUuid]);
      final bleOk = await Native.scanBleUnfiltered();
      final classicOk = await Native.startClassicDiscovery();
      final bonded = await Native.listBondedSppDevices();
      if (!mounted) return;
      setState(() {
        _adaptScanning = true;
        _scanning = true;
        _bleGpsScanning = bleOk;
        _classicScanning = classicOk;
        for (final d in bonded) {
          _mergeScanned(d, 'spp', bonded: true);
        }
        _notice = '正在扫描周围可适配的 GPS 设备（BLE + 经典蓝牙 + 已配对）…';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = '扫描失败：$e');
    }
  }

  /// 单入口自动连接：通道自动选（BLE 优先；只有 SPP 通道时走 SPP），
  /// 档案由设备推导（名称匹配优先，否则 RaceBox 服务、否则通用 NMEA），
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
    if (!await _ensureBtPermissions()) return;
    await _disconnectCurrentQuietlyIfOther(addr);
    final uuids = _effectiveUuids;
    if (uuids == null) {
      // 无公开 UUID 的类别：不猜 UUID。先连 GATT，连接成功后由
      // connected 事件自动尝试通用 NUS 订阅（设备实际广播为准）；
      // 若设备不广播 NUS 且支持经典蓝牙，请改用 SPP 连接。
      try {
        setState(() {
          _notice = '正在连接“${dev['name']}”…连接成功后自动尝试通用 NUS 订阅。';
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
        _notice = '正在连接“${dev['name']}”…连接成功后自动订阅 NMEA 特征。';
        _connectingAddress = addr;
        _pendingSubscribe =
            (address: addr, service: uuids.service, tx: uuids.tx);
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
    if (!await _ensureBtPermissions()) return;
    await _disconnectCurrentQuietlyIfOther(addr);
    try {
      setState(() {
        _connectingAddress = addr;
        _notice = '正在通过 SPP 连接“${dev['name']}”…（经典蓝牙串口直连）';
      });
      await Native.connectSpp(addr);
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        if (_connectingAddress == addr && _connectedAddress != addr) {
          setState(() {
            _connectingAddress = null;
            _notice = 'SPP 连接超时：请确认设备已开机、在系统蓝牙里已配对，'
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

  /// 对已连接设备直接尝试订阅 NMEA 特征（不重新连接）。
  /// SPP 通道无需订阅（串口直读）；无 UUID 的类别尝试通用 NUS 订阅。
  Future<void> _subscribeConnected() async {
    final addr = _connectedAddress;
    if (addr == null) {
      setState(() => _notice = '无已连接设备，无法订阅。');
      return;
    }
    if (_connectedChannel == 'spp') {
      setState(() => _notice = 'SPP 通道无需订阅特征：NMEA 文本经串口直达解析器，'
          '有效定位已自动注入 Recorder。');
      return;
    }
    final uuids = _effectiveUuids;
    if (uuids == null) {
      setState(() => _notice = '当前类别无可确认的 UUID，尝试通用 NUS 订阅…');
      await _doSubscribe(addr, nordicUartServiceUuid, nordicUartTxUuid);
      return;
    }
    await _doSubscribe(addr, uuids.service, uuids.tx);
  }

  Future<void> _doSubscribe(String addr, String service, String tx) async {
    try {
      final r =
          await Native.subscribeBleCharacteristic(addr, service, tx);
      final ok = (r['ok'] as bool?) == true;
      if (!mounted) return;
      setState(() {
        _subscribed = ok;
        _subscribeError = ok ? null : (r['error']?.toString() ?? 'unknown');
        _notice = ok
            ? '已订阅 NMEA 特征：有效定位将经 main.dart 全局监听注入 Recorder，'
                '行程自动改用外接 GPS；5 秒无新定位自动回落手机 GPS。'
            : '订阅失败：${_subscribeError}（常见原因：GATT 服务发现未完成，'
                '或该设备实际广播的不是该服务 / 特征——请以扫描到的 serviceUuids 为准改填）。';
      });
      if (ok) _pendingSubscribe = null;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subscribed = false;
        _notice = '订阅失败：$e';
      });
    }
  }

  Future<void> _disconnect() async {
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
      _subscribed = false;
      _pendingSubscribe = null;
      _connectingAddress = null;
      _notice = '已断开外接 GPS：解析器已重置，行程定位回落手机 GPS。';
    });
  }

  Future<void> _saveConnectedAsSaved() async {
    final addr = _connectedAddress;
    if (_connectedChannel == 'spp') {
      // SPP 不走 GATT、无特征配置可存，模型（SavedDevice 要求 UUID）
      // 也不适用：重连请走已配对列表，不另造一套 SPP 保存。
      setState(() => _notice = 'SPP 设备不存入 BLE 清单：重连请走“已配对 SPP 设备”'
          '列表（SPP 不走 GATT，无特征配置可存）。');
      return;
    }
    final uuids = _effectiveUuids;
    if (addr == null || uuids == null) {
      setState(() => _notice = '当前类别无可确认的 UUID，无法保存为可重连的特征配置。');
      return;
    }
    final saved = await DeviceCenterStore.load();
    saved.add(SavedDevice(
      name: '外接 GPS（${_profile.name}）',
      serviceUuid: uuids.service,
      characteristicUuid: uuids.tx,
      type: '外部 GPS（${_profile.name}）',
      address: addr,
    ));
    final ok = await DeviceCenterStore.save(saved);
    if (!mounted) return;
    setState(() => _notice = ok
        ? '已保存到本机“已连 / 已保存设备”清单，下次可用重连（重连后仍需订阅 NMEA 特征）。'
        : '保存失败：本机文件写入失败。');
  }

  /// 扫描行的提示：先看广播事实，再看名称字样；名称含厂商字样
  /// 不等于身份断言，绝不把名称当作协议证据。
  String _guessHint(Map<String, dynamic> dev) {
    final uuids = ((dev['serviceUuids'] as List?) ?? [])
        .map((e) => e.toString().toLowerCase())
        .toList();
    if (uuids.any((u) => u.contains('6e400001'))) {
      return '广播含 Nordic UART 服务，可尝试订阅 NMEA。';
    }
    if (uuids.contains(raceboxNmeaServiceUuid.toLowerCase())) {
      return '广播含 RaceBox NMEA UART 服务（公开文档值，固件 3.3+），可尝试订阅。';
    }
    if (uuids.any((u) => u.contains('00001101'))) {
      return '广播含 00001101 服务（SPP / NMEA UART 可能值），以实际输出为准。';
    }
    final name = (dev['name'] ?? '').toString();
    for (final p in externalGpsProfiles) {
      if (btGpsNameMatches(name, p.nameHints)) {
        return '名称匹配：${p.name}（仅名称提示，协议以实际输出为准）。';
      }
    }
    final channels =
        (dev['channels'] as List? ?? []).map((e) => e.toString()).toList();
    if (channels.contains('spp')) {
      return '经典蓝牙设备，可尝试 SPP 连接。';
    }
    return '未见 NMEA UART 服务广播。';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fix = _feed.latest;
    final stale = _feed.shouldFallbackToPhoneGps();
    final uuids = _effectiveUuids;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '点下方按钮一次扫完周围可适配的 GPS 设备（BLE + 经典蓝牙 + 已配对），'
          '点列表里的设备即自动连接。',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _toggleAdaptScan,
            icon: Icon(_adaptScanning ? Icons.stop : Icons.bluetooth_searching,
                size: 18),
            label: Text(_adaptScanning ? '停止扫描' : '扫描适配设备'),
          ),
        ),
        const SizedBox(height: 12),
        const Text('可适配设备',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (_scanned.isEmpty)
          const Text('尚未扫描：点上方「扫描适配设备」开始。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        if (_scanned.isNotEmpty && !_scanned.any(gpsDeviceIsAdaptable))
          Text('已扫描 ${_scanned.length} 台设备，其中没有可适配的 GPS 设备'
              '（全部结果见下方「高级 / 手动添加」）。',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        for (final dev in _scanned.where(gpsDeviceIsAdaptable))
          Builder(builder: (context) {
            final channels = (dev['channels'] as List? ?? <dynamic>[])
                .map((e) => e.toString())
                .toList();
            final hasBle = channels.isEmpty || channels.contains('ble');
            final hasSpp = channels.contains('spp');
            final channelLabel =
                hasBle && hasSpp ? 'BLE+SPP' : hasSpp ? 'SPP' : 'BLE';
            final addr = (dev['address'] ?? '').toString();
            final isConnecting = _connectingAddress == addr;
            final isConnected = _connectedAddress == addr;
            final rssi = dev['rssi'];
            final signal = rssi != null
                ? '信号 $rssi'
                : (dev['bonded'] == true ? '已配对' : '');
            return ListTile(
              title: Text((dev['name'] ?? '').toString(),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                isConnected && fix != null
                    ? '$channelLabel${signal.isEmpty ? '' : ' · $signal'} · '
                        '${btGpsFixStatusLabel(fix)} · '
                        '卫星 ${fix.satellites ?? '—'} · '
                        '更新率 ${fix.hz?.toStringAsFixed(0) ?? '—'} Hz'
                    : '$channelLabel${signal.isEmpty ? '' : ' · $signal'} · $addr',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: isConnecting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2)),
                        SizedBox(width: 6),
                        Text('连接中',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : isConnected
                      ? const Text('已连接',
                          style: TextStyle(color: Colors.greenAccent))
                      : const Text('点按连接',
                          style: TextStyle(color: Colors.white70)),
              onTap: () => _connectAdaptable(dev),
            );
          }),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('高级 / 手动添加',
              style: TextStyle(color: Colors.white)),
          subtitle: const Text('档案卡浏览、自定义 UUID、分别扫描、SPP 说明、全部扫描结果',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          initiallyExpanded: _advancedExpanded,
          onExpansionChanged: (v) => setState(() => _advancedExpanded = v),
          children: [
            const Text(
              '本区是唯一的蓝牙 GPS 连接入口：BLE（NUS / RaceBox NMEA UART / 名称匹配）'
              '与经典蓝牙 SPP 双通道，扫描列表全渠道合并、一设备一行，连接状态单点管理。'
              '定位源切换复用现有链路：BLE 订阅或 SPP 直读的 NMEA 经 main.dart 全局 '
              'bleData 监听注入 Recorder（externalGpsActive = true，落点走 '
              'Recorder.onExternalFix），外部源 5 秒无新定位或断线时自动回落手机 GPS。'
              '原生单 GATT：一次只能连一台 BLE 设备，SPP 不占 GATT 名额。',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
        for (final p in externalGpsProfiles)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: p.kind == _kind ? accent : Colors.white12,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _kind = p.kind),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        p.kind == _kind
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(p.supportBadge,
                        style: TextStyle(
                            color: p.hasNmeaPath
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    if (p.kind == _kind) ...[
                      const SizedBox(height: 4),
                      Text(p.note,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (_kind == ExternalGpsKind.genericNmea) ...[
          TextField(
            controller: _customServiceCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: '服务 UUID（以设备实际广播为准）',
              labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customTxCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: '特征 UUID（NMEA 推送特征）',
              labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text('UUID 格式不对时自动回落 Nordic UART 默认值，并在下方提示里说明。',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
        ],
        if (_sppCapable) ...[
          const Text(
            'SPP 通道：请先在系统蓝牙设置里与设备配对，再用下方“已配对 SPP”连接；'
            'SPP 不占 GATT 名额、不需订阅特征，NMEA 文本直达解析器。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _toggleScan,
              icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching,
                  size: 18),
              label: Text(_scanning ? '停止扫描' : '扫描 NMEA UART 设备'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  _connectedAddress == null ? null : _subscribeConnected,
              icon: const Icon(Icons.sensors, size: 18),
              label: const Text('订阅 NMEA'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _toggleBleGpsScan,
              icon: Icon(
                  _bleGpsScanning ? Icons.stop : Icons.bluetooth_searching,
                  size: 18),
              label: Text(_bleGpsScanning ? '停止扫描' : '扫描蓝牙 GPS'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _loadBondedSpp,
              icon: const Icon(Icons.bluetooth_connected, size: 18),
              label: const Text('已配对 SPP'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _toggleClassicDiscovery,
              icon: Icon(_classicScanning ? Icons.stop : Icons.bluetooth,
                  size: 18),
              label: Text(_classicScanning ? '停止搜索' : '经典蓝牙搜索'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_scanned.isEmpty)
          const Text(
              '暂无扫描结果：点主流程「扫描适配设备」，或用上方分别扫描。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        for (final dev in _scanned)
          Builder(builder: (context) {
            final channels = (dev['channels'] as List? ?? <dynamic>[])
                .map((e) => e.toString())
                .toList();
            final hasBle = channels.isEmpty || channels.contains('ble');
            final hasSpp = channels.contains('spp');
            final channelLabel =
                hasBle && hasSpp ? 'BLE+SPP' : hasSpp ? 'SPP' : 'BLE';
            return ListTile(
              title: Text((dev['name'] ?? '').toString(),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                  '${dev['address']} · ${dev['type']} · RSSI ${dev['rssi'] ?? '—'} · '
                  '$channelLabel · ${_guessHint(dev)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasBle)
                    TextButton(
                      onPressed: () => _connectScanned(dev),
                      child: const Text('连接'),
                    ),
                  if (hasSpp)
                    TextButton(
                      onPressed: () => _connectSppDevice(dev),
                      child: const Text('SPP 连接'),
                    ),
                ],
              ),
            );
          }),
          ],
        ),
        const SizedBox(height: 8),
        if (_permNotice != null)
          Row(children: [
            Expanded(
              child: Text(_permNotice!,
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontSize: 12)),
            ),
            TextButton(
              onPressed: () => Native.openAppSettings(),
              child: const Text('去系统设置'),
            ),
          ]),
        if (_notice != null)
          Text(_notice!,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _connectedAddress == null
                        ? '外接 GPS：未连接'
                        : '外接 GPS：已连接 $_connectedAddress'
                            '${_connectedChannel == 'spp' ? ' · SPP' : ' · BLE'}'
                            '${_connectedChannel == 'spp' ? '' : _subscribed ? ' · 已订阅 NMEA' : ' · 未订阅'}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_connectedAddress != null)
                  TextButton(
                      onPressed: _disconnect, child: const Text('断开')),
              ]),
              const SizedBox(height: 4),
              Text(
                fix == null
                    ? '暂无定位：尚未收到有效 NMEA 定位。'
                    : '最新定位：${btGpsFixStatusLabel(fix)}，'
                        'lat=${fix.lat.toStringAsFixed(5)}，'
                        'lon=${fix.lon.toStringAsFixed(5)}，'
                        '速度=${fix.speedMps == null ? '—' : '${(fix.speedMps! * 3.6).toStringAsFixed(1)} km/h'}，'
                        '卫星=${fix.satellites ?? '—'}'
                        '${fix.usedSatellites != null ? ' / 解算 ${fix.usedSatellites}' : ''}，'
                        'HDOP=${fix.hdop ?? '—'}，'
                        '更新率=${fix.hz?.toStringAsFixed(0) ?? '—'} Hz'
                        '${stale ? '（已超 5 秒无新定位，应已回落手机 GPS）' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '解析统计：已接受 ${ _feed.acceptedCount} 条，有效定位外语句已丢弃 '
                '${_feed.droppedCount} 条（校验和不符 / 无效定位 / 非 A 状态一律不造假点）。',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(
                  onPressed: _connectedAddress == null
                      ? null
                      : _saveConnectedAsSaved,
                  child: const Text('保存到本机清单'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _connectedChannel == 'spp'
                        ? 'SPP 设备不存入 BLE 清单，重连请走已配对列表。'
                        : uuids == null
                            ? '当前类别无可确认的 UUID，无法保存特征配置。'
                            : '保存后重连仍需再订阅 NMEA 特征。',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class DeviceCenterPage extends StatefulWidget {
  const DeviceCenterPage({
    super.key,
    this.onBack,
    this.onSavedDeviceConnected,
  });

  /// 返回上一页的回调；不传则用 Navigator.maybePop。
  final VoidCallback? onBack;

  /// 已保存设备通过现有 BLE 通道连上时通知调用方（仅通知，不回传轨迹）。
  final void Function(SavedDevice device)? onSavedDeviceConnected;

  @override
  State<DeviceCenterPage> createState() => _DeviceCenterPageState();
}

class _DeviceCenterPageState extends State<DeviceCenterPage> {
  List<SavedDevice> _saved = [];
  final List<Map<String, dynamic>> _scanned = [];
  final Map<String, DeviceLinkStatus> _statusByAddress = {};
  final Map<String, int> _batteryByAddress = {};
  bool _scanning = false;
  String? _notice;

  DeviceLinkStatus _goproStatus = DeviceLinkStatus.disconnected;
  int? _goproBattery; // 仅当原生层未来回传电量事件时才有值，否则始终为 null。
  bool _goproScanning = false;

  StreamSubscription<Map<String, dynamic>>? _devSub;
  StreamSubscription<Map<String, dynamic>>? _dataSub;

  final _nameCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _charCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _formType = customSensorTypes.last;

  final BleDiyGpsFeed _gpsFeed = BleDiyGpsFeed();
  String? _gpsDemoResult;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _devSub = Native.bleDeviceStream.listen((e) {
      final addr = (e['address'] ?? '').toString();
      if (addr.isEmpty) return;
      setState(() {
        _scanned.removeWhere((d) => d['address'] == addr);
        _scanned.insert(0, e);
      });
    }, onError: (_) {});
    _dataSub = Native.bleDataStream.listen((e) {
      final type = (e['type'] ?? '').toString();
      final addr = (e['address'] ?? '').toString();
      setState(() {
        if (type == 'connected' && addr.isNotEmpty) {
          _statusByAddress[addr] = DeviceLinkStatus.connected;
          final hit = _saved.where((d) => d.address == addr);
          if (hit.isNotEmpty) widget.onSavedDeviceConnected?.call(hit.first);
        } else if (type == 'disconnected') {
          for (final k in _statusByAddress.keys) {
            _statusByAddress[k] = DeviceLinkStatus.disconnected;
          }
          _gpsFeed.reset();
        } else if (type == 'bleNotification') {
          // GoPro 响应特征 GP-0073：原生层通用通知原样转发，Dart 侧按
          // 特征 UUID 分发；收到响应才算 GoPro 链路通，之前只算“已下发查询”。
          final cu = (e['characteristicUuid'] ?? '').toString().toLowerCase();
          if (cu.contains('0073')) {
            _goproStatus = DeviceLinkStatus.connected;
            _notice = 'GoPro 已响应 Get Version 查询（GP-0073）：Open GoPro '
                '链路通。快门等控制命令仍须在相机实际响应后核对，不先宣称可用。';
          }
        } else if (type == 'battery' && addr.isNotEmpty) {
          // 原生层目前的 battery 事件不带 address（见 MainActivity），
          // 这里只在带 address 时记录；不带 address 时不乱贴到某台设备。
          final v = e['value'];
          if (v is num) _batteryByAddress[addr] = v.toInt();
        }
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _devSub?.cancel();
    _dataSub?.cancel();
    _nameCtrl.dispose();
    _serviceCtrl.dispose();
    _charCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = await DeviceCenterStore.load();
    if (!mounted) return;
    setState(() => _saved = list);
  }

  Future<void> _persist() async {
    final ok = await DeviceCenterStore.save(_saved);
    if (!mounted) return;
    setState(() => _notice = ok ? '已保存到本机。' : '保存失败：本机文件写入失败，清单未保存。');
  }

  Future<void> _toggleScan() async {
    try {
      if (_scanning) {
        await Native.stopBleScan();
        setState(() {
          _scanning = false;
          _notice = '已停止扫描。';
        });
      } else {
        await Native.startBleScan();
        setState(() {
          _scanning = true;
          _notice = '正在扫描…注意：现有原生扫描只过滤功率/踏频/心率三类服务，'
              'GoPro 与 UART 类设备可能不会出现在这里。';
        });
      }
    } catch (e) {
      setState(() => _notice = '扫描失败：$e');
    }
  }

  Future<void> _connectSaved(SavedDevice device) async {
    final addr = device.address;
    if (addr == null || addr.isEmpty) {
      setState(() => _notice = '“${device.name}”未保存蓝牙地址，无法重连：请在表单里补填地址后保存。');
      return;
    }
    try {
      setState(() => _statusByAddress[addr] = DeviceLinkStatus.connecting);
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(addr);
      setState(() => _notice = '正在连接“${device.name}”…结果以蓝牙事件为准；'
          'UART 类设备重连后仍需在外接 GPS 区订阅 NMEA 特征。');
    } catch (e) {
      setState(() {
        _statusByAddress[addr] = DeviceLinkStatus.disconnected;
        _notice = '连接失败：$e';
      });
    }
  }

  /// GoPro 扫描：原生层 scanBleWithServices（v0.1.3 起已有）带 FEA6
  /// 过滤扫描；扫描结果走页面通用 bleDeviceStream，进下方扫描列表，
  /// 在该行点“GoPro 连接”才真正连接并下发查询。
  Future<void> _scanGoPro() async {
    try {
      if (_goproScanning) {
        await Native.stopBleScan();
        setState(() {
          _goproScanning = false;
          _notice = '已停止 GoPro 扫描。';
        });
      } else {
        await Native.scanBleWithServices([goproAdvertisedServiceUuid]);
        setState(() {
          _goproScanning = true;
          _notice = '正在扫描广播 FEA6 的 GoPro 设备…结果出现在下方扫描列表，'
              '在 GoPro 设备行点“GoPro 连接”下发 Get Version 查询。';
        });
      }
    } catch (e) {
      setState(() => _notice = 'GoPro 扫描失败：$e');
    }
  }

  /// GoPro 连接（v1.1.0 打通）：先 connectBle，再订阅响应特征
  /// GP-0073（原生层只自动订阅功率/踏频/心率/电量，不自动订阅 GoPro
  /// 响应，不订阅就收不到回复），最后用原生层已有的通用写特征方法
  /// 下发 Get Version 只读查询（[0x01, 0x51]），绝不用快门命令作探测。
  /// 旧版直接裸调 MethodChannel 且不带地址、不先连接，必然失败；
  /// 本版走 Native.writeBleCharacteristic（带地址），失败原因如实显示。
  Future<void> _connectGoProDevice(String address) async {
    setState(() {
      _goproStatus = DeviceLinkStatus.connecting;
      _notice = '正在连接 GoPro（$address）…连接成功后订阅响应特征并下发查询。';
    });
    try {
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(address);
      final sub = await Native.subscribeBleCharacteristic(
        address,
        goproAdvertisedServiceUuid,
        goproCommandResponseUuid,
      );
      if ((sub['ok'] as bool?) != true) {
        setState(() {
          _goproStatus = DeviceLinkStatus.unavailable;
          _notice = 'GoPro 响应特征订阅失败：${sub['error'] ?? 'unknown'}。'
              '常见原因：GATT 服务发现未完成，或该设备不是 Open GoPro 兼容设备。';
        });
        return;
      }
      final r = await Native.writeBleCharacteristic(
        address,
        goproAdvertisedServiceUuid,
        goproCommandWriteUuid,
        buildGoProGetVersion(),
      );
      if (!mounted) return;
      setState(() {
        if ((r['ok'] as bool?) == true) {
          _goproStatus = DeviceLinkStatus.connecting;
          _notice = 'Get Version 查询已下发：等待 GoPro 经 GP-0073 响应，'
              '收到响应后状态才变“已连接”；电量仍以响应/电量事件为准，不编造。';
        } else {
          _goproStatus = DeviceLinkStatus.unavailable;
          _notice = 'GoPro 查询下发失败：${r['error'] ?? 'unknown'}。';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _goproStatus = DeviceLinkStatus.unavailable;
        _notice = 'GoPro 连接失败：$e';
      });
    }
  }

  Future<void> _saveForm() async {
    final name = _nameCtrl.text.trim();
    final service = normalizeUuid(_serviceCtrl.text);
    final characteristic = normalizeUuid(_charCtrl.text);
    if (name.isEmpty || service == null || characteristic == null) {
      setState(() => _notice = '保存失败：名称不能为空，服务 UUID 与特征 UUID 须为完整 '
          '128-bit 或 4/8 位短 UUID 格式。');
      return;
    }
    final device = SavedDevice(
      name: name,
      serviceUuid: service,
      characteristicUuid: characteristic,
      type: _formType,
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
    );
    setState(() {
      _saved = [..._saved, device];
      _nameCtrl.clear();
      _serviceCtrl.clear();
      _charCtrl.clear();
      _addressCtrl.clear();
    });
    await _persist();
  }

  /// BleDIY NMEA 解析自测：用校验和已验算的示例语句跑一遍解析器，
  /// 证明解析逻辑可用；这不是真实设备数据，页面上会明说。
  void _runGpsDemo() {
    final feed = BleDiyGpsFeed();
    feed.feedLine(r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
    feed.feedLine(r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A');
    feed.feedLine(r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48');
    feed.feedLine(r'$GPGGA,123519,4807.038,N,01131.000,E,0,00,99.9,0.0,M,0.0,M,,*45');
    final fix = feed.latest;
    setState(() {
      _gpsDemoResult = fix == null
          ? '自测失败：示例语句未产出定位（ dropped=${feed.droppedCount}）。'
          : '自测（示例语句，非真实设备）：lat=${fix.lat.toStringAsFixed(5)}，'
              'lon=${fix.lon.toStringAsFixed(5)}，速度=${fix.speedMps?.toStringAsFixed(1)} m/s，'
              '方向=${fix.bearingDeg?.toStringAsFixed(1)}°，卫星=${fix.satellites}，'
              '无效定位语句已丢弃 ${feed.droppedCount} 条，未造假点。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: const Text('外接设备中心', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_notice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_notice!,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          _sectionTitle('运动相机'),
          _cameraCard(
            accent: accent,
            name: 'GoPro',
            subtitle: 'Open GoPro BLE：先点下方按钮扫描 FEA6 设备，再在扫描列表的 '
                'GoPro 行点“GoPro 连接”，依次完成连接 → 订阅响应特征 GP-0073 → '
                '下发 Get Version 只读查询；收到响应后状态才变已连接。',
            status: _goproStatus,
            batteryText: _goproBattery == null
                ? '电量：—（未收到电量事件，不显示假数值）'
                : '电量：$_goproBattery%',
            actionLabel: _goproScanning ? '停止扫描 GoPro' : '扫描 GoPro 设备',
            onAction: _scanGoPro,
          ),
          _cameraCard(
            accent: accent,
            name: 'Insta360',
            subtitle: 'Beta / 向导式连接：Wi-Fi 热点 + Insta360 App 连接，'
                '本 App 不直连相机。',
            status: DeviceLinkStatus.disconnected,
            batteryText: '电量：—（请在品牌 App 内查看）',
            actionLabel: '打开连接向导',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => CameraGuidePage(
                        brand: CameraGuideBrand.insta360,
                        onBack: () => Navigator.of(context).pop(),
                      )),
            ),
          ),
          _cameraCard(
            accent: accent,
            name: 'DJI',
            subtitle: 'Beta / 向导式连接：Wi-Fi 热点 + DJI Mimo App 连接，'
                '本 App 不直连相机。',
            status: DeviceLinkStatus.disconnected,
            batteryText: '电量：—（请在品牌 App 内查看）',
            actionLabel: '打开连接向导',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => CameraGuidePage(
                        brand: CameraGuideBrand.dji,
                        onBack: () => Navigator.of(context).pop(),
                      )),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('外接 GPS 模块'),
          const Text(
            '链路：BLE（NUS / RaceBox NMEA UART / 名称匹配）与经典蓝牙 SPP 双通道 → '
            '连接 → 订阅 / 直读 NMEA → main.dart 全局监听把有效定位注入 Recorder，'
            '5 秒无新定位自动回落手机 GPS。档案覆盖 RaceChrono 支持清单；'
            'Dragy 私有协议与 DEXIAN D1 协议未公开 / 未实测验证，仅通用 NMEA 兼容，'
            '不解析其私有数据流。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const ExternalGpsSection(),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _runGpsDemo,
                icon: const Icon(Icons.bug_report, size: 18),
                label: const Text('用示例语句自测 NMEA 解析'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SatelliteSettingsPage()),
                ),
                icon: const Icon(Icons.satellite_alt, size: 18),
                label: const Text('可视化外部 GPS 配置'),
              ),
            ),
          ]),
          if (_gpsDemoResult != null) ...[
            const SizedBox(height: 8),
            Text(_gpsDemoResult!,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          _sectionTitle('传感器：自定义 BLE 设备'),
          ExpansionTile(
            title: const Text('添加自定义传感器',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('名称 / 类型 / 服务 / 特征 / 地址（必填前四项）',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white70,
            children: [
              _textField(_nameCtrl, '名称，如：我的功率计'),
              _textField(_serviceCtrl, '服务 UUID（完整或 4/8 位短 UUID）'),
              _textField(_charCtrl, '特征 UUID（完整或 4/8 位短 UUID）'),
              _textField(_addressCtrl, '蓝牙地址（可选，用于下次重连，如 AA:BB:CC:DD:EE:FF）'),
              DropdownButton<String>(
                value: _formType,
                dropdownColor: const Color(0xFF1A1A1A),
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                items: customSensorTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _formType = v ?? _formType),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saveForm,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('保存到本机'),
              ),
              const SizedBox(height: 8),
            ],
          ),
          _sectionTitle('传感器：已保存设备（点重连）'),
          if (_saved.isEmpty)
            const Text('还没有保存的设备：用上方表单添加，地址填了才能重连。',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          for (final device in _saved)
            _savedRow(accent, device),
          const SizedBox(height: 16),
          _sectionTitle('传感器：附近扫描结果'),
          FilledButton.icon(
            onPressed: _toggleScan,
            icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching,
                size: 18),
            label: Text(_scanning ? '停止扫描' : '开始扫描'),
          ),
          const SizedBox(height: 8),
          if (_scanned.isEmpty)
            const Text('暂无扫描结果。',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          for (final dev in _scanned)
            ListTile(
              title: Text((dev['name'] ?? '').toString(),
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                  '${dev['address']} · ${dev['type']} · RSSI ${dev['rssi']}'
                  '${_isGoProScanned(dev) ? ' · GoPro（广播含 FEA6）' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isGoProScanned(dev))
                    TextButton(
                      onPressed: () {
                        final addr = (dev['address'] ?? '').toString();
                        if (addr.isNotEmpty) _connectGoProDevice(addr);
                      },
                      child: const Text('GoPro 连接'),
                    ),
                  TextButton(
                    onPressed: () async {
                      final addr = (dev['address'] ?? '').toString();
                      if (addr.isEmpty) return;
                      try {
                        setState(() => _statusByAddress[addr] =
                            DeviceLinkStatus.connecting);
                        await Native.connectBle(addr);
                      } catch (e) {
                        setState(() => _notice = '连接失败：$e');
                      }
                    },
                    child: const Text('连接'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      );

  Widget _textField(TextEditingController ctrl, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _cameraCard({
    required Color accent,
    required String name,
    required String subtitle,
    required DeviceLinkStatus status,
    required String batteryText,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: status == DeviceLinkStatus.connected
                      ? Colors.green.withValues(alpha: 0.2)
                      : accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.label,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(batteryText,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  /// 扫描行是否为 GoPro：广播服务含 FEA6，或名称含 GoPro（名称仅提示，
  /// 不作身份断言；真正连接仍走 FEA6 服务下的 GP-0072/0073 特征查找，
  /// 找不到特征时如实报 characteristic_not_found）。
  bool _isGoProScanned(Map<String, dynamic> dev) {
    final uuids = ((dev['serviceUuids'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (isGoProAdvertisement(uuids)) return true;
    return (dev['name'] ?? '').toString().toLowerCase().contains('gopro');
  }

  Widget _savedRow(Color accent, SavedDevice device) {
    final addr = device.address;
    final status = addr == null
        ? DeviceLinkStatus.disconnected
        : (_statusByAddress[addr] ?? DeviceLinkStatus.disconnected);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(device.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Text(status.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${device.type} · 服务 ${device.serviceUuid} · 特征 ${device.characteristicUuid}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(addr == null ? '未填地址：无法重连' : '地址 $addr',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: addr == null ? null : () => _connectSaved(device),
                child: const Text('重连'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  setState(() => _saved =
                      _saved.where((d) => d != device).toList());
                  await _persist();
                },
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
