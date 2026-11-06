/// 卫星瓦片共用模块测试（lib/satellite_tiles.dart）。
///
/// 覆盖：
/// - URL 格式与 Esri z/y/x 顺序；
/// - satelliteTileX/Y 换算（赤道与中纬度，含与反算的往返一致）；
/// - satelliteTileRange 钳制；
/// - satelliteZoomForMetersPerPixel 的钳制与单调性。

import 'package:drive_track/satellite_tiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('satelliteTileUrl', () {
    test('格式为 Esri World Imagery tile 模板', () {
      expect(
        satelliteTileUrl(16, 123, 456),
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/16/456/123',
      );
    });

    test('Esri 顺序为 z/y/x：x 与 y 不可互换', () {
      // x=100、y=200 时 URL 第 3 段是 y(200)、第 4 段是 x(100)。
      final url = satelliteTileUrl(10, 100, 200);
      expect(url.endsWith('/tile/10/200/100'), isTrue);
      expect(url, isNot(contains('/tile/10/100/200')));
    });

    test('常量口径：署名、缩放范围、单次上限、回落阈值', () {
      expect(satelliteTileAttribution, '影像 © Esri World Imagery');
      expect(satelliteMinZoom, 10);
      expect(satelliteMaxZoom, 19);
      expect(satelliteMaxTiles, 64);
      expect(satelliteFallbackFailureThreshold, 3);
    });
  });

  group('satelliteTileX/Y 换算', () {
    test('赤道与本初子午线落在正中心瓦片', () {
      // z 级下共 2^z 列/行；lon=0 → x=2^(z-1)，lat=0 → y=2^(z-1)。
      for (final z in [10, 16, 19]) {
        final n = 1 << z;
        expect(satelliteTileX(0, z), n / 2);
        expect(satelliteTileY(0, z), closeTo(n / 2, 1e-9));
      }
    });

    test('经度边界：-180 → 0，+180 → 2^z', () {
      expect(satelliteTileX(-180, 12), 0);
      expect(satelliteTileX(180, 12), 4096);
    });

    test('中纬度（上海 31.2, 121.4）与反算往返一致', () {
      const lat = 31.2;
      const lon = 121.4;
      const z = 16;
      final x = satelliteTileX(lon, z);
      final y = satelliteTileY(lat, z);
      // 所在瓦片的西边 ≤ 经度 < 下一瓦片西边；
      // 北边 ≥ 纬度 > 下一瓦片北边。
      final xi = x.floor();
      final yi = y.floor();
      expect(satelliteTileWestLon(xi, z), lessThanOrEqualTo(lon));
      expect(lon, lessThan(satelliteTileWestLon(xi + 1, z)));
      expect(satelliteTileNorthLat(yi, z), greaterThanOrEqualTo(lat));
      expect(lat, greaterThan(satelliteTileNorthLat(yi + 1, z)));
      // 另一中纬度（赤道以南）同样往返一致。
      const lat2 = -33.9;
      const lon2 = 151.2;
      final x2 = satelliteTileX(lon2, z).floor();
      final y2 = satelliteTileY(lat2, z).floor();
      expect(satelliteTileWestLon(x2, z), lessThanOrEqualTo(lon2));
      expect(lon2, lessThan(satelliteTileWestLon(x2 + 1, z)));
      expect(satelliteTileNorthLat(y2, z), greaterThanOrEqualTo(lat2));
      expect(lat2, greaterThan(satelliteTileNorthLat(y2 + 1, z)));
    });

    test('纬度钳制到 Web Mercator 极限 ±85.0511', () {
      expect(satelliteTileY(90, 10), satelliteTileY(85.0511, 10));
      expect(satelliteTileY(-90, 10), satelliteTileY(-85.0511, 10));
    });

    test('瓦片角点反算：x=0 → -180，y=0 → 85.0511', () {
      expect(satelliteTileWestLon(0, 10), -180);
      expect(satelliteTileNorthLat(0, 10), closeTo(85.0511, 1e-4));
    });
  });

  group('satelliteTileRange', () {
    test('全球范围覆盖全部行列', () {
      final r = satelliteTileRange(
        minLat: -85.0511,
        maxLat: 85.0511,
        minLon: -180,
        maxLon: 180,
        zoom: 10,
      );
      expect((r.x0, r.x1, r.y0, r.y1), (0, 1023, 0, 1023));
    });

    test('越界经纬度钳制到合法范围', () {
      final r = satelliteTileRange(
        minLat: -90,
        maxLat: 90,
        minLon: -200,
        maxLon: 200,
        zoom: 12,
      );
      expect(r.x0, 0);
      expect(r.x1, 4095);
      expect(r.y0, 0);
      expect(r.y1, 4095);
    });

    test('小范围行列有序且落在合法区间内', () {
      final r = satelliteTileRange(
        minLat: 31.19,
        maxLat: 31.21,
        minLon: 121.39,
        maxLon: 121.41,
        zoom: 16,
      );
      expect(r.x0, lessThanOrEqualTo(r.x1));
      expect(r.y0, lessThanOrEqualTo(r.y1));
      expect(r.x0, greaterThanOrEqualTo(0));
      expect(r.x1, lessThan(1 << 16));
      expect(r.y0, greaterThanOrEqualTo(0));
      expect(r.y1, lessThan(1 << 16));
    });
  });

  group('satelliteZoomForMetersPerPixel', () {
    test('赤道上瓦片分辨率对应的缩放精确命中', () {
      // z=16 时赤道瓦片米/像素 = 156543.03392 / 2^16。
      final mpp16 = 156543.03392 / (1 << 16);
      expect(satelliteZoomForMetersPerPixel(mpp16, 0), 16);
      final mpp12 = 156543.03392 / (1 << 12);
      expect(satelliteZoomForMetersPerPixel(mpp12, 0), 12);
    });

    test('钳制：过大米/像素 → 最小缩放，过小 → 最大缩放', () {
      expect(satelliteZoomForMetersPerPixel(1e6, 0), satelliteMinZoom);
      expect(satelliteZoomForMetersPerPixel(1e-6, 0), satelliteMaxZoom);
    });

    test('非法输入回落最小缩放', () {
      expect(satelliteZoomForMetersPerPixel(double.nan, 0), satelliteMinZoom);
      expect(
        satelliteZoomForMetersPerPixel(double.infinity, 0),
        satelliteMinZoom,
      );
      expect(satelliteZoomForMetersPerPixel(0, 0), satelliteMinZoom);
      expect(satelliteZoomForMetersPerPixel(-5, 0), satelliteMinZoom);
    });

    test('单调性：米/像素越大，缩放越小（或相等）', () {
      const lat = 31.2;
      var prev = satelliteZoomForMetersPerPixel(0.01, lat);
      for (final mpp in [0.1, 1.0, 10.0, 100.0, 1000.0]) {
        final z = satelliteZoomForMetersPerPixel(mpp, lat);
        expect(z, lessThanOrEqualTo(prev));
        expect(z, inInclusiveRange(satelliteMinZoom, satelliteMaxZoom));
        prev = z;
      }
    });

    test('高纬度不高于同米/像素的赤道缩放', () {
      // cos(纬度) 越小，瓦片米/像素越小，所需缩放不高于赤道。
      const mpp = 10.0;
      expect(
        satelliteZoomForMetersPerPixel(mpp, 60),
        lessThanOrEqualTo(satelliteZoomForMetersPerPixel(mpp, 0)),
      );
    });
  });
}
