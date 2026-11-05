/// v1.2.14 越线检测测试：lib/track_timing.dart 的计时线判定。
///
/// 覆盖：
/// - 纯函数 [tangentAtPoint] / [centerlineFractionAt]：东西 / 南北 /
///   对角中心线切线、最近线段选取、退化输入返回 null；
/// - 1Hz 与 25Hz 下过线时刻插值误差小于一个采样间隔；
/// - 反向经过不触发（起终点与分段点）；
/// - 平行于计时线行驶（维修区通道两种走法）不触发；
/// - 线附近 GPS 抖动不连触发；
/// - 无中心线包回落半径法；
/// - 30 秒最短圈与停车暂停仍有效；
/// - 分段点越线 S1/S2/S3 插值切分、无分段退化两段、反向中心线自动纠正。
///
/// 合成轨迹约定：赤道附近（lat 0），1 度经度 = 111320 m，
/// 1 度纬度 = 110540 m；默认车速 30 m/s；计时线在 (0, 0)，
/// 切线向东（中心线沿经度走）。

import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 东向偏移 eastM（米）、北向偏移 northM（米）的轨迹点。
TimedPoint _pt(int t, double eastM, [double northM = 0, double speed = 30]) =>
    TimedPoint(
      timeMs: t,
      lat: northM / 110540,
      lon: eastM / 111320,
      speed: speed,
    );

/// 东向直道中心线：从 eastM = -200 到 +200（行车方向向东）。
List<GeoPoint> _straightCenterline() => [
      const GeoPoint(0, -200 / 111320),
      const GeoPoint(0, -100 / 111320),
      const GeoPoint(0, 0),
      const GeoPoint(0, 100 / 111320),
      const GeoPoint(0, 200 / 111320),
    ];

LapTimer _lineTimer({List<GeoPoint> sectorPoints = const []}) => LapTimer(
      startFinish: const GeoPoint(0, 0),
      sectorPoints: sectorPoints,
      centerline: _straightCenterline(),
    );

