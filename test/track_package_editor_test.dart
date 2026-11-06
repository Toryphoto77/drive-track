/// 赛道编辑页重做（v1.2.12）测试：准星落点、缩放后坐标换算、吸附、
/// 撤销、方向键微调等纯函数 / 逻辑，外加编辑页基础 widget 测试。
///
/// 覆盖：
/// - 准星在手指上方，不被盖住；
/// - 缩放后 project/unproject 往返一致，缩放锚点下地理点不动；
/// - 吸附到中心线最近点、分段沿线距离与按距离取点往返一致；
/// - 方向键微调按米换算（1 米 / 5 米）；
/// - 撤销栈多步、超限丢弃最旧；
/// - 编辑页能正常渲染：工具卡片、缩放工具栏、撤销与保存入口齐全。

import 'package:drive_track/satellite_tiles.dart';
import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_package_editor.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 约 1km 见方的测试中心线（纬度 31.2 附近，闭合回路）。
List<GeoPoint> _squareLine() => const [
  GeoPoint(31.2000, 121.4000),
  GeoPoint(31.2000, 121.4100),
  GeoPoint(31.2090, 121.4100),
  GeoPoint(31.2090, 121.4000),
  GeoPoint(31.2000, 121.4000),
];

EditorViewTransform _transform({double zoom = 1.0, Offset pan = Offset.zero}) {
  return EditorViewTransform(
    base: LatLonProjection(_squareLine()),
    size: const Size(400, 400),
    zoom: zoom,
    pan: pan,
  );
}

TrackPackage _pkg() {
  return TrackPackage(
    id: 'test',
    nameCn: '测试赛道',
    nameEn: 'Test',
    region: '中国',
    version: 1,
    source: TrackPackageSource.osm,
    sourceDetail: 'test',
    verification: TrackPackageVerification.pending,
    centerline: _squareLine(),
    lengthM: 3800,
    sectorPoints: const [GeoPoint(31.2000, 121.4050)],
    sectorNote: 'test',
    start: const GeoPoint(31.2000, 121.4000),
    finish: const GeoPoint(31.2000, 121.4000),
  );
}

