import 'dart:ui' as ui;

import 'package:drive_track/models.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:drive_track/vehicle_markers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 车标冒烟测试（v1.3.8 精细化重做）。
///
/// 覆盖三模式全部 9 种风格在 40 / 48 / 64px 下渲染不崩；
/// 36px 地图最小尺寸做像素级可读性自查（轮廓、灯、轮毂仍可辨认）；
/// 共用预览格与两处 UI 点选链路做 widget 级冒烟。

const _painters = <VehicleMarkerPainter>[
  VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sedan'),
  VehicleMarkerPainter(mode: TripMode.car, styleKey: 'sport'),
  VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'ducati'),
  VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'yamaha'),
  VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'honda'),
  VehicleMarkerPainter(mode: TripMode.moto, styleKey: 'kawasaki'),
  VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'road'),
  VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'mountain'),
  VehicleMarkerPainter(mode: TripMode.bike, styleKey: 'city'),
];

Future<ui.Image> _render(VehicleMarkerPainter p, double s) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & Size(s, s));
  p.paint(canvas, Size(s, s));
  return recorder.endRecording().toImage(s.toInt(), s.toInt());
}

/// [img] 的 RGBA 像素数组（行优先，透明底为全 0）。
Future<List<int>> _rgba(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

void main() {
  group('vehicle marker smoke (v1.3.8)', () {
    test('all 9 styles paint without throwing at 40/48/64px', () {
      for (final p in _painters) {
        for (final s in [40.0, 48.0, 64.0]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, Offset.zero & Size(s, s));
          p.paint(canvas, Size(s, s));
          recorder.endRecording();
        }
      }
    });

    test('heading rotation does not throw at 56px', () {
      for (final deg in [0.0, 45.0, 90.0, 180.0, 270.0]) {
        const sel = VehicleMarkerSelection();
        final p = markerPainterFor(sel, TripMode.moto, headingDeg: deg);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, Offset.zero & const Size(56, 56));
        p.paint(canvas, const Size(56, 56));
        recorder.endRecording();
      }
    });
  });

  group('36px legibility (pixel check)', () {
    test('car: body silhouette + headlights + hubs visible at 36px',
        () async {
      for (final key in ['sedan', 'sport']) {
        final img = await _render(
            VehicleMarkerPainter(mode: TripMode.car, styleKey: key), 36);
        final px = await _rgba(img);
        const n = 36;
        var opaque = 0;
        var headlight = 0;
        var hub = 0;
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            final i = (y * n + x) * 4;
            final a = px[i + 3];
            if (a == 0) continue;
            opaque++;
            final r = px[i], g = px[i + 1], b = px[i + 2];
            // 前灯带：车头区域（y 3..6）的淡黄像素。
            if (y >= 3 && y <= 6 && r > 200 && g > 180 && b > 100 && b < 210) {
              headlight++;
            }
            // 轮毂亮点：轮胎区（x 5..9 或 26..30，y 7..14 或 23..30）
            // 的浅灰像素。
            if (((x >= 5 && x <= 9) || (x >= 26 && x <= 30)) &&
                ((y >= 7 && y <= 14) || (y >= 23 && y <= 30)) &&
                r > 150 && g > 150 && b > 150) {
              hub++;
            }
          }
        }
        // 车体轮廓占画布约 1/4 以上（阴影 + 车体 + 四轮）。
        expect(opaque, greaterThan(n * n * 0.20), reason: '$key opaque');
        expect(headlight, greaterThanOrEqualTo(2), reason: '$key headlight');
        expect(hub, greaterThanOrEqualTo(2), reason: '$key hub');
      }
    });

    test('moto: fairing + accent stripe visible at 36px', () async {
      for (final style in MotoMarkerStyle.values) {
        final img = await _render(
            VehicleMarkerPainter(mode: TripMode.moto, styleKey: style.key),
            36);
        final px = await _rgba(img);
        const n = 36;
        var opaque = 0;
        var accent = 0;
        final ac = style.accent;
        final ar = (ac.r * 255).round();
        final ag = (ac.g * 255).round();
        final ab = (ac.b * 255).round();
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            final i = (y * n + x) * 4;
            if (px[i + 3] == 0) continue;
            opaque++;
            // 品牌色条区（y 21..22：色条 0.575–0.615 × 36px）的近似品牌色像素。
            if (y >= 21 &&
                y <= 22 &&
                (px[i] - ar).abs() < 40 &&
                (px[i + 1] - ag).abs() < 40 &&
                (px[i + 2] - ab).abs() < 40) {
              accent++;
            }
          }
        }
        expect(opaque, greaterThan(n * n * 0.10), reason: '${style.key} opaque');
        expect(accent, greaterThanOrEqualTo(1), reason: '${style.key} accent');
      }
    });

    test('bike: wheels + frame visible at 36px', () async {
      for (final key in ['road', 'mountain', 'city']) {
        final img = await _render(
            VehicleMarkerPainter(mode: TripMode.bike, styleKey: key), 36);
        final px = await _rgba(img);
        const n = 36;
        var opaque = 0;
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] > 0) opaque++;
        }
        // 细线车架 + 两轮圈，占比低但必须成形（> 5%）。
        expect(opaque, greaterThan(n * n * 0.05), reason: '$key opaque');
      }
    });
  });

  group('preview tile widget', () {
    testWidgets('tile is 64x64 with a 56px marker inside',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VehicleMarkerPreviewTile(
              selection: VehicleMarkerSelection(),
              mode: TripMode.car,
            ),
          ),
        ),
      );
      final tile = find.byType(VehicleMarkerPreviewTile);
      expect(tile, findsOneWidget);
      expect(tester.getSize(tile), const Size(64, 64));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('picker page tap switches style and calls onChanged',
        (tester) async {
      VehicleMarkerSelection? got;
      await tester.pumpWidget(
        MaterialApp(
          home: VehicleMarkerPickerPage(
            onChanged: (s) => got = s,
          ),
        ),
      );
      await tester.tap(find.text('跑车'));
      await tester.pump();
      expect(got, isNotNull);
      expect(got!.car, CarMarkerStyle.sport);
    });

    testWidgets('settings section tap switches style and calls onChanged',
        (tester) async {
      VehicleMarkerSelection? got;
      await tester.pumpWidget(
        MaterialApp(
          theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
          home: Scaffold(
            body: VehicleMarkerSettingsSection(
              onChanged: (s) => got = s,
            ),
          ),
        ),
      );
      await tester.tap(find.text('跑车'));
      await tester.pump();
      expect(got, isNotNull);
      expect(got!.car, CarMarkerStyle.sport);
    });
  });
}
