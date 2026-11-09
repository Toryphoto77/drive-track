/// v1.3.5 测试：地图过线后才出现（参考 TrackAddict 实时赛道图过线后才出现）。
///
/// 覆盖：
/// - LapTimer.hasCrossedStartLine：发车圈为假，第一次过线后为真，
///   完圈后仍为真（保持到本节结束）；与“有最佳圈”不是同一个状态
///   （过线后、无最佳圈时已为真）；
/// - 纯函数 showTrackOverlayFor：赛道模式过线前假、过线后真；
///   街道模式恒真（不受门控影响）；
/// - 纯函数 trackMapStatusLine：无计时器“等待定位”；过线前
///   “等待通过起终点线”；过线后为圈标签 + 当前圈用时；
/// - widget：过线前叠加层不画（中心线 / 起终点 / 分段点均不出现，
///   已录轨迹与当前位置箭头仍在）；过线后出现；过线后保持
///   （后续圈数变化不消失）；街道模式不受门控影响；
///   状态行文案“等待通过起终点线”只在过线前出现。
///
/// 不测计时判定本身（越线检测 / 半径法已由 track_timing_crossing_test
/// 覆盖）、不测幽灵车门控（v134 已覆盖，本版不动）。

import 'package:drive_track/amap_service.dart';
import 'package:drive_track/recording_map_page.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _p1 = GeoPoint(31.3380, 121.2180);
const _p2 = GeoPoint(31.3420, 121.2280);
const _p3 = GeoPoint(31.3400, 121.2230);

/// 记录页叠加层以 GCJ-02 交给 painter：期望值同样经 wgsToGcjLocal 算。
GeoPoint _gcj(GeoPoint p) {
  final (la, lo) = wgsToGcjLocal(p.lat, p.lon);
  return GeoPoint(la, lo);
}

/// 半径法回落用点：lat 为南北向米数（赤道附近 1 度纬度 = 110540 m）。
TimedPoint _pt(int timeMs, double northM, [double speed = 30]) =>
    TimedPoint(timeMs: timeMs, lat: northM / 110540, lon: 0, speed: speed);

Future<void> _pumpPage(
  WidgetTester tester,
  RecordingMapPage page,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 360, height: 480, child: page),
        ),
      ),
    ),
  );
}

RecordingMapPainter _overlayPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const ValueKey('recording-map-overlay')),
  );
  return paint.painter as RecordingMapPainter;
}

RecordingMapPage _trackPage({
  required bool showTrackOverlay,
  required String statusLine,
}) =>
    RecordingMapPage(
      isTrack: true,
      centerline: [_p1, _p3, _p2],
      start: _p1,
      finish: _p2,
      sectorPoints: [_p3],
      trail: [_p1, _p3],
      curLat: 31.3400,
      curLon: 121.2230,
      curHeading: 90,
      showTrackOverlay: showTrackOverlay,
      statusLine: statusLine,
    );

