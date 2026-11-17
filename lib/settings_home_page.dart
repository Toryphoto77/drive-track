import 'package:flutter/material.dart';

import 'account_page.dart';
import 'ai_settings_page.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'card_style.dart';
import 'cloud_service.dart';
import 'dt_page_route.dart';
import 'glass_button.dart';

/// 设置页标准分组行：图标底色块 + 标题/副标题 + 右侧 chevron / 自定义控件。
/// 抽成顶层函数，供本页分组与自包含的账号行复用，避免两套行样式。
Widget settingsGroupRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  VoidCallback? onTap,
  Widget? trailing,
}) {
  final accent = Theme.of(context).colorScheme.primary;
  final content = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white54,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          trailing
        else if (onTap != null)
          const Icon(Icons.chevron_right, size: 18, color: Colors.white24),
      ],
    ),
  );
  if (onTap == null) return content;
  return InkWell(onTap: onTap, child: content);
}

/// 账号与云端分组里的账号行（v1.7.0）：自身读取 CloudService 状态，
/// 从账号管理页返回后刷新副标题。
class AccountSettingsRow extends StatefulWidget {
  const AccountSettingsRow({super.key});

  @override
  State<AccountSettingsRow> createState() => _AccountSettingsRowState();
}

class _AccountSettingsRowState extends State<AccountSettingsRow> {
  @override
  void initState() {
    super.initState();
    CloudService.instance.initialized.then((_) {
      if (mounted) setState(() {});
    });
  }

  String _subtitle(S s) {
    final svc = CloudService.instance;
    if (!svc.isConfigured) return s.t('云端未配置', 'Cloud not configured');
    if (svc.isAnonymous) return s.t('未登录', 'Not signed in');
    final phone = svc.currentUserPhone;
    if (phone != null && phone.isNotEmpty) return phone;
    final email = svc.currentUserEmail;
    if (email != null && email.isNotEmpty) return email;
    return s.t('已登录', 'Signed in');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return settingsGroupRow(
      context,
      icon: Icons.account_circle,
      title: s.t('账号管理', 'Account'),
      subtitle: _subtitle(s),
      onTap: () async {
        await Navigator.of(context)
            .push(DtPageRoute(builder: (_) => const AccountPage()));
        if (mounted) setState(() {});
      },
    );
  }
}

/// v1.5.8 设置首页重新设计：按「驾驶 / 设备 / 外观 / 记录 / 调试」分组，
/// 每组一张圆角卡，组内行用细分隔线，不再一长串同权重入口。
///
/// - 入口行：图标底色块 + 标题/副标题 + chevron，整行可点；
/// - 开关行：同版式，右侧直接给开关，不再混用 Card + SwitchListTile；
/// - 调试分组只在本机自用版出现（回调为空时整组不渲染）。
class SettingsHomePage extends StatelessWidget {
  final VoidCallback onOpenPermission;
  final VoidCallback onOpenTheme;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenTrack;
  final VoidCallback onOpenLocation;
  // v0.1.9 传感器校准入口：可选回调，未传时不显示该入口。
  final VoidCallback? onOpenSensorCalibration;
  final VoidCallback onOpenMapImport;
  // v0.1.7 油耗费用入口：可选回调，未传时不显示该入口（不破坏旧调用方）。
  final VoidCallback? onOpenFuel;
  // v1.2.0 车辆档案入口：可选回调，未传时不显示该入口。
  final VoidCallback? onOpenVehicle;
  final bool countdownVibration;
  final ValueChanged<bool> onCountdownVibrationChanged;
  // v0.1.8：记录时保持屏幕常亮 / 记录地图 3D 透视（可选参数，
  // 旧调用方不传时默认开启，不破坏旧调用）。
  final bool keepScreenOn;
  final ValueChanged<bool>? onKeepScreenOnChanged;
  final bool recordingMap3d;
  final ValueChanged<bool>? onRecordingMap3dChanged;
  final bool videoRecording;
  final ValueChanged<bool> onVideoRecordingChanged;
  final bool trimPrivacy;
  final ValueChanged<bool> onTrimPrivacyChanged;

