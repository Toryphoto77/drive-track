import 'package:drive_track/models.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:drive_track/vehicle_markers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _accent = Color(0xFF00A19B);

Future<void> _pumpSection(
  WidgetTester tester, {
  ValueChanged<VehicleMarkerSelection>? onChanged,
  double width = 400,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: DriveTrackTheme.dark(_accent),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: ListView(
            children: [
              VehicleMarkerSettingsSection(
                accentColor: _accent,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('主题页地图车标选项', () {
    testWidgets('车型药丸居中并使用主题色，不再显示三维交互预览', (tester) async {
      await _pumpSection(tester);
      final segments = find.byType(SegmentedButton<TripMode>);
      expect(segments, findsOneWidget);
      expect(
        tester.getCenter(segments).dx,
        closeTo(
          tester.getCenter(find.byType(VehicleMarkerSettingsSection)).dx,
          0.5,
        ),
      );

      final button = tester.widget<SegmentedButton<TripMode>>(segments);
      final selected = <WidgetState>{WidgetState.selected};
      expect(
        button.style?.backgroundColor?.resolve(selected),
        _accent.withValues(alpha: 0.18),
      );
      expect(button.style?.side?.resolve(selected)?.color, _accent);
      expect(button.style?.iconColor?.resolve(selected), _accent);

      expect(find.text('真车风格 · 三维网格'), findsNothing);
      expect(
        find.byKey(const Key('vehicle-marker-interactive-preview')),
        findsNothing,
      );
      expect(find.byKey(const Key('vehicle-marker-view-angle')), findsNothing);
      expect(find.byKey(const Key('vehicle-marker-view-zoom')), findsNothing);
      expect(find.text('拖动旋转 · 双指缩放 · 双击复位'), findsNothing);
      expect(find.textContaining('三维造型'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(VehicleMarkerSettingsSection),
          matching: find.byType(GridView),
        ),
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
      expect(
        find.descendant(of: sport, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    });

    testWidgets('摩托与卡丁车都可切换，卡丁车沿用原汽车持久化 key', (tester) async {
      VehicleMarkerSelection? selected;
      await _pumpSection(tester, onChanged: (value) => selected = value);

      await tester.tap(find.text('摩托'));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('vehicle-marker-option-moto-yamaha')),
      );
      await tester.pump();
      expect(selected?.moto, MotoMarkerStyle.yamaha);

      await tester.tap(find.text('卡丁车'));
      await tester.pump();
      expect(
        find.byKey(const Key('vehicle-marker-interactive-preview')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('vehicle-marker-option-kart-sport')),
      );
      await tester.pump();
      expect(selected?.car, CarMarkerStyle.sport);
      expect(selected?.toJson()['vehicleMarkerCar'], 'sport');
    });

    testWidgets('车型选项在 320 宽度与 1.3 倍文字下不溢出', (tester) async {
      await _pumpSection(tester, width: 320, textScale: 1.3);
      final segments = find.byType(SegmentedButton<TripMode>);
      expect(segments, findsOneWidget);
      expect(
        tester.getCenter(segments).dx,
        closeTo(
          tester.getCenter(find.byType(VehicleMarkerSettingsSection)).dx,
          0.5,
        ),
      );
      expect(tester.takeException(), isNull);
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
}
