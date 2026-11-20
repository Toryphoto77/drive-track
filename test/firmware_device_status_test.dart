import 'package:drive_track/device_hardware_card.dart';
import 'package:drive_track/firmware_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PartialStorageService extends FirmwareUpdateService {
  @override
  Future<FirmwareDeviceInfo?> probeDevice({
    Duration timeout = const Duration(seconds: 4),
  }) async => const FirmwareDeviceInfo(
    model: 'DT-BOX-1',
    version: '0.4.1',
    build: 11,
  );

  @override
  Future<DeviceRuntimeStatus?> readStatus({
    Duration timeout = const Duration(seconds: 3),
  }) async => DeviceRuntimeStatus.fromJson({
    'sd': 1,
    'sdState': 'ok',
    'sdTotalKb': 30515200,
  });
}

void main() {
  group('电量解析', () {
    test('数字与带百分号的字符串都能读', () {
      expect(parseBatteryPercent({'battery': 87}), 87);
      expect(parseBatteryPercent({'battery': '87%'}), 87);
      expect(parseBatteryPercent({'batteryPct': 100}), 100);
      expect(parseBatteryPercent({'batteryPercent': 0}), 0);
    });

    test('缺字段 / 越界 / 电压不猜成百分比', () {
      expect(parseBatteryPercent({'voltage': 4.1}), isNull);
      expect(parseBatteryPercent({'battery': 101}), isNull);
      expect(parseBatteryPercent({'battery': -1}), isNull);
      expect(parseBatteryPercent(<String, dynamic>{}), isNull);
      expect(parseBatteryPercent(null), isNull);
    });
  });

  group('设备信息', () {
    test('/api/info 带电量与充电状态', () {
      final info = FirmwareDeviceInfo.fromJson({
        'model': 'DT-GPS1',
        'fw': '1.2.0',
        'build': 12,
        'battery': 64,
        'charging': true,
      });
      expect(info!.model, 'DT-GPS1');
      expect(info.version, '1.2.0');
      expect(info.build, 12);
      expect(info.batteryPercent, 64);
      expect(info.charging, true);
    });

    test('旧固件没有电量时为 null，不冒充 0', () {
      final info = FirmwareDeviceInfo.fromJson({'fw': '0.9.0'});
      expect(info!.batteryPercent, isNull);
      expect(info.charging, isNull);
    });
  });

  group('圈速文本解析', () {
    test('mm:ss.mmm / 秒 / 毫秒', () {
      expect(DeviceLap.parseLapTimeText('1:23.456'), 83456);
      expect(DeviceLap.parseLapTimeText('83.456'), 83456);
      expect(DeviceLap.parseLapTimeText(83456), 83456);
      expect(DeviceLap.parseLapTimeText('1:02:03.5'), 3723500);
    });

    test('非法文本返回 null', () {
      expect(DeviceLap.parseLapTimeText('abc'), isNull);
      expect(DeviceLap.parseLapTimeText(''), isNull);
      expect(DeviceLap.parseLapTimeText(null), isNull);
    });
  });

  group('设备圈速', () {
    test('接受 timeMs / ms / time 字段并补圈序', () {
      final a = DeviceLap.fromJson({'i': 3, 'timeMs': 61000});
      final b = DeviceLap.fromJson({'ms': 62000}, fallbackIndex: 4);
      final c = DeviceLap.fromJson({'time': '1:03.000'}, fallbackIndex: 5);
      expect(a!.index, 3);
      expect(a.timeMs, 61000);
      expect(b!.index, 4);
      expect(b.timeMs, 62000);
      expect(c!.timeMs, 63000);
    });

    test('零 / 负数 / 不可解析返回 null', () {
      expect(DeviceLap.fromJson({'timeMs': 0}), isNull);
      expect(DeviceLap.fromJson({'timeMs': -5}), isNull);
      expect(DeviceLap.fromJson({'foo': 'bar'}), isNull);
    });
  });

  group('实时状态', () {
    test('caps 声明决定关机 / 圈速接口是否可用', () {
      final s = DeviceRuntimeStatus.fromJson({
        'battery': 55,
        'sats': 12,
        'fix': true,
        'laps': 3,
        'currentLapMs': 32100,
        'bestLapMs': 60000,
        'caps': ['shutdown', 'laps'],
      });
      expect(s.batteryPercent, 55);
      expect(s.satellites, 12);
      expect(s.hasFix, true);
      expect(s.lapCount, 3);
      expect(s.currentLapMs, 32100);
      expect(s.bestLapMs, 60000);
      expect(s.supportsShutdown, true);
      expect(s.supportsLaps, true);
    });

    test('旧固件没有 caps 时按钮能力为 false', () {
      final s = DeviceRuntimeStatus.fromJson({'battery': 80});
      expect(s.supportsShutdown, false);
      expect(s.supportsLaps, false);
      expect(s.hasFix, isNull);
      expect(s.satellites, isNull);
    });

    test('0.4.1 传感器工作状态：IMU 正常、气压计异常要如实区分', () {
      final s = DeviceRuntimeStatus.fromJson({'imu': 1, 'baro': 0});
      expect(s.imuReady, true);
      expect(s.baroReady, false);
    });

    test('旧固件未上报传感器状态时保持 null，不冒充正常', () {
      final s = DeviceRuntimeStatus.fromJson({'battery': 80});
      expect(s.imuReady, isNull);
      expect(s.baroReady, isNull);
    });

    // 固件 0.4.0 起 /api/status 带 SD 字段
    test('SD 已挂载：读出总容量与剩余容量', () {
      final s = DeviceRuntimeStatus.fromJson({
        'sd': 1,
        'sdState': 'ok',
        'sdTotalKb': 30515200,
        'sdFreeKb': 24117248,
        'caps': ['shutdown', 'storage'],
      });
      expect(s.sdPresent, true);
      expect(s.sdState, 'ok');
      expect(s.sdTotalKb, 30515200);
      expect(s.sdFreeKb, 24117248);
      expect(s.sdMounted, true);
    });

    test('未插卡 / 挂载失败：sd=false 且总量为 0，界面不能当可用', () {
      final noCard = DeviceRuntimeStatus.fromJson({
        'sd': 0,
        'sdState': 'no_card',
        'sdTotalKb': 0,
        'sdFreeKb': 0,
      });
      expect(noCard.sdMounted, false);
      expect(noCard.sdState, 'no_card');

      final failed = DeviceRuntimeStatus.fromJson({
        'sd': 0,
        'sdState': 'mount_fail',
        'sdTotalKb': 0,
      });
      expect(failed.sdMounted, false);
      expect(failed.sdState, 'mount_fail');
    });

    test('0.3.0 旧固件没有 SD 字段 → 全为 null，界面隐藏该行', () {
      final s = DeviceRuntimeStatus.fromJson({'battery': 80});
      expect(s.sdPresent, isNull);
      expect(s.sdState, isNull);
      expect(s.sdTotalKb, isNull);
      expect(s.sdFreeKb, isNull);
      expect(s.sdMounted, false);
    });
  });

  group('圈速导入存档', () {
    test('toJson / fromJson 往返保留圈序与用时', () {
      final session = HardwareLapSession(
        importedAtMs: 1700000000000,
        model: 'DT-GPS1',
        laps: const [
          DeviceLap(index: 1, timeMs: 61000),
          DeviceLap(index: 2, timeMs: 60000),
        ],
      );
      final restored = HardwareLapSession.fromJson(session.toJson())!;
      expect(restored.importedAtMs, 1700000000000);
      expect(restored.model, 'DT-GPS1');
      expect(restored.laps.map((l) => l.timeMs), [61000, 60000]);
      expect(restored.laps.map((l) => l.index), [1, 2]);
    });
  });

  testWidgets('存储容量缺字段时显示占位符，不伪造成 0 KB', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceManagementPage(
          deviceName: 'DriveTrack-56F6',
          address: 'AA:BB:CC:DD:56:F6',
          deviceType: '外接GPS',
          service: _PartialStorageService(),
          pollInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('硬件存储'), findsOneWidget);
    expect(find.text('总容量'), findsOneWidget);
    expect(find.text('已用空间'), findsOneWidget);
    expect(find.text('可用空间'), findsOneWidget);
    expect(find.text('0 KB'), findsNothing);
  });
}
