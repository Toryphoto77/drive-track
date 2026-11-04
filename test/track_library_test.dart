/// 赛道库测试：数据模型、合并规则、版本比对、几何工具、行程录入、
/// 最快圈分类、服务持久化（MethodChannel mock，不依赖真实网络与文件）。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drive_track/models.dart';
import 'package:drive_track/track_guide.dart';
import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPackage _pkg({
  String id = 'test',
  int version = 1,
  TrackPackageSource source = TrackPackageSource.osm,
  bool userModified = false,
  bool isUserTrack = false,
  List<GeoPoint> centerline = const [],
  GeoPoint? start,
  List<GeoPoint> sectors = const [],
}) {
  return TrackPackage(
    id: id,
    nameCn: '测试赛道 $id',
    nameEn: 'Test $id',
    region: '中国',
    version: version,
    source: source,
    sourceDetail: 'test',
    verification: TrackPackageVerification.pending,
    centerline: centerline,
    lengthM: 5000,
    start: start,
    sectorPoints: sectors,
    userModified: userModified,
    isUserTrack: isUserTrack,
  );
}

void main() {
  group('数据模型', () {
    test('包 JSON 往返（含弯角 / 分段 / 起终点 / 龙门架 / 空值）', () {
      final pkg = TrackPackage(
        id: 'shanghai',
        nameCn: '上海国际赛车场',
        nameEn: 'Shanghai International Circuit',
        region: '中国',
        version: 1,
        source: TrackPackageSource.osm,
        sourceDetail: 'OSM relation 2094941',
        verification: TrackPackageVerification.verified,
        verificationNote: '名称一致；闭合回路',
        centerline: const [
          GeoPoint(31.3376, 121.2223),
          GeoPoint(31.3380, 121.2230),
          GeoPoint(31.3376, 121.2223),
        ],
        lengthM: 5459,
        publishedLengthM: 5451,
        corners: const [
          TrackCorner(
            number: 1,
            direction: 'left',
            radiusM: 120,
            angleDeg: 90,
            point: GeoPoint(31.3380, 121.2230),
          ),
        ],
        cornerSource: 'osm-derived',
        sectorPoints: const [GeoPoint(31.3385, 121.2240)],
        sectorNote: '分段点待核',
        gantry: const GeoPoint(31.3370, 121.2210),
        start: const GeoPoint(31.3373, 121.2206),
        finish: const GeoPoint(31.3373, 121.2206),
        startNote: 'OSM start 节点',
      );
      final back = TrackPackage.fromJson(
        jsonDecode(jsonEncode(pkg.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, 'shanghai');
      expect(back.version, 1);
      expect(back.source, TrackPackageSource.osm);
      expect(back.verification, TrackPackageVerification.verified);
      expect(back.centerline.length, 3);
      expect(back.lengthM, 5459);
      expect(back.publishedLengthM, 5451);
      expect(back.corners.length, 1);
      expect(back.corners.first.direction, 'left');
      expect(back.cornerSource, 'osm-derived');
      expect(back.sectorPoints.length, 1);
      expect(back.gantry, isNotNull);
      expect(back.start, isNotNull);
      expect(back.finish, isNotNull);
      expect(back.hasCenterline, isTrue);
      expect(back.hasStartFinish, isTrue);
      expect(back.isVerified, isTrue);
      expect(back.lengthLabel, contains('5.459'));
    });

    test('缺失键回落（不抛错，空列表 / 待核）', () {
      final pkg = TrackPackage.fromJson({'id': 'x'});
      expect(pkg.nameCn, '');
      expect(pkg.version, 0);
      expect(pkg.centerline, isEmpty);
      expect(pkg.corners, isEmpty);
      expect(pkg.start, isNull);
      expect(pkg.lengthLabel, '长度待核');
      expect(pkg.verification, TrackPackageVerification.pending);
    });

    test('种子包 JSON 格式解析（与 tools/seed_fetch.py 输出一致）', () {
      final pkg = TrackPackage.fromJson(
        jsonDecode('''
{
  "id": "sepang", "nameCn": "雪邦国际赛车场",
  "nameEn": "Sepang International Circuit", "region": "马来西亚",
  "version": 1, "source": "osm",
  "sourceDetail": "OSM relation 284496",
  "verification": "verified", "verificationNote": "名称一致",
  "centerline": [{"lat": 2.76, "lon": 101.73}, {"lat": 2.77, "lon": 101.74}],
  "lengthM": 5516, "publishedLengthM": 5543,
  "corners": [], "cornerSource": null,
  "sectorPoints": [], "sectorNote": "分段点待核",
  "gantry": null,
  "start": {"lat": 2.76, "lon": 101.73},
  "finish": {"lat": 2.76, "lon": 101.73},
  "startNote": "OSM start 节点",
  "userModified": false, "isUserTrack": false
}
''') as Map<String, dynamic>,
      );
      expect(pkg.id, 'sepang');
      expect(pkg.isVerified, isTrue);
      expect(pkg.centerline.length, 2);
      expect(pkg.gantry, isNull);
      expect(pkg.cornerSource, isNull);
    });
  });

  group('合并规则', () {
    test('打包种子 v1 覆盖内置迁移 v0', () {
      final merged = mergePackages(
        builtin: [_pkg(id: 'a', version: 0, source: TrackPackageSource.estimated)],
        bundled: [_pkg(id: 'a', version: 1, source: TrackPackageSource.osm)],
        overrides: const [],
      );
      expect(merged.length, 1);
      expect(merged.first.version, 1);
      expect(merged.first.source, TrackPackageSource.osm);
    });

    test('用户改动无条件胜出（远端 v2 也覆盖不了本地改动 v1）', () {
      final merged = mergePackages(
        builtin: [_pkg(id: 'a', version: 0)],
        bundled: [_pkg(id: 'a', version: 1)],
        overrides: [_pkg(id: 'a', version: 1, userModified: true)],
      );
      expect(merged.first.version, 1);
      expect(merged.first.userModified, isTrue);
    });

    test('远端高版本覆盖本地未改动低版本，低版本不覆盖高版本', () {
      final up = mergePackages(
        builtin: [_pkg(id: 'a', version: 1)],
        bundled: const [],
        overrides: [_pkg(id: 'a', version: 2)],
      );
      expect(up.first.version, 2);
      final down = mergePackages(
        builtin: [_pkg(id: 'a', version: 2)],
        bundled: const [],
        overrides: [_pkg(id: 'a', version: 1)],
      );
      expect(down.first.version, 2);
    });

    test('用户赛道绝不进入官方列表，远端新增 id 正常加入', () {
      final merged = mergePackages(
        builtin: [_pkg(id: 'a', version: 1)],
        bundled: const [],
        overrides: [
          _pkg(id: 'user_x', version: 1, isUserTrack: true),
          _pkg(id: 'b', version: 1),
        ],
      );
      expect(merged.map((p) => p.id), containsAll(['a', 'b']));
      expect(merged.map((p) => p.id), isNot(contains('user_x')));
    });
  });

  group('版本比对（manifest diff）', () {
    TrackLibraryManifest manifest(String dataVersion, List<Map<String, dynamic>> pkgs) {
      return TrackLibraryManifest.fromJson({
        'dataVersion': dataVersion,
        'packages': pkgs,
      });
    }

    test('版本一致 → 已是最新', () {
      final r = diffUpdates(
        localOfficial: [_pkg(id: 'a', version: 2)],
        manifest: manifest('1.0', [
          {'id': 'a', 'nameCn': 'A', 'version': 2, 'url': 'u', 'source': 'osm'},
        ]),
      );
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.updates, isEmpty);
    });

    test('远端高版本 → 可更新；本地改动 → 跳过不列入', () {
      final r = diffUpdates(
        localOfficial: [
          _pkg(id: 'a', version: 1),
          _pkg(id: 'b', version: 1, userModified: true),
        ],
        manifest: manifest('1.1', [
          {'id': 'a', 'nameCn': 'A', 'version': 2, 'url': 'u', 'source': 'osm'},
          {'id': 'b', 'nameCn': 'B', 'version': 2, 'url': 'u', 'source': 'osm'},
        ]),
      );
      expect(r.status, UpdateCheckStatus.available);
      expect(r.updates.map((u) => u.id), ['a']);
      expect(r.skippedUserModified.map((u) => u.id), ['b']);
      expect(r.remoteDataVersion, '1.1');
    });

    test('本地缺失 → 远端新增包（localVersion -1，isNew）', () {
      final r = diffUpdates(
        localOfficial: const [],
        manifest: manifest('1.0', [
          {'id': 'n', 'nameCn': 'N', 'version': 1, 'url': 'u', 'source': 'osm'},
        ]),
      );
      expect(r.updates.length, 1);
      expect(r.updates.first.isNew, isTrue);
      expect(r.updates.first.localVersion, -1);
    });

    test('网络部分用 fake：拉 manifest → 解析 → 比对（不依赖真实网络）', () async {
      Future<String> fakeFetcher(Uri uri) async {
        expect(uri.toString(), contains('tracks-manifest.json'));
        return jsonEncode({
          'dataVersion': '1.2',
          'packages': [
            {
              'id': 'a',
              'nameCn': 'A',
              'version': 3,
              'url': 'https://example.invalid/a.json',
              'source': 'osm',
            },
          ],
        });
      }

      final body = await fakeFetcher(Uri.parse(kTrackLibraryManifestUrl));
      final m = TrackLibraryManifest.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      final r = diffUpdates(
        localOfficial: [_pkg(id: 'a', version: 2)],
        manifest: m,
      );
      expect(r.status, UpdateCheckStatus.available);
      expect(r.updates.first.remoteVersion, 3);
    });
  });

  group('内置迁移（21 条原样保留，不编坐标）', () {
    test('21 条、版本 0、一律待核、无经纬度、无起终点', () {
      final pkgs = builtinPackages();
      expect(pkgs.length, 21);
      for (final p in pkgs) {
        expect(p.version, 0, reason: p.id);
        expect(p.verification, TrackPackageVerification.pending, reason: p.id);
        expect(p.centerline, isEmpty, reason: p.id);
        expect(p.start, isNull, reason: p.id);
        expect(p.finish, isNull, reason: p.id);
        expect(p.gantry, isNull, reason: p.id);
        expect(p.sectorPoints, isEmpty, reason: p.id);
        expect(p.lengthM, isNotNull, reason: p.id);
      }
    });

    test('OSM 三条标 OSM，其余标估算', () {
      final byId = {for (final p in builtinPackages()) p.id: p};
      expect(byId['monaco']!.source, TrackPackageSource.osm);
      expect(byId['sepang']!.source, TrackPackageSource.osm);
      expect(byId['bathurst']!.source, TrackPackageSource.osm);
      expect(byId['shanghai']!.source, TrackPackageSource.estimated);
      expect(byId['spa']!.source, TrackPackageSource.estimated);
    });
  });

  group('几何工具', () {
    test('归一化保长宽比、居中（东西向线 y=0.5，x 拉满 0~1）', () {
      final norm = normalizeLatLon(const [
        GeoPoint(0, 0),
        GeoPoint(0, 1),
      ]);
      expect(norm.length, 2);
      expect(norm[0].x, closeTo(0, 1e-9));
      expect(norm[1].x, closeTo(1, 1e-9));
      expect(norm[0].y, closeTo(0.5, 1e-9));
      expect(norm[1].y, closeTo(0.5, 1e-9));
    });

    test('编辑器投影往返（project → unproject 还原）', () {
      final pts = const [
        GeoPoint(31.33, 121.21),
        GeoPoint(31.35, 121.23),
        GeoPoint(31.34, 121.22),
      ];
      final proj = LatLonProjection(pts);
      for (final p in pts) {
        final (x, y) = proj.project(p, 400, 300);
        final back = proj.unproject(x, y, 400, 300);
        expect(back.lat, closeTo(p.lat, 1e-6));
        expect(back.lon, closeTo(p.lon, 1e-6));
      }
    });

    test('Douglas-Peucker：直线压成端点，端点必保留', () {
      final line = List<GeoPoint>.generate(
        21,
        (i) => GeoPoint(31.0, 121.0 + i * 0.001),
      );
      final simplified = simplifyPolyline(line, 3.0);
      expect(simplified.length, 2);
      expect(simplified.first.lat, 31.0);
      expect(simplified.last.lon, closeTo(121.02, 1e-9));
    });

    test('折线长度：赤道 0.01° 经度约 1113m', () {
      final len = polylineLengthM(const [
        GeoPoint(0, 0),
        GeoPoint(0, 0.01),
      ]);
      expect(len, closeTo(1113, 5));
    });
  });

  group('包适配选赛道', () {
    test('有中心线的包 → 真实中心线归一化示意 + 起终点', () {
      final pkg = _pkg(
        id: 'user_x',
        centerline: const [
          GeoPoint(31.33, 121.21),
          GeoPoint(31.35, 121.23),
          GeoPoint(31.34, 121.22),
          GeoPoint(31.33, 121.21),
        ],
        start: const GeoPoint(31.33, 121.21),
      );
      final info = trackInfoForPackage(pkg);
      expect(info.id, 'user_x');
      expect(info.outline.length, 4);
      expect(info.startFinishPoint, isNotNull);
      expect(info.lengthKm, closeTo(5.0, 0.01));
    });

    test('无中心线的官方包 → 回落旧目录条目', () {
      final pkg = _pkg(id: 'shanghai', version: 0);
      final info = trackInfoForPackage(pkg);
      expect(info.id, 'shanghai');
      expect(info.nameCn, '上海国际赛车场');
      expect(info.outline.length, greaterThanOrEqualTo(3));
    });
  });

  group('行程录入', () {
    TrackPoint pt(int t, double lat, double lon) => TrackPoint(
          timeMs: t,
          lat: lat,
          lon: lon,
          alt: 0,
          speed: 0,
          bearing: 0,
          hAcc: 0,
          vAcc: 0,
          speedAcc: 0,
          provider: 'gps',
          longG: 0,
          latG: 0,
          vertG: 0,
          pitch: 0,
          roll: 0,
          heading: 0,
          pressureHpa: 0,
          calibrated: false,
        );

    test('闭合回路行程 → 用户赛道包（起终点同点、长度 > 0）', () {
      final loop = <TrackPoint>[];
      const n = 40;
      for (var i = 0; i <= n; i++) {
        final a = i / n * 2 * math.pi;
        // 约 1km 见方的小环
        loop.add(pt(i * 1000, 31.34 + 0.004 * math.sin(a), 121.22 + 0.004 * math.cos(a)));
      }
      final trip = Trip(
        id: 't1',
        mode: TripMode.car,
        startMs: 1000,
        endMs: 2000,
        points: loop,
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
      );
      final pkg = packageFromTrip(trip);
      expect(pkg, isNotNull);
      expect(pkg!.isUserTrack, isTrue);
      expect(pkg.id, 'user_1000');
      expect(pkg.centerline.length, greaterThanOrEqualTo(10));
      expect(pkg.start, isNotNull);
      expect(pkg.finish, isNotNull);
      expect(pkg.start!.lat, pkg.finish!.lat);
      expect(pkg.lengthM, greaterThan(0));
    });

    test('点数不足 → null（不编数据）', () {
      final trip = Trip(
        id: 't2',
        mode: TripMode.car,
        startMs: 1000,
        endMs: 2000,
        points: [pt(0, 31.0, 121.0), pt(1000, 31.0, 121.001)],
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
      );
      expect(packageFromTrip(trip), isNull);
    });
  });

  group('最快圈按车型分栏', () {
    test('场次后缀去掉后同车型归一栏', () {
      expect(lapRecordCategory('F1'), 'F1');
      expect(lapRecordCategory('F1 排位赛'), 'F1');
      expect(lapRecordCategory('F1 冲刺排位赛'), 'F1');
      expect(lapRecordCategory('ILMC 排位赛'), 'ILMC');
      expect(lapRecordCategory('官方计时挑战（非正赛）'), '官方计时挑战');
      expect(
        lapRecordCategory('Ferrari Racing Days 表演（非正赛）'),
        'Ferrari Racing Days',
      );
    });
  });

  group('服务持久化（mock getFilesDir）', () {
    late Directory tmp;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tmp = await Directory.systemTemp.createTemp('track_lib_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('drivetrack/native'),
        (call) async {
          if (call.method == 'getFilesDir') return tmp.path;
          return null;
        },
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('drivetrack/native'),
        null,
      );
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('保存用户赛道 → loadAll 读回（官方更新不触碰用户赛道）', () async {
      final service = TrackLibraryService.instance;
      final user = _pkg(id: 'user_1', isUserTrack: true);
      await service.savePackage(user);
      final snap = await service.loadAll();
      expect(snap.userTracks.map((p) => p.id), contains('user_1'));
      expect(snap.official.map((p) => p.id), isNot(contains('user_1')));
      await service.deleteUserTrack('user_1');
      final snap2 = await service.loadAll();
      expect(snap2.userTracks.map((p) => p.id), isNot(contains('user_1')));
    });

    test('官方包本地编辑 → 覆盖层；恢复默认后回到内置迁移', () async {
      final service = TrackLibraryService.instance;
      final edited = _pkg(id: 'shanghai', version: 0, userModified: true);
      await service.savePackage(edited);
      var snap = await service.loadAll();
      expect(
        snap.official.firstWhere((p) => p.id == 'shanghai').userModified,
        isTrue,
      );
      await service.resetOverride('shanghai');
      snap = await service.loadAll();
      expect(
        snap.official.firstWhere((p) => p.id == 'shanghai').userModified,
        isFalse,
      );
    });
  });
}
