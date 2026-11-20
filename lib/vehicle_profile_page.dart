/// DriveTrack v1.2.0 第 7 项：车辆档案管理页（仅新增页面，不接线）。
/// v1.2.1 表单重做（仅本文件）：新增 / 编辑表单按组分段、
/// 模式大卡片二选一、数字项带单位后缀、行内报错、保存后回列表
/// 发顶部 app_notice；数据模型、油耗计算规则、删除规则均不动。
///
/// 本页不读 Store、不读 profile.json、不改任何现有文件；数据全部
/// 由调用方经构造函数传入，任何改动经 [VehicleProfilePage.onChanged]
/// 以完整 [VehicleLibrary] 回调给调用方持久化（收口阶段接
/// Store.saveVehicleLibrary；见 vehicle_profile.dart 尾部清单）。
///
/// 页面行为（与 vehicle_profile.dart 的模型口径一致）：
/// - 新增 / 编辑 / 删除车辆、选默认车辆；加油记录的新增 / 删除
///   （按车查看、按车新增）。
/// - 空字段就不显示、不参与计算：车辆卡片只渲染 specEntries()
///   返回的已填项；油耗估算仍由收口阶段的 fuel_page 分支决定，
///   本页不算行程油耗、不显示估算数。
/// - 实测只显示满油区间结果：有有效满油区间时显示
///   “实测 X.XX L/100km（N 段满油区间）”，否则显示
///   “暂无实测：需要两次满油记录”，绝不把不满油记录算成实测。
/// - 删除车辆确认文案（与 VehicleLibrary.deleteVehicle 行为一致）：
///   该车加油记录一并删除；行程本身不删除，已绑定该车的行程
///   回退全局油耗 / 油价（收口后表现为 vehicleId 置空）；
///   删的是默认车辆时默认随之取消。
/// - 排量与车重只作档案显示，表单下方明写“不用于推算油耗”；
///   品牌 / 型号为用户自填文本，本页不提供车型列表、不编数据；
///   本页与 vehicle_markers.dart 的地图车标风格选择无关。

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'card_style.dart';

import 'vehicle_profile.dart';

