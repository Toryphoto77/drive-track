// 高德第一批三件测试：只测纯函数与 fake 注入的编排逻辑，
// 不发真实网络请求，不用真实 Key（Key 只走构建时 --dart-define，
// 测试只走 fake 数据与空值路径）。
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_track/amap_service.dart';
import 'package:drive_track/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _pt(double lat, double lon, int timeMs, double speedMs) =>
    TrackPoint(
      timeMs: timeMs,
      lat: lat,
      lon: lon,
      alt: 0,
      speed: speedMs,
      bearing: 0,
      hAcc: 5,
      vAcc: 5,
      speedAcc: 1,
      provider: 'gps',
      longG: 0,
      latG: 0,
      vertG: 0,
      pitch: 0,
      roll: 0,
      heading: 0,
      pressureHpa: 1013,
      calibrated: true,
    );

/// 测试内正向变换（WGS-84 → GCJ-02，公开标准算法），仅用于验证
/// 逆转换的往返一致性，不进正式代码。
(double, double) _wgs84ToGcj02(double lat, double lon) {
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  double transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(y / 12.0 * math.pi) + 300.0 * math.sin(y / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x * math.pi / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
    return ret;
  }

  final dLat = transformLat(lon - 105.0, lat - 35.0);
  final dLon = transformLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final dLatDeg = dLat * 180.0 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final dLonDeg = dLon * 180.0 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (lat + dLatDeg, lon + dLonDeg);
}

/// fake 转换：原样返回入参坐标（编排测试用，不验证真实偏移量）。
Future<Map<String, dynamic>?> _identityConvertFetcher(Uri uri) async {
  final locs = uri.queryParameters['locations'] ?? '';
  return {'status': '1', 'info': 'OK', 'locations': locs.replaceAll('|', ';')};
}

