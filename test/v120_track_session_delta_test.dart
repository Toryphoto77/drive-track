/// v1.2.0 补漏测试：LapTimer 进行中分段只读 API。
///
/// 覆盖新增 API（lib/track_timing.dart）：
/// - currentCompletedSectorsMs：已完成分段各段用时；
/// - currentSectorElapsedMs：当前分段已用耗时；
/// - currentSectorDeltasVsBest：已完成分段相对本节最佳圈的 delta；
/// - predictedLapMsVsBest：预测圈 = 已完成分段实测之和 +
///   参照圈从当前分段起的各段用时（当前分段按参照圈 pace 投影，
///   不把当前分段已用耗时重复计入）。
///
/// 时序约定（坐标沿经度走，0.001 度约 111 m，穿越半径默认 30 m）：
/// - 起终点 (0, 0)，分段点 (0, 0.001) / (0, 0.002)；
/// - 完圈须满足最短圈间隔 30 秒，测试里完圈用时均为 60 秒。
/// 本文件不碰任何已有 Lap/LapTimer 行为，只断言新增只读 API。

import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

TimedPoint _pt(int t, double lon) =>
    TimedPoint(timeMs: t, lat: 0, lon: lon, speed: 10);

LapTimer _timerWithSectors() => LapTimer(
      startFinish: const GeoPoint(0, 0),
      sectorPoints: const [GeoPoint(0, 0.001), GeoPoint(0, 0.002)],
    );