String _fmtDate(int dateMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(dateMs);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

String _fmtNum(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// 车辆档案管理页 Widget。
///
/// [initialProfiles] / [initialFuelLogs] / [initialDefaultVehicleId]
/// 为调用方读出的当前存档（收口前可传空列表先行展示空态）；
/// [onChanged] 在每次新增 / 编辑 / 删除车辆、改默认、新增 /
/// 删除加油记录后回调完整新集合，调用方负责持久化。
/// 本页内部也立即 setState，改动马上可见，不依赖调用方先回写。
class VehicleProfilePage extends StatefulWidget {
  final List<VehicleProfile> initialProfiles;
  final List<FuelLog> initialFuelLogs;
  final String? initialDefaultVehicleId;
  final ValueChanged<VehicleLibrary>? onChanged;

  const VehicleProfilePage({
    super.key,
    this.initialProfiles = const [],
    this.initialFuelLogs = const [],
    this.initialDefaultVehicleId,
    this.onChanged,
  });

  @override
  State<VehicleProfilePage> createState() => _VehicleProfilePageState();
}

class _VehicleProfilePageState extends State<VehicleProfilePage> {
  late VehicleLibrary _library = VehicleLibrary(
    vehicles: List<VehicleProfile>.from(widget.initialProfiles),
    fuelLogs: List<FuelLog>.from(widget.initialFuelLogs),
    defaultVehicleId: widget.initialDefaultVehicleId,
  );

  void _emit() => widget.onChanged?.call(_library);

  String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _editVehicle([VehicleProfile? existing]) async {
    final saved = await Navigator.push<VehicleProfile>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _VehicleEditPage(existing: existing, newId: _newId('v')),
      ),
    );
    if (saved == null || !mounted) return;
    // 保存前列表里没有该 id 即为新增，否则为编辑；提示文案据此区分。
    final isNew = !_library.vehicles.any((v) => v.id == saved.id);
    setState(() {
      final list = List<VehicleProfile>.from(_library.vehicles);
      final idx = list.indexWhere((v) => v.id == saved.id);
      if (idx >= 0) {
        list[idx] = saved;
      } else {
        list.add(saved);
      }
      _library = _library.copyWith(vehicles: list);
    });
    _emit();
    // 回到列表后给顶部自动消失提示（app_notice；
    // 提示挂根 Overlay，编辑页已 pop 也不会被吞掉）。
    if (mounted) {
      final s = S.of(context);
      showAppNotice(
        context,
        isNew
            ? s.t('已新增车辆“${saved.name}”。', 'Vehicle "${saved.name}" added.')
            : s.t('已保存车辆“${saved.name}”。', 'Vehicle "${saved.name}" saved.'),
        AppNoticeKind.success,
      );
    }
  }

  Future<void> _deleteVehicle(VehicleProfile v) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('删除车辆？', 'Delete vehicle?')),
        content: Text(
          '${s.t('将删除“${v.name}”的档案及其全部加油记录。', 'This deletes the profile of "${v.name}" and all its fuel logs.')}\n\n'
          '${s.t('行程本身不会被删除：已绑定该车的行程会回退为全局油耗 / 油价设置。', 'Trips are not deleted: trips linked to this vehicle fall back to the global fuel consumption and price.')}'
          '${_library.defaultVehicleId == v.id ? s.t('\n\n该车是当前默认车辆，删除后默认随之取消。', '\n\nThis is the default vehicle; the default will be cleared as well.') : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _library = _library.deleteVehicle(v.id));
    _emit();
    if (mounted) {
      showAppNotice(
        context,
        s.t('已删除“${v.name}”，其加油记录一并删除。',
            'Deleted "${v.name}" and its fuel logs.'),
        AppNoticeKind.success,
      );
    }
  }

  void _setDefault(String? id) {
    setState(() => _library = _library.copyWith(defaultVehicleId: id));
    _emit();
  }

  Future<void> _openFuelLogs(VehicleProfile v) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _FuelLogListPage(
          vehicle: v,
          logs: _library.logsFor(v.id),
          onChanged: (logs) {
            setState(() {
              final rest = _library.fuelLogs
                  .where((l) => l.vehicleId != v.id)
                  .toList();
              _library = _library.copyWith(fuelLogs: [...rest, ...logs]);
            });
            _emit();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final vehicles = _library.vehicles;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(s.t('车辆档案', 'Vehicles')),
        actions: [
          Semantics(
            label: s.t('新增车辆', 'Add vehicle'),
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _editVehicle(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 24)),
        children: [
          Text(
            s.t('行程油耗优先用所绑车辆的油耗，未绑定或未填时回退全局值。',
                'Trip fuel use prefers the linked vehicle; unlinked or blank falls back to the global value.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            s.t('空字段不显示、不参与计算。排量与车重只作档案记录，不用于推算油耗。',
                "Blank fields are hidden and not used. Displacement and weight are recorded for reference only, not used to estimate fuel use."),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            s.t(
              '默认车辆用于新行程的油耗估算；未设默认时用全局值。'
              '删除车辆时其加油记录一并删除，行程本身不删除。',
              'The default vehicle is used to estimate fuel use for new trips; without one the global value applies. Deleting a vehicle also deletes its fuel logs, but not the trips.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (vehicles.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  s.t('还没有车辆档案。点右上角 + 新增一辆车，只填名称也能保存。',
                      'No vehicles yet. Tap + in the top right to add one; a name alone is enough.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          for (final v in vehicles) _vehicleCard(v, s),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _editVehicle(),
            icon: const Icon(Icons.add),
            label: Text(s.t('新增车辆', 'Add vehicle')),
          ),
        ],
      ),
    );
  }

  Widget _vehicleCard(VehicleProfile v, S s) {
    final isDefault = _library.defaultVehicleId == v.id;
    final logs = _library.logsFor(v.id);
    final measured = _library.measuredFor(v.id);
    final intervals = measuredIntervalsForVehicle(_library.fuelLogs, v.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isDefault)
                  Chip(
                    label: Text(s.t('默认', 'Default')),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  TextButton(
                    onPressed: () => _setDefault(v.id),
                    child: Text(s.t('设为默认', 'Set default')),
                  ),
              ],
            ),
            // 只渲染已填项：specEntries() 已跳过空字段。
            for (final e in v.specEntries())
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  s.t('${e.key}：${e.value}', '${e.key}: ${e.value}'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                measured == null
                    ? s.t('实测：暂无，需要两次满油记录',
                        'Measured: none yet, needs two full-tank logs')
                    : s.t(
                        '实测：${_fmtNum(measured)} L/100km（${intervals.length} 段满油区间）',
                        'Measured: ${_fmtNum(measured)} L/100km (${intervals.length} full-tank intervals)',
                      ),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            Text(
              s.t('加油记录：${logs.length} 条（不满油记录只记账，不计入实测）',
                  'Fuel logs: ${logs.length} (partial fills are recorded but not measured)'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _openFuelLogs(v),
                  child: Text(s.t('加油记录', 'Fuel logs')),
                ),
                OutlinedButton(
                  onPressed: () => _editVehicle(v),
                  child: Text(s.t('编辑', 'Edit')),
                ),
                if (isDefault)
                  OutlinedButton(
                    onPressed: () => _setDefault(null),
                    child: Text(s.t('取消默认', 'Clear default')),
                  ),
                TextButton(
                  onPressed: () => _deleteVehicle(v),
                  child: Text(
                    s.t('删除', 'Delete'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 车辆新增 / 编辑表单（本文件内私有页，新增与编辑共用，v1.2.1 重做）。
/// 分段：基本信息（名称 / 模式）→ 动力档案（品牌型号 / 排量 /
/// 车重 / 变速箱 / 驱动形式 / 燃油标号）→ 油耗（每车油耗 / 油箱容量）。
/// 名称必填；其余全部可空，留空 = 未填写，占位文案统一为
/// “未填写（可不填）”；数值字段只接受 > 0 的数字，否则行内报错
/// 且不保存、不闪退。模式用大卡片二选一，不用小下拉。
/// 排量表单单位写 mL：1 mL = 1 cc，数值与模型字段 displacementCc
/// 完全相同，只换显示单位，不换算；排量 / 车重仍只作档案，
/// 不参与任何油耗计算。保存成功由调用方（列表页 _editVehicle）
/// 回列表后发顶部 app_notice 提示，本页自身不发提示。
class _VehicleEditPage extends StatefulWidget {
  final VehicleProfile? existing;
  final String newId;
  const _VehicleEditPage({this.existing, required this.newId});

  @override
  State<_VehicleEditPage> createState() => _VehicleEditPageState();
}

class _VehicleEditPageState extends State<_VehicleEditPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late VehicleMode _mode = widget.existing?.mode ?? VehicleMode.car;
  late final TextEditingController _consumption = TextEditingController(
    text: _numText(widget.existing?.consumptionLPer100Km),
  );
  late final TextEditingController _tank = TextEditingController(
    text: _numText(widget.existing?.tankCapacityL),
  );
  late final TextEditingController _brand = TextEditingController(
    text: widget.existing?.brand ?? '',
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.existing?.model ?? '',
  );
  late final TextEditingController _displacement = TextEditingController(
    text: _numText(widget.existing?.displacementCc),
  );
  late final TextEditingController _weight = TextEditingController(
    text: _numText(widget.existing?.weightKg),
  );
  late final TextEditingController _gearbox = TextEditingController(
    text: widget.existing?.gearbox ?? '',
  );
  late final TextEditingController _drivetrain = TextEditingController(
    text: widget.existing?.drivetrain ?? '',
  );
  late final TextEditingController _fuelGrade = TextEditingController(
    text: widget.existing?.fuelGrade ?? '',
  );
  // 行内报错：名称一条、每个数字项一条，互不串位；保存时全量校验，
  // 任一非空即不 pop、不保存。输入改正后对应报错即时清除。
  String? _nameError;
  String? _consumptionError;
  String? _tankError;
  String? _displacementError;
  String? _weightError;

  static String _numText(double? v) => v == null ? '' : _fmtNum(v);

  static String? _numberError(String raw, String label, S s) {
    if (!isVehicleNumberValid(raw)) {
      return s.t('$label格式不对：只填大于 0 的数字，留空表示未填写。',
          '$label is invalid: enter a number greater than 0, or leave it blank.');
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _consumption.dispose();
    _tank.dispose();
    _brand.dispose();
    _model.dispose();
    _displacement.dispose();
    _weight.dispose();
    _gearbox.dispose();
    _drivetrain.dispose();
    _fuelGrade.dispose();
    super.dispose();
  }

  void _save() {
    final s = S.of(context);
    final name = _name.text.trim();
    // 全量行内校验：名称空、任一数字非法都只亮对应行的报错，
    // 不 pop、不保存、不闪退。
    setState(() {
      _nameError = name.isEmpty ? s.t('请填写车辆名称。', 'Enter a vehicle name.') : null;
      _consumptionError =
          _numberError(_consumption.text, s.t('百公里油耗', 'Fuel consumption'), s);
      _tankError = _numberError(_tank.text, s.t('油箱容量', 'Tank capacity'), s);
      _displacementError =
          _numberError(_displacement.text, s.t('排量', 'Displacement'), s);
      _weightError = _numberError(_weight.text, s.t('车重', 'Weight'), s);
    });
    if (_nameError != null ||
        _consumptionError != null ||
        _tankError != null ||
        _displacementError != null ||
        _weightError != null) {
      return;
    }
    String? text(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    Navigator.pop(
      context,
      VehicleProfile(
        id: widget.existing?.id ?? widget.newId,
        name: name,
        mode: _mode,
        consumptionLPer100Km: parseVehicleNumber(_consumption.text),
        tankCapacityL: parseVehicleNumber(_tank.text),
        brand: text(_brand),
        model: text(_model),
        displacementCc: parseVehicleNumber(_displacement.text),
        weightKg: parseVehicleNumber(_weight.text),
        gearbox: text(_gearbox),
        drivetrain: text(_drivetrain),
        fuelGrade: text(_fuelGrade),
      ),
    );
  }

  // 单个输入行：标签 + 带单位后缀的输入框 + 行内报错（有错才占行）。
  // 可空项占位统一写“未填写（可不填）”，不逼填；名称为必填项，
  // 占位仍用示例，不套可空文案。onChanged 由调用方传入，用于
  // 即时清除/刷新该行报错；数字行只在值变合法时清错，非法时
  // 立即亮行内提示，不等点保存。
  Widget _field(
    S s,
    TextEditingController c,
    String label, {
    TextInputType? keyboardType,
    String? hint,
    String? suffix,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: c,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint ?? s.t('未填写（可不填）', 'Not set (optional)'),
              suffixText: suffix,
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE10600), width: 1.5),
              ),
              errorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
              ),
            ),
            onChanged: onChanged,
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  // 分段卡：红条 + 16 号粗体段标题 + 统一大卡（#1E1E1E、圆角 26、
  // 白 14% 细边，与 App 其余页面卡片一致）。
  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: const Color(0xFFE10600)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DriveTrackCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // 模式大卡片二选一：整张可点，选中态红边 + 红底淡 tint + 红对勾。
  Widget _modeCard(
    VehicleMode mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE10600).withValues(alpha: 0.12)
                : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE10600)
                  : Colors.white.withValues(alpha: 0.14),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 28,
                    color: selected ? const Color(0xFFE10600) : Colors.white70,
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? const Color(0xFFE10600) : Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(editing
            ? s.t('编辑车辆', 'Edit vehicle')
            : s.t('新增车辆', 'Add vehicle')),
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 24)),
        children: [
          Text(
            s.t('除名称外全部可空。', 'Everything except the name is optional.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // 基本信息：名称 + 模式大卡片二选一。
          _section(s.t('基本信息', 'Basics'), [
            _field(
              s,
              _name,
              s.t('名称 *', 'Name *'),
              hint: s.t('如：家里的车', 'e.g. Family car'),
              error: _nameError,
              onChanged: (v) {
                if (_nameError != null && v.trim().isNotEmpty) {
                  setState(() => _nameError = null);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.t('模式', 'Mode'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _modeCard(VehicleMode.car, Icons.directions_car,
                      s.t('汽车', 'Car'), s.t('四轮车', 'Four wheels')),
                  const SizedBox(width: 12),
                  _modeCard(VehicleMode.moto, Icons.motorcycle,
                      s.t('摩托', 'Motorcycle'), s.t('两轮摩托', 'Two wheels')),
                ],
              ),
            ),
          ]),
          // 动力档案：品牌型号 / 排量 / 车重 / 变速箱 / 驱动形式 / 燃油标号。
          _section(s.t('动力档案', 'Powertrain'), [
            _field(s, _brand, s.t('品牌', 'Brand')),
            _field(s, _model, s.t('型号', 'Model')),
            _field(
              s,
              _displacement,
              s.t('排量', 'Displacement'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              suffix: 'mL',
              error: _displacementError,
              onChanged: (v) => setState(() => _displacementError =
                  _numberError(v, s.t('排量', 'Displacement'), s)),
            ),
            _field(
              s,
              _weight,
              s.t('车重', 'Weight'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              suffix: 'kg',
              error: _weightError,
              onChanged: (v) => setState(() => _weightError =
                  _numberError(v, s.t('车重', 'Weight'), s)),
            ),
            _field(s, _gearbox, s.t('变速箱', 'Gearbox')),
            _field(s, _drivetrain, s.t('驱动形式', 'Drivetrain')),
            _field(s, _fuelGrade, s.t('燃油标号', 'Fuel grade')),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                s.t(
                  '排量与车重只作档案记录，不用于推算油耗。'
                  '排量单位 mL 与 cc 数值相同，不换算。',
                  'Displacement and weight are recorded for reference only, not used to estimate fuel use. Displacement in mL equals cc, with no conversion.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ]),
          // 油耗：每车油耗 / 油箱容量。
          _section(s.t('油耗', 'Fuel'), [
            _field(
              s,
              _consumption,
              s.t('每车油耗', 'Fuel consumption'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              suffix: 'L/100km',
              error: _consumptionError,
              onChanged: (v) => setState(() => _consumptionError = _numberError(
                  v, s.t('百公里油耗', 'Fuel consumption'), s)),
            ),
            _field(
              s,
              _tank,
              s.t('油箱容量', 'Tank capacity'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              suffix: 'L',
              error: _tankError,
              onChanged: (v) => setState(() =>
                  _tankError = _numberError(v, s.t('油箱容量', 'Tank capacity'), s)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                s.t('未填写时行程油耗回退全局值。',
                    'When blank, trips fall back to the global fuel consumption.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ]),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE10600),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _save,
              child: Text(s.t('保存', 'Save'), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 某车的加油记录列表 + 新增 / 删除（本文件内私有页）。
/// 新增表单：升数必填 > 0；单价 / 金额 / 里程表可空（> 0 才有效）；
/// 是否加满默认关，文案明写只有满油到满油的区间才算实测。
class _FuelLogListPage extends StatefulWidget {
  final VehicleProfile vehicle;
  final List<FuelLog> logs;
  final ValueChanged<List<FuelLog>> onChanged;
  const _FuelLogListPage({
    required this.vehicle,
    required this.logs,
    required this.onChanged,
  });

  @override
  State<_FuelLogListPage> createState() => _FuelLogListPageState();
}

class _FuelLogListPageState extends State<_FuelLogListPage> {
  late List<FuelLog> _logs = List<FuelLog>.from(widget.logs)
    ..sort((a, b) => a.dateMs.compareTo(b.dateMs));

  void _emit() => widget.onChanged(_logs);

  Future<void> _addLog() async {
    final log = await showDialog<FuelLog>(
      context: context,
      builder: (ctx) => _FuelLogDialog(
        vehicleId: widget.vehicle.id,
        newId: 'f${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (log == null || !mounted) return;
    setState(() {
      _logs = [..._logs, log]..sort((a, b) => a.dateMs.compareTo(b.dateMs));
    });
    _emit();
  }

  Future<void> _deleteLog(FuelLog log) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('删除这条加油记录？', 'Delete this fuel log?')),
        content: Text(s.t('删除后实测区间会重新计算。',
            'Measured intervals will be recalculated after deleting.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _logs = _logs.where((l) => l.id != log.id).toList());
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final measured = measuredConsumption(_logs);
    final intervals = measuredIntervals(_logs);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
          title: Text(s.t('${widget.vehicle.name} · 加油记录',
              '${widget.vehicle.name} · Fuel logs'))),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 24)),
        children: [
          Text(
            measured == null
                ? s.t('实测：暂无，需要两次满油记录',
                    'Measured: none yet, needs two full-tank logs')
                : s.t(
                    '实测：${_fmtNum(measured)} L/100km（${intervals.length} 段满油区间）',
                    'Measured: ${_fmtNum(measured)} L/100km (${intervals.length} full-tank intervals)',
                  ),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            s.t(
              '只有满油到满油的区间才算实测；不满油记录只记账。'
              '满油区间要求起止两条记录都有里程表且后者大于前者。',
              'Only full-tank to full-tank intervals count as measured; partial fills are recorded only. A full-tank interval requires an odometer on both logs, with the later one higher.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_logs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  s.t('还没有加油记录。点下方“新增加油记录”记第一笔。',
                      'No fuel logs yet. Tap "Add fuel log" below to record the first one.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          for (final l in _logs)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  '${_fmtDate(l.dateMs)} · ${_fmtNum(l.liters)} L${l.isFullTank ? s.t(' · 加满', ' · Full') : s.t(' · 未满油', ' · Partial')}',
                ),
                subtitle: Text(
                  [
                    if (l.odometerKm != null)
                      s.t('里程表 ${_fmtNum(l.odometerKm!)} km',
                          'Odometer ${_fmtNum(l.odometerKm!)} km'),
                    if (l.pricePerLiter != null)
                      s.t('单价 ${_fmtNum(l.pricePerLiter!)} 元/L',
                          'Price ¥${_fmtNum(l.pricePerLiter!)}/L'),
                    if (l.effectiveAmount != null)
                      s.t('金额 ${_fmtNum(l.effectiveAmount!)} 元',
                          'Amount ¥${_fmtNum(l.effectiveAmount!)}'),
                  ].join(' · '),
                ),
                trailing: Semantics(
                  label: s.t('删除记录', 'Delete log'),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteLog(l),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addLog,
            icon: const Icon(Icons.add),
            label: Text(s.t('新增加油记录', 'Add fuel log')),
          ),
        ],
      ),
    );
  }
}

class _FuelLogDialog extends StatefulWidget {
  final String vehicleId;
  final String newId;
  const _FuelLogDialog({required this.vehicleId, required this.newId});

  @override
  State<_FuelLogDialog> createState() => _FuelLogDialogState();
}

class _FuelLogDialogState extends State<_FuelLogDialog> {
  DateTime _date = DateTime.now();
  final _liters = TextEditingController();
  final _price = TextEditingController();
  final _amount = TextEditingController();
  final _odometer = TextEditingController();
  bool _full = false;
  String? _error;

  @override
  void dispose() {
    _liters.dispose();
    _price.dispose();
    _amount.dispose();
    _odometer.dispose();
    super.dispose();
  }

  void _save() {
    final s = S.of(context);
    if (!isVehicleNumberValid(_liters.text) ||
        parseVehicleNumber(_liters.text) == null) {
      setState(() => _error = s.t('升数必填，且必须是大于 0 的数字。',
          'Liters are required and must be greater than 0.'));
      return;
    }
    for (final e in {
      s.t('单价', 'Price'): _price.text,
      s.t('金额', 'Amount'): _amount.text,
      s.t('里程表', 'Odometer'): _odometer.text,
    }.entries) {
      if (!isVehicleNumberValid(e.value)) {
        setState(() => _error = s.t(
            '${e.key}格式不对：只填大于 0 的数字，留空表示未填写。',
            '${e.key} is invalid: enter a number greater than 0, or leave it blank.'));
        return;
      }
    }
    Navigator.pop(
      context,
      FuelLog(
        id: widget.newId,
        vehicleId: widget.vehicleId,
        dateMs: DateTime(
          _date.year,
          _date.month,
          _date.day,
        ).millisecondsSinceEpoch,
        liters: parseVehicleNumber(_liters.text)!,
        pricePerLiter: parseVehicleNumber(_price.text),
        amount: parseVehicleNumber(_amount.text),
        odometerKm: parseVehicleNumber(_odometer.text),
        isFullTank: _full,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('新增加油记录', 'Add fuel log')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('日期', 'Date')),
              trailing: Text(
                _fmtDate(
                  DateTime(
                    _date.year,
                    _date.month,
                    _date.day,
                  ).millisecondsSinceEpoch,
                ),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            TextField(
              controller: _liters,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: s.t('升数（L）*', 'Liters (L) *'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: s.t('单价（元/L）', 'Price (CNY/L)'),
                hintText: s.t('未填写', 'Not set'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: s.t('金额（元）', 'Amount (CNY)'),
                hintText: s.t('未填写', 'Not set'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _odometer,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: s.t('里程表（km）', 'Odometer (km)'),
                hintText: s.t('未填写', 'Not set'),
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('这次加满了', 'Filled up this time')),
              subtitle: Text(s.t('只有满油到满油的区间才算实测；不满油只记账。',
                  'Only full-tank to full-tank intervals count as measured; partial fills are recorded only.')),
              value: _full,
              onChanged: (v) => setState(() => _full = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('取消', 'Cancel')),
        ),
        FilledButton(
            onPressed: _save, child: Text(s.t('保存', 'Save'))),
      ],
    );
  }
}
