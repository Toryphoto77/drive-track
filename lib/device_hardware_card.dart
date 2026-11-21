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
  bool _backhauling = false;
  String? _backhaulText;
  int? _rssi;
  FirmwareDeviceInfo? _info;
  DeviceRuntimeStatus? _status;
  bool _hotspotJoining = false;
  String? _hotspotNote;
  bool _hotspotOk = false;
  // 自动重试：设备刚开机时热点往往还没起来，只试一次必然失败。
  // 失败后按 5s / 15s / 30s 退避重试，最多 4 次自动请求；
  // 等待系统确认框超时不重复弹框，交给用户手动点。
  int _hotspotAutoAttempts = 0;
  Timer? _hotspotRetryTimer;
  bool _hotspotSyncing = false;
  // 成功序号：轮询查询与“刚连上”可能并发，序号变化说明查询结果已过期，
  // 不能拿旧的“未连接”把刚成功的状态又改回去。
  int _hotspotSuccessSeq = 0;
  // 热点连上后只自动拉一次蓝牙，避免失败时反复重连。
  bool _bleAutoConnectTried = false;
  bool _autoBackhaulTried = false;
  int? _settingGnssRateHz;

  static const int _hotspotMaxAutoAttempts = 4;
  static const List<Duration> _hotspotRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  bool get _ownHardware => isDriveTrackHardwareName(widget.deviceName);
  S get _s => S.of(context);

  /// 把设备 SD 上的整场记录逐个回传到 App 私有目录。
  /// 已存在同名文件时覆盖；任一场失败即停止并显示原因，
  /// 不把部分成功说成全部成功。
  Future<void> _backhaulAll() async {
    if (_backhauling) return;
    final s = _s;
    setState(() {
      _backhauling = true;
      _backhaulText = null;
    });
    try {
      final files = await _service.listRecordings();
      if (files.isEmpty) {
        if (mounted) {
          setState(() => _backhaulText =
              s.t('设备上没有可回传的记录。', 'No recordings on device.'));
        }
        return;
      }
      final directory =
          Directory('${await Native.getFilesDir()}/backhaul');
      var done = 0;
      for (final file in files) {
        final target = File('${directory.path}/${file.name}');
        // 已回传且大小一致的文件直接跳过，回到 pits 重复打开不会重复拉取。
        try {
          if (await target.exists() && await target.length() == file.size) {
            done++;
            continue;
          }
        } catch (_) {}
        await _service.downloadRecording(file.name, directory: directory);
        done++;
        if (mounted) {
          setState(() => _backhaulText = s.t(
              '已同步 $done / ${files.length}',
              'Synced $done / ${files.length}'));
        }
      }
      if (mounted) {
        setState(() => _backhaulText = s.t(
            '已同步 $done 个文件到 ${directory.path}',
            'Synced $done file(s) to ${directory.path}'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _backhaulText =
            s.t('回传失败：$e', 'Backhaul failed: $e'));
      }
    } finally {
      if (mounted) setState(() => _backhauling = false);
    }
  }

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
    // 进入设备中心就尝试连设备热点，省去用户去系统 Wi-Fi 里翻找。
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoJoinHotspot());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hotspotRetryTimer?.cancel();
    _dataSub?.cancel();
    if (widget.service == null) _service.close();
    // 解除热点绑定，离开设备中心后恢复手机默认上网网络（更新检查等）。
    unawaited(Native.disconnectDeviceHotspot());
    super.dispose();
  }

  /// 自动连接设备热点。manual=true 表示用户主动点“重新连接”，
  /// 会清空重试计数并立即再请求一次。
  Future<void> _autoJoinHotspot({bool manual = false}) async {
    if (!_ownHardware || _hotspotJoining) return;
    if (manual) {
      _hotspotAutoAttempts = 0;
      _hotspotRetryTimer?.cancel();
      _hotspotRetryTimer = null;
      if (mounted) setState(() => _hotspotNote = null);
    } else if (_hotspotAutoAttempts >= _hotspotMaxAutoAttempts) {
      if (mounted && _hotspotNote == null) {
        setState(() => _hotspotNote = '自动连接未成功，可点下方按钮重试');
      }
      return;
    }
    // 用户可能已在系统 Wi-Fi 里手动连上设备热点，先按当前 SSID 直接判定。
    try {
      final ssid = await Native.getConnectedWifiSsid();
      if (ssid != null &&
          ssid.startsWith(FirmwareUpdateService.accessPointPrefix)) {
        _markHotspotConnected();
        return;
      }
    } catch (_) {}
    if (!mounted || _hotspotJoining) return;
    _hotspotAutoAttempts++;
    setState(() => _hotspotJoining = true);
    Map<String, dynamic> r;
    try {
      r = await Native.connectDeviceHotspot(
        password: FirmwareUpdateService.accessPointPassword,
      );
    } catch (e) {
      r = {'ok': false, 'reason': e.toString()};
    }
    if (!mounted) return;
    final ok = r['ok'] == true;
    final reason = (r['reason'] ?? '').toString();
    if (ok) {
      _markHotspotConnected();
      return;
    }
    setState(() {
      _hotspotJoining = false;
      _hotspotOk = false;
      _hotspotNote = switch (reason) {
        'unsupported' => '系统版本较低，请在 Wi-Fi 设置里连接设备热点',
        'wifi_off' => '手机 Wi-Fi 未开启，请先打开 Wi-Fi',
        'unavailable' => '没搜到设备热点，确认设备已开机并在附近',
        'timeout' => '等待系统确认超时，可重试',
        _ => '热点未连接，可重试',
      };
    });
    // 没搜到时自动退避重试；等待用户点系统确认框超时的场景不重复弹框，
    // 原生请求仍然有效，稍后确认成功由轮询补判。
    if (reason != 'timeout' &&
        reason != 'unsupported' &&
        _hotspotAutoAttempts < _hotspotMaxAutoAttempts) {
      _scheduleHotspotRetry();
    }
  }

  void _scheduleHotspotRetry() {
    if (_hotspotRetryTimer != null || !mounted) return;
    final index =
        (_hotspotAutoAttempts - 1).clamp(0, _hotspotRetryDelays.length - 1);
    _hotspotRetryTimer = Timer(_hotspotRetryDelays[index], () {
      _hotspotRetryTimer = null;
      if (mounted && !_hotspotOk) unawaited(_autoJoinHotspot());
    });
  }

  /// 热点确认可用：更新状态、补一次设备探测，并自动拉起蓝牙。
  void _markHotspotConnected() {
    _hotspotRetryTimer?.cancel();
    _hotspotRetryTimer = null;
    _hotspotAutoAttempts = 0;
    _hotspotSuccessSeq++;
    if (mounted && (!_hotspotOk || _hotspotNote != null || _hotspotJoining)) {
      setState(() {
        _hotspotJoining = false;
        _hotspotOk = true;
        _hotspotNote = null;
      });
    }
    unawaited(_refresh());
    unawaited(_autoConnectBleAfterHotspot());
  }

  /// 热点连上后自动连接蓝牙：设备热点与 BLE 是两条链路，
  /// 用户不该再回设备中心手动点一次“连接”。
  Future<void> _autoConnectBleAfterHotspot() async {
    if (_connected || _bleAutoConnectTried) return;
    final connect = widget.onConnect;
    if (connect == null) return;
    _bleAutoConnectTried = true;
    try {
      await connect();
    } catch (_) {
      // 热点仍在时允许下一轮轮询再补一次，不做无限重连。
      _bleAutoConnectTried = false;
    }
  }

  /// 轮询原生热点状态：系统确认框晚点被点、或热点中途掉线，
  /// 都在这里同步，避免界面一直停在“尚未连接”。
  Future<void> _syncHotspotState() async {
    if (!_ownHardware || _hotspotSyncing) return;
    _hotspotSyncing = true;
    try {
      final seqAtStart = _hotspotSuccessSeq;
      final available = await Native.isDeviceHotspotConnected();
      if (!mounted) return;
      if (available && !_hotspotOk) {
        _markHotspotConnected();
      } else if (!available &&
          _hotspotOk &&
          seqAtStart == _hotspotSuccessSeq) {
        // 查询期间刚连上过（序号变了）就忽略这次过期结果。
        setState(() {
          _hotspotOk = false;
          _hotspotNote = '设备热点已断开，正在重连…';
        });
        _bleAutoConnectTried = false;
        if (!_hotspotJoining &&
            _hotspotAutoAttempts < _hotspotMaxAutoAttempts) {
          unawaited(_autoJoinHotspot());
        }
      }
    } finally {
      _hotspotSyncing = false;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      // 先对齐热点真实状态：确认框晚点被点、热点掉线都靠这里补判。
      // 不阻塞设备信息探测，两条链路互不等待。
      if (_ownHardware) unawaited(_syncHotspotState());
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
      // 回到 pits 连上热点后自动同步一次：SD 上有整场记录才触发，
      // 失败只显示原因，不阻塞设备信息轮询。
      if (info != null &&
          status != null &&
          status.sdMounted &&
          status.supportsFileBackhaul &&
          !_backhauling &&
          !_autoBackhaulTried) {
        _autoBackhaulTried = true;
        unawaited(_backhaulAll());
      }
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

  /// 自动标定状态：true=已完成，false=进行中/未完成，null=旧固件不报。
  String _calText(bool? done) => switch (done) {
    true => _s.t('已完成（自动）', 'Done (auto)'),
    false => _s.t('进行中 / 未完成', 'Pending'),
    null => '—',
  };

  Color? _calColor(bool? done) => switch (done) {
    true => Colors.greenAccent,
    false => Colors.amberAccent,
    null => null,
  };

  /// 三轴读数：任一轴缺失则整体显示“—”，不把缺失补成 0。
  String _vectorText(List<double?> values, String unit) {
    if (values.any((v) => v == null)) return '—';
    return values.map((v) => v!.toStringAsFixed(2)).join(' / ') + unit;
  }

  String _scalarText(double? value, String unit, {int digits = 1}) {
    if (value == null) return '—';
    return value.toStringAsFixed(digits) + unit;
  }

  Future<void> _setGnssRate(int hz) async {
    if (_settingGnssRateHz != null || _status?.supportsGnssRate != true) return;
    setState(() => _settingGnssRateHz = hz);
    try {
      await _service.setGnssRate(hz);
      if (!mounted) return;
      showAppNotice(
        context,
        _s.t('定位频率已设为 $hz Hz', 'GNSS rate set to $hz Hz'),
        AppNoticeKind.success,
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        showAppNotice(
          context,
          _s.t('频率设置失败：$error', 'Failed to set GNSS rate: $error'),
          AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _settingGnssRateHz = null);
    }
  }

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
                  _row(
                    s.t('IMU 状态', 'IMU status'),
                    _sensorText(_status?.imuReady),
                  ),
                  _row(
                    s.t('自动标定', 'Auto calibration'),
                    _calText(_status?.imuCalibrated),
                    valueColor: _calColor(_status?.imuCalibrated),
                  ),
                  _row(
                    s.t('加速度 X/Y/Z', 'Acceleration X/Y/Z'),
                    _vectorText([
                      _status?.imuAx,
                      _status?.imuAy,
                      _status?.imuAz,
                    ], ' g'),
                  ),
                  _row(
                    s.t('角速度 X/Y/Z', 'Angular rate X/Y/Z'),
                    _vectorText([
                      _status?.imuGx,
                      _status?.imuGy,
                      _status?.imuGz,
                    ], ' °/s'),
                  ),
                  _row(
                    s.t('姿态 横滚/俯仰', 'Attitude roll/pitch'),
                    _vectorText([
                      _status?.imuRollDeg,
                      _status?.imuPitchDeg,
                    ], '°'),
                  ),
                  _row(
                    s.t('气压计状态', 'Barometer status'),
                    _sensorText(_status?.baroReady),
                  ),
                  _row(
                    s.t('自动零点标定', 'Auto zero calibration'),
                    _calText(_status?.baroCalibrated),
                    valueColor: _calColor(_status?.baroCalibrated),
                  ),
                  _row(
                    s.t('气压计温度', 'Barometer temperature'),
                    _scalarText(_status?.baroTempC, ' °C', digits: 1),
                  ),
                  _row(
                    s.t('气压', 'Pressure'),
                    _scalarText(_status?.baroPressPa, ' Pa', digits: 0),
                  ),
                  _row(
                    s.t('气压高度', 'Barometric altitude'),
                    _scalarText(_status?.baroAltM, ' m', digits: 1),
                  ),
                  _row(
                    s.t('相对零点高差', 'Relative altitude'),
                    _scalarText(_status?.baroRelAltM, ' m', digits: 2),
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
                    s.t('定位输出频率', 'GNSS output rate'),
                    _status?.gnssRateHz == null
                        ? '—'
                        : '${_status!.gnssRateHz} Hz',
                  ),
                  if (_status?.supportsGnssRate == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final hz in const [10, 20, 25])
                            ChoiceChip(
                              label: Text('$hz Hz'),
                              selected: _status?.gnssRateHz == hz,
                              onSelected: _settingGnssRateHz == null
                                  ? (_) => _setGnssRate(hz)
                                  : null,
                            ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        s.t(
                          '当前固件不支持在线调频，请升级固件；硬件最高 25 Hz。',
                          'Online rate control needs a firmware update. Hardware supports up to 25 Hz.',
                        ),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11.5,
                        ),
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
            if (_status?.sdMounted == true)
              _section(
                s.t('记录回传', 'Recordings'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t(
                        '设备在 SD 卡上逐场完整记录，手机没电或没连蓝牙时也不中断。'
                        '连接设备热点后可把整场原始数据回传到手机。',
                        'Every session is recorded in full on the device microSD, '
                        'even without the phone. Join the hotspot to pull the '
                        'raw recordings to the phone.',
                      ),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            (_backhauling ||
                                !_reachable ||
                                _status?.supportsFileBackhaul != true)
                            ? null
                            : _backhaulAll,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          _backhauling
                              ? s.t('正在回传…', 'Receiving…')
                              : s.t('回传全部记录', 'Receive all recordings'),
                        ),
                      ),
                    ),
                    if (_status?.supportsFileBackhaul != true)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          s.t(
                            '当前固件不支持回传，请升级固件。',
                            'Current firmware has no backhaul API. Update firmware.',
                          ),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else if (_backhaulText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _backhaulText!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            _hotspotSection(),
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

  Widget _hotspotSection() {
    final s = _s;
    return _section(
      s.t('设备热点', 'Device hotspot'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            s.t('连接状态', 'Connection'),
            _hotspotJoining
                ? s.t('正在连接…', 'Connecting…')
                : (_hotspotOk
                      ? s.t('已连接（自动）', 'Connected (auto)')
                      : (_hotspotNote ??
                          s.t('尚未连接', 'Not connected'))),
            valueColor: _hotspotOk
                ? Colors.greenAccent
                : (_hotspotNote == null ? null : Colors.amberAccent),
          ),
          const SizedBox(height: 8),
          Text(
            s.t(
              '进入本页会自动连接 ${FirmwareUpdateService.accessPointPrefix}-XXXX 热点；'
              'Android 10 及以上首次会弹一次系统确认框，点“连接”即可。'
              '没搜到会自动重试，热点连上后蓝牙也会自动重连。',
              'The ${FirmwareUpdateService.accessPointPrefix}-XXXX hotspot is joined '
              'automatically (Android 10+ shows a one-time confirmation). '
              'It retries when not found, and Bluetooth reconnects once the '
              'hotspot is up.',
            ),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (!_hotspotOk) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _hotspotJoining ? null : _retryHotspot,
                icon: const Icon(Icons.wifi, size: 18),
                label: Text(s.t('重新连接设备热点', 'Reconnect hotspot')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _retryHotspot() async {
    await _autoJoinHotspot(manual: true);
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
