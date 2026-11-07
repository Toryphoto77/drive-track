import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_bar_style.dart';
import 'gps_source.dart';
import 'native.dart';
import 'track_timing.dart';
import 'voice_service.dart';

/// 赛道模式设置子页 + 设置模型（v0.1.4 新增文件）。
///
/// 持久化：本页自己读写 Native.getFilesDir() 下的 `track_settings.json`
/// （见 [TrackSettingsStore]），键名见 [TrackSettings.toJson]。
/// 总协调不需要另起存储，也不要把同一份设置再抄进 profile.json。
/// 计时逻辑接线（本文件不改 track_timing.dart，见文件末尾接线说明）：
/// 构造 LapTimer 时从本设置取值，不要用 LapTimer 的默认值硬编码两份。

/// 分段模式。注意：真正的分段数由传给 LapTimer 的 sectorPoints 决定
/// （0 个点 = 前后半圈 2 段，2 个点 = S1/S2/S3 3 段），本设置只存
/// 用户的意向；选了 threeSegment 但赛道页没设 S1/S2 点时，界面必须
/// 标注“无分段点，前后半圈示意”，不得谎称已是三段。
enum TrackSectorMode { halves, threeSegment }

extension TrackSectorModeLabel on TrackSectorMode {
  String get key => name;
  String get label => switch (this) {
        TrackSectorMode.halves => '前后半圈',
        TrackSectorMode.threeSegment => '三段示意',
      };
  static TrackSectorMode fromKey(String? k) =>
      TrackSectorMode.values.firstWhere((e) => e.name == k,
          orElse: () => TrackSectorMode.halves);
}

/// 赛道图配色预设：键 ->（显示名，主色）。颜色只用于赛道图线条与
/// 最快圈高亮，不改变其他页面的主题色。
class TrackColorSchemes {
  static const Map<String, (String, Color)> presets = {
    'red': ('红色', Color(0xFFE53935)),
    'blue': ('蓝色', Color(0xFF1E88E5)),
    'green': ('绿色', Color(0xFF43A047)),
    'amber': ('琥珀', Color(0xFFFB8C00)),
    'purple': ('紫色', Color(0xFF8E24AA)),
  };
  static Color colorOf(String key) =>
      presets[key]?.$2 ?? const Color(0xFFE53935);
  static String nameOf(String key) => presets[key]?.$1 ?? '红色';
}

class TrackSettings {
  /// 圈速判定距离阈值（m）：起终点穿越判定半径，默认 30，与
  /// LapTimer.crossingRadiusM 默认值一致。范围 10~100。
  final double crossingRadiusM;

  /// 停车暂停阈值（秒）：速度持续低于 [dwellSpeedMs] 满这么久即判定
  /// 停车暂停，默认 30，对应 LapTimer.dwellThresholdMs = 秒 × 1000。
  final int dwellThresholdSec;

  /// 停车判定速度阈值（m/s），默认 0.5，对应 LapTimer.dwellSpeedMs。
  final double dwellSpeedMs;

  /// 分段模式意向，默认前后半圈（见 [TrackSectorMode] 注释）。
  final TrackSectorMode sectorMode;

  /// 最佳圈提醒：语音开关，默认 true（走 VoiceService 播报）。
  final bool bestLapVoice;

  /// 最佳圈提醒：震动开关，默认 true（HapticFeedback，不新增原生方法）。
  final bool bestLapVibration;

  /// Delta 显示开关，默认 true（当前圈与最快圈的差值）。
  final bool showDelta;

  /// 赛道图配色键，默认 'red'（见 [TrackColorSchemes.presets]）。
  final String trackColorKey;

  /// 定位采样率（Hz）：10 / 20 / 25 三档，默认 25（DEXIAN D1 与
  /// 自研硬件 NEO-M9N 最高都是 25Hz；Dragy 三档也是 10/20/25）。
  /// 注意：目前只保存设置、暂未生效——采样率要等固件支持：
  /// D1 走二进制协议、包格式待实测抓包才解析，自研硬件尚未组装
  /// 调试；手机 GPS 采样率也不受本项控制。界面必须如实标注
  /// “待固件支持”，不得谎称改了就生效。
  final int sampleRateHz;

