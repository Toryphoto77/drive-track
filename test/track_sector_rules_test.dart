/// 赛道分段第三步（实测替换规则）测试：用户实测分段无条件胜出推导值。
///
/// 覆盖：
/// - 合并：用户改动（含实测分段）胜过高版本打包种子（推导分段）；
/// - 合并：打包种子 v2（推导分段）正常覆盖内置 v1（无分段）；
/// - 编辑器注记规则：分段没动 → 原注记；改动 → 实测口径；清空 → 待补；
/// - LapTimer 只取前 2 个分段点（S3 结束即起终点，不需要第 3 个点）；
/// - manifest 数据总版本 V 前缀按字符串处理（V1.0.1 不得被当数字解析）。

import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPackage _pkg({
  String id = 'test',
  int version = 1,
  bool userModified = false,
  List<GeoPoint> sectors = const [],
  String sectorNote = '',
}) {
  return TrackPackage(
    id: id,
    nameCn: '测试赛道 $id',
    nameEn: 'Test $id',
    region: '中国',
    version: version,
    source: TrackPackageSource.osm,
    sourceDetail: 'test',
    verification: TrackPackageVerification.pending,
    centerline: const [],
    lengthM: 5000,
    sectorPoints: sectors,
    sectorNote: sectorNote,
    userModified: userModified,
  );
}

void main() {
  group('实测分段胜出推导分段', () {
    test('用户实测覆盖：override（实测，v1）胜过 bundled v2（推导）', () {
      const derived = [
        GeoPoint(50.431249, 5.97743),
        GeoPoint(50.429935, 5.959621),
      ];
      const measured = [
        GeoPoint(50.4313, 5.9775),
        GeoPoint(50.4299, 5.9596),
      ];
      final merged = mergePackages(
        builtin: [_pkg(id: 'spa', version: 1)],
        bundled: [
          _pkg(
            id: 'spa',
            version: 2,
            sectors: derived,
            sectorNote: '分段：模拟器数据推导，待实测核对',
          ),
        ],
        overrides: [
          _pkg(
            id: 'spa',
            version: 1,
            userModified: true,
            sectors: measured,
            sectorNote: '用户实测分段点（编辑器手动落点），以实测为准',
          ),
        ],
      );
      expect(merged.length, 1);
      expect(merged.first.sectorPoints, measured);
      expect(merged.first.sectorNote, contains('用户实测'));
    });

    test('正常更新：bundled v2（推导分段）覆盖 builtin v1（无分段）', () {
      const derived = [
        GeoPoint(50.431249, 5.97743),
        GeoPoint(50.429935, 5.959621),
      ];
      final merged = mergePackages(
        builtin: [_pkg(id: 'spa', version: 1)],
        bundled: [
          _pkg(
            id: 'spa',
            version: 2,
            sectors: derived,
            sectorNote: '分段：模拟器数据推导，待实测核对',
          ),
        ],
        overrides: const [],
      );
      expect(merged.first.version, 2);
      expect(merged.first.sectorPoints, derived);
    });

    test('diffUpdates：本地已改动（含实测分段）不被远端 v3 列入更新', () {
      final r = diffUpdates(
        localOfficial: [
          _pkg(id: 'spa', version: 2, userModified: true),
        ],
        manifest: TrackLibraryManifest(
          dataVersion: 'V1.0.1',
          updatedAt: '2026-11-05',
          attribution: 'test',
          packages: const [
            ManifestPackage(
              id: 'spa',
              nameCn: '斯帕',
              version: 3,
              url: 'https://example.invalid/spa.json',
              source: TrackPackageSource.osm,
              verification: TrackPackageVerification.verified,
            ),
          ],
        ),
      );
      expect(r.updates, isEmpty);
      expect(r.skippedUserModified.map((u) => u.id), ['spa']);
    });
  });

  group('编辑器分段注记规则', () {
    const derivedNote = '分段：模拟器数据推导，待实测核对';
    const derived = [
      GeoPoint(50.431249, 5.97743),
      GeoPoint(50.429935, 5.959621),
    ];

    test('分段没动 → 原注记不动', () {
      expect(
        sectorNoteAfterEdit(
          original: derived,
          edited: derived,
          originalNote: derivedNote,
        ),
        derivedNote,
      );
    });

    test('分段改动 → 实测口径', () {
      expect(
        sectorNoteAfterEdit(
          original: derived,
          edited: const [
            GeoPoint(50.4313, 5.9775),
            GeoPoint(50.4299, 5.9596),
          ],
          originalNote: derivedNote,
        ),
        '用户实测分段点（编辑器手动落点），以实测为准',
      );
    });

    test('分段清空 → 待补口径', () {
      expect(
        sectorNoteAfterEdit(
          original: derived,
          edited: const [],
          originalNote: derivedNote,
        ),
        contains('待重新落点'),
      );
    });
  });

  group('LapTimer 分段点语义', () {
    test('多于 2 个点只取前 2 个（S3 结束即起终点）', () {
      final timer = LapTimer(
        startFinish: const GeoPoint(50.444064, 5.965163),
        sectorPoints: const [
          GeoPoint(50.431249, 5.97743),
          GeoPoint(50.429935, 5.959621),
          GeoPoint(50.444064, 5.965163),
        ],
      );
      expect(timer.sectorPoints.length, 2);
    });
  });

  group('数据总版本 V 前缀', () {
    test('V1.0.1 按字符串原样保留', () {
      final m = TrackLibraryManifest.fromJson({
        'dataVersion': 'V1.0.1',
        'updatedAt': '2026-11-05',
        'attribution': 'test',
        'packages': [],
      });
      expect(m.dataVersion, 'V1.0.1');
    });
  });
}
