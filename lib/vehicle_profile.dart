/// DriveTrack v1.2.0 第 7 项：车辆档案模型（仅模型，不接线）。
///
/// 与现有全局油耗的关系（收口阶段才接线，本文件不改任何现有文件）：
/// - 现状是 profile.json 里唯一一对全局值（AppPrefs 的
///   fuelConsumptionLPer100Km / fuelPricePerLiter），fuel_page.dart 的
///   estimateFuel / summarizeMonthlyFuel 目前只认这一对全局值。
/// - 本文件只提供“每车一档”的档案与加油记录数据结构 + 纯函数，
///   不读 profile.json、不读 Store、不改 Trip / TripMeta。
/// - 收口阶段由协调员接线：Store 存取、Trip / TripMeta 加 vehicleId、
///   fuel_page 的估算 / 实测分支与按车汇总（见文件尾“收口接线清单”）。
///
/// 红线（写死在这里，调用方不得绕过）：
/// - 排量（displacementCc）与车重（weightKg）只作档案 / 分组维度，
///   绝不能拿它们编一个油耗公式、绝不能算出假数字。本文件没有任何
///   由排量 / 车重推导油耗的函数，调用方也不得另起一套。
/// - 品牌 / 型号是用户自填文本，不是官方车型库；本文件不提供车型
///   列表、不编价格、不编任何车型数据。
/// - 与 lib/vehicle_markers.dart 无关：那只是地图标记风格选择器，
///   其品牌风格明确写着“仅作风格区分，非官方授权模型”，绝不能当
///   车辆数据用；本文件的 brand 是用户自己填的档案文本，两者不互通。
/// - riderBikeKg（models.dart 的默认值 85）只是骑行功率估算用，
///   不是车重，不得与本文件的 weightKg 混用。
/// - 空字段口径与 fuel_page.dart 一致：空（null / 空串）= 未填写，
///   不参与计算、不显示、不按 0 算；数值字段 <= 0 在 fromJson 与
///   页面解析时一律视作未填写（null），不保存非法值。

/// 车辆模式：只分汽车 / 摩托。骑行不耗油，不建车辆档案；
/// 如需与 TripMode 对照：car -> TripMode.car，moto -> TripMode.moto。
enum VehicleMode { car, moto }

extension VehicleModeLabel on VehicleMode {
  String get key => name;
  String get label => switch (this) {
        VehicleMode.car => '汽车',
        VehicleMode.moto => '摩托',
      };
  static VehicleMode fromKey(String? k) => VehicleMode.values
      .firstWhere((e) => e.name == k, orElse: () => VehicleMode.car);
}

/// 解析数值输入：空串 = 未填写（null）；非空必须是 > 0 的数字，
/// 否则返回 null（调用方报“格式不对”，不保存非法值、不崩溃）。
/// 与 fuel_page.dart 的 parseFuelInput 口径一致。
double? parseVehicleNumber(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v <= 0) return null;
  return v;
}

/// 输入串是否合法：空（= 未填写）或 > 0 数字才合法。
bool isVehicleNumberValid(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  final v = double.tryParse(s);
  return v != null && v > 0;
}

double? _positiveDouble(dynamic v) {
  final d = (v as num?)?.toDouble();
  return (d != null && d > 0) ? d : null;
}

String? _nonEmptyString(dynamic v) {
  final s = (v as String?)?.trim();
  return (s != null && s.isNotEmpty) ? s : null;
}

/// 车辆档案。除 [id] 与 [name] 外全部可空。
class VehicleProfile {
  /// 档案 id（本机唯一，收口后 Store 持久化时沿用此 id，不改键名）。
  final String id;

  /// 名称（必填，用户自定，如“家里的车”；不强制等于品牌 + 型号）。
  final String name;

  /// 模式：汽车 / 摩托。
  final VehicleMode mode;

  /// 每车油耗（L/100km）。空 = 未填写，不参与估算、不按全局值
  /// 也不按 0 补；收口后的分支规则是：有每车油耗时用它，无则
  /// 回退全局值，全局值也没有时显示“未填写油耗/油价”。
  final double? consumptionLPer100Km;

