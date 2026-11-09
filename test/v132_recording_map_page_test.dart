/// v1.3.2 测试：记录页实时 Map 分页（RecordingMapPage）。
///
/// 覆盖：
/// - 纯函数：视口 bounds 并集（空 / 单点扩框 / 中心线 + 轨迹并集）、
///   箭头顶点朝向（0° 北 / 90° 东 / 180° 南）；
/// - widget：无点占位、卫星回落占位（测试环境瓦片失败达阈值）、
///   起终点 / 分段点 / 街道轨迹标记渲染、起终点重合只画一个。
///
/// 本版不测手势跟随（首版固定视口）、不测离线瓦片下载（不做）、
/// 不测 3D 回放（不做）。

import 'package:drive_track/amap_service.dart';
import 'package:drive_track/recording_map_page.dart';
import 'package:drive_track/track_analysis_geo.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = GeoPoint(31.3380, 121.2180);
const _p2 = GeoPoint(31.3420, 121.2280);
const _p3 = GeoPoint(31.3400, 121.2230);

/// 记录页叠加层以 GCJ-02 交给 painter：期望值同样经 wgsToGcjLocal 算。
GeoPoint _gcj(GeoPoint p) {
  final (la, lo) = wgsToGcjLocal(p.lat, p.lon);
  return GeoPoint(la, lo);
}

Future<void> _pumpPage(
  WidgetTester tester,
  RecordingMapPage page,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, height: 480, child: page),
        ),
      ),
    ),
  );
}

RecordingMapPainter _overlayPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('recording-map-overlay')),
  );
  return paint.painter as RecordingMapPainter;
}

