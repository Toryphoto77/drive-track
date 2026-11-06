import 'package:flutter/material.dart';
import 'app_notice.dart';

import 'app_icon_choice.dart';
import 'models.dart';
import 'vehicle_markers.dart';

/// 主题设置子页（v0.1.7：全局黑色，不再分昼夜）。
///
/// 全 App 强制全局黑色：背景纯黑、文字白色系、卡片深色；
/// 主题设置只换强调色（主题色），不换底色，不提供昼夜档位、
/// 不随系统亮度。旧存档里若有 themeMode='light'/'system'，
/// 加载时一律忽略、按黑色处理。
/// 本页用 [DriveTrackTheme.dark] 包住整个 Scaffold 做即时预览。
/// 全 App 跟随要靠总协调接线（见文末接线清单）：MaterialApp 只传
/// 黑色 ThemeData，themeMode 固定 dark，否则别处可能随系统变浅。
///
/// 车队配色：以下 11 个预设颜色均为自设近似色，不是任何车队的官方
/// 配色表；页内有小字声明，绝不使用官方 Logo 图片、不编造品牌授权。
/// 自定义颜色入口：色板（预设圆点）+ 十六进制输入，非法值只报错、
/// 不崩溃、不改当前主题色。

// ------------------------------------------------------------------
// 数据模型与持久化键（总协调接入 store / AppPrefs 时照此键名写）
// ------------------------------------------------------------------
//
// 建议全部写进现有 profile.json（与 AppPrefs 同一文件，不另起文件，
// 避免主题散在两处）：
//   'themeAccent' : '#RRGGBB'                    （新键；旧键 'theme' 仅作
//                                                迁移兜底：新键缺失时读旧键）
//   'themePreset' : 预设 id，如 'ferrari'，自定义时为 'custom'
//                                                （新键，可选，用于回显选中态）
// 兼容：旧版 profile.json 只有 'theme' 时，accent 取旧键；旧键
// 'themeMode'（'light'/'dark'/'system'）一律忽略，全 App 强制黑色。
//
// class ThemeChoice 就是以上字段的内存模型，可直接 toJson/fromJson
// 进 profile.json；总协调在 AppPrefs.load/save 里只写这两个字段，
// 不需要为主题另建 Store 方法。

/// 主题选择：主题色 + 是否自定义（用于回显选中态）。无昼夜档位字段。
class ThemeChoice {
  final Color accent;
  final String presetId; // 预设 id，自定义时为 'custom'

  const ThemeChoice({
    required this.accent,
    required this.presetId,
  });

  static const ThemeChoice defaults = ThemeChoice(
    accent: Color(0xFFE10600),
    presetId: 'ferrari',
  );

  Map<String, dynamic> toJson() => {
        'themeAccent': '#${accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        'themePreset': presetId,
      };

  static ThemeChoice fromJson(Map<String, dynamic> j) {
    // 旧 themeMode 键有意不读：light/system 旧档位一律按黑色处理。
    // 新键缺失时读旧键 'theme' 迁移；都缺失时用默认法拉利红。
    final hex = (j['themeAccent'] as String?) ?? (j['theme'] as String?);
    final accent = parseHexColor(hex) ?? const Color(0xFFE10600);
    return ThemeChoice(
      accent: accent,
      presetId: (j['themePreset'] as String?) ?? 'custom',
    );
  }
}

