import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'blediy_gps.dart';
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

/// 外接 GPS 模块的设备类别（v1.0.2，第 6 项）。
///
/// 支持程度必须如实标注，绝不冒充：只有“通用 NMEA 解析”本身是
/// 已实现的（blediy_gps.dart 的 GGA / RMC / VTG）；厂商私有协议
/// 只要没公开文档、没实测设备，一律标“协议未公开 / 未实测验证，
/// 仅通用 NMEA 兼容”，且 [serviceUuid] / [txUuid] 保持 null，
/// 绝不凭猜测填一个 UUID。
enum ExternalGpsKind { blediy, dragy, dexian, genericNmea }

/// 一类外接 GPS 的档案。serviceUuid / txUuid 为 null = 该厂商
/// 没有公开可确认的 BLE 服务 / 特征 UUID，本 App 不自动订阅它。
class ExternalGpsProfile {
  const ExternalGpsProfile({
    required this.kind,
    required this.name,
    required this.note,
    this.serviceUuid,
    this.txUuid,
  });

  final ExternalGpsKind kind;
  final String name;
  final String note;
  final String? serviceUuid;
  final String? txUuid;

  /// 是否有可确认的 NMEA 订阅路径（不是“厂商已完整支持”）。
  bool get hasNmeaPath => serviceUuid != null && txUuid != null;

  /// 页面上的支持程度徽标文案。
  String get supportBadge => hasNmeaPath
      ? '通用 NMEA 兼容（GGA / RMC / VTG 解析已实现）'
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
///   因此本档案不填它。
/// - 通用 NMEA BLE UART：默认 Nordic UART，可改填设备实际广播值。
const List<ExternalGpsProfile> externalGpsProfiles = [
  ExternalGpsProfile(
    kind: ExternalGpsKind.blediy,
    name: 'BleDIY（RaceChrono DIY 兼容）',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    note: 'NMEA 文本经 BLE UART 推送时可订阅解析；服务 / 特征为 '
        'Nordic UART 通用默认值，非 RaceChrono 官方专属值，实际设备以广播为准。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dragy,
    name: 'Dragy（DRG70 / DRG70-C / Pro DRG71）',
    note: '协议未公开 / 未实测验证：官方只说明蓝牙连接与官方 App，'
        '未公开 BLE 服务 / 特征 UUID 与数据格式；本 App 不解析 Dragy 私有数据流。'
        '若该设备以 NMEA 文本经 BLE UART 推送，请走“通用 NMEA BLE UART”'
        '填入实际广播的 UUID 后订阅，否则暂不支持。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.dexian,
    name: 'DEXIAN Timer（D1）',
    note: '协议未公开 / 未实测验证：Dexian Timer 应用介绍称兼容 D1 25Hz GPS '
        '且支持 RaceChrono DIY 协议设备，但未找到 D1 本身公开的 BLE 服务 / '
        '特征 UUID 与数据格式；本 App 不解析 D1 私有数据流，走通用 NMEA 路径时'
        '同样须以设备实际广播的 UUID 为准。',
  ),
  ExternalGpsProfile(
    kind: ExternalGpsKind.genericNmea,
    name: '通用 NMEA BLE UART',
    serviceUuid: nordicUartServiceUuid,
    txUuid: nordicUartTxUuid,
    note: '默认 Nordic UART；下方可改填设备实际广播的服务 / 特征 UUID。'
        '只解析 NMEA 文本（GGA / RMC / VTG），非 NMEA 二进制流一律丢弃计数。',
  ),
];

/// 外接 GPS 模块区（v1.0.2，第 6 项），供 DeviceCenterPage 嵌入。
///
/// 定位源切换复用现有链路，不另造一套（主协调接线见回执）：
/// 本区只做扫描 → 连接 → 订阅 NUS TX（…0003）；订阅成功后，
/// main.dart 已有的全局 bleData 监听（uuid 含 '0003' 时喂给
/// BleDiyGpsFeed）会自动把有效定位注入 Recorder：externalGpsActive
/// = true，行程落点改走 Recorder.onExternalFix；外部源 5 秒无新
/// 定位或断线时，main.dart 的回落逻辑自动切回手机 GPS。本区不
/// 直接持有 Recorder、不改 Recorder、不改 main.dart。
///
/// 原生层限制（必须如实显示，不假装全量扫描）：
/// - 原生扫描始终带服务过滤：scanBleWithServices 传入 NUS 时只扫
///   广播 NUS 的设备；不广播 NUS（或不广播骑行三类服务）的设备
///   可能扫不到，须先在系统蓝牙里看到它，或用下方通用表单登记
///   地址后直连。
/// - 原生单 GATT：一次只能连一台设备，连新设备会断开旧的。
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
  String? _notice;
  String? _connectedAddress;
  bool _subscribed = false;
  String? _subscribeError;
  // 已连接后待订阅的 (address, service, tx)；GATT 服务发现是异步的，
  // 连接事件到达时若立即订阅报 characteristic_not_found，会在
  // connected 事件里再试一次（见 _dataSub）。
  ({String address, String service, String tx})? _pendingSubscribe;