void main() {
  group('切线方向纯函数', () {
    test('东西向中心线切线向东', () {
      final t = tangentAtPoint(_straightCenterline(), const GeoPoint(0, 0))!;
      expect(t.east, closeTo(1, 1e-9));
      expect(t.north, closeTo(0, 1e-9));
    });

    test('南北向中心线切线向北', () {
      final cl = [
        const GeoPoint(-200 / 110540, 0),
        const GeoPoint(0, 0),
        const GeoPoint(200 / 110540, 0),
      ];
      final t = tangentAtPoint(cl, const GeoPoint(0, 0))!;
      expect(t.east, closeTo(0, 1e-9));
      expect(t.north, closeTo(1, 1e-9));
    });

    test('对角中心线切线为 45 度单位向量', () {
      final cl = [
        const GeoPoint(-100 / 110540, -100 / 111320),
        const GeoPoint(0, 0),
        const GeoPoint(100 / 110540, 100 / 111320),
      ];
      final t = tangentAtPoint(cl, const GeoPoint(0, 0))!;
      expect(t.east, closeTo(0.7071, 1e-3));
      expect(t.north, closeTo(0.7071, 1e-3));
    });

    test('取最近线段的切线：L 形中心线东段取东、北段取北', () {
      final cl = [
        const GeoPoint(0, -200 / 111320),
        const GeoPoint(0, 0),
        const GeoPoint(200 / 110540, 0),
      ];
      final east = tangentAtPoint(cl, const GeoPoint(0, -100 / 111320))!;
      expect(east.east, closeTo(1, 1e-9));
      expect(east.north, closeTo(0, 1e-9));
      final north = tangentAtPoint(cl, const GeoPoint(100 / 110540, 0))!;
      expect(north.east, closeTo(0, 1e-9));
      expect(north.north, closeTo(1, 1e-9));
    });

    test('退化输入返回 null，不抛错', () {
      expect(tangentAtPoint([], const GeoPoint(0, 0)), isNull);
      expect(tangentAtPoint([const GeoPoint(0, 0)], const GeoPoint(0, 0)),
          isNull);
      // 全零长度线段：中心线“点”重合，无有效切线。
      expect(
          tangentAtPoint([
            const GeoPoint(0, 0),
            const GeoPoint(0, 0),
          ], const GeoPoint(0, 0)),
          isNull);
    });

    test('centerlineFractionAt：四分之一处约 0.25，退化返回 null', () {
      expect(centerlineFractionAt(_straightCenterline(), const GeoPoint(0, 0)),
          closeTo(0.5, 1e-9));
      expect(
          centerlineFractionAt(
              _straightCenterline(), const GeoPoint(0, -100 / 111320)),
          closeTo(0.25, 1e-9));
      expect(centerlineFractionAt([], const GeoPoint(0, 0)), isNull);
      expect(centerlineFractionAt([const GeoPoint(0, 0)], const GeoPoint(0, 0)),
          isNull);
    });
  });

  group('越线检测：插值时刻', () {
    test('1Hz：过线时刻插值误差小于一个采样间隔（1000 ms）', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 真实过线在 t=500
      timer.addPoint(_pt(2000, 45));
      expect(timer.currentLapNumber, 1);
      // 由当前圈已用时长反推圈起点：2000 - currentLapMs。
      final impliedStartMs = 2000 - timer.currentLapMs!;
      expect((impliedStartMs - 500).abs(), lessThan(1000));
      expect(impliedStartMs, 500); // 本构造下插值应精确命中
    });

    test('25Hz：过线时刻插值误差小于一个采样间隔（40 ms）', () {
      final timer = _lineTimer();
      // 每 40 ms 一点，30 m/s，每步 1.2 m；真实过线在 t=500。
      for (var t = 0; t <= 1000; t += 40) {
        timer.addPoint(_pt(t, -15 + 30 * t / 1000));
      }
      expect(timer.currentLapNumber, 1);
      final impliedStartMs = 1000 - timer.currentLapMs!;
      expect((impliedStartMs - 500).abs(), lessThan(40));
      expect(impliedStartMs, 500); // 本构造下插值应精确命中
    });

    test('首点恰在线上：过线时刻即首点时刻，不崩', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, 0)); // 恰在计时线上
      timer.addPoint(_pt(1000, 30));
      timer.addPoint(_pt(2000, 60));
      expect(timer.currentLapNumber, 1);
      expect(2000 - timer.currentLapMs!, 0);
    });
  });

  group('越线检测：不触发的情形', () {
    test('反向经过起终点不触发', () {
      final timer = _lineTimer();
      // 自东向西反向穿过计时线。
      timer.addPoint(_pt(0, 100));
      timer.addPoint(_pt(1000, 70));
      timer.addPoint(_pt(2000, 40));
      timer.addPoint(_pt(3000, 10));
      timer.addPoint(_pt(4000, -20));
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });

    test('正向开圈后反向穿回起终点不关圈', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 正向过线，第 1 圈开始（t=500）
      timer.addPoint(_pt(40000, 1185)); // 向东远离，重新获得资格
      // 掉头向西穿回：距开圈 41500 ms，已超最短圈 30 秒，
      // 只有方向检查能拦住这次穿越。
      timer.addPoint(_pt(41000, 30));
      timer.addPoint(_pt(42000, -30));
      expect(timer.laps, isEmpty);
      expect(timer.currentLapNumber, 1);
    });

    test('平行于计时线行驶不触发：沿线向北走', () {
      final timer = _lineTimer();
      // 计时线为南北向直线，沿其平行方向（向北）行驶，
      // 带符号距离恒为 +48 m，不变号。
      for (var i = 0; i <= 5; i++) {
        timer.addPoint(_pt(i * 1000, 48, i * 30));
      }
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });

    test('平行于计时线行驶不触发：恰沿计时线向北走', () {
      final timer = _lineTimer();
      // 东向偏移恒为 0，沿计时线本身行驶：位移与切线点积为 0。
      for (var i = 0; i <= 5; i++) {
        timer.addPoint(_pt(i * 1000, 0, i * 30));
      }
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });

    test('维修区通道横穿计时线延长线不触发（横向偏移 50 m > 半宽 30 m）', () {
      final timer = _lineTimer();
      // 维修区通道在计时线以北 50 m、与主直道平行向东：
      // 会穿过计时线的无限延长线，但过线点横向偏移 50 m，
      // 超出计时线半宽 30 m，不触发。
      timer.addPoint(_pt(0, -60, 50));
      timer.addPoint(_pt(1000, -30, 50));
      timer.addPoint(_pt(2000, 0, 50));
      timer.addPoint(_pt(3000, 30, 50));
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });

    test('横向偏移 20 m 内的正向过线仍触发（半宽内为赛道）', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15, 20));
      timer.addPoint(_pt(1000, 15, 20));
      timer.addPoint(_pt(2000, 45, 20));
      expect(timer.currentLapNumber, 1);
      expect(2000 - timer.currentLapMs!, 500);
    });
  });

  group('越线检测：GPS 抖动', () {
    test('过线后在线附近抖动不连触发', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 正向过线，第 1 圈开始（t=500）
      // 在线附近 ±5 m 来回抖动 20 点（未离开 60 m，无重获资格）。
      for (var i = 0; i < 20; i++) {
        timer.addPoint(_pt(1100 + i * 100, i.isEven ? 5 : -5, 0, 1));
      }
      expect(timer.laps, isEmpty);
      expect(timer.currentLapNumber, 1);
    });

    test('开圈前在线西侧小幅抖动（不过线）不触发', () {
      final timer = _lineTimer();
      for (var i = 0; i < 10; i++) {
        timer.addPoint(_pt(i * 1000, -5 + (i.isEven ? 3 : -3), 0, 1));
      }
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });
  });

  group('无中心线回落半径法', () {
    test('高速 1Hz 跨点仍触发（线段距离法）', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_pt(0, -40));
      timer.addPoint(_pt(1000, 40)); // 一步跨过 30 m 半径圆
      expect(timer.currentLapNumber, 1);
    });

    test('远离起终点不触发，完圈行为与旧版一致', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_pt(0, -100));
      timer.addPoint(_pt(1000, -70));
      expect(timer.currentLapNumber, 0);

      // 完一圈：t=2000 过线开圈，t=62000 再次过线关圈，圈速 60000。
      // 注意：开圈点恰在起终点上，须 1 秒内离开（否则 30 秒后
      // 离开线段的起点仍在圆内，半径法会再次命中——旧版亦如此）。
      timer.addPoint(_pt(2000, 0)); // 落入 30 m 圆，开圈（t=2000）
      timer.addPoint(_pt(3000, 500)); // 1 秒内远离，重新获得资格
      timer.addPoint(_pt(62000, 0)); // 再次过线
      expect(timer.laps.length, 1);
      expect(timer.laps.first.durationMs, 60000);
    });
  });

  group('越线模式下既有保护仍有效', () {
    test('30 秒最短圈：30 秒内再次正向过线不关圈', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 开圈 t=500
      timer.addPoint(_pt(5000, 200)); // 远离，重新获得资格
      // 30 秒内再次正向过线（合成轨迹跳回线西再穿过）：不关圈。
      timer.addPoint(_pt(10000, -15));
      timer.addPoint(_pt(11000, 15));
      expect(timer.laps, isEmpty);
      expect(timer.currentLapNumber, 1);
      // 30 秒后再正向过线：关圈时刻为插值的 t=40500，
      // 圈速 40500 - 500 = 40000。
      timer.addPoint(_pt(40000, -15));
      timer.addPoint(_pt(41000, 15));
      expect(timer.laps.length, 1);
      expect(timer.laps.first.durationMs, 40000);
    });

    test('停车暂停：停车 30 秒自动暂停，圈速扣除暂停、本圈不计', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 开圈 t=500
      // 原地停车 35 秒（速度 0）：首个静止点在 t=10000。
      timer.addPoint(_pt(10000, 300, 0, 0));
      for (var t = 11000; t <= 45000; t += 1000) {
        timer.addPoint(_pt(t, 300, 0, 0));
      }
      // 恢复行驶：低速满 30 秒时（t=40000）开始暂停，
      // t=46000 恢复，暂停时长 6000 ms。
      timer.addPoint(_pt(46000, 330));
      // 跳回线西再正向过线关圈：过线时刻 t=61500。
      timer.addPoint(_pt(61000, -15));
      timer.addPoint(_pt(62000, 15));
      expect(timer.laps.length, 1);
      final lap = timer.laps.first;
      expect(lap.pausedMs, 6000);
      expect(lap.dwellNotCounted, isTrue);
      expect(lap.durationMs, 61500 - 500 - 6000);
      expect(timer.bestLap, isNull); // 停留不计圈的圈不进最快圈
    });
  });

  group('越线模式：分段点', () {
    test('S1/S2/S3 按插值过线时刻切分', () {
      final timer = _lineTimer(sectorPoints: const [
        GeoPoint(0, 95 / 111320),
        GeoPoint(0, 190 / 111320),
      ]);
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 起终点过线 t=500
      timer.addPoint(_pt(3000, 75));
      timer.addPoint(_pt(4000, 105)); // S1 过线 t=3667
      timer.addPoint(_pt(6000, 165));
      timer.addPoint(_pt(7000, 195)); // S2 过线 t=6833
      // 关圈：过线时刻 t=61500。
      timer.addPoint(_pt(61000, -15));
      timer.addPoint(_pt(62000, 15));
      expect(timer.laps.length, 1);
      final lap = timer.laps.first;
      expect(lap.durationMs, 61000);
      expect(lap.sectorsMs, [3167, 3166, 54667]);
    });

    test('分段点反向经过不记段，正向经过才记', () {
      final timer = _lineTimer(sectorPoints: const [
        GeoPoint(0, 95 / 111320),
        GeoPoint(0, 190 / 111320),
      ]);
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 开圈 t=500
      timer.addPoint(_pt(2000, 45));
      // 绕到 S1 以东再向西穿回：经北侧绕行（横向偏移 > 半宽）
      // 再向南回到主直道，向西穿过 S1 不记段。
      timer.addPoint(_pt(3000, 150, 100));
      timer.addPoint(_pt(4000, 150));
      timer.addPoint(_pt(5000, 120));
      timer.addPoint(_pt(6000, 90)); // 向西穿过 S1
      expect(timer.currentCompletedSectorsMs, isEmpty);
      // 再向东穿过 S1：记段，过线时刻 t=6167，S1 = 5667。
      timer.addPoint(_pt(7000, 120));
      expect(timer.currentCompletedSectorsMs, [5667]);
    });

    test('无分段点时退化为前后半圈两段', () {
      final timer = _lineTimer();
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15)); // 开圈 t=500
      timer.addPoint(_pt(31000, 500)); // 向东远离，重新获得资格
      timer.addPoint(_pt(61000, -15));
      timer.addPoint(_pt(62000, 15)); // 关圈 t=61500
      expect(timer.laps.length, 1);
      expect(timer.laps.first.durationMs, 61000);
      expect(timer.laps.first.sectorsMs, [30500, 30500]);
    });
  });

  group('中心线方向纠正与显式切线', () {
    test('反向中心线自动纠正：正向过线仍触发', () {
      // 中心线按行车反方向排序（自东向西）。
      final reversed = _straightCenterline().reversed.toList();
      // 原始切线应为向西，证明数据确实是反的。
      expect(tangentAtPoint(reversed, const GeoPoint(0, 0))!.east,
          closeTo(-1, 1e-9));
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        sectorPoints: const [
          GeoPoint(0, 95 / 111320),
          GeoPoint(0, 190 / 111320),
        ],
        centerline: reversed,
      );
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15));
      timer.addPoint(_pt(2000, 45));
      expect(timer.currentLapNumber, 1);
      expect(2000 - timer.currentLapMs!, 500);
    });

    test('显式切线优先于中心线：传向西切线时正向过线不触发', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(0, 0),
        centerline: _straightCenterline(),
        startFinishTangent: const TrackDirection(-1, 0),
      );
      timer.addPoint(_pt(0, -15));
      timer.addPoint(_pt(1000, 15));
      timer.addPoint(_pt(2000, 45));
      expect(timer.currentLapNumber, 0);
      expect(timer.laps, isEmpty);
    });
  });
}