/// 严格解析 #RRGGBB（允许省略 #，不接受 3 位 / 8 位 / 非十六进制）。
/// 非法返回 null，调用方只显示错误、不抛异常、不崩溃。
Color? parseHexColor(String? raw) {
  if (raw == null) return null;
  final hex = raw.trim().replaceFirst('#', '');
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// 一个车队主题色预设：id（存 themePreset 用）+ 中文名 + 自设近似色。
class ThemePreset {
  final String id;
  final String name;
  final Color color;
  const ThemePreset(this.id, this.name, this.color);
}

/// F1 车队主题色预设（自设近似色，非官方配色表；无官方 Logo）。
class F1ThemePresets {
  static const List<ThemePreset> all = [
    ThemePreset('ferrari', '法拉利红', Color(0xFFE10600)),
    ThemePreset('mclaren', '迈凯伦木瓜橙', Color(0xFFFF8000)),
    ThemePreset('redbull', '红牛深蓝', Color(0xFF12184A)),
    ThemePreset('mercedes', '梅赛德斯绿松', Color(0xFF00A19B)),
    ThemePreset('astonmartin', '阿斯顿马丁绿', Color(0xFF006F62)),
    ThemePreset('alpine', 'Alpine 蓝', Color(0xFF0090FF)),
    ThemePreset('williams', '威廉姆斯蓝', Color(0xFF002654)),
    ThemePreset('racingbulls', 'Racing Bulls', Color(0xFF6A9ED6)),
    ThemePreset('haas', '哈斯', Color(0xFF8A8D8F)),
    ThemePreset('sauber', '索伯/奥迪', Color(0xFF52E252)),
    ThemePreset('cadillac', '凯迪拉克', Color(0xFFD9B45B)),
  ];

  static ThemePreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// 全局黑色唯一配色：背景纯黑、文字白色系、卡片深色、AppBar、按钮只换强调色。
class DriveTrackTheme {
  DriveTrackTheme._();

  static ThemeData dark(Color accent) {
    const bg = Color(0xFF121212);
    const card = Color(0xFF1E1E1E);
    const text = Color(0xFFFFFFFF);
    const secondary = Color(0xFFFFFFFF70);
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(primary: accent, onSurface: text, surface: bg),
      scaffoldBackgroundColor: bg,
      cardColor: card,
      cardTheme: const CardThemeData(color: card),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        centerTitle: true,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text, fontSize: 16),
        bodyMedium: TextStyle(color: text, fontSize: 14),
        bodySmall: TextStyle(color: secondary, fontSize: 12),
        titleMedium: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(color: secondary, fontSize: 13),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent.withValues(alpha: 0.4) : null),
      ),
    );
  }

  /// 强制全局黑色：不分档位、不随系统亮度，只换强调色。
  static ThemeData resolve(Color accent) => DriveTrackTheme.dark(accent);
}

/// 主题设置子页。
///
/// [initial] 为已存选择（总协调从 profile.json 读出后传入）；
/// 选择变化时调 [onAccentChanged]，由总协调持久化并应用到
/// MaterialApp；本页内部也立即 setState 做预览。
/// 主题设置内的“地图车标”分区（v1.0.2：第 8 项从设置首页移入此处）。
///
/// 原设置首页“地图车标”入口已删，改由本分区承接：同一分区内切
/// 汽车 / 摩托 / 自行车三档，分别选轿车/跑车、摩托品牌风格、
/// 自行车类型；预览即新版俯视 3D 车标（见 vehicle_markers.dart）。
/// [initial] 为已存选择；[onChanged] 由总协调持久化到 profile.json
/// 的 vehicleMarkerCar / vehicleMarkerMoto / vehicleMarkerBike 三键。
class VehicleMarkerSettingsSection extends StatefulWidget {
  final VehicleMarkerSelection initial;
  final ValueChanged<VehicleMarkerSelection>? onChanged;
  final Color accentColor;

  const VehicleMarkerSettingsSection({
    super.key,
    this.initial = const VehicleMarkerSelection(),
    this.onChanged,
    this.accentColor = const Color(0xFFE10600),
  });

  @override
  State<VehicleMarkerSettingsSection> createState() =>
      _VehicleMarkerSettingsSectionState();
}