void main() {
  group('china guard', () {
    test('inside, outside and boundary', () {
      expect(isInChina(39.9, 116.4), isTrue);
      expect(isInChina(30.2, 120.1), isTrue);
      expect(isInChina(51.5, -0.1), isFalse); // 伦敦
      expect(isInChina(39.9, 140.0), isFalse); // 日本经度
      expect(isInChina(72.004, 0.8293), isFalse); // 框角不在中国境内纬度
      expect(isInChina(39.9, 72.004), isTrue); // 边界含
    });

    test('tripInChina requires both ends inside', () {
      final inside = [
        _pt(39.9, 116.4, 0, 10),
        _pt(39.91, 116.41, 5000, 10),
      ];
      expect(tripInChina(inside), isTrue);
      final cross = [
        _pt(39.9, 116.4, 0, 10),
        _pt(51.5, -0.1, 5000, 10),
      ];
      expect(tripInChina(cross), isFalse);
      expect(tripInChina([]), isFalse);
    });
  });

  group('correction thinning and chunking', () {
    test('thin keeps first/last and 4s gaps', () {
      final pts = List<TrackPoint>.generate(
          10, (i) => _pt(39.9, 116.4 + i * 0.001, i * 1000, 10));
      final thinned = thinPointsForCorrection(pts);
      // 1 秒间隔 → 每 4 秒取 1 个 + 首尾：0,4,8,9
      expect(thinned.map((p) => p.timeMs).toList(), [0, 4000, 8000, 9000]);
    });

    test('thin keeps all when gaps already large', () {
      final pts = List<TrackPoint>.generate(
          5, (i) => _pt(39.9, 116.4 + i * 0.001, i * 5000, 10));
      expect(thinPointsForCorrection(pts).length, 5);
    });

    test('chunkWithOverlap shares boundary point', () {
      final chunks = chunkWithOverlap<int>(
          List<int>.generate(450, (i) => i), 400,
          overlap: 1);
      expect(chunks.length, 2);
      expect(chunks[0].length, 400);
      expect(chunks[1].length, 51);
      expect(chunks[0].last, 399);
      expect(chunks[1].first, 399);
    });

    test('chunkWithOverlap short list is one chunk', () {
      expect(chunkWithOverlap<int>([1, 2, 3], 400).length, 1);
      expect(chunkWithOverlap<int>([], 400), isEmpty);
    });
  });

  group('correction request body', () {
    test('fields, tm offsets, sp clamp, slow interior dropped', () {
      final pts = [
        _pt(39.9, 116.4, 1700000000000, 0), // 首点静止也保留
        _pt(39.901, 116.401, 1700000005000, 0.2), // 内点 <2km/h 剔除
        _pt(39.902, 116.402, 1700000010000, 10),
        _pt(39.903, 116.403, 1700000015000, 0), // 尾点静止也保留
      ];
      final body = jsonDecode(buildCorrectionRequestBody(pts)) as List;
      expect(body.length, 3);
      final first = body[0] as Map<String, dynamic>;
      expect(first['x'], 116.4);
      expect(first['y'], 39.9);
      expect(first['tm'], 0);
      expect(first['sp'], 5.0); // 静止首点下限 5
      final last = body[2] as Map<String, dynamic>;
      expect(last['tm'], 15);
      expect(last['sp'], 5.0);
    });

    test('angle: east is 90, due north nudged to 0.5', () {
      final east = [_pt(39.9, 116.4, 0, 10), _pt(39.9, 116.41, 5000, 10)];
      expect(correctionAngleFor(east, 0), closeTo(90, 0.01));
      final north = [_pt(39.9, 116.4, 0, 10), _pt(39.91, 116.4, 5000, 10)];
      expect(correctionAngleFor(north, 0), 0.5);
      expect(correctionAngleFor(north, 1), 0.5);
    });
  });

  group('correction response parsing', () {
    test('valid points, string numbers accepted', () {
      final parsed = parseCorrectionResponse({
        'errcode': 0,
        'data': {
          'points': [
            {'x': 116.4, 'y': 39.9},
            {'x': '116.41', 'y': '39.91'},
          ],
        },
      });
      expect(parsed, [(39.9, 116.4), (39.91, 116.41)]);
    });

    test('failure shapes return null', () {
      expect(parseCorrectionResponse({'errcode': 30001}), isNull);
      expect(parseCorrectionResponse({'errcode': 0}), isNull);
      expect(parseCorrectionResponse({
        'errcode': 0,
        'data': {
          'points': [
            {'x': 'bad', 'y': 39.9},
          ],
        },
      }), isNull);
    });
  });

  group('convert API', () {
    test('parse locations string in order', () {
      expect(
          parseConvertResponse(
              {'status': '1', 'locations': '116.4,39.9;116.41,39.91'}),
          [(39.9, 116.4), (39.91, 116.41)]);
      expect(parseConvertResponse({'status': '0'}), isNull);
      expect(parseConvertResponse({'status': '1'}), isNull);
      expect(
          parseConvertResponse(
              {'status': '1', 'locations': '116.4,39.9;bad'}),
          isNull);
    });

    test('chunks at 40 and fails fast on chunk failure', () async {
      var calls = 0;
      Future<Map<String, dynamic>?> fetcher(Uri uri) async {
        calls++;
        if (calls == 2) return {'status': '0'};
        return _identityConvertFetcher(uri);
      }

      final pts = List<(double, double)>.generate(
          85, (i) => (39.9 + i * 0.0001, 116.4));
      expect(
          await convertWgsToGcj(pts, key: 'fake', jsonFetcher: fetcher),
          isNull);
      expect(calls, 2);
    });

    test('85 points convert in 3 chunks with identity fake', () async {
      final pts = List<(double, double)>.generate(
          85, (i) => (39.9 + i * 0.0001, 116.4));
      final out = await convertWgsToGcj(pts,
          key: 'fake', jsonFetcher: _identityConvertFetcher);
      expect(out!.length, 85);
      expect(out.first, (39.9, 116.4));
    });
  });

  group('correctTrackPoints orchestration with fakes', () {
    test('450 points splice without duplicate boundary', () async {
      final pts = List<TrackPoint>.generate(
          450, (i) => _pt(39.9, 116.4 + i * 0.0001, i * 5000, 10));
      Future<Map<String, dynamic>?> post(Uri uri, String body) async {
        final arr = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
        return {
          'errcode': 0,
          'data': {
            'points':
                arr.map((e) => {'x': e['x'], 'y': e['y']}).toList(),
          },
        };
      }

      final out = await correctTrackPoints(pts,
          key: 'fake',
          jsonFetcher: _identityConvertFetcher,
          postFetcher: post);
      expect(out, isNotNull);
      // 450 输入 → 400 + 51 两段，拼接去重后仍为 450 点。
      expect(out!.length, 450);
      // 首尾与输入同一点（逆推在 fake 恒等转换下只剩米级公式残差）。
      expect((out.first.$1 - 39.9).abs(), lessThan(0.01));
      expect((out.last.$2 - (116.4 + 449 * 0.0001)).abs(),
          lessThan(0.01));
    });

    test('correction chunk failure returns null', () async {
      final pts = List<TrackPoint>.generate(
          10, (i) => _pt(39.9, 116.4 + i * 0.001, i * 5000, 10));
      Future<Map<String, dynamic>?> post(Uri uri, String body) async =>
          {'errcode': 30001};
      expect(
          await correctTrackPoints(pts,
              key: 'fake',
              jsonFetcher: _identityConvertFetcher,
              postFetcher: post),
          isNull);
    });

    test('too few points returns null without network', () async {
      var called = false;
      Future<Map<String, dynamic>?> never(Uri uri) async {
        called = true;
        return null;
      }

      expect(
          await correctTrackPoints([_pt(39.9, 116.4, 0, 10)],
              key: 'fake', jsonFetcher: never),
          isNull);
      expect(called, isFalse);
    });
  });

  group('wgsToGcjLocal forward and amap tiles', () {
    test('round trip wgs->gcj->wgs is identity within meters', () {
      const lat = 39.9042, lon = 116.4074; // 北京
      final (glat, glon) = wgsToGcjLocal(lat, lon);
      final (blat, blon) = gcjToWgsLocal(glat, glon);
      expect((blat - lat).abs(), lessThan(0.00005));
      expect((blon - lon).abs(), lessThan(0.00005));
      // 上海点同样往返。
      const slat = 31.3380, slon = 121.2180;
      final (gslat, gslon) = wgsToGcjLocal(slat, slon);
      final (bslat, bslon) = gcjToWgsLocal(gslat, gslon);
      expect((bslat - slat).abs(), lessThan(0.00005));
      expect((bslon - slon).abs(), lessThan(0.00005));
    });

    test('known China point shifts by a plausible GCJ offset', () {
      final (glat, glon) = wgsToGcjLocal(39.9042, 116.4074);
      // 偏移约数百米：纬度 / 经度各移动 0.0005~0.01 度，既非 0 也非离谱值。
      expect((glat - 39.9042).abs(), greaterThan(0.0005));
      expect((glat - 39.9042).abs(), lessThan(0.01));
      expect((glon - 116.4074).abs(), greaterThan(0.0005));
      expect((glon - 116.4074).abs(), lessThan(0.01));
    });

    test('outside China returns input unchanged', () {
      expect(wgsToGcjLocal(51.5, -0.1), (51.5, -0.1));
      expect(wgsToGcjLocal(0, 0), (0, 0));
    });

    test('amap tile url is keyless style=7 road map', () {
      expect(
          amapTileUrl(14, 1234, 5678),
          'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x=1234&y=5678&z=14');
      expect(amapTileAttribution, '© 高德地图');
    });
  });

  group('gcj inverse round trip', () {
    test('inverse of forward lands within meters', () {
      const lat = 39.9042, lon = 116.4074;
      final (glat, glon) = _wgs84ToGcj02(lat, lon);
      final (blat, blon) = gcjToWgsLocal(glat, glon);
      expect((blat - lat).abs(), lessThan(0.00005));
      expect((blon - lon).abs(), lessThan(0.00005));
      // 框外原样返回。
      expect(gcjToWgsLocal(51.5, -0.1), (51.5, -0.1));
    });
  });

  group('regeo parsing', () {
    test('short name from district township street number', () {
      expect(
          buildRegeoShortName({
            'district': '西湖区',
            'township': '翠苑街道',
            'streetNumber': {'street': '文三路', 'number': '123号'},
          }),
          '西湖区 翠苑街道 文三路123号');
      expect(buildRegeoShortName({'district': '西湖区'}), '西湖区');
      expect(buildRegeoShortName({}), isNull);
    });

    test('parse falls back to formatted address', () {
      final p = parseRegeoResponse({
        'status': '1',
        'regeocode': {
          'formatted_address': '浙江省杭州市西湖区文三路123号',
          'addressComponent': {'district': '', 'township': ''},
        },
      });
      expect(p!.shortName, '浙江省杭州市西湖区文三路123号');
      expect(parseRegeoResponse({'status': '0'}), isNull);
      expect(parseRegeoResponse({'status': '1'}), isNull);
    });

    test('reverseGeocode chains convert then regeo with fakes', () async {
      Future<Map<String, dynamic>?> fetcher(Uri uri) async {
        if (uri.toString().contains('coordinate/convert')) {
          return _identityConvertFetcher(uri);
        }
        return {
          'status': '1',
          'regeocode': {
            'formatted_address': '浙江省杭州市西湖区文三路123号',
            'addressComponent': {
              'district': '西湖区',
              'township': '',
              'streetNumber': {'street': '文三路', 'number': '123号'},
            },
          },
        };
      }

      final p = await reverseGeocode(39.9, 116.4,
          key: 'fake', jsonFetcher: fetcher);
      expect(p!.shortName, '西湖区 文三路123号');
    });
  });

  group('static map', () {
    test('simplify collapses straight line, keeps peak', () {
      final straight =
          List<(double, double)>.generate(11, (i) => (39.9, 116.4 + i * 0.001));
      expect(simplifyPolyline(straight, 50).length, 2);
      final zigzag = <(double, double)>[
        (39.9, 116.4),
        (39.9025, 116.405), // 落在首点→峰顶的连线上，应剔除
        (39.905, 116.41), // 偏离直线约 550 米，应保留
        (39.9025, 116.415), // 落在峰顶→尾点的连线上，应剔除
        (39.9, 116.42),
      ];
      final kept = simplifyPolyline(zigzag, 50);
      expect(kept.length, 3);
      expect(kept[1], (39.905, 116.41));
    });

    test('simplifyForStaticMap caps points, keeps ends', () {
      final pts = List<(double, double)>.generate(
          300, (i) => (39.9 + math.sin(i / 10) * 0.01, 116.4 + i * 0.0002));
      final out = simplifyForStaticMap(pts);
      expect(out.length, lessThanOrEqualTo(150));
      expect(out.first, pts.first);
      expect(out.last, pts.last);
    });

    test('fitZoom shrinks with span and clamps', () {
      final small = fitZoomForStaticMap(
          minLat: 39.9, maxLat: 39.901, minLon: 116.4, maxLon: 116.401);
      final big = fitZoomForStaticMap(
          minLat: 39.0, maxLat: 41.0, minLon: 115.0, maxLon: 118.0);
      expect(small, greaterThan(big));
      expect(small, lessThanOrEqualTo(17));
      expect(big, greaterThanOrEqualTo(3));
      final huge = fitZoomForStaticMap(
          minLat: -80, maxLat: 80, minLon: -170, maxLon: 170);
      expect(huge, 3);
    });

    test('buildStaticMapUrl has paths and markers in lon,lat order', () {
      final url = buildStaticMapUrl(
        key: 'fake',
        gcjPoints: [(39.9, 116.4), (39.91, 116.41)],
        centerLat: 39.905,
        centerLon: 116.405,
        zoom: 14,
      );
      expect(url, contains('paths=5,0xFF0000,1,,:116.400000,39.900000;116.410000,39.910000'));
      expect(url, contains('markers=mid,0xFF0000,A:116.400000,39.900000'));
      expect(url, contains('mid,0x00AA00,B:116.410000,39.910000'));
      expect(url, contains('size=1024*512&scale=2'));
    });

    test('fetchStaticMapImage stays under url cap and returns bytes',
        () async {
      var seenUrl = '';
      Future<Uint8List?> bytes(Uri uri) async {
        seenUrl = uri.toString();
        return Uint8List.fromList([1, 2, 3]);
      }

      // 500 点波浪线（振幅约 550 米，简化后仍保留大量点）：抽稀 +
      // 上限后 URL 必须 ≤6000，否则分享请求会被服务端拒。
      final pts = List<(double, double)>.generate(
          500,
          (i) =>
              (39.9 + math.sin(i / 5) * 0.005, 116.4 + i * 0.0002));
      final out = await fetchStaticMapImage(pts,
          key: 'fake',
          jsonFetcher: _identityConvertFetcher,
          bytesFetcher: bytes);
      expect(out, [1, 2, 3]);
      expect(seenUrl.length, lessThanOrEqualTo(kStaticMapMaxUrlLength));
      expect(seenUrl, contains('paths='));
    });

    test('fetchStaticMapImage returns null when bytes fail', () async {
      Future<Uint8List?> fail(Uri uri) async => null;
      final pts = [(39.9, 116.4), (39.91, 116.41)];
      expect(
          await fetchStaticMapImage(pts,
              key: 'fake',
              jsonFetcher: _identityConvertFetcher,
              bytesFetcher: fail),
          isNull);
    });
  });

  group('trip enrichment json round trip', () {
    test('corrected points, status and places survive', () {
      final trip = Trip(
        id: 't1',
        mode: TripMode.car,
        startMs: 1000,
        endMs: 2000,
        points: [_pt(39.9, 116.4, 1000, 10), _pt(39.91, 116.41, 2000, 10)],
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
        correctedPoints: [(39.9001, 116.4001), (39.9101, 116.4101)],
        correctionStatus: 'done',
        startPlace: '西湖区',
        endPlace: '滨江区',
      );
      final back = Trip.fromJson(trip.toJson());
      expect(back.correctedPoints, [(39.9001, 116.4001), (39.9101, 116.4101)]);
      expect(back.correctionStatus, 'done');
      expect(back.startPlace, '西湖区');
      expect(back.endPlace, '滨江区');
      // 派生层绝不覆盖原始轨迹：原始点列原样。
      expect(back.points.map((p) => (p.lat, p.lon)).toList(),
          [(39.9, 116.4), (39.91, 116.41)]);
    });

    test('old json without enrichment keys reads defaults', () {
      final trip = Trip(
        id: 't2',
        mode: TripMode.car,
        startMs: 1000,
        endMs: 2000,
        points: [_pt(39.9, 116.4, 1000, 10)],
        events: const [],
        score: 0,
        subScores: const {},
        scoreReasons: const [],
      );
      final json = trip.toJson()
        ..remove('corrPts')
        ..remove('corrStatus')
        ..remove('startPlace')
        ..remove('endPlace');
      final back = Trip.fromJson(json);
      expect(back.correctedPoints, isEmpty);
      expect(back.correctionStatus, 'none');
      expect(back.startPlace, '');
      expect(back.endPlace, '');
    });
  });
}
