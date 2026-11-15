import 'package:flutter_test/flutter_test.dart';
import 'package:drive_track/gps_source.dart';
import 'package:drive_track/models.dart';

void main() {
  group('v1.5.7 模式行：汽车 / 摩托 / 卡丁', () {
    test('首页三档不含骑行，卡丁占第三位', () {
      expect(kHomeModes, [TripMode.car, TripMode.moto, TripMode.kart]);
      expect(kHomeModes.contains(TripMode.bike), isFalse);
    });

    test('卡丁车按 name 往返序列化', () {
      expect(TripMode.kart.key, 'kart');
      expect(TripMode.kart.label, '卡丁车');
      expect(TripModeLabel.fromKey('kart'), TripMode.kart);
    });

    test('历史 bike 行程仍可解析', () {
      expect(TripModeLabel.fromKey('bike'), TripMode.bike);
      expect(TripMode.bike.label, '骑行');
    });

    test('卡丁车阈值与摩托同档，不套用骑行', () {
      expect(ModeThresholds.of(TripMode.kart).harshAccel, 0.35);
      expect(ModeThresholds.of(TripMode.kart).harshBrake, -0.40);
    });
  });

  group('v1.5.7 赛道硬件门槛', () {
    int agoMs(int ms) => DateTime.now().millisecondsSinceEpoch - ms;

    test('未连接不放行', () {
      expect(ExternalGpsStatus.disconnected.hardwareReady, isFalse);
    });

    test('二进制待解析设备不放行', () {
      final st = ExternalGpsStatus(
        connected: true,
        binaryOnly: true,
        lastFixAtMs: agoMs(1000),
        sampleRateHz: 25,
      );
      expect(st.hardwareReady, isFalse);
    });

    test('连接正常、1 秒内有定位、25Hz：放行', () {
      final st = ExternalGpsStatus(
        connected: true,
        lastFixAtMs: agoMs(1000),
        sampleRateHz: 25,
      );
      expect(st.hardwareReady, isTrue);
    });

    test('手机 1Hz 采样率不放行', () {
      final st = ExternalGpsStatus(
        connected: true,
        lastFixAtMs: agoMs(500),
        sampleRateHz: 1,
      );
      expect(st.hardwareReady, isFalse);
    });

    test('定位超过 3 秒未更新不放行', () {
      final st = ExternalGpsStatus(
        connected: true,
        lastFixAtMs: agoMs(5000),
        sampleRateHz: 10,
      );
      expect(st.hardwareReady, isFalse);
    });

    test('copyWith 只改心跳，不动连接信息', () {
      const base = ExternalGpsStatus(
        connected: true,
        deviceName: 'DIY-GPS',
        channel: 'ble',
      );
      final next = base.copyWith(lastFixAtMs: 123, sampleRateHz: 10);
      expect(next.connected, isTrue);
      expect(next.deviceName, 'DIY-GPS');
      expect(next.channel, 'ble');
      expect(next.lastFixAtMs, 123);
      expect(next.sampleRateHz, 10);
    });
  });
}
