import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native.dart';

/// 语音播报服务（v0.1.4 新增文件，不改动 main.dart / settings_page.dart）。
///
/// 设计（总协调接线前必读）：
/// - 队列在 Dart 侧管理：同一时间只向原生发一条 [Native.ttsSpeak]，
///   下一条在原生经 `drivetrack/tts` EventChannel 回 `done`/`error`
///   后才发出；原生侧用 QUEUE_ADD，不替 Dart 做排队。
/// - 原生播报完成回调：EventChannel `drivetrack/tts`，事件
///   `{type: 'done'|'error', utteranceId: String}`。若 30 秒内无回执，
///   Dart 侧看门狗超时推进（不断在一条坏语音上卡住），并把该条记为失败。
/// - 静音：播报前先查 [isMuted]（原生 AudioManager：非正常响铃模式，
///   或音乐流音量为 0，即视为静音）。“仅在非静音模式播报”这句话由
///   调用方（设置页/语音设置行）在界面上展示，本文件只提供判断接口
///   与下面的 [voiceMutedNote] 文案常量，UI 不得自己另编一套说法。
/// - 本服务不读系统通知权限、不申请麦克风：TTS 是输出，不是录音。
/// - 无 TTS 引擎时原生返回 ok=false + error，Dart 侧不静默假装播了：
///   [lastError] 会被置为该错误，调用方可展示“设备无语音引擎”。

/// 调用方展示的静音说明文案（原样展示，不要改写成“已开启勿扰”等说法）。
const String voiceMutedNote = '仅在非静音模式播报：手机处于静音或振动模式、或媒体音量为 0 时不播报。';

/// 语音设置：默认总开关开启（见 [VoiceSettings.defaults]）。
class VoiceSettings {
  /// 总开关。默认 true。
  final bool enabled;

  /// 语速，0.5 ~ 2.0，默认 1.0。
  final double rate;

  /// 音调，0.5 ~ 2.0，默认 1.0。
  final double pitch;

  /// 音量，0.0 ~ 1.0，默认 1.0（传给原生 TTS 的 KEY_PARAM_VOLUME）。
  final double volume;

  /// 是否播报事件：急加速 / 急刹车 / 过弯完成 / 压弯超阈值。默认 true。
  final bool announceEvents;

  /// 是否播报每圈完成（含最快圈提醒）。默认 true。
  final bool announceLaps;

  /// 是否播报行程结束总结。默认 true。
  final bool announceSummary;

  const VoiceSettings({
    required this.enabled,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.announceEvents,
    required this.announceLaps,
    required this.announceSummary,
  });

  /// 默认值：总开关开启，其余全部开启，语速/音调 1.0，音量 1.0。
  static const defaults = VoiceSettings(
    enabled: true,
    rate: 1.0,
    pitch: 1.0,
    volume: 1.0,
    announceEvents: true,
    announceLaps: true,
    announceSummary: true,
  );

  VoiceSettings copyWith({
    bool? enabled,
    double? rate,
    double? pitch,
    double? volume,
    bool? announceEvents,
    bool? announceLaps,
    bool? announceSummary,
  }) =>
      VoiceSettings(
        enabled: enabled ?? this.enabled,
        rate: _clamp(rate ?? this.rate, 0.5, 2.0),
        pitch: _clamp(pitch ?? this.pitch, 0.5, 2.0),
        volume: _clamp(volume ?? this.volume, 0.0, 1.0),
        announceEvents: announceEvents ?? this.announceEvents,
        announceLaps: announceLaps ?? this.announceLaps,
        announceSummary: announceSummary ?? this.announceSummary,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'announceEvents': announceEvents,
        'announceLaps': announceLaps,
        'announceSummary': announceSummary,
      };

