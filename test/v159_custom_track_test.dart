import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drive_track/blediy_gps.dart';
import 'package:drive_track/kart_prep_page.dart';
import 'package:drive_track/models.dart';
import 'package:drive_track/track_creation.dart';
import 'package:drive_track/track_creation_page.dart';
import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_package_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint _point(int index, double lat, double lon) => TrackPoint(
  timeMs: 1000 + index * 1000,
  lat: lat,
  lon: lon,
  alt: 500,
  speed: 8,
  bearing: 90,
  hAcc: 0,
  vAcc: 0,
  speedAcc: 0,
  provider: 'external',
  longG: 0,
  latG: 0,
  vertG: 0,
  pitch: 0,
  roll: 0,
  heading: 90,
  pressureHpa: 0,
  calibrated: false,
  altValid: true,
  locSource: 'external',
);

List<TrackPoint> _closedLoop(int count, {double radiusM = 120}) {
  const centerLat = 31.2304;
  const centerLon = 121.4737;
  return [
    for (var i = 0; i < count; i++)
      _point(
        i,
        centerLat + radiusM / 110540 * math.sin(i * 2 * math.pi / (count - 1)),
        centerLon +
            radiusM /
                (111320 * math.cos(centerLat * math.pi / 180)) *
                math.cos(i * 2 * math.pi / (count - 1)),
      ),
  ];
}