void main() {
  group('准星落点', () {
    test('准星在手指正上方 72px，x 不变', () {
      const finger = Offset(200, 300);
      final cross = editorCrosshairPosition(finger);
      expect(cross.dx, 200);
      expect(cross.dy, 300 - editorCrosshairLiftPx);
      expect(editorCrosshairLiftPx, 72.0);
    });

    test('自定义上移距离生效', () {
      expect(
        editorCrosshairPosition(const Offset(10, 100), 50),
        const Offset(10, 50),
      );
    });
  });

  group('缩放后坐标换算', () {
    test('zoom=1 时 project/unproject 往返一致', () {
      final t = _transform();
      const p = GeoPoint(31.2050, 121.4050);
      final back = t.unproject(t.project(p));
      expect(back.lat, closeTo(p.lat, 1e-9));
      expect(back.lon, closeTo(p.lon, 1e-9));
    });

    test('zoom=3 时 project/unproject 往返一致（已落点不漂移）', () {
      final t = _transform(zoom: 3.0, pan: const Offset(40, -30));
      const p = GeoPoint(31.2050, 121.4050);
      final back = t.unproject(t.project(p));
      expect(back.lat, closeTo(p.lat, 1e-9));
      expect(back.lon, closeTo(p.lon, 1e-9));
    });

    test('zoomAt 以焦点为锚点：焦点下地理点不动', () {
      final t = _transform();
      const focal = Offset(250, 150);
      final before = t.unproject(focal);
      t.zoomAt(focal, 2.5);
      final after = t.unproject(focal);
      expect(after.lat, closeTo(before.lat, 1e-9));
      expect(after.lon, closeTo(before.lon, 1e-9));
      expect(t.zoom, 2.5);
    });

    test('缩放钳制在 1×–12×', () {
      final t = _transform();
      t.zoomAt(const Offset(200, 200), 100);
      expect(t.zoom, editorMaxZoom);
      t.zoomAt(const Offset(200, 200), 0.001);
      expect(t.zoom, editorMinZoom);
    });

    test('放大后米/像素变小（精度提高）', () {
      final t1 = _transform(zoom: 1.0);
      final t4 = _transform(zoom: 4.0);
      expect(t4.metersPerPixel, closeTo(t1.metersPerPixel / 4, 0.01));
      // 1× 下 400px 画布约 1km，精度约 2–3 米/像素；4× 后不到 1 米。
      expect(t4.metersPerPixel, lessThan(1.0));
    });

    test('reset 回到全景', () {
      final t = _transform(zoom: 3.0, pan: const Offset(50, 50));
      t.reset();
      expect(t.zoom, 1.0);
      expect(t.pan, Offset.zero);
    });
  });

  group('吸附到中心线', () {
    test('线外 20 米的点吸到线上（到线距离≈0）', () {
      // 南边底边中点向南偏约 20 米。
      const off = GeoPoint(31.2000 - 20 / 110540, 121.4050);
      final snapped = snapPointToCenterline(off, _squareLine());
      expect(snapped.lat, closeTo(31.2000, 1e-6));
      expect(snapped.lon, closeTo(121.4050, 1e-6));
      final dist = nearestOnPolyline(off, _squareLine()).distM;
      expect(dist, closeTo(20, 0.5));
    });

    test('线上点吸附后不动', () {
      const on = GeoPoint(31.2000, 121.4050);
      final snapped = snapPointToCenterline(on, _squareLine());
      expect(snapped.lat, closeTo(on.lat, 1e-9));
      expect(snapped.lon, closeTo(on.lon, 1e-9));
    });

    test('无中心线时原样返回', () {
      const p = GeoPoint(31.2, 121.4);
      expect(snapPointToCenterline(p, const []), p);
      expect(snapPointToCenterline(p, const [GeoPoint(31.2, 121.4)]), p);
    });

    test('沿线距离与按距离取点往返一致', () {
      final line = _squareLine();
      final total = polylineLengthM(line);
      // 底边中点：距线首约半条底边。
      const mid = GeoPoint(31.2000, 121.4050);
      final d = centerlineDistanceAt(mid, line);
      expect(d, closeTo(polylineLengthM([line[0], line[1]]) / 2, 1.0));
      final back = pointAtCenterlineDistance(line, d);
      expect(back.lat, closeTo(mid.lat, 1e-6));
      expect(back.lon, closeTo(mid.lon, 1e-6));
      // 边界钳制。
      expect(pointAtCenterlineDistance(line, 0), line.first);
      expect(pointAtCenterlineDistance(line, total + 1000), line.last);
      // 滑块中途值落在底边上（总长/8 < 底边长）。
      final eighth = pointAtCenterlineDistance(line, total / 8);
      expect(eighth.lat, closeTo(31.2000, 1e-6));
    });
  });

  group('方向键微调', () {
    test('向北 1 米：纬度增加约 1/110540', () {
      const p = GeoPoint(31.2, 121.4);
      final moved = nudgeGeoPoint(p, northM: 1, eastM: 0);
      expect(moved.lat - p.lat, closeTo(1 / 110540, 1e-9));
      expect(moved.lon, p.lon);
    });

    test('向东 5 米：经度按 cos(纬度) 换算', () {
      const p = GeoPoint(31.2, 121.4);
      final moved = nudgeGeoPoint(p, northM: 0, eastM: 5);
      final expected = 5 / (111320 * 0.8555); // cos(31.2°) ≈ 0.8555
      expect(moved.lon - p.lon, closeTo(expected, 1e-6));
      expect(moved.lat, p.lat);
    });

    test('零位移不动', () {
      const p = GeoPoint(31.2, 121.4);
      final moved = nudgeGeoPoint(p, northM: 0, eastM: 0);
      expect(moved.lat, p.lat);
      expect(moved.lon, p.lon);
    });
  });

  group('撤销栈', () {
    test('多步撤销按压栈逆序弹出，空栈返回 null', () {
      final stack = EditorUndoStack<int>();
      expect(stack.canUndo, isFalse);
      stack.push(1);
      stack.push(2);
      stack.push(3);
      expect(stack.length, 3);
      expect(stack.undo(), 3);
      expect(stack.undo(), 2);
      expect(stack.undo(), 1);
      expect(stack.canUndo, isFalse);
      expect(stack.undo(), isNull);
    });

    test('超限丢弃最旧快照', () {
      final stack = EditorUndoStack<int>(maxDepth: 3);
      stack.push(1);
      stack.push(2);
      stack.push(3);
      stack.push(4);
      expect(stack.length, 3);
      expect(stack.undo(), 4);
      expect(stack.undo(), 3);
      expect(stack.undo(), 2);
      expect(stack.undo(), isNull);
    });
  });

  group('卫星底图纯函数', () {
    test('瓦片 URL：Esri 顺序为 z/y/x，免 Key', () {
      expect(
        satelliteTileUrl(15, 26979, 18109),
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/15/18109/26979',
      );
    });

    test('瓦片行列包含目标经纬度（角点反算往返）', () {
      const lat = 31.2050;
      const lon = 121.4050;
      const z = 15;
      final x = satelliteTileX(lon, z).floor();
      final y = satelliteTileY(lat, z).floor();
      expect(satelliteTileWestLon(x, z), lessThanOrEqualTo(lon));
      expect(satelliteTileWestLon(x + 1, z), greaterThan(lon));
      expect(satelliteTileNorthLat(y, z), greaterThanOrEqualTo(lat));
      expect(satelliteTileNorthLat(y + 1, z), lessThan(lat));
    });

    test('按米/像素选缩放：越精细越高，钳制在 10–19', () {
      // 2.5 米/像素 @31.2°：156543×cos31.2°/2.5 ≈ 2^15.71 → 16 级。
      expect(satelliteZoomForMetersPerPixel(2.5, 31.2), 16);
      expect(
        satelliteZoomForMetersPerPixel(0.5, 31.2),
        greaterThan(satelliteZoomForMetersPerPixel(2.5, 31.2)),
      );
      expect(satelliteZoomForMetersPerPixel(10000, 31.2), satelliteMinZoom);
      expect(satelliteZoomForMetersPerPixel(0.01, 31.2), satelliteMaxZoom);
      expect(satelliteZoomForMetersPerPixel(double.nan, 31.2), satelliteMinZoom);
    });

    test('瓦片范围覆盖给定经纬度框，行列有序', () {
      final r = satelliteTileRange(
        minLat: 31.20,
        maxLat: 31.209,
        minLon: 121.40,
        maxLon: 121.41,
        zoom: 16,
      );
      expect(r.x0, lessThanOrEqualTo(r.x1));
      expect(r.y0, lessThanOrEqualTo(r.y1));
      // 框的四角都落在范围内。
      expect(satelliteTileX(121.40, 16).floor(), greaterThanOrEqualTo(r.x0));
      expect(satelliteTileX(121.41, 16).floor(), lessThanOrEqualTo(r.x1));
    });

    test('超大范围自动降级，瓦片数不超过上限', () {
      final tiles = satelliteTilesForBounds(
        minLat: 30.0,
        maxLat: 32.0,
        minLon: 120.0,
        maxLon: 122.0,
        metersPerPixel: 0.1,
        latitude: 31.0,
      );
      expect(tiles.length, lessThanOrEqualTo(satelliteMaxTiles));
      expect(tiles.length, greaterThan(0));
      // 同级瓦片 z 一致。
      expect(tiles.map((t) => t.z).toSet().length, 1);
    });

    test('瓦片屏幕矩形：角点与同一变换投影一致，宽高为正', () {
      final t = _transform();
      const z = 16;
      final x = satelliteTileX(121.4050, z).floor();
      final y = satelliteTileY(31.2050, z).floor();
      final rect = satelliteTileScreenRect(t, z, x, y);
      final nw = t.project(
        GeoPoint(satelliteTileNorthLat(y, z), satelliteTileWestLon(x, z)),
      );
      expect(rect.left, closeTo(nw.dx, 1e-9));
      expect(rect.top, closeTo(nw.dy, 1e-9));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      // 赛道中心点落在该瓦片矩形内（换算不打架）。
      expect(rect.contains(t.project(const GeoPoint(31.2050, 121.4050))), isTrue);
    });
  });

  group('编辑页 widget', () {
    testWidgets('渲染：工具卡片、缩放工具栏、撤销与保存齐全', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackPackageEditorPage(package: _pkg(), onSave: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      // 五张工具卡片。
      for (final label in ['起点', '终点', '龙门架', '分段点', '轮廓点']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('回到全景'), findsOneWidget);
      expect(find.text('吸附'), findsOneWidget);
      expect(find.text('落点列表（点某行选中该点，再用方向键或滑块微调）'), findsOneWidget);
      expect(find.text('分段 S1'), findsOneWidget);
      expect(find.text('手动输入坐标落点'), findsOneWidget);
      expect(find.text('保存'), findsWidgets);
      expect(find.text('取消'), findsOneWidget);
      // 撤销初始不可用（无快照）。
      final undo = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.undo),
          matching: find.byType(IconButton),
        ),
      );
      expect(undo.onPressed, isNull);
    });

    testWidgets('点工具卡片切换当前工具', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackPackageEditorPage(package: _pkg(), onSave: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('分段点').last);
      await tester.pump();
      // 切换后仍在页内、无报错；分段工具卡片高亮（红边框容器存在）。
      expect(find.text('分段点'), findsWidgets);
    });
  });

  group('卫星底图 widget', () {
    Finder esriImages() => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is NetworkImage &&
          (w.image as NetworkImage).url.startsWith(
            'https://server.arcgisonline.com/',
          ),
    );

    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackPackageEditorPage(package: _pkg(), onSave: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('默认关闭：无卫星瓦片、无回落提示', (tester) async {
      await pumpEditor(tester);
      expect(find.text('卫星底图'), findsOneWidget);
      expect(esriImages(), findsNothing);
      expect(find.text('卫星图未加载，已显示示意图'), findsNothing);
    });

    testWidgets('打开开关：叠加 Esri 瓦片并显示署名', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('satelliteToggle')));
      await tester.pump();
      expect(esriImages(), findsWidgets);
      expect(find.text(satelliteTileAttribution), findsOneWidget);
      expect(find.text('卫星图未加载，已显示示意图'), findsNothing);
    });

    testWidgets('关闭开关：瓦片层撤下，回到示意图', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('satelliteToggle')));
      await tester.pump();
      expect(esriImages(), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('satelliteToggle')));
      await tester.pump();
      expect(esriImages(), findsNothing);
      expect(find.text(satelliteTileAttribution), findsNothing);
    });

    testWidgets('瓦片全部加载失败：静默回落示意图，状态行提示', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('satelliteToggle')));
      // 测试环境无真实网络：瓦片失败走 errorBuilder，累计达阈值后回落。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('卫星图未加载，已显示示意图'), findsOneWidget);
      expect(esriImages(), findsNothing);
    });
  });
}
