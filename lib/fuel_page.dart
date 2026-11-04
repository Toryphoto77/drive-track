/// 油耗费用（v0.1.7 追加项 4，仅汽车 / 摩托，骑行不做）。
///
/// 口径（写死在这里，各处复用同一套，不各自另算）：
/// - 行程油耗量（L）= 里程（km）× 百公里油耗（L/100km）/ 100；
/// - 油钱（元）= 油耗量（L）× 油价（元/L）。
/// - 里程一律复用 Trip.distanceM / TripMeta.distanceM（轨迹点逐段
///   haversine 累加），本文件不另算一套里程、不读轨迹点。
/// - 百公里油耗与油价默认都是空（null），不编默认值、不预设 8L
///   之类；两者任一为空或 <= 0 时不计算，所有油耗位置显示
///   “未填写油耗/油价”，绝不显示 0 或估算数。
/// - 仅汽车 / 摩托计入油耗；骑行不耗油，不显示油耗模块，
///   也不计入油耗 / 花费汇总。
/// - 当月汇总：按行程开始时间（本地年月）过滤当月；演示行程
///   不计入；总里程含全部模式（汽车 / 摩托 / 骑行），油耗与
///   花费仅汽车 / 摩托。汇总用的是当前填写的全局值回算历史
///   行程，不是逐次加油实测——各处都要标“按填写油耗估算”。
/// - 单组全局值：多辆车 / 换车场景暂不支持，换车需手动改设置，
///   改后历史行程的估算值会随新值重算。

import 'package:flutter/material.dart';
import 'app_notice.dart';

import 'models.dart';

/// 单次行程的油耗估算结果。null = 未填写（不计算）。
class FuelEstimate {
  final double liters;
  final double cost;
  const FuelEstimate({required this.liters, required this.cost});
}

/// 行程油耗量 = 里程 × 百公里油耗 / 100；油钱 = 油耗量 × 油价。
/// [consumptionLPer100Km] 或 [fuelPricePerLiter] 任一为空或 <= 0
/// 时返回 null（调用方显示“未填写油耗/油价”，不显示 0）。
FuelEstimate? estimateFuel({
  required double distanceKm,
  double? consumptionLPer100Km,
  double? fuelPricePerLiter,
}) {
  final c = consumptionLPer100Km;
  final p = fuelPricePerLiter;
  if (c == null || p == null || c <= 0 || p <= 0) return null;
  final liters = distanceKm * c / 100;
  return FuelEstimate(liters: liters, cost: liters * p);
}

/// 当月汇总的输入：一律用 TripMeta 的现成字段映射进来，
/// 不在这里读 store、不读轨迹文件。
/// v1.2.0：新增 [vehicleId]（null = 未绑定车辆，回退全局值）。
class FuelTripInput {
  final TripMode mode;
  final double distanceM;
  final int startMs;
  final bool demo;
  final String? vehicleId;
  const FuelTripInput({
    required this.mode,
    required this.distanceM,
    required this.startMs,
    this.demo = false,
    this.vehicleId,
  });
}

/// 当月汇总结果。fuel/cost 为 null = 未填写油耗/油价（不是 0）。
class MonthlyFuelSummary {
  final int year;
  final int month;
  final int tripCount; // 当月真实行程数（全部模式，演示除外）
  final double totalDistanceKm; // 含全部模式
  final double fuelDistanceKm; // 仅汽车 / 摩托的里程
  final double? totalLiters; // 仅汽车 / 摩托，未填写时为 null
  final double? totalCost; // 仅汽车 / 摩托，未填写时为 null
  const MonthlyFuelSummary({
    required this.year,
    required this.month,
    required this.tripCount,
    required this.totalDistanceKm,
    required this.fuelDistanceKm,
    required this.totalLiters,
    required this.totalCost,
  });

  bool get hasFuelSettings => totalLiters != null;
}