  final BleDiyGpsFeed _feed = BleDiyGpsFeed();
  StreamSubscription<Map<String, dynamic>>? _devSub;
  StreamSubscription<Map<String, dynamic>>? _dataSub;

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
      final addr = (e['address'] ?? '').toString();
      if (addr.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _scanned.removeWhere((d) => d['address'] == addr);
        _scanned.insert(0, e);
      });
    }, onError: (_) {});
    _dataSub = Native.bleDataStream.listen((e) async {
      final type = (e['type'] ?? '').toString();
      if (!mounted) return;
      if (type == 'connected') {
        final addr = (e['address'] ?? '').toString();
        setState(() => _connectedAddress = addr.isEmpty ? null : addr);
        final pending = _pendingSubscribe;
        if (pending != null && pending.address == addr) {
          await _doSubscribe(pending.address, pending.service, pending.tx);
        }
      } else if (type == 'disconnected') {
        setState(() {
          _connectedAddress = null;
          _subscribed = false;
          _pendingSubscribe = null;
          _notice = '外接 GPS 已断开：解析器已重置，行程定位由 main.dart 回落逻辑切回手机 GPS。';
        });
        _feed.reset();
      } else if (type == 'bleNotification') {
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
    _customServiceCtrl.dispose();
    _customTxCtrl.dispose();
    super.dispose();
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
        // 只扫广播 NUS 的设备；Dragy / DEXIAN 若不广播 NUS，
        // 本次扫描不会出现它（见本区顶部的原生层限制说明）。
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

  Future<void> _connectScanned(Map<String, dynamic> dev) async {
    final addr = (dev['address'] ?? '').toString();
    if (addr.isEmpty) return;
    final uuids = _effectiveUuids;
    if (uuids == null) {
      // Dragy / DEXIAN：无公开 UUID，不猜、不自动订阅，只连 GATT。
      try {
        setState(() => _notice = '正在连接“${dev['name']}”…');
        await Native.setBleAutoReconnect(true);
        await Native.connectBle(addr);
        setState(() {
          _connectedAddress = addr;
          _pendingSubscribe = null;
          _notice = '已发起连接（GATT 层）：该厂商协议未公开，无法自动订阅数据特征。'
              '若设备以 NMEA 文本经 BLE UART 推送，请切到“通用 NMEA BLE UART”，'
              '填入实际广播的服务 / 特征 UUID 后点“订阅 NMEA”，否则本 App '
              '暂不能解析该厂商私有数据流。';
        });
      } catch (e) {
        setState(() => _notice = '连接失败：$e');
      }
      return;
    }
    try {
      setState(() {
        _notice = '正在连接“${dev['name']}”…连接成功后自动订阅 NMEA 特征。';
        _pendingSubscribe =
            (address: addr, service: uuids.service, tx: uuids.tx);
      });
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(addr);
      // GATT 服务发现完成前订阅可能报 not_found，connected 事件里会再试一次。
      await _doSubscribe(addr, uuids.service, uuids.tx);
    } catch (e) {
      setState(() => _notice = '连接失败：$e');
    }
  }

  /// 对已连接设备直接尝试订阅 NMEA 特征（不重新连接）。
  Future<void> _subscribeConnected() async {
    final addr = _connectedAddress;
    final uuids = _effectiveUuids;
    if (addr == null || uuids == null) {
      setState(() => _notice = '无已连接设备或当前类别无可确认的 UUID，无法订阅。');
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
      await Native.disconnectBle();
    } catch (_) {}
    _feed.reset();
    if (!mounted) return;
    setState(() {
      _connectedAddress = null;
      _subscribed = false;
      _pendingSubscribe = null;
      _notice = '已断开外接 GPS：解析器已重置，行程定位回落手机 GPS。';
    });
  }

  Future<void> _saveConnectedAsSaved() async {
    final addr = _connectedAddress;
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

  /// 扫描行的提示：只按广播内容与名称字样提示，名称含厂商字样
  /// 不等于身份断言，绝不把名称当作协议证据。
  String _guessHint(Map<String, dynamic> dev) {
    final uuids = ((dev['serviceUuids'] as List?) ?? [])
        .map((e) => e.toString().toLowerCase())
        .toList();
    if (uuids.any((u) => u.contains('6e400001'))) {
      return '广播含 Nordic UART 服务，可尝试订阅 NMEA。';
    }
    final name = (dev['name'] ?? '').toString().toLowerCase();
    if (name.contains('dragy') || name.contains('dexian')) {
      return '名称含厂商字样（仅名称提示，不作身份断言），服务 UUID 以广播为准。';
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
          '定位源切换复用现有链路，不另造一套：本区只负责扫描、连接与订阅 '
          'NUS TX（…0003）；订阅成功后，main.dart 已有的全局 bleData 监听会把'
          '有效定位注入 Recorder（externalGpsActive = true，落点走 '
          'Recorder.onExternalFix），外部源 5 秒无新定位或断线时自动回落手机 GPS。'
          '本区不直接持有 Recorder、不改 main.dart。原生单 GATT：一次只能连一台设备。',
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
                            '${_subscribed ? ' · 已订阅 NMEA' : ' · 未订阅'}',
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
                    : '最新定位：lat=${fix.lat.toStringAsFixed(5)}，'
                        'lon=${fix.lon.toStringAsFixed(5)}，'
                        '速度=${fix.speedMps == null ? '—' : '${(fix.speedMps! * 3.6).toStringAsFixed(1)} km/h'}，'
                        '卫星=${fix.satellites ?? '—'}，HDOP=${fix.hdop ?? '—'}'
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
                    uuids == null
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
        if (_scanned.isEmpty)
          const Text('暂无本区扫描结果：点上方扫描，或用下方“附近扫描结果”里的设备连接。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        for (final dev in _scanned)
          ListTile(
            title: Text((dev['name'] ?? '').toString(),
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(
                '${dev['address']} · ${dev['type']} · RSSI ${dev['rssi']} · ${_guessHint(dev)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: TextButton(
              onPressed: () => _connectScanned(dev),
              child: const Text('连接'),
            ),
          ),
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
            '链路：扫描（NUS 过滤）→ 连接 → 订阅 NUS TX（…0003）→ main.dart '
            '全局监听把有效定位注入 Recorder，5 秒无新定位自动回落手机 GPS。'
            'Dragy / DEXIAN 协议未公开 / 未实测验证，仅通用 NMEA 兼容，'
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
