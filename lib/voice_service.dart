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
/// - 静音（v1.2.1 已修正）：播报前先查 [isMuted]，只看媒体音量
///   是否为 0。TTS 走媒体流 STREAM_MUSIC，振动/静音响铃模式下
///   照常播报，不再悄悄丢弃。旧文案“仅在非静音模式播报”已删除，
///   改由 [voiceMuteRuleNote] 如实说明该规则，UI 不得自己另编一套说法。
/// - 语言（v1.2.1）：原生按 zh_CN → zh → zh_TW → 系统默认顺序试，
///   [ttsLanguage] 存最终选中的语言代码原样（如 zh_CN），不再只写
///   zh/default；中文可用当且仅当该代码以 zh 开头（见
///   [ttsChineseAvailable]）。
/// - 首选引擎（v1.2.1）：[preferredTtsEngine] 持久化进
///   voice_settings.json，[load] 时恢复并在首次 TTS 初始化前经
///   原生 ttsApplyPreferredEngine 传给原生；所选引擎不在已装列表
///   时 [loadEngines] 置 [preferredEngineMissing] 并回退系统默认。
/// - 试听（v1.2.1）：[speakTest] 不再入队即报成功，改为等待单条
///   utterance 的原生 done/error 回调（超时约 8 秒），返回播完 /
///   引擎报错（带原生错误码）/ 超时无回调三种明确结果。
/// - 本服务不读系统通知权限、不申请麦克风：TTS 是输出，不是录音。
/// - 无 TTS 引擎时原生返回 ok=false + error，Dart 侧不静默假装播了：
///   [lastError] 会被置为该错误，调用方可展示“设备无语音引擎”。