void main() {
  group('3D 定位与卡丁赛道门槛', () {
    test('只有新鲜、有效的 3D 外接定位可用于建赛', () {
      const fix = ExternalGpsFix(lat: 31.23, lon: 121.47, fixMode: 3);
      expect(external3DFixReady(fix, 9000, nowMs: 10000), isTrue);
      expect(
        external3DFixReady(
          const ExternalGpsFix(lat: 31.23, lon: 121.47, fixMode: 2),
          9000,
          nowMs: 10000,
        ),
        isFalse,
      );
      expect(external3DFixReady(fix, 5000, nowMs: 10000), isFalse);
      expect(external3DFixReady(null, 9000, nowMs: 10000), isFalse);
    });

    test('自研硬件 NDJSON 定位带 fixMode=3，可用于现场实测', () {
      // 自研固件不发 GSA（GSA/GSV 已在模块侧关闭），fixMode 只能来自
      // 私有协议；此前一律为 null，导致已连接硬件仍点不了“开始 3D 定位实测”。
      final feed = BleDiyGpsFeed();
      final fix = feed.feedLine(
        '{"t":"gps","fix":1,"sats":18,"lat":31.2304,"lon":121.4737,'
        '"alt":12.5,"spd":0.0,"cog":0.0,"hdop":0.8,"ts":12345678}',
      );
      expect(fix, isNotNull);
      expect(fix!.fixMode, 3);
      expect(fix.fixQuality, isNotNull);
      expect(fix.deviceTsUs, 12345678);
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(external3DFixReady(fix, now), isTrue);
    });

    test('NDJSON 无定位时不得伪造 3D', () {
      final feed = BleDiyGpsFeed();
      final fix = feed.feedLine(
        '{"t":"gps","fix":0,"sats":3,"lat":0,"lon":0,"alt":0}',
      );
      expect(fix, isNull);
      expect(external3DFixReady(feed.latest, 0), isFalse);
    });

    test('NDJSON 模式下忽略并行 NMEA，避免频率与轨迹翻倍', () {
      final feed = BleDiyGpsFeed();
      final fix = feed.feedLine(
        '{"t":"gps","fix":1,"sats":18,"lat":31.2304,"lon":121.4737,'
        '"alt":12.5,"spd":0,"cog":0,"hdop":0.8}',
      );
      expect(fix, isNotNull);
      final accepted = feed.acceptedCount;
      final ignored = feed.feedLine(
        r'$GNGGA,100000.00,3113.8240,N,12128.4220,E,1,18,0.8,12.5,M,0.0,M,,*4C',
      );
      expect(ignored, same(fix));
      expect(feed.acceptedCount, accepted);
    });

    test('卡丁必须选择同时有中心线和起终点的赛道', () {
      expect(kartTrackProblem(null), isNotNull);
      expect(
        kartTrackProblem(
          const TrackPackage(
            id: 'x',
            nameCn: 'X',
            nameEn: '',
            region: '测试',
            version: 1,
            source: TrackPackageSource.user,
            verification: TrackPackageVerification.pending,
            centerline: [
              GeoPoint(31, 121),
              GeoPoint(31.001, 121.001),
              GeoPoint(31, 121),
            ],
          ),
        ),
        isNotNull,
      );
      expect(
        kartTrackProblem(
          const TrackPackage(
            id: 'x',
            nameCn: 'X',
            nameEn: '',
            region: '测试',
            version: 1,
            source: TrackPackageSource.user,
            verification: TrackPackageVerification.pending,
            centerline: [
              GeoPoint(31, 121),
              GeoPoint(31.001, 121.001),
              GeoPoint(31, 121),
            ],
            start: GeoPoint(31, 121),
            finish: GeoPoint(31, 121),
          ),
        ),
        isNull,
      );
    });
  });

  group('双路径自定义赛道', () {
    test('实测轨迹拒绝点数不足、过短和未闭合', () {
      expect(measuredTrackProblem(_closedLoop(12)), contains('30'));
      expect(
        measuredTrackProblem(_closedLoop(32, radiusM: 5)),
        contains('100'),
      );
      final open = _closedLoop(32).sublist(0, 28);
      expect(measuredTrackProblem(open), isNotNull);
      expect(measuredTrackProblem(_closedLoop(32)), isNull);
    });

    test('实测轨迹生成闭合用户赛道和真实起终点', () {
      final pkg = measuredTrackPackage(
        id: 'user_test_loop',
        name: '测试卡丁场',
        points: _closedLoop(40),
      );
      expect(pkg.id, 'user_test_loop');
      expect(pkg.nameCn, '测试卡丁场');
      expect(pkg.isUserTrack, isTrue);
      expect(pkg.source, TrackPackageSource.measured);
      expect(pkg.centerline.first.lat, closeTo(pkg.centerline.last.lat, 1e-9));
      expect(pkg.start, isNotNull);
      expect(pkg.hasCenterline, isTrue);
      expect(kartTrackProblem(pkg), isNull);
    });

    test('卫星绘制从真实定位锚点创建空用户包', () {
      const anchor = GeoPoint(31.2304, 121.4737);
      final pkg = emptyTrackPackageAt(
        id: 'user_draw',
        name: '手绘赛道',
        anchor: anchor,
      );
      expect(pkg.isUserTrack, isTrue);
      expect(pkg.centerline, isEmpty);
      expect(pkg.start, isNull);
      expect(pkg.verification, TrackPackageVerification.pending);
      expect(pkg.sourceDetail, contains('卫星'));
    });

    testWidgets('空包编辑器用定位锚点建视口并默认开卫星图', (tester) async {
      const anchor = GeoPoint(31.2304, 121.4737);
      final pkg = emptyTrackPackageAt(
        id: 'user_draw',
        name: '手绘赛道',
        anchor: anchor,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrackPackageEditorPage(
            package: pkg,
            initialCenter: anchor,
            initialSatelliteOn: true,
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('影像 © Esri World Imagery'), findsWidgets);
    });

    testWidgets('建赛页提供两种方式，3D 定位后才允许开始', (tester) async {
      final controller = StreamController<ExternalGpsFix>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomTrackCreatePage(
            initialMethod: CustomTrackMethod.measured,
            fixStream: controller.stream,
          ),
        ),
      );
      expect(find.text('现场 3D 实测'), findsOneWidget);
      expect(find.text('卫星图手动绘制'), findsOneWidget);
      final start = find.byKey(const ValueKey('start-track-measure'));
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      controller.add(
        const ExternalGpsFix(lat: 31.2304, lon: 121.4737, fixMode: 3),
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    });

    testWidgets('卡丁准备页显示当前赛道并提供两个建赛入口', (tester) async {
      var measured = 0;
      var satellite = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: KartPrepPage(
            selectedTrackName: '测试卡丁场',
            onPickTrack: () {},
            onConnectDevice: () {},
            onCreateMeasuredTrack: () => measured++,
            onCreateSatelliteTrack: () => satellite++,
          ),
        ),
      );
      expect(find.textContaining('测试卡丁场'), findsWidgets);
      await tester.tap(find.text('3D 定位实测建赛'));
      await tester.tap(find.text('卫星图手动建赛'));
      expect(measured, 1);
      expect(satellite, 1);
    });
  });

  group('主框架建赛与开录接线', () {
    final source = File('lib/main.dart').readAsStringSync();

    test('BLE 与 SPP 共用广播定位流并同步 GSA 模式', () {
      expect(source, contains('_externalFixController.add(fix)'));
      expect(source, contains('fixStream: _externalFixController.stream'));
      expect(source, contains('fixMode: _blediyFeed.latest?.fixMode'));
    });

    test('开录前（安全确认与倒计时后）都校验赛道就绪', () {
      // v1.6.0：_requireKartTrack → _requireTrackReady，汽车/摩托没选赛道时
      // 也走“实录建赛道 / 卫星图绘制 / 选已有”引导层，不再静默进街道页。
      expect(source, contains('_requireTrackReady(mode)'));
      expect(
        RegExp(r'_requireTrackReady\(mode\)').allMatches(source).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('自定义赛道统一进编辑器，保存后写库并自动选中', () {
      expect(
        source,
        contains('_openCustomTrackCreator(CustomTrackMethod method)'),
      );
      expect(source, contains('TrackPackageEditorPage('));
      expect(source, contains('TrackLibraryService.instance.savePackage(pkg)'));
      expect(source, contains('selectedTrack = trackInfoForPackage(pkg)'));
      expect(source, contains('selectedPackage = pkg'));
    });
  });
}
