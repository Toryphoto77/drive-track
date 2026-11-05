/// v1.2.16（B 路：行程 GPS 来源标签）测试。
///
/// 覆盖：
/// - classifyGpsSource 四档：全外接 / 全手机 / 混合 / 未知；
/// - 空列表、空串 provider、大小写 provider；
/// - TripMeta fromJson/toJson 往返与缺键 / 非法值回退 unknown；
/// - 标签与徽标配色。
/// 不含任何真机断言（纯函数 + JSON 往返）。

import 'package:drive_track/gps_source.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyGpsSource', () {
    test('全外接 → external', () {
      expect(classifyGpsSource(['external', 'external']), GpsSource.external);
    });

    test('全手机（gps / network / fused 原始值）→ phone', () {
      expect(classifyGpsSource(['gps', 'network', 'fused']), GpsSource.phone);
      expect(classifyGpsSource(['gps']), GpsSource.phone);
    });

    test('外接 + 手机 → mixed', () {
      expect(classifyGpsSource(['gps', 'external']), GpsSource.mixed);
      expect(classifyGpsSource(['external', 'fused', 'external']), GpsSource.mixed);
    });

    test('空列表 → unknown', () {
      expect(classifyGpsSource([]), GpsSource.unknown);
    });

    test('空串 / 全空白 provider → unknown（该点无 provider，不计入任何一方）', () {
      expect(classifyGpsSource(['', '   ']), GpsSource.unknown);
      // 空串混在外接点里不改变结果。
      expect(classifyGpsSource(['external', '']), GpsSource.external);
      expect(classifyGpsSource(['gps', '']), GpsSource.phone);
    });

    test('大小写不敏感', () {
      expect(classifyGpsSource(['EXTERNAL']), GpsSource.external);
      expect(classifyGpsSource(['External', 'GPS']), GpsSource.mixed);
      expect(classifyGpsSource(['Gps', 'FUSED']), GpsSource.phone);
    });

    test('非 external 的非空值一律归手机侧', () {
      expect(classifyGpsSource(['phone']), GpsSource.phone);
      expect(classifyGpsSource(['passive']), GpsSource.phone);
    });
  });

  group('GpsSource 标签与配色', () {
    test('中文标签', () {
      expect(GpsSource.external.label, '外接 GPS');
      expect(GpsSource.phone.label, '手机 GPS');
      expect(GpsSource.mixed.label, '混合');
      expect(GpsSource.unknown.label, '');
    });

    test('徽标配色：外接绿、手机灰、混合琥珀', () {
      expect(GpsSource.external.chipColor, const Color(0xFF4CAF50));
      expect(GpsSource.phone.chipColor, const Color(0xFF9E9E9E));
      expect(GpsSource.mixed.chipColor, const Color(0xFFFFB300));
    });

    test('fromKey：缺键 / null / 非法值 → unknown', () {
      expect(GpsSourceLabel.fromKey(null), GpsSource.unknown);
      expect(GpsSourceLabel.fromKey('bogus'), GpsSource.unknown);
      expect(GpsSourceLabel.fromKey('external'), GpsSource.external);
      expect(GpsSourceLabel.fromKey('mixed'), GpsSource.mixed);
    });
  });

  group('TripMeta gpsSource JSON', () {
    TripMeta meta({GpsSource gpsSource = GpsSource.unknown}) => TripMeta(
          't1',
          TripMode.car,
          1000,
          2000,
          1500,
          80,
          false,
          gpsSource: gpsSource,
        );

    test('toJson 写 gps 键，fromJson 往返一致', () {
      for (final s in GpsSource.values) {
        final j = meta(gpsSource: s).toJson();
        expect(j['gps'], s.name);
        expect(TripMeta.fromJson(j).gpsSource, s);
      }
    });

    test('缺 gps 键 → unknown（老行程不回填）', () {
      final j = meta().toJson()..remove('gps');
      expect(TripMeta.fromJson(j).gpsSource, GpsSource.unknown);
    });

    test('非法 gps 值 → unknown，不抛错', () {
      final j = meta().toJson()..['gps'] = 'not-a-source';
      expect(TripMeta.fromJson(j).gpsSource, GpsSource.unknown);
    });

    test('默认构造即 unknown', () {
      const m = TripMeta('t1', TripMode.car, 1000, 2000, 1500, 80, false);
      expect(m.gpsSource, GpsSource.unknown);
    });
  });

  group('GpsSourceChip', () {
    testWidgets('unknown 不显示任何标签', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GpsSourceChip(source: GpsSource.unknown)),
      );
      expect(find.text('外接 GPS'), findsNothing);
      expect(find.text('手机 GPS'), findsNothing);
      expect(find.text('混合'), findsNothing);
    });

    testWidgets('三档各显示对应标签', (tester) async {
      for (final entry in {
        GpsSource.external: '外接 GPS',
        GpsSource.phone: '手机 GPS',
        GpsSource.mixed: '混合',
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(home: GpsSourceChip(source: entry.key)),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });
  });
}