void main() {
  group('视口 bounds 计算', () {
    test('中心线与轨迹都空时为 null（占位）', () {
      expect(recordingMapBounds([], []), isNull);
    });

    test('单点时扩一小框，不除零', () {
      final b = recordingMapBounds([], [_p1])!;
      expect(b.minLat, lessThan(_p1.lat));
      expect(b.maxLat, greaterThan(_p1.lat));
      expect(b.minLon, lessThan(_p1.lon));
      expect(b.maxLon, greaterThan(_p1.lon));
      expect(b.maxLat - b.minLat, closeTo(0.004, 1e-9));
    });

    test('全部重合时扩框，不返回 null', () {
      final b = recordingMapBounds([_p1], [_p1, _p1])!;
      expect(b.minLat, lessThan(_p1.lat));
      expect(b.maxLat, greaterThan(_p1.lat));
    });

    test('中心线与轨迹并集取全量范围', () {
      final b = recordingMapBounds([_p1], [_p2])!;
      expect(b.minLat, _p1.lat);
      expect(b.maxLat, _p2.lat);
      expect(b.minLon, _p1.lon);
      expect(b.maxLon, _p2.lon);
    });

    test('并集点落在投影画布内', () {
      final b = recordingMapBounds([_p1, _p2], [_p3])!;
      final zoom = analysisGeoZoom(
        bounds: b,
        widthPx: 360,
        heightPx: 480,
      );
      final projector = AnalysisGeoProjector(
        bounds: b,
        zoom: zoom,
        size: const Size(360, 480),
      );
      for (final p in [_p1, _p2, _p3]) {
        final o = projector.project(p.lat, p.lon);
        expect(o.dx, greaterThanOrEqualTo(0));
        expect(o.dx, lessThanOrEqualTo(360));
        expect(o.dy, greaterThanOrEqualTo(0));
        expect(o.dy, lessThanOrEqualTo(480));
      }
    });
  });

  group('箭头朝向', () {
    test('0° 尖角朝上（北）', () {
      final v = recordingMapArrowVertices(const Offset(100, 100), 0);
      expect(v.tip.dx, closeTo(100, 1e-9));
      expect(v.tip.dy, closeTo(88, 1e-9));
      expect(v.baseLeft.dy, closeTo(108, 1e-9));
      expect(v.baseRight.dy, closeTo(108, 1e-9));
    });

    test('90° 尖角朝右（东）', () {
      final v = recordingMapArrowVertices(const Offset(100, 100), 90);
      expect(v.tip.dx, closeTo(112, 1e-9));
      expect(v.tip.dy, closeTo(100, 1e-9));
    });

    test('180° 尖角朝下（南）', () {
      final v = recordingMapArrowVertices(const Offset(100, 100), 180);
      expect(v.tip.dx, closeTo(100, 1e-9));
      expect(v.tip.dy, closeTo(112, 1e-9));
    });
  });

  group('RecordingMapPage widget', () {
    testWidgets('无点时显示占位，不画假线', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [],
          start: null,
          finish: null,
          sectorPoints: [],
          trail: [],
          curLat: 0,
          curLon: 0,
          curHeading: 0,
          statusLine: '等待定位',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无位置，等待定位'), findsOneWidget);
      expect(find.text('等待定位'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recording-map-overlay')),
        findsNothing,
      );
    });

    testWidgets('测试环境瓦片失败达阈值后回落示意图', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: false,
          centerline: [],
          start: null,
          finish: null,
          sectorPoints: [],
          trail: [_p1, _p2],
          curLat: 31.3400,
          curLon: 121.2230,
          curHeading: 45,
          statusLine: '用时 00:10 · 里程 1.20 km',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('地图未加载，已显示示意图'), findsOneWidget);
      expect(find.text('用时 00:10 · 里程 1.20 km'), findsNothing);
      // 回落时不显示高德署名。
      expect(find.text('© 高德地图'), findsNothing);
      final painter = _overlayPainter(tester);
      expect(painter.satelliteOn, isFalse);
      expect(painter.hasValidPosition, isTrue);
    });

    testWidgets('赛道标记渲染：中心线 / 起终点 / 分段点 / 箭头', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [_p1, _p3, _p2],
          start: _p1,
          finish: _p2,
          sectorPoints: [_p3, _p2],
          trail: [_p1, _p3],
          curLat: 31.3400,
          curLon: 121.2230,
          curHeading: 90,
          statusLine: '第 2 圈 · 当前圈 01:23',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('第 2 圈 · 当前圈 01:23'), findsOneWidget);
      final painter = _overlayPainter(tester);
      expect(painter.centerline.length, 3);
      // 叠加层以 GCJ-02 交给 painter：与 WGS-84 入参比应有偏移。
      expect(painter.start!.lat, closeTo(_gcj(_p1).lat, 1e-9));
      expect(painter.start!.lon, closeTo(_gcj(_p1).lon, 1e-9));
      expect(painter.finish!.lat, closeTo(_gcj(_p2).lat, 1e-9));
      expect(painter.finish!.lon, closeTo(_gcj(_p2).lon, 1e-9));
      expect(painter.startFinishCoincident, isFalse);
      expect(painter.sectorPoints.length, 2);
      expect(painter.trail.length, 2);
      expect(painter.hasValidPosition, isTrue);
    });

    testWidgets('起终点重合时只画一个（方格旗）', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: true,
          centerline: [_p1, _p3, _p2, _p1],
          start: _p1,
          finish: _p1,
          sectorPoints: [],
          trail: [_p1],
          curLat: 0,
          curLon: 0,
          curHeading: 0,
          statusLine: '等待定位',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.startFinishCoincident, isTrue);
      expect(painter.hasValidPosition, isFalse);
    });

    testWidgets('街道轨迹渲染：无中心线，只有实测轨迹', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: false,
          centerline: [],
          start: null,
          finish: null,
          sectorPoints: [],
          trail: [_p1, _p3, _p2],
          curLat: 31.3420,
          curLon: 121.2280,
          curHeading: 180,
          statusLine: '用时 05:00 · 里程 3.40 km',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.centerline, isEmpty);
      expect(painter.trail.length, 3);
      expect(painter.start, isNull);
      expect(painter.finish, isNull);
      expect(painter.sectorPoints, isEmpty);
      expect(painter.hasValidPosition, isTrue);
    });
  });
}
