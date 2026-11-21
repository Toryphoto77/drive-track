import 'package:drive_track/settings_home_page.dart';
import 'package:drive_track/track_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings home does not list Device Center', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: SettingsHomePage(
        onOpenPermission: () {},
        onOpenTheme: () {},
        onOpenVoice: () {},
        onOpenTrack: () {},
        onOpenLocation: () {},
        onOpenMapImport: () {},
        countdownVibration: false,
        onCountdownVibrationChanged: (_) {},
        videoRecording: false,
        onVideoRecordingChanged: (_) {},
        trimPrivacy: true,
        onTrimPrivacyChanged: (_) {},
      ),
    ));
    await tester.pump();
    expect(find.text('设备中心'), findsNothing);
    expect(find.text('Devices'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('赛道设置不再保存未生效的定位频率', () {
    final settings = TrackSettings.fromJson({'sample_rate_hz': 10});
    expect(settings.toJson().containsKey('sample_rate_hz'), isFalse);
  });

  testWidgets('频率控制只保留在设备详情，不显示旧假入口', (tester) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: TrackSettingsPage(initial: TrackSettings.defaults),
    ));
    await tester.pump();
    expect(find.text('定位采样率（待固件支持）'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '10 Hz'), findsNothing);
    expect(find.textContaining('请在设备中心'), findsOneWidget);
  });
}
