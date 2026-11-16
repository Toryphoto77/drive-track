import 'package:drive_track/models.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:drive_track/vehicle_markers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewKey = Key('vehicle-marker-interactive-preview');
const _canvasKey = Key('vehicle-marker-3d-canvas');
const _angleKey = Key('vehicle-marker-view-angle');
const _zoomKey = Key('vehicle-marker-view-zoom');

Future<void> _pumpSection(
  WidgetTester tester, {
  ValueChanged<VehicleMarkerSelection>? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
      home: Scaffold(
        body: ListView(
          children: [VehicleMarkerSettingsSection(onChanged: onChanged)],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

VehicleMarkerPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byKey(_canvasKey));
  return paint.painter! as VehicleMarkerPainter;
}

Future<void> _pinchOut(WidgetTester tester) async {
  final center = tester.getCenter(find.byKey(_previewKey));
  final first = await tester.startGesture(
    center - const Offset(24, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(24, 0),
    pointer: 2,
  );
  await tester.pump();
  await first.moveTo(center - const Offset(66, 0));
  await second.moveTo(center + const Offset(66, 0));
  await tester.pump();
  await first.up();
  await second.up();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('主题页三维车标选项', () {
    testWidgets('汽车使用可交互预览和卡片网格，不再使用纵向 ListTile', (tester) async {
      await _pumpSection(tester);
      expect(find.byKey(_previewKey), findsOneWidget);
      expect(find.byKey(_canvasKey), findsOneWidget);
      expect(find.text('拖动旋转 · 双指缩放 · 双击复位'), findsOneWidget);
      expect(find.byKey(_angleKey), findsOneWidget);
      expect(find.byKey(_zoomKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VehicleMarkerSettingsSection),
          matching: find.byType(GridView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(VehicleMarkerSettingsSection),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('vehicle-marker-option-car-sedan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vehicle-marker-option-car-offroad')),
        findsOneWidget,
      );
    });

    testWidgets('点选卡片立即更新选中态并保留原选择回调', (tester) async {
      VehicleMarkerSelection? selected;
      await _pumpSection(tester, onChanged: (value) => selected = value);
      final sport = find.byKey(const Key('vehicle-marker-option-car-sport'));
      await tester.tap(sport);
      await tester.pump();
      expect(selected?.car, CarMarkerStyle.sport);
      expect(_painter(tester).styleKey, 'sport');
      expect(
        find.descendant(of: sport, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    });

    testWidgets('卡丁车保留三维交互并使用原汽车持久化选择', (tester) async {
      VehicleMarkerSelection? selected;
      await _pumpSection(tester, onChanged: (value) => selected = value);
      await tester.tap(find.text('卡丁车'));
      await tester.pump();
      expect(find.byKey(_previewKey), findsOneWidget);
      expect(_painter(tester).mode, TripMode.kart);
      await tester.tap(
        find.byKey(const Key('vehicle-marker-option-kart-sport')),
      );
      await tester.pump();
      expect(selected?.car, CarMarkerStyle.sport);
      expect(selected?.toJson()['vehicleMarkerCar'], 'sport');
    });

    test('旧持久化 key 不变', () {
      const selection = VehicleMarkerSelection(
        car: CarMarkerStyle.offroad,
        moto: MotoMarkerStyle.honda,
        bike: BikeMarkerStyle.city,
      );
      expect(selection.toJson(), {
        'vehicleMarkerCar': 'offroad',
        'vehicleMarkerMoto': 'honda',
        'vehicleMarkerBike': 'city',
      });
    });
  });

  group('三维预览手势', () {
    testWidgets('拖动改变方位角和俯仰角，角度提示同步更新', (tester) async {
      await _pumpSection(tester);
      final before = _painter(tester);
      final beforeText = tester.widget<Text>(find.byKey(_angleKey)).data;
      await tester.drag(find.byKey(_previewKey), const Offset(64, -24));
      await tester.pump(const Duration(milliseconds: 400));
      final after = _painter(tester);
      expect(after.headingDeg, isNot(before.headingDeg));
      expect(after.pitchDeg, isNot(before.pitchDeg));
      expect(
        tester.widget<Text>(find.byKey(_angleKey)).data,
        isNot(beforeText),
      );
    });

    testWidgets('双指缩放更新画笔和倍率提示', (tester) async {
      await _pumpSection(tester);
      expect(_painter(tester).zoom, 1.0);
      await _pinchOut(tester);
      expect(_painter(tester).zoom, greaterThan(1.0));
      expect(tester.widget<Text>(find.byKey(_zoomKey)).data, isNot('1.0×'));
    });

    testWidgets('双击将旋转和缩放恢复默认视角', (tester) async {
      await _pumpSection(tester);
      final initialHeading = _painter(tester).headingDeg;
      final initialPitch = _painter(tester).pitchDeg;
      await tester.drag(find.byKey(_previewKey), const Offset(80, 32));
      await tester.pump();
      await _pinchOut(tester);
      expect(_painter(tester).headingDeg, isNot(initialHeading));
      expect(_painter(tester).zoom, greaterThan(1.0));
      await tester.tap(find.byKey(_previewKey));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(_previewKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_painter(tester).headingDeg, initialHeading);
      expect(_painter(tester).pitchDeg, initialPitch);
      expect(_painter(tester).zoom, 1.0);
      expect(tester.widget<Text>(find.byKey(_zoomKey)).data, '1.0×');
    });
  });
}