/// 调用方展示的播报规则文案（原样展示）：振动 / 静音模式下照常
/// 播报，只有媒体音量为 0 时才不播报。旧的 voiceMutedNote
/// （“仅在非静音模式播报”）已在 v1.2.1 删除，那是误导文案。
const String voiceMuteRuleNote =
    '振动 / 静音模式下照常播报：TTS 走媒体音量，只有媒体音量为 0 时才不播报。';

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

  /// 是否播报开始语音：开始记录时的安全注意事项 + 倒数报数，
  /// 两项共用这一个开关。默认 true；旧配置文件无此键时同样默认 true。
  final bool announceStart;

  const VoiceSettings({
    required this.enabled,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.announceEvents,
    required this.announceLaps,
    required this.announceSummary,
    required this.announceStart,
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
    announceStart: true,
  );

  VoiceSettings copyWith({
    bool? enabled,
    double? rate,
    double? pitch,
    double? volume,
    bool? announceEvents,
    bool? announceLaps,
    bool? announceSummary,
    bool? announceStart,
  }) =>
      VoiceSettings(
        enabled: enabled ?? this.enabled,
        rate: _clamp(rate ?? this.rate, 0.5, 2.0),
        pitch: _clamp(pitch ?? this.pitch, 0.5, 2.0),
        volume: _clamp(volume ?? this.volume, 0.0, 1.0),
        announceEvents: announceEvents ?? this.announceEvents,
        announceLaps: announceLaps ?? this.announceLaps,
        announceSummary: announceSummary ?? this.announceSummary,
        announceStart: announceStart ?? this.announceStart,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'announceEvents': announceEvents,
        'announceLaps': announceLaps,
        'announceSummary': announceSummary,
        'announceStart': announceStart,
      };

  static VoiceSettings fromJson(Map<String, dynamic> j) => VoiceSettings(
        enabled: (j['enabled'] as bool?) ?? true,
        rate: _clamp((j['rate'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        pitch: _clamp((j['pitch'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        volume: _clamp((j['volume'] as num?)?.toDouble() ?? 1.0, 0.0, 1.0),
        announceEvents: (j['announceEvents'] as bool?) ?? true,
        announceLaps: (j['announceLaps'] as bool?) ?? true,
        announceSummary: (j['announceSummary'] as bool?) ?? true,
        announceStart: (j['announceStart'] as bool?) ?? true,
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
///
/// v1.2.5：新增提供方 'mimo'（小米 MiMo-V2.5-TTS 云端模型，
/// OpenAI 兼容接口，见 [mimoChatRequest]）。MiMo 不是系统 TTS
/// 引擎、也不是通用接口：它要求 POST chat/completions、目标文本
/// 放在 assistant 消息里、回包是 JSON 内嵌 base64 音频——按通用
/// 接口填必然报“未返回音频”，这就是用户“填写会报错”的根因。
/// MiMo 的 Key 须用户在小米 MiMo 开放平台自行申请，本 App 不
/// 内置任何 Key、不预填；端点固定写死，不让用户手填。
class CustomVoiceConfig {
  final bool enabled;
  final String endpoint;
  final String apiKey;

  /// 提供方：'generic'（通用接口，默认）或 'mimo'（小米 MiMo）。
  final String provider;

  /// MiMo 音色（仅 provider == 'mimo' 时用），默认 '冰糖'。
  final String mimoVoice;

  const CustomVoiceConfig({
    this.enabled = false,
    this.endpoint = '',
    this.apiKey = '',
    this.provider = 'generic',
    this.mimoVoice = '冰糖',
  });

  bool get isMimo => provider == 'mimo';

  /// MiMo 只需 Key（端点固定）；通用接口需地址与 Key 都填。
  bool get configured =>
      isMimo ? apiKey.isNotEmpty : endpoint.trim().isNotEmpty && apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'provider': provider,
        'mimoVoice': mimoVoice,
      };

  static CustomVoiceConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CustomVoiceConfig();
    return CustomVoiceConfig(
      enabled: (j['enabled'] as bool?) ?? false,
      endpoint: (j['endpoint'] as String?) ?? '',
      apiKey: (j['apiKey'] as String?) ?? '',
      provider: (j['provider'] as String?) ?? 'generic',
      mimoVoice: (j['mimoVoice'] as String?) ?? '冰糖',
    );
  }
}

/// 小米 MiMo-V2.5-TTS 接入点与模型（OpenAI 兼容接口，官方文档
/// mimo.mi.com 语音合成章；纯函数，可单测）。
const mimoTtsEndpoint = 'https://api.xiaomimimo.com/v1/chat/completions';
const mimoTtsModel = 'mimo-v2.5-tts';

/// MiMo 预置中文音色（官方内置音色表；mimo_default 在中国集群
/// 默认即冰糖，故默认音色取冰糖）。
const mimoTtsVoices = ['冰糖', '茉莉', '苏打', '白桦'];

/// MiMo 非流式请求体：目标文本必须放在 assistant 消息里，user
/// 消息可选（风格指令），驾驶播报不写风格指令、只传目标文本；
/// audio.format 取 wav（回包 base64 可直接存 wav 播放）。
Map<String, Object> mimoChatRequest(String text, String voice) => {
      'model': mimoTtsModel,
      'messages': [
        {'role': 'assistant', 'content': text},
      ],
      'audio': {'format': 'wav', 'voice': voice},
    };

/// 从 MiMo 非流式回包里取 base64 音频；结构不对返回 null。
String? mimoAudioDataFromJson(Map<String, dynamic> json) {
  try {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final audio = message['audio'];
    if (audio is! Map) return null;
    final data = audio['data'];
    if (data is! String || data.isEmpty) return null;
    return data;
  } catch (_) {
    return null;
  }
}

/// 从 MiMo 错误回包里取可读原因；取不到返回 null。
String? mimoErrorFromJson(Map<String, dynamic> json) {
  try {
    final error = json['error'];
    if (error is Map) {
      final msg = error['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
  } catch (_) {}
  return null;
}

/// 播报事件种类（与 models.dart 的 TripEvent.kind 对应，外加圈与压弯）。
enum VoiceEventKind {
  harshAccel,
  harshBrake,
  corner,
  leanOver,
  lapDone,
}

/// 队列里的一条语音。[epoch] 是入队时的播报世代：倒计时页进入
/// 时世代 +1，旧世代的安全播报即使在倒计时进入后才落地，也会在
/// 轮到它时直接丢弃，不与倒数报数重叠（见 [VoiceService.beginCountdown]）。
class _QueuedSpeech {
  final String text;
  final String utteranceId;
  final int epoch;
  _QueuedSpeech(this.text, this.utteranceId, this.epoch);
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

  /// v1.2.1：已保存的首选引擎包名（持久化进 voice_settings.json），
  /// null = 未保存首选，走系统默认。重启后 [load] 恢复它。
  String? preferredTtsEngine;

  /// v1.2.1：已保存的首选引擎不在已装列表时为 true（该引擎已卸载，
  /// [loadEngines] 已回退系统默认并清掉已保存首选）。
  bool preferredEngineMissing = false;

  /// 诊断用：最近一次 audioMuted 回执的响铃模式与媒体音量。
  /// 响铃模式不参与播报静音判断，只展示。
  String? audioRingerMode;
  int? audioMusicVolume;

  /// 手动静音（用户在行程中点“静音”）：为 true 时队列直接丢弃新播报，
  /// 不进原生。区别于设备静音（[isMuted] 查的是系统状态）。
  bool manualMuted = false;

  /// 最近一次原生返回的错误（如 'tts_unavailable'），无错误时为 null。
  /// 供调用方展示“设备无语音引擎，播报不可用”，不要静默吞掉。
  String? lastError;

  /// 最近一次原生 TTS 报错事件的错误码（UtteranceProgressListener
  /// onError 的 errorCode），无报错事件时为 null；供诊断页展示。
  int? lastTtsErrorCode;

  /// 原生 TTS 引擎是否可用（最后一次探测结果；未探测过为 null）。
  /// 语言：最终选中的语言代码原样（如 'zh_CN'/'zh'/'zh_TW'/
  /// 系统默认代码）/ 'none'（不可用）。v1.2.1 前的 'zh'/'default'
  /// 旧值不再产生；中文可用见 [ttsChineseAvailable]。
  bool? ttsAvailable;
  String? ttsLanguage;

  /// 最终语言是否为中文：代码以 zh 开头（zh_CN / zh / zh_TW）。
  /// 系统默认语言代码（如 en_US）即使可用也不算中文。
  bool get ttsChineseAvailable =>
      ttsLanguage != null && ttsLanguage!.startsWith('zh');

  final List<_QueuedSpeech> _queue = [];
  bool _speaking = false;
  int _seq = 0;

  /// 播报世代：倒计时页进入时 [beginCountdown] 将其 +1。安全播报
  /// 在调用时记下当时的世代，入队与自定义音频播放前都会核对：
  /// 世代已变说明倒计时已进入，该条安全播报直接丢弃，不与倒数
  /// 报数重叠。正常播报（事件/圈/总结/倒数）都在当前世代入队，
  /// 不受影响。
  int _speechEpoch = 0;

  /// 安全播报去重：同一文本 10 秒内只播一次，防重复点开始导致
  /// 同一段安全注意事项排队播两遍。取消后 10 秒内再点开始，
  /// 同样跳过（刚听过一遍，不重复打扰）。
  String? _lastSafetyText;
  int _lastSafetyAtMs = 0;

  Timer? _watchdog;
  StreamSubscription<Map<String, dynamic>>? _ttsSub;

  /// v1.2.1 试听等待者：utteranceId → (结果类型 'done'/'error',
  /// 原生错误码, 原生错误串)。试听入队前先登记，事件回调里按
  /// utteranceId 精确完成，不靠“入队即成功”。
  final Map<String, Completer<(String, int?, String?)>> _utteranceWaiters = {};
  final Map<VoiceEventKind, int> _lastSpokenKindMs = {};

  int get queueLength => _queue.length;
  bool get isSpeaking => _speaking;

  /// 加载本机语音设置；文件不存在或损坏时用默认值，不抛错。
  /// v1.2.1：恢复已保存的首选引擎，并在首次 TTS 初始化前传给
  /// 原生（原生尚未建实例时只记下 override，不提前触发默认引擎
  /// 初始化；本方法在 main.dart _init 里先于任何播报调用）。
  Future<void> load() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/$fileName');
      if (!await f.exists()) {
        settings = VoiceSettings.defaults;
        customVoice = const CustomVoiceConfig();
        preferredTtsEngine = null;
        preferredEngineMissing = false;
      } else {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        settings = VoiceSettings.fromJson(j);
        customVoice = CustomVoiceConfig.fromJson(
            (j['customVoice'] as Map?)?.cast<String, dynamic>());
        final saved = (j['preferredTtsEngine'] as String?)?.trim();
        preferredTtsEngine = (saved != null && saved.isNotEmpty) ? saved : null;
        preferredEngineMissing = false;
      }
    } catch (_) {
      settings = VoiceSettings.defaults;
      customVoice = const CustomVoiceConfig();
      preferredTtsEngine = null;
      preferredEngineMissing = false;
    }
    if (preferredTtsEngine != null) {
      try {
        await Native.ttsApplyPreferredEngine(preferredTtsEngine!);
      } catch (_) {
        // 原生未就绪不阻塞：下次 ensureAvailable / loadEngines 时
        // 仍以已保存首选为准，页面会展示实际探测结果。
      }
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/$fileName').writeAsString(jsonEncode({
            ...settings.toJson(),
            'customVoice': customVoice.toJson(),
            'preferredTtsEngine': preferredTtsEngine,
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
  /// v1.2.1：已保存的首选引擎不在已装列表（且列表非空，即不是
  /// 探测失败）时，置 [preferredEngineMissing]，清掉已保存首选并
  /// 持久化，同时把原生切回系统默认引擎；页面据此展示
  /// “该引擎已卸载，已回退系统默认”。列表为空时不判定缺失，
  /// 避免一次探测失败误删用户首选。
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
    if (preferredTtsEngine != null &&
        ttsEngineList.isNotEmpty &&
        !ttsEngineList.contains(preferredTtsEngine)) {
      preferredEngineMissing = true;
      preferredTtsEngine = null;
      ttsAvailable = null;
      await save();
      try {
        await Native.ttsSetEngine('');
      } catch (_) {}
      try {
        final r = await Native.ttsEngines();
        final raw = r['engines'];
        ttsEngineList = raw is List
            ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : <String>[];
        final cur = r['current'] as String?;
        ttsEngineCurrent = (cur != null && cur.isNotEmpty) ? cur : null;
      } catch (_) {}
    } else {
      preferredEngineMissing = false;
    }
    notifyListeners();
  }

  /// 用户在选择器里选引擎：原生切换成功才把包名持久化为首选；
  /// 切换失败不写盘，并尝试把原生恢复到切换前的首选（或系统默认），
  /// 避免本次会话残留一个建不起来的引擎、页面却谎称“已保持原引擎”。
  Future<bool> setTtsEngine(String packageName) async {
    final previousPreferred = preferredTtsEngine;
    final ok = await Native.ttsSetEngine(packageName);
    if (ok) {
      ttsEngineCurrent = packageName;
      preferredTtsEngine = packageName;
      preferredEngineMissing = false;
      ttsAvailable = null;
      await save();
      await ensureAvailable();
    } else {
      lastError = 'tts_unavailable';
      if (previousPreferred != packageName) {
        try {
          await Native.ttsSetEngine(previousPreferred ?? '');
        } catch (_) {}
        ttsEngineCurrent = previousPreferred;
        await ensureAvailable();
      }
    }
    notifyListeners();
    return ok;
  }

  /// 清除已保存的首选引擎并切回系统默认（供设置页“恢复系统默认”）。
  Future<bool> clearPreferredEngine() async {
    preferredTtsEngine = null;
    preferredEngineMissing = false;
    await save();
    final ok = await Native.ttsSetEngine('');
    await loadEngines();
    await ensureAvailable();
    notifyListeners();
    return ok;
  }

  /// 刷新诊断用的响铃模式与媒体音量（不改变播报判断）。
  Future<void> refreshAudioStatus() async {
    try {
      final r = await Native.audioMuted();
      audioRingerMode = r['ringerMode'] as String?;
      audioMusicVolume = (r['musicVolume'] as num?)?.toInt();
    } catch (_) {}
    notifyListeners();
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

  /// 播报是否会被听不到：v1.2.1 起只看媒体音量是否为 0。
  /// 振动/静音响铃模式不再算静音（TTS 走媒体流，响铃模式不影响
  /// 媒体播报）；响铃模式与媒体音量同时记进诊断字段。
  /// 调用方在行程中播报前可用它决定是否跳过；[speakText] 内部同样会查。
  Future<bool> isMuted() async {
    try {
      final r = await Native.audioMuted();
      audioRingerMode = r['ringerMode'] as String?;
      audioMusicVolume = (r['musicVolume'] as num?)?.toInt();
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
    // 调用时记下世代：自定义调用耗时（HTTP）期间若倒计时已进入，
    // 回落的原生入队仍带旧世代，轮到它时会被 _pump 直接丢弃。
    final epoch = _speechEpoch;
    if (await isMuted()) return false;
    if (usesCustomVoice) {
      final r = await _speakViaCustom(text);
      if (r.$1) return true;
      lastError = '${r.$2}，已回落原生 TTS。';
      notifyListeners();
    }
    _enqueue(text, epoch: epoch);
    return true;
  }

  /// 开始记录时的安全播报：走用户已选引擎（自定义 MiMo/通用 或
  /// 原生 TTS，与 speakText 完全相同的失败回落），受开始语音开关
  /// [VoiceSettings.announceStart] 与总开关门控。调用方一律不 await
  /// （fire-and-forget），TTS 失败绝不卡住开始记录流程。
  /// 同一文本 10 秒内重复调用直接跳过，防重复点开始导致播两遍。
  Future<bool> speakSafety(String text) async {
    if (!settings.announceStart) return false;
    if (text.trim().isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSafetyText == text && now - _lastSafetyAtMs < 10000) {
      return false;
    }
    _lastSafetyText = text;
    _lastSafetyAtMs = now;
    return speakText(text);
  }

  /// 倒数报数（3、2、1、开始）：只走原生 TTS 队列，不走自定义
  /// HTTP 路径——云端往返对不准 1 秒节拍，数字会滞后甚至堆叠；
  /// 节拍对齐优先于音色统一。受开始语音开关与总开关门控，
  /// 失败静默（内部全部 catch），绝不卡住倒计时流程。
  Future<bool> speakCountdown(String text) async {
    if (!settings.announceStart) return false;
    if (!settings.enabled || manualMuted) return false;
    if (text.trim().isEmpty) return false;
    if (await isMuted()) return false;
    _enqueue(text);
    return true;
  }

  /// 倒计时页进入时调用：停掉未播完的安全播报（清队列 + 停原生
  /// 当前播报），并推进播报世代，使此后才落地的旧安全播报
  /// （自定义音频播放前、原生入队后）直接丢弃，不与倒数报数重叠。
  /// 已在播的自定义音频文件原生侧没有停止方法，属已知残留风险：
  /// 该音频只能靠世代拦截“尚未开始播”的情形，见 _speakViaMimo /
  /// _speakViaGeneric 播放前的世代核对。
  Future<void> beginCountdown() async {
    _speechEpoch++;
    await cancelAll();
  }

  /// v1.2.1 试听：不再入队即报成功。返回 (是否播完, 结果说明)，
  /// 三种明确结果：播完（收到原生 done 回调）/ 引擎报错（带原生
  /// 错误码或原生错误串）/ 超时无回调（约 8 秒）。总开关关闭 /
  /// 手动静音 / 无引擎时直接给原因不入队；媒体音量为 0 时仍跑
  /// 试听（回调本身不受音量影响），但成功结果里明确说听不到。
  /// 自定义语音服务开启时试听仍走原生系统 TTS（测的是引擎本身）。
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
    final utteranceId = 'dt_test_${++_seq}';
    final waiter = Completer<(String, int?, String?)>();
    _utteranceWaiters[utteranceId] = waiter;
    _listenTtsEvents();
    _queue.add(
        _QueuedSpeech('语音播报已开启，当前语速正常。', utteranceId, _speechEpoch));
    _pump();
    late final (String, int?, String?) result;
    try {
      result = await waiter.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // 超时即摘掉等待者：之后姗姗来迟的回调不再翻案；该条仍可能
      // 在队列里或正在播，但绝不能把“已入队”说成“已播完”。
      _utteranceWaiters.remove(utteranceId);
      return (
        false,
        '试听超时：8 秒内未收到原生播报完成回调，引擎可能无响应或前方播报未播完，'
            '请点“重新探测”后再试。'
      );
    }
    if (result.$1 == 'done') {
      if (muted) {
        return (
          true,
          '试听完成：已收到原生播报完成回调，但媒体音量为 0，当前听不到声音，'
              '请调大媒体音量后再试。'
        );
      }
      return (true, '试听完成：已收到原生播报完成回调。');
    }
    final detail = result.$2 != null
        ? '（原生错误码：${result.$2}）'
        : (result.$3 != null ? '（${result.$3}）' : '');
    return (
      false,
      '试听失败：引擎报错$detail，请换一个已装引擎或点“重新探测”后再试。'
    );
  }

  /// v0.1.9 自定义服务测试：只测用户自己填的端点，不用示例 Key。
  Future<(bool, String)> testCustomVoice() async {
    if (!customVoice.configured) {
      return (
        false,
        customVoice.isMimo
            ? '请先填写小米 MiMo 的 API Key（小米 MiMo 开放平台申请，只存本机，不上传）。'
            : '请先填写接口地址与 Key（Key 只存本机，不上传）。'
      );
    }
    final r = await _speakViaCustom('自定义语音服务测试，当前语速正常。');
    return r;
  }

  /// 自定义语音分发：MiMo 走 [_speakViaMimo]，其余走通用端点。
  Future<(bool, String)> _speakViaCustom(String text) async {
    if (customVoice.isMimo) return _speakViaMimo(text);
    return _speakViaGeneric(text);
  }

  /// 小米 MiMo-V2.5-TTS 调用：POST chat/completions（OpenAI 兼容），
  /// 回包 JSON 内嵌 base64 wav，解码后存 wav 播放；失败原因如实
  /// 返回，不伪装成功（调用方失败时回落原生 TTS）。
  Future<(bool, String)> _speakViaMimo(String text) async {
    // 调用时记下世代：HTTP 往返期间若倒计时已进入，音频到手后也不播。
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写小米 MiMo 的 API Key（小米 MiMo 开放平台申请，只存本机）。');
    }
    final voice = mimoTtsVoices.contains(customVoice.mimoVoice)
        ? customVoice.mimoVoice
        : '冰糖';
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(mimoTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $key');
        req.write(jsonEncode(mimoChatRequest(text, voice)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          String? detail;
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>) {
              detail = mimoErrorFromJson(decoded);
            }
          } catch (_) {}
          return (
            false,
            '小米 MiMo 返回 HTTP ${resp.statusCode}'
                '${detail == null ? '，请检查 Key 是否正确' : '：$detail'}'
          );
        }
        final decoded = jsonDecode(body);
        final data = decoded is Map<String, dynamic>
            ? mimoAudioDataFromJson(decoded)
            : null;
        if (data == null) {
          return (false, '小米 MiMo 未返回音频数据，请检查模型与音色是否可用。');
        }
        late final List<int> bytes;
        try {
          bytes = base64Decode(data);
        } catch (_) {
          return (false, '小米 MiMo 返回的音频解码失败。');
        }
        if (bytes.isEmpty) return (false, '小米 MiMo 返回了空音频。');
        final dir = await Native.getFilesDir();
        final path = '$dir/custom_voice_last.wav';
        await File(path).writeAsBytes(bytes);
        if (epoch != _speechEpoch) {
          // HTTP 期间倒计时已进入：这段安全播报不再播，不与倒数报数重叠。
          return (false, '已被倒计时打断，不再播放。');
        }
        final played = await Native.playAudioFile(path);
        if (!played) return (false, '小米 MiMo 返回了音频，但本机播放失败。');
        return (true, '小米 MiMo 播报成功。');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, '小米 MiMo 调用失败：$e');
    }
  }

  /// 通用自定义端点调用：POST JSON {"text": ...}、Bearer 鉴权，
  /// 期望返回音频流；返回 (成功, 原因)。协议不符、非音频响应、
  /// 超时、网络错误一律返回明确原因，不伪装成功。
  Future<(bool, String)> _speakViaGeneric(String text) async {
    // 调用时记下世代：HTTP 往返期间若倒计时已进入，音频到手后也不播。
    final epoch = _speechEpoch;
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
        if (epoch != _speechEpoch) {
          // HTTP 期间倒计时已进入：这段安全播报不再播，不与倒数报数重叠。
          return (false, '已被倒计时打断，不再播放。');
        }
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

  void _enqueue(String text, {int? epoch}) {
    _listenTtsEvents();
    _queue.add(_QueuedSpeech(text, 'dt_${++_seq}', epoch ?? _speechEpoch));
    _pump();
  }

  void _listenTtsEvents() {
    _ttsSub ??= Native.ttsStream.listen((e) {
      final type = e['type'] as String? ?? '';
      if (type == 'done' || type == 'error') {
        _watchdog?.cancel();
        _watchdog = null;
        _speaking = false;
        final utteranceId = e['utteranceId'] as String?;
        final errorCode = (e['errorCode'] as num?)?.toInt();
        if (type == 'error') {
          lastError = 'tts_speak_error';
          lastTtsErrorCode = errorCode;
        }
        // v1.2.1：按 utteranceId 精确完成试听等待者；非试听条目
        // 不在等待表里，直接跳过，不影响队列推进。
        if (utteranceId != null) {
          final waiter = _utteranceWaiters.remove(utteranceId);
          if (waiter != null && !waiter.isCompleted) {
            waiter.complete((type, errorCode, null));
          }
        }
        _pump();
      }
    }, onError: (_) {});
  }

  void _completeWaiter(
      String utteranceId, String type, int? errorCode, String? error) {
    final waiter = _utteranceWaiters.remove(utteranceId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete((type, errorCode, error));
    }
  }

  Future<void> _pump() async {
    if (_speaking || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    if (next.epoch != _speechEpoch) {
      // 旧世代的安全播报（如倒计时进入后才落地的入队）：直接丢弃，
      // 不播、不报错，继续推进队列里的倒数报数。
      notifyListeners();
      _pump();
      return;
    }
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
        // 原生明确失败（如无引擎）：不静默假装，记错误并推进下一条；
        // 若该条是试听，立刻以报错完成等待者，不让试听等满 8 秒超时。
        lastError = (r['error'] as String?) ?? 'tts_speak_failed';
        _completeWaiter(next.utteranceId, 'error', null, lastError);
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
      _completeWaiter(next.utteranceId, 'error', null, lastError);
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
