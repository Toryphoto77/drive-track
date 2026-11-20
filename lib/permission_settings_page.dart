import 'package:flutter/material.dart';
import 'app_notice.dart';
import 'package:flutter/services.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'glass_button.dart';
import 'native.dart';

/// v0.1.4 权限检查子页：状态每次从原生现查；补齐走分步系统框；
/// 取消授权 = 打开系统应用详情设置页 + App 内停用开关（Android 不允许
/// App 自行吊销自己的权限，本页绝不谎称点一下就吊销了）。
class _PermRow {
  final String id, title, titleEn, subtitle, subtitleEn, step, statusKey;
  final IconData icon;
  final List<String> androidPerms;
  const _PermRow(this.id, this.title, this.titleEn, this.subtitle, this.subtitleEn, this.icon, this.step, this.statusKey, this.androidPerms);
}

const _rows = [
  _PermRow('location', '精确定位', 'Precise location', '记录轨迹与车速必需', 'Required for tracks and speed', Icons.my_location, 'foreground', 'location', ['android.permission.ACCESS_FINE_LOCATION']),
  _PermRow('background', '后台定位', 'Background location', '切后台后继续记录；须先授予精确定位', 'Keeps recording in background; requires precise location first', Icons.location_on, 'background', 'background', ['android.permission.ACCESS_BACKGROUND_LOCATION']),
  _PermRow('notifications', '通知', 'Notifications', '前台服务常驻通知', 'Ongoing foreground-service notice', Icons.notifications, 'extras', 'notifications', ['android.permission.POST_NOTIFICATIONS']),
  _PermRow('bluetooth', '蓝牙扫描/连接', 'Bluetooth scan/connect', '骑行传感器与运动相机连接', 'Sensors and action camera connections', Icons.bluetooth, 'extras', 'bluetooth', ['android.permission.BLUETOOTH_SCAN', 'android.permission.BLUETOOTH_CONNECT']),
  _PermRow('camera', '相机', 'Camera', '同步视频录制', 'Video recording', Icons.camera_alt, 'camera', 'camera', ['android.permission.CAMERA']),
  _PermRow('microphone', '麦克风', 'Microphone', '同步视频录音（无声录制可不授予）', 'Video sound (not needed for silent clips)', Icons.mic, 'microphone', 'microphone', ['android.permission.RECORD_AUDIO']),
];

