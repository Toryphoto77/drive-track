// v1.2.5 高德兜底测试：只测纯函数（交通态势解析、GCJ-02 逆转换、
// 文案区分），不发真实网络请求，不用真实 Key（Key 只走构建时
// --dart-define，测试只走假数据与空值路径）。
import 'dart:math' as math;

import 'package:drive_track/recording_3d_map.dart';
import 'package:flutter_test/flutter_test.dart';

double _distM(double lat1, double lon1, double lat2, double lon2) {
  final dx = (lon2 - lon1) * math.cos(lat1 * math.pi / 180) * 111320;
  final dy = (lat2 - lat1) * 110540;
  return math.sqrt(dx * dx + dy * dy);
}

/// 测试内正向变换（WGS-84 → GCJ-02，公开标准算法），仅用于验证
/// 逆转换的往返一致性，不进正式代码。
(double, double) _wgs84ToGcj02(double lat, double lon) {
  const a = 6378245.0;
  const ee = 0.00669342162296594323;
  double transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y * math.pi / 3.0)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y * math.pi / 12.0) +
            320 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  double transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x * math.pi / 3.0)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x * math.pi / 12.0) +
            300 * math.sin(x * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  final dLat = transformLat(lon - 105.0, lat - 35.0);
  final dLon = transformLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  final dLatDeg =
      dLat * 180.0 / ((a * (1 - ee)) / (magic * sqrtMagic) * math.pi);
  final dLonDeg =
      dLon * 180.0 / (a / sqrtMagic * math.cos(radLat) * math.pi);
  return (lat + dLatDeg, lon + dLonDeg);
}

void main() {
  group('amap traffic rectangle', () {
    test('bbox format matches osm range, semicolon separated', () {
      expect(amapTrafficRectangle(39.9, 116.4),
          '116.395000,39.895000;116.405000,39.905000');
    });

    test('parses roads, converts GCJ-02 points, drops short polylines', () {
      final data = {
        'status': '1',
        'info': 'OK',
        'trafficinfo': {
          'roads': [
            {
              'name': '北河沿大街',
              'polyline':
                  '116.406677,39.9153099;116.406616,39.9167099;116.406578,39.9173203',
            },
            {'name': '单点', 'polyline': '116.406677,39.9153099'},
            {
              'name': '坏点',
              'polyline': 'not-a-pair;116.406677,39.9153099',
            },
            {'name': '无折线'},
          ],
        },
      };
      final ways = parseAmapTrafficRoads(data);
      expect(ways.length, 1);
      expect(ways.first.points.length, 3);
      // 交通态势不给等级：不冒充分类，highway 置空走一般道路。
      expect(ways.first.highway, '');
      // 转换后的点与原始 GCJ 点应有几百米级偏移（坐标系差），
      // 但仍在同一条路上（2 公里内），不是原地不动也不是乱跳。
      final (clat, clon) = ways.first.points.first;
      final d = _distM(clat, clon, 39.9153099, 116.406677);
      expect(d, greaterThan(50));
      expect(d, lessThan(2000));
    });

    test('failure shapes return empty, never throw', () {
      expect(parseAmapTrafficRoads({'status': '0', 'info': 'X'}), isEmpty);
      expect(parseAmapTrafficRoads({'status': '1'}), isEmpty);
      expect(
          parseAmapTrafficRoads({
            'status': '1',
            'trafficinfo': {'roads': null},
          }),
          isEmpty);
      expect(
          parseAmapTrafficRoads({
            'status': '1',
            'trafficinfo': {'roads': []},
          }),
          isEmpty);
    });
  });

  group('gcj02 to wgs84', () {
    test('outside China passes through unchanged', () {
      expect(gcj02ToWgs84(0, 0), (0.0, 0.0));
      expect(gcj02ToWgs84(40.7128, -74.0060), (40.7128, -74.0060));
    });

    test('round trip wgs -> gcj -> wgs within 10m', () {
      const wgsLat = 39.90923;
      const wgsLon = 116.397428;
      final (gcjLat, gcjLon) = _wgs84ToGcj02(wgsLat, wgsLon);
      final (backLat, backLon) = gcj02ToWgs84(gcjLat, gcjLon);
      expect(_distM(backLat, backLon, wgsLat, wgsLon), lessThan(10));
    });
  });

  group('amap source plumbing', () {
    test('label distinguishes amap fallback from osm', () {
      String label(bool amap) => roadStatusLabel(
            loaded: true,
            fromCache: false,
            neighborCache: false,
            hasRoads: true,
            fromAmap: amap,
          );
      expect(label(true), '路网：高德兜底（仅主干路）');
      expect(label(false), '路网：OpenStreetMap');
    });

    test('result source defaults to osm, amap preserved', () {
      expect(const RoadFetchResult([], 'none').source, 'osm');
      expect(
          const RoadFetchResult([], 'none', source: 'amap').source, 'amap');
    });
  });
}
