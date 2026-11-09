import 'package:drive_track/lean_estimator.dart';
import 'package:drive_track/track_landscape_panel.dart';
import 'package:drive_track/track_live_g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('split puts the map on the left and hides it from a second column', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TrackLandscapeSplit(
          map: SizedBox(key: Key('map-pane'), child: Text('MAP')),
          instruments: Text('HUD'),
        ),
      ),
    ));
    final map = tester.getTopLeft(find.byKey(const Key('map-pane')));
    final hud = tester.getTopLeft(find.text('HUD'));
    expect(map.dx, lessThan(hud.dx));
    expect(tester.getSize(find.byKey(const Key('map-pane'))).width, greaterThan(400));
  });

  testWidgets('full map keeps corner capsules and drops the instrument column', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TrackLandscapeSplit(
          fullMap: true,
          map: Text('MAP'),
          instruments: Text('HUD'),
          fullMapOverlay: Text('CAPSULE'),
        ),
      ),
    ));
    expect(find.text('MAP'), findsOneWidget);
    expect(find.text('CAPSULE'), findsOneWidget);
    expect(find.text('HUD'), findsNothing);
  });

  testWidgets('instrument column shows lap time and Delta, not pause or lap list', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var details = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrackLandscapeInstruments(
          currentLapNumber: 3,
          currentLapMs: 95432,
          timerPaused: false,
          timerLive: false,
          liveDeltaMs: -170,
          showDelta: true,
          sectorLabels: const ['S1', 'S2', 'S3'],
          sectorTimesMs: const [25123, 33456],
          sectorDeltasMs: const [-320, 150, null],
          speedKmh: 128,
          speedColor: Colors.red,
          latG: -0.42,
          longG: 0.2,
          leanDeg: 18,
          leanQuality: LeanQuality.good,
          leanCalibrated: true,
          autoPaused: false,
          distanceKm: 4.2,
          elapsedLabel: '12分',
          onOpenDetails: () => details++,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('track-landscape-delta')), findsOneWidget);
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.byType(TrackGCross), findsOneWidget);
    expect(find.textContaining('横向'), findsOneWidget);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('长按结束'), findsNothing);
    expect(find.text('圈速列表'), findsNothing);
    expect(find.byKey(const Key('track-landscape-pause')), findsNothing);
    await tester.tap(find.byKey(const Key('track-landscape-details')));
    expect(details, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-pause banner appears only while paused', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TrackLandscapeInstruments(
          currentLapNumber: 1,
          currentLapMs: 1000,
          timerPaused: true,
          timerLive: false,
          liveDeltaMs: null,
          showDelta: true,
          sectorLabels: const ['S1'],
          sectorTimesMs: const [],
          sectorDeltasMs: const [],
          speedKmh: 0,
          speedColor: Colors.white,
          latG: 0,
          longG: 0,
          leanDeg: 0,
          leanQuality: LeanQuality.unreliable,
          leanCalibrated: false,
          autoPaused: true,
          distanceKm: 0,
          elapsedLabel: '0分',
        ),
      ),
    ));
    expect(find.byKey(const Key('track-landscape-pause')), findsOneWidget);
    expect(find.textContaining('已自动暂停'), findsOneWidget);
  });
}
