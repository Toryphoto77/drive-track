/// 官方赛道包搜索匹配测试（v1.5.2）。
///
/// 覆盖：中文名 / 英文名 / 地区子串匹配（不区分大小写）、空查询
/// 不过滤、无匹配返回 false。页面整页泵 TrackLibraryPage 会在
/// widget 测试里挂起（dart:io Future，见
/// track_library_page_card_test.dart），因此只测纯函数
/// matchesTrackSearch；页面接线（输入框 → _searchQuery → 过滤）
/// 为三行直连代码，已人工核对。

import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_library_page.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPackage pkg({
  required String id,
  required String nameCn,
  required String nameEn,
  required String region,
}) =>
    TrackPackage(
      id: id,
      nameCn: nameCn,
      nameEn: nameEn,
      region: region,
      version: 1,
      source: TrackPackageSource.official,
      verification: TrackPackageVerification.verified,
    );

void main() {
  group('matchesTrackSearch', () {
    final shanghai = pkg(
      id: 'shanghai',
      nameCn: '上海国际赛车场',
      nameEn: 'Shanghai International Circuit',
      region: '中国 · 上海',
    );
    final silverstone = pkg(
      id: 'silverstone',
      nameCn: '银石赛道',
      nameEn: 'Silverstone Circuit',
      region: '英国',
    );

    test('中文名子串匹配', () {
      expect(matchesTrackSearch(shanghai, '上海'), isTrue);
      expect(matchesTrackSearch(silverstone, '上海'), isFalse);
    });

    test('英文名匹配不区分大小写', () {
      expect(matchesTrackSearch(shanghai, 'shanghai'), isTrue);
      expect(matchesTrackSearch(shanghai, 'SHANGHAI'), isTrue);
      expect(matchesTrackSearch(silverstone, 'silverstone'), isTrue);
    });

    test('地区子串匹配', () {
      expect(matchesTrackSearch(shanghai, '中国'), isTrue);
      expect(matchesTrackSearch(silverstone, '英国'), isTrue);
      expect(matchesTrackSearch(silverstone, '中国'), isFalse);
    });

    test('空查询与空白查询不过滤', () {
      expect(matchesTrackSearch(shanghai, ''), isTrue);
      expect(matchesTrackSearch(shanghai, '   '), isTrue);
    });

    test('无匹配返回 false', () {
      expect(matchesTrackSearch(shanghai, '摩纳哥'), isFalse);
      expect(matchesTrackSearch(silverstone, 'monza'), isFalse);
    });
  });
}
