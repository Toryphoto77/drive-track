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
    '振动 / 静音模式下照常播报，只有媒体音量为 0 时才不播报。';

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

  /// 是否播报分段 Delta：赛道模式过 S1/S2 分段点时，播报本段相对
  /// 本节最快圈同段的差值（快/慢零点几秒）。默认 true；仅赛道模式、
  /// 仅有真实分段点、仅已有最快圈参照时触发，每圈最多两次；
  /// 分段差值小于 0.1 秒时不播（无信息量）。
  final bool announceSectors;

  /// 是否播报行程结束总结。默认 true。
  final bool announceSummary;

  /// 是否播报开始语音：开始记录时的安全注意事项 + 倒数报数，
  /// 两项共用这一个开关。默认 true；旧配置文件无此键时同样默认 true。
  final bool announceStart;

  /// 是否播报 GPS 信号：外接 GPS 断开回落手机定位、手机 GPS
  /// 信号丢失与恢复。默认 true；仅街道模式播报。
  final bool announceGps;

  /// 是否播报起步提示：开始记录后第一次拿到有效定位时播报
  /// “定位已就绪”。默认 true；仅街道模式播报。
  final bool announceFirstFix;

  /// 是否播报超速提醒：车速超过 [speedLimitKmh] 时播报。
  /// 默认 true；仅街道模式播报。
  final bool announceSpeeding;

  /// 超速提醒阈值（km/h），20 ~ 200，默认 120（高速限速）。
  /// 骑行一般用不到，可把开关关掉或把阈值调低。
  final double speedLimitKmh;

  /// 是否播报里程与时间：每 5 公里、每 10 分钟各播报一次。
  /// 默认 true；仅街道模式播报。
  final bool announceMilestones;

  /// 是否播报低精度提醒：定位精度差（水平精度 > 50 米）时播报，
  /// 精度恢复后不再重复。默认 true；仅街道模式播报。
  final bool announceLowAccuracy;

  const VoiceSettings({
    required this.enabled,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.announceEvents,
    required this.announceLaps,
    required this.announceSectors,
    required this.announceSummary,
    required this.announceStart,
    required this.announceGps,
    required this.announceFirstFix,
    required this.announceSpeeding,
    required this.speedLimitKmh,
    required this.announceMilestones,
    required this.announceLowAccuracy,
  });

  /// 默认值：总开关开启，其余全部开启，语速/音调 1.0，音量 1.0，
  /// 超速阈值 120 km/h。
  static const defaults = VoiceSettings(
    enabled: true,
    rate: 1.0,
    pitch: 1.0,
    volume: 1.0,
    announceEvents: true,
    announceLaps: true,
    announceSectors: true,
    announceSummary: true,
    announceStart: true,
    announceGps: true,
    announceFirstFix: true,
    announceSpeeding: true,
    speedLimitKmh: 120,
    announceMilestones: true,
    announceLowAccuracy: true,
  );

  VoiceSettings copyWith({
    bool? enabled,
    double? rate,
    double? pitch,
    double? volume,
    bool? announceEvents,
    bool? announceLaps,
    bool? announceSectors,
    bool? announceSummary,
    bool? announceStart,
    bool? announceGps,
    bool? announceFirstFix,
    bool? announceSpeeding,
    double? speedLimitKmh,
    bool? announceMilestones,
    bool? announceLowAccuracy,
  }) =>
      VoiceSettings(
        enabled: enabled ?? this.enabled,
        rate: _clamp(rate ?? this.rate, 0.5, 2.0),
        pitch: _clamp(pitch ?? this.pitch, 0.5, 2.0),
        volume: _clamp(volume ?? this.volume, 0.0, 1.0),
        announceEvents: announceEvents ?? this.announceEvents,
        announceLaps: announceLaps ?? this.announceLaps,
        announceSectors: announceSectors ?? this.announceSectors,
        announceSummary: announceSummary ?? this.announceSummary,
        announceStart: announceStart ?? this.announceStart,
        announceGps: announceGps ?? this.announceGps,
        announceFirstFix: announceFirstFix ?? this.announceFirstFix,
        announceSpeeding: announceSpeeding ?? this.announceSpeeding,
        speedLimitKmh:
            _clamp(speedLimitKmh ?? this.speedLimitKmh, 20, 200),
        announceMilestones: announceMilestones ?? this.announceMilestones,
        announceLowAccuracy: announceLowAccuracy ?? this.announceLowAccuracy,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'announceEvents': announceEvents,
        'announceLaps': announceLaps,
        'announceSectors': announceSectors,
        'announceSummary': announceSummary,
        'announceStart': announceStart,
        'announceGps': announceGps,
        'announceFirstFix': announceFirstFix,
        'announceSpeeding': announceSpeeding,
        'speedLimitKmh': speedLimitKmh,
        'announceMilestones': announceMilestones,
        'announceLowAccuracy': announceLowAccuracy,
      };

  static VoiceSettings fromJson(Map<String, dynamic> j) => VoiceSettings(
        enabled: (j['enabled'] as bool?) ?? true,
        rate: _clamp((j['rate'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        pitch: _clamp((j['pitch'] as num?)?.toDouble() ?? 1.0, 0.5, 2.0),
        volume: _clamp((j['volume'] as num?)?.toDouble() ?? 1.0, 0.0, 1.0),
        announceEvents: (j['announceEvents'] as bool?) ?? true,
        announceLaps: (j['announceLaps'] as bool?) ?? true,
        announceSectors: (j['announceSectors'] as bool?) ?? true,
        announceSummary: (j['announceSummary'] as bool?) ?? true,
        announceStart: (j['announceStart'] as bool?) ?? true,
        announceGps: (j['announceGps'] as bool?) ?? true,
        announceFirstFix: (j['announceFirstFix'] as bool?) ?? true,
        announceSpeeding: (j['announceSpeeding'] as bool?) ?? true,
        speedLimitKmh:
            _clamp((j['speedLimitKmh'] as num?)?.toDouble() ?? 120, 20, 200),
        announceMilestones: (j['announceMilestones'] as bool?) ?? true,
        announceLowAccuracy: (j['announceLowAccuracy'] as bool?) ?? true,
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
///
/// v1.4.x：新增提供方 'openai'（OpenAI TTS）、'azure'（Azure
/// AI Speech）、'google'（Google Cloud TTS）、'minimax'（MiniMax
/// T2A v2）、'elevenlabs'（ElevenLabs）、'fish'（Fish Audio）、
/// 'doubao'（火山引擎豆包语音合成 V3）、'cosyvoice'（阿里
/// CosyVoice / DashScope）。接的标准与核实口径：HTTP REST +
/// API Key 认证 + 返回音频（mp3 直出 / JSON 内嵌 base64 / 十六进制
/// / 音频下载链接均可），零新增 pub 包（dart:io HttpClient）。
/// 各家端点、模型、音色均以官方文档为准（见各常量注释）；
/// 未接 Edge Read Aloud：它没有公开 REST 接口，是 WebSocket +
/// 浏览器内置 token 的非官方逆向协议，不符合接的标准。
class CustomVoiceConfig {
  final bool enabled;
  final String endpoint;
  final String apiKey;

  /// 提供方：'generic'（通用接口，默认）、'mimo'（小米 MiMo）、
  /// 'openai'、'azure'、'google'、'minimax'、'elevenlabs'、
  /// 'fish'、'doubao'、'cosyvoice'。
  final String provider;

  /// MiMo 音色（仅 provider == 'mimo' 时用），默认 '冰糖'。
  final String mimoVoice;

  /// 各提供方的音色 / 音色 ID（voice 字段，通用）：
  /// - openai/azure/google/minimax/doubao：音色名（下拉选，留空用默认）；
  /// - elevenlabs：voice_id（留空用默认音色 Rachel）；fish：reference_id
  ///   （留空用模型默认音色）；cosyvoice：voice（留空用默认音色）。
  /// 克隆 / Design 音色一律不在 App 内训练：先去各家网页控制台
  /// 生成，拿到 voice_id / reference_id / speaker 填进来就能用。
  final String voice;

  const CustomVoiceConfig({
    this.enabled = false,
    this.endpoint = '',
    this.apiKey = '',
    this.provider = 'generic',
    this.mimoVoice = '冰糖',
    this.voice = '',
  });

  bool get isMimo => provider == 'mimo';

  /// 需要用户手填端点的提供方：通用接口与 Azure（Azure 端点含
  /// 区域，形如 https://<区域>.tts.speech.microsoft.com/cognitiveservices/v1，
  /// 由用户按自己资源的区域填；其余提供方端点固定写死）。
  bool get needsEndpoint => provider == 'generic' || provider == 'azure';

  /// 各提供方“已配好”的判定（只看必填项）：
  /// - mimo / openai / google / minimax / elevenlabs / fish /
  ///   doubao / cosyvoice：只需 Key（端点固定；音色留空有默认）；
  /// - generic / azure：需地址与 Key 都填。
  bool get configured {
    if (isMimo) return apiKey.isNotEmpty;
    if (needsEndpoint) {
      return endpoint.trim().isNotEmpty && apiKey.isNotEmpty;
    }
    return apiKey.isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'provider': provider,
        'mimoVoice': mimoVoice,
        'voice': voice,
      };

  static CustomVoiceConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CustomVoiceConfig();
    return CustomVoiceConfig(
      enabled: (j['enabled'] as bool?) ?? false,
      endpoint: (j['endpoint'] as String?) ?? '',
      apiKey: (j['apiKey'] as String?) ?? '',
      provider: (j['provider'] as String?) ?? 'generic',
      mimoVoice: (j['mimoVoice'] as String?) ?? '冰糖',
      voice: (j['voice'] as String?) ?? '',
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

/// v1.4.x 新增提供方：端点、模型与音色（官方文档口径，见各注释）。
/// 全部走 dart:io HttpClient 发 HTTP 请求，零新增 pub 包；
/// 失败时一律回落原生 TTS（见 [_speakViaCustom] 调用方）。

/// OpenAI TTS：POST /v1/audio/speech，Bearer 鉴权，JSON
/// {model, input, voice, response_format}，回包为 mp3 音频流
/// （platform.openai.com/docs/guides/text-to-speech）。
const openAiTtsEndpoint = 'https://api.openai.com/v1/audio/speech';
const openAiTtsModel = 'tts-1';

/// OpenAI tts-1 可用音色（官方文档音色表；gpt-4o-mini-tts 的
/// ash/ballad/coral/marin/sage/verse 不列入，tts-1 不支持）。
const openAiTtsVoices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];

/// OpenAI TTS 非流式请求体（纯函数，可单测）。
Map<String, Object> openAiTtsRequest(String text, String voice) => {
      'model': openAiTtsModel,
      'input': text,
      'voice': voice,
      'response_format': 'mp3',
    };

/// Google Cloud TTS：POST /v1/text:synthesize，API Key 走
/// X-goog-api-key 请求头，JSON {input, voice, audioConfig}，
/// 回包 JSON 的 audioContent 为 base64 mp3
/// （cloud.google.com/text-to-speech/docs/how-to）。
const googleTtsEndpoint = 'https://texttospeech.googleapis.com/v1/text:synthesize';

/// Google Cloud TTS 中文（普通话）音色：languageCode 一律 cmn-CN
/// （voice 名即 cmn-CN-Standard/Wavenet-*，官方音色表）。
const googleTtsVoices = [
  'cmn-CN-Standard-A',
  'cmn-CN-Standard-B',
  'cmn-CN-Wavenet-A',
  'cmn-CN-Wavenet-B',
];

/// Google Cloud TTS 请求体（纯函数，可单测）。
Map<String, Object> googleTtsRequest(String text, String voice) => {
      'input': {'text': text},
      'voice': {'languageCode': 'cmn-CN', 'name': voice},
      'audioConfig': {'audioEncoding': 'MP3'},
    };

/// 从 Google Cloud TTS 回包里取 base64 音频；结构不对返回 null。
String? googleAudioDataFromJson(Map<String, dynamic> json) {
  try {
    final data = json['audioContent'];
    if (data is String && data.isNotEmpty) return data;
  } catch (_) {}
  return null;
}

/// Azure AI Speech：POST https://<区域>.tts.speech.microsoft.com/
/// cognitiveservices/v1，Ocp-Apim-Subscription-Key 鉴权，
/// 请求体为 SSML（application/ssml+xml），回包为 mp3 音频流
/// （learn.microsoft.com/azure/ai-services/speech-service/rest-text-to-speech）。
/// 端点含区域，无法写死，由用户按自己资源的区域填进 endpoint。
/// 输出格式固定 audio-24khz-48kbitrate-mono-mp3。
const azureTtsOutputFormat = 'audio-24khz-48kbitrate-mono-mp3';

/// Azure 中文（普通话）神经网络音色（官方语言与音色支持表）。
const azureTtsVoices = [
  'zh-CN-XiaoxiaoNeural',
  'zh-CN-YunyangNeural',
  'zh-CN-YunjianNeural',
  'zh-CN-YunxiNeural',
  'zh-CN-XiaoyiNeural',
  'zh-CN-XiaochenNeural',
];

/// Azure SSML 请求体（纯函数，可单测）：文本先转义 XML 特殊字符。
String azureSsml(String text, String voice) =>
    "<speak version='1.0' xml:lang='zh-CN'>"
    "<voice xml:lang='zh-CN' name='$voice'>${_xmlEscape(text)}</voice></speak>";

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// MiniMax T2A v2：POST https://api.minimax.io/v1/t2a_v2，
/// Bearer 鉴权，JSON {model, text, voice_setting, audio_setting,
/// output_format}，回包 JSON：data.audio 为 hex 编码 mp3
/// （非 base64，见 [_hexDecode]），base_resp.status_code 非 0
/// 即错误（platform.minimax.io/docs/api-reference/speech-t2a-http）。
/// 国内 Key 与海外 Key 的区域端点不同：本 App 用 api.minimax.io；
/// 若 Key 是 api.minimaxi.com 区域签发的，需走通用接口自填端点。
const minimaxTtsEndpoint = 'https://api.minimax.io/v1/t2a_v2';
const minimaxTtsModel = 'speech-02-hd';

/// MiniMax 系统音色（官方系统音色表口径；克隆音色填自己的 voice_id）。
const minimaxTtsVoices = ['male-qn-qingse', 'Chinese (Mandarin)_Crisp_Girl'];

/// MiniMax T2A v2 请求体（纯函数，可单测）。
Map<String, Object> minimaxTtsRequest(String text, String voice) => {
      'model': minimaxTtsModel,
      'text': text,
      'voice_setting': {'voice_id': voice},
      'audio_setting': {'format': 'mp3', 'sample_rate': 32000},
      'output_format': 'hex',
    };

/// 从 MiniMax 回包里取 hex 音频；结构不对返回 null。
/// 另须查 base_resp.status_code（见 [_speakViaMiniMax]）。
String? minimaxAudioHexFromJson(Map<String, dynamic> json) {
  try {
    final data = json['data'];
    if (data is! Map) return null;
    final audio = data['audio'];
    if (audio is String && audio.isNotEmpty) return audio;
  } catch (_) {}
  return null;
}

/// ElevenLabs：POST /v1/text-to-speech/{voice_id}，
/// xi-api-key 请求头鉴权（不是 Bearer），JSON {text, model_id,
/// output_format}，回包为 mp3 音频流（elevenlabs.io/docs）。
/// voice_id 必须先在 ElevenLabs 网页控制台拿到：内置音色在
/// 语音库里点进详情复制，克隆音色（Instant Voice Cloning）
/// 上传样本后生成、Voice Design 设计后生成，都是同一个 voice_id
/// 用法；App 内不做训练、不调 Voice Design 生成接口。
const elevenLabsTtsBase = 'https://api.elevenlabs.io/v1/text-to-speech';
const elevenLabsTtsModel = 'eleven_multilingual_v2';

/// ElevenLabs 默认音色：官方文档示例里的 Rachel（voice_id，
/// 不是 Key；用户可在设置页换成自己的 / 克隆的 voice_id）。
const elevenLabsDefaultVoiceId = '21m00Tcm4TlvDq8ikWAM';

/// ElevenLabs TTS 请求体（纯函数，可单测）。
Map<String, Object> elevenLabsTtsRequest(String text) => {
      'text': text,
      'model_id': elevenLabsTtsModel,
      'output_format': 'mp3_44100_128',
    };

/// Fish Audio：POST https://api.fish.audio/v1/tts，Bearer 鉴权，
/// 模型走 `model` 请求头（s2.1-pro），JSON {text, reference_id,
/// format, latency}，回包为分块 mp3 音频流
/// （docs.fish.audio/api-reference/endpoint/openapi-v1/text-to-speech）。
/// reference_id 是语音模型 _id：先在 Fish Audio 网页端语音库 /
/// 自己的模型里复制填进来；留空用模型默认音色。零样本克隆
/// （references 字段 inline 音频）须用 MessagePack 体，本 App
/// 只走 JSON，故不支持 inline 克隆——克隆请先在网页端建模型。
const fishTtsEndpoint = 'https://api.fish.audio/v1/tts';
const fishTtsModel = 's2.1-pro';

/// Fish Audio TTS 请求体（纯函数，可单测；referenceId 为空时不传该键）。
Map<String, Object> fishTtsRequest(String text, String referenceId) => {
      'text': text,
      if (referenceId.isNotEmpty) 'reference_id': referenceId,
      'format': 'mp3',
      'latency': 'normal',
    };

/// 火山引擎豆包语音合成 V3（单向流式 HTTP）：
/// POST https://openspeech.bytedance.com/api/v3/tts/unidirectional，
/// X-Api-Key 鉴权（控制台 API Key 管理处获取），X-Api-Resource-Id
/// 指明模型资源，JSON {user, req_params{text, speaker,
/// audio_params{format, sample_rate}}}，回包为流式 mp3 音频
/// （docs.volcengine.com/docs/doubao-voice/unidirectional-streaming-text-to-speech-http）。
/// speaker 是音色 ID（控制台音色库获取；声音复刻音色以 S_ 开头，
/// 复刻音色须把 resource 换成 seed-icl-1.0，见 [doubaoTtsResourceFor])。
/// 响应帧格式未在文档页正文里写死：本 App 按音频流优先解析，
/// JSON/SSE 形态作兜底（见 [doubaoAudioFromBytes]），失败时
/// 明确报错回落原生 TTS，需用户拿真实 Key 实测确认。
const doubaoTtsEndpoint = 'https://openspeech.bytedance.com/api/v3/tts/unidirectional';
const doubaoTtsResource = 'seed-tts-2.0';
const doubaoTtsCloneResource = 'seed-icl-1.0';

/// 豆包官方 2.0 音色（官方文档示例里的 speaker）。
const doubaoTtsVoices = [
  'zh_female_vv_uranus_bigtts',
  'zh_female_shuangkuaisisi_moon_bigtts',
  'zh_female_gaolengyujie_uranus_bigtts',
  'zh_female_xiaohe_uranus_bigtts',
];

/// 豆包音色对应的资源 ID：S_ 开头为声音复刻音色，用
/// seed-icl-1.0；其余官方音色用 seed-tts-2.0（纯函数，可单测）。
String doubaoTtsResourceFor(String speaker) =>
    speaker.startsWith('S_') ? doubaoTtsCloneResource : doubaoTtsResource;

/// 豆包 V3 请求体（纯函数，可单测）。
Map<String, Object> doubaoTtsRequest(String text, String speaker) => {
      'user': {'uid': 'drivetrack'},
      'req_params': {
        'text': text,
        'speaker': speaker,
        'audio_params': {'format': 'mp3', 'sample_rate': 24000},
      },
    };

/// 从豆包 V3 回包字节里取 mp3 音频（纯函数，可单测）：
/// 1) Content-Type 是 audio/* → 原样当音频；
/// 2) 以 '{' 开头 → 尝试 JSON 内嵌 base64 音频（data/audio/audio_data）；
/// 3) 以 'data:' 开头 → SSE 行，每行 JSON 里的 base64 音频拼接；
/// 4) 其余 → 原样当音频。都取不到返回 null。
/// （响应帧格式是本家唯一未在官方文档页正文里写死的细节，
/// 见 [doubaoTtsEndpoint] 注释；解析失败时调用方明确报错。）
List<int>? doubaoAudioFromBytes(List<int> bytes, String contentType) {
  if (bytes.isEmpty) return null;
  if (contentType.startsWith('audio/')) return bytes;
  final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
  if (text.startsWith('{')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final b64 = _base64AudioFromJson(decoded);
        if (b64 != null) {
          try {
            return base64Decode(b64);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }
  if (text.startsWith('data:')) {
    final out = <int>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('data:')) continue;
      final payload = t.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final b64 = _base64AudioFromJson(decoded);
          if (b64 != null) {
            try {
              out.addAll(base64Decode(b64));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return out.isEmpty ? null : out;
  }
  return bytes;
}

/// 在 JSON 里找 base64 音频字段（data / audio / audio_data / data.audio）。
String? _base64AudioFromJson(Map<String, dynamic> json) {
  for (final key in const ['data', 'audio', 'audio_data']) {
    final v = json[key];
    if (v is String && v.isNotEmpty) return v;
  }
  final data = json['data'];
  if (data is Map) {
    final v = data['audio'];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

/// 阿里 CosyVoice（DashScope 百炼 HTTP 接口）：
/// POST https://cn-beijing.maas.qwencloudapi.com/api/v1/services/audio/tts/SpeechSynthesizer，
/// Bearer 鉴权（DashScope API Key），JSON {model, input{text,
/// voice, format}}，回包 JSON 的 output.audio.url 是完整音频
/// 文件链接（24 小时有效），需再 GET 下载（docs.qwencloud.com
/// CosyVoice HTTP API）。仅华北 2（北京）地域可用，Key 与地域
/// 绑定（北京 Key 才能调北京端点）。voice 是音色 ID：系统音色
/// 见百炼音色列表；克隆 / Voice Design 音色先在百炼控制台
/// 生成，再把绑定的目标模型音色 ID 填进来。
const cosyVoiceTtsEndpoint =
    'https://cn-beijing.maas.qwencloudapi.com/api/v1/services/audio/tts/SpeechSynthesizer';
const cosyVoiceTtsModel = 'cosyvoice-v3-flash';

/// CosyVoice 默认音色：官方 HTTP 文档 curl 示例里的 longanyang。
const cosyVoiceDefaultVoice = 'longanyang';

/// CosyVoice 请求体（纯函数，可单测）。
Map<String, Object> cosyVoiceTtsRequest(String text, String voice) => {
      'model': cosyVoiceTtsModel,
      'input': {'text': text, 'voice': voice, 'format': 'mp3'},
    };

/// 从 CosyVoice 回包里取音频下载链接；结构不对返回 null。
String? cosyVoiceAudioUrlFromJson(Map<String, dynamic> json) {
  try {
    final output = json['output'];
    if (output is! Map) return null;
    final audio = output['audio'];
    if (audio is! Map) return null;
    final url = audio['url'];
    if (url is String && url.isNotEmpty) return url;
  } catch (_) {}
  return null;
}

/// 从 CosyVoice 回包里取内嵌 base64 音频（非流式时一般为空，
/// 有则优先用，不用再下载链接）；取不到返回 null。
String? cosyVoiceAudioDataFromJson(Map<String, dynamic> json) {
  try {
    final output = json['output'];
    if (output is! Map) return null;
    final audio = output['audio'];
    if (audio is! Map) return null;
    final data = audio['data'];
    if (data is String && data.isNotEmpty) return data;
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

  // --- 街道模式新增语音（v1.4.x）：状态只在行程内有效，
  // [setTripActive] 开录时清零、结束时停看门狗并清零。 ---
  /// GPS 信号看门狗：每 5 秒查一次，超 10 秒无新定位即判信号丢失。
  Timer? _gpsWatchdog;

  /// 行程是否进行中（开录 true、结束 false）；赛道行程不跑街道提示。
  bool _tripActive = false;
  bool _tripIsTrack = false;

  /// 最近一次有效定位（行程内 [noteStreetLocation] 调用）的时刻。
  int _lastFixMs = 0;

  /// GPS 丢失状态位：已报丢失、等恢复播报时为 true。
  bool _gpsLost = false;

  /// 起步提示是否已播过（每行程一次）。
  bool _firstFixAnnounced = false;

  /// 超速播报状态：超阈值中为 true，降回阈值以下 5 km/h 即复位；
  /// 持续超速时每 60 秒最多补报一次。
  bool _speedingActive = false;
  int _lastSpeedingMs = 0;

  /// 下一个里程 / 时间整点：每 5 公里、每 10 分钟各播一次。
  double _nextMilestoneKm = 5;
  int _nextMilestoneMin = 10;

  /// 低精度状态位：进入低精度时播一次，持续低精度每 120 秒
  /// 最多补报一次，精度恢复（≤ 30 米）即复位。
  bool _lowAccuracyActive = false;
  int _lastLowAccuracyMs = 0;

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
      return (false, '总开关已关闭，请先开启语音播报总开关。');
    }
    if (manualMuted) {
      return (false, '已手动静音，请先取消行程内静音。');
    }
    final muted = await isMuted();
    final ok = await ensureAvailable();
    if (!ok) {
      return (
        false,
        '无可用语音引擎：请在系统设置中安装中文 '
            'TTS 语音数据，或换一个已装引擎。'
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
        '试听超时：引擎可能无响应，'
            '请点“重新探测”后再试。'
      );
    }
    if (result.$1 == 'done') {
      if (muted) {
        return (
          true,
          '试听完成，但媒体音量为 0，当前听不到声音，'
              '请调大媒体音量。'
        );
      }
      return (true, '试听完成。');
    }
    final detail =
        result.$3 != null ? '（${result.$3}）' : '';
    return (
      false,
      '试听失败$detail，请换一个已装引擎或点“重新探测”后再试。'
    );
  }

  /// v0.1.9 自定义服务测试：只测用户自己填的端点，不用示例 Key。
  Future<(bool, String)> testCustomVoice() async {
    if (!customVoice.configured) {
      return (
        false,
        switch (customVoice.provider) {
          'mimo' =>
            '请先填写小米 MiMo 的 API Key（小米 MiMo 开放平台申请，只存本机）。',
          'azure' =>
            '请先填写 Azure 区域端点与资源 Key（Azure 门户 Speech 资源页获取，只存本机）。',
          'generic' => '请先填写接口地址与 Key（Key 只存本机）。',
          _ => '请先填写该提供方的 API Key（只存本机）。',
        }
      );
    }
    final r = await _speakViaCustom('自定义语音服务测试，当前语速正常。');
    return r;
  }

  /// 自定义语音分发：MiMo 走 [_speakViaMimo]，OpenAI / Azure /
  /// Google / MiniMax / ElevenLabs / Fish / 豆包 / CosyVoice
  /// 各走自己的方法，其余走通用端点。任一失败都由调用方
  /// （[speakText] / [testCustomVoice]）回落原生 TTS 或明示原因。
  Future<(bool, String)> _speakViaCustom(String text) async {
    switch (customVoice.provider) {
      case 'mimo':
        return _speakViaMimo(text);
      case 'openai':
        return _speakViaOpenAi(text);
      case 'azure':
        return _speakViaAzure(text);
      case 'google':
        return _speakViaGoogle(text);
      case 'minimax':
        return _speakViaMiniMax(text);
      case 'elevenlabs':
        return _speakViaElevenLabs(text);
      case 'fish':
        return _speakViaFish(text);
      case 'doubao':
        return _speakViaDoubao(text);
      case 'cosyvoice':
        return _speakViaCosyVoice(text);
      default:
        return _speakViaGeneric(text);
    }
  }

  /// 从云端错误回包正文里取可读原因后缀：依次找
  /// error.message / error / message / detail.message / detail /
  /// base_resp.status_msg；取不到时给“请检查 Key 是否正确”。
  String _cloudErrorSuffix(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = _cloudErrorFromJson(decoded);
        if (detail != null) return '：$detail';
      }
    } catch (_) {}
    return '，请检查 Key 是否正确';
  }

  /// 从云端错误 JSON 里取可读原因；取不到返回 null。
  String? _cloudErrorFromJson(Map<String, dynamic> json) {
    try {
      final error = json['error'];
      if (error is Map) {
        final msg = error['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      } else if (error is String && error.isNotEmpty) {
        return error;
      }
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
      final detail = json['detail'];
      if (detail is Map) {
        final msg = detail['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      } else if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      final baseResp = json['base_resp'];
      if (baseResp is Map) {
        final msg = baseResp['status_msg'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return null;
  }

  /// 云端音频落盘并播放（新提供方共用）：先写文件、再核对播报世代、
  /// 最后经原生播放；任一步失败都返回明确原因（调用方回落原生 TTS）。
  Future<(bool, String)> _saveAndPlayAudio(
      List<int> bytes, String ext, int epoch, String label) async {
    if (bytes.isEmpty) return (false, '$label 返回了空音频。');
    final dir = await Native.getFilesDir();
    final path = '$dir/custom_voice_last.$ext';
    await File(path).writeAsBytes(bytes);
    if (epoch != _speechEpoch) {
      // HTTP 期间倒计时已进入：这段安全播报不再播，不与倒数报数重叠。
      return (false, '已被倒计时打断，不再播放。');
    }
    final played = await Native.playAudioFile(path);
    if (!played) return (false, '$label 返回了音频，但本机播放失败。');
    return (true, '$label 播报成功。');
  }

  /// 十六进制解码（MiniMax 回包的音频是 hex 编码，不是 base64）：
  /// 每两个 hex 字符一个字节；格式不对返回 null。
  List<int>? _hexDecode(String hex) {
    final s = hex.trim();
    if (s.isEmpty || s.length.isOdd) return null;
    final out = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      final b = int.tryParse(s.substring(i, i + 2), radix: 16);
      if (b == null) return null;
      out.add(b);
    }
    return out;
  }

  /// OpenAI TTS 调用：POST /v1/audio/speech，Bearer 鉴权，
  /// 回包为 mp3 音频流；失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaOpenAi(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) return (false, '请先填写 OpenAI 的 API Key（只存本机）。');
    final voice = openAiTtsVoices.contains(customVoice.voice)
        ? customVoice.voice
        : 'alloy';
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(openAiTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $key');
        req.write(jsonEncode(openAiTtsRequest(text, voice)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          final body = await resp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
          return (false, 'OpenAI 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}');
        }
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'OpenAI');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'OpenAI 调用失败：$e');
    }
  }

  /// Azure AI Speech 调用：POST 用户填的区域端点，
  /// Ocp-Apim-Subscription-Key 鉴权，SSML 请求体，
  /// 回包为 mp3 音频流；失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaAzure(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    final endpoint = customVoice.endpoint.trim();
    if (key.isEmpty || endpoint.isEmpty) {
      return (false, '请先填写 Azure 区域端点与资源 Key（只存本机）。');
    }
    final voice = azureTtsVoices.contains(customVoice.voice)
        ? customVoice.voice
        : 'zh-CN-XiaoxiaoNeural';
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(endpoint));
        req.headers.set('Content-Type', 'application/ssml+xml');
        req.headers.set('Ocp-Apim-Subscription-Key', key);
        req.headers.set('X-Microsoft-OutputFormat', azureTtsOutputFormat);
        req.write(azureSsml(text, voice));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          await resp.drain<void>();
          return (
            false,
            'Azure 返回 HTTP ${resp.statusCode}，请检查区域端点与 Key 是否正确'
          );
        }
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'Azure');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'Azure 调用失败：$e');
    }
  }

  /// Google Cloud TTS 调用：POST /v1/text:synthesize，
  /// X-goog-api-key 请求头鉴权，回包 JSON 的 audioContent
  /// 为 base64 mp3；失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaGoogle(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写 Google Cloud 的 API Key（只存本机）。');
    }
    final voice = googleTtsVoices.contains(customVoice.voice)
        ? customVoice.voice
        : 'cmn-CN-Standard-A';
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(googleTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('X-goog-api-key', key);
        req.write(jsonEncode(googleTtsRequest(text, voice)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          return (false, 'Google 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}');
        }
        final decoded = jsonDecode(body);
        final data = decoded is Map<String, dynamic>
            ? googleAudioDataFromJson(decoded)
            : null;
        if (data == null) {
          return (false, 'Google 未返回音频数据，请检查音色是否可用。');
        }
        late final List<int> bytes;
        try {
          bytes = base64Decode(data);
        } catch (_) {
          return (false, 'Google 返回的音频解码失败。');
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'Google');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'Google 调用失败：$e');
    }
  }

  /// MiniMax T2A v2 调用：POST /v1/t2a_v2，Bearer 鉴权，
  /// 回包 JSON 的 data.audio 为 hex 编码 mp3；HTTP 200 也可能
  /// 在 base_resp 里带错误，须查 status_code；失败原因如实返回。
  Future<(bool, String)> _speakViaMiniMax(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) return (false, '请先填写 MiniMax 的 API Key（只存本机）。');
    final voice = customVoice.voice.trim().isEmpty
        ? 'male-qn-qingse'
        : customVoice.voice.trim();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(minimaxTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $key');
        req.write(jsonEncode(minimaxTtsRequest(text, voice)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          return (false, 'MiniMax 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return (false, 'MiniMax 返回格式不对，请检查 Key 是否正确。');
        }
        final baseResp = decoded['base_resp'];
        if (baseResp is Map) {
          final code = (baseResp['status_code'] as num?)?.toInt() ?? -1;
          if (code != 0) {
            final msg = baseResp['status_msg'];
            return (
              false,
              'MiniMax 返回错误${msg is String && msg.isNotEmpty ? '：$msg' : ''}，请检查 Key 与音色是否正确'
            );
          }
        }
        final hex = minimaxAudioHexFromJson(decoded);
        if (hex == null) {
          return (false, 'MiniMax 未返回音频数据，请检查音色是否可用。');
        }
        final bytes = _hexDecode(hex);
        if (bytes == null) {
          return (false, 'MiniMax 返回的音频解码失败。');
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'MiniMax');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'MiniMax 调用失败：$e');
    }
  }

  /// ElevenLabs 调用：POST /v1/text-to-speech/{voice_id}，
  /// xi-api-key 请求头鉴权，回包为 mp3 音频流；
  /// 失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaElevenLabs(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写 ElevenLabs 的 API Key（只存本机）。');
    }
    final voiceId = customVoice.voice.trim().isEmpty
        ? elevenLabsDefaultVoiceId
        : customVoice.voice.trim();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final url =
            '$elevenLabsTtsBase/${Uri.encodeComponent(voiceId)}';
        final req = await client.postUrl(Uri.parse(url));
        req.headers.contentType = ContentType.json;
        req.headers.set('xi-api-key', key);
        req.headers.set('Accept', 'audio/mpeg');
        req.write(jsonEncode(elevenLabsTtsRequest(text)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          final body = await resp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
          return (
            false,
            'ElevenLabs 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}'
          );
        }
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'ElevenLabs');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'ElevenLabs 调用失败：$e');
    }
  }

  /// Fish Audio 调用：POST /v1/tts，Bearer 鉴权，模型走 `model`
  /// 请求头（s2.1-pro），回包为分块 mp3 音频流；
  /// 失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaFish(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写 Fish Audio 的 API Key（只存本机）。');
    }
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(fishTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $key');
        req.headers.set('model', fishTtsModel);
        req.write(
            jsonEncode(fishTtsRequest(text, customVoice.voice.trim())));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          final body = await resp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
          return (
            false,
            'Fish Audio 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}'
          );
        }
        final bytes = <int>[];
        await for (final chunk in resp) {
          bytes.addAll(chunk);
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'Fish Audio');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'Fish Audio 调用失败：$e');
    }
  }

  /// 火山引擎豆包语音合成 V3 调用：POST /api/v3/tts/unidirectional，
  /// X-Api-Key 鉴权，X-Api-Resource-Id 指明模型资源，
  /// 回包为流式 mp3 音频（JSON/SSE 形态作兜底，见
  /// [doubaoAudioFromBytes]）；失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaDoubao(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写豆包语音的 API Key（只存本机）。');
    }
    final speaker = customVoice.voice.trim().isEmpty
        ? 'zh_female_vv_uranus_bigtts'
        : customVoice.voice.trim();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(doubaoTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('X-Api-Key', key);
        req.headers.set('X-Api-Resource-Id', doubaoTtsResourceFor(speaker));
        req.headers.set('X-Api-Request-Id',
            'dt-${DateTime.now().millisecondsSinceEpoch}-${++_seq}');
        req.write(jsonEncode(doubaoTtsRequest(text, speaker)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          final body = await resp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 10));
          return (
            false,
            '豆包语音返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}'
          );
        }
        final raw = <int>[];
        await for (final chunk in resp) {
          raw.addAll(chunk);
        }
        final bytes = doubaoAudioFromBytes(
            raw, resp.headers.contentType?.mimeType ?? '');
        if (bytes == null) {
          return (false, '豆包语音未返回可解析的音频，请检查 Key 与音色是否正确。');
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, '豆包语音');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, '豆包语音调用失败：$e');
    }
  }

  /// 阿里 CosyVoice 调用：POST 百炼 SpeechSynthesizer，
  /// Bearer 鉴权（DashScope API Key），回包 JSON 的
  /// output.audio.url 是音频下载链接，需再 GET 下载；
  /// 失败原因如实返回，不伪装成功。
  Future<(bool, String)> _speakViaCosyVoice(String text) async {
    final epoch = _speechEpoch;
    final key = customVoice.apiKey;
    if (key.isEmpty) {
      return (false, '请先填写 DashScope 的 API Key（只存本机）。');
    }
    final voice = customVoice.voice.trim().isEmpty
        ? cosyVoiceDefaultVoice
        : customVoice.voice.trim();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.postUrl(Uri.parse(cosyVoiceTtsEndpoint));
        req.headers.contentType = ContentType.json;
        req.headers.set('Authorization', 'Bearer $key');
        req.write(jsonEncode(cosyVoiceTtsRequest(text, voice)));
        final resp = await req.close().timeout(const Duration(seconds: 30));
        final body = await resp
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          return (
            false,
            'CosyVoice 返回 HTTP ${resp.statusCode}${_cloudErrorSuffix(body)}'
          );
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return (false, 'CosyVoice 返回格式不对，请检查 Key 是否正确。');
        }
        final inline = cosyVoiceAudioDataFromJson(decoded);
        if (inline != null) {
          late final List<int> bytes;
          try {
            bytes = base64Decode(inline);
          } catch (_) {
            return (false, 'CosyVoice 返回的音频解码失败。');
          }
          return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'CosyVoice');
        }
        final url = cosyVoiceAudioUrlFromJson(decoded);
        if (url == null) {
          final detail = _cloudErrorFromJson(decoded);
          return (
            false,
            'CosyVoice 未返回音频链接${detail == null ? '，请检查 Key 与音色是否正确' : '：$detail'}'
          );
        }
        final audioReq = await client.getUrl(Uri.parse(url));
        final audioResp =
            await audioReq.close().timeout(const Duration(seconds: 30));
        if (audioResp.statusCode != 200) {
          await audioResp.drain<void>();
          return (false, 'CosyVoice 音频下载失败（HTTP ${audioResp.statusCode}）。');
        }
        final bytes = <int>[];
        await for (final chunk in audioResp) {
          bytes.addAll(chunk);
        }
        return await _saveAndPlayAudio(bytes, 'mp3', epoch, 'CosyVoice');
      } finally {
        client.close();
      }
    } catch (e) {
      return (false, 'CosyVoice 调用失败：$e');
    }
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
            '自定义服务未返回音频：请确认该端点协议是否相符'
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
  /// [deltaVsBestMs] 为本圈相对此前最快圈的差值（毫秒，正 = 更慢）：
  /// 非最快圈且差值 ≥ 100 毫秒时追加“比最快圈慢 X.X 秒”，
  /// 无此前最快圈（首个计入圈）或差值过小时不追加，不编数。
  /// 最快圈本身只报“最快圈”，不另报差值。
  Future<bool> announceLap({
    required int lapNumber,
    required int lapMs,
    bool isBest = false,
    int? deltaVsBestMs,
  }) async {
    if (!settings.announceLaps) return false;
    if (isBest) {
      return speakText(
          '第 $lapNumber 圈完成，${_fmtDuration(lapMs, withMillis: true)}，最快圈');
    }
    final delta = deltaVsBestMs != null && deltaVsBestMs >= 100
        ? '，比最快圈慢 ${(deltaVsBestMs / 1000).toStringAsFixed(1)} 秒'
        : '';
    return speakText(
        '第 $lapNumber 圈完成，${_fmtDuration(lapMs, withMillis: true)}$delta');
  }

  /// 分段 Delta 播报（赛道模式）：过 S1/S2 分段点时报本段相对
  /// 最快圈同段的差值，负 = 更快、正 = 更慢；差值绝对值小于
  /// 100 毫秒时不播。调用方（main.dart _drainLapTimer）只在
  /// 真实分段点 + 已有最快圈参照时调。
  Future<bool> announceSector({
    required int sectorIndex,
    required int deltaMs,
  }) async {
    if (!settings.announceSectors) return false;
    if (deltaMs.abs() < 100) return false;
    final dir = deltaMs < 0 ? '快' : '慢';
    return speakText(
        'S${sectorIndex + 1} $dir ${(deltaMs.abs() / 1000).toStringAsFixed(1)} 秒');
  }

  /// 发车圈第一次穿越起终点、开始计时时播一次（赛道模式）。
  /// 与开始记录时的倒数“开始”不同：记录可能在维修区起步，
  /// 本播报只在真正开始计时那一刻报。共用圈速播报开关。
  Future<bool> announceTimingStarted() async {
    if (!settings.announceLaps) return false;
    return speakText('开始计时，第一圈');
  }

  /// 外接 GPS 定位心跳：只刷新 GPS 看门狗的最近定位时刻；
  /// 看门狗已报丢失时同样播恢复。超速 / 里程 / 低精度仍只走
  /// [noteStreetLocation]（手机定位回调），避免 25Hz 外接流
  /// 重复触发街道播报。调用方在外接定位落点后调一次。
  void noteExternalFix() {
    if (!_tripActive || _tripIsTrack) return;
    _lastFixMs = DateTime.now().millisecondsSinceEpoch;
    if (_gpsLost) {
      _gpsLost = false;
      unawaited(announceGpsRestored());
    }
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

  /// 行程开始 / 结束时由调用方（main.dart）调：开录即清零街道
  /// 播报状态并启动 GPS 信号看门狗，结束即停看门狗。
  /// 赛道行程只计圈，不跑街道提示（[noteStreetLocation] 内同样门控）。
  void setTripActive(bool active, {bool isTrack = false}) {
    _gpsWatchdog?.cancel();
    _gpsWatchdog = null;
    _tripActive = active;
    _tripIsTrack = isTrack;
    _lastFixMs =
        active ? DateTime.now().millisecondsSinceEpoch : 0;
    _gpsLost = false;
    _firstFixAnnounced = false;
    _speedingActive = false;
    _lastSpeedingMs = 0;
    _nextMilestoneKm = 5;
    _nextMilestoneMin = 10;
    _lowAccuracyActive = false;
    _lastLowAccuracyMs = 0;
    if (active) {
      _gpsWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_tripActive || _tripIsTrack) return;
        if (_lastFixMs == 0 || _gpsLost) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastFixMs > 10000) {
          _gpsLost = true;
          unawaited(announceGpsLost());
        }
      });
    }
    notifyListeners();
  }

  /// 街道模式定位事件入口：调用方（main.dart 定位回调）在记录中
  /// 每次拿到定位都调一次，数据全部取自真实定位与轨迹，不编信号。
  /// 只处理街道模式；赛道模式直接返回（圈速播报走 announceLap）。
  /// - 起步提示：本行程第一次拿到有效定位时播一次；
  /// - GPS 恢复：看门狗已报丢失后、再次拿到定位时播一次；
  /// - 超速：超过阈值播一次，持续超速每 60 秒最多补报一次，
  ///   降回阈值以下 5 km/h 复位；
  /// - 里程 / 时间：每 5 公里、每 10 分钟各播一次；
  /// - 低精度：水平精度 > 50 米时播一次，持续低精度每 120 秒
  ///   最多补报一次，精度恢复（≤ 30 米）复位；精度未知
  ///   （≥ 900 米为占位值）时不播、不复位。
  void noteStreetLocation({
    required double speedKmh,
    required double hAcc,
    required double distanceKm,
    required int elapsedMs,
  }) {
    if (!_tripActive || _tripIsTrack) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastFixMs = now;
    if (_gpsLost) {
      _gpsLost = false;
      unawaited(announceGpsRestored());
    }
    if (!_firstFixAnnounced) {
      _firstFixAnnounced = true;
      unawaited(announceFirstFix());
    }
    if (speedKmh < settings.speedLimitKmh - 5) {
      _speedingActive = false;
    } else if (settings.announceSpeeding &&
        speedKmh > settings.speedLimitKmh) {
      if (!_speedingActive || now - _lastSpeedingMs >= 60000) {
        _speedingActive = true;
        _lastSpeedingMs = now;
        unawaited(
            speakText('超速，当前时速 ${speedKmh.round()} 公里'));
      }
    }
    if (settings.announceMilestones) {
      if (distanceKm >= _nextMilestoneKm) {
        unawaited(speakText('已行驶 ${_nextMilestoneKm.round()} 公里'));
        _nextMilestoneKm += 5;
      }
      if (elapsedMs >= _nextMilestoneMin * 60000) {
        unawaited(speakText('已用时 $_nextMilestoneMin 分钟'));
        _nextMilestoneMin += 10;
      }
    }
    if (hAcc > 50 && hAcc < 900) {
      if (!_lowAccuracyActive) {
        _lowAccuracyActive = true;
        _lastLowAccuracyMs = now;
        unawaited(announceLowAccuracy());
      } else if (now - _lastLowAccuracyMs >= 120000) {
        _lastLowAccuracyMs = now;
        unawaited(announceLowAccuracy());
      }
    } else if (hAcc > 0 && hAcc <= 30) {
      _lowAccuracyActive = false;
    }
  }

  /// 外接 GPS 断开回落：5 秒无新定位、切回手机定位时播一次
  /// （调用方在回落处调，只在街道模式、记录中调）。
  Future<bool> announceGpsFallback() async {
    if (!settings.announceGps) return false;
    return speakText('外接 GPS 信号丢失，已切回手机定位');
  }

  /// 手机 GPS 信号丢失：看门狗 10 秒无新定位时播一次。
  Future<bool> announceGpsLost() async {
    if (!settings.announceGps) return false;
    return speakText('GPS 信号丢失，正在等待定位');
  }

  /// GPS 信号恢复：丢失后再次拿到定位时播一次。
  Future<bool> announceGpsRestored() async {
    if (!settings.announceGps) return false;
    return speakText('GPS 信号已恢复');
  }

  /// 起步提示：开始记录后第一次拿到有效定位时播一次。
  Future<bool> announceFirstFix() async {
    if (!settings.announceFirstFix) return false;
    return speakText('定位已就绪');
  }

  /// 低精度提醒：定位精度差时播报，精度恢复后不再重复。
  Future<bool> announceLowAccuracy() async {
    if (!settings.announceLowAccuracy) return false;
    return speakText('定位精度较低，轨迹可能有偏差');
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
    _gpsWatchdog?.cancel();
    _ttsSub?.cancel();
    super.dispose();
  }
}