void main() {
  group('进行中分段只读 API（有分段点）', () {
    test('未开始计时时全部为空 / null，不抛错', () {
      final timer = _timerWithSectors();
      expect(timer.currentLapMs, isNull);
      expect(timer.currentCompletedSectorsMs, isEmpty);
      expect(timer.currentSectorElapsedMs, isNull);
      expect(timer.currentSectorDeltasVsBest, isEmpty);
      expect(timer.predictedLapMsVsBest, isNull);
    });

    test('首圈进行中：无参照圈时 delta 为 null、预测圈为 null', () {
      final timer = _timerWithSectors();
      timer.addPoint(_pt(0, -0.001));
      timer.addPoint(_pt(1000, 0)); // 穿越起终点，第 1 圈开始
      timer.addPoint(_pt(11000, 0.0005));
      expect(timer.currentCompletedSectorsMs, isEmpty);
      expect(timer.currentSectorElapsedMs, 10000);
      expect(timer.currentSectorDeltasVsBest, isEmpty);
      expect(timer.predictedLapMsVsBest, isNull);

      timer.addPoint(_pt(21000, 0.001)); // S1 完成，用时 20000
      expect(timer.currentCompletedSectorsMs, [20000]);
      expect(timer.currentSectorElapsedMs, 0);
      // 有已完成分段但尚无最佳圈：对应位置为 null，不编 delta。
      expect(timer.currentSectorDeltasVsBest, [null]);
      expect(timer.predictedLapMsVsBest, isNull);
    });

    test('第 2 圈进行中：delta 带正负号，预测圈 = 参照圈 + 已完成 delta', () {
      final timer = _timerWithSectors();
      // 第 1 圈：S1 20000 / S2 20000 / S3 20000，圈速 60000，成为最佳圈。
      timer.addPoint(_pt(0, -0.001));
      timer.addPoint(_pt(1000, 0));
      timer.addPoint(_pt(11000, 0.0005));
      timer.addPoint(_pt(21000, 0.001));
      timer.addPoint(_pt(31000, 0.0015));
      timer.addPoint(_pt(41000, 0.002));
      // 完圈走绕行闭合（北侧迂回回起终点），不用原路返回：
      // 原路返回的线段会穿过扇区点，给新圈误记 0 时刻分段。
      timer.addPoint(TimedPoint(timeMs: 46000, lat: 0.002, lon: 0.002, speed: 10));
      timer.addPoint(TimedPoint(timeMs: 51000, lat: 0.002, lon: 0, speed: 10));
      timer.addPoint(_pt(61000, 0)); // 完圈，第 2 圈开始
      expect(timer.bestLap!.durationMs, 60000);
      expect(timer.bestLap!.sectorsMs, [20000, 20000, 20000]);
      // 刚开第 2 圈：无已完成分段，预测圈即参照圈圈速（无 delta 可加）。
      expect(timer.currentCompletedSectorsMs, isEmpty);
      expect(timer.currentSectorDeltasVsBest, isEmpty);
      expect(timer.predictedLapMsVsBest, 60000);

      // 第 2 圈 S1 用时 15000：比最佳圈 S1 快 5000。
      timer.addPoint(_pt(76000, 0.001));
      expect(timer.currentCompletedSectorsMs, [15000]);
      expect(timer.currentSectorDeltasVsBest, [-5000]);
      expect(timer.predictedLapMsVsBest, 55000); // 15000 + 20000 + 20000
      // 当前分段已跑 10000，但预测圈不因此变化：当前分段按
      // 参照圈 pace 投影，已用耗时不重复计入。
      timer.addPoint(_pt(86000, 0.0015));
      expect(timer.currentSectorElapsedMs, 10000);
      expect(timer.currentSectorDeltasVsBest, [-5000]);
      expect(timer.predictedLapMsVsBest, 55000);

      // 第 2 圈 S2 用时 25000：比最佳圈 S2 慢 5000，预测圈回到 60000。
      timer.addPoint(_pt(101000, 0.002));
      expect(timer.currentCompletedSectorsMs, [15000, 25000]);
      expect(timer.currentSectorDeltasVsBest, [-5000, 5000]);
      expect(timer.currentSectorElapsedMs, 0);
      expect(timer.predictedLapMsVsBest, 60000); // 40000 + 20000
    });

    test('参照圈分段数 <= 已完成分段数时预测圈为 null（口径不一致不硬拼）',
        () {
      final timer = _timerWithSectors();
      // 第 1 圈只触发 S1 就完圈：分段为 [20000, 40000]（2 段），
      // 圈速 60000，成为最佳圈。
      timer.addPoint(_pt(0, -0.001));
      timer.addPoint(_pt(1000, 0));
      timer.addPoint(_pt(21000, 0.001));
      // 同上：绕行闭合回起终点，不原路返回穿扇区点。
      timer.addPoint(TimedPoint(timeMs: 31000, lat: 0.002, lon: 0.001, speed: 10));
      timer.addPoint(TimedPoint(timeMs: 41000, lat: 0.002, lon: 0, speed: 10));
      timer.addPoint(_pt(61000, 0));
      expect(timer.bestLap!.sectorsMs, [20000, 40000]);
      // 第 2 圈触发 S1 + S2：已完成 2 段，已追平参照圈段数，
      // 无剩余参照段可投影，预测圈必须为 null；delta 仍可逐段算。
      timer.addPoint(_pt(76000, 0.001));
      timer.addPoint(_pt(96000, 0.002));
      expect(timer.currentCompletedSectorsMs, [15000, 20000]);
      expect(timer.currentSectorDeltasVsBest, [-5000, -20000]);
      expect(timer.predictedLapMsVsBest, isNull);
    });
  });

  group('进行中分段只读 API（无分段点）', () {
    test('无分段点时进行中恒无已完成分段，当前分段已用 = 当前圈已用', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_pt(0, -0.001));
      timer.addPoint(_pt(1000, 0));
      timer.addPoint(_pt(11000, 0.0005));
      expect(timer.currentCompletedSectorsMs, isEmpty);
      expect(timer.currentSectorElapsedMs, 10000);
      expect(timer.currentSectorDeltasVsBest, isEmpty);
      // 尚无最佳圈：预测圈为 null。
      expect(timer.predictedLapMsVsBest, isNull);

      // 完第 1 圈（前后半圈 [30000, 30000]），第 2 圈进行中：
      // 仍无已完成分段；v1.2.15：无真实分段点时预测圈为 null（占位），
      // 不再退化成“预测圈 = 最佳圈总时长”复读。
      timer.addPoint(_pt(31000, 0.001));
      timer.addPoint(_pt(61000, 0));
      expect(timer.bestLap!.sectorsMs, [30000, 30000]);
      timer.addPoint(_pt(71000, 0.0005));
      expect(timer.currentCompletedSectorsMs, isEmpty);
      expect(timer.currentSectorElapsedMs, 10000);
      expect(timer.currentSectorDeltasVsBest, isEmpty);
      expect(timer.predictedLapMsVsBest, isNull);
    });
  });
}