  const TrackSettings({
    required this.crossingRadiusM,
    required this.dwellThresholdSec,
    required this.dwellSpeedMs,
    required this.sectorMode,
    required this.bestLapVoice,
    required this.bestLapVibration,
    required this.showDelta,
    required this.trackColorKey,
    required this.sampleRateHz,
  });

  static const defaults = TrackSettings(
    crossingRadiusM: 30,
    dwellThresholdSec: 30,
    dwellSpeedMs: 0.5,
    sectorMode: TrackSectorMode.halves,
    bestLapVoice: true,
    bestLapVibration: true,
    showDelta: true,
    trackColorKey: 'red',
    sampleRateHz: 25,
  );

  TrackSettings copyWith({
    double? crossingRadiusM,
    int? dwellThresholdSec,
    double? dwellSpeedMs,
    TrackSectorMode? sectorMode,
    bool? bestLapVoice,
    bool? bestLapVibration,
    bool? showDelta,
    String? trackColorKey,
    int? sampleRateHz,
  }) =>
      TrackSettings(
        crossingRadiusM: (crossingRadiusM ?? this.crossingRadiusM)
            .clamp(10.0, 100.0),
        dwellThresholdSec:
            (dwellThresholdSec ?? this.dwellThresholdSec).clamp(10, 120),
        dwellSpeedMs:
            (dwellSpeedMs ?? this.dwellSpeedMs).clamp(0.3, 2.0),
        sectorMode: sectorMode ?? this.sectorMode,
        bestLapVoice: bestLapVoice ?? this.bestLapVoice,
        bestLapVibration: bestLapVibration ?? this.bestLapVibration,
        showDelta: showDelta ?? this.showDelta,
        trackColorKey: trackColorKey ?? this.trackColorKey,
        sampleRateHz: _snapSampleRate(sampleRateHz ?? this.sampleRateHz),
      );

  /// 采样率只认 10 / 20 / 25 三档，其余值就近归档。
  static int _snapSampleRate(int v) {
    if (v <= 15) return 10;
    if (v <= 22) return 20;
    return 25;
  }

  /// 本机存储键名（track_settings.json 的 JSON 键，固定不变）：
  /// crossing_radius_m / dwell_threshold_sec / dwell_speed_ms /
  /// sector_mode / best_lap_voice / best_lap_vibration / show_delta /
  /// track_color / sample_rate_hz。
  Map<String, dynamic> toJson() => {
        'crossing_radius_m': crossingRadiusM,
        'dwell_threshold_sec': dwellThresholdSec,
        'dwell_speed_ms': dwellSpeedMs,
        'sector_mode': sectorMode.key,
        'best_lap_voice': bestLapVoice,
        'best_lap_vibration': bestLapVibration,
        'show_delta': showDelta,
        'track_color': trackColorKey,
        'sample_rate_hz': sampleRateHz,
      };

  static TrackSettings fromJson(Map<String, dynamic> j) => TrackSettings(
        crossingRadiusM:
            ((j['crossing_radius_m'] as num?)?.toDouble() ?? 30)
                .clamp(10.0, 100.0),
        dwellThresholdSec:
            ((j['dwell_threshold_sec'] as num?)?.toInt() ?? 30)
                .clamp(10, 120),
        dwellSpeedMs: ((j['dwell_speed_ms'] as num?)?.toDouble() ?? 0.5)
            .clamp(0.3, 2.0),
        sectorMode:
            TrackSectorModeLabel.fromKey(j['sector_mode'] as String?),
        bestLapVoice: (j['best_lap_voice'] as bool?) ?? true,
        bestLapVibration: (j['best_lap_vibration'] as bool?) ?? true,
        showDelta: (j['show_delta'] as bool?) ?? true,
        trackColorKey: (j['track_color'] as String?) ?? 'red',
        sampleRateHz: _snapSampleRate(
            (j['sample_rate_hz'] as num?)?.toInt() ?? 25),
      );