  /// 油箱容量（L）。仅作档案显示，不参与任何油耗计算。
  final double? tankCapacityL;

  /// 品牌（用户自填文本，非官方授权模型、非车型库）。
  final String? brand;

  /// 型号（用户自填文本）。
  final String? model;

  /// 排量（cc，如 1500 表示 1500cc）。仅作档案 / 分组维度，
  /// 绝不用于推导油耗（见文件头红线）。
  final double? displacementCc;

  /// 车重（kg）。仅作档案 / 分组维度，绝不用于推导油耗；
  /// 与 models.dart 的 riderBikeKg（骑行功率估算）无关。
  final double? weightKg;

  /// 变速箱（用户自填文本，如“自动”“手动”，不做枚举、不校验）。
  final String? gearbox;

  /// 驱动形式（用户自填文本，如“前驱”“四驱”，不做枚举、不校验）。
  final String? drivetrain;

  /// 燃油标号（用户自填文本，如“95”，不做枚举、不校验、不编价格）。
  final String? fuelGrade;

  const VehicleProfile({
    required this.id,
    required this.name,
    this.mode = VehicleMode.car,
    this.consumptionLPer100Km,
    this.tankCapacityL,
    this.brand,
    this.model,
    this.displacementCc,
    this.weightKg,
    this.gearbox,
    this.drivetrain,
    this.fuelGrade,
  });

  /// 是否填了可用的每车油耗（> 0 才算填了）。
  bool get hasConsumption =>
      consumptionLPer100Km != null && consumptionLPer100Km! > 0;

  /// 仅返回已填字段的“标签 → 显示值”条目（页面直接按此渲染，
  /// 空字段自然不显示）。排量 / 车重只显示原值，不换算、不推导。
  List<MapEntry<String, String>> specEntries() {
    final entries = <MapEntry<String, String>>[];
    entries.add(MapEntry('模式', mode.label));
    final b = brand;
    if (b != null) entries.add(MapEntry('品牌', b));
    final m = model;
    if (m != null) entries.add(MapEntry('型号', m));
    final c = consumptionLPer100Km;
    if (c != null && c > 0) {
      entries.add(MapEntry('百公里油耗', '${_trimNum(c)} L/100km'));
    }
    final t = tankCapacityL;
    if (t != null && t > 0) entries.add(MapEntry('油箱容量', '${_trimNum(t)} L'));
    final d = displacementCc;
    if (d != null && d > 0) entries.add(MapEntry('排量', '${_trimNum(d)} cc'));
    final w = weightKg;
    if (w != null && w > 0) entries.add(MapEntry('车重', '${_trimNum(w)} kg'));
    final g = gearbox;
    if (g != null) entries.add(MapEntry('变速箱', g));
    final dr = drivetrain;
    if (dr != null) entries.add(MapEntry('驱动形式', dr));
    final fg = fuelGrade;
    if (fg != null) entries.add(MapEntry('燃油标号', fg));
    return entries;
  }

