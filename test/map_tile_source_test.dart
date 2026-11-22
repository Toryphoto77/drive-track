import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/amap_service.dart';
import 'package:drive_track/map_tile_source.dart';

/// v1.8.3 地图源单测：
/// - 高德 / 谷歌的路网与卫星瓦片 URL 必须落到不同域名与坐标系；
/// - 选择持久化到本机 map_tile_source.json，重启后可读回；
/// - WGS-84 → GCJ-02 在国内偏移数百米，框外原样返回（叠加层对齐依据）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dt_map_src_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drivetrack/native'),
      (call) async =>
          call.method == 'getFilesDir' ? tmp.path : null,
    );
    mapTileSourceStore.resetForTest();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('drivetrack/native'),
      null,
    );
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('高德与谷歌的瓦片 URL 域名 / 参数不同', () {
    final amapRoad = roadTileUrl(MapTileSource.amap, 16, 53910, 24827);
    final googleRoad = roadTileUrl(MapTileSource.google, 16, 53910, 24827);
    expect(amapRoad, contains('is.autonavi.com'));
    expect(amapRoad, contains('style=8'));
    expect(googleRoad, contains('mt'));
    expect(googleRoad, contains('google.com'));
    expect(googleRoad, contains('lyrs=m'));
    expect(amapRoad, isNot(equals(googleRoad)));

    final amapSat = satelliteTileUrlFor(MapTileSource.amap, 16, 1, 2);
    final googleSat = satelliteTileUrlFor(MapTileSource.google, 16, 1, 2);
    expect(amapSat, contains('webst0'));
    expect(amapSat, contains('style=6'));
    expect(googleSat, contains('lyrs=s'));
    expect(amapSat, isNot(equals(googleSat)));
  });

  test('瓦片源坐标系：高德 GCJ-02，谷歌 WGS-84', () {
    expect(MapTileSource.amap.usesGcj, isTrue);
    expect(MapTileSource.google.usesGcj, isFalse);
  });

  test('默认高德；setSource 写盘后新实例可读回谷歌', () async {
    await mapTileSourceStore.load();
    expect(mapTileSourceStore.source, MapTileSource.amap);

    await mapTileSourceStore.setSource(MapTileSource.google);
    expect(mapTileSourceStore.source, MapTileSource.google);

    final f = File('${tmp.path}/map_tile_source.json');
    expect(await f.exists(), isTrue);
    expect(
      (jsonDecode(await f.readAsString()) as Map<String, dynamic>)['source'],
      'google',
    );

    // 模拟冷启动：重新 load 应读回用户选择。
    mapTileSourceStore.resetForTest();
    await mapTileSourceStore.load();
    expect(mapTileSourceStore.source, MapTileSource.google);
  });

  test('WGS-84 → GCJ-02：国内偏移明显，国外原样返回', () {
    const lat = 39.9042, lon = 116.4074; // 北京
    final (gLat, gLon) = wgsToGcjLocal(lat, lon);
    final dyM = (gLat - lat).abs() * 111320;
    final dxM = (gLon - lon).abs() * 111320 * 0.76;
    expect(dyM, greaterThan(100));
    expect(dxM, greaterThan(100));
    expect(dyM, lessThan(1000));
    expect(dxM, lessThan(1000));

    const tokyoLat = 35.6762, tokyoLon = 139.6503;
    final (tLat, tLon) = wgsToGcjLocal(tokyoLat, tokyoLon);
    expect(tLat, tokyoLat);
    expect(tLon, tokyoLon);
  });
}
