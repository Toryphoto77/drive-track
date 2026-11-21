/// 融合层回归：密度高度、垂直 ESKF、腾空检测。
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/blediy_gps.dart';
import 'package:drive_track/sensor_fusion.dart';

void main() {
  test('NDJSON 的 imu/baro 帧进入融合器，并带统一时基', () {
    final feed = BleDiyGpsFeed();
    feed.feedLine(
      '{"t":"baro","tc":20.0,"pa":100000.0,"alt":100.0,"rel":0.5,'
      '"cal":1,"ts":1000000}',
    );
    expect(feed.fusion.latestBaro, isNotNull);
    expect(feed.fusion.latestBaro!.tsUs, 1000000);
    expect(feed.fusion.ekf.altitudeM, closeTo(100, 0.01));
    expect(feed.fusion.densityAltitude, isNotNull);

    feed.feedLine(
      '{"t":"imu","ax":0.0,"ay":0.0,"az":1.0,"roll":0.0,"pitch":0.0,'
      '"ts":1010000}',
    );
    expect(feed.fusion.latestImu, isNotNull);
    expect(feed.fusion.latestImu!.tsUs, 1010000);
  });

  test('密度高度：标准海平面约 0 m，高空随温度升高', () {
    expect(densityAltitudeM(pressurePa: 101325, temperatureC: 15),
        closeTo(0, 1));
    final cold = densityAltitudeM(pressurePa: 90000, temperatureC: 0);
    final hot = densityAltitudeM(pressurePa: 90000, temperatureC: 35);
    // 90000 Pa / 0°C 的 ISA 干空气密度高度约 673 m；
    // 也可用气压高度约 988 m + 120 ft/°C 的温度修正交叉核对。
    expect(cold, closeTo(673, 2));
    expect(hot, greaterThan(cold));
  });

  test('气压计无效读数不产生密度高度', () {
    expect(densityAltitudeM(pressurePa: 0, temperatureC: 20), 0);
  });

  test('ESKF 静止时被气压观测拉回，不发散', () {
    final ekf = VerticalEkf();
    var ts = 1000000;
    for (var i = 0; i < 400; i++) {
      ts += 10000; // 100 Hz
      ekf.predict(tsUs: ts, azMps2: 9.80665, pitchRad: 0, rollRad: 0);
      if (i % 10 == 0) ekf.updateBaro(100.0);
    }
    expect(ekf.altitudeM, isNotNull);
    expect(ekf.altitudeM!, closeTo(100, 1.5));
    expect(ekf.verticalSpeedMps.abs(), lessThan(0.3));
  });

  test('GPS 海拔只做低频修正，不把气压高度整体拽走', () {
    final ekf = VerticalEkf();
    var ts = 0;
    for (var i = 0; i < 200; i++) {
      ts += 10000;
      ekf.predict(tsUs: ts, azMps2: 9.80665, pitchRad: 0, rollRad: 0);
      if (i % 10 == 0) ekf.updateBaro(50.0);
    }
    ekf.updateGpsAltitude(58.0);
    expect(ekf.altitudeM!, greaterThan(49));
    expect(ekf.altitudeM!, lessThan(58));
  });

  test('腾空：失重窗口 + 速度回落后产生一次事件', () {
    final jd = JumpDetector();
    var ts = 0;
    JumpEvent? event;
    // 上升阶段（正常重力读数），垂直速度增加
    for (var i = 0; i < 10; i++) {
      ts += 10000;
      jd.update(
        imu: ImuSample(tsUs: ts, ax: 0, ay: 0, az: 1.0),
        verticalSpeedMps: i * 0.4,
      );
    }
    // 失重（1.5 g 起跳后自由落体，读数趋近 0）
    for (var i = 0; i < 20; i++) {
      ts += 10000;
      toEvent(jd, ts, 0.05, 3.0 - i * 0.35, (e) => event = e);
    }
    // 落地
    ts += 10000;
    event = jd.update(
          imu: ImuSample(tsUs: ts, ax: 0, ay: 0, az: 1.0),
          verticalSpeedMps: 0,
        ) ??
        event;
    // 至少有一次有效事件，且高度不为负
    expect(jd.events, isNotEmpty);
    expect(jd.events.first.heightM, greaterThanOrEqualTo(0));
  });

  test('短于阈值的抖动不算腾空', () {
    final jd = JumpDetector();
    var ts = 0;
    // 两个 10ms 采样低于阈值
    for (var i = 0; i < 2; i++) {
      ts += 10000;
      jd.update(
        imu: ImuSample(tsUs: ts, ax: 0, ay: 0, az: 0.2),
        verticalSpeedMps: 1.0,
      );
    }
    ts += 10000;
    jd.update(
      imu: ImuSample(tsUs: ts, ax: 0, ay: 0, az: 1.0),
      verticalSpeedMps: 0,
    );
    expect(jd.events, isEmpty);
  });
}

void toEvent(
  JumpDetector jd,
  int ts,
  double az,
  double v,
  void Function(JumpEvent?) onEvent,
) {
  final e = jd.update(
    imu: ImuSample(tsUs: ts, ax: 0, ay: 0, az: az),
    verticalSpeedMps: v,
  );
  if (e != null) onEvent(e);
}
