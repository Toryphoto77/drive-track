/// 增强项回归：增量草稿、行程侧车、云端对比、仓库链接、原生录制策略钉选。
import 'dart:convert';
import 'dart:io';

import 'package:drive_track/about_page.dart';
import 'package:drive_track/cloud_compare.dart';
import 'package:drive_track/gps_source_badge.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/recording_draft.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/track_library.dart';
import 'package:drive_track/trip_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<TrackPoint> line(int n, {int t0 = 1_000_000}) => List.generate(
      n,
      (i) => TrackPoint(
        timeMs: t0 + 1000 * i,
        lat: 31.2 + i * 0.0005,
        lon: 121.4,
        alt: 10,
        speed: 15,
        bearing: 0,
        hAcc: 3,
        vAcc: 3,
        speedAcc: 1,
        provider: 'gps',
        longG: 0,
        latG: 0,
        vertG: 0,
        pitch: 0,
        roll: 0,
        heading: 0,
        pressureHpa: 0,
        calibrated: true,
      ),
    );

void main() {
  late Directory tmp;
  late Store store;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('enhance_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'),
            (c) async {
      if (c.method == 'getFilesDir' || c.method == 'getCacheDir') {
        return tmp.path;
      }
      return null;
    });
    store = Store();
    await store.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('incremental recording draft', () {
    test('saveIncremental appends points without rewriting prior lines',
        () async {
      final drafts = RecordingDraftStore(tmp.path);
      final d1 = RecordingDraft(
        mode: TripMode.car,
        startMs: 1000,
        savedAtMs: 2000,
        points: line(5),
      );
      await drafts.saveIncremental(d1);
      final before = await File(drafts.pointsPath).readAsString();
      expect(before.trim().split('\n'), hasLength(5));

      final d2 = RecordingDraft(
        mode: TripMode.car,
        startMs: 1000,
        savedAtMs: 3000,
        points: line(8),
      );
      await drafts.saveIncremental(d2);
      final after = await File(drafts.pointsPath).readAsString();
      final lines = after.trim().split('\n');
      expect(lines, hasLength(8));
      // 前 5 行字节应原样保留（追加，不是整文件重写打乱）。
      expect(after.startsWith(before.trimRight()), isTrue);

      final loaded = await drafts.load();
      expect(loaded, isNotNull);
      expect(loaded!.points, hasLength(8));
      expect(loaded.points.last.timeMs, line(8).last.timeMs);
    });

    test('load merges native sidecar points by timeMs', () async {
      final drafts = RecordingDraftStore(tmp.path);
      await drafts.save(RecordingDraft(
        mode: TripMode.moto,
        startMs: 1000,
        savedAtMs: 2000,
        points: line(3),
      ));
      // 原生侧车：重叠 1 点 + 2 个新点
      final native = File(drafts.nativePointsPath);
      final extra = [
        line(3)[1], // overlap
        ...line(2, t0: 2_000_000),
      ];
      await native.writeAsString(
          extra.map((p) => jsonEncode(p.toJson())).join('\n') + '\n');
      final loaded = await drafts.load();
      expect(loaded!.points.length, 5); // 3 + 2 new
      expect(loaded.mode, TripMode.moto);
    });

    test('legacy v1 recording_draft.json still loads', () async {
      final drafts = RecordingDraftStore(tmp.path);
      final legacy = RecordingDraft(
        mode: TripMode.bike,
        startMs: 42,
        savedAtMs: 99,
        points: line(12),
      );
      await File(drafts.legacyPath)
          .writeAsString(jsonEncode(legacy.toJson()));
      final loaded = await drafts.load();
      expect(loaded, isNotNull);
      expect(loaded!.points, hasLength(12));
      expect(loaded.mode, TripMode.bike);
    });
  });

  group('trip points sidecar', () {
    test('small trip stays inline; large trip uses ndjson sidecar', () async {
      final smallPts = line(10);
      final small = await store.saveTrip(
          TripMode.car, 1, 2, smallPts);
      final smallBody =
          await File('${tmp.path}/trip_${small.id}.json').readAsString();
      final smallJson = jsonDecode(smallBody) as Map<String, dynamic>;
      expect(smallJson['pointsFile'], isNull);
      expect((smallJson['points'] as List).length, 10);
      expect(await File(tripPointsPath(tmp.path, small.id)).exists(), isFalse);

      // 直接走 encode，避免生成 2000+ 点的完整 saveTrip 评分耗时过长：
      // 构造一个已有 id 的 Trip 再写盘。
      final bigPts = line(kTripPointsSidecarThreshold);
      final big = Trip(
        id: 'big-side',
        mode: TripMode.car,
        startMs: 1,
        endMs: 2,
        points: bigPts,
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
      );
      await encodeTripForDisk(tmp.path, big);
      final body =
          jsonDecode(await File(tripJsonPath(tmp.path, big.id)).readAsString())
              as Map<String, dynamic>;
      expect(body['pointsFile'], 'trip_big-side.points.ndjson');
      expect(body['points'], isEmpty);
      expect(body['pointCount'], kTripPointsSidecarThreshold);
      expect(await File(tripPointsPath(tmp.path, big.id)).exists(), isTrue);

      final loaded = await decodeTripFromDisk(tmp.path, big.id);
      expect(loaded, isNotNull);
      expect(loaded!.points, hasLength(kTripPointsSidecarThreshold));
      expect(loaded.points.first.lat, bigPts.first.lat);
      expect(loaded.points.last.lat, bigPts.last.lat);
    });

    test('deleteTrip removes sidecar too', () async {
      final big = Trip(
        id: 'del-side',
        mode: TripMode.car,
        startMs: 1,
        endMs: 2,
        points: line(kTripPointsSidecarThreshold),
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
      );
      await encodeTripForDisk(tmp.path, big);
      // 写入索引以便 deleteTrip 正常跑
      await File('${tmp.path}/trips_index.json').writeAsString(jsonEncode([
        {
          'id': big.id,
          'mode': 'car',
          'start': 1,
          'end': 2,
          'dist': 0,
          'score': 0,
          'demo': false
        }
      ]));
      await store.deleteTrip(big.id);
      expect(await File(tripJsonPath(tmp.path, big.id)).exists(), isFalse);
      expect(await File(tripPointsPath(tmp.path, big.id)).exists(), isFalse);
    });
  });

  group('cloud compare', () {
    test('fromIds reports only-local / only-cloud / both', () {
      final c = CloudLocalCompare.fromIds(
          ['a', 'b', 'c'], ['b', 'c', 'd', 'e']);
      expect(c.localCount, 3);
      expect(c.cloudCount, 4);
      expect(c.onlyLocalIds, ['a']);
      expect(c.onlyCloudIds, ['d', 'e']);
      expect(c.bothIds, ['b', 'c']);
      expect(c.summary, contains('Local 3 / Cloud 4'));
    });

    test('localIdFromStoragePath parses public and private paths', () {
      expect(
          CloudLocalCompare.localIdFromStoragePath(
              'public-files/uid/trip123.json'),
          'trip123');
      expect(CloudLocalCompare.localIdFromStoragePath('uid/trip456.json'),
          'trip456');
      expect(CloudLocalCompare.localIdFromStoragePath(''), isNull);
    });
  });

  group('repo links cleaned', () {
    test('about + track library URLs use Toryphoto77', () {
      expect(kDriveTrackRepoUrl, contains('Toryphoto77/drive-track'));
      expect(kDriveTrackRepoUrl, isNot(contains('wangtao969')));
      expect(kDriveTrackAuthorUrl, contains('Toryphoto77'));
      expect(kTrackLibraryManifestUrlCdn, contains('Toryphoto77'));
      expect(kTrackLibraryManifestUrlCdn, isNot(contains('wangtao969')));
    });

    test('tracks-manifest.json package urls use Toryphoto77', () {
      final raw =
          File('data/tracks-manifest.json').readAsStringSync();
      expect(raw.contains('wangtao969'), isFalse);
      expect(raw.contains('Toryphoto77/drive-track'), isTrue);
    });
  });

  group('gps badge accuracy in label', () {
    test('phone and external labels include accuracy when provided', () {
      const phone = GpsSourceBadge(externalActive: false, accuracyM: 8);
      expect(phone.label, contains('手机 GPS'));
      expect(phone.label, contains('8 m'));
      const ext = GpsSourceBadge(
          externalActive: true, deviceName: 'BX280', accuracyM: 2, hz: 10);
      expect(ext.label, contains('外接 GPS'));
      expect(ext.label, contains('BX280'));
      expect(ext.label, contains('2 m'));
    });
  });

  group('device center as bottom tab', () {
    test('main shell uses 4-way tab including embedded DeviceCenterPage', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("ValueKey('devices')"));
      expect(main, contains('DeviceCenterPage(embedded: true)'));
      expect(main, contains('void _goTab(int i)'));
      expect(main, contains('底部导航四页同壳'));
      expect(main, isNot(contains('直接打开设备中心')));
      expect(main, contains('selectedIndex: tab.clamp(0, 3)'));
    });
  });

  group('cold start splash pins', () {
    test('system splash icon bg black; Flutter splash icon opacity 1', () {
      final v31 = File('android/app/src/main/res/values-v31/styles.xml')
          .readAsStringSync();
      expect(v31, contains('windowSplashScreenIconBackgroundColor'));
      expect(v31, contains('@android:color/black'));
      final splash = File('lib/splash_page.dart').readAsStringSync();
      expect(splash, contains('AlwaysStoppedAnimation(1.0)'));
      expect(splash, contains('Color(0xFF000000)'));
    });
  });

  group('native recording strategy pins', () {
    test('TrackService uses START_STICKY and keeps service when recording', () {
      final kt = File(
              'android/app/src/main/kotlin/com/chixi/drive_track/MainActivity.kt')
          .readAsStringSync();
      expect(kt.contains('START_STICKY'), isTrue);
      expect(kt.contains('START_NOT_STICKY'), isFalse);
      expect(kt.contains('recordingActive'), isTrue);
      expect(kt.contains('recording_native_points.ndjson'), isTrue);
      expect(kt.contains('Force-stop may interrupt'), isTrue);
      expect(
          kt.contains(
              'if (!TrackService.recordingActive)'),
          isTrue);
    });

    test('release pipeline script and checklist exist', () {
      expect(File('tools/release_pipeline.sh').existsSync(), isTrue);
      expect(File('RELEASE_CHECKLIST.md').existsSync(), isTrue);
      final sh = File('tools/release_pipeline.sh').readAsStringSync();
      expect(sh.contains('gen_update_manifest.py'), isTrue);
      expect(sh.contains('purge.jsdelivr.net'), isTrue);
      expect(sh.contains('git push'), isTrue); // mentioned as manual step
      expect(sh.contains('本脚本不执行 git push'), isTrue);
    });
  });
}