class _VehicleMarkerSettingsSectionState
    extends State<VehicleMarkerSettingsSection> {
  late VehicleMarkerSelection _sel = widget.initial;
  TripMode _tab = TripMode.car;

  VehicleMarkerSelection _selectionForRow(String key) => switch (_tab) {
        TripMode.car => _sel.copyWith(car: CarMarkerStyleLabel.fromKey(key)),
        TripMode.moto => _sel.copyWith(moto: MotoMarkerStyleLabel.fromKey(key)),
        TripMode.bike => _sel.copyWith(bike: BikeMarkerStyleLabel.fromKey(key)),
      };

  void _pick(TripMode mode, String key) {
    setState(() {
      _sel = switch (mode) {
        TripMode.car => _sel.copyWith(car: CarMarkerStyleLabel.fromKey(key)),
        TripMode.moto => _sel.copyWith(moto: MotoMarkerStyleLabel.fromKey(key)),
        TripMode.bike => _sel.copyWith(bike: BikeMarkerStyleLabel.fromKey(key)),
      };
    });
    widget.onChanged?.call(_sel);
  }

  @override
  Widget build(BuildContext context) {
    final options = switch (_tab) {
      TripMode.car => CarMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.car.key))
          .toList(),
      TripMode.moto => MotoMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.moto.key))
          .toList(),
      TripMode.bike => BikeMarkerStyle.values
          .map((e) => (key: e.key, label: e.label, sel: _sel.bike.key))
          .toList(),
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<TripMode>(
              segments: const [
                ButtonSegment(value: TripMode.car, label: Text('汽车')),
                ButtonSegment(value: TripMode.moto, label: Text('摩托')),
                ButtonSegment(value: TripMode.bike, label: Text('自行车')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            if (_tab == TripMode.moto)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '品牌名仅作风格区分，非官方授权模型；车标为自绘矢量轮廓，不使用官方 Logo。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            for (final o in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                minLeadingWidth: 64,
                horizontalTitleGap: 12,
                leading: VehicleMarkerPreviewTile(
                  selection: _selectionForRow(o.key),
                  mode: _tab,
                  selected: o.sel == o.key,
                  accentColor: widget.accentColor,
                ),
                title: Text(o.label),
                trailing: o.sel == o.key
                    ? Icon(Icons.check, color: widget.accentColor)
                    : null,
                onTap: () => _pick(_tab, o.key),
              ),
            const Text(
              '选择只存本机（profile.json 的 vehicleMarkerCar / '
              'vehicleMarkerMoto / vehicleMarkerBike 三个键），不上传。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeSettingsPage extends StatefulWidget {
  final ThemeChoice initial;
  final ValueChanged<ThemeChoice>? onAccentChanged;

  /// v1.0.2：第 8 项——地图车标选择（默认轿车/杜卡迪风格/公路）。
  /// 总协调接线：initial 传 appPrefs.vehicleSelection，
  /// onVehicleMarkerChanged 传 (sel) => appPrefs.setVehicleSelection(sel)。
  final VehicleMarkerSelection vehicleMarkerInitial;
  final ValueChanged<VehicleMarkerSelection>? onVehicleMarkerChanged;

  /// v1.0.3：APP 图标选择。v1.1.3 扩展到四张：红赛车 / 蓝仪表 / RB17 / 女武神。
  /// 总协调接线：appIconInitial 传 appPrefs.appIcon，
  /// onAppIconChanged 传持久化 + Native.setAppIcon 的回调。
  final String appIconInitial;
  final ValueChanged<String>? onAppIconChanged;

  /// v1.0.4：字体设置（从设置首页移入）：导入/清除回调与当前状态。
  final VoidCallback? onImportFont;
  final VoidCallback? onClearFont;
  final bool hasCustomFont;

  const ThemeSettingsPage({
    super.key,
    this.initial = ThemeChoice.defaults,
    this.onAccentChanged,
    this.vehicleMarkerInitial = const VehicleMarkerSelection(),
    this.onVehicleMarkerChanged,
    this.appIconInitial = AppIconChoice.red,
    this.onAppIconChanged,
    this.onImportFont,
    this.onClearFont,
    this.hasCustomFont = false,
  });

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late Color _accent = widget.initial.accent;
  late String _presetId = widget.initial.presetId;
  late String _appIcon = AppIconChoice.normalize(widget.appIconInitial);
  late final TextEditingController _hexCtrl = TextEditingController(
    text: '#${widget.initial.accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
  );
  String? _hexError;

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _setAccent(Color c, String presetId) {
    setState(() {
      _accent = c;
      _presetId = presetId;
      _hexError = null;
      _hexCtrl.text = '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    });
    widget.onAccentChanged?.call(ThemeChoice(accent: c, presetId: presetId));
  }

  void _applyHex() {
    final c = parseHexColor(_hexCtrl.text);
    if (c == null) {
      // 非法值只报错、不崩溃、不改当前主题色。
      setState(() => _hexError = '格式不对：请输入 #RRGGBB，如 #E10600（6 位十六进制）');
      return;
    }
    _setAccent(c, 'custom');
  }

  /// v1.0.3：点选即切换 APP 图标。选择先写回 AppPrefs（调用方回调
  /// 里持久化 + 调 Native.setAppIcon 切桌面 alias），本页只负责回显
  /// 与提示；不另起第三张、不含旧转速表图。
  void _pickAppIcon(String key) {
    if (_appIcon == key) return;
    setState(() => _appIcon = key);
    widget.onAppIconChanged?.call(key);
    showAppNotice(context, '桌面图标已切换，若桌面未立即刷新请稍等或重启启动器', AppNoticeKind.success);
  }

  /// v1.0.3 APP 图标分区卡：图标并排（小图 + 名称），点选即切换。
  Widget _appIconOption(String key) {
    final selected = _appIcon == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => _pickAppIcon(key),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _accent : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(AppIconChoice.assetFor(key),
                    width: 72, height: 72),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(AppIconChoice.labelFor(key),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle, size: 16, color: _accent),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(AppIconChoice.descriptionFor(key),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v0.1.9：去掉主题预览功能——不再渲染预览卡/预览图，也不再用
    // Theme 包住本页做页内预览；选色即通过 onAccentChanged 写回
    // AppPrefs 并在整个 App 内实时生效，返回首页即可看到新主题色。
    // 每项只留名称与一行必要说明，不再堆描述文字。
    return Scaffold(
        appBar: AppBar(title: const Text('主题设置')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                '全局黑色，只换主题色。',
                style: TextStyle(fontSize: 12),
              ),
            ),
            _sectionTitle('主题色'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final p in F1ThemePresets.all)
                          GestureDetector(
                            onTap: () => _setAccent(p.color, p.id),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: p.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _presetId == p.id ? Colors.white : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '近似色，非官方配色表。',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            _sectionTitle('自定义颜色'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _hexCtrl,
                            decoration: InputDecoration(
                              labelText: '十六进制颜色（#RRGGBB）',
                              border: const OutlineInputBorder(),
                              errorText: _hexError,
                            ),
                            onSubmitted: (_) => _applyHex(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _applyHex,
                          style: FilledButton.styleFrom(backgroundColor: _accent),
                          child: const Text('应用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // v1.0.3：APP 图标分区。v1.2.2 扩展到五张，3+2 两行并排，点选即切换。
            _sectionTitle('APP 图标'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _appIconOption(AppIconChoice.red),
                        const SizedBox(width: 12),
                        _appIconOption(AppIconChoice.rb17),
                        const SizedBox(width: 12),
                        _appIconOption(AppIconChoice.valkyrie),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _appIconOption(AppIconChoice.steering),
                        const SizedBox(width: 12),
                        _appIconOption(AppIconChoice.checkered),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '点选即切换桌面图标与 App 内图标（启动页、关于页同步变化）。'
                      '切换使用 DONT_KILL_APP，不会在切换瞬间杀掉 App 导致数据丢失；'
                      '桌面图标由启动器刷新后变化，若未立即刷新请稍等或重启启动器。',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '回落说明：部分厂商启动器（如个别定制 ROM）可能不立即刷新、'
                      '需重启启动器或重新安装才显示新图标；若切换后启动异常，'
                      '请从系统设置的应用信息里清除启动器缓存或重装本应用，'
                      '默认图标为红赛车。',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '若桌面仍显示旧图标，请长按删除桌面图标后从应用列表重新添加：'
                      'v1.0.2 的桌面入口指向主 Activity，v1.0.3 起改为 alias，'
                      '个别启动器需重加才刷新。',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
            // v1.0.2：第 8 项——地图车标分区（原设置首页入口已删，功能在此）。
            _sectionTitle('地图车标'),
            VehicleMarkerSettingsSection(
              initial: widget.vehicleMarkerInitial,
              onChanged: widget.onVehicleMarkerChanged,
              accentColor: _accent,
            ),
            // v1.0.4：字体分区（从设置首页移入，功能不变）。
            _sectionTitle('字体'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.font_download),
                    title: const Text('导入自带字体'),
                    subtitle: const Text('导入自己合法取得的 .ttf/.otf'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onImportFont,
                  ),
                  if (widget.hasCustomFont)
                    ListTile(
                      leading: const Icon(Icons.clear),
                      title: const Text('清除自带字体'),
                      subtitle: const Text('恢复内置字体'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.onClearFont,
                    )
                  else
                    const ListTile(
                      leading: Icon(Icons.check),
                      title: Text('当前使用内置字体'),
                      subtitle: Text('导入后可在此清除恢复'),
                    ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

// ---------- 总协调接线（不执行，仅供参考） ----------
// 1) AppPrefs.load/save 只写 profile.json 的 themeAccent / themePreset
//    两个键（见 ThemeChoice.toJson/fromJson，旧 'theme' 兜底；旧
//    'themeMode' 键一律忽略，不再读写昼夜档位）。
// 2) MaterialApp 改为全局黑色：
//      theme: DriveTrackTheme.dark(appPrefs.themeColor),
//      darkTheme: DriveTrackTheme.dark(appPrefs.themeColor),
//      themeMode: ThemeMode.dark,
//    不再传 light、不再随系统。
// 3) 设置页“主题”入口改为推 ThemeSettingsPage(initial: 当前 ThemeChoice,
//    onAccentChanged: 存主题色)，旧 settings_page.dart
//    里的主题色板 + 十六进制行由总协调决定保留或替换为本页入口。
