/// v1.2.17 计时器维修区检测 + 段速 + 到下一计时线距离测试：
/// lib/track_timing.dart（LapKind / inPit / pitStopMs /
/// sectorSpeeds / nextLineDistanceM）。
///
/// 覆盖：
/// - 入口穿越置 inPit、停站计时递增、出口穿越清 inPit；
/// - 圈种 inLap / outLap / flying（含同圈双穿取 outLap）；
/// - 进站圈停车仍按 dwell 规则不计成绩；
/// - 无 pit 点时行为与旧版一致；只传 pitIn 时检测关闭；
/// - 反向经过入口线不触发；无中心线时维修区检测关闭；
/// - 段速 min/max（含当前段实时值）、无分段点为空列表、
///   1 分段点为 2 段；Lap kind 序列化（'k' 键，老数据缺失读 flying）；
/// - 下一线距离沿中心线递减、过线后切到下一边界、反向中心线
///   仍按行进方向算、无中心线或未喂点时为 null；
/// - 30 秒最短圈与停车暂停仍有效。
///
/// 合成赛道约定：赤道附近（lat 0），1 度经度 = 111320 m，
/// 1 度纬度 = 110540 m；矩形环线 A(-400,-100) → B(400,-100) →
/// C(400,100) → D(-400,100) → A，全长 2000 m，行车方向沿南边
/// 向东、东边向北、北边向西、西边向南；默认车速 25 m/s，
/// 一圈 80 秒。起终点 (0,-100) 在南边中点，S1 (400,0) 在东边
/// 中点，S2 (0,100) 在北边中点。维修区通道在北偏 50 m 处
/// （north=-50），与主直道平行，入口 (-100,-50)、出口 (100,-50)：
/// 偏离主直道 50 m > 计时线半宽 30 m，主直道上的圈不触发
/// 维修区线，通道内的车也不触发起终点线。

import 'dart:math' as math;

import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 米制东 / 北坐标（米）转 GeoPoint。
GeoPoint _g(double east, double north) =>
    GeoPoint(north / 110540, east / 111320);

/// 米制东 / 北坐标（米）的轨迹点。
TimedPoint _pt(int t, double east, double north, [double speed = 25]) =>
    TimedPoint(
      timeMs: t,
      lat: north / 110540,
      lon: east / 111320,
      speed: speed,
    );

/// 矩形环线中心线（闭合，首尾同点），按行车方向排序。
List<GeoPoint> _loopCenterline() => [
      _g(-400, -100),
      _g(0, -100),
      _g(400, -100),
      _g(400, 0),
      _g(400, 100),
      _g(0, 100),
      _g(-400, 100),
      _g(-400, 0),
      _g(-400, -100),
    ];

/// 反向排序的同一条环线中心线（供反向中心线纠正测试）。
List<GeoPoint> _reversedLoopCenterline() =>
    _loopCenterline().reversed.toList();

/// 分段点 S1 (400,0)、S2 (0,100)。
List<GeoPoint> _sectors() => [_g(400, 0), _g(0, 100)];

LapTimer _pitTimer({
  List<GeoPoint> sectors = const [],
  GeoPoint? pitIn,
  GeoPoint? pitOut,
  List<GeoPoint>? centerline,
}) =>
    LapTimer(
      startFinish: _g(0, -100),
      sectorPoints: sectors,
      centerline: centerline ?? _loopCenterline(),
      pitIn: pitIn,
      pitOut: pitOut,
    );

/// 沿折线 waypoints（米制东 / 北坐标对）按 speed m/s 喂点，
/// 每步 speed 米、1 秒一个点（最后一段不足一步时按比例计时间）；
/// waypoints[0] 须已喂入（本函数只喂后续点）；返回结束时刻。
int _feedPath(
  LapTimer timer,
  int tMs,
  List<(double, double)> waypoints, {
  double speed = 25,
}) {
  var t = tMs;
  for (var i = 0; i + 1 < waypoints.length; i++) {
    final (x0, y0) = waypoints[i];
    final (x1, y1) = waypoints[i + 1];
    final dx = x1 - x0;
    final dy = y1 - y0;
    final len = math.sqrt(dx * dx + dy * dy);
    var covered = 0.0;
    while (covered < len - 1e-9) {
      final step = math.min(speed, len - covered);
      covered += step;
      t += (step / speed * 1000).round();
      final f = covered / len;
      timer.addPoint(_pt(t, x0 + dx * f, y0 + dy * f, speed));
    }
  }
  return t;
}

