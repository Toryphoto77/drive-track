/// 审计修复回归测试（2026-11-09）：每组对应一个已复现 / 已确认的问题，
/// 修复前这些用例会失败。不发真实网络请求（下载走本机 HttpServer），
/// 不读任何密钥。
import 'dart:convert';
import 'dart:io';

import 'package:drive_track/atomic_file.dart';
import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/photo_points.dart';
import 'package:drive_track/public_trip.dart';
import 'package:drive_track/recording_draft.dart';
import 'package:drive_track/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 沿经线每点约 55 m 的直线轨迹（n 个点、1 Hz）。
List<TrackPoint> line(int n, {int t0 = 1000000}) => List.generate(
    n,
    (i) => TrackPoint(
        timeMs: t0 + 1000 * i, lat: 31.2 + i * 0.0005, lon: 121.4, alt: 10, speed: 15, bearing: 0,
        hAcc: 3, vAcc: 3, speedAcc: 1, provider: 'gps', longG: 0, latG: 0, vertG: 0, pitch: 0,
        roll: 0, heading: 0, pressureHpa: 0, calibrated: true));

void main() {
  late Directory tmp;
  late Store store;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('audit_fix_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'), (c) async {
      if (c.method == 'getFilesDir' || c.method == 'getCacheDir') return tmp.path;
      return null;
    });
    store = Store();
    await store.init();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'), null);
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('field preservation (Trip.copyWith)', () {
    test('obdSamples survive enrichment / social / photo / vehicle rebind', () async {
      final t = await store.saveTrip(TripMode.car, 0, 60000, line(60),
          obdSamples: [{'t': 1001000, 'rpm': 3000}], vehicleId: 'car1');
      await store.updateTripEnrichment(t.id, correctionStatus: 'skipped');
      expect((await store.loadTrip(t.id))!.obdSamples, hasLength(1));
      await store.updateTripSocial(t.id, isPublic: true);
      expect((await store.loadTrip(t.id))!.obdSamples, hasLength(1));
      await store.updateTripPhotoPointsChecked(
          t.id, [const PhotoPoint(lat: 31.2, lon: 121.4, timeMs: 1001000)]);
      expect((await store.loadTrip(t.id))!.obdSamples, hasLength(1));
      expect(await store.rebindTripsAfterVehicleDeleted('car1'), 1);
      final after = (await store.loadTrip(t.id))!;
      expect(after.obdSamples, hasLength(1));
      expect(after.vehicleId, isNull);
      expect(after.isPublic, isTrue);
      expect(after.photoPoints, hasLength(1));
      expect((await store.loadIndex()).single.vehicleId, isNull);
    });

    test('toggling public keeps start/end place names in the index', () async {
      final t = await store.saveTrip(TripMode.car, 0, 60000, line(60));
      await store.updateTripEnrichment(t.id, startPlace: 'A', endPlace: 'B');
      await store.updateTripSocial(t.id, isPublic: true);
      final m = (await store.loadIndex()).single;
      expect(m.startPlace, 'A');
      expect(m.endPlace, 'B');
      expect(m.isPublic, isTrue);
    });

    test('concurrent updates on one trip do not overwrite each other', () async {
      final t = await store.saveTrip(TripMode.car, 0, 60000, line(60));
      await Future.wait([
        store.updateTripEnrichment(t.id, startPlace: 'A', correctionStatus: 'done'),
        store.updateTripSocial(t.id, isPublic: true),
        store.updateTripSocial(t.id, toggleLike: true),
      ]);
      final after = (await store.loadTrip(t.id))!;
      expect(after.startPlace, 'A');
      expect(after.correctionStatus, 'done');
      expect(after.isPublic, isTrue);
      expect(after.liked, isTrue);
    });
  });

  group('index persistence', () {
    test('corrupted index is rebuilt from trip files, nothing hidden or deleted', () async {
      for (var i = 0; i < 3; i++) {
        await store.saveTrip(TripMode.car, i * 100000, i * 100000 + 60000, line(30, t0: i * 100000));
        await Future.delayed(const Duration(milliseconds: 3));
      }
      final idx = File('${tmp.path}/trips_index.json');
      final s = await idx.readAsString();
      await idx.writeAsString(s.substring(0, s.length ~/ 2)); // 模拟写一半被杀
      await store.saveTrip(TripMode.car, 900000, 960000, line(30, t0: 900000));
      final metas = await store.loadIndex();
      final tripFiles = tmp
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'trip_.+\.json$').hasMatch(f.path))
          .length;
      expect(tripFiles, 4);
      expect(metas, hasLength(4));
      expect(metas.map((m) => m.id).toSet(), hasLength(4));
      expect(metas.first.startMs, 900000, reason: 'newest first');
      final corrupt = tmp.listSync().where((e) => e.path.contains('trips_index.corrupt-'));
      expect(corrupt, hasLength(1), reason: 'damaged index kept for diagnosis');
    });

    test('missing index is rebuilt by migrateIndexTrackFields on startup', () async {
      await store.saveTrip(TripMode.moto, 0, 60000, line(30));
      await store.saveTrip(TripMode.car, 100000, 160000, line(30, t0: 100000));
      await File('${tmp.path}/trips_index.json').delete();
      final metas = await store.migrateIndexTrackFields();
      expect(metas, hasLength(2));
      expect(File('${tmp.path}/trips_index.json').existsSync(), isTrue);
    });

    test('atomic write leaves no temp file and a complete target', () async {
      final p = '${tmp.path}/x.json';
      await writeStringAtomic(p, '{"a":1}');
      await writeStringAtomic(p, '{"a":2}');
      expect(jsonDecode(File(p).readAsStringSync()), {'a': 2});
      expect(File('$p.tmp').existsSync(), isFalse);
    });
  });

  group('public upload sanitization', () {
    Trip sample({bool trim = true, int n = 120}) {
      final pts = line(n);
      return Trip(
        id: '1', mode: TripMode.car, startMs: pts.first.timeMs, endMs: pts.last.timeMs,
        points: pts,
        events: [
          TripEvent(kind: 'harshBrake', startMs: pts[2].timeMs, endMs: pts[3].timeMs, startIndex: 2, endIndex: 3,
              peakLongG: -0.5, peakLatG: 0, entrySpeed: 10, minSpeed: 5, exitSpeed: 5),
          if (n > 62) TripEvent(kind: 'corner', startMs: pts[60].timeMs, endMs: pts[62].timeMs, startIndex: 60, endIndex: 62,
              peakLongG: 0, peakLatG: 0.4, entrySpeed: 10, minSpeed: 8, exitSpeed: 10),
        ],
        score: 90, subScores: const {}, scoreReasons: const [],
        trimPrivacy: trim, isPublic: true,
        videoPaths: const ['/data/user/0/com.chixi.drive_track/files/trip_1.mp4'],
        photoPoints: [
          PhotoPoint(lat: pts[1].lat, lon: pts[1].lon, timeMs: pts[1].timeMs,
              photoPath: '/data/user/0/com.chixi.drive_track/files/photo_points/a.jpg'),
          if (n > 62)
            PhotoPoint(lat: pts[60].lat, lon: pts[60].lon, timeMs: pts[60].timeMs,
                photoPath: '/data/user/0/com.chixi.drive_track/files/photo_points/b.jpg', note: 'mid'),
        ],
        obdSamples: [
          {'t': pts[1].timeMs, 'rpm': 1000},
          if (n > 62) {'t': pts[60].timeMs, 'rpm': 3000},
        ],
        correctedPoints: [(pts.first.lat, pts.first.lon)],
        correctionStatus: 'done',
        startPlace: 'Home street', endPlace: 'Office',
      );
    }

    test('public copy trims ends, drops local paths and end-point metadata', () {
      final t = sample();
      final p = publicTripCopy(t);
      expect(p.points.first.lat, greaterThan(t.points.first.lat));
      expect(p.points.last.lat, lessThan(t.points.last.lat));
      expect(haversineM(t.points.first.lat, t.points.first.lon, p.points.first.lat, p.points.first.lon),
          greaterThanOrEqualTo(kPrivacyTrimM));
      expect(p.videoPaths, isEmpty);
      expect(p.photoPoints, hasLength(1));
      expect(p.photoPoints.single.photoPath, isNull);
      expect(p.photoPoints.single.note, 'mid');
      expect(p.photoPoints.single.effectiveType, PhotoPointType.photo);
      expect(p.obdSamples, hasLength(1));
      expect(p.correctedPoints, isEmpty);
      expect(p.startPlace, isEmpty);
      expect(p.endPlace, isEmpty);
      expect(p.events.map((e) => e.kind), ['corner']);
      final ev = p.events.single;
      expect(p.points[ev.startIndex].timeMs, t.points[60].timeMs, reason: 'event index re-aligned');
      final json = jsonEncode(p.toJson());
      expect(json, isNot(contains('/data/user/0')));
      expect(Trip.fromJson(jsonDecode(json) as Map<String, dynamic>).points, hasLength(p.points.length));
    });

    test('too-short public trip publishes no track points', () {
      final p = publicTripCopy(sample(n: 12));
      expect(p.points, isEmpty);
      expect(p.photoPoints, isEmpty);
    });

    test('user-disabled trim keeps the track but still strips local paths', () {
      final t = sample(trim: false);
      final p = publicTripCopy(t);
      expect(p.points, hasLength(t.points.length));
      expect(p.videoPaths, isEmpty);
      expect(p.photoPoints.every((x) => x.photoPath == null), isTrue);
    });

    test('cloud upload bytes: public sanitized, private full backup', () {
      final pub = utf8.decode(cloudTripBytes(sample()));
      expect(pub, isNot(contains('/data/user/0')));
      expect(pub, isNot(contains('Home street')));
      final priv = utf8.decode(cloudTripBytes(sample().copyWith(isPublic: false)));
      expect(priv, contains('/data/user/0'));
      final full = Trip.fromJson(jsonDecode(priv) as Map<String, dynamic>);
      expect(full.points, hasLength(120));
    });
  });

  group('recording draft', () {
    test('draft round-trips and recovers into a trip with OBD + markers', () async {
      final drafts = RecordingDraftStore(tmp.path);
      final pts = line(40);
      await drafts.save(RecordingDraft(
        mode: TripMode.moto, startMs: pts.first.timeMs, savedAtMs: pts.last.timeMs + 5000,
        points: pts, obdSamples: [{'t': pts[5].timeMs, 'rpm': 4000}],
        photoPoints: [PhotoPoint(lat: pts[5].lat, lon: pts[5].lon, timeMs: pts[5].timeMs)],
        vehicleId: 'm1',
      ));
      final d = (await drafts.load())!;
      expect(d.points, hasLength(40));
      final trip = (await drafts.recoverInto(store, d))!;
      expect(trip.endMs, pts.last.timeMs);
      expect(trip.obdSamples, hasLength(1));
      expect(trip.photoPoints, hasLength(1));
      expect(trip.vehicleId, 'm1');
      expect(await drafts.load(), isNull, reason: 'draft cleared after recovery');
      expect((await store.loadIndex()).single.id, trip.id);
    });

    test('too-short draft is not saved; corrupt draft is set aside', () async {
      final drafts = RecordingDraftStore(tmp.path);
      final d = RecordingDraft(mode: TripMode.car, startMs: 0, savedAtMs: 1, points: line(5));
      await drafts.save(d);
      expect(await drafts.recoverInto(store, d), isNull);
      await File(drafts.metaPath).writeAsString('{"mode":"car","start":0,"po');
      expect(await drafts.load(), isNull);
      expect(tmp.listSync().where((e) => e.path.contains('recording_draft_meta.corrupt-')), hasLength(1));
    });
  });

  group('native / build config source pins', () {
    final kt = File('android/app/src/main/kotlin/com/chixi/drive_track/MainActivity.kt').readAsStringSync();
    test('Bluetooth base UUID is the SIG value everywhere', () {
      expect(kt, isNot(contains('00805f9b34b0')));
      expect(kt, contains('00002902-0000-1000-8000-00805f9b34fb'));
    });
    test('background-thread Bluetooth events are marshalled to the main thread', () {
      expect(kt, contains('{ map -> emitOnMain { bleDataSink?.success(map) } }'));
      expect(kt, contains('{ map -> emitOnMain { obdSink?.success(map) } }'));
      expect(kt, contains('emitOnMain { parseBle(uuid, bytes) }'));
    });
    test('default BLE scan clears a stale service filter', () {
      expect(kt, contains('"startBleScan" -> {'));
      final i = kt.indexOf('"startBleScan" -> {');
      expect(kt.substring(i, i + 400), contains('scanServiceFilter = null'));
    });
    test('release signing path is not machine-specific', () {
      final g = File('android/app/build.gradle.kts').readAsStringSync();
      expect(g, isNot(contains('/home/hatch')));
      expect(g, contains('DRIVETRACK_KEYSTORE'));
    });
  });
}
