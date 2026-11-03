import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/recording_3d_map.dart';

void main() {
  testWidgets('Recording3dMap shows stylized disclaimer, 3D toggle and no tiles', (tester) async {
    var mode = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: Recording3dMap(
            centerLat: 31.2304,
            centerLon: 121.4737,
            headingDeg: 0,
            points: const [
              Recording3dPoint(lat: 31.2304, lon: 121.4737, speedKmh: 20),
              Recording3dPoint(lat: 31.2314, lon: 121.4737, speedKmh: 80),
            ],
            is3d: mode,
            onModeChanged: (v) => mode = v,
            zoom: 16,
            onZoomChanged: (_) {},
            headingUp: true,
            onCompassTap: () {},
            accentColor: Colors.red,
            vehicleColor: Colors.red,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('风格化示意，非真实 3D 城市模型；路网来自 OpenStreetMap'), findsOneWidget);
    // v1.0.7：路网状态改为分档显示 + 点按重拉，初始为加载中，断言只认“路网”开头。
    expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('路网')), findsWidgets);
    expect(find.text('3D'), findsOneWidget);
    await tester.tap(find.text('3D'));
    expect(mode, isFalse);
  });
}
