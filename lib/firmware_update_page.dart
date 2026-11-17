import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_notice.dart';
import 'firmware_update_service.dart';
import 'native.dart';

/// 自研硬件固件在线升级页。
///
/// 流程：手机连设备热点 → 读取设备当前固件 → 比对版本清单 →
/// 下载并校验 → 通过 WiFi 直传设备 → 设备写入备用分区后重启。
///
/// 页面不伪造状态：没连上设备就明确提示先连热点，检测失败给出原因。
class FirmwareUpdatePage extends StatefulWidget {
  const FirmwareUpdatePage({super.key, this.service});

  /// 便于测试注入；默认按设备热点地址创建。
  final FirmwareUpdateService? service;

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

enum _Stage { idle, probing, ready, downloading, uploading, done, error }

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage> {
  late final FirmwareUpdateService _service =
      widget.service ?? FirmwareUpdateService();

  _Stage _stage = _Stage.idle;
  FirmwareDeviceInfo? _device;
  FirmwareRelease? _target;
  FirmwareProgress? _progress;
  String _message = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  S get _s => S.of(context);

  @override
  void dispose() {
    if (widget.service == null) {
      _service.close();
    }
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = _Stage.probing;
      _progress = null;
      _message = _s.t('正在检测设备…', 'Probing device…');
    });
    final device = await _service.probeDevice();
    FirmwareManifest? manifest;
    String message = '';
    if (device == null) {
      message = _s.t(
        '未发现设备。请先在系统 WiFi 设置里连接设备热点（名称以 DriveTrack 开头），再回来检测。',
        'Device not found. Join the device hotspot (SSID starts with DriveTrack) first.',
      );
    } else {
      try {
        manifest = await _service.fetchManifest();
      } catch (e) {
        message = e is FormatException
            ? _s.t('清单里暂无可升级固件', 'No firmware published yet')
            : e.toString();
      }
    }
    if (!mounted) return;
    FirmwareRelease? target;
    var stage = _Stage.ready;
    if (device == null) {
      stage = _Stage.error;
    } else if (manifest != null) {
      target = manifest.latestFor(device.model);
      if (target != null && target.build <= device.build) {
        message = _s.t('已是最新固件', 'Firmware is up to date');
      } else if (target == null) {
        message = _s.t('清单里没有匹配该型号的固件', 'No firmware for this model');
      }
    }
    setState(() {
      _busy = false;
      _device = device;
      _target = target;
      _stage = stage;
      _message = message;
    });
  }

  bool get _canUpgrade {
    final device = _device;
    final target = _target;
    return !_busy &&
        device != null &&
        target != null &&
        target.build > device.build;
  }

  Future<void> _upgrade() async {
    final target = _target;
    if (target == null || _busy) return;
    setState(() {
      _busy = true;
      _stage = _Stage.downloading;
      _progress = null;
      _message = _s.t('正在下载固件…', 'Downloading firmware…');
    });
    try {
      final cache = await Native.getCacheDir();
      final directory = Directory('$cache/firmware');
      final file = await _service.download(
        target,
        directory: directory,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _stage = _Stage.uploading;
        _progress = null;
        _message = _s.t('正在写入设备，请勿断电…', 'Writing to device, keep power on…');
      });
      await _service.upload(
        file,
        sha256: target.sha256,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _message = _s.t('设备正在重启并校验新固件…', 'Device is rebooting…');
        _progress = null;
      });
      final info = await _service.waitForFirmware(target.version);
      if (!mounted) return;
      if (info == null) {
        setState(() {
          _busy = false;
          _stage = _Stage.error;
          _message = _s.t(
            '设备未在预期时间内以新版本上线，请重新连接热点后检测。',
            'Device did not come back with the new firmware.',
          );
        });
        return;
      }
      setState(() {
        _busy = false;
        _stage = _Stage.done;
        _device = info;
        _target = null;
        _progress = null;
        _message = _s.t('升级完成', 'Update complete');
      });
      showAppNotice(context, _s.t('固件已更新', 'Firmware updated'),
          AppNoticeKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _Stage.error;
        _progress = null;
        _message = e.toString();
      });
      showAppNotice(context, _s.t('升级失败', 'Update failed'),
          AppNoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final device = _device;
    final target = _target;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_s.t('设备固件升级', 'Firmware update')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _s.t('无线升级（WiFi）', 'Wireless update (WiFi)'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _s.t(
                    '1. 在系统 WiFi 设置里连接设备热点（${FirmwareUpdateService.accessPointPrefix}-XXXX，密码 ${FirmwareUpdateService.accessPointPassword}）\n'
                        '2. 回到本页点“检测设备”\n'
                        '3. 有新版本时点“下载并升级”，过程中保持设备供电',
                    '1. Join the device hotspot (${FirmwareUpdateService.accessPointPrefix}-XXXX, password ${FirmwareUpdateService.accessPointPassword})\n'
                        '2. Tap Check device\n'
                        '3. Tap Download and update, keep the device powered',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  _s.t('设备型号', 'Model'),
                  device?.model.isNotEmpty == true
                      ? device!.model
                      : _s.t('未连接', 'Not connected'),
                ),
                const SizedBox(height: 8),
                _infoRow(
                  _s.t('当前固件', 'Current firmware'),
                  device == null
                      ? '—'
                      : '${device.version}${device.build > 0 ? ' (${device.build})' : ''}',
                ),
                const SizedBox(height: 8),
                _infoRow(
                  _s.t('最新固件', 'Latest firmware'),
                  target == null
                      ? '—'
                      : '${target.version}${target.build > 0 ? ' (${target.build})' : ''}',
                ),
                if (target != null && target.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoRow(_s.t('更新说明', 'Notes'), target.notes),
                ],
              ],
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _message,
              style: TextStyle(
                color: _stage == _Stage.error
                    ? Colors.orangeAccent
                    : Colors.white70,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progress!.fraction,
              backgroundColor: Colors.white12,
              color: accent,
            ),
            const SizedBox(height: 6),
            Text(
              '${(_progress!.fraction * 100).toStringAsFixed(0)}%'
              '  ${(_progress!.received / 1024).toStringAsFixed(0)}'
              ' / ${(_progress!.total / 1024).toStringAsFixed(0)} KB',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _check,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_s.t('检测设备', 'Check device')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _canUpgrade ? _upgrade : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(_stage == _Stage.done
                      ? _s.t('已是最新', 'Up to date')
                      : _s.t('下载并升级', 'Download & update')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _s.t(
              '升级通过设备热点直传，固件写入备用分区并由设备自行校验；'
                  '写入期间断电可能导致设备停留在旧版本，重新上电后重试即可。',
              'Firmware is transferred over the device hotspot and written to the standby '
                  'partition with on-device verification. Power loss during writing leaves the '
                  'old firmware intact; retry after restarting the device.',
            ),
            style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );

  Widget _infoRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      );
}
