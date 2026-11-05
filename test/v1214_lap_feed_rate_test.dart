/// v1.2.14 越线检测：喂给 LapTimer 的定位点频率链路核查（只验证，不改链路）。
///
/// 结论（见 main.dart:575-578 的排空循环 + 下面的断言）：
/// - Recorder 不降采样：onLocation / onExternalFix 每次调用都追加一个点，
///   无时间门、无节流、无去重；LapTimer 的排空循环逐点喂入，无丢点。
/// - 手机 GPS 的 1Hz 上限来自原生层（MainActivity.requestLocationUpdates
///   minTime=1000ms），是源头频率，不是记录器降采样。
/// - 外接 GPS（BLE/SPP）25Hz 的不同位置点全部到达 Recorder.points，
///   排空循环即全部喂给 LapTimer；本文件只断言“全量到达”，不改任何生产代码。
import 'dart:convert';

import 'package:drive_track/blediy_gps.dart';
import 'package:drive_track/recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成 25 条 GGA 行（无校验段：解析器容忍缺校验段，见 verifyNmeaChecksum），
/// 每条纬度递增 0.002 分（约 3.7m），模拟 25Hz 外接 GPS 一秒的输出。
List<String> _gga25() {
  return List<String>.generate(25, (i) {
    // 纬度字段为 ddmm.mmm：48 度 + 07.038 分，分钟须补前导零成 2 位整数。
    final minutes = (7.038 + i * 0.002).toStringAsFixed(3).padLeft(6, '0');
    return '\$GPGGA,123519,48$minutes,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,';
  });
}

double _expectedLat(int i) => 48 + (7.038 + i * 0.002) / 60;

void main() {
  group('v1.2.14 LapTimer 喂点频率：记录器不降采样', () {
    test('外接 GPS：25 次 onExternalFix（40ms 间隔）→ 25 个点全量落点', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      for (var i = 0; i < 25; i++) {
        rec.onExternalFix(30.0 + i * 0.0001, 120.0, 10.0, 90.0, 1000 + i * 40);
      }
      expect(rec.points.length, 25);
      // 顺序与时间戳原样保留：排空循环按此顺序喂 LapTimer，圈时用点时间戳。
      expect(rec.points.first.timeMs, 1000);
      expect(rec.points.last.timeMs, 1000 + 24 * 40);
      expect(rec.points.last.lat, closeTo(30.0 + 24 * 0.0001, 1e-9));
    });

    test('手机 GPS：25 次 onLocation 连续调用 → 25 个点，无 1 秒节流', () {
      final rec = Recorder();
      rec.state = RecState.recording;
      for (var i = 0; i < 25; i++) {
        rec.onLocation(<String, dynamic>{
          'lat': 30.0 + i * 0.0001,
          'lon': 120.0,
          'speed': 10.0,
          'bearing': 90.0,
          'timeMs': 1000 + i * 40,
          'alt': 0.0,
          'hasAlt': false,
          'hAcc': 5.0,
          'vAcc': 999.0,
          'sAcc': 999.0,
          'provider': 'gps',
          'satCount': 8,
        });
      }
      expect(rec.points.length, 25);
      expect(rec.points.last.timeMs, 1000 + 24 * 40);
    });

    test('BLE：25Hz GGA 流按 20 字节通知分片 → 25 个不同位置全被 latest 看到', () {
      final feed = BleDiyGpsFeed();
      final bytes = utf8.encode('${_gga25().join('\n')}\n');
      final seen = <double>{};
      for (var off = 0; off < bytes.length; off += 20) {
        final end = (off + 20).clamp(0, bytes.length);
        feed.feedBytes(bytes.sublist(off, end));
        final fix = feed.latest;
        if (fix != null) seen.add(fix.lat);
      }
      // 每条 GGA 都触发一次 emit（acceptedCount 计次），且 main.dart
      // 每通知读一次 latest 时看到的位置无跳号：25 个不同纬度全出现。
      expect(feed.acceptedCount, 25);
      expect(seen.length, 25);
      expect(feed.latest!.lat, closeTo(_expectedLat(24), 1e-9));
    });

    test('SPP：逐行 feedLine → 25 个不同位置全被 latest 看到', () {
      final feed = BleDiyGpsFeed();
      final seen = <double>{};
      for (final line in _gga25()) {
        feed.feedLine(line);
        final fix = feed.latest;
        if (fix != null) seen.add(fix.lat);
      }
      expect(feed.acceptedCount, 25);
      expect(seen.length, 25);
      expect(feed.latest!.lat, closeTo(_expectedLat(24), 1e-9));
    });
  });
}
