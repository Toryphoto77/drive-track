import 'package:drive_track/vehicle_profile.dart';
import 'package:drive_track/vehicle_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FuelLog log(
  String id,
  String vehicleId,
  int dateMs,
  double liters, {
  double? odometerKm,
  bool full = false,
}) =>
    FuelLog(
      id: id,
      vehicleId: vehicleId,
      dateMs: dateMs,
      liters: liters,
      odometerKm: odometerKm,
      isFullTank: full,
    );

void main() {
  test('VehicleProfile round-trip keeps all fields, drops invalid numbers', () {
    const v = VehicleProfile(
      id: 'v1',
      name: '家里的车',
      mode: VehicleMode.moto,
      consumptionLPer100Km: 5.5,
      tankCapacityL: 17,
      brand: '自填品牌',
      model: '自填型号',
      displacementCc: 1000,
      weightKg: 200,
      gearbox: '手动',
      drivetrain: '后驱',
      fuelGrade: '95',
    );
    final back = VehicleProfile.fromJson(v.toJson());
    expect(back.id, 'v1');
    expect(back.name, '家里的车');
    expect(back.mode, VehicleMode.moto);
    expect(back.consumptionLPer100Km, 5.5);
    expect(back.tankCapacityL, 17);
    expect(back.brand, '自填品牌');
    expect(back.model, '自填型号');
    expect(back.displacementCc, 1000);
    expect(back.weightKg, 200);
    expect(back.gearbox, '手动');
    expect(back.drivetrain, '后驱');
    expect(back.fuelGrade, '95');
    // 全部可空：只填名称也能往返；<=0 / 空串视作未填写。
    final sparse = VehicleProfile.fromJson({
      'id': 'v2',
      'name': '只填名称',
      'consumptionLPer100Km': 0,
      'weightKg': -5,
      'brand': '  ',
    });
    expect(sparse.consumptionLPer100Km, isNull);
    expect(sparse.weightKg, isNull);
    expect(sparse.brand, isNull);
    expect(sparse.displacementCc, isNull);
    expect(sparse.hasConsumption, isFalse);
    expect(VehicleProfile.fromJson(sparse.toJson()).name, '只填名称');
  });

  test('FuelLog round-trip and effective amount prefers stored amount', () {
    final l = FuelLog(
      id: 'f1',
      vehicleId: 'v1',
      dateMs: 1700000000000,
      liters: 10,
      pricePerLiter: 8,
      amount: 79,
      odometerKm: 10000,
      isFullTank: true,
    );
    final back = FuelLog.fromJson(l.toJson());
    expect(back.effectiveAmount, 79);
    expect(back.isFullTank, isTrue);
    // 未填金额时为升数×单价；两项缺一时为 null，不是 0。
    expect(
        FuelLog(id: 'f2', vehicleId: 'v1', dateMs: 1, liters: 10, pricePerLiter: 8)
            .effectiveAmount,
        80);
    expect(
        FuelLog(id: 'f3', vehicleId: 'v1', dateMs: 1, liters: 10)
            .effectiveAmount,
        isNull);
  });

  test('full-to-full interval counts, opening fill itself excluded', () {
    // 满油 10000km，加 40L 到 10500km 满油：40/500*100 = 8.0。
    final logs = [
      log('a', 'v1', 1000, 30, odometerKm: 10000, full: true),
      log('b', 'v1', 2000, 40, odometerKm: 10500, full: true),
    ];
    final intervals = measuredIntervals(logs);
    expect(intervals.length, 1);
    expect(intervals.first.distanceKm, 500);
    expect(intervals.first.liters, 40);
    expect(measuredConsumption(logs), closeTo(8.0, 1e-9));
  });

  test('partial fills between fulls count into that interval, trailing partial does not', () {
    final logs = [
      log('a', 'v1', 1000, 30, odometerKm: 10000, full: true),
      log('b', 'v1', 2000, 10, odometerKm: 10200), // 不满油，夹在中间
      log('c', 'v1', 3000, 30, odometerKm: 10500, full: true),
      log('d', 'v1', 4000, 5, odometerKm: 10600), // 尾段悬空，不算
    ];
    // 区间油量 = 10 + 30 = 40，里程 500 -> 8.0；尾段 5L 不计。
    expect(measuredConsumption(logs), closeTo(8.0, 1e-9));
    expect(measuredIntervals(logs).length, 1);
  });

  test('partial-only, single full, and missing odometer never yield measured', () {
    expect(
        measuredConsumption([
          log('a', 'v1', 1000, 10, odometerKm: 10000),
          log('b', 'v1', 2000, 10, odometerKm: 10500),
        ]),
        isNull);
    expect(
        measuredConsumption([
          log('a', 'v1', 1000, 10, odometerKm: 10000, full: true),
        ]),
        isNull);
    expect(
        measuredConsumption([
          log('a', 'v1', 1000, 10, full: true),
          log('b', 'v1', 2000, 40, full: true),
        ]),
        isNull);
    // 里程倒退 / 相等也不算。
    expect(
        measuredConsumption([
          log('a', 'v1', 1000, 10, odometerKm: 10500, full: true),
          log('b', 'v1', 2000, 40, odometerKm: 10500, full: true),
        ]),
        isNull);
  });

  test('measured is distance-weighted, not a plain mean; other vehicles excluded', () {
    final logs = [
      log('a', 'v1', 1000, 10, odometerKm: 10000, full: true),
      log('b', 'v1', 2000, 10, odometerKm: 10100, full: true), // 10L/100km
      log('c', 'v1', 3000, 40, odometerKm: 10500, full: true), // 40L/400km = 10L/100km
      log('x', 'v2', 1500, 99, odometerKm: 0, full: true),
      log('y', 'v2', 2500, 99, odometerKm: 100, full: true),
    ];
    // v1 两区间：10/100 与 40/400，加权 = 50/500*100 = 10。
    expect(measuredConsumptionForVehicle(logs, 'v1'), closeTo(10.0, 1e-9));
    expect(measuredIntervalsForVehicle(logs, 'v1').length, 2);
  });

  test('empty fields do not participate: specEntries skips them, no derived consumption', () {
    const v = VehicleProfile(id: 'v1', name: '只填名称');
    expect(v.specEntries().map((e) => e.key), contains('模式'));
    expect(v.specEntries().map((e) => e.key), isNot(contains('排量')));
    expect(v.specEntries().map((e) => e.key), isNot(contains('车重')));
    expect(v.specEntries().map((e) => e.key), isNot(contains('百公里油耗')));
    // 排量 / 车重齐全也不产生油耗：模型根本没有此类函数，
    // 这里只断言档案本身不携带任何油耗值。
    const heavy = VehicleProfile(
        id: 'v2', name: '重车', displacementCc: 5000, weightKg: 2500);
    expect(heavy.consumptionLPer100Km, isNull);
    expect(heavy.hasConsumption, isFalse);
  });

  test('VehicleLibrary delete drops its fuel logs, clears default, keeps trips fallback rule', () {
    final lib = VehicleLibrary(
      vehicles: const [
        VehicleProfile(id: 'v1', name: '车一'),
        VehicleProfile(id: 'v2', name: '车二'),
      ],
      fuelLogs: [
        log('f1', 'v1', 1000, 10, odometerKm: 10000, full: true),
        log('f2', 'v2', 1000, 10, odometerKm: 5000, full: true),
      ],
      defaultVehicleId: 'v1',
    );
    final after = lib.deleteVehicle('v1');
    expect(after.vehicles.map((v) => v.id), ['v2']);
    expect(after.fuelLogs.map((l) => l.id), ['f2']);
    expect(after.defaultVehicleId, isNull);
    // 行程绑定：绑被删车辆 -> null（回退全局值）；绑别的车不变。
    expect(tripVehicleIdAfterVehicleDeleted('v1', 'v1'), isNull);
    expect(tripVehicleIdAfterVehicleDeleted('v1', 'v2'), 'v2');
    expect(tripVehicleIdAfterVehicleDeleted('v1', null), isNull);
    // 集合往返：默认车不存在时不编默认。
    final round = VehicleLibrary.fromJson(lib.toJson());
    expect(round.defaultVehicleId, 'v1');
    expect(VehicleLibrary.fromJson(after.toJson()).defaultVehicleId, isNull);
  });

  testWidgets('VehicleProfilePage shows filled fields only, hides empty ones',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VehicleProfilePage(
          initialProfiles: [
            VehicleProfile(id: 'v1', name: '家里的车', brand: '自填品牌'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('家里的车'), findsOneWidget);
    expect(find.text('品牌：自填品牌'), findsOneWidget);
    // 空字段不渲染为卡片条目（条目格式为“标签：值”，页眉说明文案
    // 不含冒号，故用带冒号的精确子串区分说明与条目）。
    expect(find.textContaining('排量：'), findsNothing);
    expect(find.textContaining('车重：'), findsNothing);
    expect(find.textContaining('百公里油耗：'), findsNothing);
    expect(find.textContaining('暂无，需要两次满油记录'), findsOneWidget);
  });

  testWidgets('VehicleProfilePage empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: VehicleProfilePage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('车辆档案'), findsOneWidget);
    expect(find.textContaining('还没有车辆档案'), findsOneWidget);
  });
}
