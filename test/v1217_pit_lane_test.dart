/// v1.2.17 维修区入口 / 出口点：模型字段与 JSON 键、hasPitLane、
/// 编辑页工具卡片与点列表、手动落点与保存回写。
///
/// 注意：本文件全部用测试坐标，不含任何真实赛道的维修区坐标；
/// 19 个官方包目前均无 pitIn/pitOut（见任务核对），不得在此
/// 编造或写入。

import 'package:drive_track/track_library.dart';
import 'package:drive_track/track_package_editor.dart';
import 'package:drive_track/track_timing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPackage _pkg({
  GeoPoint? pitIn,
  GeoPoint? pitOut,
  List<GeoPoint> sectors = const [],
}) {
  return TrackPackage(
    id: 'test-pit',
    nameCn: '测试赛道',
    nameEn: 'Test Pit',
    region: '中国',
    version: 1,
    source: TrackPackageSource.osm,
    sourceDetail: 'test',
    verification: TrackPackageVerification.verified,
    verificationNote: '已核对',
    centerline: const [
      GeoPoint(31.3376, 121.2223),
      GeoPoint(31.3380, 121.2230),
      GeoPoint(31.3376, 121.2223),
    ],
    lengthM: 5000,
    start: const GeoPoint(31.3376, 121.2223),
    finish: const GeoPoint(31.3376, 121.2223),
    gantry: const GeoPoint(31.3378, 121.2226),
    pitIn: pitIn,
    pitOut: pitOut,
    sectorPoints: sectors,
    sectorNote: '分段待核',
  );
}

