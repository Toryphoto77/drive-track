import 'package:drive_track/device_hardware_card.dart';
import 'package:drive_track/firmware_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
