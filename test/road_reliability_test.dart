// 路网修复新增测试：只测纯函数，不发真实网络请求。
import 'package:drive_track/recording_3d_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('overpass query narrowing', () {
    test('600m + drivable classes only + server timeout 12', () {
      final q = buildOverpassQuery(31.2304, 121.4737);
      expect(q, contains('around:600,31.2304,121.4737'));
      expect(q, contains('[timeout:12]'));
      for (final c in drivableHighwayClasses) {
        expect(q, contains('way["highway"="$c"]'));
      }
      for (final excluded in ['footway', 'path', 'cycleway', 'pedestrian', 'track', 'steps', 'service']) {
        expect(q, isNot(contains('"$excluded"')));
      }
    });
  });

  group('osm api bbox', () {
    test('order minlon,minlat,maxlon,maxlat, 0.01 degree wide', () {
      expect(osmApiBbox(31.2304, 121.4737),
          '121.468700,31.225400,121.478700,31.235400');
    });
  });

  group('osm api map parsing', () {
    const sample = '''<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
 <node id="1" lat="31.2304" lon="121.4737" version="1"/>
 <node id="2" lat="31.2314" lon="121.4737" version="1"/>
 <node id="3" lat="31.2314" lon="121.4747" version="1"/>
 <node id="4" lat="31.2304" lon="121.4747" version="1"/>
 <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way>
 <way id="11"><nd ref="2"/><nd ref="3"/><tag k="highway" v="motorway"/><tag k="name" v="G2"/></way>
 <way id="12"><nd ref="1"/><nd ref="99"/><tag k="highway" v="primary"/></way>
 <way id="13"><nd ref="3"/><nd ref="4"/><tag k="building" v="yes"/></way>
 <way id="14"><nd ref="4"/><nd ref="1"/><tag k="highway" v="footway"/></way>
</osm>''';

    test('keeps highway ways, drops unresolved and untagged', () {
      final ways = parseOsmApiMap(sample);
      expect(ways.length, 3);
      // 倒序：步行类先画、高速后画压在上层。
      expect(ways[0].highway, 'footway');
      expect(ways[1].highway, 'residential');
      expect(ways[2].highway, 'motorway');
      expect(ways[2].points, [(31.2314, 121.4737), (31.2314, 121.4747)]);
    });

    test('caps at 250 ways', () {
      final buf = StringBuffer('<osm version="0.6">'
          '<node id="1" lat="31.2304" lon="121.4737"/>'
          '<node id="2" lat="31.2314" lon="121.4737"/>');
      for (var i = 0; i < 300; i++) {
        buf.write('<way id="${100 + i}"><nd ref="1"/><nd ref="2"/>'
            '<tag k="highway" v="residential"/></way>');
      }
      buf.write('</osm>');
      expect(parseOsmApiMap(buf.toString()).length, 250);
    });
  });

  group('cache v2 and compat', () {
    test('round-trip keeps highway and savedAt', () {
      final ways = [const RoadWay([(31.1, 121.1), (31.2, 121.2)], highway: 'primary')];
      final parsed = parseCachedRoads(roadCacheFileJson(ways, 123456789));
      expect(parsed.savedAtMs, 123456789);
      expect(parsed.ways.length, 1);
      expect(parsed.ways[0].highway, 'primary');
      expect(parsed.ways[0].points, [(31.1, 121.1), (31.2, 121.2)]);
    });

    test('old list format still reads, savedAt null', () {
      final parsed = parseCachedRoads([
        [
          [31.1, 121.1],
          [31.2, 121.2],
        ]
      ]);
      expect(parsed.savedAtMs, isNull);
      expect(parsed.ways.length, 1);
      expect(parsed.ways[0].highway, '');
    });

    test('cell key and neighbor ring order', () {
      expect(roadCacheCellKey(31.2304, 121.4737), 'road_31.23_121.47.json');
      final offsets = neighborCellOffsets();
      expect(offsets.length, 24);
      expect(offsets.contains((0, 0)), isFalse);
      expect(offsets[0], (-1, 0));
      int ring((int, int) o) => o.$1.abs() > o.$2.abs() ? o.$1.abs() : o.$2.abs();
      expect(offsets.take(8).every((o) => ring(o) == 1), isTrue);
      expect(offsets.skip(8).every((o) => ring(o) == 2), isTrue);
    });
  });

  group('status label', () {
    test('error text mapping', () {
      expect(roadErrorText('offline'), '无网络');
      expect(roadErrorText('timeout'), '请求超时');
      expect(roadErrorText('busy'), '服务器繁忙');
      expect(roadErrorText('empty'), '周边无道路数据');
      expect(roadErrorText('other'), '拉取失败');
      expect(roadErrorText('weird'), '拉取失败');
    });

    test('label matrix', () {
      String label({
        bool loaded = false,
        bool fromCache = false,
        bool neighborCache = false,
        bool hasRoads = false,
        String? errorKind,
      }) =>
          roadStatusLabel(
            loaded: loaded,
            fromCache: fromCache,
            neighborCache: neighborCache,
            hasRoads: hasRoads,
            errorKind: errorKind,
          );
      expect(label(loaded: true), '路网：OpenStreetMap');
      expect(label(fromCache: true, hasRoads: true), '缓存路网（点按重拉）');
      expect(label(fromCache: true, neighborCache: true, hasRoads: true),
          '附近缓存路网（点按重拉）');
      expect(label(fromCache: true, hasRoads: true, errorKind: 'busy'),
          '缓存路网·服务器繁忙（点按重拉）');
      expect(
          label(
              fromCache: true,
              neighborCache: true,
              hasRoads: true,
              errorKind: 'timeout'),
          '附近缓存路网·请求超时（点按重拉）');
      expect(label(fromCache: true, hasRoads: true, errorKind: 'empty'),
          '缓存路网（点按重拉）');
      expect(label(fromCache: true, hasRoads: false, errorKind: 'busy'),
          '路网：服务器繁忙（点按重拉）');
      expect(label(errorKind: 'offline'), '路网：无网络（点按重拉）');
      expect(label(), '路网加载中…（点按重拉）');
    });
  });
}
