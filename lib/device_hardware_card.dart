import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_bar_style.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'dt_page_route.dart';
import 'firmware_update_page.dart';
import 'firmware_update_service.dart';
import 'native.dart';

/// 自研硬件（GPS 计时模块）的管理卡（v1.7.0）。
///
/// 外接 GPS 卡片在连上自研硬件后切换为本卡：实时电量、固件信息、
/// 实时状态（定位 / 圈速）、圈速导入、固件升级、App 内关机。
///
/// 数据全部来自设备热点上的 HTTP 接口，字段缺失一律显示“—”，
/// 能力未声明（旧固件）的按钮置灰，绝不假装可用；
/// 设备不可达时明确提示先连接热点，不伪造读数。
class DeviceHardwareCard extends StatefulWidget {
  const DeviceHardwareCard({
    super.key,
    this.service,
    this.pollInterval = const Duration(seconds: 3),
  });

  /// 测试注入；默认按设备热点地址创建。
  final FirmwareUpdateService? service;

  final Duration pollInterval;

  @override
  State<DeviceHardwareCard> createState() => _DeviceHardwareCardState();
}

class _DeviceHardwareCardState extends State<DeviceHardwareCard> {
  late final FirmwareUpdateService _service =
      widget.service ?? FirmwareUpdateService();

  Timer? _timer;
  bool _probing = true;
  bool _reachable = false;
  bool _poweredOff = false;
  bool _busy = false;
  String? _notice;

