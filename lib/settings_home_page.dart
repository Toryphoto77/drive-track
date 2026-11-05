import 'package:flutter/material.dart';
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
    // v1.0.2：设置入口行改用统一卡片组件（见 card_style.dart）。
    Widget entry(IconData icon, String title, String subtitle, VoidCallback onTap) {
      return DriveTrackEntryCard(icon: icon, title: title, subtitle: subtitle, onTap: onTap);
    }

    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          entry(Icons.verified_user, '权限检查', '补齐授权或去系统设置取消授权', onOpenPermission),
          entry(Icons.palette, '主题设置', '全局黑色、F1 车队近似色、自定义颜色', onOpenTheme),
          entry(Icons.record_voice_over, '语音设置', '播报开关、语速、音调、播报项', onOpenVoice),
          entry(Icons.flag, '赛道模式设置', '圈速判定、分段、Delta、最佳圈提醒', onOpenTrack),
          entry(Icons.satellite_alt, '定位', '直连卫星模式、卫星数与精度说明', onOpenLocation),
          // v0.1.9 传感器校准：水平静置校零、车头方向标定、罗盘 8 字提示，
          // 复用现有标定逻辑，不另造一套 G 值计算。
          if (onOpenSensorCalibration != null)
            entry(Icons.sensors, '传感器校准', '静置校零、车头标定、罗盘提示', onOpenSensorCalibration!),
          entry(Icons.devices, '设备中心', '运动相机 · 传感器 · 外接 GPS', onOpenDevices),
          entry(Icons.map, '地图资源导入', '离线瓦片包、GeoJSON/KML 叠加、底图样式', onOpenMapImport),
          // v1.0.2：第 8 项——“地图车标”入口已从设置首页删除，
          // 功能移入主题设置页的“地图车标”分区。
          // v0.1.7 油耗费用：百公里油耗与油价，汽车/摩托行程自动估算。
          if (onOpenFuel != null)
            entry(Icons.local_gas_station, '油耗费用', '百公里油耗与油价，行程自动估算油耗与油钱', onOpenFuel!),
          if (onOpenVehicle != null)
            entry(Icons.directions_car, '车辆档案', '车辆档案与加油记录，行程油耗按车计算、实测按满油区间算', onOpenVehicle!),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('快捷开关', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              SwitchListTile(
                title: const Text('倒计时震动提醒'),
                value: countdownVibration,
                onChanged: onCountdownVibrationChanged,
              ),
              SwitchListTile(
                title: const Text('同步视频录制（App 内停用）'),
                subtitle: const Text('关闭后不再调用相机与麦克风'),
                value: videoRecording,
                onChanged: onVideoRecordingChanged,
              ),
              SwitchListTile(
                title: const Text('分享轨迹截掉首尾'),
                value: trimPrivacy,
                onChanged: onTrimPrivacyChanged,
              ),
              // v0.1.8：记录开始自动开常亮、结束自动关闭；熄屏是系统
              // 锁屏超时，不是定位问题。开关关闭时记录开始不再自动开启。
              SwitchListTile(
                title: const Text('记录时保持屏幕常亮'),
                subtitle: const Text('记录开始自动开启，结束自动关闭'),
                value: keepScreenOn,
                onChanged: onKeepScreenOnChanged,
              ),
              SwitchListTile(
                title: const Text('记录地图 3D 透视'),
                subtitle: const Text('关闭为 2D 俯视示意；风格化示意，非真实建筑/路网'),
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
