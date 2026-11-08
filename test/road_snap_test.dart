/// 街道模式 GPS 精度测试（v1.5.3 攒版）。
///
/// 覆盖：贴路只认同向路段（对向车道不贴）、单线双向路反向节点
/// 仍能贴、无路网/超距/垂直方向不贴；低速锁方向、停车定点、
/// 跳变过滤与重采纳（手机定位与外接定位两路）。

import 'package:drive_track/recorder.dart';
import 'package:drive_track/road_snap.dart';
import 'package:flutter_test/flutter_test.dart';

// 东西向双向路：A 车道（东向，lat 39.0）与 B 车道（西向，
// lat 39.0001，约 11 米北）——中间相当于隔离带。
final List<(double, double)> laneEast = [
  (39.0, 116.0),
  (39.0, 116.01),
];
final List<(double, double)> laneWest = [
  (39.0001, 116.01),
  (39.0001, 116.0),
];
// 单线双向路：节点顺序与行进方向相反。
final List<(double, double)> twoWayReversed = [
  (39.0, 116.01),
  (39.0, 116.0),
];

void main() {
  group('snapToRoad', () {
    test('同向路段：偏北 8.8 米的点贴回东向车道', () {
      final out = snapToRoad(
        lat: 39.00008,
        lon: 116.005,
        headingDeg: 90,
        ways: [laneEast, laneWest],
      );
      expect(out.lat, closeTo(39.0, 1e-6));
      expect(out.lon, closeTo(116.005, 1e-6));
    });

    test('对向车道不贴：离西向车道仅 2.2 米，仍贴回东向车道', () {
      // 点离 B 车道（西向）只有 2.2 米、离 A 车道 8.8 米；
      // 行进方向东，第一遍排除对向车道，必须贴 A 而不是更近的 B。
      final out = snapToRoad(
        lat: 39.00008,
        lon: 116.005,
        headingDeg: 90,
        ways: [laneEast, laneWest],
      );
      expect(out.lat, closeTo(39.0, 1e-6));
      expect(out.lat, isNot(closeTo(39.0001, 1e-6)));
    });

    test('单线双向路节点反向：第二遍按直线方向仍能贴', () {
      final out = snapToRoad(
        lat: 39.00005,
        lon: 116.005,
        headingDeg: 90,
        ways: [twoWayReversed],
      );
      expect(out.lat, closeTo(39.0, 1e-6));
    });

    test('无路网 / 超距 / 垂直方向：原样返回', () {
      const orig = (lat: 39.00005, lon: 116.005);
      final noWays = snapToRoad(
          lat: orig.lat, lon: orig.lon, headingDeg: 90, ways: const []);
      expect((noWays.lat, noWays.lon), (orig.lat, orig.lon));
      final tooFar = snapToRoad(
        lat: 39.001,
        lon: 116.005,
        headingDeg: 90,
        ways: [laneEast],
      );
      expect((tooFar.lat, tooFar.lon), (39.001, 116.005));
      final perpendicular = snapToRoad(
        lat: orig.lat,
        lon: orig.lon,
        headingDeg: 0,
        ways: [laneEast],
      );
      expect((perpendicular.lat, perpendicular.lon), (orig.lat, orig.lon));
    });
  });

  group('RoadSnapper', () {
    test('注入路网可贴，reset 后不贴', () {
      final snapper = RoadSnapper();
      expect(
          snapper.snap(39.00008, 116.005, 90), (lat: 39.00008, lon: 116.005));
      snapper.setWaysForTest([laneEast, laneWest]);
      expect(snapper.hasRoads, isTrue);
      final out = snapper.snap(39.00008, 116.005, 90);
      expect(out.lat, closeTo(39.0, 1e-6));
      snapper.reset();
      expect(snapper.hasRoads, isFalse);
      expect(
          snapper.snap(39.00008, 116.005, 90), (lat: 39.00008, lon: 116.005));
    });
  });

  group('Recorder 街道 GPS 精度', () {
    late Recorder rec;

    setUp(() {
      rec = Recorder();
      rec.state = RecState.recording;
    });

    void feedLocation({
      required double lat,
      required double lon,
      required double speed,
      required double bearing,
      required int t,
      double hAcc = 5,
    }) {
      rec.onLocation({
        'lat': lat,
        'lon': lon,
        'speed': speed,
        'bearing': bearing,
        'timeMs': t,
        'hAcc': hAcc,
      });
    }

    test('低速锁方向：低于 5km/h 时航向沿用上个可靠值', () {
      feedLocation(lat: 39.0, lon: 116.0, speed: 10, bearing: 90, t: 1000);
      expect(rec.curHeading, 90);
      // 3.6km/h 停车瞬间航向跳到 200°：不跟，仍锁 90°。
      feedLocation(
          lat: 39.0, lon: 116.00002, speed: 1, bearing: 200, t: 2000);
      expect(rec.curHeading, 90);
      expect(rec.points.last.bearing, 90);
      expect(rec.points.last.heading, 90);
      // 速度回来后重新采纳新航向。
      feedLocation(
          lat: 39.0, lon: 116.00004, speed: 10, bearing: 180, t: 3000);
      expect(rec.curHeading, 180);
    });

    test('停车定点：速度归零后漂移的点不再落点', () {
      feedLocation(lat: 39.0, lon: 116.0, speed: 10, bearing: 90, t: 1000);
      feedLocation(
          lat: 39.0001, lon: 116.0001, speed: 0, bearing: 90, t: 2000);
      feedLocation(
          lat: 38.9999, lon: 115.9999, speed: 0, bearing: 270, t: 3000);
      feedLocation(
          lat: 39.00005, lon: 116.00005, speed: 0, bearing: 45, t: 4000);
      expect(rec.points.length, 4);
      for (var i = 1; i < rec.points.length; i++) {
        expect(rec.points[i].lat, 39.0);
        expect(rec.points[i].lon, 116.0);
      }
      expect(rec.curLat, 39.0);
      expect(rec.curLon, 116.0);
    });

    test('跳变过滤：单次 111 米跳变被拒，连续 3 次同位置重采纳', () {
      feedLocation(lat: 39.0, lon: 116.0, speed: 10, bearing: 90, t: 1000);
      feedLocation(
          lat: 39.0, lon: 116.0001, speed: 10, bearing: 90, t: 2000);
      // 1 秒内跳 111 米：不可能的速度，拒收，留在上个接受点。
      feedLocation(
          lat: 39.001, lon: 116.0002, speed: 10, bearing: 90, t: 3000);
      expect(rec.points.length, 3);
      expect(rec.points.last.lat, 39.0);
      expect(rec.points.last.lon, closeTo(116.0001, 1e-9));
      // 同一新位置第 2 次：仍拒收。
      feedLocation(
          lat: 39.001, lon: 116.0002, speed: 10, bearing: 90, t: 4000);
      expect(rec.points.last.lat, 39.0);
      // 第 3 次：重采纳为新位置。
      feedLocation(
          lat: 39.001, lon: 116.0002, speed: 10, bearing: 90, t: 5000);
      expect(rec.points.last.lat, closeTo(39.001, 1e-9));
      expect(rec.points.last.lon, closeTo(116.0002, 1e-9));
    });

    test('贴路：注入路网后，偏向对向车道的点贴回同向车道', () {
      rec.setRoadWaysForTest([laneEast, laneWest]);
      feedLocation(
          lat: 39.00008, lon: 116.005, speed: 10, bearing: 90, t: 1000);
      expect(rec.points.length, 1);
      expect(rec.points.last.lat, closeTo(39.0, 1e-6));
      expect(rec.points.last.lon, closeTo(116.005, 1e-6));
    });

    test('贴路关闭（赛道）时不贴', () {
      rec.roadSnapEnabled = false;
      rec.setRoadWaysForTest([laneEast, laneWest]);
      feedLocation(
          lat: 39.00008, lon: 116.005, speed: 10, bearing: 90, t: 1000);
      expect(rec.points.last.lat, closeTo(39.00008, 1e-9));
    });

    test('外接定位同样锁方向', () {
      rec.onExternalFix(39.0, 116.0, 10, 90, 1000);
      expect(rec.curHeading, 90);
      rec.onExternalFix(39.0, 116.00002, 1, 200, 2000);
      expect(rec.curHeading, 90);
      expect(rec.points.last.bearing, 90);
    });
  });
}
