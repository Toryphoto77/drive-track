import 'package:drive_track/big_action_buttons.dart';
import 'package:drive_track/mount_calibration.dart';
import 'package:drive_track/recorder.dart';
import 'package:drive_track/sensor_calibration_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('安装标定步骤保存方向与补偿角', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rec = Recorder();
    MountCalibration? saved;
    await tester.pumpWidget(MaterialApp(
      home: SensorCalibrationPage(
        recorder: rec,
        onStartHeadingCalibration: () {},
        onSaveMountCalibration: (calibration) async => saved = calibration,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pump();

    expect(find.text('第 3 步 · 安装方向与补偿角'), findsOneWidget);
    await tester.tap(find.text('横装（长边垂直车头）'));
    await tester.pump();
    await tester.tap(find.text('保存安装标定'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.orientation, MountOrientation.lateral);
    expect(saved!.configured, isTrue);
  });

  testWidgets('车头已标定但安装未确认时首页显示橙色提示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: BigActionButtons(
              calibrationState: CalibrationButtonState.calibrated,
              calibrationDetail: '10:00 · 车头已锁定',
              mountCalibrated: false,
              onCalibrate: () {},
              onStartRecording: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('安装未确认 · 姿态角可能偏移'), findsOneWidget);
  });
}