  VehicleProfile copyWith({
    String? id,
    String? name,
    VehicleMode? mode,
    Object? consumptionLPer100Km = _sentinel,
    Object? tankCapacityL = _sentinel,
    Object? brand = _sentinel,
    Object? model = _sentinel,
    Object? displacementCc = _sentinel,
    Object? weightKg = _sentinel,
    Object? gearbox = _sentinel,
    Object? drivetrain = _sentinel,
    Object? fuelGrade = _sentinel,
  }) =>
      VehicleProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        consumptionLPer100Km: consumptionLPer100Km == _sentinel
            ? this.consumptionLPer100Km
            : consumptionLPer100Km as double?,
        tankCapacityL: tankCapacityL == _sentinel
            ? this.tankCapacityL
            : tankCapacityL as double?,
        brand: brand == _sentinel ? this.brand : brand as String?,
        model: model == _sentinel ? this.model : model as String?,
        displacementCc: displacementCc == _sentinel
            ? this.displacementCc
            : displacementCc as double?,
        weightKg:
            weightKg == _sentinel ? this.weightKg : weightKg as double?,
        gearbox: gearbox == _sentinel ? this.gearbox : gearbox as String?,
        drivetrain:
            drivetrain == _sentinel ? this.drivetrain : drivetrain as String?,
        fuelGrade:
            fuelGrade == _sentinel ? this.fuelGrade : fuelGrade as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mode': mode.key,
        'consumptionLPer100Km': consumptionLPer100Km,
        'tankCapacityL': tankCapacityL,
        'brand': brand,
        'model': model,
        'displacementCc': displacementCc,
        'weightKg': weightKg,
        'gearbox': gearbox,
        'drivetrain': drivetrain,
        'fuelGrade': fuelGrade,
      };

  static VehicleProfile fromJson(Map<String, dynamic> j) => VehicleProfile(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        mode: VehicleModeLabel.fromKey(j['mode'] as String?),
        consumptionLPer100Km: _positiveDouble(j['consumptionLPer100Km']),
        tankCapacityL: _positiveDouble(j['tankCapacityL']),
        brand: _nonEmptyString(j['brand']),
        model: _nonEmptyString(j['model']),
        displacementCc: _positiveDouble(j['displacementCc']),
        weightKg: _positiveDouble(j['weightKg']),
        gearbox: _nonEmptyString(j['gearbox']),
        drivetrain: _nonEmptyString(j['drivetrain']),
        fuelGrade: _nonEmptyString(j['fuelGrade']),
      );
}

const Object _sentinel = Object();

