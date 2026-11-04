import 'package:drive_track/photo_points.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('旧数据兼容（无 type/title/id 键）', () {
    test('有照片的旧数据默认为 photo 类型', () {
      final p = PhotoPoint.fromJson({
        'lat': 30.123456,
        'lon': 120.654321,
        't': 1700000000000,
        'photo': '/x/photo_points/photo_1.jpg',
        'note': '旧备注',
      });
      expect(p.effectiveType, PhotoPointType.photo);
      expect(p.type, isNull);
      expect(p.title, isNull);
      expect(p.hasPhoto, isTrue);
    });

    test('无照片的旧数据默认为 marker 类型', () {
      final p = PhotoPoint.fromJson({
        'lat': 30.0,
        'lon': 120.0,
        't': 1700000000000,
      });
      expect(p.effectiveType, PhotoPointType.marker);
      expect(p.hasPhoto, isFalse);
    });

    test('kind 键可作 type 的别名', () {
      final p = PhotoPoint.fromJson({
        'lat': 30.0,
        'lon': 120.0,
        't': 1700000000000,
        'kind': 'fuel',
      });
      expect(p.effectiveType, PhotoPointType.fuel);
    });

    test('未知 type 名字回落到默认规则，不抛错', () {
      final p = PhotoPoint.fromJson({
        'lat': 30.0,
        'lon': 120.0,
        't': 1700000000000,
        'type': 'not_a_type',
      });
      expect(p.effectiveType, PhotoPointType.marker);
    });
  });

  group('id 稳定性', () {
    test('旧数据无 id 时由 lat/lon/timeMs 生成稳定 id，两次加载一致', () {
      final json = {'lat': 30.123456, 'lon': 120.654321, 't': 1700000000000};
      final a = PhotoPoint.fromJson(json);
      final b = PhotoPoint.fromJson(json);
      expect(a.resolvedId, b.resolvedId);
      expect(a.resolvedId,
          PhotoPoint.stableId(30.123456, 120.654321, 1700000000000));
      expect(a.resolvedId, isNotEmpty);
    });

    test('显式 id 优先，toJson/fromJson 往返保持', () {
      final p = PhotoPoint.fromJson({
        'lat': 30.0,
        'lon': 120.0,
        't': 1700000000000,
        'type': 'rest',
        'title': '服务区',
        'id': 'custom-1',
      });
      expect(p.resolvedId, 'custom-1');
      final back = PhotoPoint.fromJson(p.toJson());
      expect(back.resolvedId, 'custom-1');
      expect(back.effectiveType, PhotoPointType.rest);
      expect(back.title, '服务区');
    });

    test('旧数据一经 toJson 就带上稳定 id，再加载不变', () {
      final p = PhotoPoint.fromJson(
          {'lat': 30.0, 'lon': 120.0, 't': 1700000000000});
      final back = PhotoPoint.fromJson(p.toJson());
      expect(back.resolvedId, p.resolvedId);
    });
  });

  group('长度上限', () {
    test('title 超 50 字被截断，note 超 200 字被截断', () {
      final longTitle = '标' * 60;
      final longNote = '备' * 250;
      final p = PhotoPoint.fromJson({
        'lat': 30.0,
        'lon': 120.0,
        't': 1,
        'title': longTitle,
        'note': longNote,
      });
      expect(p.title!.length, 50);
      expect(p.note!.length, 200);
      final viaCopy = p.copyWith(title: 'x' * 60, note: 'y' * 250);
      expect(viaCopy.title!.length, 50);
      expect(viaCopy.note!.length, 200);
    });
  });

  group('时间排序与类型筛选', () {
    final points = [
      const PhotoPoint(lat: 30.0, lon: 120.0, timeMs: 3000),
      const PhotoPoint(
          lat: 30.0, lon: 120.0, timeMs: 1000, type: PhotoPointType.fuel),
      const PhotoPoint(
          lat: 30.0, lon: 120.0, timeMs: 2000, type: PhotoPointType.fuel),
      const PhotoPoint(lat: 30.0, lon: 120.0, timeMs: 2000),
    ];

    test('按时间升序，时间相同按稳定 id 确定顺序，不改原列表', () {
      final sorted = sortPhotoPointsByTime(points);
      expect(sorted.map((p) => p.timeMs).toList(), [1000, 2000, 2000, 3000]);
      expect(points.first.timeMs, 3000);
    });

    test('筛选 fuel 只返回该类型，null 返回全部', () {
      final fuels = filterPhotoPointsByType(points, PhotoPointType.fuel);
      expect(fuels.length, 2);
      expect(fuels.every((p) => p.effectiveType == PhotoPointType.fuel),
          isTrue);
      expect(filterPhotoPointsByType(points, null).length, 4);
    });
  });

  group('类型清单', () {
    test('6 种类型，中文标签非空、颜色互不相同', () {
      expect(PhotoPointType.values.length, 6);
      final labels =
          PhotoPointType.values.map((t) => t.label).toSet();
      expect(labels.length, 6);
      final colors =
          PhotoPointType.values.map((t) => t.color).toSet();
      expect(colors.length, 6);
      expect(PhotoPointType.photo.label, '照片');
      expect(PhotoPointType.marker.label, '标记');
      expect(PhotoPointType.incident.label, '状况');
      expect(PhotoPointType.fuel.label, '加油');
      expect(PhotoPointType.rest.label, '休息');
      expect(PhotoPointType.view.label, '风景');
    });
  });

  group('TripAlbumPage 参数', () {
    testWidgets('时间线按时间排序并显示类型筛选 chips', (tester) async {
      final points = [
        const PhotoPoint(
            lat: 30.0, lon: 120.0, timeMs: 3000, type: PhotoPointType.view),
        const PhotoPoint(
            lat: 30.0, lon: 120.0, timeMs: 1000, type: PhotoPointType.fuel),
      ];
      await tester.pumpWidget(MaterialApp(
        home: TripAlbumPage(
          initialPhotoPoints: points,
          trackPoints: const [],
          focusPointId: points[1].resolvedId,
        ),
      ));
      await tester.pumpAndSettle();
      // chips 存在（“全部”只在 chip 行出现一次；类型标签在
      // chip 与卡片各出现一次，故用 findsWidgets）。
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('加油'), findsWidgets);
      expect(find.text('风景'), findsWidgets);
      // 传入 focusPointId 不崩溃；时间顺序由纯函数单测覆盖。
    });
  });
}
