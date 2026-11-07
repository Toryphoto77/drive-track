import 'dart:async';
import 'package:flutter/services.dart';

import 'app_icon_choice.dart';

/// 与 Android 原生通道的唯一接口。零 pub 插件，全部走手写 Method/EventChannel。
class Native {
  static const MethodChannel _m = MethodChannel('drivetrack/native');
  static const EventChannel _loc = EventChannel('drivetrack/location');
  static const EventChannel _sen = EventChannel('drivetrack/sensors');
  static const EventChannel _bleDev = EventChannel('drivetrack/bleDevices');
  static const EventChannel _bleData = EventChannel('drivetrack/bleData');
  static const EventChannel _btGpsDev =
      EventChannel('drivetrack/btGpsDevices');
  static const EventChannel _gnss = EventChannel('drivetrack/gnss');
  static const EventChannel _tts = EventChannel('drivetrack/tts');

  static Stream<Map<String, dynamic>> get locationStream => _loc
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
  static Stream<Map<String, dynamic>> get sensorStream => _sen
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
  static Stream<Map<String, dynamic>> get bleDeviceStream => _bleDev
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
  static Stream<Map<String, dynamic>> get bleDataStream => _bleData
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// 外置蓝牙 GPS 专用发现流：无过滤 BLE 扫描与经典蓝牙发现的
  /// 结果（{type: 'ble'|'classic', address, name, rssi, serviceUuids}）。
  /// 与页级 bleDeviceStream 分离，避免 GPS 扫描结果污染页级
  /// “附近扫描结果”列表、造成同一设备出现两条。
  static Stream<Map<String, dynamic>> get btGpsDeviceStream => _btGpsDev
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// v0.1.4 GNSS 卫星事件流：原生 GnssStatus.Callback 上报的历元快照，
  /// {visible, used, avgCn0(-1 表示无 CN0 数据）, byConstellation,
  /// usedByConstellation, l5Seen, timeMs}。卫星数由 satellite_service.dart 解析。
  static Stream<Map<String, dynamic>> get gnssStream => _gnss
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// v0.1.4 TTS 完成事件流：{type: 'done'|'error', utteranceId}。
  /// 队列由 voice_service.dart 的 Dart 侧管理，原生只报单条完成。
  static Stream<Map<String, dynamic>> get ttsStream => _tts
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));

  /// 分步授权状态快照。
  /// 返回键：location（前台定位，FINE 或 COARSE 任一已授予）、foreground（同
  /// location）、background（Android 10 以下无后台定位概念时恒为 true）、
  /// notifications（Android 13 以下恒为 true）、bluetooth（Android 12 以下
  /// 恒为 true）、permanentlyDenied（已拒绝且 rationale 为 false 的完整权限
  /// 名列表；注意从未申请过时 rationale 同样为 false，调用方只应在刚发起
  /// 过该步请求、复查仍拒绝时才将其当作永久拒绝，见 permission_gate.dart）。
  static Future<Map<String, dynamic>> checkPermissions() async {
    final r = await _m.invokeMethod('checkPermissions');
    return Map<String, dynamic>.from(r as Map);
  }

  /// 分步拉系统权限框，每步原生侧用不同 requestCode，结果按 code 分发。
  /// - 'foreground'：仅 ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION。
  /// - 'extras'：Android 13+ 的 POST_NOTIFICATIONS、Android 12+ 的
  ///   BLUETOOTH_SCAN / BLUETOOTH_CONNECT；低版本对应项不申请。
  /// - 'background'：仅 ACCESS_BACKGROUND_LOCATION，且仅在前台定位已授予
  ///   时才发起；前台未授予时不拉框，返回 requested=false +
  ///   reason=foreground_not_granted。
  /// - 'camera'：CAMERA + RECORD_AUDIO（随同步视频按需申请）。
  /// - 'microphone'（v0.1.3 新增）：仅 RECORD_AUDIO，独立 requestCode。
  /// 返回为 checkPermissions 的快照外加 step / requested（已授予无需申请
  /// 时同样为 false）；未知 step 原生侧报 INVALID_STEP 错误。
  static Future<Map<String, dynamic>> requestStep(String step) async {
    final r = await _m.invokeMethod('requestStep', {'step': step});
    return Map<String, dynamic>.from(r as Map);
  }

  /// 打开本应用的系统设置页（ACTION_APPLICATION_DETAILS_SETTINGS）。
  /// 仅供 permission_gate.dart 在永久拒绝时作为次要入口调用。
  static Future<void> openAppSettings() =>
      _m.invokeMethod('openAppSettings');

  /// 残留调用兼容：旧名保留，但 v0.1.1 起只走 foreground 一步，不再打包
  /// 后台定位 / 通知 / 蓝牙。打包是 v0.1.0 的 bug 根因（Android 11+ 会静默
  /// 丢弃与前台定位同批的后台定位项），新代码一律用 requestStep 分步申请。
  static Future<Map<String, dynamic>> requestPermissions() async {
    final r = await _m.invokeMethod('requestPermissions');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<String> getFilesDir() async =>
      await _m.invokeMethod('getFilesDir') as String;
  static Future<String> getCacheDir() async =>
      await _m.invokeMethod('getCacheDir') as String;
  static Future<void> startForeground() => _m.invokeMethod('startForeground');
  static Future<void> stopForeground() => _m.invokeMethod('stopForeground');
  static Future<void> startLocation() => _m.invokeMethod('startLocation');
  static Future<void> stopLocation() => _m.invokeMethod('stopLocation');
  static Future<void> startSensors() => _m.invokeMethod('startSensors');
  static Future<void> stopSensors() => _m.invokeMethod('stopSensors');
  static Future<void> startBleScan() => _m.invokeMethod('startBleScan');
  static Future<void> stopBleScan() => _m.invokeMethod('stopBleScan');
  static Future<void> connectBle(String address) =>
      _m.invokeMethod('connectBle', {'address': address});
  static Future<void> disconnectBle() => _m.invokeMethod('disconnectBle');
  static Future<void> setBleAutoReconnect(bool v) =>
      _m.invokeMethod('setBleAutoReconnect', {'value': v});
  static Future<void> zeroCalibrate() => _m.invokeMethod('zeroCalibrate');

  /// v0.1.3 通用 BLE（外接设备中心 / GoPro / BleDIY UART 用）。
  /// 注意：原生侧仍为单 GATT，一次只能连一台设备，连新设备会断开旧的；
  /// 通知以 {type:'bleNotification', characteristicUuid, bytes} 发到 bleData 流。
  static Future<Map<String, dynamic>> writeBleCharacteristic(String address, String serviceUuid, String characteristicUuid, List<int> bytes, {bool withResponse = true}) async {
    final r = await _m.invokeMethod('writeBleCharacteristic', {'address': address, 'serviceUuid': serviceUuid, 'characteristicUuid': characteristicUuid, 'bytes': bytes, 'withResponse': withResponse});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> subscribeBleCharacteristic(String address, String serviceUuid, String characteristicUuid) async {
    final r = await _m.invokeMethod('subscribeBleCharacteristic', {'address': address, 'serviceUuid': serviceUuid, 'characteristicUuid': characteristicUuid});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> unsubscribeBleCharacteristic(String address, String serviceUuid, String characteristicUuid) =>
      _m.invokeMethod('unsubscribeBleCharacteristic', {'address': address, 'serviceUuid': serviceUuid, 'characteristicUuid': characteristicUuid});

  static Future<List<int>> readBleCharacteristic(String address, String serviceUuid, String characteristicUuid) async {
    final r = await _m.invokeMethod('readBleCharacteristic', {'address': address, 'serviceUuid': serviceUuid, 'characteristicUuid': characteristicUuid});
    return (r as List).map((e) => (e as num).toInt()).toList();
  }

  static Future<void> scanBleWithServices(List<String> serviceUuids) =>
      _m.invokeMethod('scanBleWithServices', {'serviceUuids': serviceUuids});

  /// 外置蓝牙 GPS（BtGpsManager）：经典蓝牙 SPP + 经典蓝牙发现 +
  /// 无过滤 BLE 扫描。SPP 数据事件走 bleData 流（sppNmea 等），
  /// 发现事件走 btGpsDeviceStream；返回值除已注明外均为 ok 布尔。
  static Future<List<Map<String, dynamic>>> listBondedSppDevices() async {
    final r = await _m.invokeMethod('listBondedSppDevices');
    return (r as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> connectSpp(String address) =>
      _m.invokeMethod('connectSpp', {'address': address});
  static Future<void> disconnectSpp() => _m.invokeMethod('disconnectSpp');
  static Future<bool> startClassicDiscovery() async =>
      await _m.invokeMethod('startClassicDiscovery') as bool;
  static Future<void> stopClassicDiscovery() =>
      _m.invokeMethod('stopClassicDiscovery');
  static Future<bool> scanBleUnfiltered() async =>
      await _m.invokeMethod('scanBleUnfiltered') as bool;

  static Future<String?> getConnectedWifiSsid() async {
    final r = await _m.invokeMethod('getConnectedWifiSsid');
    return r as String?;
  }
  static Future<void> shareFiles(List<String> paths, String mime, String text) =>
      _m.invokeMethod('shareFiles', {'paths': paths, 'mime': mime, 'text': text});

  /// 同步视频（v0.1.2）：后置摄像头无预览录制，1080p 优先、设备不支持则降档。
  /// start 返回 {ok, path?, error?}；stop 返回本趟全部视频分段路径。
  static Future<Map<String, dynamic>> startVideoRecording() async {
    final r = await _m.invokeMethod('startVideoRecording');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<List<String>> stopVideoRecording() async {
    final r = await _m.invokeMethod('stopVideoRecording');
    return (r as List).map((e) => e.toString()).toList();
  }

  static Future<void> playVideo(String path) =>
      _m.invokeMethod('playVideo', {'path': path});

  /// v0.1.5 在线更新安装：调原生 installApk（FileProvider +
  /// ACTION_VIEW，见 MainActivity），由系统安装器完成安装。
  /// 返回 true = 已调起系统安装器（安装本身由用户在系统安装器
  /// 里确认；用户未授予“安装未知应用”时系统会引导去授权）。
  /// v1.0.7：用系统浏览器打开外部链接（库链接 / 作者主页 / Issues）。
  static Future<bool> openUrl(String url) async {
    try {
      final r = await _m.invokeMethod('openUrl', {'url': url});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> installApk(String path) async {
    try {
      await _m.invokeMethod('installApk', {'path': path});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// v0.1.4 语音播报（Android TextToSpeech，语言优先中文）。
  /// v1.2.1：语言按 zh_CN → zh → zh_TW → 系统默认顺序试，
  /// ttsIsAvailable 返回 {available, language: 最终语言代码原样
  /// （如 'zh_CN'/'zh'/'zh_TW'/系统默认代码）/'none', error?}；
  /// 无引擎时 available=false + error='tts_unavailable'，绝不假装播了。
  /// ttsSpeak 返回 {ok, utteranceId?, error?}；完成/失败经 ttsStream 回报，
  /// Dart 侧（voice_service.dart）据此推进队列，原生不做排队。
  static Future<Map<String, dynamic>> ttsIsAvailable() async {
    final r = await _m.invokeMethod('ttsIsAvailable');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> ttsSpeak(String text, {String? utteranceId}) async {
    final r = await _m.invokeMethod('ttsSpeak', {'text': text, if (utteranceId != null) 'utteranceId': utteranceId});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> ttsStop() => _m.invokeMethod('ttsStop');

  /// v1.0.3：切换桌面启动图标 alias（见 AndroidManifest 的
  /// LauncherRed / LauncherRb17 / LauncherValkyrie / LauncherSteering /
  /// LauncherCheckered；alias 定义一个不删，见 app_icon_choice.dart）。
  /// 原生侧用 DONT_KILL_APP，不在
  /// 切换瞬间杀 App、不丢数据；部分厂商启动器刷新有延迟，见主题页
  /// 回落说明。返回 false = 原生切换未成功（选择本身仍已持久化，
  /// 下次冷启动会按持久化选择重新同步一次）。
  /// 图标删减后：被删键（'red'/'rb17'/'valkyrie'/'blue'/'gray'）与非法键
  /// 在 Dart 侧先经 AppIconChoice.normalize 折到 'steering' 再发原生，
  /// 原生永远收不到被删键；MainActivity 里的旧映射仅作兜底保留。
  static Future<bool> setAppIcon(String key) async {
    try {
      final r = await _m.invokeMethod(
          'setAppIcon', {'icon': AppIconChoice.normalize(key)});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// 语速 / 音调 / 音量：Dart 侧已 clamp 到 0.5~2.0 / 0.5~2.0 / 0~1，
  /// 原生侧再 clamp 一次（TextToSpeech 接受范围 0.25~4.0，音量 0~1）。
  static Future<void> ttsSetRate(double rate) =>
      _m.invokeMethod('ttsSetRate', {'rate': rate});
  static Future<void> ttsSetPitch(double pitch) =>
      _m.invokeMethod('ttsSetPitch', {'pitch': pitch});
  static Future<void> ttsSetVolume(double volume) =>
      _m.invokeMethod('ttsSetVolume', {'volume': volume});

  /// v0.1.9 TTS 引擎选择器：返回 {engines: [包名…], current: 默认引擎包名}。
  /// 引擎列表来自系统已装 TTS 引擎，不编造；选中的引擎由原生重建
  /// TextToSpeech 实例后生效，语言仍优先中文、中文不可用回退默认。
  static Future<Map<String, dynamic>> ttsEngines() async {
    try {
      final r = await _m.invokeMethod('ttsEngines');
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {'engines': <String>[], 'current': ''};
    }
  }

  static Future<bool> ttsSetEngine(String packageName) async {
    try {
      final r = await _m.invokeMethod('ttsSetEngine', {'engine': packageName});
      return (Map<String, dynamic>.from(r as Map))['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// v1.2.1 持久化首选引擎：在首次 TTS 初始化前把已保存的首选
  /// 引擎包名传给原生。TTS 尚未创建时原生只记下 override，
  /// 建实例时用它；已创建时原生重建。空串 = 系统默认。
  static Future<bool> ttsApplyPreferredEngine(String packageName) async {
    try {
      final r = await _m.invokeMethod(
          'ttsApplyPreferredEngine', {'engine': packageName});
      return (Map<String, dynamic>.from(r as Map))['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// v0.1.9 自定义语音服务回放：播放自定义服务返回的音频文件。
  /// 仅供 VoiceService 的通用自定义端点使用；原生 TTS 播报不走这里。
  static Future<bool> playAudioFile(String path) async {
    try {
      final r = await _m.invokeMethod('playAudioFile', {'path': path});
      return (Map<String, dynamic>.from(r as Map))['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 设备静音判断（v1.2.1）：只看媒体音量是否为 0，即 muted=true。
  /// TTS 走媒体流，振动/静音响铃模式不再禁播报；响铃模式仍回传，
  /// 供诊断页展示。返回 {muted, ringerMode:
  /// 'normal'/'vibrate'/'silent'/'unknown', musicVolume}。
  static Future<Map<String, dynamic>> audioMuted() async {
    final r = await _m.invokeMethod('audioMuted');
    return Map<String, dynamic>.from(r as Map);
  }

  /// v0.1.4 直连卫星模式：true=只用 GPS_PROVIDER 出位置（网络仅辅星历），
  /// false=恢复 GPS + NETWORK 融合定位。返回 {ok, directMode, error?}；
  /// 定位权限未授予时 ok=false，不假装已切换。卫星快照走 gnssStream。
  static Future<Map<String, dynamic>> setDirectSatelliteMode(bool enabled) async {
    final r = await _m.invokeMethod('setDirectSatelliteMode', {'enabled': enabled});
    return Map<String, dynamic>.from(r as Map);
  }

  /// 最近一次 GNSS 历元快照；从未收到过时 {available: false}。
  static Future<Map<String, dynamic>> getGnssStatus() async {
    final r = await _m.invokeMethod('getGnssStatus');
    return Map<String, dynamic>.from(r as Map);
  }

  /// 自带文件导入口（v0.1.2）：系统文件选择器，kind 为 'font' 或 'image'，
  /// 原生侧拷贝到应用 filesDir，返回本机路径；用户取消返回 null。
  /// 字体文件由 Dart 侧 FontLoader 载入，头像直接作 FileImage 显示。
  static Future<String?> pickFile(String kind) async {
    final r = await _m.invokeMethod('pickFile', {'kind': kind});
    return r as String?;
  }

  /// v0.1.8 记录时保持屏幕常亮：原生 window FLAG_KEEP_SCREEN_ON。
  /// 返回 true = 原生确实加上了 flag；返回 false / 抛错 = 未开启，
  /// 调用方必须按 false 显示“常亮未开启”，绝不假装已开启。
  /// 该 flag 只属于当前 Activity 窗口，App 退出 / Activity 销毁即失效，
  /// 不会在 App 退出后残留。
  static Future<bool> setKeepScreenOn(bool enabled) async {
    try {
      final r = await _m.invokeMethod('setKeepScreenOn', {'enabled': enabled});
      final m = Map<String, dynamic>.from(r as Map);
      return m['ok'] == true && (m['enabled'] as bool? ?? false) == enabled;
    } catch (_) {
      return false;
    }
  }

  /// v0.1.8 电池优化检测：PowerManager.isIgnoringBatteryOptimizations。
  /// 返回 {ignored}；查不到时 ignored=false，页面不得写成“已获白名单”。
  static Future<Map<String, dynamic>> checkBatteryOptimization() async {
    try {
      final r = await _m.invokeMethod('checkBatteryOptimization');
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {'ignored': false};
    }
  }

  /// v0.1.8 跳系统电池优化设置页：ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
  /// （手动选本应用），刻意不用 ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
  /// 自动申请接口，不静默改系统设置、不冒充已获白名单。
  static Future<bool> openBatteryOptimizationSettings() async {
    try {
      await _m.invokeMethod('openBatteryOptimizationSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// v1.0.2 跳系统 TTS 设置页：原生走
  /// Settings.ACTION_TEXT_TO_SPEECH_SETTINGS（系统“文字转语音输出”页，
  /// 可在里面选首选引擎、下载/管理中文语音数据）。
  /// 刻意不用 TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA /
  /// ACTION_CHECK_TTS_DATA：不少设备（尤其无 Google TTS 的国产机）
  /// 没有处理这两个动作的 Activity，直接 startActivity 会抛
  /// ActivityNotFoundException 导致崩溃；也不用
  /// ACTION_VOICE_INPUT_SETTINGS（那是语音输入，不是 TTS）。
  /// 原生侧已 try/catch，个别 OEM 无此设置页时返回 false，调用方
  /// 应改显示文字引导（系统设置 > 系统 > 语言与输入法 >
  /// 文字转语音输出），不要再起第二个 Intent 猜路径。
  static Future<bool> openTtsSettings() async {
    try {
      await _m.invokeMethod('openTtsSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// v0.1.7 拍照打点（新增原生通道，原先没有静态照片通道，只有
  /// Camera2 同步视频录制）：系统相机 ACTION_IMAGE_CAPTURE +
  /// FileProvider 输出到 filesDir/photo_points/ 唯一文件，返回本机
  /// 路径；用户取消返回 null，相机不可用时抛错由调用方提示。
  /// 相机权限由调用方先走 requestStep('camera') 申请，本方法不代申请。
  static Future<String?> takePhoto() async {
    final r = await _m.invokeMethod('takePhoto');
    return r as String?;
  }
}