String _trimNum(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00')
      ? s.substring(0, s.length - 3)
      : s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// 单条加油记录。金额与单价均为用户实填（或小票值），模型不反推、
/// 不补价：amount 为空时调用方可按 liters × pricePerLiter 现算
/// 展示（见 [FuelLog.effectiveAmount]），但那只是“已填两项的乘积”，
/// 不是估算油耗，也不是编价格。
class FuelLog {
  /// 记录 id（本机唯一）。
  final String id;

  /// 所属车辆 id（对应 VehicleProfile.id）。
  final String vehicleId;

  /// 加油日期（毫秒时间戳；页面按本地日期显示，不含时刻语义）。
  final int dateMs;

  /// 加油升数（L）。必须 > 0 才参与任何计算；<= 0 / 缺失时
  /// [isUsable] 为 false，该条不计入实测区间、不估算。
  final double liters;

  /// 单价（元/L），可空。空 = 未填写，不编价格。
  final double? pricePerLiter;

  /// 金额（元），可空。用户实填优先；为空且升数与单价齐全时
  /// [effectiveAmount] 返回两者乘积，否则为 null（不是 0）。
  final double? amount;

  /// 里程表读数（km），可空。实测区间要求起止两条满油记录
  /// 都有里程表且后者大于前者，否则该区间不算（见下）。
  final double? odometerKm;

  /// 是否加满。false = 不满油：只记账，不计入实测，
  /// 也不作为实测区间的起止点（但夹在两次满油之间的不满油
  /// 记录，其升数会计入该满油区间的总油量，见 measuredIntervals）。
  final bool isFullTank;

  const FuelLog({
    required this.id,
    required this.vehicleId,
    required this.dateMs,
    required this.liters,
    this.pricePerLiter,
    this.amount,
    this.odometerKm,
    this.isFullTank = false,
  });

  bool get isUsable => liters > 0;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(dateMs);

  /// 金额：实填优先；未填且升数与单价齐全时为乘积；否则 null。
  double? get effectiveAmount {
    final a = amount;
    if (a != null && a > 0) return a;
    final p = pricePerLiter;
    if (p != null && p > 0 && liters > 0) return liters * p;
    return null;
  }

  FuelLog copyWith({
    String? id,
    String? vehicleId,
    int? dateMs,
    double? liters,
    Object? pricePerLiter = _sentinel,
    Object? amount = _sentinel,
    Object? odometerKm = _sentinel,
    bool? isFullTank,
  }) =>
      FuelLog(
        id: id ?? this.id,
        vehicleId: vehicleId ?? this.vehicleId,
        dateMs: dateMs ?? this.dateMs,
        liters: liters ?? this.liters,
        pricePerLiter: pricePerLiter == _sentinel
            ? this.pricePerLiter
            : pricePerLiter as double?,
        amount: amount == _sentinel ? this.amount : amount as double?,
        odometerKm: odometerKm == _sentinel
            ? this.odometerKm
            : odometerKm as double?,
        isFullTank: isFullTank ?? this.isFullTank,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicleId': vehicleId,
        'dateMs': dateMs,
        'liters': liters,
        'pricePerLiter': pricePerLiter,
        'amount': amount,
        'odometerKm': odometerKm,
        'isFullTank': isFullTank,
      };

  static FuelLog fromJson(Map<String, dynamic> j) => FuelLog(
        id: (j['id'] as String?) ?? '',
        vehicleId: (j['vehicleId'] as String?) ?? '',
        dateMs: (j['dateMs'] as num?)?.toInt() ?? 0,
        liters: (j['liters'] as num?)?.toDouble() ?? 0,
        pricePerLiter: _positiveDouble(j['pricePerLiter']),
        amount: _positiveDouble(j['amount']),
        odometerKm: _positiveDouble(j['odometerKm']),
        isFullTank: (j['isFullTank'] as bool?) ?? false,
      );
}

/// 一段满油到满油的实测区间。
class MeasuredConsumptionInterval {
  /// 起点满油记录 id（该条本身的升数不计入本区间油量）。
  final String startLogId;

  /// 终点满油记录 id（该条及其中间不满油记录的升数计入油量）。
  final String endLogId;

  /// 区间里程（km）= 终点里程表 − 起点里程表，恒 > 0。
  final double distanceKm;

  /// 区间总油量（L）= 起点之后（含终点）所有记录升数之和。
  final double liters;

  /// 实测油耗（L/100km）= liters / distanceKm × 100。
  final double consumptionLPer100Km;

  const MeasuredConsumptionInterval({
    required this.startLogId,
    required this.endLogId,
    required this.distanceKm,
    required this.liters,
    required this.consumptionLPer100Km,
  });
}

/// 实测计算规则（唯一口径，测试以此为准）：
/// 1. 先按（日期，里程表，id）排序；只看同一车辆的记录
///    （调用方先按 vehicleId 过滤，或用 measuredConsumptionForVehicle）。
/// 2. 只有“满油 → 满油”的区间才算：取排序后相邻的两条满油记录
///    为起止点；起点本身的升数不计（那是上个区间的油），终点及
///    其中间所有不满油记录的升数全部计入本区间油量。
/// 3. 以下情况该区间不算、不估算、不补数：
///    - 起止任一满油记录缺里程表，或终点里程表 <= 起点里程表；
///    - 区间内任一条记录升数 <= 0 / 无效；
///    - 只有一条满油记录、只有不满油记录、或满油后只有不满油
///      而无下一个满油（尾段悬空不算）。
/// 4. 排序前第一条满油之前的记录（包括不满油）不属于任何区间。
/// 5. 返回的区间按时间顺序排列；不满油区间本身不作为独立区间返回。
List<MeasuredConsumptionInterval> measuredIntervals(List<FuelLog> logs) {
  final sorted = List<FuelLog>.from(logs)
    ..sort((a, b) {
      final byDate = a.dateMs.compareTo(b.dateMs);
      if (byDate != 0) return byDate;
      final ao = a.odometerKm, bo = b.odometerKm;
      if (ao != null && bo != null && ao != bo) return ao.compareTo(bo);
      return a.id.compareTo(b.id);
    });
  final fullIdx = <int>[];
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].isFullTank) fullIdx.add(i);
  }
  final out = <MeasuredConsumptionInterval>[];
  for (var k = 0; k + 1 < fullIdx.length; k++) {
    final start = sorted[fullIdx[k]];
    final end = sorted[fullIdx[k + 1]];
    final o0 = start.odometerKm, o1 = end.odometerKm;
    if (o0 == null || o1 == null || o1 <= o0) continue;
    var liters = 0.0;
    var valid = true;
    for (var i = fullIdx[k] + 1; i <= fullIdx[k + 1]; i++) {
      if (!sorted[i].isUsable) {
        valid = false;
        break;
      }
      liters += sorted[i].liters;
    }
    if (!valid || liters <= 0) continue;
    final dist = o1 - o0;
    out.add(MeasuredConsumptionInterval(
      startLogId: start.id,
      endLogId: end.id,
      distanceKm: dist,
      liters: liters,
      consumptionLPer100Km: liters / dist * 100,
    ));
  }
  return out;
}