/// 从主直道 (-350,-100) 出发绕环线一圈回到起终点 (0,-100)：
/// 途经起终点两次（t=14000 开圈，t=94000 关圈），第 1 圈
/// 飞驰圈 80000 ms，第 2 圈开始。返回结束时刻 94000。
int _driveFirstLap(LapTimer timer) {
  timer.addPoint(_pt(0, -350, -100));
  return _feedPath(timer, 0, [
    (-350, -100),
    (400, -100),
    (400, 100),
    (-400, 100),
    (-400, -100),
    (0, -100),
  ]);
}

void main() {
  group('维修区检测：入口/出口与停站计时', () {
    test('入口穿越置 inPit、停站计时递增、出口穿越清 inPit', () {
      final timer = _pitTimer(pitIn: _g(-100, -50), pitOut: _g(100, -50));
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);

      timer.addPoint(_pt(0, -350, -100));
      var t = _feedPath(timer, 0, [(-350, -100), (-125, -100)]);
      t = _feedPath(timer, t, [(-125, -100), (-125, -50)]);
      // 通道内向东，穿越入口线 (-100,-50)：点恰好落在线上。
      t = _feedPath(timer, t, [(-125, -50), (-100, -50)]);
      expect(timer.inPit, isTrue);
      expect(timer.pitStopMs, 0); // 刚穿越，停站 0

      // 原地停 5 秒（速度 0），停站计时递增。
      for (var i = 1; i <= 5; i++) {
        timer.addPoint(_pt(t + i * 1000, -100, -50, 0));
      }
      t += 5000;
      expect(timer.inPit, isTrue);
      expect(timer.pitStopMs, 5000);
      // 通道内未触发起终点（偏离 50 m > 半宽 30 m）。
      expect(timer.currentLapNumber, 0);

      // 通道内继续向东，穿越出口线 (100,-50)。
      t = _feedPath(timer, t, [(-100, -50), (100, -50)]);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
    });

    test('反向经过入口线不触发', () {
      final timer = _pitTimer(pitIn: _g(-100, -50), pitOut: _g(100, -50));
      // 通道内自东向西反向穿过入口线。
      timer.addPoint(_pt(0, 50, -50));
      _feedPath(timer, 0, [(50, -50), (-150, -50)]);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
      expect(timer.currentLapNumber, 0);
    });

    test('只传 pitIn（无 pitOut）时维修区检测关闭', () {
      final timer = _pitTimer(pitIn: _g(-100, -50));
      timer.addPoint(_pt(0, -350, -100));
      var t = _feedPath(timer, 0, [(-350, -100), (-125, -100)]);
      t = _feedPath(timer, t, [(-125, -100), (-125, -50)]);
      t = _feedPath(timer, t, [(-125, -50), (100, -50)]);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
    });

    test('无中心线时维修区检测关闭，计时本身不受影响', () {
      final timer = LapTimer(
        startFinish: _g(0, -100),
        pitIn: _g(-100, -50),
        pitOut: _g(100, -50),
        // 不传 centerline：维修区线无切线来源，整体关闭。
      );
      timer.addPoint(_pt(0, -350, -100));
      var t = _feedPath(timer, 0, [(-350, -100), (-125, -100)]);
      t = _feedPath(timer, t, [(-125, -100), (-125, -50)]);
      t = _feedPath(timer, t, [(-125, -50), (100, -50)]);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
      expect(timer.currentLapNumber, 0);
    });
  });

  group('圈种标记', () {
    test('无 pit 点时行为与旧版一致：圈均为飞驰圈', () {
      final timer = _pitTimer(sectors: _sectors());
      final t = _driveFirstLap(timer);
      expect(t, 94000);
      expect(timer.laps.length, 1);
      expect(timer.laps.first.kind, LapKind.flying);
      expect(timer.laps.first.durationMs, 80000);
      expect(timer.laps.first.sectorsMs, [20000, 20000, 40000]);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
    });

    test('飞驰圈 → 进站圈 → 出站圈', () {
      final timer = _pitTimer(
        sectors: _sectors(),
        pitIn: _g(-100, -50),
        pitOut: _g(100, -50),
      );
      var t = _driveFirstLap(timer);
      expect(timer.laps.first.kind, LapKind.flying);

      // 第 2 圈（进站圈）：绕圈后在南边末段进通道过入口线，
      // 回主直道过起终点关圈；出口线在下一圈，不触发。
      t = _feedPath(timer, t, [
        (0, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
        (-250, -100),
        (-250, -50),
        (-50, -50),
        (-50, -100),
        (0, -100),
      ]);
      expect(timer.laps.length, 2);
      expect(timer.laps[1].kind, LapKind.inLap);
      expect(timer.laps[1].durationMs, 84000);
      // 关圈时仍在维修区内（入口已穿、出口未穿）。
      expect(timer.inPit, isTrue);
      expect(timer.pitStopMs, 6000);

      // 第 3 圈（出站圈）：南边初段进通道过出口线，回主直道
      // 绕圈过起终点关圈；入口线在主直道上不触发。
      t = _feedPath(timer, t, [
        (0, -100),
        (50, -100),
        (50, -50),
        (150, -50),
        (150, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
        (0, -100),
      ]);
      expect(timer.laps.length, 3);
      expect(timer.laps[0].kind, LapKind.flying);
      expect(timer.laps[1].kind, LapKind.inLap);
      expect(timer.laps[2].kind, LapKind.outLap);
      expect(timer.laps[2].durationMs, 84000);
      expect(timer.inPit, isFalse);
      expect(timer.pitStopMs, 0);
    });

    test('同圈双穿取 outLap（出站圈优先）', () {
      // 本测试用另一组维修区点：入口在起终点后、出口在起终点前，
      // 使同一圈内可先后穿越入口线与出口线。
      final timer = _pitTimer(
        sectors: _sectors(),
        pitIn: _g(100, -50),
        pitOut: _g(-100, -50),
      );
      var t = _driveFirstLap(timer);
      expect(timer.laps.first.kind, LapKind.flying);

      // 第 2 圈：南边初段进通道过入口线，回主直道绕圈；
      // 南边末段再进通道过出口线，回主直道过起终点关圈。
      t = _feedPath(timer, t, [
        (0, -100),
        (50, -100),
        (50, -50),
        (150, -50),
        (150, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
        (-250, -100),
        (-250, -50),
        (-50, -50),
        (-50, -100),
        (0, -100),
      ]);
      expect(timer.laps.length, 2);
      expect(timer.laps[1].kind, LapKind.outLap);
      expect(timer.laps[1].durationMs, 88000);
      expect(timer.inPit, isFalse);
    });

    test('进站圈停车仍按 dwell 规则不计成绩', () {
      final timer = _pitTimer(
        sectors: _sectors(),
        pitIn: _g(-100, -50),
        pitOut: _g(100, -50),
      );
      var t = _driveFirstLap(timer);

      // 第 2 圈：绕圈后进通道过入口线，在通道内原地停 35 秒，
      // 再回主直道过起终点关圈。
      t = _feedPath(timer, t, [
        (0, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
        (-250, -100),
        (-250, -50),
        (-100, -50),
      ]);
      // 入口穿越时刻 t=172000，停站计时随之递增。
      expect(timer.inPit, isTrue);
      for (var i = 1; i <= 35; i++) {
        timer.addPoint(_pt(t + i * 1000, -100, -50, 0));
      }
      t += 35000;
      expect(timer.pitStopMs, 35000);
      expect(timer.isPaused, isTrue);
      t = _feedPath(timer, t, [(-100, -50), (-50, -50), (-50, -100), (0, -100)]);
      expect(timer.laps.length, 2);
      expect(timer.laps[1].kind, LapKind.inLap);
      expect(timer.laps[1].dwellNotCounted, isTrue);
      // 总耗时 119000，扣除暂停 5000（停车 30 秒阈值后才起算），圈速 114000。
      expect(timer.laps[1].durationMs, 114000);
      expect(timer.isPaused, isFalse);
    });
  });

  group('段速', () {
    test('段速 min/max：当前段实时值，未开始的段为 null', () {
      final timer = _pitTimer(sectors: _sectors());
      timer.addPoint(_pt(0, -100, -100, 20));
      // 段 0（SF→S1）：前 200 m 用 20 m/s，后 300 m 用 30 m/s。
      var t = _feedPath(timer, 0, [(-100, -100), (200, -100)], speed: 20);
      t = _feedPath(timer, t, [(200, -100), (400, -100), (400, 0)],
          speed: 30);
      // 已过 S1（t=25000），段 0 完成，段 1 刚开始（含 S1 点本身）。
      final s0 = timer.sectorSpeeds;
      expect(s0.length, 3);
      expect(s0[0]!.minKmh, closeTo(72, 1e-6));
      expect(s0[0]!.maxKmh, closeTo(108, 1e-6));
      expect(s0[1]!.minKmh, closeTo(108, 1e-6));
      expect(s0[1]!.maxKmh, closeTo(108, 1e-6));
      expect(s0[2], isNull);
      // 段 1（S1→S2）用 25 m/s：S1 点 108 km/h 留在段内，min 90、max 108。
      t = _feedPath(timer, t, [(400, 0), (400, 100), (0, 100)], speed: 25);
      final s1 = timer.sectorSpeeds;
      expect(s1[1]!.minKmh, closeTo(90, 1e-6));
      expect(s1[1]!.maxKmh, closeTo(108, 1e-6));
      expect(s1[2]!.minKmh, closeTo(90, 1e-6));
      expect(s1[2]!.maxKmh, closeTo(90, 1e-6));
      // 段 2（S2→SF）用 25 m/s，完圈：分段 [20000, 20000, 40000]。
      t = _feedPath(timer, t, [(0, 100), (-400, 100), (-400, -100), (0, -100)],
          speed: 25);
      expect(timer.laps.length, 1);
      expect(timer.laps.first.sectorsMs, [20000, 20000, 40000]);
      // 新圈段速清零：只有起终点穿越点本身（25 m/s）在段 0。
      final s2 = timer.sectorSpeeds;
      expect(s2[0]!.minKmh, closeTo(90, 1e-6));
      expect(s2[0]!.maxKmh, closeTo(90, 1e-6));
      expect(s2[1], isNull);
      expect(s2[2], isNull);
    });

    test('无分段点时段速为空列表', () {
      final timer = _pitTimer();
      final t = _driveFirstLap(timer);
      expect(t, 94000);
      expect(timer.sectorSpeeds, isEmpty);
      expect(timer.laps.length, 1);
    });

    test('1 分段点时段速为 2 段，未开始的段为 null', () {
      final timer = _pitTimer(sectors: [_g(400, 0)]);
      timer.addPoint(_pt(0, -350, -100));
      var t = _feedPath(timer, 0, [(-350, -100), (400, -100)]);
      expect(timer.sectorSpeeds.length, 2);
      expect(timer.sectorSpeeds[0], isNotNull);
      expect(timer.sectorSpeeds[1], isNull);
      t = _feedPath(timer, t, [(400, -100), (400, 0)]);
      expect(timer.sectorSpeeds[1]!.minKmh, closeTo(90, 1e-6));
      expect(timer.sectorSpeeds[1]!.maxKmh, closeTo(90, 1e-6));
    });
  });

  group('到下一计时线距离', () {
    test('沿中心线递减、过线后切到下一边界', () {
      final timer = _pitTimer(sectors: _sectors());
      timer.addPoint(_pt(0, -350, -100)); // s=50，下一线 SF（s=400）
      expect(timer.nextLineDistanceM, closeTo(350, 5));
      var t = _feedPath(timer, 0, [(-350, -100), (-100, -100)]); // s=300
      expect(timer.nextLineDistanceM, closeTo(100, 5));
      t = _feedPath(timer, t, [(-100, -100), (0, -100), (25, -100)]);
      // 已过 SF（s=400），下一线 S1（s=900）：475 m。
      expect(timer.nextLineDistanceM, closeTo(475, 5));
      t = _feedPath(timer, t, [(25, -100), (400, -100), (400, -50)]);
      // s=850，距 S1 50 m。
      expect(timer.nextLineDistanceM, closeTo(50, 5));
      t = _feedPath(timer, t, [(400, -50), (400, 0), (400, 25)]);
      // 已过 S1（s=900），下一线 S2（s=1400）：475 m。
      expect(timer.nextLineDistanceM, closeTo(475, 5));
      t = _feedPath(timer, t, [(400, 25), (400, 100), (0, 100), (-25, 100)]);
      // 已过 S2（s=1400），下一线 SF（s=2400）：975 m。
      expect(timer.nextLineDistanceM, closeTo(975, 5));
    });

    test('反向中心线时仍按行进方向算下一线距离', () {
      final timer = _pitTimer(
        sectors: _sectors(),
        centerline: _reversedLoopCenterline(),
      );
      timer.addPoint(_pt(0, -350, -100)); // s=50，下一线 SF（s=400）
      expect(timer.nextLineDistanceM, closeTo(350, 5));
      _feedPath(timer, 0, [(-350, -100), (0, -100), (25, -100)]);
      // 切线已取反纠正：正向过线开圈，过线后切到 S1。
      expect(timer.currentLapNumber, 1);
      expect(timer.nextLineDistanceM, closeTo(475, 5));
    });

    test('无中心线或未喂点时下一线距离为 null', () {
      final noCenterline = LapTimer(
        startFinish: _g(0, -100),
        sectorPoints: _sectors(),
      );
      noCenterline.addPoint(_pt(0, -350, -100));
      expect(noCenterline.nextLineDistanceM, isNull);
      final timer = _pitTimer(sectors: _sectors());
      expect(timer.nextLineDistanceM, isNull);
    });
  });

  group('Lap kind 序列化', () {
    test("toJson 用 'k' 键，fromJson 缺失 'k' 读作 flying", () {
      const lap = Lap(
        number: 2,
        startMs: 1000,
        endMs: 90000,
        durationMs: 89000,
        pausedMs: 0,
        dwellNotCounted: false,
        sectorsMs: [30000, 30000, 29000],
        kind: LapKind.inLap,
      );
      final j = lap.toJson();
      expect(j['k'], 'in');
      expect(Lap.fromJson(j).kind, LapKind.inLap);
      expect(Lap.fromJson(j).sectorsMs, [30000, 30000, 29000]);

      // 老数据无 'k' 键：读作飞驰圈；'out' 读作出站圈。
      final old = Lap.fromJson({
        'n': 1,
        's': 0,
        'e': 80000,
        'd': 80000,
        'paused': 0,
        'dwell': false,
        'sec': [40000, 40000],
      });
      expect(old.kind, LapKind.flying);
      expect(
        Lap.fromJson({
          'n': 1,
          's': 0,
          'e': 80000,
          'd': 80000,
          'paused': 0,
          'dwell': false,
          'sec': [40000, 40000],
          'k': 'out',
        }).kind,
        LapKind.outLap,
      );
      // 构造默认 kind 为 flying。
      const def = Lap(
        number: 1,
        startMs: 0,
        endMs: 80000,
        durationMs: 80000,
        pausedMs: 0,
        dwellNotCounted: false,
        sectorsMs: [40000, 40000],
      );
      expect(def.kind, LapKind.flying);
      expect(def.toJson()['k'], 'flying');
    });
  });

  group('既有保护仍有效', () {
    test('30 秒最短圈：30 秒内再次正向过线不关圈', () {
      final timer = _pitTimer(sectors: _sectors());
      // 100 m/s 跑 2000 m 环线，一圈 20 秒 < 30 秒最短圈。
      timer.addPoint(_pt(0, -400, -100, 100));
      var t = _feedPath(timer, 0, [
        (-400, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
      ], speed: 100);
      // t=4000 开圈（t=24000 第二次过线被最短圈拦住），仍无完圈。
      expect(timer.currentLapNumber, 1);
      expect(timer.laps, isEmpty);
      // 再跑一圈：t=44000 第三次过线，距开圈 40000 ms，关圈。
      t = _feedPath(timer, t, [
        (-400, -100),
        (400, -100),
        (400, 100),
        (-400, 100),
        (-400, -100),
        (0, -100),
      ], speed: 100);
      expect(timer.laps.length, 1);
      expect(timer.laps.first.durationMs, 40000);
      expect(timer.laps.first.kind, LapKind.flying);
    });

    test('停车暂停：停车 30 秒自动暂停，圈速扣除暂停、本圈不计', () {
      final timer = _pitTimer(sectors: _sectors());
      timer.addPoint(_pt(0, -350, -100));
      var t = _feedPath(timer, 0, [(-350, -100), (400, -100), (400, 100)]);
      // 已过 SF（t=14000 开圈）、S1（t=34000），停在 (400,100)。
      for (var i = 1; i <= 35; i++) {
        timer.addPoint(_pt(t + i * 1000, 400, 100, 0));
      }
      t += 35000;
      expect(timer.isPaused, isTrue);
      t = _feedPath(timer, t, [(400, 100), (-400, 100), (-400, -100), (0, -100)]);
      expect(timer.laps.length, 1);
      expect(timer.laps.first.dwellNotCounted, isTrue);
      expect(timer.laps.first.kind, LapKind.flying);
      // 总耗时 115000（移动 80 秒 + 停车 35 秒），扣除暂停 5000，圈速 110000。
      expect(timer.laps.first.durationMs, 110000);
      expect(timer.isPaused, isFalse);
    });
  });
}
