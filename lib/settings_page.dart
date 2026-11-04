import 'package:flutter/material.dart';
import 'app_notice.dart';
import 'package:flutter/services.dart';

import 'import_style.dart';
import 'native.dart';

/// 独立设置页（v0.1.3 新建文件，不改旧文件）。
///
/// 路由跳转用，不是弹窗。总协调接线方式见文件末尾注释与回执里的接线片段。
/// 本页不引用 main.dart 里的任何类（不 import main.dart），不自己存任何
/// 偏好：主题、震动开关、App 内停用开关全部走构造函数回调，由总协调
/// 写入已有存储（如 AppPrefs / profile.json）；本页只负责展示与触发。
///
/// 权限状态说明（必须如实传达给用户）：
/// - “补齐授权”调 Native.requestStep 对应分步，走系统权限框。
/// - “取消授权”不等同于吊销：Android 不允许 App 自行吊销自己的权限，
///   所以该按钮只做 Native.openAppSettings()（打开系统设置页，让用户
///   在系统里关闭），同时本行下方提供 App 内停用开关（关掉后 App
///   自己不再调用该能力）。两件事缺一不可，本页绝不谎称点一下就吊销了。
/// - “永久拒绝”只在本次会话内刚走过对应分步、复查仍拒绝、且该权限名
///   出现在 Native.checkPermissions() 的 permanentlyDenied 列表里时才
///   认定（与 permission_gate.dart 同一条约定：从未申请过的权限
///   rationale 同样为 false，不能直接当永久拒绝）。

enum PermissionDisplayStatus {
  granted,
  notGranted,
  permanentlyDenied,
  unknown,
}

class SettingsPage extends StatefulWidget {
  /// 主题预设，类型与 main.dart 里 AppPrefs.presets 完全一致
  /// （List<(String, Color)> 位置 record），总协调直接传 AppPrefs.presets
  /// 即可，无需转换。
  final List<(String, Color)> themePresets;

  /// 当前主题色（用于标出已选预设与显示当前 #RRGGBB）。
  final Color currentThemeColor;

  /// 主题变更回调。总协调在此调已有存储（如 appPrefs.setTheme），
  /// 本页不写 profile.json、不另起主题存储。
  final ValueChanged<Color> onThemeSelected;

  /// 倒计时震动提醒开关当前值（总协调持有并持久化；AppPrefs 目前
  /// 没有这个键，总协调需新增存储，见回执）。
  final bool countdownVibrationEnabled;

  /// 倒计时震动开关变更回调。
  final ValueChanged<bool> onCountdownVibrationChanged;

  /// 以下 5 组 App 内停用开关全部可选：传了 value + 回调才渲染开关，
  /// 未传时该行只显示说明文字（不谎称已停用），总协调按需补接线。
  /// - locationRecording：App 内停用定位记录（关掉后即使系统权限
  ///   还在，App 也不再用定位记录轨迹）。
  final bool? locationRecordingEnabled;
  final ValueChanged<bool>? onLocationRecordingChanged;

  /// - backgroundLocation：App 内停用后台定位使用。
  final bool? backgroundLocationEnabled;
  final ValueChanged<bool>? onBackgroundLocationChanged;

  /// - notifications：App 内停用通知。
  final bool? notificationsEnabled;
  final ValueChanged<bool>? onNotificationsChanged;

  /// - bluetooth：App 内停用蓝牙连接。
  final bool? bluetoothEnabled;
  final ValueChanged<bool>? onBluetoothChanged;

  /// - videoRecording：App 内停用视频录制。相机与麦克风目前只随
  ///   同步视频使用，因此相机行与麦克风行共用这一个开关。
  final bool? videoRecordingEnabled;
  final ValueChanged<bool>? onVideoRecordingChanged;

  /// v0.1.3 统合补：旧设置弹窗里的其余行（可选，传了才显示）。
  final VoidCallback? onImportFont;
  final VoidCallback? onClearFont;
  final VoidCallback? onImportAvatar;
  final bool? trimPrivacy;
  final ValueChanged<bool>? onTrimPrivacyChanged;
  final double? riderKg;
  final ValueChanged<double>? onRiderKgChanged;
  final bool? autoReconnect;
  final ValueChanged<bool>? onAutoReconnectChanged;

  /// 设备入口（总协调传已有 _showSensors 或传感器页跳转）。
  final VoidCallback onOpenDevices;


