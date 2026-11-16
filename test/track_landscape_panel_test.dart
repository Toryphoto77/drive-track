import 'package:drive_track/gps_source_badge.dart';
import 'package:drive_track/lean_estimator.dart';
import 'package:drive_track/recording_map_page.dart';
import 'package:drive_track/track_landscape_panel.dart';
import 'package:drive_track/track_live_g.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'split puts the map on the left and hides it from a second column',
    (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackLandscapeSplit(
              map: SizedBox(key: Key('map-pane'), child: Text('MAP')),
              instruments: Text('HUD'),
            ),
          ),
        ),
      );
      final map = tester.getTopLeft(find.byKey(const Key('map-pane')));
      final hud = tester.getTopLeft(find.text('HUD'));
      expect(map.dx, lessThan(hud.dx));
      expect(
        tester.getSize(find.byKey(const Key('map-pane'))).width,
        greaterThan(400),
      );
    },
  );

  testWidgets(
    'full map keeps corner capsules and drops the instrument column',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackLandscapeSplit(
              fullMap: true,
              map: Text('MAP'),
              instruments: Text('HUD'),
              fullMapOverlay: Text('CAPSULE'),
            ),
          ),
        ),
      );
      expect(find.text('MAP'), findsOneWidget);
      expect(find.text('CAPSULE'), findsOneWidget);
      expect(find.text('HUD'), findsNothing);
    },
  );

  testWidgets(
    'instrument column shows lap time and Delta, not pause or lap list',
    (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var details = 0;
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
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
    },
  );

  testWidgets('auto-pause banner appears only while paused', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
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
      ),
    );
    expect(find.byKey(const Key('track-landscape-pause')), findsOneWidget);
    expect(find.textContaining('已自动暂停'), findsOneWidget);
  });

  testWidgets('赛道横屏保留 58/42 分栏并在地图上悬浮 GPS 与赛道名', (tester) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackLandscapeSplit(
            map: SizedBox(key: Key('split-map')),
            instruments: SizedBox(key: Key('split-instruments')),
            mapOverlay: TrackLandscapeStatusOverlay(
              trackName: '测试卡丁场',
              gpsBadge: GpsSourceBadge(
                key: Key('landscape-gps-badge'),
                externalActive: true,
                hz: 25,
                satelliteCount: 18,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('split-map'))).width, 580);
    expect(
      tester.getSize(find.byKey(const Key('split-instruments'))).width,
      420,
    );
    expect(
      find.byKey(const Key('track-landscape-status-overlay')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('landscape-gps-badge')), findsOneWidget);
    expect(find.text('测试卡丁场'), findsOneWidget);
    expect(find.byKey(const Key('track-landscape-gps-pill')), findsOneWidget);
    final gpsTop = tester
        .getTopLeft(find.byKey(const Key('landscape-gps-badge')))
        .dy;
    expect(gpsTop, lessThan(52));
  });

  testWidgets('赛道横屏全图仍保留悬浮 GPS，不显示仪表列', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackLandscapeSplit(
            fullMap: true,
            map: SizedBox.expand(),
            instruments: Text('不应显示的仪表'),
            mapOverlay: TrackLandscapeStatusOverlay(
              trackName: '测试卡丁场',
              gpsBadge: GpsSourceBadge(externalActive: true),
            ),
            fullMapOverlay: TrackLandscapeMapCapsules(
              currentLapNumber: 1,
              currentLapMs: 60000,
              timerPaused: false,
              timerLive: false,
              liveDeltaMs: null,
              showDelta: false,
              topPadding: 60,
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('track-landscape-status-overlay')),
      findsOneWidget,
    );
    expect(find.text('第 1 圈'), findsOneWidget);
    expect(tester.getTopLeft(find.text('第 1 圈')).dy, greaterThanOrEqualTo(52));
    expect(find.text('不应显示的仪表'), findsNothing);
  });

  testWidgets('空状态文本时地图不保留整条黑色状态栏', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecordingMapPage(
            isTrack: true,
            centerline: [GeoPoint(31, 121), GeoPoint(31.001, 121.001)],
            start: GeoPoint(31, 121),
            finish: GeoPoint(31, 121),
            sectorPoints: [],
            trail: [GeoPoint(31, 121), GeoPoint(31.001, 121.001)],
            curLat: 31,
            curLon: 121,
            curHeading: 0,
            statusLine: '',
          ),
        ),
      ),
    );
    final legacyBar = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.color == const Color(0xFF111111) &&
          widget.padding ==
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(legacyBar, findsNothing);
  });

  group('赛道横屏沉浸式系统栏', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
              calls.add(call);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    String modeOf(MethodCall call) {
      final arguments = call.arguments;
      return arguments is Map
          ? arguments['mode'] as String
          : arguments as String;
    }

    testWidgets('仅激活时进入沉浸，重复重建不重复调用，退出即恢复', (tester) async {
      Widget host(bool active) => MaterialApp(
        home: TrackLandscapeImmersive(
          active: active,
          child: const SizedBox.expand(),
        ),
      );

      await tester.pumpWidget(host(false));
      expect(calls, isEmpty, reason: '街道或竖屏不应改写系统栏');

      await tester.pumpWidget(host(true));
      await tester.pumpWidget(host(true));
      expect(calls, hasLength(1));
      expect(calls.single.method, 'SystemChrome.setEnabledSystemUIMode');
      expect(modeOf(calls.single), 'SystemUiMode.immersiveSticky');

      await tester.pumpWidget(host(false));
      expect(calls, hasLength(2));
      expect(modeOf(calls.last), 'SystemUiMode.edgeToEdge');
    });

    testWidgets('记录页在沉浸状态被移除时恢复原系统 UI', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TrackLandscapeImmersive(active: true, child: SizedBox.expand()),
        ),
      );
      expect(calls, hasLength(1));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
      expect(calls, hasLength(2));
      expect(modeOf(calls.last), 'SystemUiMode.edgeToEdge');
    });
  });
}