/// 全部有效满油区间的加权实测油耗（总油量 / 总里程 × 100，
/// 不是各区间油耗的简单平均）。无有效区间时返回 null（不是 0、
/// 不回退估算值、不回退全局值——回退由收口阶段的调用方决定）。
double? measuredConsumption(List<FuelLog> logs) {
  final intervals = measuredIntervals(logs);
  if (intervals.isEmpty) return null;
  var liters = 0.0, dist = 0.0;
  for (final i in intervals) {
    liters += i.liters;
    dist += i.distanceKm;
  }
  if (dist <= 0 || liters <= 0) return null;
  return liters / dist * 100;
}

/// 按区间列表算加权实测（与 measuredConsumption 同口径，
/// 供已算出区间的调用方复用，避免重算）。
double? measuredConsumptionFromIntervals(
    List<MeasuredConsumptionInterval> intervals) {
  if (intervals.isEmpty) return null;
  var liters = 0.0, dist = 0.0;
  for (final i in intervals) {
    liters += i.liters;
    dist += i.distanceKm;
  }
  if (dist <= 0 || liters <= 0) return null;
  return liters / dist * 100;
}

/// 某车实测：先按 vehicleId 过滤再算；无有效区间返回 null。
double? measuredConsumptionForVehicle(List<FuelLog> logs, String vehicleId) =>
    measuredConsumption(logs.where((l) => l.vehicleId == vehicleId).toList());

/// 某车实测区间：先按 vehicleId 过滤再算。
List<MeasuredConsumptionInterval> measuredIntervalsForVehicle(
        List<FuelLog> logs, String vehicleId) =>
    measuredIntervals(logs.where((l) => l.vehicleId == vehicleId).toList());

/// 车辆 + 加油记录 + 默认车辆的集合（页面与收口 Store 共用此形状）。
///
/// JSON 键（收口 Store 持久化时建议沿用，不另起键名）：
///   'vehicles' : VehicleProfile.toJson() 列表
///   'fuelLogs' : FuelLog.toJson() 列表
///   'defaultVehicleId' : String?（未设默认 = null，不编默认车）
class VehicleLibrary {
  final List<VehicleProfile> vehicles;
  final List<FuelLog> fuelLogs;
  final String? defaultVehicleId;

  const VehicleLibrary({
    this.vehicles = const [],
    this.fuelLogs = const [],
    this.defaultVehicleId,
  });

