import 'package:drive_track/settings_home_page.dart';
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
}
