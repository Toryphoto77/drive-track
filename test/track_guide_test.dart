import 'package:drive_track/track_encyclopedia.dart';
import 'package:drive_track/track_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1.1.0 encyclopedia still has 21 tracks', () {
    expect(encyclopediaTracks.length, 21);
    expect(
      encyclopediaTracks.map((t) => t.id).toSet().length,
      21,
      reason: 'track ids must be unique',
    );
  });

  test('v1.1.0 all 21 tracks have a guide entry', () {
    expect(trackGuides.length, 21);
    for (final t in encyclopediaTracks) {
      expect(trackGuides.containsKey(t.id), isTrue, reason: t.id);
    }
  });

  test('v1.1.0 OSM outlines are the 3 verified circuit relations', () {
    expect(trackOsmOutlines.keys.toSet(), {'monaco', 'sepang', 'bathurst'});
  });

  test('v1.1.0 new 7 tracks have a guide with history and sources', () {
    for (final id in [
      'chengdu_tianfu',
      'goldenport',
      'guangdong_gic',
      'monaco',
      'le_mans',
      'sepang',
      'bathurst',
    ]) {
      final t = encyclopediaTrackById(id);
      expect(t, isNotNull, reason: id);
      final g = guideFor(t!);
      expect(g.historyParagraphs, isNotEmpty, reason: id);
      expect(g.historyParagraphs.first, isNot('历史资料：待核'), reason: id);
      expect(g.sources, isNotEmpty, reason: id);
    }
  });

  test('v1.1.0 lap records, when present, are complete and plausible', () {
    for (final entry in trackGuides.entries) {
      final r = entry.value.lapRecord;
      if (r == null) continue;
      expect(r.series, isNotEmpty, reason: entry.key);
      expect(r.driver, isNotEmpty, reason: entry.key);
      expect(r.car, isNotEmpty, reason: entry.key);
      expect(r.lapTime, isNotEmpty, reason: entry.key);
      expect(r.year, greaterThanOrEqualTo(1923));
      expect(r.year, lessThanOrEqualTo(2026));
    }
    for (final entry in trackGuides.entries) {
      for (final e in entry.value.events) {
        expect(e.year, greaterThanOrEqualTo(1900));
        expect(e.year, lessThanOrEqualTo(2026));
        expect(e.event, isNotEmpty);
      }
    }
  });

  test('v1.1.0 OSM outlines, when present, are normalized', () {
    for (final entry in trackOsmOutlines.entries) {
      expect(entry.value.length, greaterThanOrEqualTo(3), reason: entry.key);
      for (final p in entry.value) {
        expect(p.x, greaterThanOrEqualTo(0.0));
        expect(p.x, lessThanOrEqualTo(1.0));
        expect(p.y, greaterThanOrEqualTo(0.0));
        expect(p.y, lessThanOrEqualTo(1.0));
      }
    }
  });

  testWidgets('v1.1.0 encyclopedia list opens detail page', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
        ),
        home: const TrackEncyclopediaPage(),
      ),
    );
    await tester.pump();
    expect(find.text('赛道图鉴'), findsOneWidget);
    expect(find.text('摩纳哥赛道'), findsOneWidget);
    await tester.tap(find.text('摩纳哥赛道').first);
    await tester.pumpAndSettle();
    expect(find.text('历史资料'), findsOneWidget);
    expect(find.text('最快圈速'), findsOneWidget);
    expect(find.text('办赛历史'), findsOneWidget);
    expect(find.text('1:12.909'), findsOneWidget);
  });
}
