import 'package:drive_track/app_bar_style.dart';
import 'package:drive_track/device_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inside extendBodyBehindAppBar, inset is the bar height not bar+toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewPadding = const FakeViewPadding(top: 40);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    double? outside;
    double? inside;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        outside = appBarTopInset(context);
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: DtAppBar(title: const Text('DriveTrack')),
          body: Builder(builder: (context) {
            inside = appBarTopInset(context);
            return const SizedBox.expand();
          }),
        );
      }),
    ));
    await tester.pump();

    expect(outside, 40 + kToolbarHeight);
    expect(inside, isNotNull);
    expect(inside!, greaterThan(40));
    expect(inside!, lessThan(40 + kToolbarHeight + 8));
    expect((inside! - (40 + 2 * kToolbarHeight)).abs(), greaterThan(20));
  });

  testWidgets('embedded device title sits just under the shell app bar', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 16);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 16);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600))),
      home: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: DtAppBar(title: const Text('DriveTrack')),
        body: const DeviceCenterPage(embedded: true),
      ),
    ));
    await tester.pump();

    final bar = tester.getRect(find.byType(DtAppBar));
    final title = tester.getTopLeft(find.text('设备中心'));
    expect(title.dy, greaterThanOrEqualTo(bar.bottom + 8));
    expect(title.dy, lessThan(bar.bottom + 24));
  });
}