  /// 给 LapTimer 构造用的阈值（record 解构，字段名与 LapTimer 构造参数一致）。
  ({double crossingRadiusM, int dwellThresholdMs, double dwellSpeedMs})
      get lapTimerArgs => (
            crossingRadiusM: crossingRadiusM,
            dwellThresholdMs: dwellThresholdSec * 1000,
            dwellSpeedMs: dwellSpeedMs,
          );

  Color get trackColor => TrackColorSchemes.colorOf(trackColorKey);
}

/// 本机存储：Native.getFilesDir() 下的 track_settings.json。
class TrackSettingsStore {
  static const String fileName = 'track_settings.json';

  static Future<TrackSettings> load() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/$fileName');
      if (!await f.exists()) return TrackSettings.defaults;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return TrackSettings.fromJson(j);
    } catch (_) {
      return TrackSettings.defaults;
    }
  }

  static Future<void> save(TrackSettings s) async {
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/$fileName')
          .writeAsString(jsonEncode(s.toJson()));
    } catch (_) {
      // 写盘失败不阻塞界面；本次会话内设置仍生效。
    }
  }
}

/// 最佳圈提醒触发器（总协调在检测到新最快圈时调这个，不要自己拼语音文案）。
/// - 语音：settings.bestLapVoice 为 true 且 VoiceService 总开关开启时，
///   走 voice.announceLap(isBest: true)；
/// - 震动：settings.bestLapVibration 为 true 时 HapticFeedback 一次。
/// 两个开关都关时什么都不做。
class BestLapNotifier {
  static Future<void> notifyBestLap({
    required TrackSettings settings,
    required VoiceService voice,
    required Lap lap,
  }) async {
    if (settings.bestLapVoice) {
      await voice.announceLap(
          lapNumber: lap.number, lapMs: lap.durationMs, isBest: true);
    }
    if (settings.bestLapVibration) {
      HapticFeedback.mediumImpact();
    }
  }
}

class TrackSettingsPage extends StatefulWidget {
  /// 初始值：不传时本页从 [TrackSettingsStore] 加载；
  /// 传了则以它为起点，之后每次改动仍会写回 Store（单一存储源）。
  final TrackSettings? initial;

  /// 改动回调：总协调可在此把新设置同步给正在跑的 LapTimer
  /// （LapTimer 构造后阈值不可改，需用新阈值重建计时器，见文末接线说明）。
  final ValueChanged<TrackSettings>? onChanged;

  /// 外置 GPS 入口回调：总协调传推设备中心页的跳转（main.dart 的
  /// _openDeviceCenter）。不传时入口只显示提示，不跳转、不伪造。
  final VoidCallback? onOpenDeviceCenter;

  /// IMU 标定入口回调：总协调传推传感器校准页的跳转（main.dart 的
  /// _openSensorCalibration，需 Recorder）。不传时入口只显示提示。
  final VoidCallback? onOpenSensorCalibration;

  const TrackSettingsPage({
    super.key,
    this.initial,
    this.onChanged,
    this.onOpenDeviceCenter,
    this.onOpenSensorCalibration,
  });

  @override
  State<TrackSettingsPage> createState() => _TrackSettingsPageState();
}

