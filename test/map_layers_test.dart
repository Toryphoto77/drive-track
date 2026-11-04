import 'package:drive_track/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> wayEl(Map<String, String> tags, List<List<double>> geom) {
  return {
    'type': 'way',
    'tags': tags,
    'geometry': [
      for (final p in geom) {'lat': p[0], 'lon': p[1]},
    ],
  };
}

List<List<double>> square(double lat, double lon, double d) => [
      [lat, lon],
      [lat, lon + d],
      [lat + d, lon + d],
      [lat + d, lon],
    ];

void main() {
  test('图层查询含水体/建筑/绿地/山峰子句，600 米、服务端 12 秒', () {
    final q = buildLayerOverpassQuery(31.0, 121.0);
    expect(q, contains('[timeout:12]'));
    expect(q, contains('around:600,31.0,121.0'));
    expect(q, contains('way["natural"="water"]'));
    expect(q, contains('way["landuse"="reservoir"]'));
    expect(q, contains('way["waterway"="riverbank"]'));
    expect(q, contains('way["waterway"="river"]'));
    expect(q, contains('way["waterway"="stream"]'));
    expect(q, contains('way["building"]'));
    expect(q, contains('way["leisure"="park"]'));
    expect(q, contains('way["landuse"="forest"]'));
    expect(q, contains('node["natural"="peak"]'));
    expect(q, contains('relation["natural"="water"]'));
    // 等值子句，不用正则（个别镜像对方言正则支持不一致会整站 400）。
    expect(q.contains('~'), isFalse);
  });

  test('水体面：闭合环原样，未闭合环自动补首点', () {
    final closed = parseOverpassLayers({
      'elements': [
        wayEl({'natural': 'water'}, [
          ...square(31.0, 121.0, 0.001),
          [31.0, 121.0],
        ]),
      ],
    });
    expect(closed.waters.length, 1);
    expect(closed.waters.first.outers.first.length, 5);
    expect(closed.waters.first.inners, isEmpty);

    final open = parseOverpassLayers({
      'elements': [wayEl({'natural': 'water'}, square(31.0, 121.0, 0.001))],
    });
    expect(open.waters.length, 1);
    final ring = open.waters.first.outers.first;
    expect(ring.length, 5);
    expect(ring.first, ring.last);
  });

  test('水体线：river/stream 成线，riverbank 成面', () {
    final layers = parseOverpassLayers({
      'elements': [
        wayEl({'waterway': 'river'}, [
          [31.0, 121.0],
          [31.001, 121.001],
        ]),
        wayEl({'waterway': 'stream'}, [
          [31.0, 121.0],
          [31.001, 121.002],
        ]),
        wayEl({'waterway': 'riverbank'}, square(31.0, 121.0, 0.001)),
      ],
    });
    expect(layers.waterLines.length, 2);
    expect(layers.waters.length, 1);
  });

  test('水体 relation：外环与内环齐全，岛不涂水', () {
    final layers = parseOverpassLayers({
      'elements': [
        {
          'type': 'relation',
          'tags': {'natural': 'water'},
          'members': [
            {
              'type': 'way',
              'role': 'outer',
              'geometry': [
                for (final p in [...square(31.0, 121.0, 0.01), [31.0, 121.0]])
                  {'lat': p[0], 'lon': p[1]},
              ],
            },
            {
              'type': 'way',
              'role': 'inner',
              'geometry': [
                for (final p in [...square(31.002, 121.002, 0.002), [31.002, 121.002]])
                  {'lat': p[0], 'lon': p[1]},
              ],
            },
          ],
        },
      ],
    });
    expect(layers.waters.length, 1);
    expect(layers.waters.first.outers.length, 1);
    expect(layers.waters.first.inners.length, 1);
  });

  test('建筑面：任意 building=* 值都算，超限按离中心最近保留 400', () {
    final elements = <Map<String, dynamic>>[];
    for (var i = 0; i < 500; i++) {
      // 每栋向北递增约 11 米，第 500 栋在 5.5 公里外。
      elements.add(wayEl(
          {'building': i.isEven ? 'yes' : 'apartments'},
          square(31.0 + i * 0.0001, 121.0, 0.0001)));
    }
    final layers = parseOverpassLayers({'elements': elements},
        centerLat: 31.0, centerLon: 121.0);
    expect(layers.buildings.length, maxBuildings);
    // 最远的栋被砍掉：保留的最大首点纬度不超过第 400 栋。
    var maxLat = 0.0;
    for (final b in layers.buildings) {
      if (b.points.first.$1 > maxLat) maxLat = b.points.first.$1;
    }
    expect(maxLat, lessThanOrEqualTo(31.0 + 399 * 0.0001 + 1e-9));
  });

  test('绿地：park/forest/meadow/grass/village_green/recreation_ground 算，住宅用地不算', () {
    final layers = parseOverpassLayers({
      'elements': [
        wayEl({'leisure': 'park'}, square(31.0, 121.0, 0.001)),
        wayEl({'landuse': 'forest'}, square(31.01, 121.0, 0.001)),
        wayEl({'landuse': 'meadow'}, square(31.02, 121.0, 0.001)),
        wayEl({'landuse': 'grass'}, square(31.03, 121.0, 0.001)),
        wayEl({'landuse': 'village_green'}, square(31.04, 121.0, 0.001)),
        wayEl({'landuse': 'recreation_ground'}, square(31.05, 121.0, 0.001)),
        wayEl({'landuse': 'residential'}, square(31.06, 121.0, 0.001)),
      ],
    });
    expect(layers.greens.length, 6);
  });

  test('山峰点：名字与海拔解析，带单位海拔取数字，无海拔不编造', () {
    final layers = parseOverpassLayers({
      'elements': [
        {
          'type': 'node',
          'lat': 31.1,
          'lon': 121.1,
          'tags': {'natural': 'peak', 'name': '玉龙雪山', 'ele': '5596'},
        },
        {
          'type': 'node',
          'lat': 31.2,
          'lon': 121.2,
          'tags': {'natural': 'peak', 'name': '泰山', 'ele': '1545 m'},
        },
        {
          'type': 'node',
          'lat': 31.3,
          'lon': 121.3,
          'tags': {'natural': 'peak'},
        },
        {
          'type': 'node',
          'lat': 31.4,
          'lon': 121.4,
          'tags': {'natural': 'spring'},
        },
      ],
    });
    expect(layers.peaks.length, 3);
    expect(layers.peaks[0].name, '玉龙雪山');
    expect(layers.peaks[0].eleM, 5596);
    expect(layers.peaks[1].eleM, 1545);
    expect(layers.peaks[2].name, '');
    expect(layers.peaks[2].eleM, isNull);
  });

  test('道路 way 在图层解析里被忽略（道路仍由道路管线负责）', () {
    final layers = parseOverpassLayers({
      'elements': [
        wayEl({'highway': 'primary'}, [
          [31.0, 121.0],
          [31.001, 121.001],
        ]),
      ],
    });
    expect(layers.isEmpty, isTrue);
  });

  test('环面积：约 100 米见方在纬度 31 度约 10000 平方米', () {
    // 100 米纬度差 = 100/110540 度；100 米经度差 = 100/(111320*cos31°) 度。
    const lat = 31.0;
    const dLat = 100 / 110540;
    const dLon = 100 / (111320 * 0.8571673007021122);
    final ring = [
      (lat, 121.0),
      (lat, 121.0 + dLon),
      (lat + dLat, 121.0 + dLon),
      (lat + dLat, 121.0),
    ];
    expect(ringAreaM2(ring, lat), closeTo(10000, 150));
    expect(ringAreaM2([(lat, 121.0), (lat, 121.001)], lat), 0);
  });

  test('建筑缩放门限：越远只画越大 footprint', () {
    expect(buildingVisibleAtZoom(50, 17), isTrue);
    expect(buildingVisibleAtZoom(50, 16), isFalse);
    expect(buildingVisibleAtZoom(60, 16), isTrue);
    expect(buildingVisibleAtZoom(149, 15), isFalse);
    expect(buildingVisibleAtZoom(150, 15), isTrue);
    expect(buildingVisibleAtZoom(399, 14), isFalse);
    expect(buildingVisibleAtZoom(400, 14), isTrue);
    expect(buildingVisibleAtZoom(899, 13), isFalse);
    expect(buildingVisibleAtZoom(900, 13), isTrue);
  });

  test('环抽稀：超限按步长取点且保持闭合，未超限原样', () {
    final ring = <(double, double)>[];
    for (var i = 0; i < 100; i++) {
      ring.add((31.0 + i * 0.0001, 121.0));
    }
    ring.add(ring.first);
    final thinned = simplifyRing(ring, 48);
    expect(thinned.length, lessThanOrEqualTo(49));
    expect(thinned.first, thinned.last);
    final small = [(31.0, 121.0), (31.001, 121.0), (31.001, 121.001)];
    expect(simplifyRing(small, 48), small);
  });

  test('山峰标记文字：名 + 海拔拼法', () {
    expect(
        peakLabelText(
            const MapPeak(lat: 31.0, lon: 121.0, name: '玉龙雪山', eleM: 5596)),
        '玉龙雪山 5596m');
    expect(
        peakLabelText(const MapPeak(lat: 31.0, lon: 121.0, eleM: 100)),
        '100m');
    expect(
        peakLabelText(
            const MapPeak(lat: 31.0, lon: 121.0, name: '泰山')),
        '泰山');
    expect(peakLabelText(const MapPeak(lat: 31.0, lon: 121.0)), '');
  });

  test('图层顺序：绿地 → 水体 → 建筑 → 道路 → 山峰标记', () {
    final order = mapLayerDrawOrder;
    expect(order.indexOf(MapLayerKind.green) <
        order.indexOf(MapLayerKind.water), isTrue);
    expect(order.indexOf(MapLayerKind.water) <
        order.indexOf(MapLayerKind.building), isTrue);
    expect(order.indexOf(MapLayerKind.building) <
        order.indexOf(MapLayerKind.road), isTrue);
    expect(order.indexOf(MapLayerKind.road) <
        order.indexOf(MapLayerKind.peak), isTrue);
  });

  test('缓存 v3 往返一致，v2 与脏数据一律作废', () {
    const layers = MapLayers(
      waters: [
        WaterArea(
          outers: [
            [(31.0, 121.0), (31.0, 121.001), (31.001, 121.001), (31.001, 121.0)],
          ],
          inners: [
            [(31.0002, 121.0002), (31.0002, 121.0004), (31.0004, 121.0004)],
          ],
        ),
      ],
      waterLines: [
        WaterLine([(31.0, 121.0), (31.001, 121.001)]),
      ],
      greens: [
        MapPolygon([(31.0, 121.0), (31.0, 121.001), (31.001, 121.001)]),
      ],
      buildings: [
        MapPolygon([(31.0, 121.0), (31.0, 121.001), (31.001, 121.001)]),
      ],
      peaks: [
        MapPeak(lat: 31.1, lon: 121.1, name: '玉龙雪山', eleM: 5596),
      ],
    );
    final decoded = mapLayersToCacheJson(layers, 123);
    expect(decoded['v'], layerCacheVersion);
    final back = mapLayersFromCacheJson(decoded);
    expect(back.waters.length, 1);
    expect(back.waters.first.outers.first.length, 4);
    expect(back.waters.first.inners.first.length, 3);
    expect(back.waterLines.length, 1);
    expect(back.greens.length, 1);
    expect(back.buildings.length, 1);
    expect(back.peaks.length, 1);
    expect(back.peaks.first.name, '玉龙雪山');
    expect(back.peaks.first.eleM, 5596);
    // 旧版本与脏数据作废，不串味。
    expect(mapLayersFromCacheJson({'v': 2, 'waters': []}).isEmpty, isTrue);
    expect(mapLayersFromCacheJson({'v': 3}).isEmpty, isTrue);
    expect(mapLayersFromCacheJson('nope').isEmpty, isTrue);
    expect(mapLayersFromCacheJson(null).isEmpty, isTrue);
  });
}
