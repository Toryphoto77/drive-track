/// v1.2.18（A 路：GPX 航点 + CSV 分段列）测试。
///
/// 覆盖：
/// - GPX 有点加航点（起终点 + S1 + S2 共 3 个 wpt，名字正确，位置在
///   <trk> 之前，按 GPX 1.1 XSD 顺序）；
/// - GPX 只有起终点 / 只有分段点时各只加对应的航点；
/// - GPX 无点不加 wpt、默认参数输出与改前逐字节一致；
/// - CSV 赛道行程追加分段小节，缺失段留空（绝不填 0）；
/// - CSV 分段门控：hasSectorPoints=false 时三列全留空，null（未告知）
///   时 2 段退化半圈留空、3 段才写值；
/// - CSV 街道行程无小节且与改前一致；
/// - CSV 无 laps 的赛道行程无小节。
/// 不含任何真实赛道坐标；全部用测试坐标。

import 'package:drive_track/models.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _pt(int t, double lat, double lon) {
  return TrackPoint(
    timeMs: t,
    lat: lat,
    lon: lon,
    alt: 10,
    speed: 20,
    bearing: 90,
    hAcc: 5,
    vAcc: 5,
    speedAcc: 1,
    provider: 'gps',
    longG: 0.1,
    latG: 0.2,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: 90,
    pressureHpa: 1013,
    calibrated: true,
  );
}

Lap _lap(int n, int duration, List<int> sectors) {
  return Lap(
    number: n,
    startMs: n * 100000,
    endMs: n * 100000 + duration,
    durationMs: duration,
    pausedMs: 0,
    dwellNotCounted: false,
    sectorsMs: sectors,
  );
}

Trip _trip({bool isTrackMode = false, List<Map<String, dynamic>> lapsJson = const []}) {
  return Trip(
    id: 't1',
    mode: TripMode.car,
    startMs: 100000,
    endMs: 200000,
    points: [_pt(100000, 31.0, 121.0), _pt(150000, 31.01, 121.01)],
    events: const [],
    score: 0,
    subScores: const {},
    scoreReasons: const [],
    trackId: isTrackMode ? 'test-track' : null,
    trackName: isTrackMode ? '测试赛道' : '',
    isTrackMode: isTrackMode,
    lapsJson: lapsJson,
  );
}

/// 改前 GPX（无航点）的逐字节期望：按旧 toGpx 实现逐行拼出。
String _oldGpx(Trip trip) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="DriveTrack" xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('<trk><name>${trip.mode.label} ${DateTime.fromMillisecondsSinceEpoch(trip.startMs)}</name><trkseg>');
  for (final p in trip.points) {
    final ele = p.altValid ? '<ele>${p.alt.toStringAsFixed(1)}</ele>' : '';
    b.writeln('<trkpt lat="${p.lat}" lon="${p.lon}">$ele'
        '<time>${DateTime.fromMillisecondsSinceEpoch(p.timeMs).toUtc().toIso8601String()}</time></trkpt>');
  }
  b.writeln('</trkseg></trk></gpx>');
  return b.toString();
}

/// 改前 CSV（无分段小节）的逐字节期望：按旧 toCsv 实现逐行拼出。
String _oldCsv(Trip trip) {
  final b = StringBuffer()
    ..writeln('time,lat,lon,alt_m,speed_kmh,bearing,hAcc_m,longG,latG,pitch_deg,roll_deg,powerW,powerEstimated,cadenceRpm,heartRate,sensorStatus');
  for (final p in trip.points) {
    b.writeln('${DateTime.fromMillisecondsSinceEpoch(p.timeMs).toIso8601String()},${p.lat},${p.lon},'
        '${p.alt.toStringAsFixed(1)},${(p.speed * 3.6).toStringAsFixed(1)},${p.bearing.toStringAsFixed(0)},'
        '${p.hAcc.toStringAsFixed(1)},${p.longG.toStringAsFixed(3)},${p.latG.toStringAsFixed(3)},'
        '${p.pitch.toStringAsFixed(1)},${p.roll.toStringAsFixed(1)},${p.powerW ?? ''},${p.powerEstimated},'
        '${p.cadenceRpm ?? ''},${p.heartRate ?? ''},${p.sensorStatus}');
  }
  return b.toString();
}

int _wptCount(String gpx) => '<wpt '.allMatches(gpx).length;

