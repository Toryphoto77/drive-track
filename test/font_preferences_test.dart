import 'dart:convert';
import 'dart:io';

import 'package:drive_track/main.dart';
import 'package:drive_track/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drive_track_fonts_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('drivetrack/native'), (
          call,
        ) async {
          if (call.method == 'getFilesDir' || call.method == 'getCacheDir') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('drivetrack/native'),
          null,
        );
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('账号 ID 新生成为 8 位数字，旧的超长 ID 自动迁移', () async {
    final fresh = AppPrefs();
    await fresh.load();
    expect(fresh.userId, matches(RegExp(r'^\d{8}$')));

    await File('${tempDir.path}/profile.json').writeAsString(
      jsonEncode({'userId': '1763539200123456'}),
    );
    final migrated = AppPrefs();
    await migrated.load();
    expect(migrated.userId, '00123456');
    expect(migrated.userId.length, 8);
  });

  test('不超过 8 位的纯数字账号 ID 保持不变', () async {
    await File(
      '${tempDir.path}/profile.json',
    ).writeAsString(jsonEncode({'userId': '123456'}));
    final prefs = AppPrefs();
    await prefs.load();
    expect(prefs.userId, '123456');
  });

  test(
    'default and persisted Latin font use the two bundled families',
    () async {
      final prefs = AppPrefs();
      expect(prefs.fontFamily, 'Orbitron');
      expect(prefs.displayFont, 'Orbitron');

      await File('${tempDir.path}/profile.json').writeAsString(
        jsonEncode({'userId': '123456', 'latinFont': 'racingSansOne'}),
      );
      await prefs.load();
      expect(prefs.fontFamily, 'RacingSansOne');
      expect(prefs.displayFont, 'RacingSansOne');
    },
  );

  test('unknown persisted font falls back to Orbitron', () async {
    await File(
      '${tempDir.path}/profile.json',
    ).writeAsString(jsonEncode({'userId': '123456', 'latinFont': 'Speedee'}));
    final prefs = AppPrefs();
    await prefs.load();
    expect(prefs.fontFamily, 'Orbitron');
    expect(prefs.displayFont, 'Orbitron');
  });

  test(
    'dark theme applies Latin font and no bundled CJK fallback (system default)',
    () {
      final theme = DriveTrackTheme.dark(const Color(0xFFE10600));
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Orbitron');
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, isEmpty);
    },
  );

  testWidgets('theme settings offers only Orbitron and Racing Sans One', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
        home: const ThemeSettingsPage(),
      ),
    );

    final racing = find.text('Racing Sans One');
    for (var i = 0; i < 6 && racing.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
    }
    expect(find.text('Orbitron'), findsOneWidget);
    expect(racing, findsOneWidget);
    expect(find.text('Speedee'), findsNothing);
    expect(find.text('导入字体文件'), findsNothing);
    expect(find.text('清除，恢复内置字体'), findsNothing);

    await tester.tap(racing);
    await tester.pump();
    final selectedCards = find.ancestor(
      of: racing,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            ((widget.decoration as BoxDecoration).border?.top.width == 2),
      ),
    );
    expect(selectedCards, findsOneWidget);
  });

  testWidgets('font options fit 320 width with larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: DriveTrackTheme.dark(const Color(0xFFE10600)),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ThemeSettingsPage(),
        ),
      ),
    );

    final racing = find.text('Racing Sans One');
    for (var i = 0; i < 8 && racing.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
    }
    expect(find.text('Orbitron'), findsOneWidget);
    expect(racing, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
