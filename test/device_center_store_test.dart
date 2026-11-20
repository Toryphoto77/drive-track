import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/device_center.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('drivetrack/native');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dt_store');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (MethodCall call) async {
      if (call.method == 'getFilesDir') return tempDir.path;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DeviceCenterStore.save 后 load 能读回（含地址与类型）', () async {
    const dev = SavedDevice(
      name: 'Test GPS',
      serviceUuid: '',
      characteristicUuid: '',
      type: '外接GPS',
      address: 'AA:BB:CC:DD:EE:01',
    );
    final ok = await DeviceCenterStore.save(<SavedDevice>[dev]);
    expect(ok, isTrue);

    final loaded = await DeviceCenterStore.load();
    expect(loaded.length, 1);
    expect(loaded.first.name, 'Test GPS');
    expect(loaded.first.type, '外接GPS');
    expect(loaded.first.address, 'AA:BB:CC:DD:EE:01');
  });

  test('空清单 load 返回空列表，不抛异常', () async {
    final loaded = await DeviceCenterStore.load();
    expect(loaded, isEmpty);
  });
}
