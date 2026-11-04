/// v1.2.0 收口集成测试（只覆盖收口阶段新增/改动的口径）。
///
/// 注意：Store 的文件操作经 MethodChannel 'drivetrack/native' 拿
/// filesDir，本测试用 setMockMethodCallHandler 把它指向系统临时目录，
/// 不碰真机目录、不写仓库；跑完删临时目录。
import 'dart:convert';
import 'dart:io';

import 'package:drive_track/fuel_page.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/photo_points.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/trip_analytics_page.dart';
import 'package:drive_track/vehicle_profile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

List<TrackPoint> _points(int n) => [
      for (var i = 0; i < n; i++)
        TrackPoint(
          timeMs: 1700000000000 + i * 1000,
          lat: 31.0 + i * 0.001,
          lon: 121.0 + i * 0.001,
          alt: 10,
          speed: 10,
          bearing: 45,
          hAcc: 5,
          vAcc: 8,
          speedAcc: 0.5,
          provider: 'gps',
          longG: 0.1,
          latG: 0.1,
          vertG: 0,
          pitch: 0,
          roll: 0,
          heading: 45,
          pressureHpa: 1013,
          calibrated: true,
        ),
    ];

void main() {
  group('TripMeta track/vehicleId 往返与旧索引兼容', () {
    test('新字段往返', () {
      const m = TripMeta('x', TripMode.car, 1000, 2000, 1500, 80, false,
          isPublic: true,
          likes: 3,
          isTrackMode: true,
          trackId: 'shanghai',
          trackName: '上海',
          vehicleId: 'v1');
      final back = TripMeta.fromJson(m.toJson());
      expect(back.isTrackMode, isTrue);
      expect(back.trackId, 'shanghai');
      expect(back.trackName, '上海');
      expect(back.vehicleId, 'v1');
      expect(back.isPublic, isTrue);
      expect(back.likes, 3);
    });

    test('旧索引缺键回退为街道/未绑定，不丢旧数据', () {
      final back = TripMeta.fromJson({
        'id': 'old',
        'mode': 'car',
        'start': 1000,
        'end': 2000,
        'dist': 1500,
        'score': 80,
        'demo': false,
      });
      expect(back.isTrackMode, isFalse);
      expect(back.trackId, isNull);
      expect(back.trackName, '');
      expect(back.vehicleId, isNull);
    });

    test('Trip vehicleId 往返，缺键为 null', () {
      final t = Trip(
        id: 't1',
        mode: TripMode.moto,
        startMs: 1000,
        endMs: 2000,
        points: const [],
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
        vehicleId: 'v9',
      );
      expect(Trip.fromJson(t.toJson()).vehicleId, 'v9');
      final json = t.toJson()..remove('vehicleId');
      expect(Trip.fromJson(json).vehicleId, isNull);
    });
  });

  group('天气新鲜度短路逻辑', () {
    const now = 1700000000000;
    test('10 分钟内且未移出 10 km 时不重拉', () {
      expect(
        weatherNeedsRefresh(
            hasWeather: true,
            weatherMs: now - 5 * 60 * 1000,
            nowMs: now,
            cachedLat: 31.0,
            cachedLon: 121.0,
            lat: 31.0,
            lon: 121.0),
        isFalse,
      );
    });
    test('无旧天气、超 10 分钟、移出 10 km 时都要重拉', () {
      expect(
          weatherNeedsRefresh(hasWeather: false, weatherMs: 0, nowMs: now),
          isTrue);
      expect(
          weatherNeedsRefresh(
              hasWeather: true, weatherMs: now - 11 * 60 * 1000, nowMs: now),
          isTrue);
      expect(
          weatherNeedsRefresh(
              hasWeather: true,
              weatherMs: now - 1000,
              nowMs: now,
              cachedLat: 31.0,
              cachedLon: 121.0,
              lat: 31.5,
              lon: 121.0),
          isTrue);
    });
  });

  group('分析页分组纯函数', () {
    AnalyticsTripInput input({
      required String id,
      required bool track,
      required int startMs,
      double score = 80,
      double maxG = 0.2,
      List<int> laps = const [],
      bool demo = false,
    }) =>
        AnalyticsTripInput(
          id: id,
          mode: TripMode.car,
          isTrackMode: track,
          trackId: track ? 'shanghai' : null,
          trackName: track ? '上海' : '',
          startMs: startMs,
          endMs: startMs + 600000,
          distanceM: 10000,
          score: score,
          demo: demo,
          maxSpeedKmh: 90,
          maxG: maxG,
          countedLapDurationsMs: laps,
        );

    test('街道/赛道分组，演示排除，赛道不进评分分布', () {
      final s = summarizeAnalyticsTrips([
        input(id: 'a', track: false, startMs: 1000, score: 95, maxG: 0.9),
        input(id: 'b', track: false, startMs: 2000, score: 50, maxG: 0.2),
        input(id: 'c', track: true, startMs: 3000, laps: [90000, 92000, 88000]),
        input(id: 'd', track: false, startMs: 4000, demo: true),
      ]);
      expect(s.street.tripCount, 2);
      expect(s.street.totalDistanceKm, 20);
      expect(s.street.scoreBuckets['90+'], 1);
      expect(s.street.scoreBuckets['<60'], 1);
      expect(s.street.gBuckets['≥0.8g'], 1);
      expect(s.track.tripCount, 1);
      expect(s.track.totalLaps, 3);
      expect(s.track.bestLapMs, 88000);
      expect(s.track.hasStability, isTrue);
    });

    test('范围过滤：近 30 天含界内、不含界外与未来', () {
      const now = 1700000000000;
      const day = 24 * 3600 * 1000;
      expect(
          analyticsTripInRange(
              startMs: now - 29 * day, range: AnalyticsRange.last30, nowMs: now),
          isTrue);
      expect(
          analyticsTripInRange(
              startMs: now - 31 * day, range: AnalyticsRange.last30, nowMs: now),
          isFalse);
      expect(
          analyticsTripInRange(
              startMs: now + day, range: AnalyticsRange.last30, nowMs: now),
          isFalse);
      expect(
          analyticsTripInRange(
              startMs: now - 100 * day,
              range: AnalyticsRange.custom,
              nowMs: now,
              customStartMs: now - 200 * day,
              customEndMs: now - 50 * day),
          isTrue);
      expect(
          analyticsTripInRange(
              startMs: now - 10 * day,
              range: AnalyticsRange.custom,
              nowMs: now,
              customStartMs: now - 200 * day,
              customEndMs: now - 50 * day),
          isFalse);
    });
  });

  group('油耗按车分组与任意区间', () {
    test('每车油耗优先、未绑定进全局组、实测分开列', () {
      final groups = summarizeFuelByVehicle(
        trips: [
          const FuelTripInput(mode: TripMode.car, distanceM: 100000, startMs: 1000, vehicleId: 'v1'),
          const FuelTripInput(mode: TripMode.moto, distanceM: 50000, startMs: 2000),
          const FuelTripInput(mode: TripMode.bike, distanceM: 20000, startMs: 3000, vehicleId: 'v1'),
          const FuelTripInput(mode: TripMode.car, distanceM: 100000, startMs: 999999999, vehicleId: 'v1'),
        ],
        startMs: 0,
        endMs: 100000,
        globalConsumptionLPer100Km: 8,
        globalPricePerLiter: 8,
        perVehicleConsumption: const {'v1': 6},
        measuredConsumptionByVehicle: const {'v1': 5},
        vehicleNames: const {'v1': '家里的车'},
      );
      expect(groups.length, 2);
      final v1 = groups.firstWhere((g) => g.vehicleId == 'v1');
      expect(v1.estimatedLiters, closeTo(6, 0.001));
      expect(v1.measuredLiters, closeTo(5, 0.001));
      expect(v1.measuredCost, closeTo(40, 0.001));
      final unbound = groups.firstWhere((g) => g.vehicleId == null);
      expect(unbound.label, '未指定车辆（全局值）');
      expect(unbound.estimatedLiters, closeTo(4, 0.001));
      expect(unbound.hasMeasured, isFalse);
    });
  });

  group('Store 文件级：上限、批量删除、迁移、车辆回退', () {
    late Directory tmp;
    late Store store;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tmp = await Directory.systemTemp.createTemp('v120_');
      const channel = MethodChannel('drivetrack/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getFilesDir') return tmp.path;
        return null;
      });
      store = Store();
      await store.init();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('drivetrack/native'), null);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('updateTripPhotoPointsChecked：超 50 条保留前 50 条并报告超限', () async {
      final trip = await store.saveTrip(
          TripMode.car, 1700000000000, 1700000600000, _points(20));
      final pts = [
        for (var i = 0; i < 60; i++)
          PhotoPoint(lat: 31.0 + i * 0.001, lon: 121.0, timeMs: 1700000000000 + i * 1000)
      ];
      final r = await store.updateTripPhotoPointsChecked(trip.id, pts);
      expect(r.truncated, isTrue);
      expect(r.inputCount, 60);
      expect(r.savedCount, 50);
      expect(r.trip!.photoPoints.length, 50);
      expect(r.trip!.photoPoints.first.lat, 31.0);
      expect(kMaxPhotoPointsPerTrip, 50);
    });

    test('deleteTrips 同步清理 favorites 孤儿 id，视频不受影响', () async {
      final a = await store.saveTrip(
          TripMode.car, 1700000000000, 1700000600000, _points(20));
      final b = await store.saveTrip(
          TripMode.moto, 1700000000000, 1700000600000, _points(20));
      await store.toggleFavorite(a.id);
      await store.toggleFavorite(b.id);
      await store.deleteTrips([a.id]);
      expect((await store.loadIndex()).any((m) => m.id == a.id), isFalse);
      expect((await store.loadIndex()).any((m) => m.id == b.id), isTrue);
      final fav = await store.loadFavorites();
      expect(fav.contains(a.id), isFalse);
      expect(fav.contains(b.id), isTrue);
    });

    test('migrateIndexTrackFields：旧索引无赛道键时回填 Trip 真实字段', () async {
      final trip = await store.saveTrip(
        TripMode.car, 1700000000000, 1700000600000, _points(20),
        trackId: 'shanghai',
        trackName: '上海',
        isTrackMode: true,
        vehicleId: 'v1',
      );
      // 模拟旧索引：去掉赛道/车辆键后写回。
      final metas = await store.loadIndex();
      final raw = metas.map((m) => m.toJson()).toList();
      for (final j in raw) {
        j.remove('trackMode');
        j.remove('trackId');
        j.remove('trackName');
        j.remove('vehicleId');
      }
      await File('${tmp.path}/trips_index.json').writeAsString(jsonEncode(raw));
      final migrated = await store.migrateIndexTrackFields();
      final back = migrated.firstWhere((m) => m.id == trip.id);
      expect(back.isTrackMode, isTrue);
      expect(back.trackId, 'shanghai');
      expect(back.trackName, '上海');
      expect(back.vehicleId, 'v1');
    });

    test('车辆库往返 + 删除车辆回退绑定行程', () async {
      final trip = await store.saveTrip(
          TripMode.car, 1700000000000, 1700000600000, _points(20),
          vehicleId: 'v1');
      const lib = VehicleLibrary(
        vehicles: [
          VehicleProfile(id: 'v1', name: '家里的车', consumptionLPer100Km: 6),
        ],
        fuelLogs: [],
        defaultVehicleId: 'v1',
      );
      await store.saveVehicleLibrary(lib);
      expect((await store.loadVehicleLibrary()).vehicles.first.name, '家里的车');
      expect(await store.loadVehicleLibrary().then((l) => l.defaultVehicleId), 'v1');
      final changed = await store.rebindTripsAfterVehicleDeleted('v1');
      expect(changed, 1);
      expect((await store.loadTrip(trip.id))!.vehicleId, isNull);
      expect((await store.loadIndex()).firstWhere((m) => m.id == trip.id).vehicleId, isNull);
    });

    test('删除车辆辅助函数：只回退被删车辆的绑定', () {
      expect(tripVehicleIdAfterVehicleDeleted('v1', 'v1'), isNull);
      expect(tripVehicleIdAfterVehicleDeleted('v1', 'v2'), 'v2');
      expect(tripVehicleIdAfterVehicleDeleted('v1', null), isNull);
    });
  });
}