class PermissionSettingsPage extends StatefulWidget {
  final bool videoRecording;
  final ValueChanged<bool> onVideoRecordingChanged;
  final bool bluetoothEnabled;
  final ValueChanged<bool> onBluetoothChanged;
  final bool voiceEnabled;
  final ValueChanged<bool> onVoiceChanged;
  const PermissionSettingsPage({
    super.key,
    required this.videoRecording,
    required this.onVideoRecordingChanged,
    required this.bluetoothEnabled,
    required this.onBluetoothChanged,
    required this.voiceEnabled,
    required this.onVoiceChanged,
  });
  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage> with WidgetsBindingObserver {
  Map<String, dynamic> _status = {};
  bool _loading = true;
  String? _error;
  String? _busyStep;
  // v0.1.8 电池优化：null=未查到（页面不得写成已获白名单）。
  bool? _batteryIgnored;
  bool _batteryBusy = false;
  final Set<String> _requested = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await Native.checkPermissions();
      if (mounted) setState(() { _status = s; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '${S.current.t('权限状态读取失败：', 'Failed to read permission status: ')}$e';
        });
      }
    }
    await _refreshBattery();
  }

  // v0.1.8：电池优化只读检测（PowerManager），从不自动申请白名单。
  Future<void> _refreshBattery() async {
    try {
      final r = await Native.checkBatteryOptimization();
      if (mounted) setState(() => _batteryIgnored = r['ignored'] as bool?);
    } catch (_) {
      if (mounted) setState(() => _batteryIgnored = null);
    }
  }

  String _label(_PermRow r, S s) {
    if (_status[r.statusKey] == true) return s.t('已授予', 'Granted');
    final denied = (_status['permanentlyDenied'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (_requested.contains(r.step) && r.androidPerms.any(denied.contains)) return s.t('永久拒绝', 'Blocked');
    return s.t('未授予', 'Not granted');
  }

  Future<void> _request(_PermRow r) async {
    if (_busyStep != null) return;
    final s = S.of(context);
    setState(() => _busyStep = r.step);
    try {
      final result = await Native.requestStep(r.step);
      if (mounted) setState(() { _status = result; _requested.add(r.step); });
      if (r.step == 'background' && result['reason'] == 'foreground_not_granted' && mounted) {
        showAppNotice(context, s.t('请先补齐精确定位，再申请后台定位', 'Grant precise location before background location'), AppNoticeKind.warning);
      }
    } on PlatformException catch (e) {
      if (mounted) showAppNotice(context, '${s.t('申请失败：', 'Request failed: ')}${e.message ?? e.code}', AppNoticeKind.error);
    } catch (e) {
      if (mounted) showAppNotice(context, '${s.t('申请失败：', 'Request failed: ')}$e', AppNoticeKind.error);
    } finally {
      if (mounted) setState(() { _busyStep = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: Text(s.t('权限检查', 'Permissions')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: withAppBarTopInset(
                  context, const EdgeInsets.only(bottom: 24)),
              children: [
              if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.orange))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                    s.t(
                      'App 不能自行吊销权限，点“去系统设置”在系统里关闭；App 内停用开关关闭后，App 不再调用该能力。',
                      'Apps cannot revoke their own permissions. Use “Open system settings” to turn them off in the system; in-app switches stop this app from using the feature.',
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              for (final r in _rows)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(r.icon, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.t(r.title, r.titleEn), style: const TextStyle(fontWeight: FontWeight.bold))),
                        Text(_label(r, s), style: TextStyle(color: _status[r.statusKey] == true ? Colors.green : Colors.orange, fontSize: 12)),
                      ]),
                      const SizedBox(height: 2),
                      Text(s.t(r.subtitle, r.subtitleEn), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: _busyStep == null ? () => _request(r) : null, child: Text(s.t('补齐授权', 'Grant')))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Native.openAppSettings(),
                            child: Text(s.t('去系统设置取消', 'Open system settings')),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              // v0.1.8 电池优化：后台续录不靠新服务（见回执复核结论），
              // 但系统电池优化仍可能杀后台；本项只检测 + 跳系统设置页
              // 让用户手动选本应用，绝不冒充已获白名单。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(s.t('电池优化', 'Battery optimization'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.battery_charging_full, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.t('电池优化', 'Battery optimization'), style: const TextStyle(fontWeight: FontWeight.bold))),
                      Text(
                        _batteryIgnored == null
                            ? s.t('未查到', 'Unknown')
                            : (_batteryIgnored!
                                ? s.t('已忽略优化', 'Optimization ignored')
                                : s.t('未忽略优化', 'Optimization on')),
                        style: TextStyle(color: _batteryIgnored == true ? Colors.green : Colors.orange, fontSize: 12),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                        s.t(
                          '还需在厂商管家 / 后台管理里允许后台运行；下方按钮只打开系统电池优化设置页，由你手动选本应用。',
                          'Also allow background running in the device manager. The button below only opens the system battery optimization page; pick this app manually.',
                        ),
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _batteryBusy ? null : () async {
                            setState(() => _batteryBusy = true);
                            final ok = await Native.openBatteryOptimizationSettings();
                            if (mounted) {
                              setState(() => _batteryBusy = false);
                              if (!ok) showAppNotice(context, s.t('打不开系统电池优化设置页，请在系统设置里手动找电池优化', 'Cannot open battery optimization settings; find it manually in system settings'), AppNoticeKind.error);
                            }
                          },
                          child: Text(s.t('去系统电池优化设置', 'Battery optimization settings')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton(onPressed: _refreshBattery, child: Text(s.t('刷新状态', 'Refresh')))),
                    ]),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(s.t('App 内停用开关', 'In-app switches'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  SwitchListTile(title: Text(s.t('同步视频录制', 'Video recording')), subtitle: Text(s.t('关闭后不再调用相机与麦克风', 'Off: no camera or microphone')), value: widget.videoRecording, onChanged: widget.onVideoRecordingChanged),
                  SwitchListTile(title: Text(s.t('蓝牙连接', 'Bluetooth')), subtitle: Text(s.t('关闭后不再扫描与连接 BLE 设备', 'Off: no BLE scanning or connections')), value: widget.bluetoothEnabled, onChanged: widget.onBluetoothChanged),
                  SwitchListTile(title: Text(s.t('语音播报', 'Voice announcements')), subtitle: Text(s.t('关闭后不再播报事件与总结', 'Off: no event or summary announcements')), value: widget.voiceEnabled, onChanged: widget.onVoiceChanged),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(s.t('定位与通知没有 App 内停用开关，请在系统设置里关闭。', 'Location and notifications have no in-app switch; turn them off in system settings.'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
            ]),
    );
  }
}
