/// v1.3.3：选赛道卫星预览测试（共用组件 + 选择器接线）。
///
/// 不依赖真实网络：Image.network 在测试环境加载失败走 errorBuilder，
/// 回落用 fallbackThreshold 测试缝确定性触发。

import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_package_selector.dart';
import 'package:drive_track/track_satellite_preview.dart';
import 'package:drive_track/track_analysis_geo.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用小闭合回路（约 0.006° × 0.01°，约 660m × 950m）。
List<GeoPoint> get _loop => const [
      GeoPoint(31.3389, 121.2198),
      GeoPoint(31.3389, 121.2298),
      GeoPoint(31.3449, 121.2298),
      GeoPoint(31.3449, 121.2198),
      GeoPoint(31.3389, 121.2198),
    ];

TrackPackage _pkg({
  required String id,
  required List<GeoPoint> centerline,
  GeoPoint? start,
  GeoPoint? finish,
}) =>
    TrackPackage(
      id: id,
      nameCn: '测试赛道 $id',
      nameEn: 'Test $id',
      region: '中国',
      version: 1,
      source: TrackPackageSource.osm,
      verification: TrackPackageVerification.pending,
      centerline: centerline,
      start: start,
      finish: finish,
    );

void main() {
  group('previewGeoBounds', () {
    test('中心线范围正确', () {
      final b = previewGeoBounds(_loop);
      expect(b, isNotNull);
      expect(b!.minLat, 31.3389);
      expect(b.maxLat, 31.3449);
      expect(b.minLon, 121.2198);
      expect(b.maxLon, 121.2298);
    });

    test('起终点超出中心线范围时并入视口', () {
      final b = previewGeoBounds(
        _loop,
        start: const GeoPoint(31.3389, 121.2198),
        finish: const GeoPoint(31.3500, 121.2198),
      );
      expect(b, isNotNull);
      expect(b!.maxLat, 31.3500);
    });

    test('中心线不足 2 点返回 null（不画假线）', () {
      expect(previewGeoBounds(const []), isNull);
      expect(
        previewGeoBounds(const [GeoPoint(31.3389, 121.2198)]),
        isNull,
      );
    });

    test('全部重合时扩一小框（±0.002°）', () {
      final b = previewGeoBounds(const [
        GeoPoint(31.3389, 121.2198),
        GeoPoint(31.3389, 121.2198),
      ]);
      expect(b, isNotNull);
      expect(b!.minLat, closeTo(31.3369, 1e-9));
      expect(b.maxLat, closeTo(31.3409, 1e-9));
      expect(b.minLon, closeTo(121.2178, 1e-9));
      expect(b.maxLon, closeTo(121.2218, 1e-9));
    });
  });

  group('TrackSatellitePreviewPainter', () {
    test('起终点重合判定', () {
      final bounds = previewGeoBounds(_loop)!;
      final projector = AnalysisGeoProjector(
        bounds: bounds,
        zoom: analysisGeoZoom(
          bounds: bounds,
          widthPx: 300,
          heightPx: 220,
        ),
        size: const Size(300, 220),
      );
      final coincident = TrackSatellitePreviewPainter(
        projector: projector,
        centerline: _loop,
        start: const GeoPoint(31.3389, 121.2198),
        finish: const GeoPoint(31.3389, 121.2198),
        satelliteOn: true,
      );
      expect(coincident.startFinishCoincident, isTrue);
      final separate = TrackSatellitePreviewPainter(
        projector: projector,
        centerline: _loop,
        start: const GeoPoint(31.3389, 121.2198),
        finish: const GeoPoint(31.3449, 121.2298),
        satelliteOn: true,
      );
      expect(separate.startFinishCoincident, isFalse);
    });
  });

  group('TrackSatellitePreview widget', () {
    testWidgets('有中心线时尝试加载卫星瓦片并画叠加层', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 220,
              child: TrackSatellitePreview(
                centerline: _loop,
                start: const GeoPoint(31.3389, 121.2198),
                finish: const GeoPoint(31.3389, 121.2198),
                height: 220,
                fallback: const Text('回落示意图'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // 卫星瓦片在尝试加载（Image 存在），叠加层 painter 字段正确。
      expect(find.byType(Image), findsWidgets);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('track-preview-overlay')),
      );
      final painter = paint.painter as TrackSatellitePreviewPainter;
      expect(painter.centerline.length, _loop.length);
      expect(painter.start, isNotNull);
      expect(painter.finish, isNotNull);
      expect(painter.startFinishCoincident, isTrue);
      // 署名在卫星显示时出现。
      expect(find.text('影像 © Esri World Imagery'), findsOneWidget);
    });

    testWidgets('瓦片失败达阈值回落示意图并显示状态行', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 220,
              child: TrackSatellitePreview(
                centerline: _loop,
                start: const GeoPoint(31.3389, 121.2198),
                finish: const GeoPoint(31.3389, 121.2198),
                height: 220,
                showStatusLine: true,
                fallbackThreshold: 1,
                fallback: const Text('回落示意图'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('回落示意图'), findsOneWidget);
      expect(find.text('卫星图未加载，已显示示意图'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('中心线不足 2 点直接显示回落占位、不请求瓦片', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 220,
              child: TrackSatellitePreview(
                centerline: const [],
                height: 220,
                fallback: const Text('轮廓待补'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('轮廓待补'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('TrackPackageSelector 接线', () {
    testWidgets('有中心线的包用卫星预览、无中心线的包显示轮廓待补', (tester) async {
      final withLine = _pkg(
        id: 'with-line',
        centerline: _loop,
        start: const GeoPoint(31.3389, 121.2198),
        finish: const GeoPoint(31.3389, 121.2198),
      );
      final withoutLine = _pkg(id: 'without-line', centerline: const []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrackPackageSelector(
                packages: [withLine, withoutLine],
                selectedId: null,
                onSelected: (_) {},
                onInfo: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TrackSatellitePreview), findsOneWidget);
      expect(find.text('轮廓待补'), findsOneWidget);
    });
  });
}