/// 按 [now] 的本地年月过滤 [trips]，演示行程除外。
MonthlyFuelSummary summarizeMonthlyFuel({
  required List<FuelTripInput> trips,
  required DateTime now,
  double? consumptionLPer100Km,
  double? fuelPricePerLiter,
}) {
  var count = 0;
  var totalKm = 0.0;
  var fuelKm = 0.0;
  for (final t in trips) {
    if (t.demo) continue;
    final d = DateTime.fromMillisecondsSinceEpoch(t.startMs);
    if (d.year != now.year || d.month != now.month) continue;
    count++;
    final km = t.distanceM / 1000;
    totalKm += km;
    if (t.mode == TripMode.car || t.mode == TripMode.moto) fuelKm += km;
  }
  final est = estimateFuel(
    distanceKm: fuelKm,
    consumptionLPer100Km: consumptionLPer100Km,
    fuelPricePerLiter: fuelPricePerLiter,
  );
  return MonthlyFuelSummary(
    year: now.year,
    month: now.month,
    tripCount: count,
    totalDistanceKm: totalKm,
    fuelDistanceKm: fuelKm,
    totalLiters: est?.liters,
    totalCost: est?.cost,
  );
}

/// v1.2.0：按车辆分组的区间汇总结果。只含汽车 / 摩托行程
/// （骑行不耗油，不进组）；演示行程不计入。
/// - [estimatedLiters]/[estimatedCost]：按每车油耗（有则用，无则
///   回退全局值）× 全局油价估算；任一缺失时为 null（不是 0）。
/// - [measuredLiters]：按该车实测油耗（满油区间加权，见
///   vehicle_profile.dart 的 measuredFor）× 本组里程；无实测区间
///   时为 null，无实测行不显示；[measuredCost] 为实测油量 × 全局
///   油价折算（全局油价未填时为 null），界面须注明是按全局油价折算。
/// - 未绑定车辆的行程统一进 label 为“未指定车辆（全局值）”的组，
///   该组无实测（加油记录只属于某车）。
class FuelGroupSummary {
  final String? vehicleId;
  final String label;
  final int tripCount;
  final double fuelDistanceKm;
  final double? estimatedLiters;
  final double? estimatedCost;
  final double? measuredLiters;
  final double? measuredCost;
  const FuelGroupSummary({
    required this.vehicleId,
    required this.label,
    required this.tripCount,
    required this.fuelDistanceKm,
    required this.estimatedLiters,
    required this.estimatedCost,
    required this.measuredLiters,
    required this.measuredCost,
  });
  bool get hasMeasured => measuredLiters != null;
}

/// v1.2.0：任意区间 + 按车辆分组汇总（单月汇总的推广版，
/// summarizeMonthlyFuel 保持原样不动作兼容）。
/// 区间为左闭右开：startMs <= 行程开始 < endMs；全部区间调用方
/// 传 startMs=0、endMs 为很大的未来值。排量 / 车重不参与计算。
List<FuelGroupSummary> summarizeFuelByVehicle({
  required List<FuelTripInput> trips,
  required int startMs,
  required int endMs,
  double? globalConsumptionLPer100Km,
  double? globalPricePerLiter,
  Map<String, double?> perVehicleConsumption = const {},
  Map<String, double?> measuredConsumptionByVehicle = const {},
  Map<String, String> vehicleNames = const {},
}) {
  final groups = <String?, List<FuelTripInput>>{};
  for (final t in trips) {
    if (t.demo) continue;
    if (t.mode != TripMode.car && t.mode != TripMode.moto) continue;
    if (t.startMs < startMs || t.startMs >= endMs) continue;
    final key = (t.vehicleId == null || t.vehicleId!.isEmpty) ? null : t.vehicleId;
    (groups[key] ??= []).add(t);
  }
  final out = <FuelGroupSummary>[];
  for (final entry in groups.entries) {
    final id = entry.key;
    final km = entry.value.fold(0.0, (a, t) => a + t.distanceM / 1000);
    double? perVehicle;
    if (id != null) {
      final c = perVehicleConsumption[id];
      if (c != null && c > 0) perVehicle = c;
    }
    final est = estimateFuel(
      distanceKm: km,
      consumptionLPer100Km: perVehicle ?? globalConsumptionLPer100Km,
      fuelPricePerLiter: globalPricePerLiter,
    );
    double? measuredLiters;
    double? measuredCost;
    if (id != null) {
      final mc = measuredConsumptionByVehicle[id];
      if (mc != null && mc > 0) {
        measuredLiters = km * mc / 100;
        if (globalPricePerLiter != null && globalPricePerLiter > 0) {
          measuredCost = measuredLiters * globalPricePerLiter;
        }
      }
    }
    out.add(FuelGroupSummary(
      vehicleId: id,
      label: id == null ? '未指定车辆（全局值）' : (vehicleNames[id] ?? '车辆 $id'),
      tripCount: entry.value.length,
      fuelDistanceKm: km,
      estimatedLiters: est?.liters,
      estimatedCost: est?.cost,
      measuredLiters: measuredLiters,
      measuredCost: measuredCost,
    ));
  }
  out.sort((a, b) => b.fuelDistanceKm.compareTo(a.fuelDistanceKm));
  return out;
}

