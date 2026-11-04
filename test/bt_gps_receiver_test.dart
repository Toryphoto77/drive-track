import 'package:drive_track/blediy_gps.dart';
import 'package:drive_track/bt_gps_receiver.dart';
import 'package:drive_track/device_center.dart';
import 'package:drive_track/recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GGA 解析', () {
    test('正常 N/E 句：经纬度 / 质量 / 卫星 / HDOP / 海拔', () {
      final gga = parseGga(
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
      expect(gga, isNotNull);
      expect(gga!.lat, closeTo(48.1173, 0.0001));
      expect(gga.lon, closeTo(11.5167, 0.0001));
      expect(gga.fixQuality, 1);
      expect(gga.satellites, 8);
      expect(gga.hdop, closeTo(0.9, 0.001));
      expect(gga.altitudeM, closeTo(545.4, 0.001));
    });

    test('南纬 / 西经取负值', () {
      final gga = parseGga(
          r'$GPGGA,123519,3351.123,S,15112.456,W,1,07,1.2,100.0,M,10.0,M,,*41');
      expect(gga, isNotNull);
      expect(gga!.lat, closeTo(-33.85205, 0.0001));
      expect(gga.lon, closeTo(-151.2076, 0.0001));
    });

    test('质量 0（无效定位）→ null，不造点', () {
      expect(
          parseGga(
              r'$GPGGA,123519,4807.038,N,01131.000,E,0,00,99.9,0.0,M,0.0,M,,*45'),
          isNull);
    });

    test('坏校验和 → null', () {
      expect(
          parseGga(
              r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00'),
          isNull);
    });

    test('残缺句（字段不足）→ null', () {
      expect(parseGga(r'$GPGGA,123519,4807.038,N'), isNull);
    });
  });

  group('RMC 解析', () {
    test('正常句：节→m/s、航向、UTC 时间戳', () {
      final rmc = parseRmc(
          r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A');
      expect(rmc, isNotNull);
      expect(rmc!.lat, closeTo(48.1173, 0.0001));
      expect(rmc.lon, closeTo(11.5167, 0.0001));
      expect(rmc.speedMps, closeTo(22.4 * 0.514444, 0.001));
      expect(rmc.bearingDeg, closeTo(84.4, 0.001));
      // 现有解析器按 2000+yy 映射两位年（既有约定，不在本任务改动）：
      // '94' → 2094，月日时分秒与语句一致即可。
      expect(rmc.timestampUtc, DateTime.utc(2094, 3, 23, 12, 35, 19));
    });

    test('南纬 / 西经取负值', () {
      final rmc = parseRmc(
          r'$GPRMC,123519,A,3351.123,S,15112.456,W,010.0,180.0,230394,003.1,W*66');
      expect(rmc, isNotNull);
      expect(rmc!.lat, closeTo(-33.85205, 0.0001));
      expect(rmc.lon, closeTo(-151.2076, 0.0001));
      expect(rmc.speedMps, closeTo(10.0 * 0.514444, 0.001));
      expect(rmc.bearingDeg, 180.0);
    });

    test('状态 V → null，不造点', () {
      expect(
          parseRmc(
              r'$GPRMC,123519,V,3351.123,S,15112.456,W,010.0,180.0,230394,003.1,W*71'),
          isNull);
    });

    test('13 字段变体（RaceChrono v10.3.0 曾修的场景）能解析', () {
      final rmc = parseRmc(
          r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W,A*07');
      expect(rmc, isNotNull);
      expect(rmc!.speedMps, closeTo(22.4 * 0.514444, 0.001));
      expect(rmc.bearingDeg, closeTo(84.4, 0.001));
    });
  });

  group('VTG 解析', () {
    test('km/h 换算 + 真北方向优先于磁北', () {
      final vtg =
          parseVtg(r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48');
      expect(vtg, isNotNull);
      expect(vtg!.bearingDeg, closeTo(54.7, 0.001));
      expect(vtg.speedMps, closeTo(10.2 / 3.6, 0.001));
    });

    test('km/h 为空时走节换算', () {
      final vtg = parseVtg(r'$GPVTG,090.0,T,080.0,M,010.0,N,,K*60');
      expect(vtg, isNotNull);
      expect(vtg!.bearingDeg, 90.0);
      expect(vtg.speedMps, closeTo(10.0 * 0.514444, 0.001));
    });

    test('速度方向全无 → null，不造点', () {
      expect(parseVtg(r'$GPVTG,,T,,M,,N,,K'), isNull);
    });

    test('坏校验和 → null', () {
      expect(parseVtg(r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*00'),
          isNull);
    });
  });

  group('GSA 解析', () {
    test('3D：模式 3、已用 5 颗、PDOP/HDOP/VDOP', () {
      final gsa = parseGsa(
          r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3,2.1*39');
      expect(gsa, isNotNull);
      expect(gsa!.fixType, 3);
      expect(gsa.usedSatellites, 5);
      expect(gsa.pdop, 2.5);
      expect(gsa.hdop, 1.3);
      expect(gsa.vdop, 2.1);
    });

    test('模式 1：无定位、0 颗星', () {
      final gsa = parseGsa(
          r'$GPGSA,A,1,,,,,,,,,,,,,2.5,1.3,2.1*36');
      expect(gsa, isNotNull);
      expect(gsa!.fixType, 1);
      expect(gsa.usedSatellites, 0);
    });

    test('VDOP 缺失（17 字段）容忍为 null', () {
      final gsa = parseGsa(
          r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3*38');
      expect(gsa, isNotNull);
      expect(gsa!.fixType, 3);
      expect(gsa.usedSatellites, 5);
      expect(gsa.vdop, isNull);
    });

    test('坏校验和 → null', () {
      expect(
          parseGsa(
              r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3,2.1*00'),
          isNull);
    });

    test('残缺句（字段 <15）→ null', () {
      expect(parseGsa(r'$GPGSA,A,3,04'), isNull);
    });
  });

  group('Feed 合并', () {
    test('GSA 先到只记模式 / 星数，不造点、不计 accepted', () {
      final feed = BleDiyGpsFeed();
      final out = feed.feedLine(
          r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3,2.1*39');
      expect(out, isNull);
      expect(feed.latest, isNull);
      expect(feed.acceptedCount, 0);
      expect(feed.droppedCount, 0);
    });

    test('GSA 后 GGA：模式 / 星数 / 质量带入定位', () {
      final feed = BleDiyGpsFeed();
      feed.feedLine(
          r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3,2.1*39');
      final fix = feed.feedLine(
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
      expect(fix, isNotNull);
      expect(fix!.fixMode, 3);
      expect(fix.usedSatellites, 5);
      expect(fix.fixQuality, 1);
      expect(fix.hdop, closeTo(0.9, 0.001)); // GGA HDOP 优先于 GSA。
    });

    test('RMC 沿用 GSA 模式 / 星数', () {
      final feed = BleDiyGpsFeed();
      feed.feedLine(
          r'$GPGSA,A,3,04,05,09,12,24,,,,,,,,2.5,1.3,2.1*39');
      final fix = feed.feedLine(
          r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A');
      expect(fix, isNotNull);
      expect(fix!.fixMode, 3);
      expect(fix.usedSatellites, 5);
    });

    test('VTG 先于位置只暂存，首个位置合并暂存速度', () {
      final feed = BleDiyGpsFeed();
      expect(feed.feedLine(r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48'),
          isNull);
      final fix = feed.feedLine(
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
      expect(fix, isNotNull);
      expect(fix!.speedMps, closeTo(10.2 / 3.6, 0.001));
      expect(fix.bearingDeg, closeTo(54.7, 0.001));
    });

    test('坏句计 dropped，不改最新定位', () {
      final feed = BleDiyGpsFeed();
      feed.feedLine(
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
      expect(
          feed.feedLine(
              r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00'),
          isNull);
      expect(feed.droppedCount, 1);
      expect(feed.latest!.lat, closeTo(48.1173, 0.0001));
    });
  });

  group('设备名匹配', () {
    test('Dexian D1、Garmin GLO、Dual XGPS、RaceBox 命中', () {
      expect(btGpsNameMatches('DEXIAN D1', ['dexian', 'd1']), isTrue);
      expect(btGpsNameMatches('Garmin GLO 2', ['garmin', 'glo']), isTrue);
      expect(btGpsNameMatches('Dual XGPS160', ['dual', 'xgps']), isTrue);
      expect(btGpsNameMatches('RaceBox Mini S', ['racebox']), isTrue);
    });

    test('短提示词按整词匹配，不误判子串', () {
      expect(btGpsNameMatches('AudioD1x', ['d1']), isFalse);
      expect(btGpsNameMatches('MyGloBall', ['glo']), isFalse);
      expect(btGpsNameMatches('JBL Flip', ['dexian', 'd1', 'garmin', 'glo']),
          isFalse);
    });
  });

  group('档案诚实不变量', () {
    test('每设备只出现一次（kind 不重复）', () {
      final kinds = externalGpsProfiles.map((p) => p.kind).toList();
      expect(kinds.toSet().length, kinds.length);
    });

    test('Dexian D1：无硬编 UUID、协议未公开、待真机验证', () {
      final dexian = externalGpsProfiles
          .firstWhere((p) => p.kind == ExternalGpsKind.dexian);
      expect(dexian.serviceUuid, isNull);
      expect(dexian.txUuid, isNull);
      expect(dexian.hasNmeaPath, isFalse);
      expect(dexian.name, contains('D1'));
      expect(dexian.supportBadge, contains('协议未公开'));
      expect(dexian.supportBadge, contains('未实测验证'));
    });

    test('Dragy：无硬编 UUID、私有协议 stub', () {
      final dragy = externalGpsProfiles
          .firstWhere((p) => p.kind == ExternalGpsKind.dragy);
      expect(dragy.serviceUuid, isNull);
      expect(dragy.txUuid, isNull);
      expect(dragy.hasNmeaPath, isFalse);
      expect(dragy.supportBadge, contains('协议未公开'));
      expect(dragy.supportBadge, contains('未实测验证'));
    });

    test('RaceBox：公开文档 NMEA UART UUID（固件 3.3+）', () {
      final rb = externalGpsProfiles
          .firstWhere((p) => p.kind == ExternalGpsKind.racebox);
      expect(rb.serviceUuid, raceboxNmeaServiceUuid);
      expect(rb.txUuid, raceboxNmeaTxUuid);
      expect(rb.hasNmeaPath, isTrue);
    });
  });

  group('协议适配器注册表', () {
    test('通用 NMEA 可用；RaceBox UBX 与 Dragy 私有协议为 stub', () {
      expect(btGpsAdapters['generic_nmea']!.supported, isTrue);
      final ubx = btGpsAdapters['racebox_ubx']!;
      expect(ubx.supported, isFalse);
      expect(ubx.note, contains('UBX'));
      final dragy = btGpsAdapters['dragy_proprietary']!;
      expect(dragy.supported, isFalse);
      expect(dragy.note, contains('私有'));
    });
  });

  group('定位状态文案', () {
    test('各档质量 + 2D/3D 后缀', () {
      expect(btGpsFixStatusLabel(null), '无定位');
      expect(
          btGpsFixStatusLabel(
              const ExternalGpsFix(lat: 1, lon: 2, fixQuality: 1, fixMode: 3)),
          'GPS 定位 · 3D');
      expect(
          btGpsFixStatusLabel(
              const ExternalGpsFix(lat: 1, lon: 2, fixQuality: 4, fixMode: 2)),
          'RTK 固定 · 2D');
      expect(
          btGpsFixStatusLabel(
              const ExternalGpsFix(lat: 1, lon: 2, fixQuality: 0)),
          '无效定位');
      expect(
          btGpsFixStatusLabel(
              const ExternalGpsFix(lat: 1, lon: 2, fixQuality: 5)),
          'RTK 浮动');
    });
  });

  group('Recorder 外置定位守卫', () {
    test('0,0 占位符不移动显示、不进轨迹', () {
      final rec = Recorder();
      rec.onExternalFix(30.0, 120.0, 10.0, 90.0, 1000);
      expect(rec.curLat, 30.0);
      expect(rec.curLon, 120.0);
      rec.onExternalFix(0, 0, 0, 0, 2000);
      expect(rec.curLat, 30.0);
      expect(rec.curLon, 120.0);
    });
  });

  group('Hz 计次（按定位周期，不按语句数）', () {
    const gga =
        r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47';
    const rmc =
        r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A';
    const vtg = r'$GPVTG,054.7,T,034.4,M,005.5,N,010.2,K*48';

    test('GGA+RMC 成对喂 25 周期读数应为 25 而非 50', () {
      final feed = BleDiyGpsFeed();
      final base = DateTime.now();
      for (var i = 0; i < 25; i++) {
        feed.feedLine(gga, now: base.add(Duration(milliseconds: i * 40)));
        feed.feedLine(rmc,
            now: base.add(Duration(milliseconds: i * 40 + 5)));
      }
      expect(feed.hz, 25);
    });

    test('30 条 GGA 读数应为 30，证明无 10Hz 封顶或截断', () {
      final feed = BleDiyGpsFeed();
      final base = DateTime.now();
      for (var i = 0; i < 30; i++) {
        feed.feedLine(gga, now: base.add(Duration(milliseconds: i * 30)));
      }
      expect(feed.hz, 30);
    });

    test('RMC 单发 10 周期读数正常（无 GGA 时以 RMC 计次）', () {
      final feed = BleDiyGpsFeed();
      final base = DateTime.now();
      for (var i = 0; i < 10; i++) {
        feed.feedLine(rmc, now: base.add(Duration(milliseconds: i * 50)));
      }
      expect(feed.hz, 10);
    });

    test('VTG 不计次：GGA+RMC+VTG 三句一周期仍读周期数', () {
      final feed = BleDiyGpsFeed();
      final base = DateTime.now();
      for (var i = 0; i < 10; i++) {
        feed.feedLine(gga, now: base.add(Duration(milliseconds: i * 50)));
        feed.feedLine(rmc,
            now: base.add(Duration(milliseconds: i * 50 + 5)));
        feed.feedLine(vtg,
            now: base.add(Duration(milliseconds: i * 50 + 10)));
      }
      expect(feed.hz, 10);
    });
  });
}
