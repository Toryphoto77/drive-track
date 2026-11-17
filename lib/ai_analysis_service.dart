import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'native.dart';

/// AI 分析配置（v1.7.0）：OpenAI 兼容接口。
///
/// 安全约定：
/// - API Key 只存本机 filesDir/ai_settings.json，不上传云端、不写日志、
///   不进崩溃日志；
/// - 只有用户在赛道分析页主动点“生成分析”时才发起请求；
/// - 未启用 / 未填全时 [usable] 为 false，调用方直接拒绝，不试连。
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
  });

  static const String defaultBaseUrl = 'https://api.openai.com/v1';
  static const String defaultModel = 'gpt-4o-mini';
  static const AiSettings defaults = AiSettings();

  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String model;

  bool get usable =>
      enabled &&
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  AiSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) => AiSettings(
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  static AiSettings fromJson(Object? value) {
    if (value is! Map) return defaults;
    return AiSettings(
      enabled: value['enabled'] == true,
      baseUrl: (value['baseUrl'] ?? defaultBaseUrl).toString(),
      apiKey: (value['apiKey'] ?? '').toString(),
      model: (value['model'] ?? defaultModel).toString(),
    );
  }
}

/// 本机配置读写；文件不存在或损坏时回默认值（不抛异常）。
class AiSettingsStore {
  static const String fileName = 'ai_settings.json';

  static Future<File> _file() async {
    final dir = await Native.getFilesDir();
    return File('$dir/$fileName');
  }

  static Future<AiSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return AiSettings.defaults;
      return AiSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return AiSettings.defaults;
    }
  }

  static Future<bool> save(AiSettings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AiAnalysisException implements Exception {
  AiAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// OpenAI 兼容 chat/completions 调用。只做一次请求，失败给出人话原因。
class AiAnalysisService {
  AiAnalysisService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// 把用户填写的 Base URL 归一成 chat/completions 端点：
  /// 已以 /chat/completions 结尾就原样用，否则补上。
  static String endpointFor(String baseUrl) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return '';
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  static String systemPrompt({required bool zh}) {
    if (zh) {
      return '你是 DriveTrack 的赛道数据分析助手。你只能依据用户提供的 JSON 实测数据回答，'
          '不得使用常识补出任何数值。数据里没有的通道（例如转向角、油门、刹车、转速、水温、胎温、'
          '赛道限速、其他车手成绩）必须明确写“未接入/无数据”，绝不能猜测或编造具体数字。'
          '回答用中文，简洁分点：1) 本次表现总结（引用圈速与关键数据）；2) 分析圈相对参照圈的主要得失'
          '（引用速度差与弯角数据）；3) 最多 3 条可执行的改进点；4) 一句数据局限说明。'
          '所有数字必须来自输入 JSON，不得自造。';
    }
    return 'You are DriveTrack race-analysis assistant. Answer ONLY from the provided JSON '
        'telemetry facts and never invent numbers. Channels absent from the data '
        '(steering angle, throttle, brake, RPM, coolant, tyre temperature, track limits, '
        'other drivers) must be explicitly reported as unavailable. Reply in English with '
        'short sections: 1) session summary with quoted numbers; 2) key gains/losses of the '
        'analysed lap vs reference; 3) at most 3 actionable improvements; 4) one line on data '
        'limits. Every number must come from the input JSON.';
  }

  /// 生成分析文本。[factsJson] 调用方保证只含实测事实。
  Future<String> analyze({
    required AiSettings settings,
    required String factsJson,
    required bool zh,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!settings.usable) {
      throw AiAnalysisException(
        'AI 未配置：请先在 设置 → AI 分析 里填写 Base URL、API Key 与模型。',
      );
    }
    final endpoint = endpointFor(settings.baseUrl);
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw AiAnalysisException('Base URL 不正确，需要 http(s):// 开头的地址。');
    }

    final payload = <String, dynamic>{
      'model': settings.model.trim(),
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': systemPrompt(zh: zh)},
        {
          'role': 'user',
          'content':
              '以下是本次实测数据（JSON）：\n$factsJson\n'
              '请严格基于这些数据做分析。',
        },
      ],
    };

    try {
      final request = await _client.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${settings.apiKey.trim()}',
      );
      final body = utf8.encode(jsonEncode(payload));
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiAnalysisException(
          'AI 服务返回 HTTP ${response.statusCode}：${_shortBody(text)}',
        );
      }
      final decoded = jsonDecode(text);
      final content = decoded is Map
          ? (decoded['choices'] is List &&
                    (decoded['choices'] as List).isNotEmpty &&
                    (decoded['choices'] as List).first is Map)
                ? ((decoded['choices'] as List).first as Map)['message']
                : null
          : null;
      final result = content is Map
          ? content['content']?.toString().trim()
          : null;
      if (result == null || result.isEmpty) {
        throw AiAnalysisException('AI 返回内容为空，请检查模型名是否支持 chat/completions。');
      }
      return result;
    } on AiAnalysisException {
      rethrow;
    } on TimeoutException {
      throw AiAnalysisException('AI 请求超时，请检查网络后重试。');
    } on SocketException {
      throw AiAnalysisException('无法连接 AI 服务，请检查 Base URL 与网络。');
    } on FormatException {
      throw AiAnalysisException('AI 返回格式无法解析（不是 OpenAI 兼容响应）。');
    } catch (e) {
      // 不把 Key 或请求头带进错误文案。
      throw AiAnalysisException('AI 请求失败：$e');
    }
  }

  static String _shortBody(String body) {
    final t = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 240 ? '${t.substring(0, 240)}…' : t;
  }

  void close() => _client.close(force: true);
}