void main() {
  final store = Store();

  group('GPX 分段航点', () {
    test('有点加航点：起终点 + S1 + S2 共 3 个 wpt，名字正确', () {
      final gpx = store.toGpx(
        _trip(isTrackMode: true),
        trimmed: false,
        startFinish: const GeoPoint(31.0, 121.0),
        sectorPoints: const [GeoPoint(31.005, 121.005), GeoPoint(31.008, 121.008)],
      );
      expect(_wptCount(gpx), 3);
      expect(gpx, contains('<wpt lat="31.0" lon="121.0"><name>起终点</name></wpt>'));
      expect(gpx, contains('<wpt lat="31.005" lon="121.005"><name>S1</name></wpt>'));
      expect(gpx, contains('<wpt lat="31.008" lon="121.008"><name>S2</name></wpt>'));
      // 航点按 GPX 1.1 XSD 顺序写在 <trk> 之前，且不在 <trkseg> 内。
      expect(gpx.indexOf('<wpt '), lessThan(gpx.indexOf('<trk>')));
      expect(gpx.indexOf('</trk>'), lessThan(gpx.indexOf('</gpx>')));
      // 不写来源字样。
      expect(gpx, isNot(contains('实测')));
      expect(gpx, isNot(contains('官方')));
    });

    test('只有起终点时只加 1 个 wpt', () {
      final gpx = store.toGpx(
        _trip(isTrackMode: true),
        trimmed: false,
        startFinish: const GeoPoint(31.0, 121.0),
      );
      expect(_wptCount(gpx), 1);
      expect(gpx, contains('<name>起终点</name>'));
    });

    test('只有分段点时只加 S1/S2，不加起终点', () {
      final gpx = store.toGpx(
        _trip(isTrackMode: true),
        trimmed: false,
        sectorPoints: const [GeoPoint(31.005, 121.005), GeoPoint(31.008, 121.008)],
      );
      expect(_wptCount(gpx), 2);
      expect(gpx, isNot(contains('起终点')));
      expect(gpx, contains('<name>S1</name>'));
      expect(gpx, contains('<name>S2</name>'));
    });

    test('无点不加 wpt', () {
      final gpx = store.toGpx(_trip(isTrackMode: true), trimmed: false);
      expect(_wptCount(gpx), 0);
      expect(gpx, isNot(contains('<wpt')));
    });

    test('默认参数老行为不变：与改前逐字节一致', () {
      final trip = _trip(isTrackMode: true);
      expect(store.toGpx(trip, trimmed: false), _oldGpx(trip));
      // 显式传空分段点也与改前一致。
      expect(
        store.toGpx(trip, trimmed: false, sectorPoints: const []),
        _oldGpx(trip),
      );
    });
  });

  group('CSV 分段小节', () {
    test('赛道行程追加小节，缺失段留空（绝不填 0）', () {
      final trip = _trip(isTrackMode: true, lapsJson: [
        _lap(1, 100000, [30000, 40000, 30000]).toJson(),
        // 第 2 圈只触发了 S1：S2/S3 缺失，留空。
        _lap(2, 99000, [28000]).toJson(),
      ]);
      // 告知有真实分段点：按实际长度写值。
      final csv = store.toCsv(trip, hasSectorPoints: true);
      // 逐点行部分与改前一致。
      expect(csv.startsWith(_oldCsv(trip)), isTrue);
      // 小节：空行 + 表头 + 每圈一行（圈号从 1 起按 lapsJson 顺序）。
      expect(
        csv.substring(_oldCsv(trip).length),
        '\nlap,total_ms,s1_ms,s2_ms,s3_ms\n'
        '1,100000,30000,40000,30000\n'
        '2,99000,28000,,\n',
      );
    });

    test('hasSectorPoints=false 时三列全留空（不把退化半圈当分段）', () {
      final trip = _trip(isTrackMode: true, lapsJson: [
        _lap(1, 100000, [50000, 50000]).toJson(),
      ]);
      final csv = store.toCsv(trip, hasSectorPoints: false);
      expect(
        csv.substring(_oldCsv(trip).length),
        '\nlap,total_ms,s1_ms,s2_ms,s3_ms\n'
        '1,100000,,,\n',
      );
    });

    test('未告知时 2 段退化半圈留空、3 段才写值', () {
      final trip = _trip(isTrackMode: true, lapsJson: [
        _lap(1, 95000, [32451, 28103, 35220]).toJson(),
        // 2 段可能是无分段点的退化半圈：未告知时不写。
        _lap(2, 100000, [50000, 50000]).toJson(),
      ]);
      final csv = store.toCsv(trip);
      expect(
        csv.substring(_oldCsv(trip).length),
        '\nlap,total_ms,s1_ms,s2_ms,s3_ms\n'
        '1,95000,32451,28103,35220\n'
        '2,100000,,,\n',
      );
    });

    test('街道行程无小节且与改前一致', () {
      final trip = _trip();
      final csv = store.toCsv(trip);
      expect(csv, _oldCsv(trip));
      expect(csv, isNot(contains('lap,total_ms')));
    });

    test('无 laps 的赛道行程无小节', () {
      final trip = _trip(isTrackMode: true, lapsJson: const []);
      final csv = store.toCsv(trip);
      expect(csv, _oldCsv(trip));
      expect(csv, isNot(contains('lap,total_ms')));
      // 不得多一个空行：末尾即最后一条逐点行。
      expect(csv.endsWith('\n'), isTrue);
      expect(csv.endsWith('\n\n'), isFalse);
    });
  });
}