  /// v1.6.1：导出崩溃日志（Dart + 原生合并）。null = 不渲染该入口。
  final VoidCallback? onExportCrashLog;

  /// v1.5.8：自用调试模式开关。null = 不渲染调试分组（正式版）。
  final bool debugMode;
  final ValueChanged<bool>? onDebugModeChanged;

  const SettingsHomePage({
    super.key,
    required this.onOpenPermission,
    required this.onOpenTheme,
    required this.onOpenVoice,
    required this.onOpenTrack,
    required this.onOpenLocation,
    this.onOpenSensorCalibration,
    required this.onOpenMapImport,
    this.onOpenFuel,
    this.onOpenVehicle,
    required this.countdownVibration,
    required this.onCountdownVibrationChanged,
    this.keepScreenOn = true,
    this.onKeepScreenOnChanged,
    this.recordingMap3d = true,
    this.onRecordingMap3dChanged,
    required this.videoRecording,
    required this.onVideoRecordingChanged,
    required this.trimPrivacy,
    required this.onTrimPrivacyChanged,
    this.onExportCrashLog,
    this.debugMode = false,
    this.onDebugModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    Widget row({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Widget? trailing,
    }) {
      return settingsGroupRow(
        context,
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: trailing,
      );
    }

    Widget switchRow({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) {
      return row(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Switch(value: value, onChanged: onChanged),
      );
    }

    Widget group(String title, List<Widget> children) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: CardStyle.cardColor,
              borderRadius: BorderRadius.circular(CardStyle.cardRadius),
              border: Border.all(color: CardStyle.borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CardStyle.cardRadius),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 60,
                        color: Colors.white10,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final driveRows = <Widget>[
      row(
        icon: Icons.flag,
        title: s.t('赛道模式设置', 'Track mode'),
        subtitle: s.t('圈速判定、分段、Delta、最佳圈提醒', 'Laps, sectors, delta'),
        onTap: onOpenTrack,
      ),
      if (onOpenSensorCalibration != null)
        row(
          icon: Icons.sensors,
          title: s.t('传感器校准', 'Sensor calibration'),
          subtitle: s.t('静置校零、车头标定、罗盘提示', 'Level, heading, compass'),
          onTap: onOpenSensorCalibration!,
        ),
      if (onOpenVehicle != null)
        row(
          icon: Icons.directions_car,
          title: s.t('车辆档案', 'Vehicles'),
          subtitle: s.t('车辆档案与加油记录，行程油耗按车计算', 'Garage and fuel logs'),
          onTap: onOpenVehicle!,
        ),
      if (onOpenFuel != null)
        row(
          icon: Icons.local_gas_station,
          title: s.t('油耗费用', 'Fuel cost'),
          subtitle: s.t('百公里油耗与油价，行程自动估算', 'Consumption and price'),
          onTap: onOpenFuel!,
        ),
    ];

    final deviceRows = <Widget>[
      row(
        icon: Icons.verified_user,
        title: s.t('权限检查', 'Permissions'),
        subtitle: s.t('补齐授权或去系统设置取消授权', 'Grant access or open system settings'),
        onTap: onOpenPermission,
      ),
      row(
        icon: Icons.satellite_alt,
        title: s.t('定位', 'Location'),
        subtitle: s.t('直连卫星模式、卫星数', 'GNSS-only mode, satellite count'),
        onTap: onOpenLocation,
      ),
      row(
        icon: Icons.map,
        title: s.t('地图资源导入', 'Map import'),
        subtitle: s.t(
          '离线瓦片包、GeoJSON/KML 叠加、底图样式',
          'Offline tiles and overlays',
        ),
        onTap: onOpenMapImport,
      ),
    ];

    final lookRows = <Widget>[
      row(
        icon: Icons.palette,
        title: s.t('主题设置', 'Theme'),
        subtitle: s.t('全局黑色、F1 车队近似色、自定义颜色', 'Black UI, accent color'),
        onTap: onOpenTheme,
      ),
      row(
        icon: Icons.record_voice_over,
        title: s.t('语音设置', 'Voice'),
        subtitle: s.t('播报开关、语速、音调、播报项', 'Speech, rate, pitch'),
        onTap: onOpenVoice,
      ),
    ];

    final recordRows = <Widget>[
      if (onKeepScreenOnChanged != null)
        switchRow(
          icon: Icons.brightness_high,
          title: s.t('记录时保持屏幕常亮', 'Keep screen on while recording'),
          subtitle: s.t(
            '记录开始自动开启，结束自动关闭',
            'On when recording starts, off when it ends',
          ),
          value: keepScreenOn,
          onChanged: onKeepScreenOnChanged,
        ),
      if (onRecordingMap3dChanged != null)
        switchRow(
          icon: Icons.threed_rotation,
          title: s.t('记录地图 3D 透视', '3D recording map'),
          subtitle: s.t(
            '关闭为 2D 俯视，非真实建筑/路网',
            'Off is a flat view, not real buildings',
          ),
          value: recordingMap3d,
          onChanged: onRecordingMap3dChanged,
        ),
      switchRow(
        icon: Icons.videocam,
        title: s.t('同步视频录制（App 内停用）', 'In-app video (off)'),
        subtitle: s.t('关闭后不再调用相机与麦克风', 'Off: no camera or microphone'),
        value: videoRecording,
        onChanged: onVideoRecordingChanged,
      ),
      switchRow(
        icon: Icons.vibration,
        title: s.t('倒计时震动提醒', 'Countdown vibration'),
        subtitle: s.t(
          '3-2-1 每秒短震，GO 时长震',
          'Short buzz each count, long buzz on GO',
        ),
        value: countdownVibration,
        onChanged: onCountdownVibrationChanged,
      ),
      switchRow(
        icon: Icons.location_off,
        title: s.t('分享轨迹截掉首尾', 'Trim ends when sharing'),
        subtitle: s.t('不暴露具体住址', 'Hides your home address'),
        value: trimPrivacy,
        onChanged: onTrimPrivacyChanged,
      ),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: Text(s.t('设置', 'Settings')),
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.only(bottom: 28)),
        children: [
          const SizedBox(height: 8),
          // v1.7.0：语言入口改为设置页标准分组行（不再单独一张风格
          // 不同的卡），登录页仍用独立卡片（LanguageSwitch 默认样式）。
          group(s.t('通用', 'General'), [
            const LanguageSwitch(rowStyle: true),
            const AccountSettingsRow(),
            settingsGroupRow(
              context,
              icon: Icons.auto_awesome,
              title: s.t('AI 分析', 'AI analysis'),
              subtitle: s.t(
                '配置 OpenAI 兼容接口，用于赛后与单圈分析',
                'Configure an OpenAI-compatible API for race analysis',
              ),
              onTap: () => Navigator.of(context)
                  .push(DtPageRoute(builder: (_) => const AiSettingsPage())),
            ),
          ]),
          group(s.t('驾驶与赛道', 'Driving & track'), driveRows),
          group(s.t('设备与地图', 'Devices & maps'), deviceRows),
          group(s.t('外观与语音', 'Look & voice'), lookRows),
          group(s.t('记录偏好', 'Recording'), recordRows),
          if (onExportCrashLog != null)
            group(s.t('帮助与诊断', 'Help & diagnostics'), [
              row(
                icon: Icons.bug_report,
                title: s.t('导出崩溃日志', 'Export crash log'),
                subtitle: s.t(
                  '闪退/异常记录（仅本机，200KB 上限，可分享给开发者）',
                  'Local crash log only (200KB cap), share with the developer',
                ),
                onTap: onExportCrashLog,
              ),
            ]),
          if (onDebugModeChanged != null)
            group(s.t('调试（自用版）', 'Debug (personal build)'), [
              switchRow(
                icon: Icons.bug_report,
                title: s.t('调试模式', 'Debug mode'),
                subtitle: s.t(
                  '跳过赛道/卡丁的外接硬件门槛，方便无硬件联调；正式使用请关闭',
                  'Bypasses the external-hardware gate for track/kart. Turn off for normal use.',
                ),
                value: debugMode,
                onChanged: onDebugModeChanged,
              ),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            child: Text(
              s.t('设置只保存在本机，不上传。', 'Settings stay on this device.'),
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}