  /// 关于里显示的版本号，总协调传入当前版本（默认 0.1.3）。
  final String version;

  const SettingsPage({
    super.key,
    this.onImportFont,
    this.onClearFont,
    this.onImportAvatar,
    this.trimPrivacy,
    this.onTrimPrivacyChanged,
    this.riderKg,
    this.onRiderKgChanged,
    this.autoReconnect,
    this.onAutoReconnectChanged,
    required this.themePresets,
    required this.currentThemeColor,
    required this.onThemeSelected,
    required this.countdownVibrationEnabled,
    required this.onCountdownVibrationChanged,
    this.locationRecordingEnabled,
    this.onLocationRecordingChanged,
    this.backgroundLocationEnabled,
    this.onBackgroundLocationChanged,
    this.notificationsEnabled,
    this.onNotificationsChanged,
    this.bluetoothEnabled,
    this.onBluetoothChanged,
    this.videoRecordingEnabled,
    this.onVideoRecordingChanged,
    required this.onOpenDevices,
    this.version = '0.1.3',
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// 单行权限的静态描述（不含状态，状态每次从 Native 现查）。
class _PermSpec {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// 对应 Native.requestStep 的分步名。麦克风没有独立分步，见下方 TODO，
  /// 此处填 'camera'（复用相机步一并申请 RECORD_AUDIO）。
  final String step;

  /// checkPermissions() 返回 map 里对应的状态键；麦克风为 null
  /// （原生不返回 'microphone' 键，见 TODO）。
  final String? statusKey;

  /// 该行对应的 Android 权限名（用于 permanentlyDenied 判定）。
  final List<String> androidPerms;

  /// App 内停用开关的文案；null 表示该行无对应开关概念。
  final String? inAppLabel;

  /// 开关当前值与回调（总协调传入；任一为空时不渲染开关，只显示说明）。
  final bool? inAppValue;
  final ValueChanged<bool>? onInAppChanged;

  /// 开关未接线时显示的说明。
  final String? inAppUnwiredNote;

  const _PermSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.step,
    required this.statusKey,
    required this.androidPerms,
    this.inAppLabel,
    this.inAppValue,
    this.onInAppChanged,
    this.inAppUnwiredNote,
  });
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> _status = {};
  bool _loading = true;
  String? _error;

  /// 本次会话内已经走过系统框的分步名。permanentlyDenied 列表只有
  /// 在对应步刚走过、复查仍拒绝时才采信（见文件头约定）。
  final Set<String> _requestedSteps = {};

  /// 正在拉系统框的分步名（防重复点击）。
  String? _busyStep;
  bool _refreshing = false;

  late final TextEditingController _hexCtrl = TextEditingController(
    text: '#${widget.currentThemeColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页重回前台时自动重新 check，不依赖用户再点什么。
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final s = await Native.checkPermissions();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '权限状态读取失败：$e';
      });
    } finally {
      _refreshing = false;
    }
  }

  List<String> _permanentlyDeniedList() {
    final raw = _status['permanentlyDenied'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  PermissionDisplayStatus _statusFor(_PermSpec spec) {
    // TODO(总协调/原生)：麦克风没有独立状态键，见 _micSpec 下方的 TODO。
    // 只有当原生补了 "microphone" 键之后，这里才能直接读键判定已授予。
    if (spec.statusKey == null) {
      final denied = _permanentlyDeniedList();
      final justRequested = _requestedSteps.contains(spec.step);
      final inDeniedList =
          spec.androidPerms.any((p) => denied.contains(p));
      if (justRequested && inDeniedList) {
        return PermissionDisplayStatus.permanentlyDenied;
      }
      return PermissionDisplayStatus.unknown;
    }
    if (_status[spec.statusKey] == true) {
      return PermissionDisplayStatus.granted;
    }
    final denied = _permanentlyDeniedList();
    final justRequested = _requestedSteps.contains(spec.step);
    final inDeniedList = spec.androidPerms.any((p) => denied.contains(p));
    if (justRequested && inDeniedList) {
      return PermissionDisplayStatus.permanentlyDenied;
    }
    return PermissionDisplayStatus.notGranted;
  }

  Future<void> _requestStep(_PermSpec spec) async {
    if (_busyStep != null) return;
    setState(() => _busyStep = spec.step);
    try {
      // requestStep 成功时返回的就是 checkPermissions 快照 + step/requested，
      // 直接拿来刷新本页状态，不再多一次 check。
      final result = await Native.requestStep(spec.step);
      if (!mounted) return;
      setState(() {
        _status = result;
        _requestedSteps.add(spec.step);
        _loading = false;
        _error = null;
      });
      // 后台定位步的特殊情况：前台定位未授予时原生不拉框，
      // 只返回 reason=foreground_not_granted，必须明说，不能静默。
      if (spec.step == 'background' &&
          result['reason'] == 'foreground_not_granted') {
        if (mounted) {
          showAppNotice(context, '请先补齐精确定位，再申请后台定位', AppNoticeKind.warning);
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        showAppNotice(context, '申请失败：${e.message ?? e.code}', AppNoticeKind.error);
      }
    } catch (e) {
      if (mounted) {
        showAppNotice(context, '申请失败：$e', AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await Native.openAppSettings();
    } catch (e) {
      if (mounted) {
        showAppNotice(context, '无法打开系统设置：$e', AppNoticeKind.error);
      }
    }
  }

  List<_PermSpec> _specs() {
    // 通知与蓝牙同属 extras 一步：点任一行的“补齐授权”都会一并拉
    // 通知 + 蓝牙的系统框，这是原生 requestStep('extras') 的已有行为，
    // 不是本页自己打包（v0.1.0 打包 bug 的教训：只有前台+后台同批
    // 才会被系统静默丢弃，extras 内两项同批是原生既定实现）。
    return [
      _PermSpec(
        id: 'location',
        title: '精确定位',
        subtitle: '记录轨迹与车速必需。系统里关闭后 App 将无法记录轨迹。',
        icon: Icons.my_location,
        step: 'foreground',
        statusKey: 'location',
        androidPerms: const [
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        ],
        inAppLabel: 'App 内停用定位记录',
        inAppValue: widget.locationRecordingEnabled,
        onInAppChanged: widget.onLocationRecordingChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onLocationRecordingChanged 后显示。',
      ),
      _PermSpec(
        id: 'background',
        title: '后台定位',
        subtitle: '切后台后继续记录。申请前须先授予精确定位，否则系统不拉框。',
        icon: Icons.location_on,
        step: 'background',
        statusKey: 'background',
        androidPerms: const ['android.permission.ACCESS_BACKGROUND_LOCATION'],
        inAppLabel: 'App 内停用后台定位使用',
        inAppValue: widget.backgroundLocationEnabled,
        onInAppChanged: widget.onBackgroundLocationChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onBackgroundLocationChanged 后显示。',
      ),
      _PermSpec(
        id: 'notifications',
        title: '通知',
        subtitle: '后台记录时显示常驻通知。与蓝牙同属 extras 一步，一并申请。',
        icon: Icons.notifications,
        step: 'extras',
        statusKey: 'notifications',
        androidPerms: const ['android.permission.POST_NOTIFICATIONS'],
        inAppLabel: 'App 内停用通知',
        inAppValue: widget.notificationsEnabled,
        onInAppChanged: widget.onNotificationsChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onNotificationsChanged 后显示。',
      ),
      _PermSpec(
        id: 'bluetooth',
        title: '蓝牙扫描 / 连接',
        subtitle: '连接骑行功率计、踏频、心率带。与通知同属 extras 一步，一并申请。',
        icon: Icons.bluetooth,
        step: 'extras',
        statusKey: 'bluetooth',
        androidPerms: const [
          'android.permission.BLUETOOTH_SCAN',
          'android.permission.BLUETOOTH_CONNECT',
        ],
        inAppLabel: 'App 内停用蓝牙连接',
        inAppValue: widget.bluetoothEnabled,
        onInAppChanged: widget.onBluetoothChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onBluetoothChanged 后显示。',
      ),
      _PermSpec(
        id: 'camera',
        title: '相机',
        subtitle: '仅随同步视频使用（后置摄像头无预览录像），不用于拍照。',
        icon: Icons.videocam,
        step: 'camera',
        statusKey: 'camera',
        androidPerms: const ['android.permission.CAMERA'],
        inAppLabel: 'App 内停用视频录制',
        inAppValue: widget.videoRecordingEnabled,
        onInAppChanged: widget.onVideoRecordingChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onVideoRecordingChanged 后显示。',
      ),
      // v0.1.3 统合：原生已补 microphone 键与独立分步（requestCode 1005），
      // 本行直接用独立状态与独立拉框，不再复用相机步。
      _PermSpec(
        id: 'microphone',
        title: '麦克风',
        subtitle: '仅随同步视频使用；当前视频实现不设音频源，麦克风被拒仍可录无声视频。',
        icon: Icons.mic,
        step: 'microphone',
        statusKey: 'microphone',
        androidPerms: const ['android.permission.RECORD_AUDIO'],
        inAppLabel: 'App 内停用视频录制（麦克风随视频开关停用）',
        inAppValue: widget.videoRecordingEnabled,
        onInAppChanged: widget.onVideoRecordingChanged,
        inAppUnwiredNote: 'App 内停用开关未接线：总协调传入 onVideoRecordingChanged 后显示。',
      ),
    ];
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _statusChip(PermissionDisplayStatus s) {
    final (label, color) = switch (s) {
      PermissionDisplayStatus.granted => ('已授予', Colors.green),
      PermissionDisplayStatus.notGranted => ('未授予', Colors.orange),
      PermissionDisplayStatus.permanentlyDenied => ('永久拒绝', Colors.red),
      PermissionDisplayStatus.unknown => ('状态未知', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _permTile(_PermSpec spec) {
    final status = _statusFor(spec);
    final busy = _busyStep == spec.step;
    final showInAppSwitch =
        spec.inAppLabel != null && spec.inAppValue != null && spec.onInAppChanged != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(
          children: [
            ListTile(
              leading: Icon(spec.icon),
              title: Text(spec.title),
              subtitle: Text(spec.subtitle),
              trailing: _statusChip(status),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (status == PermissionDisplayStatus.granted) ...[
                    // “取消授权”不是吊销：只打开系统设置页，同时下方
                    // App 内停用开关才是 App 自己能做的停用。两者并列，
                    // 文案上绝不写成“点此即吊销”。
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openSystemSettings,
                        child: const Text('取消授权（去系统设置）'),
                      ),
                    ),
                  ] else if (status == PermissionDisplayStatus.permanentlyDenied) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openSystemSettings,
                        child: const Text('去系统设置开启'),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => _requestStep(spec),
                        child: Text(busy
                            ? '等待系统框…'
                            : spec.id == 'microphone'
                                ? '补齐授权（随相机一步申请）'
                                : '补齐授权'),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('刷新'),
                  ),
                ],
              ),
            ),
            if (status == PermissionDisplayStatus.unknown)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '原生未单独上报该权限的授予状态：只有在本次会话内刚申请过、'
                  '复查仍被系统标记为永久拒绝时，本行才会显示“永久拒绝”。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            if (status == PermissionDisplayStatus.permanentlyDenied)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '系统已标记为永久拒绝，App 内无法再拉框，请去系统设置里手动开启。',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            if (showInAppSwitch)
              SwitchListTile(
                value: spec.inAppValue!,
                title: Text(spec.inAppLabel!),
                subtitle: const Text('只停用 App 自己的调用，不等于系统权限吊销'),
                onChanged: spec.onInAppChanged,
              )
            else if (spec.inAppLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  spec.inAppUnwiredNote ?? 'App 内停用开关未接线。',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _applyHexTheme() {
    final raw = _hexCtrl.text.trim().replaceFirst('#', '');
    final v = raw.length == 6 ? int.tryParse(raw, radix: 16) : null;
    if (v == null) {
      if (mounted) showAppNotice(context, '请输入 #RRGGBB 格式，如 #E10600', AppNoticeKind.warning);
      return;
    }
    widget.onThemeSelected(Color(0xFF000000 | v));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionTitle('权限检查'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '回到本页时自动刷新。App 无法自行吊销权限：“取消授权”只打开系统'
              '设置页，请在系统里关闭；同时可用每行下方的 App 内开关停用对应功能。'
              '低版本 Android 上系统无对应权限概念时，原生恒返回已授予。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              ),
            )
          else
            for (final spec in _specs()) _permTile(spec),
          _sectionTitle('主题'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final p in widget.themePresets)
                        GestureDetector(
                          onTap: () => widget.onThemeSelected(p.$2),
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: p.$2,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: widget.currentThemeColor == p.$2
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(p.$1, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hexCtrl,
                          decoration: const InputDecoration(
                            labelText: '自定义颜色（#RRGGBB）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _applyHexTheme,
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前：#${widget.currentThemeColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
                    '（主题色全 App 生效；G 值绿黄红为语义色，不随主题变）',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          _sectionTitle('倒计时提醒'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SwitchListTile(
              value: widget.countdownVibrationEnabled,
              title: const Text('倒计时震动提醒'),
              subtitle: const Text('3-2-1 每秒短震动，GO 时长震动；关掉后倒计时不震动'),
              onChanged: widget.onCountdownVibrationChanged,
            ),
          ),
          _sectionTitle('设备'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('骑行传感器连接'),
              subtitle: const Text('BLE 传感器扫描、连接与功率计归零'),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onOpenDevices,
            ),
          ),
          _sectionTitle('更多'),
          // v1.0.2：字体导入行只换 UI 为统一导入画风（ImportCard /
          // ImportFileRow，蓝色主按钮）；onImportFont / onClearFont
          // 回调（main.dart 里的 pickFile('font') + FontLoader 逻辑）未动。
          // 本页不知道当前字体文件名，只凭 onClearFont 是否传入判断
          // 有无已导入字体：传入即已导入，未传入即未导入。
          if (widget.onImportFont != null || widget.onClearFont != null)
            ImportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('导入自带字体',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('导入自己合法取得的 .ttf/.otf，导入后全 App 改用该字体',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 12),
                  ImportFileRow(
                    fileName: widget.onClearFont != null ? '已导入自定义字体' : null,
                    placeholder: '未导入自定义字体',
                    pickLabel: '选择字体文件',
                    onPick: widget.onImportFont,
                    onClear: widget.onClearFont,
                  ),
                  const SizedBox(height: 4),
                  const Text('清除后恢复内置字体。',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                if (widget.trimPrivacy != null && widget.onTrimPrivacyChanged != null)
                  SwitchListTile(
                    value: widget.trimPrivacy!,
                    title: const Text('分享默认截掉首尾 300-500 米'),
                    subtitle: const Text('不显示具体家庭地址；关掉才分享完整轨迹'),
                    onChanged: widget.onTrimPrivacyChanged,
                  ),
                if (widget.autoReconnect != null && widget.onAutoReconnectChanged != null)
                  SwitchListTile(
                    value: widget.autoReconnect!,
                    title: const Text('传感器掉线自动重连'),
                    onChanged: widget.onAutoReconnectChanged,
                  ),
                if (widget.riderKg != null)
                  ListTile(
                    title: const Text('人车总重量（估算功率用）'),
                    subtitle: Text('${widget.riderKg!.toStringAsFixed(0)} kg'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: widget.onRiderKgChanged == null
                              ? null
                              : () => widget.onRiderKgChanged!((widget.riderKg! - 5).clamp(40, 200))),
                      IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: widget.onRiderKgChanged == null
                              ? null
                              : () => widget.onRiderKgChanged!((widget.riderKg! + 5).clamp(40, 200))),
                    ]),
                  ),
              ],
            ),
          ),
          // v1.0.3：旧长页 SettingsPage 自 v0.1.4 起已不再从主界面进入，
          // 其“关于”信息区一并删除，避免设置侧残留第二处关于；
          // 关于唯一入口在左拉菜单（见 main.dart _buildMenuPanel）。
        ],
      ),
    );
  }
}

// ---------- 总协调接线提示（不执行，仅供参考） ----------
// Navigator.push(context, MaterialPageRoute(
//   builder: (_) => SettingsPage(
//     themePresets: AppPrefs.presets, // 类型与本页参数完全一致，直接传
//     currentThemeColor: appPrefs.themeColor,
//     onThemeSelected: (c) => appPrefs.setTheme(c),
//     countdownVibrationEnabled: <总协调新增的状态值>,
//     onCountdownVibrationChanged: (v) { <总协调新增的持久化> },
//     // 以下 5 组可选：传了才渲染开关；其中 videoRecordingEnabled
//     // 对应首页已有的 videoEnabled 状态，backgroundLocationEnabled /
//     // bluetoothEnabled / locationRecordingEnabled / notificationsEnabled
//     // 若无现有状态，总协调需新增（或先不传，只保留系统设置入口）。
//     videoRecordingEnabled: videoEnabled,
//     onVideoRecordingChanged: (v) => setState(() => videoEnabled = v),
//     onOpenDevices: _showSensors,
//   ),
// ));
// 注意：旧 _showSettings 弹窗里的字体导入/头像、分享截断、自动重连、
// 人车总重量几行本页没有收纳；删旧弹窗前总协调须决定这些行的去留
// （移入本页后续分区，或另保留入口），否则删弹窗即丢功能。