void main() {
  group('模型：pitIn / pitOut', () {
    test('JSON 往返：维修区入口/出口坐标不丢', () {
      const pitIn = GeoPoint(31.3370, 121.2210);
      const pitOut = GeoPoint(31.3385, 121.2240);
      final pkg = _pkg(pitIn: pitIn, pitOut: pitOut);
      final restored = TrackPackage.fromJson(pkg.toJson());
      // GeoPoint 无 == 重写，按坐标比对（与既有测试同口径）。
      expect(restored.pitIn?.lat, pitIn.lat);
      expect(restored.pitIn?.lon, pitIn.lon);
      expect(restored.pitOut?.lat, pitOut.lat);
      expect(restored.pitOut?.lon, pitOut.lon);
      expect(restored.hasPitLane, isTrue);
      expect(pkg.toJson()['pitIn'], {'lat': 31.337, 'lon': 121.221});
      expect(pkg.toJson()['pitOut'], {'lat': 31.3385, 'lon': 121.224});
    });

    test('hasPitLane：缺任一端即为 false', () {
      expect(_pkg().hasPitLane, isFalse);
      expect(_pkg(pitIn: const GeoPoint(31.337, 121.221)).hasPitLane, isFalse);
      expect(_pkg(pitOut: const GeoPoint(31.3385, 121.224)).hasPitLane, isFalse);
      expect(
        _pkg(
          pitIn: const GeoPoint(31.337, 121.221),
          pitOut: const GeoPoint(31.3385, 121.224),
        ).hasPitLane,
        isTrue,
      );
    });

    test('旧包 JSON 无 pit 键：解析为 null，不报错', () {
      final json = _pkg().toJson()
        ..remove('pitIn')
        ..remove('pitOut');
      final restored = TrackPackage.fromJson(json);
      expect(restored.pitIn, isNull);
      expect(restored.pitOut, isNull);
      expect(restored.hasPitLane, isFalse);
    });

    test('copyWith：不传 pit 参数时保留原值，传入时替换', () {
      const pitIn = GeoPoint(31.337, 121.221);
      const pitOut = GeoPoint(31.3385, 121.224);
      final pkg = _pkg(pitIn: pitIn, pitOut: pitOut);
      final kept = pkg.copyWith(version: 2);
      expect(kept.pitIn?.lat, pitIn.lat);
      expect(kept.pitIn?.lon, pitIn.lon);
      expect(kept.pitOut?.lat, pitOut.lat);
      expect(kept.pitOut?.lon, pitOut.lon);
      const newPitIn = GeoPoint(31.3371, 121.2211);
      final replaced = pkg.copyWith(pitIn: newPitIn);
      expect(replaced.pitIn?.lat, newPitIn.lat);
      expect(replaced.pitIn?.lon, newPitIn.lon);
      expect(replaced.pitOut?.lat, pitOut.lat);
      expect(replaced.pitOut?.lon, pitOut.lon);
    });
  });

  group('编辑页 widget：维修区工具与点列表', () {
    Future<void> pumpEditor(
      WidgetTester tester,
      TrackPackage package,
      ValueChanged<TrackPackage> onSave,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackPackageEditorPage(package: package, onSave: onSave),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('工具卡片含维修区入口/出口；未标定时点列表显示未设置', (tester) async {
      await pumpEditor(tester, _pkg(), (_) {});
      for (final label in ['维修区入口', '维修区出口']) {
        // 工具卡片与点列表各出现一次。
        expect(find.text(label), findsWidgets);
      }
      // 起点/终点/龙门架已设，维修区两行未设置。
      expect(find.text('未设置'), findsNWidgets(2));
    });

    testWidgets('已标定：点列表显示坐标，点行可选中微调', (tester) async {
      const pitIn = GeoPoint(31.337, 121.221);
      const pitOut = GeoPoint(31.3385, 121.224);
      await pumpEditor(tester, _pkg(pitIn: pitIn, pitOut: pitOut), (_) {});
      expect(find.text('31.33700, 121.22100'), findsOneWidget);
      expect(find.text('31.33850, 121.22400'), findsOneWidget);
      // 点维修区入口行（工具卡片在上、点列表在下，取最后一个）：
      // 点列表在可滚动下半区，先滚到可见再点。
      final pitInRow = find.text('维修区入口').last;
      await tester.ensureVisible(pitInRow);
      await tester.pumpAndSettle();
      await tester.tap(pitInRow);
      await tester.pump();
      expect(find.textContaining('已选中 维修区入口'), findsOneWidget);
    });

    testWidgets('手动输入落点：选维修区入口下拉，输入坐标后保存回写', (tester) async {
      TrackPackage? saved;
      await pumpEditor(tester, _pkg(), (p) => saved = p);
      // 手动输入区在可滚动下半区，先滚到可见再操作。
      final dropdown = find.byWidgetPredicate((w) => w is DropdownButton);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      // 手动输入区下拉：点开后选“维修区入口”。
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('维修区入口').last);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '31.337');
      await tester.enterText(fields.last, '121.221');
      final dropButton = find.text('落点');
      await tester.ensureVisible(dropButton);
      await tester.pumpAndSettle();
      await tester.tap(dropButton);
      await tester.pump();
      expect(find.text('31.33700, 121.22100'), findsOneWidget);
      // 保存：回写含 pitIn，核对状态回落 pending（既有规则）。
      await tester.tap(find.text('保存').last);
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.pitIn?.lat, 31.337);
      expect(saved!.pitIn?.lon, 121.221);
      expect(saved!.pitOut, isNull);
      expect(saved!.hasPitLane, isFalse);
      expect(saved!.verification, TrackPackageVerification.pending);
      expect(saved!.verificationNote, '用户编辑，待核对');
      // 未动分段点：sectorNote 保持原注记。
      expect(saved!.sectorNote, '分段待核');
    });

    testWidgets('保存：已标定的维修区两点原样回写', (tester) async {
      TrackPackage? saved;
      const pitIn = GeoPoint(31.337, 121.221);
      const pitOut = GeoPoint(31.3385, 121.224);
      await pumpEditor(
        tester,
        _pkg(pitIn: pitIn, pitOut: pitOut),
        (p) => saved = p,
      );
      await tester.tap(find.text('保存').last);
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.pitIn?.lat, pitIn.lat);
      expect(saved!.pitIn?.lon, pitIn.lon);
      expect(saved!.pitOut?.lat, pitOut.lat);
      expect(saved!.pitOut?.lon, pitOut.lon);
      expect(saved!.hasPitLane, isTrue);
    });
  });
}