  FirmwareDeviceInfo? _info;
  DeviceRuntimeStatus? _status;
  List<HardwareLapSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _refresh();
    _timer = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final list = await HardwareLapStore.load();
    if (!mounted) return;
    setState(() => _sessions = list);
  }

  Future<void> _refresh() async {
    if (_busy || !mounted) return;
    final info = await _service.probeDevice(
      timeout: const Duration(seconds: 3),
    );
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _probing = false;
        _reachable = false;
        _info = null;
        _status = null;
      });
      return;
    }
    final status = await _service.readStatus();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _reachable = true;
      _poweredOff = false;
      _info = info;
      _status = status;
    });
  }

  S get _s => S.of(context);

  String _v(String? value) => (value == null || value.isEmpty) ? '—' : value;

  String _duration(int? ms) {
    if (ms == null || ms < 0) return '—';
    if (ms < 1000) return '${ms}ms';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final millis = ms % 1000;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}.'
          '${millis.toString().padLeft(3, '0')}';
    }
    return '$seconds.${millis.toString().padLeft(3, '0')}s';
  }

  String _uptime(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ${seconds % 60}s';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Future<void> _upgrade() async {
    await Navigator.of(
      context,
    ).push(DtPageRoute(builder: (_) => FirmwareUpdatePage(service: _service)));
    if (mounted) _refresh();
  }

  Future<void> _shutdown() async {
    final s = _s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.t('关闭硬件电源', 'Power off device')),
        content: Text(
          s.t(
            '关机后设备会立即断开热点，只能通过机身按键重新开机。确认关机？',
            'The device will drop its hotspot and can only be powered on again with the physical button. Continue?',
          ),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.t('关机', 'Power off'),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await _service.shutdown();
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _busy = false;
        _poweredOff = true;
        _reachable = false;
        _info = null;
        _status = null;
        _notice = _s.t('已发送关机指令，设备正在关机。', 'Power-off command sent.');
      });
      showAppNotice(
        context,
        _s.t('设备关机中', 'Powering off'),
        AppNoticeKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = _s.t('关机失败：$e', 'Power off failed: $e');
      });
    }
  }

  Future<void> _readLaps() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final laps = await _service.readLaps();
    if (!mounted) return;
    setState(() => _busy = false);
    if (laps.isEmpty) {
      setState(
        () => _notice = _s.t(
          '没有读到圈速：设备未记录，或当前固件不支持圈速接口。',
          'No laps: nothing recorded, or the firmware has no laps API.',
        ),
      );
      return;
    }
    final session = HardwareLapSession(
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
      model: _info?.model ?? '',
      laps: laps,
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      isScrollControlled: true,
      builder: (ctx) => _LapSheet(session: session),
    );
    if (action != 'import' || !mounted) return;
    final result = await HardwareLapStore.append(session);
    if (!mounted) return;
    setState(() {
      _notice = result == HardwareLapImportResult.duplicate
          ? _s.t('这批圈速已经导入过，无需重复导入。', 'These laps were already imported.')
          : result == HardwareLapImportResult.saved
          ? _s.t('已导入 ${laps.length} 圈到本机。', 'Imported ${laps.length} laps.')
          : _s.t('导入失败：本机文件写入失败。', 'Import failed: local write error.');
    });
    if (result == HardwareLapImportResult.saved) await _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final accent = Theme.of(context).colorScheme.primary;
    final info = _info;
    final status = _status;
    final battery = status?.batteryPercent ?? info?.batteryPercent;
    final charging = status?.charging ?? info?.charging;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('自研硬件管理', 'DriveTrack hardware'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _poweredOff
                          ? s.t('已关机', 'Powered off')
                          : _reachable
                          ? s.t('已连接设备热点', 'Device hotspot connected')
                          : _probing
                          ? s.t('正在检测…', 'Detecting…')
                          : s.t('未连接设备热点', 'Device hotspot not connected'),
                      style: TextStyle(
                        color: _reachable
                            ? Colors.greenAccent
                            : _probing
                            ? Colors.white54
                            : Colors.orangeAccent,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: s.t('刷新', 'Refresh'),
                onPressed: _busy ? null : _refresh,
                icon: const Icon(
                  Icons.refresh,
                  size: 20,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_reachable) ...[
            Text(
              _poweredOff
                  ? s.t(
                      '设备已关机，需要时按机身按键重新开机。',
                      'Device is off. Use the physical button to power it on.',
                    )
                  : s.t(
                      '在系统 WiFi 里连接设备热点（${FirmwareUpdateService.accessPointPrefix}-XXXX，密码 ${FirmwareUpdateService.accessPointPassword}），即可查看电量、固件并在此关机。',
                      'Join the device hotspot (${FirmwareUpdateService.accessPointPrefix}-XXXX, password ${FirmwareUpdateService.accessPointPassword}) to read battery and firmware, or power it off.',
                    ),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ] else ...[
            // 电量
            Row(
              children: [
                Icon(
                  charging == true
                      ? Icons.battery_charging_full
                      : Icons.battery_full,
                  size: 18,
                  color: battery == null
                      ? Colors.white24
                      : battery <= 20
                      ? Colors.orangeAccent
                      : Colors.greenAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: battery == null
                          ? 0
                          : (battery / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      color: battery == null
                          ? Colors.white12
                          : battery <= 20
                          ? Colors.orangeAccent
                          : accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  battery == null
                      ? s.t('电量 —', 'Battery —')
                      : '$battery%${charging == true ? ' · ${s.t('充电中', 'Charging')}' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoGrid(s, info, status),
            if (_sessions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _importedSummary(s),
            ],
          ],
          if (_notice != null) ...[
            const SizedBox(height: 10),
            Text(
              _notice!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_reachable) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _readLaps,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(s.t('读取圈速', 'Read laps')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _upgrade,
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: Text(s.t('固件升级', 'Firmware')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_busy || status?.supportsShutdown != true)
                    ? null
                    : _shutdown,
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: Text(
                  status?.supportsShutdown == true
                      ? s.t('关闭硬件电源', 'Power off device')
                      : s.t('关机（固件不支持，请先升级）', 'Power off (upgrade firmware)'),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _upgrade,
                icon: const Icon(Icons.system_update_alt, size: 18),
                label: Text(s.t('打开固件升级', 'Firmware update')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoGrid(S s, FirmwareDeviceInfo? info, DeviceRuntimeStatus? status) {
    final rows = <(String, String)>[
      (s.t('型号', 'Model'), _v(info?.model)),
      (
        s.t('当前固件', 'Firmware'),
        info == null
            ? '—'
            : '${info.version}${info.build > 0 ? ' (${info.build})' : ''}',
      ),
      (s.t('运行时长', 'Uptime'), _uptime(status?.uptimeMs ?? info?.uptimeMs)),
      (
        s.t('定位', 'GNSS'),
        status == null
            ? '—'
            : status.hasFix == true
            ? s.t('已定位', 'Fix')
            : status.hasFix == false
            ? s.t('未定位', 'No fix')
            : '—',
      ),
      (
        s.t('卫星', 'Satellites'),
        status?.satellites == null ? '—' : '${status!.satellites}',
      ),
      // 固件 0.4.0+ 才上报 SD 字段；旧固件整行不出现，避免显示成“0 GB”。
      if (status?.sdTotalKb != null)
        (s.t('存储卡', 'microSD'), _sdText(s, status!)),
      (
        s.t('已记录圈数', 'Laps recorded'),
        status?.lapCount == null ? '—' : '${status!.lapCount}',
      ),
      (s.t('当前圈', 'Current lap'), _duration(status?.currentLapMs)),
      (s.t('最快圈', 'Best lap'), _duration(status?.bestLapMs)),
      (s.t('上一圈', 'Last lap'), _duration(status?.lastLapMs)),
      (
        s.t('空闲内存', 'Free heap'),
        info?.freeHeap == null ? '—' : '${info!.freeHeap} B',
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _kv(s, rows[i].$1, rows[i].$2)),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < rows.length
                    ? _kv(s, rows[i + 1].$1, rows[i + 1].$2)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (i + 2 < rows.length) const SizedBox(height: 10),
        ],
      ],
    );
  }

  String _sdText(S s, DeviceRuntimeStatus st) {
    final total = st.sdTotalKb ?? 0;
    final free = st.sdFreeKb ?? 0;
    if (!st.sdMounted) {
      switch (st.sdState) {
        case 'mount_fail':
          return s.t('挂载失败', 'Mount failed');
        case 'no_card':
          return s.t('未插卡', 'No card');
        default:
          return s.t('不可用', 'Unavailable');
      }
    }
    final used = (total - free).clamp(0, total);
    return '${_size(used)} / ${_size(total)}'
        '（${s.t('可用', 'free')} ${_size(free)}）';
  }

  String _size(int kb) {
    if (kb >= 1024 * 1024) {
      return '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(0)} MB';
    return '$kb KB';
  }

  Widget _kv(S s, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _importedSummary(S s) {
    final latest = _sessions.first;
    final best = latest.laps
        .map((l) => l.timeMs)
        .reduce((a, b) => a < b ? a : b);
    return Text(
      s.t(
        '本机已导入 ${_sessions.length} 组圈速 · 最近 ${latest.laps.length} 圈 · 最快 ${_duration(best)}',
        '${_sessions.length} lap set(s) imported · last ${latest.laps.length} laps · best ${_duration(best)}',
      ),
      style: const TextStyle(color: Colors.white54, fontSize: 11.5),
    );
  }
}

/// 广播名仅用于识别自研硬件；第三方设备不会进入硬件管理数据通道。
bool isDriveTrackHardwareName(String name) =>
    name.trim().toLowerCase().contains('drivetrack');

/// 已保存设备的完整管理页（v1.7.14）。
///
/// 蓝牙连接与 RSSI 来自原生通道；自研硬件的电量、传感器、卫星、
/// 固件与 microSD 来自设备热点接口。任何字段未上报都显示“—”，
/// 不用缓存值或默认值冒充实测状态。
class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({
    super.key,
    required this.deviceName,
    required this.address,
    required this.deviceType,
    this.serviceUuid = '',
    this.characteristicUuid = '',
    this.connected = false,
    this.onConnect,
    this.onDisconnect,
    this.service,
    this.pollInterval = const Duration(seconds: 3),
  });

  final String deviceName;
  final String? address;
  final String deviceType;
  final String serviceUuid;
  final String characteristicUuid;
  final bool connected;
  final Future<void> Function()? onConnect;
  final Future<void> Function()? onDisconnect;
  final FirmwareUpdateService? service;
  final Duration pollInterval;

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  late final FirmwareUpdateService _service =
      widget.service ?? FirmwareUpdateService();
  late bool _connected = widget.connected;

  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _dataSub;
  bool _refreshing = false;
  bool _probing = true;
  bool _reachable = false;
  bool _poweredOff = false;
  bool _busy = false;
  int? _rssi;
  FirmwareDeviceInfo? _info;
  DeviceRuntimeStatus? _status;

  bool get _ownHardware => isDriveTrackHardwareName(widget.deviceName);
  S get _s => S.of(context);

  @override
  void initState() {
    super.initState();
    _dataSub = Native.bleDataStream.listen((event) {
      final type = (event['type'] ?? '').toString();
      final address = (event['address'] ?? '').toString();
      if (!mounted) return;
      if (type == 'connected' && address == widget.address) {
        setState(() => _connected = true);
        _refresh();
      } else if (type == 'disconnected') {
        setState(() {
          _connected = false;
          _rssi = null;
        });
      }
    }, onError: (_) {});
    _refresh();
    _timer = Timer.periodic(widget.pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSub?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final rssi = _connected ? await Native.readBleRssi() : null;
      if (!_ownHardware) {
        if (mounted) setState(() => _rssi = rssi);
        return;
      }
      final info = await _service.probeDevice(
        timeout: const Duration(seconds: 3),
      );
      final status = info == null ? null : await _service.readStatus();
      if (!mounted) return;
      setState(() {
        _rssi = rssi;
        _probing = false;
        _reachable = info != null;
        if (info != null) _poweredOff = false;
        _info = info;
        _status = status;
      });
    } finally {
      _refreshing = false;
    }
  }

  String _v(String? value) => (value == null || value.isEmpty) ? '—' : value;

  String _uptime(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final seconds = ms ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ${seconds % 60}s';
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  String _size(int kb) {
    if (kb >= 1024 * 1024) {
      return '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(0)} MB';
    return '$kb KB';
  }

  String _signalText() {
    if (!_connected) return '—';
    final rssi = _rssi;
    if (rssi == null) return _s.t('读取中…', 'Reading…');
    final quality = rssi >= -60
        ? _s.t('良好', 'Good')
        : rssi >= -80
        ? _s.t('一般', 'Fair')
        : _s.t('较弱', 'Weak');
    return '$rssi dBm · $quality';
  }

  String _sensorText(bool? ready) => switch (ready) {
    true => _s.t('工作正常', 'Ready'),
    false => _s.t('未就绪 / 异常', 'Not ready'),
    null => '—',
  };

  Future<void> _toggleConnection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_connected) {
        await widget.onDisconnect?.call();
      } else {
        await widget.onConnect?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upgrade() async {
    await Navigator.of(
      context,
    ).push(DtPageRoute(builder: (_) => FirmwareUpdatePage(service: _service)));
    if (mounted) _refresh();
  }

  Future<void> _shutdown() async {
    final s = _s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.t('关闭硬件电源', 'Power off device')),
        content: Text(
          s.t(
            '关机后设备会断开蓝牙与热点，只能按机身按键重新开机。确认关机？',
            'This disconnects Bluetooth and the hotspot. Use the physical button to power on again. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.t('关机', 'Power off'),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.shutdown();
      if (!mounted) return;
      setState(() {
        _poweredOff = true;
        _reachable = false;
        _connected = false;
        _info = null;
        _status = null;
        _rssi = null;
      });
      showAppNotice(
        context,
        s.t('已发送关机指令', 'Power-off command sent'),
        AppNoticeKind.success,
      );
    } catch (error) {
      if (mounted) {
        showAppNotice(
          context,
          s.t('关机失败：$error', 'Power off failed: $error'),
          AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPairingPassword() async {
    final s = _s;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.t('更改配对密码', 'Change pairing PIN')),
        content: Text(
          _ownHardware
              ? s.t(
                  '当前硬件固件使用 BLE 直连，未启用可修改的数字配对 PIN，因此这里不能设置新密码。自动重连已改为不再主动请求系统配对；若系统里残留旧配对，可先在系统蓝牙中忽略此设备，再手动连接。',
                  'This firmware uses direct BLE and has no configurable numeric pairing PIN. Automatic reconnect no longer requests bonding. If an old bond remains, forget it in system Bluetooth and reconnect manually.',
                )
              : s.t(
                  '配对密码由设备厂商固件管理，DriveTrack 不能修改第三方设备的 PIN。',
                  'The manufacturer firmware owns pairing. DriveTrack cannot change a third-party device PIN.',
                ),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.t('知道了', 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final accent = Theme.of(context).colorScheme.primary;
    final battery = _status?.batteryPercent ?? _info?.batteryPercent;
    final charging = _status?.charging ?? _info?.charging;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          s.t('设备管理', 'Device management'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: s.t('刷新', 'Refresh'),
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh, color: Colors.white54),
          ),
        ],
      ),
      body: ListView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 16, 16, 32),
        ),
        children: [
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(
                        _ownHardware ? Icons.memory : Icons.sensors,
                        size: 34,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.deviceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _poweredOff
                                ? s.t('已关机', 'Powered off')
                                : _connected
                                ? s.t('蓝牙已连接', 'Bluetooth connected')
                                : s.t('蓝牙未连接', 'Bluetooth disconnected'),
                            style: TextStyle(
                              color: _connected
                                  ? Colors.greenAccent
                                  : Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_ownHardware) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        charging == true
                            ? Icons.battery_charging_full
                            : Icons.battery_full,
                        color: battery != null && battery <= 20
                            ? Colors.orangeAccent
                            : Colors.greenAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.t('电池电量', 'Battery'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        battery == null
                            ? '—'
                            : '$battery%${charging == true ? ' · ${s.t('充电中', 'Charging')}' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: battery == null
                          ? 0
                          : (battery / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      color: battery != null && battery <= 20
                          ? Colors.orangeAccent
                          : accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          _section(
            s.t('连接与信号', 'Connection & signal'),
            Column(
              children: [
                _row(
                  s.t('连接状态', 'Connection'),
                  _connected
                      ? s.t('已连接', 'Connected')
                      : s.t('未连接', 'Disconnected'),
                  valueColor: _connected ? Colors.greenAccent : Colors.white54,
                ),
                _row(s.t('信号强度', 'Signal'), _signalText()),
                _row(s.t('蓝牙地址', 'Address'), _v(widget.address)),
                _row(s.t('设备类型', 'Type'), _v(widget.deviceType)),
                if (widget.serviceUuid.isNotEmpty)
                  _row(s.t('服务 UUID', 'Service UUID'), widget.serviceUuid),
                if (widget.characteristicUuid.isNotEmpty)
                  _row(
                    s.t('特征 UUID', 'Characteristic UUID'),
                    widget.characteristicUuid,
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_busy ||
                            (!_connected &&
                                (widget.onConnect == null ||
                                    (widget.address ?? '').isEmpty)))
                        ? null
                        : _toggleConnection,
                    icon: Icon(
                      _connected ? Icons.bluetooth_disabled : Icons.bluetooth,
                      size: 18,
                    ),
                    label: Text(
                      _connected
                          ? s.t('断开连接', 'Disconnect')
                          : s.t('连接设备', 'Connect'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_ownHardware) ...[
            if (!_reachable)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _poweredOff
                      ? s.t(
                          '设备已关机，按机身按键可重新开机。',
                          'Device is off. Use the physical button to power it on.',
                        )
                      : _probing
                      ? s.t('正在读取硬件状态…', 'Reading hardware status…')
                      : s.t(
                          '蓝牙可传输定位；电量、传感器、固件与存储详情需连接设备热点 ${FirmwareUpdateService.accessPointPrefix}-XXXX（密码 ${FirmwareUpdateService.accessPointPassword}）。',
                          'Bluetooth carries GPS. Join ${FirmwareUpdateService.accessPointPrefix}-XXXX (password ${FirmwareUpdateService.accessPointPassword}) for battery, sensors, firmware and storage.',
                        ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ),
            _section(
              s.t('传感器状态', 'Sensors'),
              Column(
                children: [
                  _row('IMU（BMI088）', _sensorText(_status?.imuReady)),
                  _row(
                    s.t('气压计（BMP388/390）', 'Barometer (BMP388/390)'),
                    _sensorText(_status?.baroReady),
                  ),
                ],
              ),
            ),
            _section(
              s.t('卫星与定位', 'GNSS & positioning'),
              Column(
                children: [
                  _row(
                    s.t('搜星状态', 'Fix status'),
                    _status?.hasFix == true
                        ? s.t('已定位', 'Fix acquired')
                        : _status?.hasFix == false
                        ? s.t('搜星中 / 未定位', 'Searching / no fix')
                        : '—',
                    valueColor: _status?.hasFix == true
                        ? Colors.greenAccent
                        : Colors.white70,
                  ),
                  _row(
                    s.t('卫星数量', 'Satellites'),
                    _status?.satellites == null
                        ? '—'
                        : s.t(
                            '${_status!.satellites} 颗',
                            '${_status!.satellites}',
                          ),
                  ),
                  _row(
                    s.t('记录状态', 'Recording'),
                    _status?.recording == true
                        ? s.t('记录中', 'Recording')
                        : _status?.recording == false
                        ? s.t('待机', 'Idle')
                        : '—',
                  ),
                ],
              ),
            ),
            _section(
              s.t('固件信息', 'Firmware'),
              Column(
                children: [
                  _row(s.t('设备名称', 'Device name'), widget.deviceName),
                  _row(s.t('设备型号', 'Model'), _v(_info?.model)),
                  _row(s.t('固件版本', 'Version'), _v(_info?.version)),
                  _row(
                    'Build',
                    _info?.build == null || _info!.build <= 0
                        ? '—'
                        : '${_info!.build}',
                  ),
                  _row(
                    s.t('运行时长', 'Uptime'),
                    _uptime(_status?.uptimeMs ?? _info?.uptimeMs),
                  ),
                  _row(
                    s.t('空闲内存', 'Free heap'),
                    _status?.freeHeap == null && _info?.freeHeap == null
                        ? '—'
                        : '${_status?.freeHeap ?? _info!.freeHeap} B',
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _upgrade,
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: Text(s.t('固件升级', 'Firmware update')),
                    ),
                  ),
                ],
              ),
            ),
            _section(s.t('硬件存储', 'Hardware storage'), _storageSection()),
            _section(
              s.t('电源管理', 'Power'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_busy || _status?.supportsShutdown != true)
                          ? null
                          : _shutdown,
                      icon: const Icon(Icons.power_settings_new, size: 18),
                      label: Text(
                        _status?.supportsShutdown == true
                            ? s.t('关闭硬件电源', 'Power off device')
                            : s.t(
                                '关机（连接热点并升级固件后可用）',
                                'Power off (connect hotspot / upgrade firmware)',
                              ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t(
                      '硬件不支持远程开机；关机后需按机身按键开机。',
                      'Remote power-on is unsupported. Use the physical button after power-off.',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                s.t(
                  '第三方设备没有 DriveTrack 硬件管理接口，本页只展示实际可读取的蓝牙信息。',
                  'This third-party device has no DriveTrack hardware API; only readable Bluetooth data is shown.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          _section(
            s.t('配对与安全', 'Pairing & security'),
            DriveTrackEntryCard(
              icon: Icons.password,
              title: s.t('更改配对密码', 'Change pairing PIN'),
              subtitle: _ownHardware
                  ? s.t(
                      '当前固件未启用可修改的配对 PIN',
                      'No configurable pairing PIN in current firmware',
                    )
                  : s.t('由设备厂商固件管理', 'Managed by device firmware'),
              onTap: _showPairingPassword,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageSection() {
    final s = _s;
    final status = _status;
    final hasStorage =
        status != null &&
        (status.sdPresent != null ||
            status.sdState != null ||
            status.sdTotalKb != null);
    if (!hasStorage) {
      return Text(
        status == null
            ? s.t(
                '连接设备热点后读取 microSD 状态、总容量与可用空间。',
                'Connect to the device hotspot to read microSD status and capacity.',
              )
            : s.t(
                '当前固件未上报存储信息，请升级固件。',
                'Current firmware does not report storage. Upgrade firmware.',
              ),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          height: 1.5,
        ),
      );
    }
    final total = status.sdTotalKb;
    final free = status.sdFreeKb;
    final int? used = total == null || free == null
        ? null
        : (total - free).clamp(0, total);
    final state = status.sdMounted
        ? s.t('已挂载', 'Mounted')
        : switch (status.sdState) {
            'no_card' => s.t('未插卡', 'No card'),
            'mount_fail' => s.t('挂载失败', 'Mount failed'),
            _ => s.t('不可用', 'Unavailable'),
          };
    return Column(
      children: [
        _row(
          'microSD',
          state,
          valueColor: status.sdMounted
              ? Colors.greenAccent
              : Colors.orangeAccent,
        ),
        if (status.sdMounted) ...[
          _row(s.t('总容量', 'Total'), total == null ? '—' : _size(total)),
          _row(s.t('已用空间', 'Used'), used == null ? '—' : _size(used)),
          _row(s.t('可用空间', 'Free'), free == null ? '—' : _size(free)),
          if (total != null && total > 0 && used != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (used / total).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (child is DriveTrackEntryCard)
          child
        else
          DriveTrackCard(child: child),
      ],
    ),
  );

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LapSheet extends StatelessWidget {
  const _LapSheet({required this.session});

  final HardwareLapSession session;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final best = session.laps
        .map((l) => l.timeMs)
        .reduce((a, b) => a < b ? a : b);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('设备圈速', 'Device laps'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.t(
                '共 ${session.laps.length} 圈 · 最快 ${_fmt(best)}',
                '${session.laps.length} laps · best ${_fmt(best)}',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: session.laps.length,
                itemBuilder: (_, i) {
                  final lap = session.laps[i];
                  final isBest = lap.timeMs == best;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          'L${lap.index}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _fmt(lap.timeMs),
                          style: TextStyle(
                            color: isBest ? Colors.greenAccent : Colors.white,
                            fontSize: 14,
                            fontWeight: isBest
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop('import'),
                child: Text(s.t('导入到本机', 'Import to this device')),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.t(
                '导入只保存圈序与用时，不会伪造轨迹或成绩。',
                'Only lap order and times are stored; no fake track or score.',
              ),
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(int ms) {
    final total = ms;
    final minutes = total ~/ 60000;
    final seconds = (total % 60000) ~/ 1000;
    final millis = total % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }
}

/// 一次导入的圈速集合（设备端只提供圈序与用时）。
class HardwareLapSession {
  const HardwareLapSession({
    required this.importedAtMs,
    required this.model,
    required this.laps,
  });

  final int importedAtMs;
  final String model;
  final List<DeviceLap> laps;

  Map<String, dynamic> toJson() => {
    'importedAt': importedAtMs,
    'model': model,
    'laps': laps.map((l) => {'i': l.index, 'timeMs': l.timeMs}).toList(),
  };

  static HardwareLapSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final raw = value['laps'];
    if (raw is! List) return null;
    final laps = <DeviceLap>[];
    for (var i = 0; i < raw.length; i++) {
      final lap = DeviceLap.fromJson(raw[i], fallbackIndex: i + 1);
      if (lap != null) laps.add(lap);
    }
    if (laps.isEmpty) return null;
    return HardwareLapSession(
      importedAtMs: int.tryParse('${value['importedAt'] ?? ''}') ?? 0,
      model: (value['model'] ?? '').toString(),
      laps: laps,
    );
  }
}

enum HardwareLapImportResult { saved, duplicate, failed }

/// 硬件圈速的本机存档：filesDir/hardware_laps.json，最多保留 20 组。
/// 同一组圈速（圈数与每圈毫秒完全一致）不重复写入。
class HardwareLapStore {
  static const String fileName = 'hardware_laps.json';
  static const int maxSessions = 20;

  static Future<File> _file() async {
    final dir = await Native.getFilesDir();
    return File('$dir/$fileName');
  }

  static Future<List<HardwareLapSession>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .map(HardwareLapSession.fromJson)
          .whereType<HardwareLapSession>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<HardwareLapImportResult> append(
    HardwareLapSession session,
  ) async {
    try {
      final existing = await load();
      final signature = session.laps
          .map((l) => '${l.index}:${l.timeMs}')
          .join(',');
      for (final old in existing) {
        final oldSignature = old.laps
            .map((l) => '${l.index}:${l.timeMs}')
            .join(',');
        if (oldSignature == signature) return HardwareLapImportResult.duplicate;
      }
      final next = [session, ...existing];
      if (next.length > maxSessions) next.removeRange(maxSessions, next.length);
      final file = await _file();
      await file.writeAsString(
        jsonEncode(next.map((e) => e.toJson()).toList()),
      );
      return HardwareLapImportResult.saved;
    } catch (_) {
      return HardwareLapImportResult.failed;
    }
  }
}
