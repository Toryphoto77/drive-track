import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'glass_button.dart';
import 'card_style.dart';

/// v0.1.4 设置入口列表页：设置不再是一长页，每行一个入口点进子页。
class SettingsHomePage extends StatelessWidget {
  final VoidCallback onOpenPermission;
  final VoidCallback onOpenTheme;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenTrack;
  final VoidCallback onOpenLocation;
  // v0.1.9 传感器校准入口：可选回调，未传时不显示该入口。
  final VoidCallback? onOpenSensorCalibration;
  final VoidCallback onOpenDevices;
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

  const SettingsHomePage({
    super.key,
    required this.onOpenPermission,
    required this.onOpenTheme,
    required this.onOpenVoice,
    required this.onOpenTrack,
    required this.onOpenLocation,
    this.onOpenSensorCalibration,
    required this.onOpenDevices,
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
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // v1.0.2：设置入口行改用统一卡片组件（见 card_style.dart）。
    Widget entry(IconData icon, String title, String subtitle, VoidCallback onTap) {
      return DriveTrackEntryCard(icon: icon, title: title, subtitle: subtitle, onTap: onTap);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: Text(s.t('设置', 'Settings')),
      ),
      body: ListView(
        padding: withAppBarTopInset(
            context, const EdgeInsets.only(bottom: 24)),
        children: [
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: LanguageSwitch(),
          ),
          entry(Icons.verified_user, s.t('权限检查', 'Permissions'), s.t('补齐授权或去系统设置取消授权', 'Grant access or open system settings'), onOpenPermission),
          entry(Icons.palette, s.t('主题设置', 'Theme'), s.t('全局黑色、F1 车队近似色、自定义颜色', 'Black UI, accent color'), onOpenTheme),
          entry(Icons.record_voice_over, s.t('语音设置', 'Voice'), s.t('播报开关、语速、音调、播报项', 'Speech, rate, pitch'), onOpenVoice),
          entry(Icons.flag, s.t('赛道模式设置', 'Track mode'), s.t('圈速判定、分段、Delta、最佳圈提醒', 'Laps, sectors, delta'), onOpenTrack),
          entry(Icons.satellite_alt, s.t('定位', 'Location'), s.t('直连卫星模式、卫星数', 'GNSS-only mode, satellite count'), onOpenLocation),
          // v0.1.9 传感器校准：水平静置校零、车头方向标定、罗盘 8 字提示，
          // 复用现有标定逻辑，不另造一套 G 值计算。
          if (onOpenSensorCalibration != null)
            entry(Icons.sensors, s.t('传感器校准', 'Sensor calibration'), s.t('静置校零、车头标定、罗盘提示', 'Level, heading, compass'), onOpenSensorCalibration!),
          entry(Icons.devices, s.t('设备中心', 'Devices'), s.t('运动相机 · 传感器 · 外接 GPS', 'Camera, sensors, external GPS'), onOpenDevices),
          entry(Icons.map, s.t('地图资源导入', 'Map import'), s.t('离线瓦片包、GeoJSON/KML 叠加、底图样式', 'Offline tiles and overlays'), onOpenMapImport),
          // v1.0.2：第 8 项——“地图车标”入口已从设置首页删除，
          // 功能移入主题设置页的“地图车标”分区。
          // v0.1.7 油耗费用：百公里油耗与油价，汽车/摩托行程自动估算。
          if (onOpenFuel != null)
            entry(Icons.local_gas_station, s.t('油耗费用', 'Fuel cost'), s.t('百公里油耗与油价，行程自动估算油耗与油钱', 'Consumption and price for estimates'), onOpenFuel!),
          if (onOpenVehicle != null)
            entry(Icons.directions_car, s.t('车辆档案', 'Vehicles'), s.t('车辆档案与加油记录，行程油耗按车计算', 'Garage and fuel logs'), onOpenVehicle!),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(s.t('快捷开关', 'Quick toggles'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SwitchListTile(
                title: Text(s.t('倒计时震动提醒', 'Countdown vibration')),
                value: countdownVibration,
                onChanged: onCountdownVibrationChanged,
              ),
              SwitchListTile(
                title: Text(s.t('同步视频录制（App 内停用）', 'In-app video (off)')),
                subtitle: Text(s.t('关闭后不再调用相机与麦克风', 'Off: no camera or microphone')),
                value: videoRecording,
                onChanged: onVideoRecordingChanged,
              ),
              SwitchListTile(
                title: Text(s.t('分享轨迹截掉首尾', 'Trim ends when sharing')),
                value: trimPrivacy,
                onChanged: onTrimPrivacyChanged,
              ),
              // v0.1.8：记录开始自动开常亮、结束自动关闭；熄屏是系统
              // 锁屏超时，不是定位问题。开关关闭时记录开始不再自动开启。
              SwitchListTile(
                title: Text(s.t('记录时保持屏幕常亮', 'Keep screen on while recording')),
                subtitle: Text(s.t('记录开始自动开启，结束自动关闭', 'On when recording starts, off when it ends')),
                value: keepScreenOn,
                onChanged: onKeepScreenOnChanged,
              ),
              SwitchListTile(
                title: Text(s.t('记录地图 3D 透视', '3D recording map')),
                subtitle: Text(s.t('关闭为 2D 俯视，非真实建筑/路网', 'Off is a flat view, not real buildings')),
                value: recordingMap3d,
                onChanged: onRecordingMap3dChanged,
              ),
            ]),
          ),
          // v1.0.4：字体设置入口已从设置首页删除，功能移入主题设置页
          // 的“字体”分区（见 theme_settings_page.dart），此处不留残留。
          // v1.0.3：设置页“关于”入口已删，关于只在左拉菜单里。
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
