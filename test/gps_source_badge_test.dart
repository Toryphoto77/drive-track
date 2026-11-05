import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/gps_source_badge.dart';

Widget _wrap(GpsSourceBadge badge) => MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(primary: Color(0xFFE10600)),
      ),
      home: Scaffold(body: badge),
    );

void main() {
  group('v1.2.16 GPS 来源徽标（纯 widget，不涉真机）', () {
    testWidgets('外接态：设备名 + 频率 + 星数', (tester) async {
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: true,
        deviceName: 'DEXIAN D1',
        hz: 25,
        satelliteCount: 12,
        accuracyM: 3,
      )));
      await tester.pump();
      expect(find.text('外接 GPS · DEXIAN D1 · 25Hz · 12 颗星'),
          findsOneWidget);
      expect(find.text('手机 GPS · 1Hz'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('外接态：无设备名时省略该段，不编名', (tester) async {
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: true,
        hz: 25,
        satelliteCount: 9,
        accuracyM: 2,
      )));
      await tester.pump();
      expect(find.text('外接 GPS · 25Hz · 9 颗星'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手机态：灰色文案固定为“手机 GPS · 1Hz”', (tester) async {
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: false,
        satelliteCount: 14,
        accuracyM: 5,
      )));
      await tester.pump();
      expect(find.text('手机 GPS · 1Hz'), findsOneWidget);
      expect(find.textContaining('外接 GPS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('回落态：外接失效即变灰，文案为手机 GPS', (tester) async {
      // 回落 = 曾接外接但已超时：externalActive=false + fallingBack=true。
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: false,
        fallingBack: true,
        hz: 25,
        satelliteCount: 12,
      )));
      await tester.pump();
      expect(find.text('手机 GPS · 1Hz'), findsOneWidget);
      expect(find.textContaining('外接 GPS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('详情：无数据项显示“—”，不编数', (tester) async {
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: false,
      )));
      await tester.pump();
      await tester.tap(find.text('手机 GPS · 1Hz'));
      await tester.pumpAndSettle();
      expect(find.text('GPS 来源'), findsOneWidget);
      // 设备 / 卫星数 / 定位精度三项无数据 → 三个“—”。
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('手机 GPS'), findsWidgets);
      expect(find.text('1Hz'), findsOneWidget);
      expect(find.text('否'), findsOneWidget); // 正在回落手机 GPS：否
      expect(tester.takeException(), isNull);
    });

    testWidgets('详情：外接态显示实测值，回落行显示“是”', (tester) async {
      await tester.pumpWidget(_wrap(const GpsSourceBadge(
        externalActive: false,
        fallingBack: true,
        deviceName: 'DEXIAN D1',
        hz: 25,
        satelliteCount: 12,
        accuracyM: 3,
      )));
      await tester.pump();
      await tester.tap(find.text('手机 GPS · 1Hz'));
      await tester.pumpAndSettle();
      expect(find.text('GPS 来源'), findsOneWidget);
      expect(find.text('DEXIAN D1'), findsOneWidget);
      // 已回落：当前来源是手机 GPS，频率按手机 1Hz 显示，
      // 不把回落前外接的 25Hz 当作当前频率继续展示。
      expect(find.text('1Hz'), findsOneWidget);
      expect(find.text('25Hz'), findsNothing);
      expect(find.text('12 颗'), findsOneWidget);
      expect(find.text('3 m'), findsOneWidget);
      expect(find.text('是'), findsOneWidget); // 正在回落手机 GPS：是
      expect(find.text('—'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
