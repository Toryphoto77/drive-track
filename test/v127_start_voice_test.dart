// 开始语音测试：安全播报口播文本、开始语音开关门控、倒数报数节拍与取消。
// TTS 全部用 MethodChannel fake，不依赖真机引擎、不发真实网络请求。
import 'package:drive_track/countdown_page.dart';
import 'package:drive_track/main.dart' show safetySpeechText;
import 'package:drive_track/models.dart' show TripMode;
import 'package:drive_track/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _spoken = <String>[];
var _stopCalls = 0;

void _installMocks() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('drivetrack/native'),
    (call) async {
      switch (call.method) {
        case 'audioMuted':
          return {'muted': false, 'ringerMode': 'normal', 'musicVolume': 10};
        case 'ttsSpeak':
          final args = call.arguments as Map;
          _spoken.add(args['text'] as String);
          // 模拟原生播完回调：没有 done 回执，VoiceService 的队列会
          // 永远卡在 _speaking=true，后续报数入队后也播不出来
          // （生产环境原生每条播完都会回 done）。
          final uid = args['utteranceId'] as String?;
          if (uid != null) {
            Future.microtask(() {
              TestDefaultBinaryMessengerBinding
                  .instance.defaultBinaryMessenger
                  .handlePlatformMessage(
                'drivetrack/tts',
                const StandardMethodCodec().encodeSuccessEnvelope(
                  {'type': 'done', 'utteranceId': uid},
                ),
                (_) {},
              );
            });
          }
          return {'ok': true};
        case 'ttsStop':
          _stopCalls++;
          return null;
        default:
          return null;
      }
    },
  );
  // TTS 完成事件流：测试里不发 done/error，队列靠 cancelAll 推进；
  // listen/cancel 直接回空，不抛 MissingPluginException。
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('drivetrack/tts'),
    (call) async => null,
  );
}

Future<void> _resetVoice() async {
  final svc = VoiceService.instance;
  await svc.cancelAll();
  svc.settings = VoiceSettings.defaults;
  svc.manualMuted = false;
  _spoken.clear();
  _stopCalls = 0;
}

Future<void> _flushSpeech() async {
  // 让 _pump 里的几次 mock 通道调用跑完（均为立即返回的 Future）。
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async {
    _installMocks();
    await _resetVoice();
  });

  tearDown(() async {
    await VoiceService.instance.cancelAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('drivetrack/native'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/tts'), null);
  });

  group('safety speech text', () {
    test('car street: red declarations verbatim + compressed rest', () {
      expect(
        safetySpeechText(TripMode.car),
        '安全提醒：不要在公开道路上追逐竞技驾驶，不要超速驾驶。'
        '手机已固定，行车中不操作手机，已系好安全带，车况已检查。'
        '开录后界面锁定，只留暂停和结束。',
      );
    });

    test('car track: track-only red declaration', () {
      expect(
        safetySpeechText(TripMode.car, isTrack: true),
        '安全提醒：仅在正规封闭赛道使用。'
        '手机已固定，行车中不操作手机，已系好安全带，车况已检查。'
        '开录后界面锁定，只留暂停和结束。',
      );
    });

    test('moto street and track', () {
      expect(
        safetySpeechText(TripMode.moto),
        '安全提醒：不要在公开道路上追逐竞技驾驶，不要超速驾驶。'
        '头盔、手套已戴好，支架已锁紧，行车中不操作手机，车况已检查。'
        '开录后界面锁定，只留暂停和结束。',
      );
      expect(
        safetySpeechText(TripMode.moto, isTrack: true),
        '安全提醒：仅在正规封闭赛道使用。'
        '头盔、手套已戴好，支架已锁紧，行车中不操作手机，车况已检查。'
        '开录后界面锁定，只留暂停和结束。',
      );
    });

    test('bike', () {
      expect(
        safetySpeechText(TripMode.bike),
        '安全提醒：不要在公开道路上追逐竞技驾驶，不要超速驾驶。'
        '头盔已戴好，刹车轮胎已检查，夜骑灯光已准备，骑行中不操作手机。'
        '开录后界面锁定，只留暂停和结束。',
      );
    });
  });

  group('announceStart switch', () {
    test('round-trip keeps false, missing key defaults true', () {
      final off = VoiceSettings.defaults.copyWith(announceStart: false);
      expect(VoiceSettings.fromJson(off.toJson()).announceStart, isFalse);
      expect(VoiceSettings.fromJson({}).announceStart, isTrue);
      expect(VoiceSettings.defaults.announceStart, isTrue);
    });

    test('switch off: safety and countdown both silent', () async {
      VoiceService.instance.settings =
          VoiceSettings.defaults.copyWith(announceStart: false);
      expect(await VoiceService.instance.speakSafety('安全提醒测试'), isFalse);
      expect(await VoiceService.instance.speakCountdown('3'), isFalse);
      await _flushSpeech();
      expect(_spoken, isEmpty);
    });

    test('switch on: safety goes through native queue', () async {
      expect(
          await VoiceService.instance
              .speakSafety(safetySpeechText(TripMode.car)),
          isTrue);
      await _flushSpeech();
      expect(_spoken, [safetySpeechText(TripMode.car)]);
    });

    test('same safety text within 10s is spoken only once', () async {
      const text = '去重测试安全播报';
      expect(await VoiceService.instance.speakSafety(text), isTrue);
      expect(await VoiceService.instance.speakSafety(text), isFalse);
      await _flushSpeech();
      expect(_spoken, [text]);
    });
  });

  group('countdown voice', () {
    test('beginCountdown stops in-flight speech, numbers follow', () async {
      expect(
          await VoiceService.instance.speakSafety('倒计时打断测试文本'), isTrue);
      await _flushSpeech();
      expect(_spoken, ['倒计时打断测试文本']);
      await VoiceService.instance.beginCountdown();
      expect(_stopCalls, 1);
      expect(await VoiceService.instance.speakCountdown('3'), isTrue);
      await _flushSpeech();
      expect(_spoken, ['倒计时打断测试文本', '3']);
    });

    testWidgets('page speaks 3-2-1-开始 on the visual beat', (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: CountdownPage(
          onFinish: () => finished = true,
          vibrationEnabled: false,
          speakCountdown: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_spoken, ['3']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_spoken, ['3', '2']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_spoken, ['3', '2', '1']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_spoken, ['3', '2', '1', '开始']);
      await tester.pump(const Duration(milliseconds: 800));
      expect(finished, isTrue);
    });

    testWidgets('cancel stops in-flight countdown speech', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(MaterialApp(
        home: CountdownPage(
          onFinish: () {},
          onCancel: () => cancelled = true,
          vibrationEnabled: false,
          speakCountdown: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_spoken, ['3', '2']);
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(cancelled, isTrue);
      expect(_stopCalls, greaterThan(0));
    });

    testWidgets('speakCountdown false: fully silent, no stop call',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CountdownPage(
          onFinish: () {},
          vibrationEnabled: false,
          speakCountdown: false,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_spoken, isEmpty);
      expect(_stopCalls, 0);
    });
  });
}
