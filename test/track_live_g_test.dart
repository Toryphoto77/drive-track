/// 赛道面板实时 G 值行单测：G 圆 + 纵向/横向数值 + 本节峰值。
///
/// 锚点：
/// - 数值带正负号（纵向 +加速 / -刹车，横向 +右 / -左），两位小数；
/// - 只订阅数据源的 Listenable 刷新 G 值行（改值 + notify 后 pump
///   即更新，不需要重建父级）；
/// - 未标定时只显示“未标定”，不编数字；
/// - 峰值回调不传时峰值行不显示；超量程（±3g）不抛错；
/// - 面板不传 liveGSource 时 G 值行整行不存在（老调用方不受影响）；
/// - Recorder.onSensor 解析原生透传的 gx/gy/gz（无陀螺仪字段时
///   保持旧值，向后兼容）。

import 'package:drive_track/recorder.dart';
import 'package:drive_track/track_live_g.dart';
import 'package:drive_track/track_session_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSignedG', () {
    test('正显 +，负显 -，保留两位小数', () {
      expect(formatSignedG(0.423), '+0.42');
      // -0.155 的二进制浮点实际略小于 0.155，toStringAsFixed 会出
      // '-0.15'，故用 -0.156 测负向进位，避免二进制边界误判。
      expect(formatSignedG(-0.156), '-0.16');
      expect(formatSignedG(0), '+0.00');
    });
  });

  group('TrackLiveGRow', () {
    late ChangeNotifier notifier;
    late double lo, la, pLo, pLa;
    late bool cal;
    late LiveGSource source;

    setUp(() {
      notifier = ChangeNotifier();
      lo = 0.42;
      la = -0.15;
      pLo = 1.05;
      pLa = -0.87;
      cal = true;
      source = LiveGSource(
        listenable: notifier,
        longG: () => lo,
        latG: () => la,
        calibrated: () => cal,
        peakLong: () => pLo,
        peakLat: () => pLa,
      );
    });

    testWidgets('显示 G 圆 + 纵向/横向数值 + 峰值', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.byType(TrackGVectorCircle), findsOneWidget);
      expect(find.text('+0.42g'), findsOneWidget);
      expect(find.text('-0.15g'), findsOneWidget);
      expect(find.textContaining('峰值'), findsOneWidget);
      expect(find.textContaining('+1.05g'), findsOneWidget);
      expect(find.textContaining('-0.87g'), findsOneWidget);
    });

    testWidgets('数据源通知后只刷新 G 值行（改值 + notify 即更新）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.text('+0.42g'), findsOneWidget);
      lo = -0.63;
      la = 0.91;
      notifier.notifyListeners();
      await tester.pump();
      expect(find.text('-0.63g'), findsOneWidget);
      expect(find.text('+0.91g'), findsOneWidget);
      expect(find.text('+0.42g'), findsNothing);
    });

    testWidgets('未标定时只显示“未标定”，不编数字', (tester) async {
      cal = false;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.text('G 值：未标定'), findsOneWidget);
      expect(find.byType(TrackGVectorCircle), findsNothing);
      expect(find.text('+0.42g'), findsNothing);
    });

    testWidgets('峰值回调不传时峰值行不显示', (tester) async {
      source = LiveGSource(
        listenable: notifier,
        longG: () => lo,
        latG: () => la,
        calibrated: () => cal,
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.textContaining('峰值'), findsNothing);
      expect(find.text('+0.42g'), findsOneWidget);
    });

    testWidgets('拖尾点不抛错，仍画出 G 圆', (tester) async {
      source = LiveGSource(
        listenable: notifier,
        longG: () => lo,
        latG: () => la,
        calibrated: () => cal,
        peakLong: () => pLo,
        peakLat: () => pLa,
        trail: () => const [
          (longG: 0.1, latG: -0.1),
          (longG: 0.4, latG: -0.2),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.byType(TrackGVectorCircle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超量程 ±3g 不抛错（圆点钳制在圆边上）', (tester) async {
      lo = 3.0;
      la = -3.0;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TrackLiveGRow(source: source))),
      );
      expect(find.text('+3.00g'), findsOneWidget);
      expect(find.text('-3.00g'), findsOneWidget);
    });
  });

  group('TrackGCross', () {
    testWidgets('未标定只显示未标定，不画十字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrackGCross(longG: 0.4, latG: -0.2, calibrated: false),
        ),
      ));
      expect(find.text('G 值：未标定'), findsOneWidget);
      expect(find.byKey(const Key('g-cross-plot')), findsNothing);
      expect(find.textContaining('+0.40'), findsNothing);
    });

    testWidgets('已标定显示纵向横向和峰值', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TrackGCross(
            longG: 0.42,
            latG: -0.15,
            peakLong: 1.05,
            peakLat: -0.87,
            calibrated: true,
          ),
        ),
      ));
      expect(find.byKey(const Key('g-cross-plot')), findsOneWidget);
      expect(find.textContaining('+0.42'), findsOneWidget);
      expect(find.textContaining('-0.15'), findsOneWidget);
      expect(find.textContaining('峰值'), findsOneWidget);
    });
  });

  group('TrackSessionDisplay liveGSource 接线', () {
    testWidgets('传 liveGSource 显示 G 值行，不传则整行不存在',
        (tester) async {
      final notifier = ChangeNotifier();
      final source = LiveGSource(
        listenable: notifier,
        longG: () => 0.10,
        latG: () => 0.20,
        calibrated: () => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 1,
              currentLapMs: 61234,
              sectorDeltasMs: const [],
              bestLapMs: null,
              predictedLapMs: null,
              liveGSource: source,
            ),
          ),
        ),
      );
      expect(find.byType(TrackLiveGRow), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrackSessionDisplay(
              currentLapNumber: 1,
              currentLapMs: 61234,
              sectorDeltasMs: [],
              bestLapMs: null,
              predictedLapMs: null,
            ),
          ),
        ),
      );
      expect(find.byType(TrackLiveGRow), findsNothing);
    });
  });

  group('Recorder 陀螺仪透传', () {
    test('onSensor 存 gx/gy/gz；无字段时保持旧值', () {
      final rec = Recorder();
      rec.onSensor(<String, dynamic>{
        'ax': 0.0,
        'ay': 0.0,
        'az': 0.0,
        'rv': <double>[],
        'gx': 0.1,
        'gy': -0.2,
        'gz': 0.3,
      });
      expect(rec.curGyroX, 0.1);
      expect(rec.curGyroY, -0.2);
      expect(rec.curGyroZ, 0.3);
      // 老版本原生不发陀螺仪字段：保持旧值，不清零、不抛错。
      rec.onSensor(<String, dynamic>{
        'ax': 0.0,
        'ay': 0.0,
        'az': 0.0,
        'rv': <double>[],
      });
      expect(rec.curGyroX, 0.1);
      expect(rec.curGyroY, -0.2);
      expect(rec.curGyroZ, 0.3);
    });
  });
}