  static VoiceSettings fromJson(Map<String, dynamic> j) => VoiceSettings(
        enabled: (j['enabled'] as bool?) ?? true,
        rate: _clamp((j['rate'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        pitch: _clamp((j['pitch'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        volume: _clamp((j['volume'] as num?)?.toDouble() ?? 1.0, 0.0, 1.0),
        announceEvents: (j['announceEvents'] as bool?) ?? true,
        announceLaps: (j['announceLaps'] as bool?) ?? true,
        announceSummary: (j['announceSummary'] as bool?) ?? true,
      );
}

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// v0.1.9 自定义语音服务配置（设置页“自定义语音服务”区）。
///
/// 结论（见回执）：默认仍用系统原生 TTS。原生本地、无需联网、
/// 无需密钥、无费用，适合驾驶播报；国内 API（讯飞/阿里/腾讯）
/// 音质更好但需要用户自己的 Key、联网、按量计费、有密钥保管
/// 风险，因此绝不内置密钥、不预填示例 Key、不作默认。
/// 本配置只存用户自己填的接口地址与 Key（本机 voice_settings.json，
/// 不上传到任何地方）；未填时完全走原生；填了也只在 [enabled]
/// 被用户明确开启后才走自定义路径，且失败时回落原生并记录原因。
/// 通用接口约定（各厂商协议不同，未逐一实现）：POST JSON
/// {"text": "..."}、Authorization: Bearer <Key>，期望返回音频流；
/// 协议不符时测试按钮会明确报错，而不是静默失败。
class CustomVoiceConfig {
  final bool enabled;
  final String endpoint;
  final String apiKey;
  const CustomVoiceConfig({this.enabled = false, this.endpoint = '', this.apiKey = ''});

  bool get configured => endpoint.trim().isNotEmpty && apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'endpoint': endpoint,
        'apiKey': apiKey,
      };

  static CustomVoiceConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CustomVoiceConfig();
    return CustomVoiceConfig(
      enabled: (j['enabled'] as bool?) ?? false,
      endpoint: (j['endpoint'] as String?) ?? '',
      apiKey: (j['apiKey'] as String?) ?? '',
    );
  }
}

/// 播报事件种类（与 models.dart 的 TripEvent.kind 对应，外加圈与压弯）。
enum VoiceEventKind {
  harshAccel,
  harshBrake,
  corner,
  leanOver,
  lapDone,
}

/// 队列里的一条语音。
class _QueuedSpeech {
  final String text;
  final String utteranceId;
  _QueuedSpeech(this.text, this.utteranceId);
}

class VoiceService extends ChangeNotifier {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  /// 本机存储文件名（Native.getFilesDir() 下），与 settings_page.dart 的
  /// 约定一致：本文件自己读写，不经过 main.dart 的 AppPrefs。
  static const String fileName = 'voice_settings.json';

  VoiceSettings settings = VoiceSettings.defaults;

  /// v0.1.9：用户自填的自定义语音服务配置（默认未启用、未填写）。
  CustomVoiceConfig customVoice = const CustomVoiceConfig();

  /// 自定义路径是否真正启用：开关开 + 地址与 Key 都已填。
  bool get usesCustomVoice => customVoice.enabled && customVoice.configured;

  /// 系统已装 TTS 引擎列表与当前引擎（原生 ttsEngines 回执）。
  List<String> ttsEngineList = [];
  String? ttsEngineCurrent;

  /// 手动静音（用户在行程中点“静音”）：为 true 时队列直接丢弃新播报，
  /// 不进原生。区别于设备静音（[isMuted] 查的是系统状态）。
  bool manualMuted = false;

  /// 最近一次原生返回的错误（如 'tts_unavailable'），无错误时为 null。
  /// 供调用方展示“设备无语音引擎，播报不可用”，不要静默吞掉。
  String? lastError;

  /// 原生 TTS 引擎是否可用（最后一次探测结果；未探测过为 null）。
  /// 语言：'zh'（中文）/ 'default'（中文不可用，回退系统默认语言）/
  /// 'none'（不可用）。中文优先 Locale.CHINESE，不可用时回退默认。
  bool? ttsAvailable;
  String? ttsLanguage;

  final List<_QueuedSpeech> _queue = [];
  bool _speaking = false;
  int _seq = 0;
  Timer? _watchdog;
  StreamSubscription<Map<String, dynamic>>? _ttsSub;
  final Map<VoiceEventKind, int> _lastSpokenKindMs = {};

  int get queueLength => _queue.length;
  bool get isSpeaking => _speaking;

  /// 加载本机语音设置；文件不存在或损坏时用默认值，不抛错。
  Future<void> load() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/$fileName');
      if (!await f.exists()) {
        settings = VoiceSettings.defaults;
        customVoice = const CustomVoiceConfig();
        return;
      }
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      settings = VoiceSettings.fromJson(j);
      customVoice = CustomVoiceConfig.fromJson(
          (j['customVoice'] as Map?)?.cast<String, dynamic>());
    } catch (_) {
      settings = VoiceSettings.defaults;
      customVoice = const CustomVoiceConfig();
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/$fileName').writeAsString(jsonEncode({
            ...settings.toJson(),
            'customVoice': customVoice.toJson(),
          }));
    } catch (_) {
      // 本机写盘失败不阻塞播报；设置本次会话内仍生效。
    }
  }

  Future<void> updateCustomVoice(CustomVoiceConfig next) async {
    customVoice = next;
    await save();
    notifyListeners();
  }

  /// 刷新系统已装 TTS 引擎列表与当前引擎（供引擎选择器展示）。
  Future<void> loadEngines() async {
    try {
      final r = await Native.ttsEngines();
      final raw = r['engines'];
      ttsEngineList = raw is List
          ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      final cur = r['current'] as String?;
      ttsEngineCurrent = (cur != null && cur.isNotEmpty) ? cur : null;
    } catch (_) {
      ttsEngineList = [];
      ttsEngineCurrent = null;
    }
    notifyListeners();
  }

  Future<bool> setTtsEngine(String packageName) async {
    final ok = await Native.ttsSetEngine(packageName);
    if (ok) {
      ttsEngineCurrent = packageName;
      ttsAvailable = null;
      await ensureAvailable();
    }
    notifyListeners();
    return ok;
  }

  Future<void> updateSettings(VoiceSettings next) async {
    settings = next;
    try {
      await Native.ttsSetRate(next.rate);
      await Native.ttsSetPitch(next.pitch);
      await Native.ttsSetVolume(next.volume);
    } catch (_) {
      // 原生未就绪时不阻塞；下次 speak 前会重设一次。
    }
    await save();
    notifyListeners();
  }

  /// 探测原生 TTS 是否可用。返回 false 时 [lastError] 说明原因，
  /// 调用方应如实展示，不得假装播报成功。
  Future<bool> ensureAvailable() async {
    try {
      // 原生 TTS 初始化是异步的；10 秒无回执即视为不可用，不无限挂起。
      final r = await Native.ttsIsAvailable().timeout(
          const Duration(seconds: 10),
          onTimeout: () => {'available': false, 'error': 'tts_timeout'});
      ttsAvailable = (r['available'] as bool?) ?? false;
      ttsLanguage = r['language'] as String?;
      if (ttsAvailable != true) {
        lastError = (r['error'] as String?) ?? 'tts_unavailable';
      } else {
        lastError = null;
      }
      notifyListeners();
      return ttsAvailable == true;
    } catch (e) {
      ttsAvailable = false;
      lastError = 'tts_unavailable';
      notifyListeners();
      return false;
    }
  }

  /// 设备是否处于静音状态：响铃模式非正常，或媒体音量为 0。
  /// 调用方在行程中播报前可用它决定是否跳过；[speakText] 内部同样会查。
  Future<bool> isMuted() async {
    try {
      final r = await Native.audioMuted();
      return (r['muted'] as bool?) ?? false;
    } catch (_) {
      return manualMuted;
    }
  }

  /// 通用播报入口：排队，不重叠。内部会查总开关、手动静音与设备静音，
  /// 任一成立即丢弃（返回 false），不进原生队列。
  /// v0.1.9：自定义服务明确开启且已填地址与 Key 时，先走自定义
  /// 路径；自定义失败时回落原生 TTS 并把原因记进 [lastError]，
  /// 不让一次自定义失败静默吞掉驾驶播报。
  Future<bool> speakText(String text) async {
    if (!settings.enabled || manualMuted) return false;
    if (text.trim().isEmpty) return false;
    if (await isMuted()) return false;
    if (usesCustomVoice) {
      final r = await _speakViaCustom(text);
      if (r.$1) return true;
      lastError = '${r.$2}，已回落原生 TTS。';
      notifyListeners();
    }
    _enqueue(text);
    return true;
  }

  /// v0.1.9 试听：不静默失败。返回 (是否发出, 原因说明)：
  /// 总开关关闭 / 手动静音 / 无引擎时直接给原因；设备静音时仍
  /// 发出试听但明确提示“可能听不到”，而不是悄悄返回 false。
  Future<(bool, String)> speakTest() async {
    if (!settings.enabled) {
      return (false, '总开关已关闭：请先开启语音播报总开关再试听。');
    }
    if (manualMuted) {
      return (false, '已手动静音：请先取消行程内静音再试听。');
    }
    final muted = await isMuted();
    final ok = await ensureAvailable();
    if (!ok) {
      return (
        false,
        '无可用语音引擎（${lastError ?? 'tts_unavailable'}）：请在系统设置中安装中文 '
            'TTS 语音数据，或在下方引擎选择器里换一个已装引擎。'
      );
    }
    _enqueue('语音播报已开启，当前语速正常。');
    if (muted) {
      return (true, '试听已发出，但设备处于静音或媒体音量为 0，当前可能听不到声音。');
    }
    return (true, '试听已播报。');
  }

  /// v0.1.9 自定义服务测试：只测用户自己填的端点，不用示例 Key。
  Future<(bool, String)> testCustomVoice() async {
    if (!customVoice.configured) {
      return (false, '请先填写接口地址与 Key（Key 只存本机，不上传）。');
    }
    final r = await _speakViaCustom('自定义语音服务测试，当前语速正常。');
    return r;
  }

  /// 通用自定义端点调用：POST JSON {"text": ...}、Bearer 鉴权，
  /// 期望返回音频流；返回 (成功, 原因)。协议不符、非音频响应、
  /// 超时、网络错误一律返回明确原因，不伪装成功。
  Future<(bool, String)> _speakViaCustom(String text) async {
    final endpoint = customVoice.endpoint.trim();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(endpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer ${customVoice.apiKey}');
        req.write(jsonEncode({'text': text}));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        final ct = resp.headers.contentType?.mimeType ?? '';
        if (resp.statusCode != 200) {
          return (false, '自定义服务返回 HTTP ${resp.statusCode}，请检查接口地址与 Key 是否正确');
        }
        if (!ct.startsWith('audio/')) {
          await resp.drain<void>();
          return (
            false,
            '自定义服务未返回音频（内容类型 $ct）：通用接口约定为 POST JSON '
                '{"text": "..."} 返回音频流，请确认该端点协议是否相符'
          );
        }
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) return (false, '自定义服务返回了空音频。');
        final ext = ct == 'audio/wav' || ct == 'audio/x-wav' ? 'wav' : 'mp3';
        final dir = await Native.getFilesDir();
        final path = '$dir/custom_voice_last.$ext';
        await File(path).writeAsBytes(bytes);
        final played = await Native.playAudioFile(path);
        if (!played) return (false, '自定义服务返回了音频，但本机播放失败。');
        return (true, '自定义服务播报成功。');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, '自定义服务调用失败：$e');
    }
  }

  /// 事件播报。速度单位：调用方传 km/h（界面与播报统一用 km/h）。
  /// 短句示例：过弯完成时 “过弯，横向 0.42g，速度 68”。
  /// 同类事件 3 秒内只播一次，防急加速连触发刷屏；圈完成与总结不节流。
  Future<bool> announceEvent({
    required VoiceEventKind kind,
    double? latG,
    double? longG,
    double? speedKmh,
    double? leanDeg,
  }) async {
    if (!settings.announceEvents) return false;
    if (kind != VoiceEventKind.lapDone) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastSpokenKindMs[kind];
      if (last != null && now - last < 3000) return false;
      _lastSpokenKindMs[kind] = now;
    }
    final g = (kind == VoiceEventKind.harshAccel ||
            kind == VoiceEventKind.harshBrake)
        ? longG
        : latG;
    final gText = g == null ? '' : '，${g.abs().toStringAsFixed(2)}g';
    final vText =
        speedKmh == null ? '' : '，速度 ${speedKmh.round()}';
    final leanText =
        leanDeg == null ? '' : '，压弯 ${leanDeg.abs().toStringAsFixed(0)}度';
    final text = switch (kind) {
      VoiceEventKind.harshAccel => '急加速$gText$vText',
      VoiceEventKind.harshBrake => '急刹车$gText$vText',
      VoiceEventKind.corner => '过弯$gText$vText',
      VoiceEventKind.leanOver => '压弯过大$leanText$vText',
      VoiceEventKind.lapDone => '过弯完成$vText',
    };
    return speakText(text);
  }

  /// 每圈完成播报。lapMs 为毫秒；isBest 为 true 时追加“最快圈”。
  Future<bool> announceLap({
    required int lapNumber,
    required int lapMs,
    bool isBest = false,
  }) async {
    if (!settings.announceLaps) return false;
    final best = isBest ? '，最快圈' : '';
    return speakText('第 $lapNumber 圈完成，${_fmtDuration(lapMs, withMillis: true)}$best');
  }

  /// 行程结束总结播报。score 为 0~100 的驾驶评分；bestLapMs 为 null
  /// 时不提最快圈（非赛道行程就没有最快圈，不得编一个）。
  Future<bool> announceSummary({
    required double distanceKm,
    required int durationMs,
    required double score,
    int? bestLapMs,
  }) async {
    if (!settings.announceSummary) return false;
    final best =
        bestLapMs == null ? '' : '，最快圈 ${_fmtDuration(bestLapMs)}';
    return speakText(
        '行程结束，共 ${distanceKm.toStringAsFixed(1)} 公里，'
        '用时 ${_fmtDuration(durationMs)}，评分 ${score.round()} 分$best');
  }

  /// 随时静音并取消：清队列 + 停原生当前播报。调用方“静音”按钮调这个。
  Future<void> cancelAll() async {
    _queue.clear();
    _watchdog?.cancel();
    _watchdog = null;
    _speaking = false;
    try {
      await Native.ttsStop();
    } catch (_) {}
    notifyListeners();
  }

  /// 手动静音开关（只影响本服务，不改系统音量）。
  void setManualMuted(bool v) {
    manualMuted = v;
    if (v) {
      unawaited(cancelAll());
    }
    notifyListeners();
  }

  void _enqueue(String text) {
    _listenTtsEvents();
    _queue.add(_QueuedSpeech(text, 'dt_${++_seq}'));
    _pump();
  }

  void _listenTtsEvents() {
    _ttsSub ??= Native.ttsStream.listen((e) {
      final type = e['type'] as String? ?? '';
      if (type == 'done' || type == 'error') {
        _watchdog?.cancel();
        _watchdog = null;
        _speaking = false;
        if (type == 'error') lastError = 'tts_speak_error';
        _pump();
      }
    }, onError: (_) {});
  }

  Future<void> _pump() async {
    if (_speaking || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    _speaking = true;
    notifyListeners();
    try {
      await Native.ttsSetRate(settings.rate);
      await Native.ttsSetPitch(settings.pitch);
      await Native.ttsSetVolume(settings.volume);
      final r = await Native.ttsSpeak(next.text, utteranceId: next.utteranceId)
          .timeout(const Duration(seconds: 10),
              onTimeout: () => {'ok': false, 'error': 'tts_timeout'});
      if ((r['ok'] as bool?) != true) {
        // 原生明确失败（如无引擎）：不静默假装，记错误并推进下一条。
        lastError = (r['error'] as String?) ?? 'tts_speak_failed';
        _speaking = false;
        notifyListeners();
        _pump();
        return;
      }
      // 看门狗：30 秒内无 done/error 回执则强制推进，防卡队列。
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 30), () {
        _speaking = false;
        lastError = 'tts_timeout';
        notifyListeners();
        _pump();
      });
    } catch (e) {
      lastError = 'tts_speak_failed';
      _speaking = false;
      notifyListeners();
      _pump();
    }
  }

  static String _fmtDuration(int ms, {bool withMillis = false}) {
    if (ms < 0) ms = 0;
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    final base = minutes == 0 ? '$seconds秒' : '$minutes分$seconds秒';
    if (!withMillis || millis == 0) return base;
    return '$base$millis毫秒';
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _ttsSub?.cancel();
    super.dispose();
  }
}
