import 'dart:async';
import 'dart:io';

import 'package:drive_track/performance_challenge.dart';
import 'package:drive_track/recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/sensor_fusion.dart';

SpeedSample s(
  int t,
  double kmh, {
  double? hAcc,
  double? sAcc,
  double? pressurePa,
  double? temperatureC,
}) =>
    SpeedSample(
      timeMs: t,
      speedKmh: kmh,
      hAccM: hAcc,
      speedAccMps: sAcc,
      pressurePa: pressurePa,
      temperatureC: temperatureC,
    );

void main() {
  test('0-100: starts at first >=3 sample, finishes at first >=100', () {
    final e = PerformanceChallengeEngine(ChallengeType.accel0100);
    e.arm();
    e.feed(s(1000, 0, hAcc: 5));
    e.feed(s(2000, 2, hAcc: 5));
    e.feed(s(3000, 5, hAcc: 5)); // start
    e.feed(s(4000, 50, hAcc: 5));
    e.feed(s(5000, 80, hAcc: 5));
    e.feed(s(6000, 100, hAcc: 5)); // finish
    expect(e.phase, ChallengePhase.finished);
    expect(e.outcome.durationMs, 3000);
    expect(e.outcome.valid, isTrue);
  });

  test('0-100: bad accuracy during run invalidates, no valid outcome', () {
    final e = PerformanceChallengeEngine(ChallengeType.accel0100);
    e.arm();
    e.feed(s(1000, 5, hAcc: 5));
    e.feed(s(2000, 50, hAcc: 35)); // hAcc > 20 during run
    expect(e.phase, ChallengePhase.invalid);
    expect(e.outcome.valid, isFalse);
    expect(e.outcome.durationMs, isNull);
  });

  test('0-100: no accuracy info at all finishes as unverified invalid', () {
    final e = PerformanceChallengeEngine(ChallengeType.accel0100);
    e.arm();
    e.feed(s(1000, 5));
    e.feed(s(2000, 100));
    expect(e.phase, ChallengePhase.invalid);
    expect(e.outcome.valid, isFalse);
  });

  test('0-100: gap over 2s during run invalidates', () {
    final e = PerformanceChallengeEngine(ChallengeType.accel0100);
    e.arm();
    e.feed(s(1000, 5, hAcc: 5));
    e.feed(s(4000, 50, hAcc: 5)); // 3000 ms gap
    expect(e.phase, ChallengePhase.invalid);
  });

  test('100-0: must reach 100 first, starts below 100, finishes at <=2', () {
    final e = PerformanceChallengeEngine(ChallengeType.brake1000);
    e.arm();
    e.feed(s(1000, 80, hAcc: 5)); // not ready yet
    e.feed(s(2000, 60, hAcc: 5)); // still not a run
    expect(e.phase, ChallengePhase.armed);
    e.feed(s(3000, 105, hAcc: 5)); // ready
    e.feed(s(4000, 99, hAcc: 5)); // start
    e.feed(s(5000, 50, hAcc: 5));
    e.feed(s(7000, 2, hAcc: 5)); // finish
    expect(e.phase, ChallengePhase.finished);
    expect(e.outcome.durationMs, 3000);
  });

  test('bestFor picks the shortest valid record per type', () {
    final records = [
      ChallengeRunRecord(
          type: ChallengeType.accel0100, durationMs: 8200, createdMs: 1),
      ChallengeRunRecord(
          type: ChallengeType.accel0100, durationMs: 7500, createdMs: 2),
      ChallengeRunRecord(
          type: ChallengeType.brake1000, durationMs: 3000, createdMs: 3),
    ];
    expect(
        PerformanceChallengeStore.bestFor(records, ChallengeType.accel0100)!
            .durationMs,
        7500);
    expect(
        PerformanceChallengeStore.bestFor(records, ChallengeType.brake1000)!
            .durationMs,
        3000);
  });

  test('空气密度与密度高度使用标准大气基准，热天不是 0 米', () {
    final standard = airDensityKgM3(pressurePa: 101325, temperatureC: 15);
    expect(standard, closeTo(1.225, 0.001));
    expect(densityAltitudeM(pressurePa: 101325, temperatureC: 15),
        closeTo(0, 1));
    expect(densityAltitudeM(pressurePa: 101325, temperatureC: 35),
        greaterThan(300));
    expect(airDensityKgM3(pressurePa: 101325, temperatureC: 35),
        lessThan(standard));
  });

  test('加速成绩归一化保留标准天气不变，并修正空气密度差异', () {
    const raw = 6000;
    final standard = normalizeAccelerationDurationMs(
      durationMs: raw,
      airDensityKgM3: 1.225,
    );
    final dense = normalizeAccelerationDurationMs(
      durationMs: raw,
      airDensityKgM3: 1.30,
    );
    final thin = normalizeAccelerationDurationMs(
      durationMs: raw,
      airDensityKgM3: 1.10,
    );
    expect(standard, raw);
    expect(dense!, lessThan(raw));
    expect(thin!, greaterThan(raw));
    expect(
      normalizeAccelerationDurationMs(durationMs: raw, airDensityKgM3: 0),
      isNull,
    );
  });

  test('计时期间环境样本形成平均密度和标准天气估算成绩', () {
    final e = PerformanceChallengeEngine(ChallengeType.accel0100);
    e.arm();
    e.feed(s(1000, 5,
        hAcc: 5, pressurePa: 101325, temperatureC: 15));
    e.feed(s(2000, 50,
        hAcc: 5, pressurePa: 101325, temperatureC: 15));
    e.feed(s(3000, 100,
        hAcc: 5, pressurePa: 101325, temperatureC: 15));
    expect(e.outcome.airDensityKgM3, closeTo(1.225, 0.001));
    expect(e.outcome.densityAltitudeM, closeTo(0, 1));
    expect(e.outcome.normalizedDurationMs, e.outcome.durationMs);
  });

  test('成绩 JSON 保留环境数据与归一化结果', () {
    final record = ChallengeRunRecord(
      type: ChallengeType.accel0100,
      durationMs: 6000,
      createdMs: 1,
      airDensityKgM3: 1.1,
      densityAltitudeM: 900,
      normalizedDurationMs: 6300,
    );
    final restored = ChallengeRunRecord.fromJson(record.toJson())!;
    expect(restored.airDensityKgM3, 1.1);
    expect(restored.densityAltitudeM, 900);
    expect(restored.normalizedDurationMs, 6300);
  });

  testWidgets('Recorder 样本读取气压温度并显示实时环境', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('challenge_env_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'),
            (call) async => call.method == 'getFilesDir' ? tempDir.path : null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('drivetrack/native'), null);
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 上未完成的异步保存可能短暂占用文件，临时目录由系统清理。
      }
    });
    final recorder = _TestRecorder();
    addTearDown(recorder.dispose);
    await tester.pumpWidget(MaterialApp(
      home: PerformanceChallengePage(
        recorder: recorder,
        environmentReader: () => const BaroSample(
          tsUs: 1,
          temperatureC: 35,
          pressurePa: 101325,
          altitudeM: 100,
        ),
      ),
    ));
    await tester.pump();
    recorder.emit(12);
    await tester.pump();

    expect(find.textContaining('空气密度'), findsOneWidget);
    expect(find.textContaining('密度高度'), findsOneWidget);
  });

  testWidgets('标准天气估算展示并随有效成绩保存', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('challenge_save_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'),
            (call) async => call.method == 'getFilesDir' ? tempDir.path : null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('drivetrack/native'), null);
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows 上未完成的异步保存可能短暂占用文件，临时目录由系统清理。
      }
    });
    final controller = StreamController<SpeedSample>(sync: true);
    addTearDown(controller.close);
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: PerformanceChallengePage(speedSampleStream: controller.stream),
    ));
    await tester.pump();
    await tester.tap(find.text('我已阅读并确认仅在封闭场地测试'));
    await tester.pump();
    await tester.tap(find.text('开始待命：0-100'));
    await tester.pump();

    for (final sample in [
      s(1000, 5, hAcc: 5, pressurePa: 90000, temperatureC: 35),
      s(2000, 50, hAcc: 5, pressurePa: 90000, temperatureC: 35),
      s(3000, 100, hAcc: 5, pressurePa: 90000, temperatureC: 35),
    ]) {
      controller.add(sample);
    }
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('标准天气估算'), findsWidgets);
  });
}

class _TestRecorder extends Recorder {
  void emit(double speedKmh) {
    curSpeed = speedKmh / 3.6;
    curHAcc = 5;
    notifyListeners();
  }
}
