// 小米 MiMo 语音接入测试：只测纯函数与配置编解码，不发真实网络请求。
import 'package:drive_track/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mimo chat request', () {
    test('target text goes to assistant message, wav + voice passthrough', () {
      final req = mimoChatRequest('急刹车，速度 68', '茉莉');
      expect(req['model'], mimoTtsModel);
      final messages = req['messages'] as List;
      expect(messages.length, 1);
      final msg = messages.first as Map;
      expect(msg['role'], 'assistant');
      expect(msg['content'], '急刹车，速度 68');
      final audio = req['audio'] as Map;
      expect(audio['format'], 'wav');
      expect(audio['voice'], '茉莉');
    });

    test('endpoint is the fixed mimo chat completions url', () {
      expect(mimoTtsEndpoint,
          'https://api.xiaomimimo.com/v1/chat/completions');
    });
  });

  group('mimo response parsing', () {
    test('valid response yields base64 audio data', () {
      final data = mimoAudioDataFromJson({
        'choices': [
          {
            'message': {
              'audio': {'data': 'UklGRg=='}
            }
          }
        ]
      });
      expect(data, 'UklGRg==');
    });

    test('missing choices / audio / empty data yields null', () {
      expect(mimoAudioDataFromJson({}), isNull);
      expect(mimoAudioDataFromJson({'choices': []}), isNull);
      expect(
          mimoAudioDataFromJson({
            'choices': [
              {'message': {}}
            ]
          }),
          isNull);
      expect(
          mimoAudioDataFromJson({
            'choices': [
              {
                'message': {
                  'audio': {'data': ''}
                }
              }
            ]
          }),
          isNull);
    });

    test('error message passthrough, missing yields null', () {
      expect(
          mimoErrorFromJson({
            'error': {'message': 'invalid api key'}
          }),
          'invalid api key');
      expect(mimoErrorFromJson({}), isNull);
    });
  });

  group('custom voice config provider', () {
    test('mimo round-trip keeps provider and voice', () {
      const c = CustomVoiceConfig(
          enabled: true, apiKey: 'k', provider: 'mimo', mimoVoice: '苏打');
      final back = CustomVoiceConfig.fromJson(c.toJson());
      expect(back.provider, 'mimo');
      expect(back.mimoVoice, '苏打');
      expect(back.isMimo, isTrue);
    });

    test('old json without provider defaults to generic + 冰糖', () {
      final back = CustomVoiceConfig.fromJson(
          {'enabled': false, 'endpoint': 'https://x', 'apiKey': 'k'});
      expect(back.provider, 'generic');
      expect(back.mimoVoice, '冰糖');
      expect(back.isMimo, isFalse);
    });

    test('configured: mimo needs key only, generic needs endpoint + key', () {
      expect(
          const CustomVoiceConfig(apiKey: 'k', provider: 'mimo').configured,
          isTrue);
      expect(const CustomVoiceConfig(provider: 'mimo').configured, isFalse);
      expect(
          const CustomVoiceConfig(endpoint: 'https://x', apiKey: 'k')
              .configured,
          isTrue);
      expect(const CustomVoiceConfig(apiKey: 'k').configured, isFalse);
    });
  });
}
