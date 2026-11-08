import 'dart:async';

import 'package:drive_track/device_center.dart';
import 'package:drive_track/obd_service.dart';
import 'package:drive_track/recorder.dart';
import 'package:drive_track/tunnel_gap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake OBD 平台：按命令回固定响应行（不依赖真蓝牙）。
class FakeObdPlatform implements ObdPlatform {
  final _responses = StreamController<String>.broadcast();
  final _connected = StreamController<void>.broadcast();
  final _disconnected = StreamController<String>.broadcast();

  final List<String> sentCommands = [];
  int connectCount = 0;
  bool emitConnectedEvent = true;

  List<Map<String, dynamic>> paired = [
    {
      'address': 'AA:BB:CC:DD:EE:FF',
      'name': 'ELM327',
      'type': '已配对经典蓝牙',
    },
  ];

  @override
  Stream<String> get responses => _responses.stream;

  @override
  Stream<void> get connected => _connected.stream;

  @override
  Stream<String> get disconnected => _disconnected.stream;

  @override
  Future<List<Map<String, dynamic>>> listPaired() async => paired;

  @override
  Future<void> connect(String address) async {
    connectCount++;
    if (emitConnectedEvent) {
      Timer.run(() => _connected.add(null));
    }
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendCommand(String command) async {
    sentCommands.add(command);
    for (final line in _responseFor(command)) {
      _responses.add(line);
    }
  }

  List<String> _responseFor(String cmd) {
    switch (cmd) {
      case 'ATZ':
        return ['ELM327 v1.5', '>'];
      case '010D':
        // 带回显：解析必须去回显，只取 41 0D 帧。
        return ['010D', '41 0D 3C', '>'];
      case '010C':
        return ['41 0C 1A F8', '>'];
      case '0111':
        return ['41 11 80', '>'];
      case '0105':
        return ['41 05 5A', '>'];
      default:
        return ['OK', '>'];
    }
  }

  void simulateDisconnect(String reason) => _disconnected.add(reason);

  void dispose() {
    _responses.close();
    _connected.close();
    _disconnected.close();
  }
}

ObdService testService(FakeObdPlatform fake, {Recorder? recorder}) =>
    ObdService(
      platform: fake,
      recorder: recorder,
      // 关掉后台轮询：测试手动单步 pollSpeedOnce / pollSlowOnce。
      speedPollInterval: const Duration(hours: 1),
      slowPollInterval: const Duration(hours: 1),
    );

void main() {
  group('parseElmResponse', () {
    test('车速 41 0D 3C = 60 km/h', () {
      expect(parseElmResponse('41 0D 3C').speedKmh, 60);
    });

    test('去回显：010D 回显 + 41 0D 3C 仍得 60', () {
      final r = parseElmResponse('010D\r41 0D 3C\r\r>');
      expect(r.speedKmh, 60);
      expect(r.errorKind, isNull);
    });

    test('多帧：后帧覆盖前帧', () {
      expect(parseElmResponse('41 0D 3C 41 0D 3D').speedKmh, 61);
    });

    test('转速 41 0C 1A F8 = 1726 rpm', () {
      expect(parseElmResponse('41 0C 1A F8').rpm, 1726);
    });

    test('油门 41 11 80 ≈ 50%', () {
      expect(parseElmResponse('41 11 80').throttlePct, closeTo(50.2, 0.05));
    });

    test('水温 41 05 5A = 50 ℃', () {
      expect(parseElmResponse('41 05 5A').coolantC, 50);
    });

    test('NO DATA：noData 且读数全 null', () {
      final r = parseElmResponse('010D\rNO DATA\r\r>');
      expect(r.noData, isTrue);
      expect(r.errorKind, 'NO DATA');
      expect(r.speedKmh, isNull);
    });

    test('STOPPED / UNABLE TO CONNECT / ?', () {
      expect(parseElmResponse('STOPPED').errorKind, 'STOPPED');
      expect(
          parseElmResponse('UNABLE TO CONNECT').errorKind,
          'UNABLE TO CONNECT');
      expect(parseElmResponse('?').errorKind, '?');
    });

    test('空响应 / 只有 OK：读数全 null，不抛错', () {
      final r = parseElmResponse('OK\r\r>');
      expect(r.hasAny, isFalse);
      expect(r.errorKind, isNull);
    });

    test('elmErrorKind', () {
      expect(elmErrorKind('NO DATA'), 'NO DATA');
      expect(elmErrorKind('STOPPED'), 'STOPPED');
      expect(elmErrorKind('41 0D 3C'), isNull);
      expect(elmErrorKind('?'), '?');
    });
  });

  group('ObdStatus', () {
    test('未连接时读数全部为 null', () {
      const s = ObdStatus.disconnected;
      expect(s.connected, isFalse);
      expect(s.speedKmh, isNull);
      expect(s.rpm, isNull);
      expect(s.throttlePct, isNull);
      expect(s.coolantC, isNull);
    });

    test('obdStatusLabel', () {
      expect(obdStatusLabel(ObdStatus.disconnected), '未连接 OBD');
      expect(obdStatusLabel(const ObdStatus(connecting: true)),
          '正在连接 OBD…');
      expect(
          obdStatusLabel(
              const ObdStatus(connected: true, deviceName: 'ELM327')),
          'OBD · ELM327');
      expect(obdStatusLabel(const ObdStatus(connected: true)),
          'OBD · 已连接');
    });
  });

  group('ObdService 连接与轮询（fake 平台）', () {
    late FakeObdPlatform fake;
    late ObdService service;

    setUp(() {
      fake = FakeObdPlatform();
      service = testService(fake);
    });

    tearDown(() {
      service.dispose();
      fake.dispose();
    });

    test('初始化序列 ATZ→ATE0→ATL0→ATS0→ATH0→ATSP0 后已连接', () async {
      final ok = await service.connect('AA:BB:CC:DD:EE:FF',
          deviceName: 'ELM327');
      expect(ok, isTrue);
      expect(service.status.connected, isTrue);
      expect(service.status.deviceName, 'ELM327');
      expect(fake.sentCommands, [
        'ATZ',
        'ATE0',
        'ATL0',
        'ATS0',
        'ATH0',
        'ATSP0',
      ]);
    });

    test('车速轮询写 Recorder.obdSpeedMs，慢轮询更新转速/油门/水温',
        () async {
      final rec = Recorder();
      service.recorder = rec;
      await service.connect('AA:BB:CC:DD:EE:FF', deviceName: 'ELM327');
      await service.pollSpeedOnce();
      expect(service.status.speedKmh, 60);
      expect(rec.obdSpeedMs, closeTo(60 / 3.6, 1e-9));
      await service.pollSlowOnce();
      expect(service.status.rpm, 1726);
      expect(service.status.throttlePct, closeTo(50.2, 0.05));
      expect(service.status.coolantC, 50);
    });

    test('每秒存一条实测采样（只存实测）', () async {
      final rec = Recorder();
      rec.state = RecState.recording;
      var now = 5000;
      rec.nowProvider = () => now;
      service.recorder = rec;
      await service.connect('AA:BB:CC:DD:EE:FF', deviceName: 'ELM327');
      await service.pollSpeedOnce();
      await service.pollSlowOnce();
      service.sampleNow();
      expect(rec.obdSamples.length, 1);
      expect(rec.obdSamples.first['vKmh'], 60);
      expect(rec.obdSamples.first['rpm'], 1726);
      expect(rec.obdSamples.first['thr'], closeTo(50.2, 0.05));
      expect(rec.obdSamples.first['cool'], 50);
      // 1 秒内再调不重复存。
      service.sampleNow();
      expect(rec.obdSamples.length, 1);
      now = 6000;
      service.sampleNow();
      expect(rec.obdSamples.length, 2);
    });

    test('断开清 OBD 速度与读数', () async {
      final rec = Recorder();
      service.recorder = rec;
      await service.connect('AA:BB:CC:DD:EE:FF', deviceName: 'ELM327');
      await service.pollSpeedOnce();
      expect(rec.obdSpeedMs, isNotNull);
      await service.disconnect();
      expect(service.status.connected, isFalse);
      expect(service.status.speedKmh, isNull);
      expect(service.status.rpm, isNull);
      expect(rec.obdSpeedMs, isNull);
    });
  });

  group('ObdService 状态机：断线重连一次，之后报断开', () {
    test('第一次断线重连成功，第二次断线报断开', () async {
      final fake = FakeObdPlatform();
      final rec = Recorder();
      final service = testService(fake, recorder: rec);
      addTearDown(() {
        service.dispose();
        fake.dispose();
      });
      await service.connect('AA:BB:CC:DD:EE:FF', deviceName: 'ELM327');
      await service.pollSpeedOnce();
      expect(service.status.connected, isTrue);
      expect(rec.obdSpeedMs, isNotNull);

      fake.simulateDisconnect('eof');
      await Future.delayed(const Duration(milliseconds: 500));
      expect(fake.connectCount, 2);
      expect(service.status.connected, isTrue);
      expect(service.status.deviceName, 'ELM327');

      fake.simulateDisconnect('eof');
      await Future.delayed(const Duration(milliseconds: 500));
      expect(fake.connectCount, 2);
      expect(service.status.connected, isFalse);
      expect(service.status.speedKmh, isNull);
      expect(rec.obdSpeedMs, isNull);
    });
  });

  group('Recorder 速度模型选择', () {
    Recorder recorderWithFixes() {
      final rec = Recorder();
      rec.state = RecState.recording;
      rec.startMs = 0;
      rec.nowProvider = () => 0;
      for (final t in [0, 1000]) {
        rec.onLocation({
          'lat': 39.0,
          'lon': 116.0 + t / 1000 * 0.0002,
          'speed': 20.0,
          'bearing': 90.0,
          'timeMs': t,
          'hAcc': 5.0,
          'alt': 100.0,
          'hasAlt': true,
          'provider': 'gps',
        });
      }
      return rec;
    }

    test('OBD 连上用 OBD 速度，否则用衰减模型', () {
      expect(estimateSpeed(initialMs: 20, elapsedSec: 60, obdSpeedMs: 15),
          15);
      expect(estimateSpeed(initialMs: 20, elapsedSec: 60),
          closeTo(11.8, 0.2));

      final withObd = recorderWithFixes();
      withObd.noteObdSample(speedKmh: 36); // 10 m/s
      withObd.gapTickForTest(4001);
      expect(withObd.gapStatus.value, GapStatus.estimating);
      expect(withObd.points.last.speed, closeTo(10, 1e-9));
      expect(withObd.points.last.estimated, isTrue);

      final withoutObd = recorderWithFixes();
      withoutObd.gapTickForTest(4001);
      expect(withoutObd.gapStatus.value, GapStatus.estimating);
      // 缺口 3 秒，衰减模型前 10 秒保持末速度 20 m/s。
      expect(withoutObd.points.last.speed, closeTo(20, 1e-9));
    });

    test('GPS 正常时 OBD 速度不进实测点', () {
      final rec = recorderWithFixes();
      rec.noteObdSample(speedKmh: 36);
      rec.onLocation({
        'lat': 39.0,
        'lon': 116.0004,
        'speed': 20.0,
        'bearing': 90.0,
        'timeMs': 2000,
        'hAcc': 5.0,
        'alt': 100.0,
        'hasAlt': true,
        'provider': 'gps',
      });
      expect(rec.points.last.estimated, isFalse);
      expect(rec.points.last.speed, 20);
    });
  });

  group('ObdSection（mock service，不依赖真蓝牙）', () {
    late FakeObdPlatform fake;
    late ObdService service;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('drivetrack/native'),
        (call) async {
          if (call.method == 'checkPermissions') {
            return <String, dynamic>{
              'bluetooth': true,
              'location': true,
              'foreground': true,
              'background': true,
              'notifications': true,
              'permanentlyDenied': <String>[],
            };
          }
          return null;
        },
      );
      fake = FakeObdPlatform();
      service = testService(fake);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('drivetrack/native'), null);
      service.dispose();
      fake.dispose();
    });

    testWidgets('未连接态：写明未连接 OBD 与先配对指引', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ObdSection(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未连接 OBD'), findsOneWidget);
      expect(find.textContaining('先在系统蓝牙里配对 ELM327'),
          findsOneWidget);
      expect(find.text('ELM327'), findsOneWidget);
    });

    testWidgets('点已配对设备行连接后显示已连接与实时车速', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ObdSection(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELM327'));
      await tester.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      await service.pollSpeedOnce();
      await tester.pump();
      expect(find.text('60 km/h'), findsOneWidget);
      // 测试体结束前断开：停掉轮询 Timer，否则 widget binding
      // 在 tearDown 之前校验挂起 Timer 会失败。
      await service.disconnect();
      await tester.pump();
    });
  });
}
