// 视频同步页：无分圈行程进入后，预览区不得渲染“纯灰空占位”。
//
// 覆盖 Dart 侧占位 / 状态逻辑（原生 AndroidView 在 widget 测试里不会真实
// 渲染，因此不测原生首帧，只锁 Dart 层：缺视频给明确文案 + 重导入口，
// 有视频给首帧缩略图 / 播放占位，背景始终是深色而不是浅灰）。
import 'dart:io';

import 'package:drive_track/models.dart';
import 'package:drive_track/store.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:drive_track/video_hud_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _FakeStore extends Store {
  final Trip trip;
  _FakeStore(this.trip);

  @override
  Future<Trip?> loadTrip(String id) async => trip;

  @override
  Future<List<TripMeta>> loadIndex() async => [];
}

/// 预览区出现“纯灰空占位”的判定：任何 ColoredBox 涂了中浅灰
/// （RGB 近似相等且亮度落在灰屏区间）。修复后占位背景是深色
/// （0xFF151515 / 0xFF0B0B0C），不会命中。
bool _hasLightGreyBox(WidgetTester tester) {
  for (final el in find.byType(ColoredBox).evaluate()) {
    final v = (el.widget as ColoredBox).color.toARGB32();
    final r = (v >> 16) & 0xFF;
    final g = (v >> 8) & 0xFF;
    final b = v & 0xFF;
    if ((r - g).abs() <= 4 && (g - b).abs() <= 4 && r >= 120 && r <= 220) {
      return true;
    }
  }
  return false;
}

Future<void> _pumpPage(WidgetTester tester, Trip trip) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.physicalSize = const Size(390, 844);
  // mock 原生通道：VideoHudPage 初始化会调 Native.videoThumbnails 抽帧，
  // 测试环境没有原生实现，不 mock 的话调用会挂起导致 flutter_tester 不退出。
  const channel = MethodChannel('drivetrack/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'videoThumbnails') return <String>[];
    if (call.method == 'getCacheDir' || call.method == 'getFilesDir') {
      return Directory.systemTemp.path;
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(
    MaterialApp(
      theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
      home: VideoHudPage(trip: trip, store: _FakeStore(trip)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '无分圈 + 视频文件缺失：显示明确占位文案，不渲染纯灰空框',
    (tester) async {
      final trip = Trip(
        id: 'trip-no-lap-missing-video',
        mode: TripMode.car,
        startMs: 1000000,
        endMs: 1019000,
        points: _points(),
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
        // 路径不存在：模拟文件被移动 / 重命名后路径失效。
        videoPaths: const ['/data/does-not-exist/trip_1000000.mp4'],
        // lapsJson 留空 → 无分圈。
      );

      await _pumpPage(tester, trip);

      // 底部明确提示没有分圈（证明走的是无分圈分支）。
      expect(find.text('本次行程没有分圈'), findsOneWidget);
      // 预览区给出明确原因 + 重新导入入口，而不是一块静默灰底。
      expect(find.text('视频文件不存在或已被移动'), findsOneWidget);
      expect(find.text('重新导入视频'), findsOneWidget);
      // 整页没有中浅灰的 ColoredBox 占位。
      expect(_hasLightGreyBox(tester), isFalse);
      expect(tester.takeException(), isNull);
      // 释放页面，取消 initState 里的轮询 Timer，避免测试进程挂起。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    '无分圈 + 视频文件存在：预览区有可见内容，不渲染纯灰空框',
    (tester) async {
      // 用仓库里已存在的文件模拟“磁盘上有这段视频”，避免临时文件 I/O 干扰。
      final existingFile = File('${Directory.current.path}/pubspec.yaml');
      expect(existingFile.existsSync(), isTrue);

      final trip = Trip(
        id: 'trip-no-lap-existing-video',
        mode: TripMode.car,
        startMs: 1000000,
        endMs: 1019000,
        points: _points(),
        events: const [],
        score: 90,
        subScores: const {},
        scoreReasons: const [],
        videoPaths: [existingFile.path],
      );

      await _pumpPage(tester, trip);

      expect(find.text('本次行程没有分圈'), findsOneWidget);
      // 非 Android 测试宿主没有平台视图，走播放占位（可见内容），
      // 真机上则由原生首帧 / 首帧缩略图 poster 兜底。
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(_hasLightGreyBox(tester), isFalse);
      expect(tester.takeException(), isNull);
      // 释放页面，取消 initState 里的轮询 Timer，避免测试进程挂起。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