void main() {
  group('LapTimer.hasCrossedStartLine', () {
    test('发车圈为假（未喂点 / 未过线时）', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      expect(timer.hasCrossedStartLine, isFalse);
      expect(timer.currentLapNumber, 0);
      timer.addPoint(_pt(0, -100));
      timer.addPoint(_pt(1000, -70));
      expect(timer.hasCrossedStartLine, isFalse);
      expect(timer.currentLapNumber, 0);
    });

    test('第一次过线后为真，且此时尚无最佳圈（与幽灵车门控不同）', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_pt(0, -40));
      timer.addPoint(_pt(1000, 40)); // 一步跨过 30 m 半径圆
      expect(timer.currentLapNumber, 1);
      expect(timer.hasCrossedStartLine, isTrue);
      expect(timer.bestLap, isNull);
    });

    test('完圈后仍为真（保持到本节结束）', () {
      final timer = LapTimer(startFinish: const GeoPoint(0, 0));
      timer.addPoint(_pt(0, 0)); // 落入 30 m 圆，开圈（t=0）
      timer.addPoint(_pt(1000, 500)); // 1 秒内远离，重新获得资格
      expect(timer.hasCrossedStartLine, isTrue);
      timer.addPoint(_pt(62000, 0)); // 再次过线，关圈开第 2 圈
      expect(timer.laps.length, 1);
      expect(timer.currentLapNumber, 2);
      expect(timer.hasCrossedStartLine, isTrue);
    });
  });

  group('showTrackOverlayFor 纯函数', () {
    test('赛道模式：过线前假、过线后真', () {
      expect(
        showTrackOverlayFor(isTrack: true, hasCrossedStartLine: false),
        isFalse,
      );
      expect(
        showTrackOverlayFor(isTrack: true, hasCrossedStartLine: true),
        isTrue,
      );
    });

    test('街道模式：恒真，不受门控影响', () {
      expect(
        showTrackOverlayFor(isTrack: false, hasCrossedStartLine: false),
        isTrue,
      );
      expect(
        showTrackOverlayFor(isTrack: false, hasCrossedStartLine: true),
        isTrue,
      );
    });
  });

  group('trackMapStatusLine 纯函数', () {
    test('无计时器 → 等待定位', () {
      expect(
        trackMapStatusLine(
          hasTimer: false,
          hasCrossedStartLine: false,
          lapLabel: '发车圈',
          currentLapDuration: '00:00',
        ),
        '等待定位',
      );
    });

    test('有计时器、未过线 → 等待通过起终点线', () {
      expect(
        trackMapStatusLine(
          hasTimer: true,
          hasCrossedStartLine: false,
          lapLabel: '发车圈',
          currentLapDuration: '00:10',
        ),
        '等待通过起终点线',
      );
    });

    test('已过线 → 圈标签 + 当前圈用时，不含等待文案', () {
      final line = trackMapStatusLine(
        hasTimer: true,
        hasCrossedStartLine: true,
        lapLabel: '第 2 圈',
        currentLapDuration: '01:23',
      );
      expect(line, '第 2 圈 · 当前圈 01:23');
      expect(line, isNot(contains('等待通过起终点线')));
    });
  });

  group('RecordingMapPage 叠加层显隐', () {
    testWidgets('过线前叠加层不画：中心线 / 起终点 / 分段点均不出现', (tester) async {
      await _pumpPage(
        tester,
        _trackPage(
          showTrackOverlay: false,
          statusLine: '等待通过起终点线',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.centerline, isEmpty);
      expect(painter.start, isNull);
      expect(painter.finish, isNull);
      expect(painter.sectorPoints, isEmpty);
      // 已录轨迹与当前位置箭头仍在。
      expect(painter.trail.length, 2);
      expect(painter.hasValidPosition, isTrue);
      expect(find.textContaining('等待通过起终点线'), findsOneWidget);
    });

    testWidgets('过线后叠加层出现', (tester) async {
      await _pumpPage(
        tester,
        _trackPage(
          showTrackOverlay: true,
          statusLine: '第 1 圈 · 当前圈 00:05',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.centerline.length, 3);
      expect(painter.start!.lat, closeTo(_gcj(_p1).lat, 1e-9));
      expect(painter.start!.lon, closeTo(_gcj(_p1).lon, 1e-9));
      expect(painter.finish!.lat, closeTo(_gcj(_p2).lat, 1e-9));
      expect(painter.finish!.lon, closeTo(_gcj(_p2).lon, 1e-9));
      expect(painter.sectorPoints.length, 1);
      expect(painter.trail.length, 2);
      expect(find.textContaining('第 1 圈 · 当前圈 00:05'), findsOneWidget);
      expect(find.textContaining('等待通过起终点线'), findsNothing);
    });

    testWidgets('过线后保持：后续圈数变化不消失', (tester) async {
      await _pumpPage(
        tester,
        _trackPage(
          showTrackOverlay: true,
          statusLine: '第 1 圈 · 当前圈 00:05',
        ),
      );
      await tester.pumpAndSettle();
      expect(_overlayPainter(tester).centerline.length, 3);
      // 第 3 圈：叠加层仍在，等待文案仍不出现。
      await _pumpPage(
        tester,
        _trackPage(
          showTrackOverlay: true,
          statusLine: '第 3 圈 · 当前圈 01:10',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.centerline.length, 3);
      expect(painter.start!.lat, closeTo(_gcj(_p1).lat, 1e-9));
      expect(painter.start!.lon, closeTo(_gcj(_p1).lon, 1e-9));
      expect(painter.finish!.lat, closeTo(_gcj(_p2).lat, 1e-9));
      expect(painter.finish!.lon, closeTo(_gcj(_p2).lon, 1e-9));
      expect(painter.sectorPoints.length, 1);
      expect(find.textContaining('第 3 圈 · 当前圈 01:10'), findsOneWidget);
      expect(find.textContaining('等待通过起终点线'), findsNothing);
    });

    testWidgets('街道模式不受门控影响：已录轨迹正常显示', (tester) async {
      await _pumpPage(
        tester,
        const RecordingMapPage(
          isTrack: false,
          centerline: [],
          start: null,
          finish: null,
          sectorPoints: [],
          trail: [_p1, _p3, _p2],
          curLat: 31.3420,
          curLon: 121.2280,
          curHeading: 180,
          showTrackOverlay: true,
          statusLine: '用时 05:00 · 里程 3.40 km',
        ),
      );
      await tester.pumpAndSettle();
      final painter = _overlayPainter(tester);
      expect(painter.trail.length, 3);
      expect(painter.hasValidPosition, isTrue);
      expect(find.textContaining('等待通过起终点线'), findsNothing);
    });
  });
}
