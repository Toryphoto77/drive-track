import 'package:drive_track/performance_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

SpeedSample s(int t, double kmh, {double? hAcc, double? sAcc}) =>
    SpeedSample(timeMs: t, speedKmh: kmh, hAccM: hAcc, speedAccMps: sAcc);

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
}
