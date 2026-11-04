// v1.2.0 第 2 项（路网 + 3D 车）新增测试：只测纯函数与画笔不崩，
// 不发真实网络请求、不改现有测试文件。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/recording_3d_map.dart';
import 'package:drive_track/vehicle_markers.dart';

void main() {
  group('road tier', () {
    test('motorway/primary tier 0, secondary/tertiary tier 1', () {
      expect(roadTierForHighway('motorway'), 0);
      expect(roadTierForHighway('motorway_link'), 0);
      expect(roadTierForHighway('trunk'), 0);
      expect(roadTierForHighway('primary_link'), 0);
      expect(roadTierForHighway('secondary'), 1);
      expect(roadTierForHighway('tertiary_link'), 1);
    });

    test('residential/unknown tier 2, footway/cycleway tier 3', () {
      expect(roadTierForHighway('residential'), 2);
      expect(roadTierForHighway('unclassified'), 2);
      expect(roadTierForHighway('service'), 2);
      expect(roadTierForHighway(''), 2); // 旧缓存无 highway，不降级到步行类
      expect(roadTierForHighway('footway'), 3);
      expect(roadTierForHighway('path'), 3);
      expect(roadTierForHighway('cycleway'), 3);
      expect(roadTierForHighway('pedestrian'), 3);
    });

    test('higher tier is wider and brighter than lower tier', () {
      final t0 = roadStyleForHighway('motorway');
      final t1 = roadStyleForHighway('secondary');
      final t2 = roadStyleForHighway('residential');
      final t3 = roadStyleForHighway('footway');
      expect(t0.mainWidth, greaterThan(t1.mainWidth));
      expect(t1.mainWidth, greaterThan(t2.mainWidth));
      expect(t2.mainWidth, greaterThan(t3.mainWidth));
      // 亮度：用红通道比较（各级均为灰度色，红通道即亮度）。
      expect((t0.mainColor.r * 255.0).round(), greaterThan((t3.mainColor.r * 255.0).round()));
      expect((t1.mainColor.r * 255.0).round(), greaterThan((t3.mainColor.r * 255.0).round()));
      // 远处下限：各级主线最小宽度都不低于 1.0，远处仍可见。
      for (final s in [t0, t1, t2, t3]) {
        expect(s.minMainWidth, greaterThanOrEqualTo(1.0));
        expect(s.minGlowWidth, greaterThanOrEqualTo(2.0));
      }
    });
  });

  group('perspective floors', () {
    test('width: factor 0 -> min, factor 1 -> base, monotonic', () {
      expect(roadWidthFor(4.5, 2.2, 0), 2.2);
      expect(roadWidthFor(4.5, 2.2, 1), 4.5);
      expect(roadWidthFor(4.5, 2.2, 0.5), greaterThan(2.2));
      expect(roadWidthFor(4.5, 2.2, 0.5), lessThan(4.5));
      expect(roadWidthFor(4.5, 2.2, -1), 2.2); // 钳制
      expect(roadWidthFor(4.5, 2.2, 2), 4.5); // 钳制
    });

    test('alpha: factor 0 stays above min, factor 1 equals base', () {
      expect(roadAlphaFor(0.95, 0.80, 1), 0.95);
      expect(roadAlphaFor(0.95, 0.80, 0), greaterThanOrEqualTo(0.80));
      expect(roadAlphaFor(0.95, 0.80, 0), lessThan(0.95));
    });
  });

  group('parallel failure aggregation', () {
    test('busy wins over timeout/offline, timeout over offline', () {
      expect(pickRoadErrorKind(['busy', 'busy', 'busy', 'busy']), 'busy');
      expect(pickRoadErrorKind(['busy', 'timeout', 'offline', 'other']), 'busy');
      expect(pickRoadErrorKind(['timeout', 'offline', 'other', 'other']), 'timeout');
      expect(pickRoadErrorKind(['offline', 'other']), 'offline');
      expect(pickRoadErrorKind(['other']), 'other');
      expect(pickRoadErrorKind([]), 'other');
    });
  });

  group('overpass parsing', () {
    test('keeps ways with highway tag, drops nodes and short geometry', () {
      final ways = parseOverpassWays({
        'elements': [
          {
            'type': 'way',
            'tags': {'highway': 'motorway'},
            'geometry': [
              {'lat': 31.0, 'lon': 121.0},
              {'lat': 31.01, 'lon': 121.0},
            ],
          },
          {
            'type': 'way',
            'tags': {'highway': 'residential'},
            'geometry': [
              {'lat': 31.0, 'lon': 121.0},
            ], // 只有 1 点，丢弃
          },
          {
            'type': 'node', // 非 way，丢弃
            'lat': 31.0,
            'lon': 121.0,
          },
          {
            'type': 'way', // 无 tag，highway 为空串，不编造
            'geometry': [
              {'lat': 31.0, 'lon': 121.0},
              {'lat': 31.0, 'lon': 121.01},
            ],
          },
        ],
      });
      expect(ways.length, 2);
      expect(ways[0].highway, 'motorway');
      expect(ways[0].points.length, 2);
      expect(ways[1].highway, '');
    });

    test('caps at 200 ways', () {
      final elements = List.generate(
          201,
          (_) => {
                'type': 'way',
                'tags': {'highway': 'road'},
                'geometry': [
                  {'lat': 31.0, 'lon': 121.0},
                  {'lat': 31.01, 'lon': 121.0},
                ],
              });
      expect(parseOverpassWays({'elements': elements}).length, 200);
    });
  });

  group('road cache format', () {
    test('new format round-trips highway and points', () {
      const ways = [
        RoadWay([(31.0, 121.0), (31.01, 121.0)], highway: 'primary'),
        RoadWay([(31.0, 121.0), (31.0, 121.01)], highway: 'footway'),
      ];
      final back = roadWaysFromCacheJson(roadWaysToCacheJson(ways));
      expect(back.length, 2);
      expect(back[0].highway, 'primary');
      expect(back[1].highway, 'footway');
      expect(back[0].points[1].$1, 31.01);
    });

    test('old format (bare point lists) still loads with empty highway', () {
      final back = roadWaysFromCacheJson([
        [
          [31.0, 121.0],
          [31.01, 121.0],
        ],
      ]);
      expect(back.length, 1);
      expect(back[0].highway, '');
    });
  });

  group('vehicle marker painter (v1.2.0 contract)', () {
    test('markerPainterFor signature unchanged: heading preserved, no throw', () {
      const sel = VehicleMarkerSelection();
      final painter = markerPainterFor(sel, TripMode.car, headingDeg: 90);
      expect(painter, isA<VehicleMarkerPainter>());
      expect((painter as VehicleMarkerPainter).headingDeg, 90);
    });

    test('paint does not throw for every mode/style at 52px and 48px', () {
      final cases = <VehicleMarkerPainter>[
        const VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sedan'),
        const VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sport'),
        const VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'ducati'),
        const VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'yamaha'),
        const VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'honda'),
        const VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'kawasaki'),
        const VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'road'),
        const VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'mountain'),
        const VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'city'),
        const VehicleMarkerPainter(
            mode: TripMode.car, styleKey: 'sedan', headingDeg: 135),
      ];
      for (final p in cases) {
        for (final s in [52.0, 48.0]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, Offset.zero & Size(s, s));
          p.paint(canvas, Size(s, s));
          recorder.endRecording();
        }
      }
    });

    test('shouldRepaint tracks heading and style', () {
      const a = VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sedan');
      const b = VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sedan');
      const c = VehicleMarkerPainter(
          mode: TripMode.car, styleKey: 'sedan', headingDeg: 45);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });
}
