import 'package:drive_track/models.dart';
import 'package:drive_track/recorder.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/tunnel_gap.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint pt({
  required int t,
  double lat = 39.0,
  double lon = 116.0,
  double speed = 20,
  double bearing = 90,
  bool estimated = false,
  double roll = 0,
  double longG = 0,
  double latG = 0,
  double alt = 100,
  bool altValid = true,
}) =>
    TrackPoint(
      timeMs: t,
      lat: lat,
      lon: lon,
      alt: alt,
      altValid: altValid,
      speed: speed,
      bearing: bearing,
      hAcc: 5,
      vAcc: 5,
      speedAcc: 1,
      provider: estimated ? 'estimated' : 'gps',
      longG: longG,
      latG: latG,
      vertG: 0,
      pitch: 0,
      roll: roll,
      heading: bearing,
      pressureHpa: 1013,
      calibrated: true,
      estimated: estimated,
    );

void main() {
  group('TrackPoint estimated JSON', () {
    test('est 缺省 false，老 JSON 无 est 键仍能加载', () {
      final p = pt(t: 1000);
      expect(p.estimated, isFalse);
      expect(p.toJson()['est'], isFalse);
      final legacy = Map<String, dynamic>.from(p.toJson())..remove('est');
      expect(TrackPoint.fromJson(legacy).estimated, isFalse);
      final withEst = Map<String, dynamic>.from(p.toJson())..['est'] = true;
      final back = TrackPoint.fromJson(withEst);
      expect(back.estimated, isTrue);
      expect(back.toJson()['est'], isTrue);
    });
  });

  group('Trip measured getters exclude estimates', () {
    Trip tripWithEstimates() => Trip(
          id: 't1',
          mode: TripMode.car,
          startMs: 0,
          endMs: 10000,
          points: [
            pt(t: 0, speed: 20, longG: 0.1, roll: 5, lon: 116.0),
            pt(t: 1000, speed: 25, longG: 0.2, roll: 10, lon: 116.001),
            // 推算点：速度/ G / 压弯角都更大，绝不能进统计。
            pt(t: 2000, speed: 60, longG: 2.0, roll: 45, lon: 116.002, estimated: true),
            pt(t: 3000, speed: 22, longG: 0.1, roll: 6, lon: 116.003),
          ],
          events: const [],
          score: 90,
          subScores: const {},
          scoreReasons: const [],
        );

    test('maxSpeed / maxG / maxLean 只看实测', () {
      final trip = tripWithEstimates();
      expect(trip.maxSpeed, 25);
      expect(trip.maxG, closeTo(0.2, 1e-9));
      expect(trip.maxLean, 10);
    });

    test('推算里程与实测里程分开列', () {
      final trip = tripWithEstimates();
      expect(trip.estimatedDistanceM, greaterThan(0));
      expect(trip.measuredDistanceM, greaterThan(0));
      expect(trip.distanceM,
          closeTo(trip.measuredDistanceM + trip.estimatedDistanceM, 1e-6));
    });

    test('climbM 不计推算点', () {
      final rising = Trip(
        id: 't2',
        mode: TripMode.car,
        startMs: 0,
        endMs: 6000,
        points: [
          pt(t: 0, alt: 100),
          pt(t: 1000, alt: 100),
          pt(t: 2000, alt: 100),
          pt(t: 3000, alt: 100),
          // 推算点海拔跳变 100 米，altValid=false，必须排除。
          pt(t: 4000, alt: 200, estimated: true, altValid: false),
          pt(t: 5000, alt: 100),
        ],
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
      );
      expect(rising.climbM, 0);
    });
  });

  group('shouldStartGap', () {
    test('3 秒门槛与 5 km/h 门槛', () {
      expect(shouldStartGap(elapsedMs: 3000, lastSpeedMs: 10), isFalse);
      expect(shouldStartGap(elapsedMs: 3001, lastSpeedMs: 10), isTrue);
      // 5 km/h = 1.389 m/s：低于不记缺口。
      expect(shouldStartGap(elapsedMs: 5000, lastSpeedMs: 1.0), isFalse);
      expect(shouldStartGap(elapsedMs: 5000, lastSpeedMs: 2.0), isTrue);
    });
  });

  group('decayedSpeed', () {
    test('前 10 秒保持，之后每 10 秒衰减 10%', () {
      expect(decayedSpeed(20, 0), 20);
      expect(decayedSpeed(20, 10), 20);
      expect(decayedSpeed(20, 19.9), 20);
      expect(decayedSpeed(20, 20), closeTo(18, 1e-9));
      expect(decayedSpeed(20, 30), closeTo(16.2, 1e-9));
      expect(decayedSpeed(20, 40), closeTo(14.58, 1e-9));
    });

    test('OBD 接入时用 OBD 速度，不衰减', () {
      expect(
          estimateSpeed(initialMs: 20, elapsedSec: 60, obdSpeedMs: 15), 15);
      expect(estimateSpeed(initialMs: 20, elapsedSec: 60), closeTo(11.8, 0.2));
    });
  });

  group('fillGap', () {
    test('1Hz 布点、速度线性过渡、标记位正确', () {
      final start = pt(t: 0, lat: 39.0, lon: 116.0, speed: 10, bearing: 90);
      final end = pt(
          t: 5000, lat: 39.0, lon: 116.004, speed: 20, bearing: 90);
      final fill = fillGap(start: start, end: end);
      expect(fill.length, 4);
      expect(fill.map((p) => p.timeMs), [1000, 2000, 3000, 4000]);
      expect(fill.first.speed, closeTo(12, 1e-9));
      expect(fill.last.speed, closeTo(18, 1e-9));
      for (final p in fill) {
        expect(p.estimated, isTrue);
        expect(p.hAcc, 999);
        expect(p.satCount, isNull);
        expect(p.altValid, isFalse);
        expect(p.longG, 0);
        expect(p.latG, 0);
      }
      // 沿弦：经度单调递增。
      for (var i = 1; i < fill.length; i++) {
        expect(fill[i].lon, greaterThan(fill[i - 1].lon));
      }
    });

    test('无路网超 2km 不补', () {
      final start = pt(t: 0, lat: 39.0, lon: 116.0, speed: 20);
      final end = pt(t: 60000, lat: 39.0, lon: 116.03, speed: 20);
      expect(haversineM(39.0, 116.0, 39.0, 116.03), greaterThan(2000));
      expect(fillGap(start: start, end: end), isEmpty);
    });

    test('有路网时沿路采样（折线拐弯）', () {
      final start = pt(t: 0, lat: 39.0, lon: 116.0, speed: 10);
      final end = pt(t: 4000, lat: 39.001, lon: 116.001, speed: 10);
      final road = [
        (39.0, 116.0),
        (39.001, 116.0), // 先向北
        (39.001, 116.001), // 再向东
      ];
      final fill = fillGap(start: start, end: end, roadPolyline: road);
      expect(fill.length, 3);
      // 第一个补点应在北向段上（纬度变、经度基本不变）。
      expect(fill.first.lat, greaterThan(39.0));
      expect(fill.first.lon, closeTo(116.0, 1e-6));
    });

    test('时长不足 2 秒无补点', () {
      expect(fillGap(start: pt(t: 0), end: pt(t: 1000)), isEmpty);
    });
  });

  group('replaceLiveEstimates', () {
    test('出口替换：无重复时间戳、里程只计一次', () {
      final start = pt(t: 0, speed: 20);
      final live = [
        start,
        pt(t: 1000, lon: 116.001, estimated: true),
        pt(t: 2000, lon: 116.002, estimated: true),
      ];
      final end = pt(t: 3000, lon: 116.003, speed: 20);
      final fill = fillGap(start: start, end: end);
      final out = replaceLiveEstimates(
          points: live, gapStartMs: 0, gapEndMs: 3000, fill: fill);
      final times = out.map((p) => p.timeMs).toList();
      expect(times.toSet().length, times.length);
      expect(times, [0, 1000, 2000]);
      expect(out.where((p) => p.estimated).length, 2);
    });
  });

  group('chooseGapPolyline', () {
    test('tunnel=yes 的 way 优先', () {
      final near = [
        (39.0, 116.002),
        (39.001, 116.002),
      ];
      final tunnel = [
        (39.0005, 116.0005),
        (39.0015, 116.0005),
      ];
      final picked = chooseGapPolyline(39.0, 116.0, [
        (points: near, tunnel: false),
        (points: tunnel, tunnel: true),
      ]);
      expect(picked, tunnel);
    });
  });

  group('GPX 推算分段', () {
    test('推算点单独进 <trkseg name="推算">，不混进实测段', () {
      final trip = Trip(
        id: 't3',
        mode: TripMode.car,
        startMs: 0,
        endMs: 4000,
        points: [
          pt(t: 0, lat: 39.0, lon: 116.0),
          pt(t: 1000, lat: 39.0, lon: 116.001, estimated: true),
          pt(t: 2000, lat: 39.0, lon: 116.002, estimated: true),
          pt(t: 3000, lat: 39.0, lon: 116.003),
        ],
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
      );
      final gpx = Store().toGpx(trip, trimmed: false);
      expect(gpx.contains('<trkseg name="推算">'), isTrue);
      // 实测段 2 段 + 推算段 1 段 = 3 个 trkseg。
      expect('<trkseg'.allMatches(gpx).length, 3);
      // 推算段内的 trkpt 不应出现在实测段：推算段在两个实测段之间。
      final estStart = gpx.indexOf('<trkseg name="推算">');
      final estEnd = gpx.indexOf('</trkseg>', estStart);
      final estSeg = gpx.substring(estStart, estEnd);
      expect('<trkpt'.allMatches(estSeg).length, 2);
    });
  });

  group('Recorder gap integration (fake clock)', () {
    Recorder recorderWithFixes() {
      final rec = Recorder();
      rec.state = RecState.recording;
      rec.startMs = 0;
      rec.nowProvider = () => 0;
      // 两次实测定位：t=0 与 t=1000，速度 20 m/s 向东。
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

    test('3 秒无定位开始推算，120 秒上限停发', () {
      final rec = recorderWithFixes();
      expect(rec.points.length, 2);
      rec.gapTickForTest(3000);
      expect(rec.gapStatus.value, GapStatus.ok);
      rec.gapTickForTest(4001);
      expect(rec.gapStatus.value, GapStatus.estimating);
      expect(rec.points.length, 3);
      expect(rec.points.last.estimated, isTrue);
      // 继续推算到 120 秒上限附近仍在发。
      for (var t = 5001; t <= 121001; t += 1000) {
        rec.gapTickForTest(t);
      }
      final countAtCap = rec.points.length;
      expect(countAtCap, greaterThan(10));
      rec.gapTickForTest(200001);
      expect(rec.points.length, countAtCap);
      expect(rec.gapStatus.value, GapStatus.lost);
    });

    test('出口定位到达：实时推算点被事后补段替换', () {
      final rec = recorderWithFixes();
      rec.gapTickForTest(4001);
      rec.gapTickForTest(5001);
      expect(rec.points.where((p) => p.estimated).length, 2);
      rec.onLocation({
        'lat': 39.0,
        'lon': 116.0008,
        'speed': 20.0,
        'bearing': 90.0,
        'timeMs': 6000,
        'hAcc': 5.0,
        'alt': 100.0,
        'hasAlt': true,
        'provider': 'gps',
      });
      expect(rec.gapStatus.value, GapStatus.ok);
      final times = rec.points.map((p) => p.timeMs).toList();
      expect(times.toSet().length, times.length);
      // t=6000 出口为实测；缺口内为补段推算点。
      expect(rec.points.last.timeMs, 6000);
      expect(rec.points.last.estimated, isFalse);
      expect(rec.points.where((p) => p.estimated).length, 4);
    });

    test('OBD 接入时推算速度取 OBD 速度', () {
      final rec = recorderWithFixes();
      rec.noteObdSample(speedKmh: 36); // 10 m/s
      rec.gapTickForTest(4001);
      expect(rec.points.last.speed, closeTo(10, 1e-9));
    });

    test('停车丢星不记缺口', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      rec.startMs = 0;
      rec.onLocation({
        'lat': 39.0,
        'lon': 116.0,
        'speed': 0.5,
        'bearing': 0.0,
        'timeMs': 0,
        'hAcc': 5.0,
        'provider': 'gps',
      });
      rec.gapTickForTest(10000);
      expect(rec.gapStatus.value, GapStatus.lost);
      expect(rec.points.where((p) => p.estimated).length, 0);
    });
  });
}
