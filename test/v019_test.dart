import 'package:drive_track/distance_format.dart';
import 'package:drive_track/home_layout.dart';
import 'package:drive_track/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v1.7.4 nav alignment: mode row 228, pill nav 288x68', () {
    // v1.5.8：模式行图标间距由 28 加到 40，节距 64 → 76，整行 228。
    // v1.0.9 方案 A 导航栏与模式行解耦、加宽：216x56（旧 176x52
    // 已作废，断言同步改为新规格）。
    // v1.5.4：4 项（加设备中心）再加宽到 288x56，仍是每项 72 节距。
    // v1.7.4：导航项加文字标签，药丸高度 56 → 68。
    expect(kModeRowWidth, 228.0);
    expect(kPillNavWidth, 288.0);
    expect(kModeRowItemPitch, 76.0);
    expect(kPillNavHeight, 68.0);
    for (final w in [320.0, 360.0, 390.0, 412.0, 768.0]) {
      final centers = tripleCenters(w);
      expect(centers.length, 3);
      // 中格中心恒为屏宽一半；首末格关于屏宽中心对称；节距恒 76。
      expect(centers[1], closeTo(w / 2, 1e-9));
      expect(centers[2], closeTo(w - centers[0], 1e-9));
      expect(centers[1] - centers[0], closeTo(76.0, 1e-9));
      expect(centers[2] - centers[1], closeTo(76.0, 1e-9));
    }
  });

  test('v0.1.9 total distance format: thousands + one decimal, no truncation', () {
    expect(formatDistanceKm(123456.7), '123,456.7 km');
    expect(formatDistanceKm(12345.0), '12,345.0 km');
    expect(formatDistanceKm(999.95), '1,000.0 km');
    expect(formatDistanceKm(0), '0.0 km');
    // 单位始终跟在数字同一字符串内，不会被拆到下一行。
    expect(formatDistanceKm(123456.7).contains('\n'), isFalse);
  });

  testWidgets('v0.1.9 splash: slogan shown, then navigates to /home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const SplashPage(),
        routes: {'/home': (_) => const Text('HOME_AFTER_SPLASH')},
      ),
    );
    expect(find.text('驰迹 DriveTrack'), findsOneWidget);
    expect(find.text('记录每一次出发'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('HOME_AFTER_SPLASH'), findsOneWidget);
  });
}