class _TrackSettingsPageState extends State<TrackSettingsPage> {
  TrackSettings _s = TrackSettings.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _s = widget.initial!;
      _loaded = true;
    } else {
      TrackSettingsStore.load().then((v) {
        if (!mounted) return;
        setState(() {
          _s = v;
          _loaded = true;
        });
      });
    }
  }

  Future<void> _apply(TrackSettings next) async {
    setState(() => _s = next);
    await TrackSettingsStore.save(next);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('赛道模式设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: withAppBarTopInset(context, const EdgeInsets.all(16)),
              children: [
                _section('圈速判定'),
                ListTile(
                  title: const Text('起终点判定半径'),
                  subtitle: Text(
                      '${_s.crossingRadiusM.round()} 米（默认 30 米；越大越不易漏判，也越易误触发）'),
                ),
                Slider(
                  value: _s.crossingRadiusM,
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '${_s.crossingRadiusM.round()} 米',
                  onChanged: (v) =>
                      _apply(_s.copyWith(crossingRadiusM: v)),
                ),
                _section('停车暂停'),
                ListTile(
                  title: const Text('停车持续时长'),
                  subtitle: Text(
                      '${_s.dwellThresholdSec} 秒（默认 30 秒；低于阈值满此时长暂停计时，本圈不计）'),
                ),
                Slider(
                  value: _s.dwellThresholdSec.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 22,
                  label: '${_s.dwellThresholdSec} 秒',
                  onChanged: (v) => _apply(
                      _s.copyWith(dwellThresholdSec: v.round())),
                ),
                ListTile(
                  title: const Text('停车速度阈值'),
                  subtitle: Text(
                      '${_s.dwellSpeedMs.toStringAsFixed(1)} m/s（默认 0.5 m/s）'),
                ),
                Slider(
                  value: _s.dwellSpeedMs,
                  min: 0.3,
                  max: 2.0,
                  divisions: 17,
                  label: '${_s.dwellSpeedMs.toStringAsFixed(1)} m/s',
                  onChanged: (v) =>
                      _apply(_s.copyWith(dwellSpeedMs: v)),
                ),
                _section('分段模式'),
                RadioGroup<TrackSectorMode>(
                  groupValue: _s.sectorMode,
                  onChanged: (v) =>
                      v == null ? null : _apply(_s.copyWith(sectorMode: v)),
                  child: Column(
                    children: [
                      RadioListTile<TrackSectorMode>(
                        title: const Text('前后半圈'),
                        subtitle:
                            const Text('按圈时长中点切两段'),
                        value: TrackSectorMode.halves,
                      ),
                      RadioListTile<TrackSectorMode>(
                        title: const Text('三段示意'),
                        subtitle: const Text(
                            '需在赛道页设 S1、S2 分段点，否则按前后半圈显示'),
                        value: TrackSectorMode.threeSegment,
                      ),
                    ],
                  ),
                ),
                _section('最佳圈提醒'),
                SwitchListTile(
                  title: const Text('语音提醒'),
                  subtitle: const Text('新最快圈时语音播报圈速（需语音总开关开启）'),
                  value: _s.bestLapVoice,
                  onChanged: (v) =>
                      _apply(_s.copyWith(bestLapVoice: v)),
                ),
                SwitchListTile(
                  title: const Text('震动提醒'),
                  subtitle: const Text('新最快圈时震动一次'),
                  value: _s.bestLapVibration,
                  onChanged: (v) =>
                      _apply(_s.copyWith(bestLapVibration: v)),
                ),
                _section('显示'),
                SwitchListTile(
                  title: const Text('显示 Delta'),
                  subtitle: const Text('当前圈与最快圈的差值（负值表示更快）'),
                  value: _s.showDelta,
                  onChanged: (v) => _apply(_s.copyWith(showDelta: v)),
                ),
                const SizedBox(height: 8),
                const Text('赛道图配色',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in TrackColorSchemes.presets.entries)
                      ChoiceChip(
                        label: Text(e.value.$1),
                        selected: _s.trackColorKey == e.key,
                        selectedColor: e.value.$2.withValues(alpha: 0.25),
                        onSelected: (_) =>
                            _apply(_s.copyWith(trackColorKey: e.key)),
                      ),
                  ],
                ),
                _section('外置设备与采样'),
                _hardwareStatusTile(),
                ListTile(
                  leading: const Icon(Icons.satellite_alt),
                  title: const Text('外置 GPS'),
                  subtitle: Text(widget.onOpenDeviceCenter == null
                      ? '从设置首页 → 设备中心进入，可扫描、连接外置 GPS 接收器'
                      : '扫描、连接 DEXIAN D1 与其它外置 GPS 接收器'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenDeviceCenter,
                ),
                ListTile(
                  leading: const Icon(Icons.sensors),
                  title: const Text('IMU 标定（传感器校准）'),
                  subtitle: Text(widget.onOpenSensorCalibration == null
                      ? '从设置首页 → 传感器校准进入'
                      : '静置校零、车头方向标定、罗盘 8 字提示。标定结果只保存在内存里，退出 App 后失效，下次使用前需重校。'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenSensorCalibration,
                ),
                const SizedBox(height: 8),
                const Text('定位采样率（待固件支持）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  '仅保存设置，暂未生效：采样率要等固件支持——D1 走二进制协议，包格式待设备回来抓包确认后才解析；自研硬件尚未组装调试。当前仍按设备实际输出采样；手机 GPS 采样率不受本项控制。',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final hz in [10, 20, 25])
                      ChoiceChip(
                        label: Text('$hz Hz'),
                        selected: _s.sampleRateHz == hz,
                        onSelected: (_) =>
                            _apply(_s.copyWith(sampleRateHz: hz)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '自研硬件在研：ESP32-S3 + NEO-M9N（最高 25Hz）+ BMI088 + BMP390，车顶外壳已定型，尚未组装调试。',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => _apply(TrackSettings.defaults),
                  child: const Text('恢复默认'),
                ),
                const SizedBox(height: 16),
                const Text(
                  '行程中改设置只影响下一趟。',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
    );
  }

  /// 外置设备连接状态行：只读设备中心写入的共享状态
  /// （gps_source.dart 的 externalGpsStatus），本页不自己猜。
  /// 未连接 = 手机 GPS；D1（二进制）已连通也不出定位，仍用手机 GPS。
  Widget _hardwareStatusTile() {
    return ValueListenableBuilder<ExternalGpsStatus>(
      valueListenable: externalGpsStatus,
      builder: (context, st, _) {
        final String title;
        final String subtitle;
        final IconData icon;
        if (!st.connected) {
          title = '未连接外置设备';
          subtitle = '当前定位来源：手机 GPS。去设备中心扫描并连接外置 GPS。';
          icon = Icons.gps_not_fixed;
        } else if (st.binaryOnly) {
          title = '已连接 ${st.deviceName}';
          subtitle = '仅连接，不出定位：二进制包格式待实测确认。当前定位来源仍是手机 GPS。';
          icon = Icons.bluetooth_connected;
        } else {
          title = '已连接 ${st.deviceName}';
          subtitle =
              '通道：${st.channel == 'spp' ? '经典蓝牙 SPP' : 'BLE'}；行程定位优先用外接设备，5 秒无新定位自动回落手机 GPS。';
          icon = Icons.satellite_alt;
        }
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
        );
      },
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
      );
}

/// ---- 总协调把阈值传给计时逻辑的方法（本文件不改 track_timing.dart） ----
///
/// 赛道开始时（构造 LapTimer 的唯一位置）：
/// ```dart
/// final settings = await TrackSettingsStore.load();
/// final args = settings.lapTimerArgs;
/// final timer = LapTimer(
///   startFinish: startFinish,
///   crossingRadiusM: args.crossingRadiusM,
///   dwellThresholdMs: args.dwellThresholdMs,
///   dwellSpeedMs: args.dwellSpeedMs,
///   sectorPoints: sectorPoints, // 来自赛道页的 S1/S2 点，与本设置无关
/// );
/// ```
/// 行程中用户在设置页改了值：通过 TrackSettingsPage 的 onChanged 收到
/// 新值后，只更新“下一趟”的待用设置，不要重建正在跑的 LapTimer。
/// 新最快圈出现时（timer.bestLap 变化且 counted）调
/// BestLapNotifier.notifyBestLap(settings: settings, voice: voice, lap: best)。
/// Delta 显示：showDelta 为 false 时隐藏 timer.currentDeltaMs 一行，
/// 不改动计时逻辑本身。
///
/// ---- 外置设备与采样接线（总协调） ----
/// - TrackSettingsPage 构造时传 onOpenDeviceCenter: _openDeviceCenter
///   与 onOpenSensorCalibration: _openSensorCalibration（main.dart
///   已有这两个方法，设置首页也在用同一入口），本页的两个入口即
///   可跳转；不传时入口只显示“从设置首页进入”的提示。
/// - 连接状态不由本页维护：device_center.dart 的 ExternalGpsSection
///   在连接 / 断开事件里写 gps_source.dart 的 externalGpsStatus，
///   本页只监听显示。
/// - sampleRateHz 目前只持久化到 track_settings.json，不接任何
///   采样逻辑：D1 二进制包未解析、自研硬件未组装，固件支持后再由
///   总协调接线；接线前不得去掉“待固件支持”的标注。
