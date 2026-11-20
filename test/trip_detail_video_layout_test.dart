import 'package:drive_track/main.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:drive_track/vehicle_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<TrackPoint> _points() => List.generate(
  20,
  (i) => TrackPoint(
    timeMs: 1000000 + i * 1000,
    lat: 31.2 + i * 0.00001,
    lon: 121.4,
    alt: 10,
    speed: 8,
    bearing: 0,
    hAcc: 3,
    vAcc: 3,
    speedAcc: 1,
    provider: 'gps',
    longG: 0,
    latG: 0,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: 0,
    pressureHpa: 0,
    calibrated: true,
  ),
);

class _TripStore extends Store {
  final Trip trip;
  _TripStore(this.trip);

  @override
  Future<Trip?> loadTrip(String id) async => trip;

  @override
  Future<List<TripMeta>> loadIndex() async => [];

  @override
  Future<VehicleLibrary> loadVehicleLibrary() async => const VehicleLibrary();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'linked videos keep five actions without add entry or vertical copy',
    (tester) async {
      const fileName =
          'a_very_long_video_file_name_that_must_not_wrap_vertically.mp4';
      final trip = Trip(
        id: 'trip-video-layout',
        mode: TripMode.car,
        startMs: 1000000,
        endMs: 1019000,
        points: _points(),
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
        videoPaths: const ['/files/$fileName'],
      );
      final store = _TripStore(trip);

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final config in [
        (width: 360.0, textScale: 1.0),
        (width: 320.0, textScale: 1.3),
      ]) {
        tester.view.physicalSize = Size(config.width, 6000);
        await tester.pumpWidget(
          MaterialApp(
            theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(config.textScale),
              ),
              child: TripDetailPage(store: store, tripId: trip.id),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('同步视频'), findsWidgets);
        expect(find.text('添加视频'), findsNothing);
        expect(find.text(fileName), findsNothing);
        expect(find.text('点回顾进应用内播放，画面叠加速度/G 值'), findsNothing);
        for (final label in [
          '视频回顾（应用内叠加）',
          '系统播放器播放',
          '视频 HUD 合成',
          '分享视频',
          '移除关联',
        ]) {
          expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${config.width}px at ${config.textScale}x text scale',
        );
      }
    },
  );
}
