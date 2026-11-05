/// 赛道库顶部版本卡片（截图样式）测试。
///
/// 背景：TrackLibraryPage 在 initState 里调 TrackLibraryService.loadAll，
/// 其 _loadLocal 走 dart:io（File.exists）。实测 widget 测试的 FakeAsync
/// 环境下，由 widget 生命周期触发的 dart:io Future 永不完成（最小复现：
/// 仅含 Directory.createTemp 的 testWidgets 即挂起；同逻辑的普通 test
/// 则通过；runAsync 也救不回已在 FakeAsync 区创建的 Future）。因此本文件
/// 不整页泵 TrackLibraryPage，改为两层覆盖：
/// ① 直接泵纯渲染的 LibraryVersionCard（不碰服务与磁盘）：版本显示、
/// 三态文案、按钮置灰/可用与回调转发；
/// ② 单测纯逻辑 VersionTapGate：2 秒内连点 7 次解锁。
/// 页面接线（卡片 onVersionTap → _onVersionTap → gate → 策展态）为三行
/// 直连代码，与旧版逐行一致，已人工核对。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_library_page.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required String dataVersion,
    UpdateCheckResult? check,
    bool checking = false,
    bool applying = false,
    VoidCallback? onVersionTap,
    VoidCallback? onCheck,
    VoidCallback? onUpdateAll,
    VoidCallback? onImport,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LibraryVersionCard(
              dataVersion: dataVersion,
              check: check,
              checking: checking,
              applying: applying,
              onVersionTap: onVersionTap ?? () {},
              onCheck: onCheck ?? () {},
              onUpdateAll: onUpdateAll ?? () {},
              onImport: onImport ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  UpdateCheckResult upToDateCheck() => UpdateCheckResult(
    status: UpdateCheckStatus.upToDate,
    message: '赛道库已是最新版本',
    updates: const [],
    remoteDataVersion: 'V1.0.1',
    skippedUserModified: const [],
  );

  UpdateCheckResult availableCheck() => UpdateCheckResult(
    status: UpdateCheckStatus.available,
    message: '1 个包可更新',
    updates: const [
      PackageUpdate(
        id: 'shanghai',
        nameCn: '上海国际赛车场',
        localVersion: 1,
        remoteVersion: 99,
        url: 'https://example.invalid/shanghai.json',
      ),
    ],
    remoteDataVersion: 'V1.0.2',
    skippedUserModified: const [],
  );

  UpdateCheckResult errorCheck() => UpdateCheckResult(
    status: UpdateCheckStatus.error,
    message: '网络不通：两个更新源都连不上，请检查网络或代理后重试',
    updates: const [],
    remoteDataVersion: '',
    skippedUserModified: const [],
  );

  testWidgets('初始版式：标题 + 真实版本 + 未检查状态 + 更新按钮置灰', (tester) async {
    await pumpCard(tester, dataVersion: 'V1.0.1');
    // 标题仍为“赛道库”，不改成截图的“支持赛道”。
    expect(find.text('赛道库'), findsOneWidget);
    // 真实数据总版本取打包 manifest 的 dataVersion（当前 V1.0.1），
    // 绝不是截图里对方 App 的 2026.11.02.2。
    expect(find.text('当前版本：V1.0.1'), findsOneWidget);
    expect(find.text('尚未检测'), findsOneWidget);
    final checkButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '赛道库版本检测'),
    );
    expect(checkButton.onPressed, isNotNull);
    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新赛道库'),
    );
    expect(updateButton.onPressed, isNull);
    // 从行程导入原样保留。
    expect(find.text('从行程导入'), findsOneWidget);
  });

  testWidgets('已是最新：绿点文案 + 更新按钮仍置灰', (tester) async {
    await pumpCard(tester, dataVersion: 'V1.0.1', check: upToDateCheck());
    expect(find.text('赛道库已是最新版本'), findsOneWidget);
    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新赛道库'),
    );
    expect(updateButton.onPressed, isNull);
  });

  testWidgets('有更新：包数文案 + 更新按钮可用 + 点按走回调', (tester) async {
    var updateTapped = false;
    await pumpCard(
      tester,
      dataVersion: 'V1.0.1',
      check: availableCheck(),
      onUpdateAll: () => updateTapped = true,
    );
    expect(find.text('1 个包可更新'), findsOneWidget);
    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新赛道库'),
    );
    expect(updateButton.onPressed, isNotNull);
    await tester.tap(find.text('更新赛道库'));
    expect(updateTapped, isTrue);
  });

  testWidgets('检查失败：显示错误原文 + 更新按钮置灰', (tester) async {
    await pumpCard(tester, dataVersion: 'V1.0.1', check: errorCheck());
    expect(find.text('网络不通：两个更新源都连不上，请检查网络或代理后重试'), findsOneWidget);
    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新赛道库'),
    );
    expect(updateButton.onPressed, isNull);
  });

  testWidgets('检测中与更新中：按钮置灰并改文案', (tester) async {
    await pumpCard(
      tester,
      dataVersion: 'V1.0.1',
      check: availableCheck(),
      checking: true,
    );
    expect(find.text('正在检测…'), findsOneWidget);
    expect(find.text('检测中…'), findsOneWidget);
    final updateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新赛道库'),
    );
    expect(updateButton.onPressed, isNull);

    await pumpCard(
      tester,
      dataVersion: 'V1.0.1',
      check: availableCheck(),
      applying: true,
    );
    expect(find.text('更新中…'), findsOneWidget);
    final updateButton2 = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '更新中…'),
    );
    expect(updateButton2.onPressed, isNull);
  });

  testWidgets('版本文本点按转发给 onVersionTap（策展 gate 的入口）', (tester) async {
    var taps = 0;
    await pumpCard(tester, dataVersion: 'V1.0.1', onVersionTap: () => taps++);
    await tester.tap(find.text('当前版本：V1.0.1'));
    expect(taps, 1);
  });

  testWidgets('检测按钮点按转发给 onCheck', (tester) async {
    var tapped = false;
    await pumpCard(tester, dataVersion: 'V1.0.1', onCheck: () => tapped = true);
    await tester.tap(find.text('赛道库版本检测'));
    expect(tapped, isTrue);
  });

  group('VersionTapGate（2 秒内连点 7 次解锁）', () {
    test('7 次快速连点：第 7 次解锁，前 6 次不解锁', () {
      final gate = VersionTapGate();
      final t = DateTime(2026, 11, 5, 7, 0, 0);
      for (var i = 0; i < 6; i++) {
        expect(gate.tap(now: t.add(Duration(milliseconds: i * 100))), isFalse);
      }
      expect(gate.tap(now: t.add(const Duration(milliseconds: 700))), isTrue);
    });

    test('6 次连点不解锁', () {
      final gate = VersionTapGate();
      final t = DateTime(2026, 11, 5, 7, 0, 0);
      for (var i = 0; i < 6; i++) {
        expect(gate.tap(now: t.add(Duration(milliseconds: i * 100))), isFalse);
      }
    });

    test('间隔超过 2 秒则计数重置，不解锁', () {
      final gate = VersionTapGate();
      final t = DateTime(2026, 11, 5, 7, 0, 0);
      expect(gate.tap(now: t), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 3))), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 6))), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 9))), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 12))), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 15))), isFalse);
      expect(gate.tap(now: t.add(const Duration(seconds: 18))), isFalse);
    });
  });
}