/// 解析设置页输入：空串 = 未填写（null）；非空必须是 > 0 的数字，
/// 否则返回 null 并由调用方报“格式不对”，不保存非法值、不崩溃。
double? parseFuelInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v <= 0) return null;
  return v;
}

/// 输入串是否合法：空（= 未填写）或 > 0 数字才合法。
bool isFuelInputValid(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  final v = double.tryParse(s);
  return v != null && v > 0;
}

/// 油耗设置页（不依赖 AppPrefs，避免与 main.dart 循环引用）。
///
/// [initialConsumption] / [initialPrice] 由调用方从 profile.json
/// 读出后传入（默认都为空）；点“保存”调 [onSaved] 由调用方
/// 持久化；点“清空”把两项都存回空。页内不写文件。
class FuelSettingsPage extends StatefulWidget {
  final double? initialConsumption;
  final double? initialPrice;
  final void Function(double? consumption, double? price)? onSaved;

  const FuelSettingsPage({
    super.key,
    this.initialConsumption,
    this.initialPrice,
    this.onSaved,
  });

  @override
  State<FuelSettingsPage> createState() => _FuelSettingsPageState();
}

class _FuelSettingsPageState extends State<FuelSettingsPage> {
  late final TextEditingController _consumptionCtrl = TextEditingController(
    text: widget.initialConsumption == null ? '' : widget.initialConsumption.toString(),
  );
  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.initialPrice == null ? '' : widget.initialPrice.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _consumptionCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _save({bool clear = false}) {
    final cText = clear ? '' : _consumptionCtrl.text;
    final pText = clear ? '' : _priceCtrl.text;
    if (!isFuelInputValid(cText) || !isFuelInputValid(pText)) {
      setState(() => _error = '格式不对：只填大于 0 的数字，留空表示未填写。');
      return;
    }
    final c = parseFuelInput(cText);
    final p = parseFuelInput(pText);
    widget.onSaved?.call(c, p);
    if (mounted) {
      showAppNotice(context, clear ? '已清空油耗设置' : '油耗设置已保存', AppNoticeKind.success);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 只填一项时仍可保存，但行程与汇总仍显示“未填写油耗/油价”，
    // 因为计算要求两项齐全——这条在页内写明，不静默按一项算。
    final bothFilled =
        _consumptionCtrl.text.trim().isNotEmpty && _priceCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('油耗费用')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            '仅汽车 / 摩托可用，骑行不耗油、不显示油耗。',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '两项默认都为空，不预设数值；两项都填了之后，行程详情与当月汇总才自动计算。只填一项时仍显示“未填写油耗/油价”。',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _consumptionCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '百公里油耗（L/100km）',
              hintText: '未填写',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '油价（元/L）',
              hintText: '未填写',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 8),
          if (!bothFilled)
            const Text(
              '提示：两项都填了才计算，缺一项时所有油耗位置都显示“未填写油耗/油价”，不会按 0 或估算数显示。',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _save(),
            child: const Text('保存'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _save(clear: true),
            child: const Text('清空（恢复未填写）'),
          ),
          const SizedBox(height: 16),
          const Text(
            '计算公式：行程油耗量 = 里程 × 百公里油耗 / 100；油钱 = 油耗量 × 油价。',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            '这是按填写油耗估算，不是加油实测；实际油耗随路况、驾驶方式变化。单组全局设置，多辆车 / 换车场景暂不支持：换车请手动改这里，改后历史行程的估算值会随新值重算。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
