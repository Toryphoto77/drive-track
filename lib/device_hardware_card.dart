import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_notice.dart';
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
