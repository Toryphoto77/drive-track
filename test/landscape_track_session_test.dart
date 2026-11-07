/// 横屏赛道面板测试（不依赖 main.dart，可独立运行）。
///
/// 赛道面板 TrackSessionDisplay 在横屏左栏宽度（440 与最窄 340）
/// 下不溢出：大计时 FittedBox、G 值行、分段行、目标行、段速行
/// 均完整渲染。整 App 横屏冒烟见 landscape_layout_test.dart
///（目前被另一子代理的 lib/app_bar_style.dart 编译错误拦住，
/// 见该文件；本文件不受影响）。

import 'package:drive_track/track_live_g.dart';
import 'package:drive_track/track_session_display.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('横屏 800x360 赛道面板', () {
    testWidgets('左栏 440 宽下不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: _landscapeTrackPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('当前圈'), findsOneWidget);
      expect(find.textContaining('实时 Delta'), findsOneWidget);
      expect(find.text('+0.42g'), findsOneWidget);
      expect(find.text('S1'), findsOneWidget);
      expect(find.text('预测圈'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('最窄左栏 340 宽下不溢出', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 340,
                child: _landscapeTrackPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('当前圈'), findsOneWidget);
      expect(find.textContaining('实时 Delta'), findsOneWidget);
      expect(find.text('+0.42g'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 横屏左栏里的赛道页内容：职业面板 + 段速行（与 main.dart
/// 记录页赛道页第 0 页的组装一致，只是数据用固定值）。
Widget _landscapeTrackPanel() {
  final notifier = ChangeNotifier();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TrackSessionDisplay(
        currentLapNumber: 3,
        currentLapMs: 95432,
        sectorDeltasMs: const [-320, 150, null],
        sectorTimesMs: const [25123, 33456],
        currentSectorIndex: 2,
        liveDeltaMs: -170,
        sectorLabels: const ['S1', 'S2', 'S3'],
        bestLapMs: 93200,
        predictedLapMs: 93030,
        optimalLapMs: 92100,
        isPaused: false,
        timerLive: false,
        timerPaused: false,
        liveGSource: LiveGSource(
          listenable: notifier,
          longG: () => 0.42,
          latG: () => -0.15,
          calibrated: () => true,
          peakLong: () => 1.05,
          peakLat: () => -0.87,
        ),
      ),
      const SizedBox(height: 12),
      const TrackSectorSpeedRow(
        sectorSpeeds: [
          SectorSpeed(62, 187),
          SectorSpeed(45, 132),
          null,
        ],
        sectorLabels: ['S1', 'S2', 'S3'],
        hasSectorPoints: true,
        nextLineDistanceM: 123,
      ),
    ],
  );
}