  VehicleProfile? get defaultVehicle {
    final id = defaultVehicleId;
    if (id == null) return null;
    for (final v in vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<FuelLog> logsFor(String vehicleId) =>
      fuelLogs.where((l) => l.vehicleId == vehicleId).toList();

  double? measuredFor(String vehicleId) =>
      measuredConsumptionForVehicle(fuelLogs, vehicleId);

  VehicleLibrary copyWith({
    List<VehicleProfile>? vehicles,
    List<FuelLog>? fuelLogs,
    Object? defaultVehicleId = _sentinel,
  }) =>
      VehicleLibrary(
        vehicles: vehicles ?? this.vehicles,
        fuelLogs: fuelLogs ?? this.fuelLogs,
        defaultVehicleId: defaultVehicleId == _sentinel
            ? this.defaultVehicleId
            : defaultVehicleId as String?,
      );

  /// 删除车辆后的集合（页面删除确认文案与此行为一致）：
  /// - 该车档案删除；其全部加油记录一并删除（里程表 / 满油区间
  ///   只属于该车，留着无法归属，也不静默转给别的车）；
  /// - 若删的是默认车辆，默认随之取消（null），不自动另立默认；
  /// - 行程本身不在本集合里，不删行程；行程绑定处理见
  ///   [tripVehicleIdAfterVehicleDeleted]（回退全局值）。
  VehicleLibrary deleteVehicle(String vehicleId) => VehicleLibrary(
        vehicles: vehicles.where((v) => v.id != vehicleId).toList(),
        fuelLogs: fuelLogs.where((l) => l.vehicleId != vehicleId).toList(),
        defaultVehicleId:
            defaultVehicleId == vehicleId ? null : defaultVehicleId,
      );

  Map<String, dynamic> toJson() => {
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
        'fuelLogs': fuelLogs.map((l) => l.toJson()).toList(),
        'defaultVehicleId': defaultVehicleId,
      };

  static VehicleLibrary fromJson(Map<String, dynamic> j) {
    final vehicles = ((j['vehicles'] as List?) ?? [])
        .map((e) => VehicleProfile.fromJson(e as Map<String, dynamic>))
        .toList();
    final logs = ((j['fuelLogs'] as List?) ?? [])
        .map((e) => FuelLog.fromJson(e as Map<String, dynamic>))
        .toList();
    final def = (j['defaultVehicleId'] as String?)?.trim();
    final defOk = (def != null &&
            def.isNotEmpty &&
            vehicles.any((v) => v.id == def))
        ? def
        : null;
    return VehicleLibrary(
      vehicles: vehicles,
      fuelLogs: logs,
      defaultVehicleId: defOk,
    );
  }
}

/// 删除车辆后，某行程原先的 vehicleId 应变成什么：
/// 绑的是被删车辆 -> null（收口后含义：该行程回退全局油耗/油价，
/// 不删行程、不把行程转给别的车）；绑的是别的车 / 本来就为空
/// -> 原值不变。本函数是纯函数，供收口阶段批量改写
/// Trip / TripMeta 时调用。
String? tripVehicleIdAfterVehicleDeleted(
    String deletedVehicleId, String? tripVehicleId) =>
    tripVehicleId == deletedVehicleId ? null : tripVehicleId;

// ---------- 收口接线清单（本文件不执行，仅供协调员照单实施） ----------
// 1) Store（lib/store.dart，收口阶段改）：新增建议方法名
//    - Future<VehicleLibrary> loadVehicleLibrary()
//    - Future<void> saveVehicleLibrary(VehicleLibrary library)
//    持久化文件建议：vehicles.json（与 trips_index.json 同目录，
//    内容即 VehicleLibrary.toJson()）；旧存档无此文件时返回空集合。
//    另：AppPrefs 的全局油耗/油价键保持不动，作为回退值。
// 2) Trip / TripMeta（lib/models.dart、lib/store.dart，收口阶段改）：
//    - Trip 新增字段 vehicleId（String?，JSON 键 'vehicleId'，
//      缺键 = null = 回退全局值）；TripMeta 同理加 vehicleId
//      （JSON 键 'vehicleId'，缺键 = null）。
//    - saveTrip / updateTripSocial 等重建 Trip 的位置须原样透传
//      vehicleId，不得丢字段；删除车辆时用
//      tripVehicleIdAfterVehicleDeleted 批量回退绑定行程。
// 3) fuel_page.dart（收口阶段改）：估算 / 实测分支建议
//    - 行程卡片：vehicleId 有值且该车有每车油耗时用每车油耗；
//      否则用全局油耗/油价；实测值（measuredFor）有值时与估算值
//      并列显示并标注“实测（满油区间）”，无实测时不显示实测行。
//    - 当月汇总：按车分组汇总（每车油耗 / 实测分开展示），
//      未绑定车辆的行程进“未指定车辆（全局值）”组；全局值缺失
//      的组仍显示“未填写油耗/油价”，不按 0 算。
// 4) 入口（lib/main.dart 或设置页，收口阶段改）：在设置页合适位置
//    加“车辆档案”入口，推 VehicleProfilePage(initialProfiles: …,
//    initialFuelLogs: …, initialDefaultVehicleId: …,
//    onChanged: (library) => Store.saveVehicleLibrary(library))。
//    本文件不改底部导航、不改主题色、不改 slogan、不改图标。
