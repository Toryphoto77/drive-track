import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'app_notice.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'models.dart';
import 'logic.dart';
import 'native.dart';
import 'tappable.dart';
import 'permission_gate.dart';
import 'recording_3d_map.dart';
import 'recording_map_page.dart';
import 'recorder.dart';
import 'tunnel_gap.dart';
import 'obd_service.dart';
import 'store.dart';
import 'gps_source.dart';
import 'widgets.dart';
// v0.1.3 新模块（统合）
import 'countdown_page.dart';
import 'big_action_buttons.dart';
import 'device_center.dart';
import 'camera_connect_page.dart';
import 'blediy_gps.dart';
import 'track_catalog.dart';
import 'track_encyclopedia.dart';
import 'track_guide.dart';
import 'track_library.dart';
import 'track_knowledge_page.dart';
import 'track_library_page.dart';
import 'track_package_info_page.dart';
import 'track_package_selector.dart';
import 'track_timing.dart';
import 'track_widgets.dart';
import 'my_page.dart';
import 'profile_edit_page.dart';
import 'refined_map.dart';
import 'weather_strip.dart';
import 'weather_service.dart';
import 'weather_page.dart';
// v0.1.4 新模块（统合）
import 'glass_button.dart';
import 'gps_source_badge.dart';
import 'mode_switch.dart';
import 'theme_settings_page.dart';
import 'vehicle_markers.dart';
import 'map_import_page.dart';
import 'map_import_service.dart' as mis;
import 'trip_detail_modules.dart';
import 'recording_draft.dart';
import 'photo_points.dart';
import 'score_module.dart';
import 'lean_chart.dart';
import 'lean_gauge.dart';
import 'live_lap_timer_text.dart';
import 'accel_module.dart';
import 'amap_service.dart';
import 'share_card_preview.dart';
import 'track_viz.dart';
import 'voice_service.dart';
import 'satellite_service.dart';
import 'track_settings_page.dart';
import 'track_session_display.dart';
import 'track_live_g.dart';
import 'track_sector_data.dart';
import 'track_analysis_page.dart';
import 'trip_analytics_page.dart';
import 'vehicle_profile.dart';
import 'vehicle_profile_page.dart';
import 'settings_home_page.dart';
import 'permission_settings_page.dart';
import 'voice_settings_page.dart';
import 'satellite_settings_page.dart';
import 'satellite_pill.dart';
// v0.1.9 新模块（统合）
import 'frosted_nav_bar.dart';
import 'home_layout.dart';
import 'distance_format.dart';
import 'splash_page.dart';
import 'app_locale.dart';
import 'dt_page_route.dart';
import 'empty_hud.dart';
import 'hold_to_end_button.dart';
import 'sensor_calibration_page.dart';
import 'about_page.dart';
import 'app_icon_choice.dart';
import 'card_style.dart';
import 'disclaimer_page.dart';
import 'video_review_page.dart';
import 'data_export_page.dart';
import 'fuel_page.dart';
import 'update_service.dart';
// v1.0.2 新模块（统合）
import 'track_home_page.dart';
import 'performance_challenge.dart';
// 云端二期：腾讯 CloudBase（匿名 + 邮箱登录，手动上传、
// 个人页云端入口）。环境 ID 只走 --dart-define，不进仓库。
import 'cloud_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // v1.5.1：全局默认只允许竖屏（用户要求：横屏只在记录页放开，
  // 其他页一律竖屏）。记录页在进入/退出记录态时另行放开/收回，
  // 见 _applyRecordingOrientation。
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]));
  runApp(const DriveTrackApp());
}

// ---------- v0.1.2 本机偏好：主题色 / 个人资料 / 自带字体 ----------
// 全部只存本机 profile.json，不登录、不上传。用户名默认“柴西”（用户自报），
// ID 首次启动时本机生成 DT-xxxx，不编造任何真实身份信息。
class AppPrefs extends ChangeNotifier {
  Color themeColor = const Color(0xFFE10600); // 法拉利赛车红（默认）
  String username = '柴西';
  String userId = '';
  String bio = '';
  // v1.0.7：个人页邮箱（仅存本机 profile.json，不发验证码、
  // 不是账号登录绑定、不发到任何服务器）。
  String email = '';
  // v1.5.1：个人资料扩展字段（只存本机 profile.json，随昵称/简介
  // 一起同步到云端公开资料）：性别（''=未填，'男'/'女'）、生日
  // （'yyyy-MM-dd' 或 ''）、行业、座驾品牌、座驾型号。
  String gender = '';
  String birthday = '';
  String industry = '';
  String vehicleBrand = '';
  String vehicleModel = '';
  String? avatarPath;
  String? customFontPath;
  bool customFontLoaded = false;
  bool countdownVibration = true; // v0.1.3：倒计时震动提醒开关（设置页）
  // v0.1.4：主题预设/车标/直连卫星（存 profile.json）
  // v0.1.7：全局黑色，无昼夜档位；旧 themeMode 档位键不再读写。
  String themePreset = 'ferrari';
  String vehicleCar = 'sedan';
  String vehicleMoto = 'ducati';
  String vehicleBike = 'road';
  bool directSatellite = false;
  // v0.1.7 油耗费用（追加项 4）：两项默认都为空，不预设数值；
  // 旧 profile.json 缺字段时兼容为空。见 fuel_page.dart 的口径说明。
  double? fuelConsumptionLPer100Km;
  double? fuelPricePerLiter;
  bool bluetoothEnabled = true;
  // v0.1.8：记录时保持屏幕常亮（默认开启，存 profile.json）；
  // 记录地图 3D 透视（默认开启，关闭为 2D 俯视示意，存 profile.json）。
  bool keepScreenOn = true;
  bool recordingMap3d = true;
  // 街道记录 3D 视角俯仰角（65° 默认 → 50° → 35°，存 profile.json）。
  double recordingMapPitch = 65.0;
  // v1.0.3：可切换启动图标（profile.json 'appIcon'，'steering' 默认，见 AppIconChoice）。
  String appIcon = 'steering';
  // v1.0.7：安全守则“今日内不再弹出”（按日期 + 模式 + 街道/赛道记，
  // 只存本机 profile.json，不上传）。
  String safetyAckDate = '';
  String safetyAckMode = '';
  bool safetyAckTrack = false;
  VehicleMarkerSelection get vehicleSelection => VehicleMarkerSelection(
        car: CarMarkerStyle.values.firstWhere((e) => e.key == vehicleCar, orElse: () => CarMarkerStyle.sedan),
        moto: MotoMarkerStyle.values.firstWhere((e) => e.key == vehicleMoto, orElse: () => MotoMarkerStyle.ducati),
        bike: BikeMarkerStyle.values.firstWhere((e) => e.key == vehicleBike, orElse: () => BikeMarkerStyle.road));
  bool _loading = false;
  bool _loaded = false;

  String get fontFamily => customFontLoaded ? 'DriveTrackCustom' : 'DriveTrackSans';
  String get displayFont => customFontLoaded ? 'DriveTrackCustom' : 'DriveTrackDisplay';

  static const List<(String, Color)> presets = [
    ('法拉利红', Color(0xFFE10600)),
    ('电光蓝', Color(0xFF2563EB)),
    ('赛道绿', Color(0xFF16A34A)),
    ('曜石紫', Color(0xFF7C3AED)),
  ];

  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/profile.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final tc = j['theme'] as String?;
        if (tc != null) {
          final v = int.tryParse(tc.replaceFirst('#', ''), radix: 16);
          if (v != null) themeColor = Color(0xFF000000 | v);
        }
        // 旧 'themeMode' 键有意不读：旧 light/system 档位一律按全局黑色处理。
        themePreset = (j['themePreset'] as String?) ?? themePreset;
        vehicleCar = (j['vehicleMarkerCar'] as String?) ?? vehicleCar;
        vehicleMoto = (j['vehicleMarkerMoto'] as String?) ?? vehicleMoto;
        vehicleBike = (j['vehicleMarkerBike'] as String?) ?? vehicleBike;
        directSatellite = (j['directSatellite'] as bool?) ?? directSatellite;
        keepScreenOn = (j['keepScreenOn'] as bool?) ?? keepScreenOn;
        recordingMap3d = (j['recordingMap3d'] as bool?) ?? recordingMap3d;
        final rp = (j['recordingMapPitch'] as num?)?.toDouble();
        recordingMapPitch = (rp == 50.0 || rp == 35.0) ? rp! : 65.0;
        appIcon = AppIconChoice.normalize(j['appIcon'] as String?);
        safetyAckDate = (j['safetyAckDate'] as String?) ?? '';
        safetyAckMode = (j['safetyAckMode'] as String?) ?? '';
        safetyAckTrack = (j['safetyAckTrack'] as bool?) ?? false;
        // 油耗两项：缺字段 / 非正数一律按空处理，不编默认值。
        final fc = (j['fuelConsumptionLPer100Km'] as num?)?.toDouble();
        fuelConsumptionLPer100Km = (fc != null && fc > 0) ? fc : null;
        final fp = (j['fuelPricePerLiter'] as num?)?.toDouble();
        fuelPricePerLiter = (fp != null && fp > 0) ? fp : null;
        username = (j['username'] as String?) ?? username;
        countdownVibration = (j['countdownVibration'] as bool?) ?? true;
        userId = (j['userId'] as String?) ?? '';
        bio = (j['bio'] as String?) ?? '';
        email = (j['email'] as String?) ?? '';
        gender = (j['gender'] as String?) ?? '';
        birthday = (j['birthday'] as String?) ?? '';
        industry = (j['industry'] as String?) ?? '';
        vehicleBrand = (j['vehicleBrand'] as String?) ?? '';
        vehicleModel = (j['vehicleModel'] as String?) ?? '';
        avatarPath = j['avatarPath'] as String?;
        customFontPath = j['customFontPath'] as String?;
      }
      if (userId.isEmpty) {
        userId = 'DT-${1000 + DateTime.now().millisecondsSinceEpoch % 9000}';
        await save();
      }
      if (customFontPath != null && await File(customFontPath!).exists()) {
        await _loadCustomFontFile(customFontPath!);
      }
    } catch (_) {}
    _loaded = true;
    _loading = false;
    // v1.0.3：冷启动按持久化选择同步一次桌面 alias（例如备份恢复后
    // profile 换了选择、而 PackageManager 里还是旧 alias 时纠正回来；
    // 测试环境无原生通道时 invoke 会抛错，此处单独捕获、不影响加载）。
    try {
      await Native.setAppIcon(appIcon);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadCustomFontFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader('DriveTrackCustom');
      loader.addFont(Future.value(bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes)));
      await loader.load();
      customFontLoaded = true;
    } catch (_) {
      customFontLoaded = false;
    }
  }

  Future<void> save() async {
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/profile.json').writeAsString(jsonEncode({
        'theme': '#${themeColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        'username': username,
        'userId': userId,
        'bio': bio,
        'email': email,
        'gender': gender,
        'birthday': birthday,
        'industry': industry,
        'vehicleBrand': vehicleBrand,
        'vehicleModel': vehicleModel,
        'avatarPath': avatarPath,
        'customFontPath': customFontPath,
        'countdownVibration': countdownVibration,
        'themePreset': themePreset,
        'vehicleMarkerCar': vehicleCar,
        'vehicleMarkerMoto': vehicleMoto,
        'vehicleMarkerBike': vehicleBike,
        'directSatellite': directSatellite,
        'keepScreenOn': keepScreenOn,
        'recordingMap3d': recordingMap3d,
        'recordingMapPitch': recordingMapPitch,
        'appIcon': appIcon,
        'safetyAckDate': safetyAckDate,
        'safetyAckMode': safetyAckMode,
        'safetyAckTrack': safetyAckTrack,
        'fuelConsumptionLPer100Km': fuelConsumptionLPer100Km,
        'fuelPricePerLiter': fuelPricePerLiter,
      }));
    } catch (_) {}
  }

  Future<void> setTheme(Color c) async {
    themeColor = c;
    notifyListeners();
    await save();
  }

  Future<void> setThemeChoice(ThemeChoice c) async {
    themePreset = c.presetId;
    themeColor = c.accent;
    notifyListeners();
    await save();
  }

  /// v1.0.3：切换启动图标选择并持久化；桌面 alias 的实际切换由
  /// 调用方经 Native.setAppIcon 执行（失败也不丢选择，下次冷启动
  /// load 完成后会重新按持久化选择同步一次 alias，见 load 末尾）。
  Future<void> setAppIcon(String key) async {
    appIcon = AppIconChoice.normalize(key);
    notifyListeners();
    await save();
  }

  /// v1.0.7：今日同一模式 + 同一街道/赛道档位是否已确认过安全守则。
  bool safetyAckedToday(TripMode mode, {required bool isTrack}) {
    final today = DateTime.now();
    final key = '${today.year}-${today.month}-${today.day}';
    return safetyAckDate == key && safetyAckMode == mode.name && safetyAckTrack == isTrack;
  }

  Future<void> setSafetyAckedToday(TripMode mode, {required bool isTrack}) async {
    final today = DateTime.now();
    safetyAckDate = '${today.year}-${today.month}-${today.day}';
    safetyAckMode = mode.name;
    safetyAckTrack = isTrack;
    notifyListeners();
    await save();
  }

  Future<void> setVehicleSelection(VehicleMarkerSelection sel) async {
    vehicleCar = sel.car.key;
    vehicleMoto = sel.moto.key;
    vehicleBike = sel.bike.key;
    notifyListeners();
    await save();
  }

  Future<void> setDirectSatellite(bool v) async {
    directSatellite = v;
    notifyListeners();
    await save();
  }

  // v0.1.7 油耗费用：空 = 未填写；调用方（fuel_page.dart）已校验
  // 非空值必须 > 0，这里再兜底一次非正数按空存。
  Future<void> setFuelSettings(double? consumption, double? price) async {
    fuelConsumptionLPer100Km =
        (consumption != null && consumption > 0) ? consumption : null;
    fuelPricePerLiter = (price != null && price > 0) ? price : null;
    notifyListeners();
    await save();
  }

  Future<void> setCountdownVibration(bool v) async {
    countdownVibration = v;
    notifyListeners();
    await save();
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v;
    notifyListeners();
    await save();
  }

  Future<void> setRecordingMap3d(bool v) async {
    recordingMap3d = v;
    notifyListeners();
    await save();
  }

  /// 街道记录 3D 视角俯仰角（只取 65°/50°/35° 三档，其它值归到 65°）。
  Future<void> setRecordingMapPitch(double v) async {
    recordingMapPitch = (v == 50.0 || v == 35.0) ? v : 65.0;
    notifyListeners();
    await save();
  }

  Future<void> applyCustomFont(String path) async {
    customFontPath = path;
    await _loadCustomFontFile(path);
    notifyListeners();
    await save();
  }

  Future<void> clearCustomFont() async {
    customFontPath = null;
    customFontLoaded = false;
    notifyListeners();
    await save();
  }
}

final appPrefs = AppPrefs();

class DriveTrackApp extends StatefulWidget {
  const DriveTrackApp({super.key});
  @override
  State<DriveTrackApp> createState() => _DriveTrackAppState();
}

class _DriveTrackAppState extends State<DriveTrackApp> {
  @override
  void initState() {
    super.initState();
    appPrefs.load();
    LocaleController.instance.load();
    // 云端一期：fire-and-forget，init 内部全包 try/catch，
    // 未配置（无 Key）或断网都不拖住启动、不崩。
    CloudService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appPrefs,
      builder: (_, __) {
        final accent = appPrefs.themeColor;
        return MaterialApp(
          title: '驰迹 DriveTrack',
          debugShowCheckedModeBanner: false,
          builder: (context, child) => LocaleScope(
            controller: LocaleController.instance,
            child: child ?? const SizedBox.shrink(),
          ),
          // v0.1.7 全局黑色：两套都传黑色、档位固定 dark，不随系统变浅。
          theme: DriveTrackTheme.dark(accent),
          darkTheme: DriveTrackTheme.dark(accent),
          themeMode: ThemeMode.dark,
          // v1.0.2 开屏闪页修法：启动第一帧只能是启动页。
          // 根因见 splash_page.dart：旧写法把 HomePage 作为实参
          // 在首帧就构造，且 PermissionGate 在 opacity 0 下照常
          // build 首页并淡入，看起来像一张不完整首页闪现。
          // 本处 home 只放 SplashPage（不传任何首页 widget），
          // 首页 widget 对象只在 '/home' 路由 builder 里首次构造，
          // 即启动动画完成之后；原生启动背景保持纯黑（v1.0.0 已改黑）。
          home: SplashPage(appIconKey: appPrefs.appIcon),
          routes: {
            '/home': (_) => const PermissionGate(child: HomePage()),
            DisclaimerPage.routeName: (_) => const DisclaimerPage(),
          },
        );
      },
    );
  }
}

String fmtDur(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// v1.2.17：维修区停站后缀（旗标头行用）。只在计时器 inPit 为真时
/// 显示“ · 维修区 · 停站 mm:ss”，停站时长取计时器 pitStopMs；
/// 不在维修区时返回空串，不显示、不编数。
String pitStopSuffix({required bool inPit, required int pitStopMs}) =>
    inPit ? ' · 维修区 · 停站 ${fmtDur(pitStopMs)}' : '';

/// v1.2.17：圈标记文案。flying（飞行圈）无标记，返回空串；
/// inLap / outLap 分别标“进站圈”/“出站圈”，与“不计圈”“最快”并存。
String lapKindTag(LapKind kind) => switch (kind) {
      LapKind.inLap => '进站圈',
      LapKind.outLap => '出站圈',
      LapKind.flying => '',
    };

/// v1.2.17：圈速列表展开行文案。“S1 1:05.000 / S2 1:06.000 / S3
/// 1:04.000”；下标即段号（2 个分段点 = S1/S2/S3，1 个 = S1/S2），
/// 实际长度按 Lap.sectorsMs，不补缺失段。
String formatLapSectorTimes(Lap lap) {
  final parts = <String>[];
  for (var i = 0; i < lap.sectorsMs.length; i++) {
    parts.add('S${i + 1} ${LapTimer.formatLapTime(lap.sectorsMs[i])}');
  }
  return parts.join(' / ');
}

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtDateEn(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// v0.1.5 安全守则分街道 / 赛道：
// - 街道模式（含骑行，骑行无赛道模式）：最前面放两条醒目声明
//   “不要在公开道路上追逐竞技驾驶”“不要超速驾驶”，与关于页
//   安全区最前面的两条置顶声明对应，用户开始前就能看到；
// - 赛道模式：最前面放“仅在正规封闭赛道使用”，街道的两条
//   不适用于封闭赛道，不放进赛道守则。
List<String> safetyItems(TripMode m, {bool isTrack = false, bool english = false}) {
  if (english) {
    final base = switch (m) {
      TripMode.car => ['Phone is mounted', 'Do not use the phone while driving', 'Seatbelt on', 'Vehicle checked'],
      TripMode.moto => ['Helmet and gloves on', 'Mount is locked', 'Do not use the phone while riding', 'Bike checked'],
      TripMode.bike => ['Helmet on', 'Brakes and tires checked', 'Lights ready at night', 'Do not use the phone while riding'],
    };
    if (isTrack) return ['Closed circuit only', ...base];
    return ['No racing on public roads', 'Do not speed', ...base];
  }
  final base = switch (m) {
    TripMode.car => ['手机已固定在支架上', '不开车时操作手机', '已系好安全带', '出发前已检查车况'],
    TripMode.moto => ['头盔、手套已戴好', '手机支架已锁紧', '不开车时操作手机', '出发前已检查车况'],
    TripMode.bike => ['头盔已戴好', '已检查刹车与轮胎', '夜骑已准备灯光', '骑行中不操作手机'],
  };
  if (isTrack) return ['仅在正规封闭赛道使用', ...base];
  return ['不要在公开道路上追逐竞技驾驶', '不要超速驾驶', ...base];
}

/// 口播版安全注意事项（开始记录语音用）：与 [safetyItems] 同源，
/// 红字置顶声明原样播出，其余条目只改说法不改意思（口语化压缩，
/// 如“不开车时操作手机”→“行车中不操作手机”），再加开录锁定提示。
/// 守则改了，口播跟着变，不另维护一份平行文案。
const _safetySpeechShort = {
  '手机已固定在支架上': '手机已固定',
  '不开车时操作手机': '行车中不操作手机',
  '出发前已检查车况': '车况已检查',
  '手机支架已锁紧': '支架已锁紧',
  '已检查刹车与轮胎': '刹车轮胎已检查',
  '夜骑已准备灯光': '夜骑灯光已准备',
};

String safetySpeechText(TripMode m, {bool isTrack = false}) {
  final items = safetyItems(m, isTrack: isTrack);
  final redCount = isTrack ? 1 : 2;
  final red = items.take(redCount).join('，');
  final rest = items
      .skip(redCount)
      .map((e) => _safetySpeechShort[e] ?? e)
      .join('，');
  return '安全提醒：$red。$rest。开录后界面锁定，只留暂停和结束。';
}

Future<void> unawaitedSaveBle(String address) async {
  try {
    final dir = await Native.getFilesDir();
    await File('$dir/last_ble.txt').writeAsString(address);
  } catch (_) {}
}

/// v1.2.14 越线检测接线：决定传给 [LapTimer] 的中心线。
///
/// 仅当包起终点已被采用（包 start 与记录首点 < 500m，见 _buildLapTimer
/// 的采用门控）且包中心线可用（≥ 2 点）时返回包中心线；其余情形
/// （无包、无起终点、离首点 ≥ 500m、中心线不足 2 点）返回 null，
/// [LapTimer] 对应边界回落半径法。起终点 / 分段点的采用逻辑仍在
/// _buildLapTimer 里，不动；本函数只决定中心线是否传。
/// 中心线不足 2 点时 tangentAtPoint 本就返回 null，显式返回 null
/// 只是让回落意图在接线处可见。
List<GeoPoint>? lapTimerCenterlineForPackage(
    TrackPackage? pkg, GeoPoint firstPoint) {
  final start = pkg?.start;
  if (start == null) return null;
  if (haversineM(start.lat, start.lon, firstPoint.lat, firstPoint.lon) >=
      500) {
    return null;
  }
  if (pkg!.centerline.length < 2) return null;
  return pkg.centerline;
}

/// v1.2.14 排空时序：LapTimer 喂点排空（纯函数部分）。
/// 把 [points] 里自 [fedCount] 起未喂的点逐点喂给 [timer]，
/// 返回新的已喂点数。手机定位回调与外接 GPS 回调共用同一循环，
/// 逻辑与 v1.2.13 的排空循环逐行一致，只改触发时机，不改排空
/// 逻辑、不改轨迹落点频率、不改存储频率。
int drainLapTimerPoints(
    LapTimer timer, List<TrackPoint> points, int fedCount) {
  var fed = fedCount;
  while (fed < points.length) {
    final p = points[fed++];
    timer.addPoint(TimedPoint(
        lat: p.lat, lon: p.lon, speed: p.speed, timeMs: p.timeMs));
  }
  return fed;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Store store = Store();
  final Recorder rec = Recorder();
  int tab = 0;
  late final PageController _modeController = PageController(initialPage: rec.mode.index);
  // v1.3.2：记录页实时 Map 分页（计时页 / 地图页左右滑）。
  late final PageController _recMapPageController = PageController();
  int _recMapPageIndex = 0;
  List<TripMeta> trips = [];
  WeatherInfo? weather;
  double? weatherLat, weatherLon;
  int weatherMs = 0;
  bool fetchingWeather = false;
  // v0.1.9 天气立即显示：初始即为加载态，绝不先显示“未获取”。
  // weatherLoading=true 且 weather==null 时天气条显示“加载中…”；
  // weatherFailed=true 且 weather==null 时才显示“未获取”并给重试入口；
  // 有上次缓存时先显示缓存（weatherFromCache），加载中追加“更新中…”。
  bool weatherLoading = true;
  bool weatherFailed = false;
  bool weatherFromCache = false;
  bool weatherStale = false;
  bool permGranted = false;
  // 录制草稿：记录中每 30 秒落盘一次，App 被杀后下次启动可恢复。
  RecordingDraftStore? _drafts;
  Timer? _draftTimer;
  bool _draftWriting = false;
  DateTime? _lastPauseTap;
  bool trimPrivacy = true;
  double riderKg = 85;
  bool autoReconnect = true;
  List<Map<String, dynamic>> bleDevices = [];
  String? bleConnected;
  StreamSubscription? _locSub, _senSub, _bleDevSub, _bleDataSub;
  // v0.1.2：滑动菜单 / 同步视频 / 收藏 / 我的页分区
  // v0.1.3 菜单手感：动画 350ms → 200ms，曲线 easeOutCubic（起手快），
  // 位移/缩放/圆角由同一动画值同步驱动（见 build 里的 easeOutCubic 变换）。
  late final AnimationController _menuAnim = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 200))..addListener(() {
      if (mounted) setState(() {});
    });
  // v0.1.3 赛道模式 / 地图 / 外接 GPS 状态
  bool trackMode = false;
  TrackInfo? selectedTrack;
  // 赛道库：与 selectedTrack 同生命周期，选中包时一并设定，供计时
  // 取包的经纬度起终点 / 分段点（无包数据时回落旧行为）。
  TrackPackage? selectedPackage;
  LapTimer? liveLapTimer;
  int _lapFedCount = 0;
  // v1.2.14 排空时序：_drainLapTimer 在途标志，防两次排空同时建计时器
  //（见 _drainLapTimer 注释）。只在 _drainLapTimer 内读写。
  bool _lapDrainRunning = false;
  // v0.1.8：记录页瓦片源已移除（改用 Recording3dMap 自绘，不再有瓦片）；
  // mapZoom / mapHeadingUp 继续作 3D 地图的缩放与跟随状态。
  double mapZoom = 16;
  bool mapHeadingUp = true;
  // v0.1.8 常亮实际状态（以原生返回值为准，绝不假装已开启）：
  // _keepScreenOnActual=true 才是真的常亮中；原生返回 false 时
  // _keepScreenOnFailed=true，记录页显示“常亮未开启”并提示检查。
  bool _keepScreenOnActual = false;
  bool _keepScreenOnFailed = false;
  WeatherData? extWeather;
  final BleDiyGpsFeed _blediyFeed = BleDiyGpsFeed();
  bool _blediyActive = false;
  bool get _menuOpen => _menuAnim.value > 0.5;
  bool videoEnabled = false; // 驾车/摩托开始前勾选，默认关闭
  bool bleEnabled = true; // v0.1.4：App 内蓝牙停用开关
  bool videoActive = false;
  String? videoError;
  // v0.1.7 沿途照片打点：本趟记录中的打点（坐标+时间，无照片也可），
  // 结束时随 saveTrip 存入行程；行程太短未保存时直接丢弃（无照片文件可删）。
  List<PhotoPoint> livePhotoPoints = [];
  Set<String> favorites = {};
  int myTab = 0; // 0 行程 1 动态 2 收藏 3 成就
  // v1.2.0：车辆档案（设置页入口加载，默认车辆用于新行程绑定）、
  // 赛道行程最佳圈（列表卡片用，加载失败为 null 即“暂无圈速”）、
  // 列表多选删除 / 油耗分组区间状态。
  VehicleLibrary? vehicleLibrary;
  Map<String, int?> trackBestLapMs = {};
  bool _listSelecting = false;
  final Set<String> _selectedTripIds = {};

  /// 赛道实况是否显示 Delta（赛道设置页“显示 Delta”开关，
  /// 默认 true）。本字段在 _init 读盘、设置页 onChanged 回写；
  /// 开关本身早已存在但此前无人读取，属未接线开关，本轮接上。
  bool _showTrackDelta = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rec.addListener(() => mounted ? setState(() {}) : null);
    // 隧道缺口状态 → 语音看门狗：同一份状态，不重复播报。
    rec.gapStatus.addListener(() {
      final s = rec.gapStatus.value;
      VoiceService.instance
          .setGapLost(s == GapStatus.lost || s == GapStatus.estimating);
    });
    // 隧道补段路网：缺口起点周围取 tunnel=yes 优先的折线。
    rec.gapRoadFetcher = (lat, lon) async {
      try {
        final result = await fetchRoadWaysAround(lat, lon);
        final ways = result.ways
            .map((w) => (points: w.points, tunnel: w.tunnel))
            .toList();
        return chooseGapPolyline(lat, lon, ways);
      } catch (_) {
        return null;
      }
    };
    // 街道贴路路网：当前位置周围的全部 ways（贴路按行进方向
    // 挑同向路段，取数失败返回 null，贴路自动跳过）。
    rec.roadWaysFetcher = (lat, lon) async {
      try {
        final result = await fetchRoadWaysAround(lat, lon);
        return result.ways.map((w) => w.points).toList();
      } catch (_) {
        return null;
      }
    };
    _init();
  }

  // v0.1.9：从系统设置页回来（本次启动内刚给上定位权限）也要立即
  // 拉天气，不等下一次定位事件——权限回调后没重拉是旧 bug 之一。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _triggerWeatherOnLaunch();
    }
  }

  Future<void> _init() async {
    await VoiceService.instance.load();
    _showTrackDelta = (await TrackSettingsStore.load()).showDelta;
    SatelliteService.instance.start();
    if (appPrefs.directSatellite) SatelliteService.instance.setDirectMode(true);
    await store.init();
    await appPrefs.load();
    // OBD 服务挂录制器：实时车速写 rec.obdSpeedMs（只供隧道推算用）、
    // 每秒一条实测采样进 rec.obdSamples；不断开不写，GPS 正常时
    // 绝不拿 OBD 速度替换实测点里的 GPS 速度（Recorder 已保证）。
    obdService.attachRecorder(rec);
    // v1.2.0：旧索引无赛道/车辆键时回填（读不到回退全量加载 Trip，
    // 见 Store.migrateIndexTrackFields），不丢旧数据。
    trips = await store.migrateIndexTrackFields();
    favorites = await store.loadFavorites();
    vehicleLibrary = await store.loadVehicleLibrary();
    _drafts = RecordingDraftStore(store.dir);
    _refreshTrackBestLaps();
    await _loadCachedWeather();
    if (mounted) setState(() {});
    // 上次记录中被系统杀掉 / 划掉：提示把草稿救回成行程。
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDraftRecovery());
    // v0.1.9：进首页即触发天气（见 _triggerWeatherOnLaunch 注释的根因）。
    await _triggerWeatherOnLaunch();
    _locSub = Native.locationStream.listen((e) async {
      // v0.1.3 外接 GPS 超时回落：5 秒无新定位即切回手机 GPS。
      if (_blediyActive && _blediyFeed.shouldFallbackToPhoneGps()) {
        _blediyActive = false;
        rec.externalGpsActive = false;
        // v1.4.x 街道语音：外接 GPS 断开回落时播一次（赛道模式不跑）。
        if (rec.isRecording && !trackMode) {
          VoiceService.instance.announceGpsFallback();
        }
      }
      rec.onLocation(e);
      SatelliteService.instance.noteLocationProvider(e['provider'] as String?);
      // v0.1.4 语音：急加速/急刹车/压弯超阈值实时播报（VoiceService 内 3 秒节流）。
      if (rec.isRecording && rec.calibrated) {
        final th = ModeThresholds.of(rec.mode);
        if (rec.smoothLong > th.harshAccel) {
          VoiceService.instance.announceEvent(kind: VoiceEventKind.harshAccel, longG: rec.smoothLong, speedKmh: rec.curSpeed * 3.6);
        } else if (rec.smoothLong < th.harshBrake) {
          VoiceService.instance.announceEvent(kind: VoiceEventKind.harshBrake, longG: rec.smoothLong, speedKmh: rec.curSpeed * 3.6);
        }
        if (rec.mode == TripMode.moto && rec.rollDeg.abs() > 30) {
          VoiceService.instance.announceEvent(kind: VoiceEventKind.leanOver, leanDeg: rec.rollDeg, speedKmh: rec.curSpeed * 3.6);
        }
      }
      // v1.4.x 街道语音：起步 / 超速 / 里程时间 / 低精度（VoiceService 内节流）；
      // 赛道模式不跑（圈速播报走 _drainLapTimer 的 announceLap）。
      if (rec.isRecording && !trackMode) {
        VoiceService.instance.noteStreetLocation(
          speedKmh: rec.curSpeed * 3.6,
          hAcc: rec.curHAcc,
          distanceKm: rec.distanceM / 1000,
          elapsedMs: rec.elapsedMs,
        );
      }
      // v0.1.3 赛道实时计时：赛道模式下，首点定为起终点，逐点喂 LapTimer
      //（排空见 _drainLapTimer；外接 GPS 回调里同样触发，见 _bleDataSub）。
      await _drainLapTimer();
      final lat = (e['lat'] as num?)?.toDouble() ?? 0;
      final lon = (e['lon'] as num?)?.toDouble() ?? 0;
      if (lat != 0) _maybeWeather(lat, lon);
      if (rec.mode == TripMode.bike && rec.sensorStatus != 'ok' && rec.points.length >= 2) {
        final a = rec.points[rec.points.length - 2];
        final b = rec.points.last;
        final d = haversineM(a.lat, a.lon, b.lat, b.lon);
        // 任一点无海拔时坡度不可信（旧外接占位 0 会造出假坡），置 0。
        final slope = (d > 1 && a.altValid && b.altValid) ? (b.alt - a.alt) / d : 0.0;
        rec.applyEstimatedPower(slope, riderKg);
      }
    }, onError: (_) {});
    _senSub = Native.sensorStream.listen((e) => rec.onSensor(e), onError: (_) {});
    _bleDevSub = Native.bleDeviceStream.listen((e) {
      setState(() {
        final addr = e['address'] as String? ?? '';
        bleDevices.removeWhere((d) => d['address'] == addr);
        bleDevices.add(e);
      });
    }, onError: (_) {});
    _bleDataSub = Native.bleDataStream.listen((e) {
      // v0.1.3 BleDIY 外接 GPS：通用通知按特征 UUID 分发，NMEA 特征
      //（NUS TX …0003、NMEA UART TX …1103）的字节喂给 NMEA 解析器；
      // 有效定位注入 Recorder（provider='external'），超时/断线立即
      // 回落手机 GPS（Recorder.externalGpsActive=false）。
      // SPP 文本（sppNmea）走同一解析器与同一接管/回落规则。
      var fedExternalFix = false;
      if (e['type'] == 'bleNotification') {
        final uuid = (e['characteristicUuid'] as String? ?? '').toLowerCase();
        final bytes = (e['bytes'] as List?)?.map((v) => (v as num).toInt()).toList() ?? <int>[];
        if ((uuid.contains('0003') || uuid.contains('1103')) &&
            bytes.isNotEmpty) {
          _blediyFeed.feedBytes(bytes);
          final fix = _blediyFeed.latest;
          if (fix != null && !_blediyFeed.shouldFallbackToPhoneGps()) {
            _blediyActive = true;
            rec.externalGpsActive = true;
            rec.onExternalFix(fix.lat, fix.lon, fix.speedMps ?? rec.curSpeed,
                fix.bearingDeg ?? rec.curHeading, DateTime.now().millisecondsSinceEpoch,
                altM: fix.altitudeM);
            fedExternalFix = true;
          }
        }
      }
      if (e['type'] == 'sppNmea') {
        final line = (e['line'] ?? '').toString();
        if (line.isNotEmpty) {
          _blediyFeed.feedLine(line);
          final fix = _blediyFeed.latest;
          if (fix != null && !_blediyFeed.shouldFallbackToPhoneGps()) {
            _blediyActive = true;
            rec.externalGpsActive = true;
            rec.onExternalFix(fix.lat, fix.lon, fix.speedMps ?? rec.curSpeed,
                fix.bearingDeg ?? rec.curHeading, DateTime.now().millisecondsSinceEpoch,
                altM: fix.altitudeM);
            fedExternalFix = true;
          }
        }
      }
      // v1.2.14 排空时序：外接 GPS（BLE/SPP，25Hz）的定位点由此回调
      // 直接落点，不经过手机定位回调；此前排空只在手机定位事件里
      // 跑，实时显示最多滞后约 1 秒。在此同样触发一次排空，只改
      // 触发时机，不改排空逻辑、不改落点/存储频率（见 _drainLapTimer）。
      if (fedExternalFix) unawaited(_drainLapTimer());
      // v1.4.x 街道语音：外接 GPS 定位同样刷新 GPS 看门狗（手机定位
      // 回调不经过外接路径；只刷新看门狗，不跑超速/里程等街道播报，
      // 那些仍以手机定位回调的 noteStreetLocation 为准）。
      if (fedExternalFix && rec.isRecording && !trackMode) {
        VoiceService.instance.noteExternalFix();
      }
      if (e['type'] == 'sppDisconnected') {
        _blediyFeed.reset();
        _blediyActive = false;
        rec.externalGpsActive = false;
      }
      if (e['type'] == 'disconnected') {
        _blediyFeed.reset();
        _blediyActive = false;
        rec.externalGpsActive = false;
      }
      rec.onBleData(e);
      if (e['type'] == 'connected') {
        bleConnected = e['address'] as String?;
        if (bleConnected != null) {
          unawaitedSaveBle(bleConnected!);
        }
      }
      if (e['type'] == 'disconnected') bleConnected = null;
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  /// v1.2.14 排空时序：手机定位回调与外接 GPS 回调共用的 LapTimer
  /// 喂点排空。只触发排空：把 rec.points 里尚未喂入的点逐点喂给
  /// LapTimer（循环见顶层 drainLapTimerPoints，与 v1.2.13 的排空
  /// 循环逐行一致），不改排空逻辑、不改轨迹落点频率、不改存储频率。
  /// 圈速本身不受影响（addPoint 用点 timeMs 计时）。
  /// 外接 GPS（BLE/SPP，25Hz）下定位点不经过手机定位回调，
  /// 此前实时显示最多滞后约 1 秒，故外接数据回调里同样调一次
  /// 本方法。[_lapDrainRunning] 防并发：两次排空若同时在途，
  /// 第二次直接返回（在途那次恢复时已能看到全部已落点，不会丢点）；
  /// 否则两次排空可能各建一个 LapTimer，后建的会顶掉已喂点的那个，
  /// 造成计时丢失。
  Future<void> _drainLapTimer() async {
    // 赛道自动暂停中也要排空：定位点在自动暂停时继续落点，LapTimer
    // 靠这些点自己暂停 / 恢复计时（3 秒停车暂停、5 km/h 以上恢复），
    // 排空一停，计时器的自动恢复就收不到起步点。
    if (!trackMode || selectedTrack == null || (!rec.isRecording && !rec.isAutoPaused) || rec.points.isEmpty) return;
    if (_lapDrainRunning) return;
    _lapDrainRunning = true;
    try {
      liveLapTimer ??= await _buildLapTimer();
      final prevBest = liveLapTimer!.bestLap?.durationMs;
      final prevLapCount = liveLapTimer!.laps.length;
      // v1.4.x 赛道语音新增：发车圈过线（开始计时）与分段 Delta
      // 播报。排空前记下旧状态，排空后只报新增的部分，不重复报。
      final prevCrossed = liveLapTimer!.hasCrossedStartLine;
      final prevSectorCount =
          liveLapTimer!.currentCompletedSectorsMs.length;
      _lapFedCount = drainLapTimerPoints(liveLapTimer!, rec.points, _lapFedCount);
      // 计时真正开始（第一次过起终点线）后，才允许赛道自动暂停：
      // 起跑线前等待不暂停（见 Recorder.trackAutoPauseTick）。
      if (liveLapTimer!.hasCrossedStartLine) rec.trackTimingStarted = true;
      final nb = liveLapTimer!.bestLap;
      final lapCompleted = liveLapTimer!.laps.length > prevLapCount;
      if (!prevCrossed && liveLapTimer!.hasCrossedStartLine) {
        VoiceService.instance.announceTimingStarted();
      }
      // 分段 Delta：本排空内无完圈时才报（完圈会重置分段计数，
      // 旧圈段数与新圈段数不能混着比）；只报新增的段，参照圈为
      // 本节最快圈（排空内不产生新最快圈，参照口径不变）。
      if (!lapCompleted) {
        final done = liveLapTimer!.currentCompletedSectorsMs.length;
        final deltas = liveLapTimer!.currentSectorDeltasVsBest;
        for (var i = prevSectorCount; i < done; i++) {
          final d = i < deltas.length ? deltas[i] : null;
          if (d != null) {
            VoiceService.instance
                .announceSector(sectorIndex: i, deltaMs: d);
          }
        }
      }
      if (lapCompleted) {
        final done = liveLapTimer!.laps.last;
        if (done.counted) {
          final isBest =
              nb != null && done.durationMs == nb.durationMs;
          VoiceService.instance.announceLap(
              lapNumber: done.number,
              lapMs: done.durationMs,
              isBest: isBest,
              deltaVsBestMs: (!isBest && prevBest != null)
                  ? done.durationMs - prevBest
                  : null);
        }
      } else if (nb != null && nb.counted && prevBest != null && nb.durationMs < prevBest) {
        VoiceService.instance.announceLap(lapNumber: nb.number, lapMs: nb.durationMs, isBest: true);
      }
    } finally {
      _lapDrainRunning = false;
    }
  }

  Future<LapTimer> _buildLapTimer() async {
    final ts = await TrackSettingsStore.load();
    final args = ts.lapTimerArgs;
    // 赛道包起终点 / 分段点：仅当用户确实在该赛道附近（包起终点与
    // 记录首点 < 500m）才采用；否则回落记录首点（旧行为），避免
    // 在错误地点永远触发不了圈。无包起终点时同样回落旧行为。
    var startFinish = GeoPoint(rec.points.first.lat, rec.points.first.lon);
    var sectors = const <GeoPoint>[];
    final pkg = selectedPackage;
    // v1.2.17：维修区入口/出口（包 pitIn/pitOut，null = 待核）。
    // 只在包起终点/分段点同一 500m 门控内采用，门控外传 null；
    // 中心线传入逻辑不动（仍走 lapTimerCenterlineForPackage）。
    GeoPoint? pitIn;
    GeoPoint? pitOut;
    if (pkg != null && pkg.start != null && rec.points.isNotEmpty) {
      final d = haversineM(
        pkg.start!.lat,
        pkg.start!.lon,
        rec.points.first.lat,
        rec.points.first.lon,
      );
      if (d < 500) {
        startFinish = pkg.start!;
        sectors = pkg.sectorPoints;
        pitIn = pkg.pitIn;
        pitOut = pkg.pitOut;
      }
    }
    return LapTimer(
      startFinish: startFinish,
      crossingRadiusM: args.crossingRadiusM,
      dwellThresholdMs: args.dwellThresholdMs,
      dwellSpeedMs: args.dwellSpeedMs,
      // v1.5.4 赛道自动暂停：停车低于 2 km/h 满 3 秒暂停计时，
      // 车速回升到 5 km/h 以上恢复（迟滞防抖动）；与 Recorder 的
      // 赛道自动暂停同口径，两边一起停、一起恢复（见 track_timing.dart）。
      autoPauseThresholdMs: 3000,
      autoPauseSpeedMs: 2 / 3.6,
      autoResumeSpeedMs: 5 / 3.6,
      sectorPoints: sectors,
      pitIn: pitIn,
      pitOut: pitOut,
      // v1.2.14 越线检测接线：包中心线由此传入（起终点/分段点
      // 采用门控内的包才传，见 lapTimerCenterlineForPackage）；
      // 无包/无中心线时传 null，LapTimer 回落半径法。
      centerline: lapTimerCenterlineForPackage(
          pkg, GeoPoint(rec.points.first.lat, rec.points.first.lon)),
    );
  }

  /// 模式切换只改 rec.mode，不触碰记录流程；记录中不展示模式切换器。
  void _selectMode(TripMode m) {
    if (rec.mode == m) return;
    _modeController.animateToPage(m.index, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  /// 底部导航四页同壳：0 首页 / 1 设备 / 2 记录 / 3 我的。
  /// 设备中心不再 push 独立路由，切 tab 走与其它页相同的 AnimatedSwitcher。
  void _goTab(int i) {
    if (i < 0 || i > 3) return;
    setState(() => tab = i);
  }

  void _toggleMenu() {
    if (_menuAnim.value > 0.5) {
      _menuAnim.reverse();
    } else {
      _menuAnim.forward();
    }
  }

  void _closeMenu() {
    if (_menuAnim.value > 0) _menuAnim.reverse();
  }

  void _menuAction(VoidCallback action) {
    _closeMenu();
    Future.microtask(action);
  }

  // v1.0.2 菜单“安全说明”：改推独立免责声明页（disclaimer_page.dart）；
  // 关于页已不再放安全 / 免责区（见 about_page.dart）。
  // 方法名不用 _showSafety：该名已被开始记录前的安全守则流程占用。
  void _openSafetySection() {
    Navigator.push(
      context,
      DtPageRoute(builder: (_) => const DisclaimerPage()),
    );
  }

  // v0.1.5：关于从弹窗改成独立路由页（AboutPage）。v1.0.3 起关于
  // 只在左拉菜单里（设置页入口已删），点进同一页。
  void _showAbout() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => AboutPage(
          // v1.0.3 正式版显示：版本号显示值由本任务定为 1.0.3，
          // pubspec.yaml 同步改 1.0.3+15；
          // versionCode 不再在关于页展示，此处不再传旧值 10。
          versionName: '1.5.5',
          packageName: 'com.chixi.drive_track',
          channelLabel: '正式版',
          displayFont: appPrefs.displayFont,
          appIconKey: appPrefs.appIcon,
          updateConfig: const UpdateConfig.domestic(),
          onOpenBackup: () => Navigator.push(
            context,
            DtPageRoute(builder: (_) => DataExportPage(store: store)),
          ),
        ),
      ),
    );
  }

  /// v0.1.8 常亮开关：原生返回 false/抛错时不改 _keepScreenOnActual
  /// 为开启；关闭失败时保持旧值（flag 大概率仍在），不谎报已关闭。
  /// 另：FLAG_KEEP_SCREEN_ON 只属于当前窗口，Activity 销毁即失效，
  /// 这里的 dispose 关闭只是双保险，绝不让常亮在 App 退出后残留。
  Future<bool> _setKeepScreenOn(bool enable) async {
    try {
      final ok = await Native.setKeepScreenOn(enable);
      if (!mounted) return ok;
      setState(() {
        if (ok) {
          _keepScreenOnActual = enable;
          _keepScreenOnFailed = false;
        } else if (enable) {
          _keepScreenOnFailed = true;
        }
      });
      return ok;
    } catch (_) {
      if (mounted && enable) setState(() => _keepScreenOnFailed = true);
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_keepScreenOnActual) Native.setKeepScreenOn(false);
    _menuAnim.dispose();
    _modeController.dispose();
    _recMapPageController.dispose();
    _locSub?.cancel();
    _senSub?.cancel();
    _bleDevSub?.cancel();
    _bleDataSub?.cancel();
    _draftTimer?.cancel();
    rec.dispose();
    super.dispose();
  }

  /// v0.1.9 天气根因（查到的三点，修法对应下面三个方法）：
  /// ① _init 从不启动定位、从不拉天气：定位只在标定表/开录时才
  ///    startLocation，天气只在 locationStream 事件里 _maybeWeather
  ///    触发——刚进首页无定位事件时 weather 恒为 null，于是首屏
  ///    直接显示“天气未获取”，哪怕权限早已授予；
  /// ② 权限回调后没重拉：PermissionGate 走完授权不通知 HomePage，
  ///    HomePage 也没有 resumed 监听，设置页里刚给的权限要等下次
  ///    定位事件才生效；
  /// ③ 失败状态被缓存：旧 _maybeWeather 失败时不置任何失败标志，
  ///    weather 仍为 null，界面无法区分“加载中”与“已失败”，
  ///    也没有上次天气缓存可先显示。
  /// 修法：进首页权限已给即 startLocation + 立即拉取并显示加载态；
  /// resumed 与 _requestPerm 授予后都重拉；失败才置 weatherFailed
  /// 并给重试入口；有缓存先显示缓存 + “更新中…”；无权限时不拉
  /// 也不假装有天气（无缓存时仍显示未获取，但那是真实无权限态）。
  Future<void> _loadCachedWeather() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/weather_cache.json');
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      weather = WeatherInfo(
        (j['temp'] as num?)?.toDouble() ?? 0,
        (j['windSpeed'] as num?)?.toDouble() ?? 0,
        (j['windDir'] as num?)?.toDouble() ?? 0,
        (j['visibility'] as num?)?.toDouble() ?? 0,
        (j['code'] as num?)?.toInt() ?? 0,
        (j['precipProb'] as num?)?.toDouble() ?? 0,
        (j['summary'] as String?) ?? '',
      );
      weatherLat = (j['lat'] as num?)?.toDouble();
      weatherLon = (j['lon'] as num?)?.toDouble();
      weatherMs = (j['ms'] as num?)?.toInt() ?? 0;
      weatherFromCache = true;
    } catch (_) {}
  }

  Future<void> _saveCachedWeather() async {
    if (weather == null || weatherLat == null || weatherLon == null) return;
    try {
      final dir = await Native.getFilesDir();
      await File('$dir/weather_cache.json').writeAsString(jsonEncode({
        'lat': weatherLat,
        'lon': weatherLon,
        'ms': weatherMs,
        'temp': weather!.temp,
        'windSpeed': weather!.windSpeed,
        'windDir': weather!.windDir,
        'visibility': weather!.visibility,
        'code': weather!.code,
        'precipProb': weather!.precipProb,
        'summary': weather!.summary,
      }));
    } catch (_) {}
  }

  Future<void> _triggerWeatherOnLaunch() async {
    try {
      final status = await Native.checkPermissions();
      permGranted = (status['location'] == true);
    } catch (_) {
      permGranted = false;
    }
    if (!mounted) return;
    if (!permGranted) {
      // 无权限：不拉取、不假装有天气；有缓存时仍可显示缓存旧数据。
      setState(() => weatherLoading = false);
      return;
    }
    // v1.2.0：10 分钟新鲜度 + 位置短路——已有天气且在 10 分钟内
    // （且未移出缓存坐标 10 km）时不重拉，直接用缓存天气。
    if (weather != null &&
        !weatherNeedsRefresh(
          hasWeather: true,
          weatherMs: weatherMs,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          cachedLat: weatherLat,
          cachedLon: weatherLon,
          lat: weatherLat,
          lon: weatherLon,
        )) {
      setState(() => weatherLoading = false);
      return;
    }
    setState(() => weatherLoading = true);
    try {
      await Native.startLocation();
    } catch (_) {}
    // 有缓存坐标时不等首次定位事件，立即用缓存坐标拉一次；
    // 定位拿到后 locationStream 还会再触发一次刷新。
    if (weatherLat != null && weatherLon != null) {
      await _fetchWeatherAt(weatherLat!, weatherLon!);
      return;
    }
    if (rec.curLat != 0) {
      await _fetchWeatherAt(rec.curLat, rec.curLon);
    }
  }

  Future<void> _retryWeather() async {
    if (!mounted) return;
    setState(() {
      weatherFailed = false;
      weatherLoading = true;
    });
    await _triggerWeatherOnLaunch();
  }

  Future<void> _fetchWeatherAt(double lat, double lon) async {
    if (fetchingWeather) return;
    fetchingWeather = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mounted) setState(() => weatherLoading = true);
    final w = await fetchWeather(lat, lon);
    fetchingWeather = false;
    if (!mounted) return;
    if (w != null) {
      setState(() {
        weather = w;
        weatherLat = lat;
        weatherLon = lon;
        weatherMs = now;
        weatherLoading = false;
        weatherFailed = false;
        weatherFromCache = false;
        weatherStale = false;
      });
      await _saveCachedWeather();
    } else {
      setState(() {
        weatherLoading = false;
        if (weather == null) {
          weatherFailed = true;
        } else {
          weatherStale = true;
        }
      });
    }
  }

  Future<void> _maybeWeather(double lat, double lon, {bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // v1.2.0：与 _triggerWeatherOnLaunch 共用同一新鲜度口径
    // （10 分钟 + 移动 10 km），见 store.dart 的 weatherNeedsRefresh。
    final need = force ||
        weatherNeedsRefresh(
          hasWeather: weather != null,
          weatherMs: weatherMs,
          nowMs: now,
          cachedLat: weatherLat,
          cachedLon: weatherLon,
          lat: lat,
          lon: lon,
        );
    if (!need || fetchingWeather) return;
    await _fetchWeatherAt(lat, lon);
  }

  String get weatherText {
    if (weather == null) return '天气未获取：定位后自动拉取（Open-Meteo）';
    final alert = weather!.alert;
    return '天气 ${weather!.summary} · 风 ${weather!.windSpeed.toStringAsFixed(0)} km/h ${weather!.windDir.toStringAsFixed(0)}°'
        ' · 能见度 ${(weather!.visibility / 1000).toStringAsFixed(1)} km · 未来1小时降水 ${weather!.precipProb.toStringAsFixed(0)}%'
        '${alert.isEmpty ? '' : ' · $alert'}'
        '${weatherFromCache ? ' · 缓存数据' : ''}'
        '${weatherStale ? ' · 更新失败，显示缓存' : ''}';
  }

  // v0.1.1：接到分步授权 API，不再用旧打包请求。首屏已由 PermissionGate
  // 自动走完 foreground → extras → background；这里仅在开始记录/取天气/
  // 标定等残留触发点复查前台定位，未授予时只拉 foreground 一步。
  Future<void> _requestPerm() async {
    try {
      var status = await Native.checkPermissions();
      if (status['location'] != true) {
        await Native.requestStep('foreground');
        status = await Native.checkPermissions();
      }
      permGranted = (status['location'] == true);
    } catch (_) {
      permGranted = false;
    }
    if (mounted) setState(() {});
    // v1.2.0 开始记录延迟修复：权限通过后不再 await 天气——天气
    // 改为后台不 await 拉取（_showSafety 随即推倒计时页，不再被
    // 弱网天气拖住）；权限流程本身与 Recorder.start 均未动。
    if (permGranted) unawaited(_triggerWeatherOnLaunch());
  }

  Future<void> _showSafety() async {
    var goCalibrate = false;
    final mode = rec.mode;
    final isTrack = trackMode && mode != TripMode.bike;
    // 开始语音是否已触发过（本轮 _showSafety 只触发一次，防重复播报）。
    var safetySpoken = false;
    // v1.0.7：今日同一模式 + 同一档位已确认过，直接进倒计时，不再弹守则。
    if (!appPrefs.safetyAckedToday(mode, isTrack: isTrack)) {
      // 开始语音：弹窗出现时即开始口播安全注意事项（不 await、不阻塞
      // 弹窗，用户边看边听）；点确认后进倒计时页时由倒计时页停掉
      // 未播完部分。开关关闭时 speakSafety 内部直接返回，不发声。
      unawaited(VoiceService.instance
          .speakSafety(safetySpeechText(mode, isTrack: isTrack)));
      safetySpoken = true;
      // 街道前两条、赛道首条为红字置顶声明，其余正常显示。
      final redCount = isTrack ? 1 : 2;
      var skipToday = false;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
          final s = S.of(ctx);
          final items = safetyItems(mode, isTrack: isTrack, english: !s.zh);
          final modeName = switch (mode) {
            TripMode.car => s.t('汽车', 'Car'),
            TripMode.moto => s.t('摩托', 'Moto'),
            TripMode.bike => s.t('骑行', 'Ride'),
          };
          return AlertDialog(
            title: Text(s.t('$modeName安全守则', '$modeName safety')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            i < redCount ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            size: 20,
                            color: i < redCount ? Colors.red : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              items[i],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: i < redCount ? FontWeight.bold : FontWeight.normal,
                                color: i < redCount ? Colors.red : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(s.t('开录后界面锁定为 HUD，只留暂停 / 结束；结束需长按，防误触。', 'After start the HUD locks to pause and hold-to-end.'),
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  if (!rec.calibrated)
                    Text(s.t('未标定提示：G 值暂不进评分；开始后也可直线行驶标定，或点“先去标定”。', 'Not calibrated: G is not scored yet. Calibrate on a straight, or calibrate first.'),
                        style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  SwitchListTile(
                    value: skipToday,
                    title: Text(s.t('今日内不再弹出', "Don't show again today"), style: const TextStyle(fontSize: 14)),
                    onChanged: (v) => setD(() => skipToday = v),
                  ),
                ],
              ),
            ),
            actions: [
              if (!rec.calibrated)
                TextButton(
                  onPressed: () {
                    goCalibrate = true;
                    Navigator.pop(ctx, false);
                  },
                  child: Text(s.t('先去标定', 'Calibrate first')),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('取消', 'Cancel'))),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.t('一键确认，开始记录', 'Confirm and record')),
              ),
            ],
          );
        }),
      );
      if (ok != true) {
        if (goCalibrate) _showCalibrationSheet();
        return;
      }
      if (skipToday) await appPrefs.setSafetyAckedToday(mode, isTrack: isTrack);
    }
    await _requestPerm();
    if (!permGranted) {
      if (mounted) showAppNotice(context, S.of(context).t('需要定位权限才能记录轨迹', 'Location permission is required to record'), AppNoticeKind.warning);
      return;
    }
    // v0.1.3：安全守则 + 权限通过后不立刻开录，先推全屏倒计时页；
    // 倒计时页自己 pop 后调 onFinish，取消则什么都不做、不开录。
    if (!mounted) return;
    if (!safetySpoken) {
      // 今日已确认、跳过弹窗：点开始时仍播一次安全注意事项；
      // 倒计时页进入即停（播不完只听到开头，符合“当日已确认”的语义）。
      unawaited(VoiceService.instance
          .speakSafety(safetySpeechText(mode, isTrack: isTrack)));
    }
    final countdownMode = mode;
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => CountdownPage(
          vibrationEnabled: appPrefs.countdownVibration,
          // 开始语音开关：安全播报与倒数报数共用，语音设置页可关。
          speakCountdown: VoiceService.instance.settings.announceStart,
          onFinish: () => _beginRecording(countdownMode),
          onCancel: () {},
        ),
      ),
    );
  }

  /// 倒计时结束后的真正开录：视频启动 + rec.start（与旧 _showSafety 尾段一致）。
  Future<void> _beginRecording(TripMode mode) async {
    videoActive = false;
    videoError = null;
    if (videoEnabled && mode != TripMode.bike) {
      try {
        final cam = await Native.requestStep('camera');
        if (cam['camera'] == true) {
          final vr = await Native.startVideoRecording();
          if (vr['ok'] == true) {
            videoActive = true;
          } else {
            videoError = (vr['error'] as String?) ?? '视频未能启动，已继续仅轨迹记录';
          }
        } else {
          videoError = '未授予相机权限，已继续仅轨迹记录';
        }
      } catch (e) {
        videoError = '视频未能启动：$e，已继续仅轨迹记录';
      }
    }
    liveLapTimer = null;
    _lapFedCount = 0;
    livePhotoPoints = [];
    await rec.start();
    await _startDraftTimer();
    // v1.4.x 街道语音：开录即启动 GPS 信号看门狗与起步 / 里程计数
    //（赛道模式只计圈，不跑街道提示）。
    VoiceService.instance.setTripActive(true, isTrack: trackMode);
    // v0.1.8 熄屏根因是系统锁屏超时自动熄屏，不是定位权限问题：
    // 记录开始后按设置开关自动开常亮；暂停时仍在记录页，保持开启
    // 更安全（暂停 ≠ 结束，用户随时恢复，不应中途熄屏）。
    _keepScreenOnActual = false;
    _keepScreenOnFailed = false;
    if (appPrefs.keepScreenOn) {
      final ok = await _setKeepScreenOn(true);
      if (!ok && mounted) {
        showAppNotice(context, '常亮未开启：请检查系统设置，记录仍在继续', AppNoticeKind.warning);
      }
    }
    if (mounted) setState(() {});
  }

  /// v1.2.0 记录中标记事件：取最新轨迹点坐标，无轨迹点时用当前
  /// 定位快照；无定位时拒绝并提示，不存 (0,0) 假点。
  /// 标记时可写标题（≤50 字）、选类型（复用 photo_points.dart 的
  /// 类型与颜色）、可选照片、可选备注；无照片也可先标记，之后在
  /// 详情时间线附照片；一趟上限 50 条（store 层另有一道，保留前 50 条）。
  Future<void> _addEventMarker() async {
    double? lat, lon;
    var timeMs = DateTime.now().millisecondsSinceEpoch;
    if (rec.points.isNotEmpty) {
      final p = rec.points.last;
      lat = p.lat;
      lon = p.lon;
      timeMs = p.timeMs;
    } else if (rec.curLat != 0 || rec.curLon != 0) {
      lat = rec.curLat;
      lon = rec.curLon;
    }
    if (lat == null || lon == null || (lat == 0 && lon == 0)) {
      if (mounted) showAppNotice(context, '暂无定位，等定位出来后再标记', AppNoticeKind.warning);
      return;
    }
    if (livePhotoPoints.length >= kMaxPhotoPointsPerTrip) {
      if (mounted) showAppNotice(context, '一趟最多 50 条事件标记，已达上限', AppNoticeKind.warning);
      return;
    }
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var type = PhotoPointType.marker;
    var attachPhoto = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('标记事件'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                maxLength: 50,
                decoration: const InputDecoration(labelText: '标题（可选，≤50 字）'),
              ),
              Row(children: [
                const Text('类型：', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                DropdownButton<PhotoPointType>(
                  value: type,
                  items: [
                    for (final t in PhotoPointType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setD(() => type = v);
                  },
                ),
              ]),
              TextField(
                controller: noteCtrl,
                maxLength: 200,
                decoration: const InputDecoration(labelText: '备注（可选，≤200 字）'),
              ),
              SwitchListTile(
                value: attachPhoto,
                title: const Text('附照片（可选）'),
                onChanged: (v) => setD(() => attachPhoto = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('标记')),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    String? photoPath;
    if (attachPhoto) {
      photoPath = await pickOrTakePhoto(context);
      if (!mounted) return;
    }
    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    setState(() => livePhotoPoints.add(PhotoPoint(
          lat: lat!,
          lon: lon!,
          timeMs: timeMs,
          type: type,
          title: title.isEmpty ? null : title,
          note: note.isEmpty ? null : note,
          photoPath: photoPath,
        )));
    if (mounted) showAppNotice(context, '已标记 ${livePhotoPoints.length} 条 · 结束后在详情时间线查看', AppNoticeKind.success);
  }

  Future<void> _startDraftTimer() async {
    _draftTimer?.cancel();
    // 启动时选了“Later”留下的旧草稿：新录制会覆盖草稿文件，先把旧草稿
    // 存成行程（点数不足的直接丢弃），避免被新录制悄悄顶掉。
    final drafts = _drafts;
    if (drafts != null) {
      try {
        final old = await drafts.load();
        if (old != null && old.startMs != rec.startMs) {
          final saved = await drafts.recoverInto(store, old);
          if (saved == null) await drafts.clear();
          trips = await store.loadIndex();
        }
      } catch (_) {}
    }
    unawaited(_writeDraft());
    _draftTimer = Timer.periodic(const Duration(seconds: 30), (_) => _writeDraft());
  }

  /// 把当前录制状态写成草稿（原子写；上一次还没写完就跳过本次）。
  Future<void> _writeDraft() async {
    final drafts = _drafts;
    if (drafts == null || _draftWriting) return;
    if (rec.state != RecState.recording && rec.state != RecState.paused) return;
    _draftWriting = true;
    try {
      final mode = rec.mode;
      final isTrack = trackMode && selectedTrack != null && mode != TripMode.bike;
      await drafts.saveIncremental(RecordingDraft(
        mode: mode,
        startMs: rec.startMs,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
        points: List<TrackPoint>.from(rec.points),
        obdSamples: List<Map<String, dynamic>>.from(rec.obdSamples),
        photoPoints: List<PhotoPoint>.from(livePhotoPoints),
        trimPrivacy: trimPrivacy,
        riderKg: riderKg,
        weatherSummary: weather?.summary ?? '',
        isTrackMode: isTrack,
        trackId: isTrack ? selectedTrack!.id : null,
        trackName: isTrack ? selectedTrack!.nameCn : '',
        lapsJson: (isTrack && liveLapTimer != null)
            ? liveLapTimer!.laps.map((l) => l.toJson()).toList()
            : const [],
        vehicleId: _defaultVehicleIdForMode(mode),
      ));
    } catch (_) {
      // 草稿只是兜底，写失败不打扰正在进行的记录。
    } finally {
      _draftWriting = false;
    }
  }

  /// 启动时发现未结束的录制草稿：询问保存为行程 / 丢弃 / 稍后再说。
  Future<void> _offerDraftRecovery() async {
    final drafts = _drafts;
    if (drafts == null || !mounted) return;
    if (rec.state == RecState.recording || rec.state == RecState.paused) return;
    final d = await drafts.load();
    if (d == null || !mounted) return;
    if (d.points.length < kMinRecoverablePoints) {
      await drafts.clear();
      return;
    }
    final started = DateTime.fromMillisecondsSinceEpoch(d.startMs);
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unfinished recording'),
        content: Text('DriveTrack stopped while recording '
            '(started ${started.toString().substring(0, 16)}, ${d.points.length} points). '
            'Save what was recorded as a trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'later'), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save trip')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') {
      await drafts.clear();
      return;
    }
    if (choice != 'save') return;
    try {
      final trip = await drafts.recoverInto(store, d);
      trips = await store.loadIndex();
      if (!mounted) return;
      setState(() {});
      if (trip != null) {
        unawaited(_enrichNewTrip(trip));
        showAppNotice(context, 'Recovered trip saved', AppNoticeKind.success);
      }
    } catch (e) {
      if (mounted) showAppNotice(context, 'Could not recover the recording: $e', AppNoticeKind.error);
    }
  }

  Future<void> _endTrip() async {
    _draftTimer?.cancel();
    _draftTimer = null;
    final endMs = DateTime.now().millisecondsSinceEpoch;
    final pts = List<TrackPoint>.from(rec.points);
    final mode = rec.mode;
    final startMs = rec.startMs;
    List<String> videoPaths = [];
    if (videoActive) {
      try {
        videoPaths = await Native.stopVideoRecording();
      } catch (_) {}
      videoActive = false;
    }
    await rec.stop();
    // v1.4.x 街道语音：行程结束即停 GPS 信号看门狗（总结播报仍走
    // 下面的 announceSummary；行程太短未保存时同样停，不漏）。
    VoiceService.instance.setTripActive(false);
    // v0.1.8：记录结束（无论行程是否够长保存）都关闭常亮。
    await _setKeepScreenOn(false);
    if (pts.length < 10) {
      livePhotoPoints = [];
      await _drafts?.clear();
      if (mounted) {
        showAppNotice(context, videoPaths.isEmpty ? '行程太短，未保存（少于 10 个轨迹点）' : '行程太短未保存，但视频文件仍在本机视频目录，未关联行程', AppNoticeKind.warning);
      }
      return;
    }
    final isTrack = trackMode && selectedTrack != null && mode != TripMode.bike;
    final lapsJson = (isTrack && liveLapTimer != null)
        ? liveLapTimer!.laps.map((l) => l.toJson()).toList()
        : <Map<String, dynamic>>[];
    // v1.2.0：新行程绑定默认车辆（仅汽车/摩托且默认车辆模式
    // 相符时；骑行不绑定，模式不符不绑定，缺默认车辆不绑定）。
    final trip = await store.saveTrip(mode, startMs, endMs, pts,
        trim: trimPrivacy, riderKg: riderKg, weatherSummary: weather?.summary ?? '', videoPaths: videoPaths,
        trackId: isTrack ? selectedTrack!.id : null, trackName: isTrack ? selectedTrack!.nameCn : '',
        isTrackMode: isTrack, lapsJson: lapsJson,
        photoPoints: livePhotoPoints, vehicleId: _defaultVehicleIdForMode(mode),
        obdSamples: List<Map<String, dynamic>>.from(rec.obdSamples),
        startFinishLat: isTrack && pts.isNotEmpty ? pts.first.lat : null,
        startFinishLon: isTrack && pts.isNotEmpty ? pts.first.lon : null);
    // 正式行程已落盘，草稿作废（保存抛错时草稿保留，下次启动仍可恢复）。
    await _drafts?.clear();
    livePhotoPoints = [];
    liveLapTimer = null;
    _lapFedCount = 0;
    trips = await store.loadIndex();
    // 高德第一批：行程保存后后台做纠偏 + 逆地理编码（不阻塞保存与
    // 跳转，失败不丢原始数据；结果落盘后刷新列表，详情页可刷新/重纠）。
    unawaited(_enrichNewTrip(trip));
    _refreshTrackBestLaps();
    VoiceService.instance.announceSummary(
      distanceKm: trip.distanceM / 1000,
      durationMs: endMs - startMs,
      score: trip.score,
      bestLapMs: (() { final cs = trip.lapsJson.map((j) => Lap.fromJson(j)).where((l) => l.counted).map((l) => l.durationMs).toList()..sort(); return cs.isEmpty ? null : cs.first; })(),
    );
    if (mounted) {
      setState(() {});
      // v1.2.0：赛道行程结束跳赛道分析页（不用街道版结束页），
      // 街道行程仍走原详情页。
      if (isTrack) {
        final laps = trip.lapsJson.map((j) => Lap.fromJson(j)).toList();
        Navigator.push(context, DtPageRoute(builder: (_) => TrackAnalysisPage(trip: trip, laps: laps, obdConnected: obdStatus.value.connected)));
      } else {
        Navigator.push(context, DtPageRoute(builder: (_) => TripDetailPage(store: store, tripId: trip.id)));
      }
    }
  }

  /// 高德第一批：新行程后台 enrichment（轨迹纠偏 + 逆地理编码）。
  /// - 无 Key 时直接跳过（不发无 Key 请求）；
  /// - 境外行程（起终点任一在中国粗框外）跳过全部高德调用，状态记 skipped；
  /// - 纠偏仅汽车/摩托街道行程；逆地理编码对所有新行程做（含骑行与赛道）；
  /// - 纠偏先置 pending 再发请求，避免详情页重复触发；全程 try/catch，
  ///   失败只写 failed/空地名，绝不影响已保存的原始行程；
  /// - 只对本次新保存的行程生效，不改写历史行程。
  Future<void> _enrichNewTrip(Trip trip) async {
    try {
      if (amapWebKey.isEmpty) return;
      if (trip.points.isEmpty || !tripInChina(trip.points)) {
        await store.updateTripEnrichment(trip.id,
            correctionStatus: 'skipped');
        trips = await store.loadIndex();
        if (mounted) setState(() {});
        return;
      }
      final correctable = !trip.isTrackMode &&
          (trip.mode == TripMode.car || trip.mode == TripMode.moto);
      if (correctable) {
        await store.updateTripEnrichment(trip.id,
            correctionStatus: 'pending');
      }
      List<(double lat, double lon)>? corrected;
      if (correctable) {
        try {
          corrected = await correctTrackPoints(trip.points);
        } catch (_) {
          corrected = null;
        }
      }
      String? startPlace, endPlace;
      try {
        startPlace = (await reverseGeocode(
                trip.points.first.lat, trip.points.first.lon))
            ?.shortName;
      } catch (_) {}
      try {
        endPlace = (await reverseGeocode(
                trip.points.last.lat, trip.points.last.lon))
            ?.shortName;
      } catch (_) {}
      await store.updateTripEnrichment(trip.id,
          correctedPoints: corrected,
          correctionStatus: correctable
              ? (corrected != null ? 'done' : 'failed')
              : 'skipped',
          startPlace: startPlace,
          endPlace: endPlace);
      trips = await store.loadIndex();
      if (mounted) setState(() {});
    } catch (_) {
      // 后台任务任何异常都不打扰用户；详情页可手动重纠/刷新。
    }
  }

  /// v1.2.0：默认车辆 id（模式相符才返回，否则 null = 回退全局值）。
  String? _defaultVehicleIdForMode(TripMode mode) {
    final lib = vehicleLibrary;
    final def = lib?.defaultVehicle;
    if (def == null) return null;
    if (mode == TripMode.car && def.mode == VehicleMode.car) return def.id;
    if (mode == TripMode.moto && def.mode == VehicleMode.moto) return def.id;
    return null;
  }

  /// v1.2.0：刷新赛道行程最佳圈映射（列表卡片用；加载失败或无
  /// 计入圈时为 null，卡片显示“暂无圈速”，不编圈速）。
  Future<void> _refreshTrackBestLaps() async {
    final map = <String, int?>{};
    for (final m in trips) {
      if (!m.isTrackMode) continue;
      final t = await store.loadTrip(m.id);
      if (t == null) {
        map[m.id] = null;
        continue;
      }
      final counted = t.lapsJson.map((j) => Lap.fromJson(j)).where((l) => l.counted).map((l) => l.durationMs).toList();
      map[m.id] = counted.isEmpty ? null : counted.reduce(math.min);
    }
    if (mounted) setState(() => trackBestLapMs = map);
  }

  @override
  Widget build(BuildContext context) {
    // v0.1.3 菜单手感：改前 350ms 线性 → 改后 200ms easeOutCubic（起手快），
    // 位移/缩放/圆角由同一动画值同步驱动；AnimatedBuilder 的 child 参数
    // 缓存主界面，动画帧不再重建地图/轨迹/G 图（只做变换），避免重活拖帧。
    // 只改菜单这一处，页面切换、倒计时等节奏不动。
    // M4：左拉菜单宽随屏宽收窄（320dp 屏上取屏宽 85%，其余 280），
    // 与 _buildMenuPanel 里的面板宽取同值，保持面板与位移一致；
    // MediaQuery 宽度不可用（≤0，如测试里被覆盖的 MediaQuery）时回落到 280。
    final screenW = MediaQuery.of(context).size.width;
    final menuW = screenW <= 0
        ? 280.0
        : (screenW * 0.85 < 280.0 ? screenW * 0.85 : 280.0);
    return AnimatedBuilder(
      animation: _menuAnim,
      builder: (_, child) {
        final tt = Curves.easeOutCubic.transform(_menuAnim.value);
        return Stack(children: [
          _buildMenuPanel(),
          Transform.translate(
            offset: Offset(menuW * tt, 0),
            child: Transform.scale(
              scale: 1 - 0.08 * tt,
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18 * tt),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: tt > 0
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(-8, 0))]
                        : null,
                  ),
                  child: GestureDetector(
                    onTap: _menuOpen ? _closeMenu : null,
                    onHorizontalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -300) _closeMenu();
                    },
                    child: AbsorbPointer(
                      absorbing: _menuOpen,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
      child: RepaintBoundary(child: _buildMainScaffold()),
    );
  }

  /// v1.0.4 记录页时速大数字颜色：<60 白、60–100 黄、>100 红。
  /// 边界：60 与 100 本身为黄（60–100 含两端），仅 >100 为红。
  static Color _speedColor(double kmh) =>
      kmh < 60 ? Colors.white : (kmh <= 100 ? Colors.yellow : Colors.red);

  /// v1.5.1 横屏门控的当前状态：true = 已放开横屏（记录态）。
  /// 只在状态变化时调平台通道，避免每帧重复调用。
  bool _orientationLandscapeAllowed = false;

  void _applyRecordingOrientation(bool recording) {
    final allow = recording;
    if (allow == _orientationLandscapeAllowed) return;
    _orientationLandscapeAllowed = allow;
    unawaited(SystemChrome.setPreferredOrientations(
      allow
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    ));
  }

  Widget _buildMainScaffold() {
    final recording = rec.isRecording || rec.state == RecState.paused;
    // v1.5.1 横屏门控：只在记录态（街道计时 / 赛道计时）放开横屏，
    // 其余页面一律竖屏；状态变化时才调一次平台通道，不每帧调用。
    _applyRecordingOrientation(recording);
    final isLandscapeRecording = recording &&
        MediaQuery.of(context).orientation == Orientation.landscape;
    // v1.0.5：删掉 navSafe 底部安全区公式。内容不再为药丸留空，
    // 直接延伸到屏幕底边、从药丸下方划过；药丸周边不再是空底色条，
    // 而是页面内容本身透过毛玻璃可见。用户明确不要为“最后一条完整
    // 露出”再把底部 padding 加回去。
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      // v1.5.1：横屏记录时不显示 App 顶栏（用户要求：横屏只专注计时），
      // 顶栏隐藏后记录页顶垫只留状态栏高（见 _buildRecording）。
      appBar: isLandscapeRecording
          ? null
          : DtAppBar(
        // v1.0.2 顶部按钮去边框：无圆形外框/圆形背景块的纯图标按钮，
        // 图标保留、点击区 44×44（SizedBox 定死，不用 GlassButton 的圆底）。
        leading: SizedBox(
          width: 44,
          height: 44,
          child: Semantics(
            label: S.of(context).t('菜单', 'Menu'),
            child: IconButton(
              icon: const Icon(Icons.menu, size: 22),
              padding: EdgeInsets.zero,
              onPressed: _toggleMenu,
            ),
          ),
        ),
        centerTitle: true,
        title: Text('DriveTrack', style: TextStyle(fontFamily: appPrefs.displayFont, fontWeight: FontWeight.w700)),
        actions: [
          // v1.0.2 同上：右设置钮去边框，点击区 44×44。
          SizedBox(
            width: 44,
            height: 44,
            child: Semantics(
              label: S.of(context).t('设置', 'Settings'),
              child: IconButton(
                icon: const Icon(Icons.settings, size: 22),
                padding: EdgeInsets.zero,
                onPressed: _openSettings,
              ),
            ),
          ),
        ],
      ),
      // v1.0.5：真正的独立悬浮药丸，不再是正常流底部栏。
      // Stack：内容 Positioned.fill 不加任何底部 padding，直接延伸到
      // 屏幕底边、从药丸下方划过；导航 Positioned 悬浮在内容上方；
      // Positioned 区域本身不带任何背景容器，没有方形模块背景。
      // 药丸底部位置直接算：12 + 系统底部 inset（药丸内不再用 SafeArea
      // 垫空底色区），可视位置与之前含 SafeArea 时一致。
      // 记录中导航仍隐藏。
      body: Stack(children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim), child: child),
            ),
            child: recording
                ? KeyedSubtree(key: const ValueKey('recording'), child: _buildRecording())
                : tab == 0
                    ? KeyedSubtree(key: const ValueKey('home'), child: _buildModePages())
                    : tab == 1
                        ? KeyedSubtree(
                            key: const ValueKey('devices'),
                            child: const DeviceCenterPage(embedded: true))
                        : tab == 2
                            ? KeyedSubtree(key: const ValueKey('list'), child: _buildList())
                            : KeyedSubtree(key: const ValueKey('my'), child: _buildMyPage()),
          ),
        ),
        if (!recording)
          Positioned(
            bottom: 12 + bottomInset,
            left: 0,
            right: 0,
            child: Center(
              child: FrostedGlassNavBar(
                // 页 tab 与导航栏一一对应：0 首页 / 1 设备 / 2 记录 / 3 我的。
                selectedIndex: tab.clamp(0, 3),
                onTap: _goTab,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _avatar(double r) {
    final path = appPrefs.avatarPath;
    if (path != null && File(path).existsSync()) {
      return CircleAvatar(radius: r, backgroundImage: FileImage(File(path)));
    }
    return CircleAvatar(
      radius: r,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Text(appPrefs.username.isEmpty ? '?' : appPrefs.username.characters.first,
          style: TextStyle(fontSize: r, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _buildMenuPanel() {
    final s = S.of(context);
    // v1.1.0 菜单底部描述溢出根因与修法：
    // 根因：面板在 Stack 里没有宽度约束，ListView 把面板撑到全屏宽，
    // 副标题按全屏宽排版成单行；但主界面只右移 280px，面板实际只露
    // 左边 280px 一条，底部较长的副标题（如性能测试、设备管理）在主
    // 界面边缘被硬裁，看起来就是“底部描述超出显示范围”。不是底部
    // inset 或药丸遮挡：SafeArea 已处理系统 inset，药丸随主界面右移、
    // 并不压在菜单上；也不是 ListTile 本身不换行——它在 280px 内会换行，
    // 只是之前从没拿到过 280px 的约束。
    // 修法：面板宽与主界面右移量同值（280，窄屏取屏宽 85%），副标题在面板宽内
    // 内自动换行，列表本身已是 ListView（可滚动），小屏与大字体下
    // 最后一项也可滚出来，不再被裁切。
    // M4：与 build 里主界面右移量取同值（320dp 屏上 272，其余 280）；
    // MediaQuery 宽度不可用（≤0）时回落到 280。
    final screenW = MediaQuery.of(context).size.width;
    final menuW = screenW <= 0
        ? 280.0
        : (screenW * 0.85 < 280.0 ? screenW * 0.85 : 280.0);
    return SizedBox(
      width: menuW,
      child: Material(
      color: const Color(0xFF0B0E13),
      child: Container(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(children: [
              _avatar(24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${appPrefs.username} · ${appPrefs.userId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  const Text('/ DriveTrack', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          const Divider(color: Colors.white12),
          // v0.1.7 菜单简化去重 + v1.0.3 关于移入菜单 + v1.0.4 性能测试
          // 移入菜单（红字加粗）：赛道库 / 赛道知识库 / 性能测试 /
          // 数据导出/备份 / 免责声明 / 关于六项。设备中心已移到
          // 底部导航第 4 项（v1.5.4），不再占菜单一项。
          // 首页与记录页入口已删，性能测试只剩这一处入口，仍进同一
          // performance_challenge.dart。关闭动画仍为 200ms easeOutCubic
          // 主界面右移（build 里的 _menuAnim，不动）。
          Expanded(
            child: ListView(children: [
              ListTile(leading: const Icon(Icons.flag), title: Text(s.t('赛道库', 'Track library')), subtitle: Text(s.t('赛道数据包、版本与更新', 'Track packages and updates')), onTap: () => _menuAction(_openTrackLibrary)),
              ListTile(leading: const Icon(Icons.menu_book), title: Text(s.t('赛道知识库', 'Track guide')), subtitle: Text(s.t('旗语 · 规则 · 赛事架构 · 驾驶技术', 'Flags, rules, and driving')), onTap: () => _menuAction(_openTrackKnowledge)),
              ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.red),
                  title: Text(s.t('性能测试', 'Performance'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: Text(s.t('0-100 加速 / 100-0 刹停 · 仅封闭场地测试', '0-100 / 100-0 · closed course only')),
                  onTap: () => _menuAction(_openPerformanceChallenge)),
              ListTile(leading: const Icon(Icons.file_download), title: Text(s.t('数据导出/备份', 'Export / backup')), subtitle: Text(s.t('按行程分享 GPX / CSV', 'Share a trip as GPX / CSV')), onTap: () => _menuAction(_openDataExport)),
              ListTile(leading: const Icon(Icons.warning_amber_rounded), title: Text(s.t('免责声明', 'Disclaimer')), subtitle: Text(s.t('使用前必读：安全须知与责任说明', 'Read before use')), onTap: () => _menuAction(_openSafetySection)),
              ListTile(leading: const Icon(Icons.info_outline), title: Text(s.t('关于', 'About')), subtitle: Text(s.t('版本号、在线更新、反馈与备份', 'Version, updates, feedback, backup')), onTap: () => _menuAction(_showAbout)),
            ]),
          ),
        ]),
      ),
      ),
      ),
    );
  }

  // v1.0.3：底部导航已改回毛玻璃药丸（lib/frosted_nav_bar.dart 的
  // FrostedGlassNavBar，无滚动放大、无切换拉伸、无选中放大），
  // 悬浮方式与尺寸（192×60、bottom 12、SafeArea）在新组件与
  // _buildMainScaffold 的 Positioned 里保持不变。

  /// 模式横滑切换：三页共用同一份首页主体（不复制三份），图标点按与滑动双向联动。
  /// v0.1.2 首页正常流布局（重叠清单见最终回执）：
  /// 模式行 → 标定 chip + 视频勾选行 → 细长天气条 → PageView 滚动区。
  /// 全部是 Column + 间距，关键信息不再用 Stack/Positioned 硬叠。
  // v0.1.3 天气页：用扩展服务拉 Open-Meteo 全量字段，失败则用旧摘要兜底。
  Future<void> _openWeatherPage() async {
    final lat = rec.curLat != 0 ? rec.curLat : (weatherLat ?? 31.2304);
    final lon = rec.curLon != 0 ? rec.curLon : (weatherLon ?? 121.4737);
    final data = await fetchExtendedWeather(lat, lon);
    if (!mounted) return;
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => WeatherPage(
          weather: data,
          headingDeg: rec.curHeading,
          onRefresh: () {
            Navigator.pop(context);
            _openWeatherPage();
          },
        ),
      ),
    );
  }

  List<WeatherStripSegment> get _weatherSegments {
    if (weather == null) {
      // v0.1.9：加载中与已失败分开显示；未获取只在拉取失败后出现。
      if (weatherLoading) {
        return [const WeatherStripSegment(Icons.cloud, '天气加载中…')];
      }
      return [const WeatherStripSegment(Icons.cloud, '天气未获取：点按下方重试（Open-Meteo）')];
    }
    IconData iconFor(String part) {
      if (part.contains('雨') || part.contains('雪')) return Icons.umbrella;
      if (part.contains('风')) return Icons.air;
      if (part.contains('能见度') || part.contains('雾')) return Icons.visibility;
      if (part.contains('降水')) return Icons.water_drop;
      return Icons.cloud;
    }

    final segments = weatherText.split(' · ').map((p) => WeatherStripSegment(iconFor(p), p)).toList();
    // v0.1.9：已有天气时加载中不清空旧天气，追加“更新中…”段。
    if (weatherLoading) segments.add(const WeatherStripSegment(Icons.refresh, '更新中…'));
    return segments;
  }

  // v0.1.5 赛道/街道切换：从模式图标行正下方移到标定与开始记录
  // 两个大方块的正上方、紧贴大方块（见 _buildModePages 的顺序），
  // 街道为默认；骑行模式不显示（返回空占位）。
  // 赛道选择器紧随药丸开关下方展开，复用菜单赛道目录的同一底部表。
  Widget _buildSurfaceSwitch() {
    if (rec.mode == TripMode.bike) return const SizedBox.shrink();
    return ModeSwitchSection(
      surface: trackMode ? DriveSurface.track : DriveSurface.street,
      enabled: !rec.isRecording,
      onSurfaceChanged: (s) => setState(() {
        trackMode = s == DriveSurface.track;
        rec.roadSnapEnabled = !trackMode;
        if (!trackMode) {
          selectedTrack = null;
          selectedPackage = null;
        }
      }),
      trackSelector: trackMode
          ? OutlinedButton.icon(
              icon: const Icon(Icons.flag, size: 16),
              label: Text(selectedTrack == null
                  ? '选择赛道'
                  : '${selectedTrack!.nameCn}（约 ${selectedTrack!.lengthKm?.toStringAsFixed(3) ?? '?'} km）'),
              onPressed: _openTrackCatalogSheet,
            )
          : null,
    );
  }

  Widget _buildModePages() {
    // v1.0.6 首页正常流（天气条上移）：天气条 → 模式行 → PageView →
    // 街道/赛道药丸开关（汽车/摩托，紧贴大方块上方）→ 下方并排
    // 大方块（标定 / 开始记录）。天气条本身的滚动、点按进天气页、
    // 拉取失败重试入口逻辑一律不动，只是位置上移：重试入口跟天气条
    // 一起移到模式行上方。v0.1.4 的模式图标正下方切换已删，
    // 不要再放回去；天气点按进独立天气页。
    final weatherStrip = Padding(
      // v1.4.2：顶栏改半透 + 主框架 extendBodyBehindAppBar，顶部叠加
      // 状态栏 + AppBar 高，天气条静止时才不会藏进顶栏后（横竖屏共用）。
      padding: EdgeInsets.fromLTRB(16, 6 + appBarTopInset(context), 16, 8),
      child: WeatherStrip(segments: _weatherSegments, onTap: _openWeatherPage),
    );
    // 横屏：固定 Column 会溢出（天气条 + 模式行 + 切换行 + 128 大方块
    // + 底部留白 ≈ 400，高于横屏可用高约 304），改整页滚动、
    // PageView 给定高 220；竖屏保持原结构（Expanded PageView +
    // 大方块贴底）。各段内容、回调全不动，只改组装方式。
    // v0.1.9：拉取失败才出现的重试入口（加载中与已有天气时不出现）。
    // v1.0.6：跟天气条一起移到模式行上方，逻辑不动。
    final retryEntry = (weatherFailed && weather == null)
        ? Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试获取天气'),
              onPressed: _retryWeather,
            ),
          ),
        )
        : const SizedBox.shrink();
    final modePageView = PageView(
      controller: _modeController,
      onPageChanged: (i) => rec.setMode(TripMode.values[i]),
      children: [for (final _ in TripMode.values) _buildIdleHome()],
    );
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      return SingleChildScrollView(
        // v1.4.2：显式零 padding——不吃主框架 extendBodyBehindAppBar
        // 带来的 MediaQuery 顶垫，顶垫只由 weatherStrip 的一处叠加承担，
        // 否则横屏顶部会多出一倍空隙。
        padding: EdgeInsets.zero,
        child: Column(children: [
          weatherStrip,
          retryEntry,
          _buildModeSwitcher(),
          SizedBox(height: 220, child: modePageView),
          _buildDevicePills(),
          _buildSurfaceSwitch(),
          _homeBottomButtons(),
        ]),
      );
    }
    return Column(children: [
      weatherStrip,
      retryEntry,
      _buildModeSwitcher(),
      Expanded(child: modePageView),
      _buildDevicePills(),
      _buildSurfaceSwitch(),
      _homeBottomButtons(),
    ]);
  }

  /// 首页外接 GPS 状态小药丸（v1.5.2，v1.5.3 起并入设备药丸行）：
  /// 硬件接入状态可视化。只读全局 externalGpsStatus（设备中心写入，
  /// 唯一来源），本身不猜状态、不改连接逻辑。纯状态显示（v1.5.4）：
  /// 不可点、不跳转，状态只看圆点颜色（绿 = 已连接，灰 = 未连接）。
  /// - 已连接：绿点 + 卫星图标 + 设备名（无名时只显示“外接 GPS”），
  ///   BLE 通道另带蓝牙小图标；
  /// - 未连接：灰点 + 卫星图标 + “未连接外接 GPS”。
  Widget _buildGpsStatusPill() {
    return ValueListenableBuilder<ExternalGpsStatus>(
      valueListenable: externalGpsStatus,
      builder: (context, status, _) {
        final s = S.of(context);
        final connected = status.connected;
        final name = status.deviceName.trim();
        final channel = status.channel.trim().toUpperCase();
        final chLabel = channel.isEmpty ? '' : ' · $channel';
        final activeNote = status.binaryOnly
            ? s.t(' · 已连接(无定位)', ' · connected (no fix)')
            : s.t(' · 定位中', ' · fixing');
        final gpsWord = s.t('外接 GPS', 'External GPS');
        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: CardStyle.cardColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: connected
                  ? Colors.green.withValues(alpha: 0.5)
                  : CardStyle.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? Colors.green : Colors.white38,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.satellite_alt,
                size: 15,
                color: connected ? Colors.green : Colors.white54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  connected
                      ? (name.isEmpty
                          ? '$gpsWord$chLabel$activeNote'
                          : '$gpsWord · $name$chLabel$activeNote')
                      : s.t('手机 GPS · 外接未连接', 'Phone GPS · external off'),
                  style: TextStyle(
                    color: connected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (connected && status.channel == 'ble') ...[
                const SizedBox(width: 6),
                const Icon(Icons.bluetooth,
                    size: 13, color: Colors.white54),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 首页运动相机状态小药丸（v1.5.3 攒版）：与 GPS 药丸同一样式
  /// （34 高圆角药丸、CardStyle 底色）。只读全局 cameraLinkStatus
  /// （相机页唯一写入），本身不猜状态、不改连接流程。纯状态显示
  /// （v1.5.4）：不可点、不跳转，状态只看圆点颜色（绿 = 已连接，
  /// 琥珀 = 连接中，灰 = 未连接 / 暂不可用）。
  /// - 已连接：绿点 + 相机图标 + “运动相机 · 已连接”；
  /// - 连接中：琥珀点 + “运动相机 · 连接中…”；
  /// - 暂不可用：灰点 + “运动相机 · 暂不可用”；
  /// - 未连接：灰点 + “未连接运动相机”。
  Widget _buildCameraStatusPill() {
    return ValueListenableBuilder<DeviceLinkStatus>(
      valueListenable: cameraLinkStatus,
      builder: (context, status, _) {
        final s = S.of(context);
        final connected = status == DeviceLinkStatus.connected;
        final connecting = status == DeviceLinkStatus.connecting;
        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: CardStyle.cardColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: connected
                  ? Colors.green.withValues(alpha: 0.5)
                  : CardStyle.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? Colors.green
                      : connecting
                          ? Colors.amber
                          : Colors.white38,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.videocam,
                size: 15,
                color: connected ? Colors.green : Colors.white54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  switch (status) {
                    DeviceLinkStatus.connected => s.t('运动相机 · 已连接', 'Camera · connected'),
                    DeviceLinkStatus.connecting => s.t('运动相机 · 连接中…', 'Camera · connecting…'),
                    DeviceLinkStatus.unavailable => s.t('运动相机 · 暂不可用', 'Camera · unavailable'),
                    DeviceLinkStatus.disconnected => s.t('未连接运动相机', 'Camera not connected'),
                  },
                  style: TextStyle(
                    color: connected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 首页设备状态药丸行（v1.5.3 攒版）：外接 GPS 药丸 + 运动相机药丸
  /// 并排，放在街道/赛道模式选择上方。两颗同一样式，各自只读全局状态。
  Widget _buildDevicePills() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Flexible(child: _buildGpsStatusPill()),
          const SizedBox(width: 8),
          Flexible(child: _buildCameraStatusPill()),
        ],
      ),
    );
  }

  /// 录制页 OBD + 缺口推算小药丸（v1.5.2 攒版）：放在 GPS 来源徽标
  /// 下方，与首页 GPS 药丸同一样式（34 高圆角药丸、CardStyle 底色）。
  /// - OBD 已连接：只读全局 obdStatus，绿点 + 实时车速（无读数时
  ///   只写“OBD · 已连接”），点按进设备中心；未连接不出现；
  /// - 缺口状态：只读 rec.gapStatus，estimating 时琥珀色
  ///   “正在推算位置”，lost 时橙色“GPS 信号丢失”，ok 时不出现。
  /// 两颗都不出现时返回空占位，不占高度。
  Widget _buildObdAndGapPills() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<ObdStatus>(
            valueListenable: obdStatus,
            builder: (context, st, _) {
              if (!st.connected) return const SizedBox.shrink();
              final speed = st.speedKmh;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _recordingPill(
                  dotColor: Colors.green,
                  icon: Icons.speed,
                  label: speed == null
                      ? 'OBD · 已连接'
                      : 'OBD · ${speed.toStringAsFixed(0)} km/h',
                  onTap: _openDeviceCenter,
                ),
              );
            },
          ),
          ValueListenableBuilder<GapStatus>(
            valueListenable: rec.gapStatus,
            builder: (context, gs, _) {
              if (gs == GapStatus.estimating) {
                return _recordingPill(
                  dotColor: Colors.amber,
                  icon: Icons.timeline,
                  label: '正在推算位置',
                );
              }
              if (gs == GapStatus.lost) {
                return _recordingPill(
                  dotColor: Colors.orange,
                  icon: Icons.gps_off,
                  label: 'GPS 信号丢失',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  /// 录制页小药丸共用外形（34 高、圆角 999、CardStyle 底色）。
  Widget _recordingPill({
    required Color dotColor,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: CardStyle.cardColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: dotColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: dotColor),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 15, color: dotColor),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  /// 首页底部大方块（标定 / 开始记录）。
  /// v1.0.4：首页性能测试入口卡已删，入口只在左拉菜单（红字加粗）。
  Widget _homeBottomButtons() {
    // v1.0.6：只修首页大方块贴底回归。首页竖屏是固定 Column（非滚动页），
    // v1.0.5 删掉主框架 navSafe 后大方块直接贴底边、与悬浮药丸重叠。
    // 只给大方块外层 Padding 加底部留白，不把主框架 Positioned.fill
    // 的底部 padding 加回去，不动滚动页（我的页/记录页仍从药丸下方
    // 划过、透过毛玻璃可见）。横屏时本页整页滚动，留白照旧。
    // 底部留白 = 药丸高 56 + 药丸底部 12 + 系统底部 inset + 间隙 12
    //          = 80 + MediaQuery.of(context).padding.bottom（实时算，
    //            不写死固定数）；大方块本身 128 高、圆角、内容、逻辑不动。
    return Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, kPillNavHeight + 12 + MediaQuery.of(context).padding.bottom + 12),
        child: BigActionButtons(
          calibrationState: rec.waitingCalibration
              ? CalibrationButtonState.calibrating
              : (rec.calibrated ? CalibrationButtonState.calibrated : CalibrationButtonState.uncalibrated),
          // v0.1.9：校准页（设置页入口）与本大方块共用 rec 状态：
          // 车头标定成功后两处同步显示；零偏已校时追加一行状态。
          calibrationDetail: rec.calibrated && rec.calibratedAtMs != null
              ? '${fmtDate(rec.calibratedAtMs!)} · 车头已锁定${rec.zeroBiasAtMs != null ? ' · 零偏已校' : ''}'
              : null,
          onCalibrate: _showCalibrationSheet,
          onStartRecording: _showSafety,
          startSubtitle: trackMode && selectedTrack != null ? '赛道：${selectedTrack!.nameCn}' : null,
          // v0.1.5：赛道模式下开始记录大方块右上角方格旗角标。
          showTrackBadge: trackMode && rec.mode != TripMode.bike,
        ),
      );
  }

  void _showCalibrationSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rec.calibrationNote, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('把手机固定在支架上，点“开始标定”后直线行驶到 18 km/h 以上，自动锁定车头方向。未标定时 G 圆灰色，不进评分。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _requestPerm();
              rec.beginCalibration();
              await Native.startLocation();
              await Native.startSensors();
            },
            child: const Text('开始标定'),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  /// v0.1.10 改回原来：Row 居中紧凑布局，每项左右 margin 14，
  /// 图标 36px 不变，整行宽度 = 3 × 64 = 192（kModeRowWidth），
  /// 不再用 Expanded 三等分撑满屏宽；底部导航栏用同一宽度，
  /// 两行同长、按钮中心点重合。
  Widget _buildModeSwitcher() {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final m in TripMode.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
              child: RippleTap(
                circular: true,
                onTap: () => _selectMode(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Column(children: [
                    AnimatedScale(
                      scale: rec.mode == m ? 1.25 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: ModeVehicleIcon(mode: m, selected: rec.mode == m, color: rec.mode == m ? accent : Colors.white54, size: 36),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: rec.mode == m ? 18 : 6,
                      height: 3,
                      decoration: BoxDecoration(
                        color: rec.mode == m ? accent : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // v0.1.2 我的页社交架构（本地骨架，不做假社交）：
  //  顶部个人资料（头像/用户名/ID/简介，可编辑）← profile.json
  //  统计行（行程数/总里程/总时长/平均评分）← 真实行程（演示除外）
  //  社交行（关注/粉丝/获赞）← 关注、粉丝本机为 0 空态；获赞 = 本人公开
  //    行程的本机点赞计数之和（初始 0，不编数）
  //  分区：我的行程（公开开关）/ 我的动态（仅公开行程）/ 收藏
  //    （favorites.json）/ 成就（由真实行程条件算出，未达成灰显）
  //  公开仅指本机标记 + 对外分享，不宣称有服务器社区。
  List<TripMeta> get _realTrips => trips.where((t) => !t.demo).toList();

  // v0.1.7 当月油耗汇总（v1.2.1 起记录页不再用，仅我的页用同一口径）：
  // 按开始时间过滤当月，演示行程不计入；总里程含全部模式，
  // 油耗/花费仅汽车/摩托；未填油耗/油价时油耗/花费为 null，
  // 显示“未填写”而不是 0。计算见 fuel_page.dart。
  MonthlyFuelSummary _monthlyFuelSummary() => summarizeMonthlyFuel(
        trips: trips
            .map((m) => FuelTripInput(mode: m.mode, distanceM: m.distanceM, startMs: m.startMs, demo: m.demo))
            .toList(),
        now: DateTime.now(),
        consumptionLPer100Km: appPrefs.fuelConsumptionLPer100Km,
        fuelPricePerLiter: appPrefs.fuelPricePerLiter,
      );

  List<(String, bool)> _achievements() {
    final real = _realTrips;
    final dist = real.fold(0.0, (a, m) => a + m.distanceM);
    final modes = real.map((m) => m.mode).toSet();
    return [
      ('首次记录', real.isNotEmpty),
      ('10 次行程', real.length >= 10),
      ('累计 100 km', dist >= 100000),
      ('累计 500 km', dist >= 500000),
      ('单次评分 90+', real.any((m) => m.score >= 90)),
      ('三种模式都跑过', modes.length >= 3),
    ];
  }

  /// v1.5.1：点“编辑”推全页编辑页（ProfileEditPage），不再弹对话框、
  /// 不再在卡片内展开编辑器。保存回调：先写本机 profile.json，再
  /// 同步云端公开资料；本机已存、云端失败只报提示、不回滚本机。
  Future<void> _editProfile() async {
    await Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => ProfileEditPage(
          username: appPrefs.username,
          bio: appPrefs.bio,
          email: appPrefs.email,
          gender: appPrefs.gender,
          birthday: appPrefs.birthday,
          industry: appPrefs.industry,
          vehicleBrand: appPrefs.vehicleBrand,
          vehicleModel: appPrefs.vehicleModel,
          avatarPath: appPrefs.avatarPath,
          onPickAvatar: () async => await Native.pickFile('image'),
          onSave: (r) async {
            appPrefs.username = r.username;
            appPrefs.bio = r.bio;
            appPrefs.email = r.email;
            appPrefs.gender = r.gender;
            appPrefs.birthday = r.birthday;
            appPrefs.industry = r.industry;
            appPrefs.vehicleBrand = r.vehicleBrand;
            appPrefs.vehicleModel = r.vehicleModel;
            if (r.avatarPath != null) appPrefs.avatarPath = r.avatarPath;
            await appPrefs.save();
            if (mounted) setState(() {});
            // 公开资料同步：昵称/简介/扩展字段写 profiles 表，头像传公开桶；
            // 本机资料已存，云端失败只报提示、不回滚本机。
            // 未配置云端时不弹提示（本机保存即预期行为，云端卡片会说明）。
            final pr = await CloudService.instance.saveProfile(
              nickname: r.username,
              bio: r.bio,
              avatarLocalPath: r.avatarPath,
              gender: r.gender,
              birthday: r.birthday,
              industry: r.industry,
              vehicleBrand: r.vehicleBrand,
              vehicleModel: r.vehicleModel,
            );
            if (mounted && !pr.notConfigured) {
              showAppNotice(
                context,
                pr.message,
                pr.ok ? AppNoticeKind.success : AppNoticeKind.error,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _shareInvite() async {
    try {
      await Native.shareFiles([], 'text/plain', '来驰迹 DriveTrack 看看我的行程：${appPrefs.username}（${appPrefs.userId}）。行程数据仅存本机，分享走系统分享。');
    } catch (_) {}
  }

  // v0.1.3：我的页换新版 MyPage（卡片化、细圆角进度条、药丸按钮），
  // 数据全部来自真实行程；关注/粉丝本机为 0 时新页显示“暂无”，不造假。
  Widget _buildMyPage() {
    final s = S.of(context);
    final real = _realTrips;
    final totalDist = real.fold(0.0, (a, m) => a + m.distanceM);
    final totalDur = real.fold(0, (a, m) => a + (m.endMs - m.startMs));
    final avgScore = real.isEmpty ? 0.0 : real.fold(0.0, (a, m) => a + m.score) / real.length;
    final totalLikes = real.where((m) => m.isPublic).fold(0, (a, m) => a + m.likes);
    MyTripItem item(TripMeta m) => MyTripItem(
          id: m.id,
          title: '${s.t(m.mode.label, switch (m.mode) { TripMode.car => 'Car', TripMode.moto => 'Moto', TripMode.bike => 'Ride' })} · ${(m.distanceM / 1000).toStringAsFixed(2)} km · ${s.t('评分', 'Score')} ${m.score.toStringAsFixed(0)}',
          // 高德逆地理编码：两端地名都有时追加“起点 → 终点”，缺一端时
          // 不拼半句（只显示日期），避免“地名 → 终点”这种半成品。
          subtitle: '${fmtDate(m.startMs)}${m.startPlace.isNotEmpty && m.endPlace.isNotEmpty ? ' · ${m.startPlace} → ${m.endPlace}' : ''}',
          isFavorite: favorites.contains(m.id),
          isPublic: m.isPublic,
          onTap: () => Navigator.push(context, DtPageRoute(builder: (_) => TripDetailPage(store: store, tripId: m.id))),
          onToggleFavorite: () async {
            favorites = await store.toggleFavorite(m.id);
            if (mounted) setState(() {});
          },
          onTogglePublic: () async {
            final nt = await store.updateTripSocial(m.id, isPublic: !m.isPublic);
            trips = await store.loadIndex();
            if (mounted) setState(() {});
            // 已上传的行程改公开标记后重新发布（搬桶 + 改云端行）；
            // 没上传过的下次上传时按新标记走对应桶。
            if (nt != null &&
                CloudService.instance.queueStatusFor(m.id) ==
                    CloudUploadStatus.done) {
              final r = await CloudService.instance.republishTrip(nt);
              if (mounted) {
                showAppNotice(
                  context,
                  r.message,
                  r.ok ? AppNoticeKind.success : AppNoticeKind.error,
                );
              }
            }
          },
        );
    return MyPage(
      avatarPath: appPrefs.avatarPath,
      username: appPrefs.username,
      userId: appPrefs.userId,
      bio: appPrefs.bio,
      email: appPrefs.email,
      onEditProfile: _editProfile,
      onShareInvite: _shareInvite,
      onStartRecording: () => _goTab(0),
      stats: [
        MyStat(label: s.t('行程', 'Trips'), value: '${real.length}'),
        // v0.1.9：千分位 + 自适应字号（my_page.dart 内 FittedBox 不换行），
        // 如 123456.7 km → “123,456.7 km”，不截断、不折行。
        MyStat(label: s.t('总里程', 'Distance'), value: formatDistanceKm(totalDist / 1000)),
        MyStat(label: s.t('总时长', 'Time'), value: fmtDur(totalDur)),
        MyStat(label: s.t('平均评分', 'Avg score'), value: avgScore.toStringAsFixed(0)),
      ],
      // v0.1.7 当月汇总：与记录页同一函数、同一口径；未填写时
      // 油耗/花费显示“未填写”，不是 0。
      monthlyStats: (() {
        final summary = _monthlyFuelSummary();
        return [
          MyStat(label: s.t('本月里程', 'Month km'), value: '${summary.totalDistanceKm.toStringAsFixed(1)} km'),
          MyStat(label: s.t('本月油耗', 'Fuel'), value: summary.totalLiters == null ? s.t('未填写', 'Not set') : '${summary.totalLiters!.toStringAsFixed(2)} L'),
          MyStat(label: s.t('本月花费', 'Cost'), value: summary.totalCost == null ? s.t('未填写', 'Not set') : '${summary.totalCost!.toStringAsFixed(2)}'),
        ];
      })(),
      monthlyNote: s.t('里程含全部模式。油耗与花费仅汽车/摩托估算，演示不计。', 'Distance includes all modes. Fuel cost is a car/moto estimate.'),
      following: 0,
      followers: 0,
      likes: totalLikes,
      trips: real.map(item).toList(),
      posts: real.where((m) => m.isPublic).map(item).toList(),
      favorites: real.where((m) => favorites.contains(m.id)).map(item).toList(),
      achievements: _achievements().map((a) => MyAchievement(title: a.$1, achieved: a.$2, progress: a.$2 ? 1 : 0)).toList(),
      initialSection: MyPageSection.values[myTab.clamp(0, 3)],
      onSectionChanged: (sec) => setState(() => myTab = MyPageSection.values.indexOf(sec)),
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  Color _vehicleColor(TripMode m) {
    final sel = appPrefs.vehicleSelection;
    return m == TripMode.moto ? sel.moto.accent : Theme.of(context).colorScheme.primary;
  }

  // v0.1.3：设置改为独立路由页（不再是弹窗）。顶部、菜单、我的页都进同一页。
  // 旧弹窗里的主题/自带字体/头像/隐私截断/传感器重连/人车重量行已保留在
  // 设置页的“更多”区与对应入口里（见 settings_page.dart 末尾的扩展区，
  // 统合时通过回调接回 _showSensors / 字体导入 / 头像导入），不丢功能。
  // v0.1.4：设置改为入口列表页（SettingsHomePage），每行一个子页；
  // 旧长页 SettingsPage 不再从主界面进入，资料编辑入口已从设置侧移除。
  void _openSettings() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => SettingsHomePage(
          onOpenPermission: _openPermissionSettings,
          onOpenTheme: _openThemeSettings,
          onOpenVoice: _openVoiceSettings,
          onOpenTrack: _openTrackSettings,
          onOpenLocation: _openLocationSettings,
          // v0.1.9：设置页传感器校准入口（复用现有标定逻辑，见 sensor_calibration_page.dart）。
          onOpenSensorCalibration: _openSensorCalibration,
          onOpenDevices: _openDeviceCenter,
          onOpenMapImport: _openMapImport,
          // v0.1.7 油耗费用入口（设置页“地图车标”之后，见 settings_home_page.dart）。
          onOpenFuel: () => Navigator.push(context, DtPageRoute(builder: (_) => FuelSettingsPage(
                initialConsumption: appPrefs.fuelConsumptionLPer100Km,
                initialPrice: appPrefs.fuelPricePerLiter,
                onSaved: (c, p) => appPrefs.setFuelSettings(c, p),
              ))),
          // v1.2.0 车辆档案入口（油耗费用之后）。
          onOpenVehicle: _openVehicleProfiles,
          countdownVibration: appPrefs.countdownVibration,
          onCountdownVibrationChanged: (v) => appPrefs.setCountdownVibration(v),
          keepScreenOn: appPrefs.keepScreenOn,
          onKeepScreenOnChanged: (v) => appPrefs.setKeepScreenOn(v),
          recordingMap3d: appPrefs.recordingMap3d,
          onRecordingMap3dChanged: (v) => appPrefs.setRecordingMap3d(v),
          videoRecording: videoEnabled,
          onVideoRecordingChanged: (v) => setState(() => videoEnabled = v),
          trimPrivacy: trimPrivacy,
          onTrimPrivacyChanged: (v) => setState(() => trimPrivacy = v),
        ),
      ),
    );
  }

  // v0.1.5：设置子页的直达入口（供 _openSettings 的入口列表与
  // 侧拉菜单“设置快捷”共用，同一子页不写两套跳转逻辑）。
  /// v1.2.0 车辆档案入口：推 VehicleProfilePage；onChanged 里
  /// 保存车辆库，检测到车辆被删时用 Store 批量回退绑定行程
  /// （行程本身不删），随后刷新索引与列表。
  Future<void> _openVehicleProfiles() async {
    final lib = await store.loadVehicleLibrary();
    if (!mounted) return;
    var prevIds = lib.vehicles.map((v) => v.id).toSet();
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => VehicleProfilePage(
          initialProfiles: lib.vehicles,
          initialFuelLogs: lib.fuelLogs,
          initialDefaultVehicleId: lib.defaultVehicleId,
          onChanged: (next) async {
            await store.saveVehicleLibrary(next);
            final deleted = prevIds.where((id) => !next.vehicles.any((v) => v.id == id)).toList();
            for (final id in deleted) {
              await store.rebindTripsAfterVehicleDeleted(id);
            }
            prevIds = next.vehicles.map((v) => v.id).toSet();
            vehicleLibrary = next;
            trips = await store.loadIndex();
            _refreshTrackBestLaps();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _openPermissionSettings() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => PermissionSettingsPage(
          videoRecording: videoEnabled,
          onVideoRecordingChanged: (v) => setState(() => videoEnabled = v),
          bluetoothEnabled: bleEnabled,
          onBluetoothChanged: (v) => setState(() => bleEnabled = v),
          voiceEnabled: VoiceService.instance.settings.enabled,
          onVoiceChanged: (v) => VoiceService.instance.updateSettings(VoiceService.instance.settings.copyWith(enabled: v)),
        ),
      ),
    );
  }

  void _openThemeSettings() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => ThemeSettingsPage(
          initial: ThemeChoice(accent: appPrefs.themeColor, presetId: appPrefs.themePreset),
          onAccentChanged: (c) => appPrefs.setThemeChoice(c),
          vehicleMarkerInitial: appPrefs.vehicleSelection,
          onVehicleMarkerChanged: (sel) => appPrefs.setVehicleSelection(sel),
          // v1.0.3：APP 图标切换——先持久化选择，再调原生切桌面 alias；
          // 原生失败也不丢选择，下次冷启动按持久化选择重新同步。
          appIconInitial: appPrefs.appIcon,
          onAppIconChanged: (key) async {
            await appPrefs.setAppIcon(key);
            await Native.setAppIcon(key);
          },
          // v1.0.4：字体设置从设置首页移入主题设置页（同一功能，不新建）。
          hasCustomFont: appPrefs.customFontPath != null,
          onImportFont: () async {
            final path = await Native.pickFile('font');
            if (path != null) {
              await appPrefs.applyCustomFont(path);
              if (mounted) setState(() {});
            }
          },
          onClearFont: appPrefs.customFontPath == null
              ? null
              : () async {
                  await appPrefs.clearCustomFont();
                  if (mounted) setState(() {});
                },
        ),
      ),
    );
  }

  // v1.2.1：赛道专区页（TrackHomePage：赛道行程分组 + 赛道库 +
  // 分析 + 模式说明），由记录页“赛道专区”卡片进入。
  void _openTrackHome() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => TrackHomePage(
          metas: trips,
          bestLapMsByTripId: trackBestLapMs,
          loadTrip: store.loadTrip,
        ),
      ),
    );
  }

  /// 抽屉“赛道库”入口：直推赛道库页（数据包管理器）。
  void _openTrackLibrary() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => TrackLibraryPage(
          metas: trips,
          loadTrip: store.loadTrip,
        ),
      ),
    );
  }

  // v1.5.2：左侧菜单“赛道知识库”入口，静态参考页（9 分类 × 25 篇），
  // 内容见 track_knowledge.dart，规则以当年规则与当日简报为准。
  void _openTrackKnowledge() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => const TrackKnowledgePage(),
      ),
    );
  }

  // v1.0.2：性能测试挑战主入口（首页）与记录页小入口共用同一页。
  void _openPerformanceChallenge() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => PerformanceChallengePage(
          onBack: () => Navigator.of(context).pop(),
          recorder: rec,
        ),
      ),
    );
  }

  void _openVoiceSettings() {
    Navigator.push(context, DtPageRoute(builder: (_) => const VoiceSettingsPage()));
  }

  void _openTrackSettings() {
    Navigator.push(
        context,
        DtPageRoute(
            builder: (_) => TrackSettingsPage(
                  onChanged: (ts) {
                    if (mounted) {
                      setState(() => _showTrackDelta = ts.showDelta);
                    }
                  },
                  onOpenDeviceCenter: _openDeviceCenter,
                  onOpenSensorCalibration: _openSensorCalibration,
                )));
  }

  void _openLocationSettings() {
    Navigator.push(context, DtPageRoute(builder: (_) => const SatelliteSettingsPage()));
  }

  // v0.1.9 传感器校准页：车头标定启动复用旧标定底部表同一流程
  // （权限复查 + beginCalibration + startLocation + startSensors）。
  void _openSensorCalibration() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => SensorCalibrationPage(
          recorder: rec,
          onStartHeadingCalibration: () async {
            await _requestPerm();
            rec.beginCalibration();
            await Native.startLocation();
            await Native.startSensors();
          },
        ),
      ),
    );
  }

  void _openMapImport() {
    Navigator.push(
      context,
      DtPageRoute(
        builder: (_) => MapImportPage(
          onRequestImport: (kind) async {
            final path = await Native.pickFile('file');
            if (path == null) return null;
            final extErr = checkSupportedExtension(path);
            if (extErr != null) return MapImportResult.fail(extErr);
            try {
              final res = await mis.MapImportService.instance.importFile(File(path));
              final pageKind = res.kind == 'tiles'
                  ? MapImportKind.tileZip
                  : res.kind == 'overlay'
                      ? (res.format == 'kml' ? MapImportKind.kml : MapImportKind.geojson)
                      : MapImportKind.styleJson;
              return MapImportResult.ok(ImportedMapResource(
                id: res.id, name: res.name, kind: pageKind, enabled: res.enabled, sizeBytes: 0,
              ));
            } on mis.MapImportException catch (e) {
              return MapImportResult.fail(e.message);
            } catch (e) {
              return MapImportResult.fail('导入失败：$e');
            }
          },
          onToggle: (r) => mis.MapImportService.instance.setEnabled(r.id, r.enabled),
          onDelete: (r) => mis.MapImportService.instance.deleteResource(r.id),
        ),
      ),
    );
  }

  void _openDataExport() {
    Navigator.push(
      context,
      DtPageRoute(builder: (_) => DataExportPage(store: store)),
    );
  }

  /// 赛道选择（赛道库版）：底部弹出包列表，选中即把该包定为本次赛道
  /// （trackMode=true + selectedTrack 为包适配的 TrackInfo +
  /// selectedPackage 为包本身，供计时取经纬度起终点 / 分段点）。
  /// 行首 ⓘ 打开简介页（官方条目走 TrackDetailPage，用户赛道走
  /// TrackPackageInfoPage），简介页点“在赛道模式中使用该赛道”时
  /// 以条目 / 包作为结果返回，本处再设为本次赛道并关闭选择器。
  /// 骑行模式下选了赛道也不会进赛道计时（_endTrip 的 isTrack 判定
  /// 排除骑行），切回汽车/摩托后该选择仍有效。
  void _openTrackCatalogSheet() async {
    final snap = await TrackLibraryService.instance.loadAll();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TrackPackageSelector(
              packages: snap.official,
              userTracks: snap.userTracks,
              selectedId: selectedTrack?.id,
              onSelected: (pkg) {
                setState(() {
                  trackMode = true;
                  rec.roadSnapEnabled = false;
                  selectedTrack = trackInfoForPackage(pkg);
                  selectedPackage = pkg;
                });
                Navigator.pop(ctx);
              },
              onInfo: (pkg) async {
                final entry = encyclopediaTracks
                    .where((e) => e.id == pkg.id)
                    .firstOrNull;
                if (entry != null) {
                  final picked = await Navigator.push<EncyclopediaTrack>(
                    ctx,
                    DtPageRoute(
                      builder: (_) => TrackDetailPage(
                        track: entry,
                        package: pkg,
                      ),
                    ),
                  );
                  if (picked != null && ctx.mounted) {
                    setState(() {
                      trackMode = true;
                      rec.roadSnapEnabled = false;
                      selectedTrack = trackInfoForPackage(pkg);
                      selectedPackage = pkg;
                    });
                    Navigator.pop(ctx);
                  }
                } else {
                  final picked = await Navigator.push<TrackPackage>(
                    ctx,
                    DtPageRoute(
                      builder: (_) => TrackPackageInfoPage(package: pkg),
                    ),
                  );
                  if (picked != null && ctx.mounted) {
                    setState(() {
                      trackMode = true;
                      rec.roadSnapEnabled = false;
                      selectedTrack = trackInfoForPackage(picked);
                      selectedPackage = picked;
                    });
                    Navigator.pop(ctx);
                  }
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openDeviceCenter() {
    // 底栏设备页：与记录/我的同壳同切换动画。若当前不在主壳
    //（例如设置子页），仍 push 独立页（带返回），chrome 保持可用。
    final route = ModalRoute.of(context);
    final onRoot = route?.isFirst ?? true;
    if (onRoot) {
      setState(() => tab = 1);
      return;
    }
    Navigator.push(
      context,
      DtPageRoute(builder: (_) => const DeviceCenterPage()),
    );
  }

  Future<void> _showSensors() async {
    // 下次自动连上次设备（本机文件持久化，非云端）
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/last_ble.txt');
      if (await f.exists() && bleConnected == null) {
        final last = (await f.readAsString()).trim();
        if (last.isNotEmpty) await Native.connectBle(last);
      }
    } catch (_) {}
    await Native.startBleScan();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('骑行传感器（BLE）'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (rec.bleBatteryNote != null) Text(rec.bleBatteryNote!, style: const TextStyle(color: Colors.orange)),
              Text('已连接：${bleConnected ?? '无'}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              if (bleDevices.isEmpty) const Text('正在扫描…请把传感器唤醒（转动曲柄 / 踩踏）'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: bleDevices.map((d) {
                    final addr = d['address'] as String? ?? '';
                    return ListTile(
                      title: Text(d['name'] as String? ?? addr),
                      subtitle: Text('${d['type'] as String? ?? '未知'} · 信号 ${d['rssi'] ?? ''}'),
                      trailing: bleConnected == addr ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () async {
                        await Native.connectBle(addr);
                        setD(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () async => Native.disconnectBle(), child: const Text('断开'))),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await Native.zeroCalibrate();
                      if (context.mounted) showAppNotice(context, '已向功率计发送归零请求（设备支持时生效）', AppNoticeKind.success);
                    },
                    child: const Text('功率计归零'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              // v0.1.3 外接设备中心：运动相机 + 其他传感器 + BleDIY GPS 入口。
              OutlinedButton.icon(
                icon: const Icon(Icons.devices),
                label: const Text('外接设备中心（运动相机 / 其他传感器 / BleDIY GPS）'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openDeviceCenter();
                },
              ),
              
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Native.stopBleScan();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('关闭'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildIdleHome() {
    // v1.0.8：两颗药丸下移到本页屏幕中间。做法不是固定大间距
    // （小屏会溢出、大屏仍偏上），而是三段式真居中：
    // 本页是 PageView 里 Expanded 的一页、高度有界，LayoutBuilder
    // 拿到该页高度后，SingleChildScrollView 内用 ConstrainedBox
    //（minHeight = 页高 − 纵向 padding 8+24）把 Column 撑满整页，
    // Column 用 spaceBetween 在“实时行 / 药丸组 / 底部组”三段间
    // 均分剩余空间：顶部组约 32 高、底部组汽车/摩托约 20 高，
    // 药丸组中心因此只比页中心低约 6px，上下留白大致均衡；
    // 骑行模式底部组多了传感器按钮，偏移仍在 20px 内。
    // 内容高于一页时 ConstrainedBox 不再撑高、Column 自然变长，
    // 仍可滚动，不溢出。药丸顺序、间距、开关逻辑、默认值、
    // 骑行隐藏视频药丸、提示文案、卫星实时数、切换失败提示全不动。
    final topGroup = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // v0.1.2：天气条与标定已移到上方正常流（见 _buildModePages），
      // 首页滚动区不再放天气按钮、大标定卡、演示入口。
      const SizedBox(height: 12),
      Center(child: Text('本次实时：${(rec.curSpeed * 3.6).toStringAsFixed(0)} km/h · G ${rec.curLongG.toStringAsFixed(2)} / ${rec.curLatG.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white70))),
    ]);
    // v1.0.0：两颗药丸同宽 kTogglePillWidth = 280（见 satellite_pill.dart），
    // 之间 SizedBox 高 10；开关逻辑与默认值不动。
    // （CompactTogglePill：视觉高 32 / 字 14 / 整行可点区 44），
    // 两颗药丸上下排在同一区域、同一 Column 内居中对齐；只改
    // 开关组件与布局，视频录制逻辑（videoEnabled → _beginRecording
    // 的相机/录像流程）原封不动，默认仍关闭。
    final pillsGroup = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rec.mode != TripMode.bike)
        Center(
          child: CompactTogglePill(
            icon: Icons.videocam,
            label: S.of(context).t('同步视频记录', 'Sync video'),
            value: videoEnabled,
            onChanged: (v) => setState(() => videoEnabled = v),
          ),
        ),
      // v1.0.0：两颗药丸之间明确间距 10（框线/阴影只在各自药丸
      // 容器内，不再视觉挤在一起）；骑行模式无视频药丸时此间距
      // 不出现，卫星药丸直接接在实时行下方。
      if (rec.mode != TripMode.bike) const SizedBox(height: 10),
      if (videoEnabled && rec.mode != TripMode.bike)
        Center(child: Text(S.of(context).t('同步视频：已开启（开始后以后置摄像头录像）', 'Sync video on. Rear camera starts with recording.'), style: const TextStyle(color: Colors.white54, fontSize: 12))),
      if (videoError != null)
        Center(child: Text('视频提示：$videoError', style: const TextStyle(color: Colors.orange, fontSize: 12))),
      // v0.1.5：开始前快速开关改成与定位子页同款紧凑 pill
      // （视觉高 32 / 字 14 / 整行可点区 44）。AnimatedBuilder 跟随
      // SatelliteService，卫星数实时更新；暂无快照时显示“—”，不编数。
      Center(
        child: AnimatedBuilder(
          animation: SatelliteService.instance,
          builder: (_, __) {
            final svc = SatelliteService.instance;
            return CompactSatellitePill(
              value: appPrefs.directSatellite,
              satelliteCount: svc.latest == null ? null : svc.visibleCount,
              onChanged: (v) async {
                final r = await SatelliteService.instance.setDirectMode(v);
                if ((r['ok'] as bool?) == true) {
                  await appPrefs.setDirectSatellite(v);
                  if (mounted) setState(() {});
                } else if (mounted) {
                  showAppNotice(context, '直连卫星切换失败：${r['error'] ?? '请先授予定位权限'}', AppNoticeKind.error);
                }
              },
            );
          },
        ),
      ),
    ]);
    final bottomGroup = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 20),
      if (rec.mode == TripMode.bike)
        OutlinedButton.icon(icon: const Icon(Icons.bluetooth), label: const Text('骑行传感器'), onPressed: _showSensors),
      if (rec.bleBatteryNote != null)
        Text(rec.bleBatteryNote!, style: const TextStyle(color: Colors.orange, fontSize: 12)),
    ]);
    return LayoutBuilder(builder: (context, constraints) {
      final centered = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [topGroup, pillsGroup, bottomGroup],
      );
      // PageView 约束有界时才做撑满居中；无界时退回普通滚动列，
      // 避免 Expanded/撑满约束在无界高度下报错。
      if (!constraints.maxHeight.isFinite) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: centered,
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: centered,
        ),
      );
    });
  }

  /// v1.3.2：记录页分页指示点（圆点 + 文字），点按切页。
  Widget _recMapPageTab(int index, String label) {
    final active = _recMapPageIndex == index;
    return RippleTap(
      onTap: () {
        if (_recMapPageIndex != index) {
          _recMapPageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFE10600) : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording() {
    final s = S.of(context);
    final cLat = rec.curLat != 0 ? rec.curLat : (rec.points.isNotEmpty ? rec.points.last.lat : 31.2304);
    final cLon = rec.curLon != 0 ? rec.curLon : (rec.points.isNotEmpty ? rec.points.last.lon : 121.4737);
    final now = DateTime.now().millisecondsSinceEpoch;
    final trail = rec.gHistory.where((g) => now - g.timeMs <= 5000).toList();
    // 赛道面板判定只看模式选择，不看 liveLapTimer：计时器是首个 GPS 点
    // 到达后才异步建成，旧条件（timer != null）会让赛道模式开局回落
    // 到街道 3D 地图，这就是“很大概率还是街道界面”的根因。
    final isTrackPage = trackMode && selectedTrack != null;
    // v1.5.4 赛道自动暂停开关：赛道模式开、街道模式关（街道绝不
    // 自动暂停，见 Recorder.trackAutoPauseTick）。
    rec.trackAutoPauseEnabled = isTrackPage;
    // v1.2.17：暂停/恢复切换（500ms 内连点防抖）；赛道紧凑按钮与
    // 街道半宽按钮共用同一份逻辑，只改布局，不改行为。
    Future<void> togglePause() async {
      final now = DateTime.now();
      if (_lastPauseTap != null &&
          now.difference(_lastPauseTap!).inMilliseconds < 500) return;
      _lastPauseTap = now;
      if (rec.isRecording) {
        await rec.pause();
      } else {
        await rec.resume();
      }
      setState(() {});
    }
    // v1.3.4：幽灵车（实时 Map 页）——参考圈取本节最佳圈
    // （liveLapTimer.bestLap），按当前圈已用时长插值出位置；
    // 门控缺一不可：赛道模式 + 有最佳圈 + 已过发车圈（currentLapNumber
    // >= 1）+ 不在维修区内 + 当前圈已开始计时。街道模式不传（全 null）。
    // 口径说明：currentLapMs 已扣暂停、参考圈切片 elapsed 是原始时间；
    // 计入圈不会有超 30 秒停留（停留圈不计入最佳圈），漂移可忽略。
    final ghostPos = (isTrackPage &&
            liveLapTimer != null &&
            liveLapTimer!.bestLap != null &&
            liveLapTimer!.currentLapNumber >= 1 &&
            !liveLapTimer!.inPit &&
            liveLapTimer!.currentLapMs != null)
        ? ghostPositionForLap(
            rec.points, liveLapTimer!.bestLap!, liveLapTimer!.currentLapMs!)
        : null;
    // v1.3.5：地图过线后才出现——赛道叠加层门控取 LapTimer 派生状态
    // hasCrossedStartLine（第一次通过起终点线后为真并保持到本节结束），
    // 与幽灵车门控“有最佳圈”不是同一个状态：发车圈过线后第 1 圈才开始，
    // 此时叠加层已出现、幽灵车仍须等最佳圈。街道模式不受门控影响
    // （showTrackOverlayFor 内 !isTrack 即为真）。
    final hasCrossedStartLine = liveLapTimer?.hasCrossedStartLine ?? false;
    final showTrackOverlay = showTrackOverlayFor(
      isTrack: isTrackPage,
      hasCrossedStartLine: hasCrossedStartLine,
    );
    final topWidgets = <Widget>[
      // v1.4.2：顶栏改半透 + 主框架 extendBodyBehindAppBar，首位占位
      // 状态栏 + AppBar 高，天气条 / GPS 徽标静止时才不会藏进顶栏后
      //（街道 / 赛道、横 / 竖屏四种组合共用此一处）。
      // v1.5.1：横屏记录时顶栏隐藏，此处只留状态栏高。
      SizedBox(
        height: MediaQuery.of(context).orientation == Orientation.landscape
            ? MediaQuery.of(context).padding.top
            : appBarTopInset(context),
      ),
      // v1.2.17：赛道模式隐藏顶部天气条容器（整块不渲染）；街道模式
      // 保留原样。GpsSourceBadge 在其下原样原位保留。
      if (!isTrackPage)
        RippleTap(
        onTap: _openWeatherPage,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0F172A),
          child: Row(children: [
            const Icon(Icons.cloud, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(child: Text(weather?.summary ?? '天气', style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(rec.state == RecState.paused ? '已暂停' : '记录中', style: const TextStyle(color: Colors.orange, fontSize: 12)),
            // v0.1.8 常亮状态一眼可辨：开启=常亮中，开关关了=常亮已关闭，
            // 开关开但原生失败=常亮未开启（与实际返回值一致，不假装）。
            const SizedBox(width: 8),
            Icon(_keepScreenOnActual ? Icons.brightness_high : Icons.brightness_low,
                size: 14, color: _keepScreenOnActual ? Colors.yellowAccent : (_keepScreenOnFailed ? Colors.orange : Colors.white54)),
            Text(
              _keepScreenOnActual
                  ? '常亮中'
                  : (!appPrefs.keepScreenOn ? '常亮已关闭' : '常亮未开启'),
              style: TextStyle(
                  color: _keepScreenOnActual ? Colors.yellowAccent : Colors.white54, fontSize: 12),
            ),
          ]),
        ),
      ),
      // v1.2.16 A 路：GPS 来源徽标（只在记录中显示）。生效态实时判定：
      // _blediyActive 为真且未超时才算外接，回落瞬间即变灰，不在已回落
      // 时仍显示外接。设备名状态里无现成映射，传 null 由徽标省略，不编名。
      // 卫星数：外接态取 GGA 星数，手机态取手机 GNSS 可见星数，无数据为 null。
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: GpsSourceBadge(
          externalActive:
              _blediyActive && !_blediyFeed.shouldFallbackToPhoneGps(),
          fallingBack:
              _blediyActive && _blediyFeed.shouldFallbackToPhoneGps(),
          deviceName: () {
            final n = externalGpsStatus.value.deviceName.trim();
            return n.isEmpty ? null : n;
          }(),
          hz: _blediyFeed.hz,
          satelliteCount: (_blediyActive &&
                  !_blediyFeed.shouldFallbackToPhoneGps())
              ? _blediyFeed.satelliteCount
              : (SatelliteService.instance.visibleCount > 0
                  ? SatelliteService.instance.visibleCount
                  : null),
          accuracyM: rec.curHAcc >= 999 ? null : rec.curHAcc,
        ),
      ),
      // OBD + 缺口推算小药丸（照 GPS 药丸模式，别堆）：
      // - OBD 已连接：绿点 + 实时车速，点按进设备中心；
      // - 缺口推算中：琥珀色“正在推算位置”；丢星未推算：橙色“GPS 信号丢失”。
      // 定位正常时两颗都不出现。
      _buildObdAndGapPills(),
      // v1.0.4：记录页性能测试小入口已删，入口只在左拉菜单（红字加粗）。
      // 职业赛道面板顶部小字：只给赛道名、圈数、本节用时，安静待着。
      // Delta 不再放这里：旧的 currentDeltaMs 是“当前圈已用 - 最佳圈
      // 总时长”，开圈不久时恒为很大的负值，会误导；真正的实时 Delta
      // （分段级）放在下方 TrackSessionDisplay 主角区。
      // 计时器未建成时显示“等待定位”，不回落街道面板。
      if (isTrackPage)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF111111),
          child: Row(children: [
            const Icon(Icons.flag, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                liveLapTimer == null
                    ? '${selectedTrack!.nameCn} · 等待定位，计时即将开始'
                    : '${selectedTrack!.nameCn} · ${liveLapTimer!.currentLapNumber <= 0 ? '发车圈' : '第 ${liveLapTimer!.currentLapNumber} 圈'}'
                        ' · 本节用时 ${fmtDur(rec.elapsedMs)}'
                        '${liveLapTimer!.isPaused ? ' · 已自动暂停' : ''}'
                        // v1.2.17：维修区内追加“ · 维修区 · 停站 mm:ss”
                        // （计时器 inPit / pitStopMs），不在维修区不显示。
                        '${pitStopSuffix(inPit: liveLapTimer!.inPit, pitStopMs: liveLapTimer!.pitStopMs)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      // v1.2.0 赛道模式：地图区不再显示地图，只显示方案 A 的
      // TrackSessionDisplay（大数字当前圈 + 分段色块 + 上一圈 /
      // 最佳圈 / 预测圈小字，参照圈默认本节最佳圈）；街道模式仍用
      // Recording3dMap。分段 delta 与预测圈由 LapTimer 新 API
      // （currentSectorDeltasVsBest / predictedLapMsVsBest）算好
      // 传入：已完成分段传带正负号的 delta，未完成分段传 null
      // （显示灰色 '--'，是未完成状态不是缺口）；无参照圈分段
      // 数据时预测圈保持 null（占位），不编数。上一圈 / 最佳圈 /
      // 当前圈 / 暂停态均为 LapTimer 实测值。待核赛道传
      // sectorSourceNote“扇区待核”，估算赛道传“估算分段”。
      // 注意：本处不合成任何扇区点——LapTimer 的 sectorPoints
      // 由 _buildLapTimer 从赛道包取（包起终点与记录首点 < 500m
      // 时采用包 sectorPoints，否则为空；见 _buildLapTimer）；
      // 目录归一化轮廓点不是经纬度，绝不能换算成 GeoPoint 冒充
      // 扇区点。无包分段点的赛道计时器无扇区点，预测圈 / Delta /
      // 最优圈三者均为占位，分段格全为 '--'。
      // v1.3.2：记录页分页（计时页 / 地图页左右滑）：第 0 页为现有
      // 内容原样不动（赛道 SingleChildScrollView、街道 Recording3dMap），
      // 第 1 页为实时地图 RecordingMapPage（只看不操作）。
      // GpsSourceBadge、天气条、赛道旗标头行在 PageView 之外原样原位。
    ];
    // 横屏分栏：下面三段（PageView / 页指示点 / 底部面板）先建成
    // 局部变量，末尾按方向组装——竖屏保持原 Column 结构，横屏
    // 改左右分栏。内容、顺序、回调全不动，只改组装方式。
    final pageViewWidget = PageView(
          controller: _recMapPageController,
          onPageChanged: (i) {
            if (_recMapPageIndex != i) setState(() => _recMapPageIndex = i);
          },
          children: [
            if (isTrackPage)
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Builder(builder: (_) {
                  final timer = liveLapTimer;
                  final sectorData = sectorDataFor(selectedTrack!.id);
                  // v1.2.15：分段标签以计时器实际配置的扇区点为准——
                  // 包分段点是经纬度实点，2 点 = S1/S2/S3、1 点 = S1/S2；
                  // 分数制 sectorData 只作无实点时的回落。勒芒等“包有
                  // 实点、分数数据却为 pending”的赛道，旧写法会把整行
                  // 分段格盖成“扇区待核”，delta 在算但格子不显示。
                  // 无实点时仍按 sectorData 标签 + 来源标注显示 '--'。
                  final hasSectorPoints =
                      timer != null && timer.sectorPoints.isNotEmpty;
                  final labels = hasSectorPoints
                      ? (timer.sectorPoints.length >= 2
                          ? const ['S1', 'S2', 'S3']
                          : const ['S1', 'S2'])
                      : (sectorData?.sectorLabels ?? const []);
                  final completedDeltas =
                      timer?.currentSectorDeltasVsBest ?? const <int?>[];
                  final count = labels.length > completedDeltas.length
                      ? labels.length
                      : completedDeltas.length;
                  final sectorDeltasMs = List<int?>.generate(
                      count,
                      (i) => i < completedDeltas.length
                          ? completedDeltas[i]
                          : null);
                  final laps = timer?.laps ?? const <Lap>[];
                  final bestMs = timer?.bestLap?.durationMs;
                  // 职业面板接线（诚实口径，见 track_session_display.dart）：
                  // - 预测圈：LapTimer.predictedLapMsVsBest（已完成分段实测 +
                  //   参照圈剩余分段，参照圈 = 本节最佳圈）；无分段点 / 无
                  //   参照圈时 getter 本身返回 null，显示占位，不编数。
                  // - 实时 Delta 只认真实扇区点：liveDeltaMsFor 内部按
                  //   hasSectorPoints 门控，Delta = 预测圈 - 最佳圈（分段级）。
                  // - 最优圈：有真实扇区点时才传 sessionOptimalLapMs（内部
                  //   先按最佳圈段数过滤，避免退化半圈与真实分段混算）；
                  //   无扇区点时传 null，不拿前后半圈拼假最优圈。
                  final completedTimes =
                      timer?.currentCompletedSectorsMs ?? const <int>[];
                  final predictedMs = timer?.predictedLapMsVsBest;
                  final liveDelta = liveDeltaMsFor(
                    predictedLapMs: predictedMs,
                    bestLapMs: bestMs,
                    hasSectorPoints: hasSectorPoints,
                  );
                  final currentSectorIndex =
                      hasSectorPoints && completedTimes.length < labels.length
                          ? completedTimes.length
                          : null;
                  final optimalLapMs =
                      hasSectorPoints ? sessionOptimalLapMs(laps) : null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TrackSessionDisplay(
                        currentLapNumber: timer?.currentLapNumber ?? 0,
                        currentLapMs: timer?.currentLapMs,
                        // 大计时直播刷新：独立 ticker 插值，只重建大数字；
                        // 暂停须合并 LapTimer 自动暂停与记录手动暂停，
                        // 否则手动暂停期间显示仍会插值往前跑。
                        timerLive: true,
                        timerPaused: (timer?.isPaused ?? false) ||
                            rec.state == RecState.paused,
                        sectorDeltasMs: sectorDeltasMs,
                        showDelta: _showTrackDelta,
                        sectorTimesMs: completedTimes,
                        currentSectorIndex: currentSectorIndex,
                        liveDeltaMs: liveDelta,
                        sectorLabels: labels,
                        bestLapMs: bestMs,
                        predictedLapMs: predictedMs,
                        optimalLapMs: optimalLapMs,
                        // 有真实扇区点时不标“扇区待核”：分段点来自赛道包
                        // 经纬度实点（模拟器推导的待核状态见包 sectorNote
                        // 与赛道 ⓘ 页，本行只标分段点是否真实存在）。
                        sectorSourceNote: hasSectorPoints
                            ? '真实分段点'
                            : (sectorData?.sourceLabel ?? '扇区待核'),
                        isPaused: timer?.isPaused ?? false,
                        liveGSource: LiveGSource(
                          listenable: rec,
                          longG: () => rec.smoothLong,
                          latG: () => rec.smoothLat,
                          calibrated: () => rec.calibrated,
                          peakLong: () => rec.tripPeakLong,
                          peakLat: () => rec.tripPeakLat,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // v1.2.17：段速 + 到下一计时线距离行（赛道页内，
                      // TrackSessionDisplay 下方）。段速取计时器
                      // sectorSpeeds（与分段标签等长，未开始的段为 null，
                      // 只取 GPS 实测点）；无真实分段点时显示占位
                      // “段速 --”，不编数。下一计时线距离取计时器
                      // nextLineDistanceM，为 null 时该段不显示。
                      TrackSectorSpeedRow(
                        sectorSpeeds:
                            timer?.sectorSpeeds ?? const <SectorSpeed?>[],
                        sectorLabels: labels,
                        hasSectorPoints: hasSectorPoints,
                        nextLineDistanceM: timer?.nextLineDistanceM,
                      ),
                      const SizedBox(height: 12),
                      _trackLapListCard(laps, bestMs,
                          hasSectorPoints: hasSectorPoints),
                      const SizedBox(height: 12),
                      _trackSpeedCard(),
                    ],
                  );
                }),
              )
            else
              // v0.1.8：记录页地图改 3D 黑色风格自绘（Recording3dMap），
              // 不再用 RefinedMap 瓦片、瓦片源选择器在记录页不再展示；
              // 详情页的 RefinedMap 这一处不动。速度/G/时间/圈速/语音/
              // 事件标记都在本页其余部分原样保留。
              Recording3dMap(
                centerLat: cLat,
                centerLon: cLon,
                headingDeg: rec.curHeading,
                points: rec.points.map((p) => Recording3dPoint(lat: p.lat, lon: p.lon, speedKmh: p.speed * 3.6)).toList(),
                photoPoints: livePhotoPoints,
                is3d: appPrefs.recordingMap3d,
                onModeChanged: (v) => appPrefs.setRecordingMap3d(v),
                initialPitchDeg: appPrefs.recordingMapPitch,
                onPitchChanged: (v) => appPrefs.setRecordingMapPitch(v),
                zoom: mapZoom,
                onZoomChanged: (z) => setState(() => mapZoom = z),
                headingUp: mapHeadingUp,
                onCompassTap: () => setState(() => mapHeadingUp = false),
                accentColor: Theme.of(context).colorScheme.primary,
                vehicleColor: _vehicleColor(rec.mode),
                vehicleMarkerPainter: markerPainterFor(appPrefs.vehicleSelection, rec.mode, bodyColor: _vehicleColor(rec.mode)),
              ),
            // 第 1 页：实时地图（只看不操作）。状态行：赛道模式为当前圈
            // 用时 + 第 N 圈（无计时器时“等待定位”，未第一次过线时
            // “等待通过起终点线”），街道模式为用时 + 里程。
            // v1.3.5：赛道叠加层只在第一次过线后显示（showTrackOverlay），
            // 过线前只显示卫星底图 + 当前位置箭头 + 已录轨迹。
            RecordingMapPage(
              isTrack: isTrackPage,
              centerline: isTrackPage
                  ? (selectedPackage?.centerline ?? const <GeoPoint>[])
                  : const <GeoPoint>[],
              start: isTrackPage ? selectedPackage?.start : null,
              finish: isTrackPage ? selectedPackage?.finish : null,
              sectorPoints: liveLapTimer?.sectorPoints ?? const <GeoPoint>[],
              trail: rec.points.map((p) => GeoPoint(p.lat, p.lon)).toList(),
              curLat: rec.curLat,
              curLon: rec.curLon,
              curHeading: rec.curHeading,
              ghostLat: ghostPos?.lat,
              ghostLon: ghostPos?.lon,
              ghostHeading: ghostPos?.headingDeg,
              showTrackOverlay: showTrackOverlay,
              statusLine: isTrackPage
                  ? trackMapStatusLine(
                      hasTimer: liveLapTimer != null,
                      hasCrossedStartLine: hasCrossedStartLine,
                      lapLabel: (liveLapTimer?.currentLapNumber ?? 0) <= 0
                          ? '发车圈'
                          : '第 ${liveLapTimer!.currentLapNumber} 圈',
                      currentLapDuration:
                          fmtDur(liveLapTimer?.currentLapMs ?? rec.elapsedMs),
                    )
                  : '用时 ${fmtDur(rec.elapsedMs)} · 里程 ${(rec.distanceM / 1000).toStringAsFixed(2)} km',
            ),
          ],
        );
      // v1.3.2：页指示点（计时 / 地图），可点切换。
      final pageTabs = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _recMapPageTab(0, s.t('计时', 'Timing')),
            const SizedBox(width: 16),
            _recMapPageTab(1, s.t('地图', 'Map')),
          ],
        ),
      );
      // v1.0.2 记录页底部面板底色统一为卡片色 #1E1E1E（仅改色，不改结构/逻辑）。
      // v1.3.2：底部按钮只在计时页（第 0 页）显示，地图页不显示操作区。
      // v1.5.1：本面板只用于竖屏（横屏用 landscapeControls）；竖屏
      // 组装时直接作 Column 子级、不包 Flexible（见末尾注释）。
      final bottomPanelWidget = Container(
            color: CardStyle.cardColor,
            child: SingleChildScrollView(
              // v1.4.2：显式零 padding——不吃主框架 extendBodyBehindAppBar
              // 带来的 MediaQuery 顶垫，否则底部面板顶部会多出一段空隙。
              padding: EdgeInsets.zero,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: CardStyle.cardColor,
                child: Column(children: [
          // 赛道面板不用街道的速度/G 值区，只留标记/暂停/结束。
          if (!isTrackPage) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(rec.curSpeed * 3.6).toStringAsFixed(0)}', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: _speedColor(rec.curSpeed * 3.6))),
                const Text('km/h', style: TextStyle(color: Colors.white60)),
                Text(s.t('时速区间：<60 白 · 60–100 黄 · >100 红', '<60 white · 60–100 yellow · >100 red'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Text('${s.t('里程', 'Distance')} ${(rec.distanceM / 1000).toStringAsFixed(2)} km · ${fmtDur(rec.elapsedMs)}', style: const TextStyle(color: Colors.white70)),
                Text('${s.t('定位精度', 'Accuracy')} ${rec.curHAcc >= 999 ? '—' : '${rec.curHAcc.toStringAsFixed(0)} m'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (rec.mode == TripMode.moto) Text('倾角 ${rec.rollDeg.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontSize: 14)),
                if (rec.mode == TripMode.bike)
                  Text(
                    '功率 ${rec.powerW == null ? '—' : '${rec.powerW!.toStringAsFixed(0)}W${rec.powerEstimated ? '（估算）' : ''}'} · 踏频 ${rec.cadenceRpm == null ? '未接入' : '${rec.cadenceRpm!.toStringAsFixed(0)} rpm'} · 心率 ${rec.heartRate ?? '—'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ]),
            ),
            RippleTap(
              circular: true,
              onTap: () => Navigator.push(context, DtPageRoute(builder: (_) => GPage(rec: rec))),
              child: GCirlce(
                longG: rec.smoothLong,
                latG: rec.smoothLat,
                trail: trail,
                threshold: ModeThresholds.of(rec.mode).harshCorner,
                calibrated: rec.calibrated,
                size: 110,
              ),
            ),
            ]),
            // v1.5.3 压弯倾角实时读数（融合估计器）：与 G 值显示并排，
            // 街道面板内、G 圆下方；不改现有 G 值与姿态显示。
            LeanAngleReadout(
              leanDeg: rec.leanDeg,
              quality: rec.leanQuality,
              calibrated: rec.calibrated,
            ),
            const SizedBox(height: 10),
          ],
          // v1.2.0 标记事件：醒目全宽按钮，位于暂停/长按结束上方；
          // 标记时可写标题、选类型、可选照片与备注，无照片也可先标记，
          // 之后在详情时间线附照片。
          // v1.2.17：赛道模式下标记事件按钮与下面那行说明文字都不显示
          // （赛道页不做标记）；街道模式保留原样，仍调用 _addEventMarker。
          if (!isTrackPage) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.place),
                label: Text(
                    '${s.t('标记事件', 'Mark')}${livePhotoPoints.isEmpty ? '' : s.t('（已标记 ${livePhotoPoints.length} 条）', ' (${livePhotoPoints.length})')}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _addEventMarker,
              ),
            ),
            const SizedBox(height: 4),
            Text(s.t('记下坐标与时间。结束后在详情时间线查看。', 'Saves this point. See it on the trip timeline.'),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          // v1.2.17：赛道模式底部按钮改为紧凑暂停按钮（96×48）+
          // Expanded 长按结束（红色、48 高，仍只响应 onLongPress
          // 防误触）；结束计时保持手动，不加任何自动结束或自动
          // 结束弹窗。街道模式保持现有两个半宽按钮不动。
          Row(children: [
            if (isTrackPage)
              SizedBox(
                width: 96,
                height: 48,
                child: FilledButton(
                  onPressed: togglePause,
                  child: Text(rec.isRecording ? s.t('暂停', 'Pause') : s.t('恢复', 'Resume')),
                ),
              )
            else
              Expanded(
                child: FilledButton(
                  onPressed: togglePause,
                  child: Text(rec.isRecording ? s.t('暂停', 'Pause') : s.t('恢复', 'Resume')),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: HoldToEndButton(
                label: s.t('长按结束', 'Hold to end'),
                onComplete: _endTrip,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(rec.calibrationNote, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
              ),
            ),
          );
    // v1.5.4 横屏控制列（重做）：赛道模式横屏无任何手动按钮——
    // 暂停 / 结束按钮已删，停车自动暂停、起步自动恢复，全程无需
    // 手动；腾出的位置放计时核心数据（大速度、当前圈、圈时、分段、
    // Delta、G 值、倾角）。街道模式横屏保持原样（大速度 + 暂停 /
    // 长按结束两个 64 高大按钮）。只在计时页（第 0 页）显示，
    // 地图页不显示。
    final landscapeControls = Container(
      color: CardStyle.cardColor,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isTrackPage) ...[
              // 自动暂停状态条：计时停了为什么，一眼可见。
              if (rec.isAutoPaused || (liveLapTimer?.isPaused ?? false))
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.5)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.pause_circle_filled,
                        size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.t('已自动暂停 · 等待起步', 'Auto-paused · waiting to roll'),
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
              if (rec.isAutoPaused || (liveLapTimer?.isPaused ?? false))
                const SizedBox(height: 12),
              // 大速度 + 当前圈 / 圈时。
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${(rec.curSpeed * 3.6).toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: _speedColor(rec.curSpeed * 3.6))),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10, left: 4),
                    child: Text('km/h',
                        style: TextStyle(color: Colors.white60)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          liveLapTimer == null
                              ? '等待定位'
                              : '第 ${liveLapTimer!.currentLapNumber <= 0 ? '发车圈' : '${liveLapTimer!.currentLapNumber} 圈'}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        LiveLapTimeText(
                          anchorMs: liveLapTimer?.currentLapMs,
                          lapNumber: liveLapTimer?.currentLapNumber ?? 0,
                          paused: (liveLapTimer?.isPaused ?? false) ||
                              rec.state == RecState.paused,
                          live: true,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 分段格：已完成段给用时 + Delta，未完成段给 '--'。
              Builder(builder: (_) {
                final timer = liveLapTimer;
                final hasSectorPoints =
                    timer != null && timer.sectorPoints.isNotEmpty;
                final labels = hasSectorPoints
                    ? (timer.sectorPoints.length >= 2
                        ? const ['S1', 'S2', 'S3']
                        : const ['S1', 'S2'])
                    : const <String>[];
                final times =
                    timer?.currentCompletedSectorsMs ?? const <int>[];
                final deltas =
                    timer?.currentSectorDeltasVsBest ?? const <int?>[];
                if (labels.isEmpty) return const SizedBox.shrink();
                return Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(
                              right: i == labels.length - 1 ? 0 : 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: Column(children: [
                            Text(labels[i],
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(
                              i < times.length
                                  ? LapTimer.formatLapTime(times[i])
                                  : '--:--.---',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              i < deltas.length
                                  ? LapTimer.formatDelta(deltas[i])
                                  : '--',
                              style: TextStyle(
                                color: i < deltas.length && deltas[i] != null
                                    ? (deltas[i]! < 0
                                        ? Colors.greenAccent
                                        : deltas[i]! > 0
                                            ? Colors.redAccent
                                            : Colors.white70)
                                    : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 12),
              // Delta / 最佳圈 / 预测圈一行。
              Builder(builder: (_) {
                final timer = liveLapTimer;
                final hasSectorPoints =
                    timer != null && timer.sectorPoints.isNotEmpty;
                final liveDelta = liveDeltaMsFor(
                  predictedLapMs: timer?.predictedLapMsVsBest,
                  bestLapMs: timer?.bestLap?.durationMs,
                  hasSectorPoints: hasSectorPoints,
                );
                return Row(children: [
                  Expanded(
                    child: Text(
                      '实时 Delta ${LapTimer.formatDelta(liveDelta)}',
                      style: TextStyle(
                        color: liveDelta == null
                            ? Colors.white54
                            : (liveDelta < 0
                                ? Colors.greenAccent
                                : liveDelta > 0
                                    ? Colors.redAccent
                                    : Colors.white),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '最佳 ${LapTimer.formatLapTime(timer?.bestLap?.durationMs)}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                ]);
              }),
              const SizedBox(height: 12),
              // G 值行：纵向 / 横向实时值。
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Text(
                      '纵向 G ${rec.smoothLong >= 0 ? '+' : ''}${rec.smoothLong.toStringAsFixed(2)}g',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Text(
                      '横向 G ${rec.smoothLat >= 0 ? '+' : ''}${rec.smoothLat.toStringAsFixed(2)}g',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // 压弯倾角（融合估计器，与竖屏街道面板同一组件）。
              LeanAngleReadout(
                leanDeg: rec.leanDeg,
                quality: rec.leanQuality,
                calibrated: rec.calibrated,
              ),
              const SizedBox(height: 12),
              Text(
                  '本节用时 ${fmtDur(rec.elapsedMs)} · 里程 ${(rec.distanceM / 1000).toStringAsFixed(2)} km',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(rec.calibrationNote,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.left),
            ] else ...[
              Text('${(rec.curSpeed * 3.6).toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: _speedColor(rec.curSpeed * 3.6))),
              const Text('km/h', style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 4),
              Text(
                  '里程 ${(rec.distanceM / 1000).toStringAsFixed(2)} km · ${fmtDur(rec.elapsedMs)}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: togglePause,
                  child: Text(rec.isRecording ? s.t('暂停', 'Pause') : s.t('恢复', 'Resume'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              HoldToEndButton(
                label: s.t('长按结束', 'Hold to end'),
                height: 64,
                fontSize: 18,
                borderRadius: BorderRadius.circular(16),
                onComplete: _endTrip,
              ),
              const SizedBox(height: 12),
              Text(rec.calibrationNote,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
    // ---- 按方向组装（竖屏原样 / 横屏左右分栏）----
    // 横屏（800×360 这类）：左右分栏。左侧 = 地图/计时 PageView
    // + 页指示点；右侧 = 横屏控制列（定宽）；地图页（第 1 页）
    // 不显示操作区，地图占满宽。竖屏：保持原 Column 结构
    // （Expanded PageView + 指示点 + 底部面板，不包 Flexible）。
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      // 右栏宽取屏宽 42%，夹在 300~380：800 宽屏上 336，窄横屏
      // 上不低于 300，左侧地图/计时区至少留约 340。
      final panelW =
          (MediaQuery.of(context).size.width * 0.42).clamp(300.0, 380.0);
      return Column(children: [
        ...topWidgets,
        Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                Expanded(child: pageViewWidget),
                pageTabs,
              ]),
            ),
            if (_recMapPageIndex == 0)
              SizedBox(width: panelW, child: landscapeControls),
          ]),
        ),
      ]);
    }
    return Column(children: [
      ...topWidgets,
      Expanded(child: pageViewWidget),
      pageTabs,
      // v1.5.1 竖屏回归：底部面板不包 Flexible。1.5.0 横屏分栏时
      // 误把底部面板包进 Flexible（默认 flex 1），它与 Expanded
      // 的 PageView 平分剩余空间：PageView 只拿到一半高度、赛道
      // 面板从分段格处被拦腰截断，剩下一半空间在屏底空着——这就是
      // 用户截图里竖屏赛道计时页的问题根因。底部面板按内容高度
      // 自然排列，Expanded 的 PageView 拿走全部剩余高度。
      if (_recMapPageIndex == 0) bottomPanelWidget,
    ]);
  }

  /// 赛道面板：圈速列表卡（最新圈在上；最快圈红字标“最快”；
  /// 停留不计圈的圈标“不计圈”，不参与最快圈比较）。
  /// v1.2.17：每圈在总时间下方展开 S1/S2/S3 用时（取 Lap.sectorsMs；
  /// 只有计时器有真实分段点时才展开，无分段点只显示总时间，不把
  /// 退化两段当前真实分段）；圈标记新增 Lap.kind：inLap“进站圈”、
  /// outLap“出站圈”，与“不计圈”“最快”并存；“发车圈”仍由旗标
  /// 头行 currentLapNumber<=0 显示，不动。
  Widget _trackLapListCard(List<Lap> laps, int? bestMs,
      {required bool hasSectorPoints}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('圈速列表',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (laps.isEmpty)
          const Text('暂无完成圈', style: TextStyle(color: Colors.white54, fontSize: 13))
        else
          for (final lap in laps.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('第 ${lap.number} 圈',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    if (lapKindTag(lap.kind).isNotEmpty)
                      Text('${lapKindTag(lap.kind)} ',
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (!lap.counted)
                      const Text('不计圈 ',
                          style: TextStyle(color: Colors.white54, fontSize: 12))
                    else if (bestMs != null && lap.durationMs == bestMs)
                      const Text('最快 ',
                          style: TextStyle(
                              color: Color(0xFFE10600),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    Text(LapTimer.formatLapTime(lap.durationMs),
                        style: TextStyle(
                            color: (lap.counted && bestMs != null && lap.durationMs == bestMs)
                                ? const Color(0xFFE10600)
                                : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                  ]),
                  if (hasSectorPoints && lap.sectorsMs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(formatLapSectorTimes(lap),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
      ]),
    );
  }

  /// 赛道面板：速度卡。不用街道面板的 G 值圆与速度区间图例。
  /// v1.2.17：删掉“里程”和“用时”两行，只留速度与定位精度。
  /// 职业面板里它降级放在圈速列表下面：内边距与字号都缩小，
  /// 不抢计时区风头。
  Widget _trackSpeedCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(rec.curSpeed * 3.6).toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: _speedColor(rec.curSpeed * 3.6))),
            const Text('km/h', style: TextStyle(color: Colors.white60)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '定位精度 ${rec.curHAcc >= 999 ? '—' : '${rec.curHAcc.toStringAsFixed(0)} m'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  /// v1.2.0：单条删除确认（长按卡片触发）与批量删除确认共用
  /// 文案：删除行程文件 + 索引 + 收藏孤儿 id，视频文件保留。
  Future<void> _confirmDeleteTrips(List<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ids.length == 1 ? '删除这趟行程？' : '删除所选 ${ids.length} 趟行程？'),
        content: const Text('删除后行程文件、索引与收藏记录一并删除，视频文件保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await store.deleteTrips(ids);
    trips = await store.loadIndex();
    favorites = await store.loadFavorites();
    trackBestLapMs.removeWhere((k, _) => !trips.any((m) => m.id == k));
    _selectedTripIds.removeAll(ids);
    if (_selectedTripIds.isEmpty) _listSelecting = false;
    if (mounted) setState(() {});
  }

  /// v1.2.1 记录页重做（2b/2c/2d）：
  /// - 演示模块整个删掉：无演示卡、无生成入口；列表与统计口径
  ///   一律排除 demo（旧演示行程文件仍在索引里时也不再出现，
  ///   分析页与油耗页的 demo 过滤保持不变，不靠本页兜底）。
  /// - 油耗汇总卡从记录页拿掉：本页不再出现当月/按车辆分组油耗卡，
  ///   油耗汇总只留在油耗页 / 车辆档案相关页与我的页（_monthlyFuelSummary
  ///   仍供我的页共用，不动）。
  /// - 排版：深色底 #121212 + 法拉利红 #E10600 点缀，统一卡片、
  ///   字号层级与按钮样式；分区清晰：标题 + 分析入口、赛道专区入口、
  ///   列表；不再并排一堆小按钮。
  /// - 列表卡片统一为“模式或赛道名 + 日期 + 里程/时长 + 关键指标
  ///   （街道给评分，赛道给最佳圈，无圈速写暂无圈速）”。
  /// - 单条长按删除、多选批量删除保留（v1.2.0 已有，不丢）；
  ///   空态写“暂无行程”。底部导航本身（216×56 方案 A 悬浮药丸）
  ///   与主题色不动。赛道行程的详情 / 图鉴 / 分析统一走赛道页
  ///   （_openTrackHome）。
  Widget _buildList() {
    final s = S.of(context);
    const red = Color(0xFFE10600);
    // 演示行程排除在外：不再出现在列表里。
    final realTrips = trips.where((m) => !m.demo).toList();

    String cardTitle(TripMeta m) {
      if (m.isTrackMode) {
        return m.trackName.isEmpty ? s.t('赛道行程', 'Track trip') : m.trackName;
      }
      return switch (m.mode) {
        TripMode.car => s.t('汽车', 'Car'),
        TripMode.moto => s.t('摩托', 'Moto'),
        TripMode.bike => s.t('骑行', 'Ride'),
      };
    }
    String keyMetric(TripMeta m) {
      if (m.isTrackMode) {
        final best = trackBestLapMs[m.id];
        // 无该 id（尚未加载完）与 null（无计入圈）都显示暂无圈速，绝不编圈速。
        return best == null
            ? s.t('最佳圈：暂无圈速', 'Best lap: none')
            : s.t('最佳圈：${LapTimer.formatLapTime(best)}', 'Best ${LapTimer.formatLapTime(best)}');
      }
      return s.t('评分：${m.score.toStringAsFixed(0)}', 'Score ${m.score.toStringAsFixed(0)}');
    }

    String whenLabel(int ms) {
      if (s.zh) return fmtDate(ms);
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    Color modeCue(TripMeta m) {
      if (m.isTrackMode) return Theme.of(context).colorScheme.primary;
      return switch (m.mode) {
        TripMode.car => const Color(0xFF60A5FA),
        TripMode.moto => const Color(0xFFFBBF24),
        TripMode.bike => const Color(0xFF4ADE80),
      };
    }

    return Container(
      color: const Color(0xFF121212),
      child: Column(children: [
        // 分区一：标题 + 分析入口。
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12 + appBarTopInset(context), 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('行程记录', 'Trips'),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: const BorderSide(color: red)),
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: Text(s.t('行程分析', 'Analysis'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(
                    context,
                    DtPageRoute(
                        builder: (_) => TripAnalyticsPage(metas: realTrips, loadTrip: store.loadTrip))),
              ),
            ),
            const SizedBox(height: 4),
            Text(s.t('不含演示行程。赛道只统计圈速。', 'Demo trips excluded. Track trips use lap times.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        // 分区二：赛道专区唯一入口（醒目红底卡片）。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openTrackHome,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: red),
              ),
              child: Row(children: [
                const Icon(Icons.flag, color: red, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.t('赛道专区', 'Track'),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(s.t('我的赛道行程 · 赛道库 · 分析', 'My track trips, library, analysis'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ]),
            ),
          ),
        ),
        // 分区三：选择 / 批量删除条（仅选择模式下出现，不与分析入口并排）。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                _listSelecting
                    ? s.t('已选 ${_selectedTripIds.length} 趟', '${_selectedTripIds.length} selected')
                    : s.t('长按卡片可删除。视频文件保留。', 'Long-press a card to delete. Video files stay.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _listSelecting = !_listSelecting;
                if (!_listSelecting) _selectedTripIds.clear();
              }),
              child: Text(_listSelecting ? s.t('取消选择', 'Cancel') : s.t('选择', 'Select'),
                  style: const TextStyle(color: red, fontWeight: FontWeight.bold)),
            ),
            if (_listSelecting)
              TextButton(
                onPressed: _selectedTripIds.isEmpty ? null : () => _confirmDeleteTrips(_selectedTripIds.toList()),
                child: Text(s.t('删除所选', 'Delete'), style: const TextStyle(color: red, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
        // 分区四：行程列表。
        Expanded(
          child: realTrips.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: EmptyHud(
                      icon: Icons.route,
                      status: s.t('暂无行程', 'No trips yet'),
                      actionLabel: s.t('开始记录', 'Start recording'),
                      onAction: () => _goTab(0),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: realTrips.length,
                  itemBuilder: (ctx, i) {
                    final m = realTrips[i];
                    final selected = _selectedTripIds.contains(m.id);
                    final cue = modeCue(m);
                    final score = m.score.clamp(0, 100).toDouble();
                    return DriveTrackCard(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: EdgeInsets.zero,
                      onTap: () {
                        if (_listSelecting) {
                          setState(() {
                            if (selected) {
                              _selectedTripIds.remove(m.id);
                            } else {
                              _selectedTripIds.add(m.id);
                            }
                          });
                          return;
                        }
                        Navigator.push(context,
                            DtPageRoute(builder: (_) => TripDetailPage(store: store, tripId: m.id)));
                      },
                      child: GestureDetector(
                        onLongPress: _listSelecting ? null : () => _confirmDeleteTrips([m.id]),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Row(children: [
                            if (_listSelecting)
                              Checkbox(
                                value: selected,
                                activeColor: red,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selectedTripIds.add(m.id);
                                  } else {
                                    _selectedTripIds.remove(m.id);
                                  }
                                }),
                              )
                            else
                              Container(
                                width: 4,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: cue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            const SizedBox(width: 10),
                            Container(
                              width: 52,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: CardStyle.innerCardColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: CardStyle.borderColor),
                              ),
                              child: Icon(Icons.route, size: 18, color: cue),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cardTitle(m),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(whenLabel(m.startMs),
                                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(m.distanceM / 1000).toStringAsFixed(2)} km · ${fmtDur(m.endMs - m.startMs)}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                  if (m.gpsSource != GpsSource.unknown) ...[
                                    const SizedBox(height: 5),
                                    GpsSourceChip(source: m.gpsSource),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (m.isTrackMode)
                              SizedBox(
                                width: 64,
                                child: Text(keyMetric(m),
                                    textAlign: TextAlign.end,
                                    style: TextStyle(color: cue, fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            else
                              SizedBox(
                                width: 44,
                                height: 44,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: score / 100,
                                      strokeWidth: 3,
                                      backgroundColor: Colors.white12,
                                      color: cue,
                                    ),
                                    Text(m.score.toStringAsFixed(0),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class GPage extends StatefulWidget {
  final Recorder rec;
  const GPage({super.key, required this.rec});
  @override
  State<GPage> createState() => _GPageState();
}

class _GPageState extends State<GPage> {
  @override
  void initState() {
    super.initState();
    widget.rec.addListener(_tick);
  }

  void _tick() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    widget.rec.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rec = widget.rec;
    final now = DateTime.now().millisecondsSinceEpoch;
    final trail = rec.gHistory.where((g) => now - g.timeMs <= 5000).toList();
    final mag = math.sqrt(rec.smoothLong * rec.smoothLong + rec.smoothLat * rec.smoothLat);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(s.t('G 值实时', 'Live G'))),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.all(16)),
        child: Column(children: [
          GCirlce(
            longG: rec.smoothLong,
            latG: rec.smoothLat,
            trail: trail,
            threshold: ModeThresholds.of(rec.mode).harshCorner,
            calibrated: rec.calibrated,
            size: 260,
          ),
          const SizedBox(height: 12),
          Text(s.t('当前纵向 ${rec.smoothLong.toStringAsFixed(2)}g · 横向 ${rec.smoothLat.toStringAsFixed(2)}g · 合成 ${mag.toStringAsFixed(2)}g', 'Now long ${rec.smoothLong.toStringAsFixed(2)}g · lat ${rec.smoothLat.toStringAsFixed(2)}g · combined ${mag.toStringAsFixed(2)}g'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(s.t('峰值保持：纵向 ${rec.peakHoldLong.toStringAsFixed(2)}g · 横向 ${rec.peakHoldLat.toStringAsFixed(2)}g（保持 2 秒）', 'Peak hold: long ${rec.peakHoldLong.toStringAsFixed(2)}g · lat ${rec.peakHoldLat.toStringAsFixed(2)}g (2 seconds)'),
              style: const TextStyle(color: Colors.white70)),
          Text(s.t('本趟峰值：纵向 ${rec.tripPeakLong.toStringAsFixed(2)}g · 横向 ${rec.tripPeakLat.toStringAsFixed(2)}g', 'Trip peak: long ${rec.tripPeakLong.toStringAsFixed(2)}g · lat ${rec.tripPeakLat.toStringAsFixed(2)}g'),
              style: const TextStyle(color: Colors.white70)),
          Text(s.t('姿态：俯仰 ${rec.pitchDeg.toStringAsFixed(1)}° · 横滚 ${rec.rollDeg.toStringAsFixed(1)}°', 'Attitude: pitch ${rec.pitchDeg.toStringAsFixed(1)}° · roll ${rec.rollDeg.toStringAsFixed(1)}°'),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text(s.t('最近 60 秒波形（青=纵向，品红=横向，橙虚线=阈值）', 'Last 60 seconds (cyan long, magenta lat, orange threshold)'))),
          const SizedBox(height: 6),
          GWaveform(history: rec.gHistory, threshold: ModeThresholds.of(rec.mode).harshCorner),
          const SizedBox(height: 8),
          Text(rec.calibrated ? s.t('已标定', 'Calibrated') : s.t('未标定：G 值仅作参考，不进评分和事件统计', 'Not calibrated: G is a guide only, and is not scored'),
              style: TextStyle(color: rec.calibrated ? Colors.green : Colors.orange)),
        ]),
      ),
    );
  }
}

class TripDetailPage extends StatefulWidget {
  final Store store;
  final String tripId;
  const TripDetailPage({super.key, required this.store, required this.tripId});
  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  Trip? trip;
  List<TripMeta> metas = [];
  VehicleLibrary? vehicleLibrary;
  bool photoPointsTruncated = false;
  int scrub = -1;
  TripEvent? selectedEvent;
  bool sharing = false;
  bool sharingFile = false;
  // 高德第一批：纠偏轨迹显示开关（默认看纠偏）、分享静态图加载态与缓存。
  bool showCorrected = true;
  bool loadingShareMap = false;
  Uint8List? shareMapBytes;
  final GlobalKey _previewCardKey = GlobalKey();
  String selectedScoreKey = '';
  bool leanMountedConfirmed = false;
  bool previewTrim = true;
  // 云端一期：手动上传（用户在详情页点按钮才传）。
  bool cloudUploading = false;

  int _vehicleKind(TripMode m) {
    final sel = appPrefs.vehicleSelection;
    return switch (m) { TripMode.car => sel.car == CarMarkerStyle.sport ? 1 : 0, TripMode.moto => 2, TripMode.bike => 3 };
  }

  Color _vehicleColor(TripMode m) {
    final sel = appPrefs.vehicleSelection;
    return m == TripMode.moto ? sel.moto.accent : Theme.of(context).colorScheme.primary;
  }

  Widget _pillButton(String label, IconData icon, VoidCallback? onTap, {bool selected = false}) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: selected ? Colors.white : accent),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ]),
      ),
    );
  }

  Future<void> _sharePreviewImage() async {
    if (trip == null) return;
    setState(() => sharing = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final boundary = _previewCardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final dir = await widget.store.cacheDir();
      final path = '$dir/share_card.png';
      await File(path).writeAsBytes(data!.buffer.asUint8List());
      await Native.shareFiles([path], 'image/png', '驰迹 ${trip!.mode.label}行程 · 评分 ${trip!.score.toStringAsFixed(0)}');
    } catch (e) {
      if (mounted) showAppNotice(context, '分享失败：$e', AppNoticeKind.error);
    }
    if (mounted) setState(() => sharing = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
    // 云端一期：init 完成后再刷新一次，上传按钮状态才准
    // （队列在 init 里加载；未配置时 Future 立即完成）。
    CloudService.instance.initialized.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    trip = await widget.store.loadTrip(widget.tripId);
    metas = await widget.store.loadIndex();
    vehicleLibrary = await widget.store.loadVehicleLibrary();
    if (mounted) setState(() {});
  }

  /// 高德第一批：详情页刷新（后台 enrichment 完成后点“刷新”可见结果）。
  Future<void> _refreshTrip() async {
    final t = await widget.store.loadTrip(widget.tripId);
    if (mounted && t != null) setState(() => trip = t);
  }

  /// 云端一期：手动上传本行程（点按钮才传，不自动传）。
  /// 未配置时只提示、不崩；上传中按钮禁用；结果用通知报。
  Future<void> _uploadTripToCloud() async {
    final t = trip;
    if (t == null || cloudUploading) return;
    if (!CloudService.instance.isConfigured) {
      if (mounted) {
        showAppNotice(context, '云端未配置：构建时未注入 CLOUDBASE_ENV_ID',
            AppNoticeKind.warning);
      }
      return;
    }
    setState(() => cloudUploading = true);
    final r = await CloudService.instance.enqueueUpload(t);
    if (!mounted) return;
    setState(() => cloudUploading = false);
    showAppNotice(context, r.message,
        r.ok ? AppNoticeKind.success : AppNoticeKind.error);
  }

  String get _cloudUploadLabel {
    if (cloudUploading) return '上传中…';
    final s = trip == null
        ? null
        : CloudService.instance.queueStatusFor(trip!.id);
    return switch (s) {
      CloudUploadStatus.done => '已上传到云端',
      CloudUploadStatus.pending || CloudUploadStatus.uploading => '上传中…',
      CloudUploadStatus.failed => '上传失败 · 点此重试',
      null => '上传到云端',
    };
  }

  /// 高德第一批：手动纠偏/重纠（仅汽车/摩托街道行程，UI 侧已门控；
  /// pending 时不重复触发）。纠偏失败时仍可再点；地名缺失时顺带补调。
  Future<void> _retryTripCorrection() async {
    final t = trip;
    if (t == null || t.correctionStatus == 'pending') return;
    await widget.store.updateTripEnrichment(t.id,
        correctionStatus: 'pending');
    final reloaded = await widget.store.loadTrip(t.id);
    if (mounted && reloaded != null) setState(() => trip = reloaded);
    List<(double lat, double lon)>? corrected;
    try {
      corrected = await correctTrackPoints(t.points);
    } catch (_) {
      corrected = null;
    }
    String? startPlace, endPlace;
    if (t.startPlace.isEmpty && t.points.isNotEmpty) {
      try {
        startPlace = (await reverseGeocode(
                t.points.first.lat, t.points.first.lon))
            ?.shortName;
      } catch (_) {}
    }
    if (t.endPlace.isEmpty && t.points.isNotEmpty) {
      try {
        endPlace = (await reverseGeocode(
                t.points.last.lat, t.points.last.lon))
            ?.shortName;
      } catch (_) {}
    }
    final nt = await widget.store.updateTripEnrichment(t.id,
        correctedPoints: corrected,
        correctionStatus: corrected != null ? 'done' : 'failed',
        startPlace: startPlace,
        endPlace: endPlace);
    if (mounted && nt != null) setState(() => trip = nt);
  }

  /// 高德第一批：纠偏行 UI（仅汽车/摩托与骑行；赛道行程不进详情页，
  /// 此处仍守卫）。状态机：pending 进行中、done 切原始/纠偏、
  /// failed 可重纠、skipped/none 按原因给说明（骑行/境外/无 Key 不给按钮）。
  Widget _correctionRow(Trip t) {
    if (t.isTrackMode) return const SizedBox.shrink();
    final actions = <Widget>[];
    String label;
    if (t.mode == TripMode.bike) {
      label = '骑行行程不自动纠偏，避免贴到机动车道';
    } else if (amapWebKey.isEmpty) {
      label = '未配置高德 Key，轨迹纠偏不可用';
    } else if (t.correctionStatus == 'pending') {
      label = '高德轨迹纠偏进行中…';
      actions.add(_pillButton('刷新', Icons.refresh, _refreshTrip));
    } else if (t.correctionStatus == 'done' &&
        t.correctedPoints.isNotEmpty) {
      label = '地图轨迹为纠偏后显示（遥测数据仍为原始记录）';
      actions.add(_pillButton('原始', Icons.route,
          () => setState(() => showCorrected = false),
          selected: !showCorrected));
      actions.add(_pillButton('纠偏', Icons.route,
          () => setState(() => showCorrected = true),
          selected: showCorrected));
      actions.add(_pillButton('刷新', Icons.refresh, _refreshTrip));
    } else if (t.correctionStatus == 'done') {
      label = '纠偏结果为空，当前显示原始轨迹';
      actions.add(_pillButton('手动重纠', Icons.refresh, _retryTripCorrection));
    } else if (t.correctionStatus == 'failed') {
      label = '纠偏失败，当前显示原始轨迹';
      actions.add(_pillButton('手动重纠', Icons.refresh, _retryTripCorrection));
      actions.add(_pillButton('刷新', Icons.refresh, _refreshTrip));
    } else if (t.correctionStatus == 'skipped') {
      label = '境外行程不走高德纠偏';
    } else {
      label = '尚未纠偏';
      actions.add(_pillButton('手动纠偏', Icons.refresh, _retryTripCorrection));
    }
    return Row(children: [
      Expanded(
          child: Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12))),
      ...actions,
    ]);
  }

  /// 高德第一批：分享卡用静态地图图片（内存 → 缓存文件 → 网络）。
  /// 与卡面轨迹同一口径：按行程存储的隐私开关截取后的点列；
  /// 境外行程、无 Key、点数不足、生成失败一律返回 null，
  /// 调用方回落现有卡面轨迹，不堵住分享。
  Future<Uint8List?> _ensureShareMapImage(Trip t) async {
    if (shareMapBytes != null) return shareMapBytes;
    try {
      if (amapWebKey.isEmpty) return null;
      if (t.points.isEmpty || !tripInChina(t.points)) return null;
      final dir = await widget.store.cacheDir();
      final path = '$dir/share_map_${t.id}.png';
      final f = File(path);
      if (await f.exists()) {
        final cached = await f.readAsBytes();
        if (cached.isNotEmpty) {
          shareMapBytes = Uint8List.fromList(cached);
          return shareMapBytes;
        }
      }
      final pts = widget.store.trimmedPoints(t);
      if (pts.length < 2) return null;
      final bytes = await fetchStaticMapImage(
          pts.map((p) => (p.lat, p.lon)).toList());
      if (bytes == null) return null;
      try {
        await f.writeAsBytes(bytes);
      } catch (_) {}
      shareMapBytes = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// v0.1.7 行程相册：改动（附照片/改备注/删点）经相册页 onChanged
  /// 回传后落盘；失败时提示且不改界面上的 trip，避免假装已保存。
  /// v1.2.0：走 updateTripPhotoPointsChecked，超 50 条截断时
  /// 卡片明示“只保留了前 50 条”，不报成全部保存成功。
  Future<void> _savePhotoPoints(List<PhotoPoint> pts) async {
    final t = trip;
    if (t == null) return;
    final r = await widget.store.updateTripPhotoPointsChecked(t.id, pts);
    if (r.trip != null && mounted) {
      setState(() {
        trip = r.trip;
        photoPointsTruncated = r.truncated;
      });
    }
  }

  void _openAlbum({String? focusPointId}) {
    final t = trip;
    if (t == null) return;
    Navigator.push(
        context,
        DtPageRoute(
            builder: (_) => TripAlbumPage(
                  initialPhotoPoints: t.photoPoints,
                  trackPoints:
                      t.points.map((p) => (lat: p.lat, lon: p.lon)).toList(),
                  onChanged: _savePhotoPoints,
                  focusPointId: focusPointId,
                )));
  }

  /// 给最新一个未附照片的打点附照片（拍照或相册选取二选一，
  /// 见 photo_points.dart 的 pickOrTakePhoto）。
  Future<void> _attachToLatestUnphotographed() async {
    final t = trip;
    if (t == null) return;
    final idx = t.photoPoints.lastIndexWhere((p) => !p.hasPhoto);
    if (idx < 0) {
      if (mounted) showAppNotice(context, '全部照片点都已有照片', AppNoticeKind.info);
      return;
    }
    final path = await pickOrTakePhoto(context);
    if (path == null || !mounted) return;
    final pts = List<PhotoPoint>.of(t.photoPoints);
    pts[idx] = pts[idx].copyWith(photoPath: path);
    await _savePhotoPoints(pts);
  }

  double _fitZoom(List<TrackPoint> pts) {
    if (pts.isEmpty) return 14;
    var minLat = pts.first.lat, maxLat = pts.first.lat, minLon = pts.first.lon, maxLon = pts.first.lon;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final span = math.max(maxLon - minLon, (maxLat - minLat) * 1.5);
    if (span < 0.01) return 16;
    if (span < 0.03) return 14;
    if (span < 0.1) return 12;
    return 10;
  }


  Future<void> _shareFile(String kind) async {
    if (trip == null || sharingFile) return;
    setState(() => sharingFile = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
    final dir = await widget.store.cacheDir();
    final trimmed = trip!.trimPrivacy;
    // v1.2.18：赛道包只查一次，GPX 航点与 CSV 分段门控共用。
    // 注：TrackPackage 无 startFinish 字段，起终线取 pkg.start
    //（与计时接线 _buildLapTimer 同口径），缺失时回落 pkg.finish。
    GeoPoint? startFinish;
    var sectorPoints = const <GeoPoint>[];
    bool? hasSectorPoints;
    final trackId = trip!.trackId;
    if (trip!.isTrackMode && trackId != null && trackId.isNotEmpty) {
      final pkg = (await TrackLibraryService.instance.loadAll())
          .packageById(trackId);
      if (pkg != null) {
        hasSectorPoints = pkg.hasSectors;
        if (pkg.hasSectors || pkg.start != null || pkg.finish != null) {
          startFinish = pkg.start ?? pkg.finish;
          sectorPoints = pkg.sectorPoints;
        }
      }
    }
    if (kind == 'gpx') {
      final path = '$dir/trip_${trip!.id}.gpx';
      await File(path).writeAsString(widget.store.toGpx(trip!,
          trimmed: trimmed,
          startFinish: startFinish,
          sectorPoints: sectorPoints));
      await Native.shareFiles([path], 'application/gpx+xml', '驰迹 GPX（${trimmed ? '已截掉首尾' : '完整轨迹'}）');
    } else {
      final path = '$dir/trip_${trip!.id}.csv';
      await File(path).writeAsString(widget.store.toCsv(trip!,
          trimmed: false, hasSectorPoints: hasSectorPoints));
      await Native.shareFiles([path], 'text/csv', '驰迹 CSV（完整数据）');
    }
    } finally {
      if (mounted) setState(() => sharingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = trip;
    if (t == null) return Scaffold(extendBodyBehindAppBar: true, appBar: DtAppBar(title: Text(s.t('行程详情', 'Trip'))), body: const Center(child: CircularProgressIndicator()));
    final _fk = selectedScoreKey.isEmpty ? null : scoreKeyToEventKinds(selectedScoreKey);
    final _kinds = (_fk == null || _fk.isEmpty) ? null : _fk;
    final corners = t.events.where((e) => e.kind == 'corner' && (_kinds == null || _kinds.contains(e.kind))).toList()..sort((a, b) => b.peakLatG.abs().compareTo(a.peakLatG.abs()));
    final others = t.events.where((e) => e.kind != 'corner' && (_kinds == null || _kinds.contains(e.kind))).toList();
    final splits = paceSplitsKm(t.points);
    final shown = widget.store.trimmedPoints(t);
    // 高德第一批：纠偏完成且开关开时，地图画纠偏轨迹（回放滑块、
    // 各遥测图与车辆标记仍用原始点，遥测口径不动）。
    final useCorrected = t.correctionStatus == 'done' &&
        t.correctedPoints.isNotEmpty &&
        showCorrected;
    final mapPoints = useCorrected
        ? t.correctedPoints
            .map((p) => RefinedTrackPoint(lat: p.$1, lon: p.$2, speedKmh: 0))
            .toList()
        : t.points
            .map((p) => RefinedTrackPoint(
                lat: p.lat,
                lon: p.lon,
                speedKmh: p.speed * 3.6,
                estimated: p.estimated))
            .toList();
    final centerPt = scrub >= 0 && scrub < t.points.length ? t.points[scrub] : t.points[t.points.length ~/ 2];
    final trend = metas.where((m) => m.mode == t.mode).take(6).toList().reversed.toList();
    // v1.2.16：详情页 GPS 来源标签取索引 TripMeta（与列表同一口径；
    // 老行程 unknown 时不显示，不拿轨迹点重算、不回填）。
    TripMeta? detailMeta;
    for (final m in metas) {
      if (m.id == t.id) {
        detailMeta = m;
        break;
      }
    }
    final powers = t.points.where((p) => p.powerW != null).map((p) => p.powerW!).toList();
    final avgPower = powers.isEmpty ? 0.0 : powers.reduce((a, b) => a + b) / powers.length;
    final cads = t.points.where((p) => p.cadenceRpm != null).map((p) => p.cadenceRpm!).toList();
    final avgCad = cads.isEmpty ? 0.0 : cads.reduce((a, b) => a + b) / cads.length;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(leading: GlassButton.back(onPressed: () => Navigator.pop(context)), title: Text('${s.t(t.mode.label, switch (t.mode) { TripMode.car => 'Car', TripMode.moto => 'Moto', TripMode.bike => 'Ride' })} ${s.zh ? '行程' : 'trip'} · ${s.zh ? fmtDate(t.startMs) : _fmtDateEn(t.startMs)}')),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // v0.1.3 详情页地图同步精细化（跟随关闭、北向上、源切换回调为空时内部切换）。
          RefinedMap(
            centerLat: centerPt.lat,
            centerLon: centerPt.lon,
            headingDeg: centerPt.heading,
            accuracyMeters: centerPt.hAcc >= 999 ? 0 : centerPt.hAcc,
            zoom: _fitZoom(t.points),
            points: mapPoints,
            follow: false,
            headingUp: false,
            height: 320,
            accentColor: Theme.of(context).colorScheme.primary,
            vehicleMarkerKind: _vehicleKind(t.mode),
            vehicleMarkerColor: _vehicleColor(t.mode),
            vehicleMarkerPainter: markerPainterFor(appPrefs.vehicleSelection, t.mode, bodyColor: _vehicleColor(t.mode)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 高德逆地理编码：有地名显示地名，缺失端回落坐标。
                  Text(
                      '${t.startPlace.isNotEmpty ? t.startPlace : (t.points.isEmpty ? '—' : '${t.points.first.lat.toStringAsFixed(5)},${t.points.first.lon.toStringAsFixed(5)}')} → ${t.endPlace.isNotEmpty ? t.endPlace : (t.points.isEmpty ? '—' : '${t.points.last.lat.toStringAsFixed(5)},${t.points.last.lon.toStringAsFixed(5)}')}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  _correctionRow(t),
                  // v1.2.16：GPS 来源标签（详情页头部，与起终点地名、
                  // 纠偏行并列展示；unknown 不显示）。
                  if (detailMeta != null && detailMeta.gpsSource != GpsSource.unknown) ...[
                    const SizedBox(height: 6),
                    GpsSourceChip(source: detailMeta.gpsSource),
                  ],
                ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(s.t('拖动回放：', 'Scrub: ')),
              Expanded(
                child: Slider(
                  value: (scrub < 0 ? t.points.length - 1 : scrub).toDouble(),
                  min: 0,
                  max: (t.points.length - 1).toDouble(),
                  onChanged: (v) => setState(() => scrub = v.toInt()),
                ),
              ),
              Text(scrub < 0 ? s.t('终点', 'End') : (s.zh ? fmtDate(t.points[scrub].timeMs) : _fmtDateEn(t.points[scrub].timeMs))),
            ]),
          ),
          if (scrub >= 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '该点：${(t.points[scrub].speed * 3.6).toStringAsFixed(0)} km/h · 纵向 ${t.points[scrub].longG.toStringAsFixed(2)}g · 横向 ${t.points[scrub].latG.toStringAsFixed(2)}g · 精度 ${t.points[scrub].hAcc >= 999 ? '—' : '${t.points[scrub].hAcc.toStringAsFixed(0)} m'}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // v1.0.7 遥测重排：顶部关键数据大字 + 统一遥测区（深色底 +
              // 网格 + 红白配色，全部实测数据，非任何车队官方分析页）。
              // 回放滑块与各图联动：滑块、曲线点选、事件点选都写同一个
              // scrub，速度/G/海拔/加速/压弯图共用同一时间轴顺序。
              TelemetryKpiStrip(trip: t),
              const SizedBox(height: 16),
              Text(s.t('数据分析 · 遥测', 'Telemetry'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(s.t('仅行程实测数据，非官方分析。拖回放滑块或点曲线，各图同步；速度曲线顶部的三角是事件（急加速绿 / 急刹红 / 弯道黄）。', 'Measured data from this trip, not an official analysis. The scrubber and the charts stay in sync. Triangles on the speed line are events (green accel, red brake, yellow corner).'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 12),
              TripSpeedChartCard(points: t.points, events: t.events, onPointSelected: (i) => setState(() => scrub = i), selectedIndex: scrub >= 0 ? scrub : null),
              const SizedBox(height: 12),
              TripGChartCard(points: t.points, onPointSelected: (i) => setState(() => scrub = i), selectedIndex: scrub >= 0 ? scrub : null),
              const SizedBox(height: 12),
              TripAltitudeCard(points: t.points),
              if (t.mode != TripMode.bike) ...[
                const SizedBox(height: 12),
                AccelSection(points: t.points, onPointSelected: (i) => setState(() => scrub = i)),
              ],
              if (t.mode == TripMode.moto) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Checkbox(value: leanMountedConfirmed, onChanged: (v) => setState(() => leanMountedConfirmed = v ?? false)),
                  Expanded(child: Text(s.t('本次手机已固定在车上（勾选后才显示压弯曲线）', 'The phone was fixed to the bike (check to show the lean chart)'), style: const TextStyle(fontSize: 12))),
                ]),
                LeanChartSection(
                  trip: t,
                  isCalibratedAndMounted: leanMountedConfirmed && t.points.any((p) => p.calibrated),
                  onEventTap: (e) => setState(() { scrub = e.startIndex; selectedEvent = e; }),
                  onPointSelected: (i) => setState(() => scrub = i),
                ),
              ],
              const SizedBox(height: 16),
              // 遥测区之后：相册、油耗、道路类型等原有模块保留、顺序顺后。
              TripPhotoAlbumCard(
                trip: t,
                onOpenAlbum: _openAlbum,
                // v1.2.0：点缩略图进相册时传入 focusPointId 定位到该点
                // （修复旧 _openAlbum 不定位的缺口）。
                onPhotoTap: (p) => _openAlbum(focusPointId: p.resolvedId),
                onAttachToLatestUnphotographed:
                    _attachToLatestUnphotographed,
                photoPointsTruncated: photoPointsTruncated,
              ),
              if (t.mode != TripMode.bike) ...[
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final lib = vehicleLibrary;
                  VehicleProfile? vehicle;
                  if (lib != null && t.vehicleId != null) {
                    for (final v in lib.vehicles) {
                      if (v.id == t.vehicleId) vehicle = v;
                    }
                  }
                  return TripFuelCard(
                    trip: t,
                    consumptionLPer100Km: appPrefs.fuelConsumptionLPer100Km,
                    fuelPricePerLiter: appPrefs.fuelPricePerLiter,
                    vehicleConsumptionLPer100Km: vehicle?.consumptionLPer100Km,
                    measuredConsumptionLPer100Km:
                        (lib != null && t.vehicleId != null) ? lib.measuredFor(t.vehicleId!) : null,
                    vehicleName: vehicle?.name,
                  );
                }),
              ],
              const SizedBox(height: 12),
              TripRoadTypeCard(points: t.points),
              // v0.1.3 赛道行程：赛道名 + 圈速表（由存入的 lapsJson 重建，不重算街道评分）。
              // v0.1.7 统合接线：详情页赛道图与选择器共用同一 TrackInfo.outline
              // 数据源（TrackDetailCard），不再是旧示意轮廓；按 trackId 查目录，
              // 查不到时只显示赛道名行。计时分段可视化（TrackVizSection）的
              // hasSectorPoints 指真实圈速分段计时数据，与目录示意分段点是两
              // 回事，故不随目录分段点改动，仍按实测分段数据走。
              if (t.isTrackMode) ...[
                const SizedBox(height: 8),
                Text(s.t('赛道：${t.trackName} · 赛道模式（示意轮廓，非官方测绘）', 'Track: ${t.trackName} · track mode (a sketch, not an official survey)'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  TrackInfo? matched;
                  for (final tr in allTracks) {
                    if (tr.id == t.trackId) matched = tr;
                  }
                  if (matched == null) return const SizedBox.shrink();
                  return TrackDetailCard(track: matched);
                }),
                const SizedBox(height: 6),
                const SizedBox(height: 6),
                Builder(builder: (_) {
                  final laps = t.lapsJson.map((j) => Lap.fromJson(j)).toList();
                  final counted = laps.where((l) => l.counted).toList();
                  counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
                  LapStability? stab;
                  if (counted.length >= 2) {
                    final mean = counted.map((l) => l.durationMs.toDouble()).reduce((a, b) => a + b) / counted.length;
                    var sq = 0.0;
                    for (final l in counted) {
                      sq += (l.durationMs - mean) * (l.durationMs - mean);
                    }
                    stab = LapStability(
                        count: counted.length,
                        meanMs: mean,
                        stdDevMs: math.sqrt(sq / counted.length),
                        rangeMs: (counted.map((l) => l.durationMs).reduce(math.max) - counted.map((l) => l.durationMs).reduce(math.min)).toDouble());
                  }
                  return LapTable(
                    currentLapMs: null,
                    lastLap: laps.isEmpty ? null : laps.last,
                    bestLap: counted.isEmpty ? null : counted.first,
                    deltaMs: null,
                    laps: counted,
                    stability: stab,
                    dwellLapCount: laps.where((l) => l.dwellNotCounted).length,
                    hasSectorPoints: false,
                  );
                }),
              ],
              if (t.isTrackMode) ...[
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final laps = t.lapsJson.map((j) => Lap.fromJson(j)).toList();
                  final counted = laps.where((l) => l.counted).toList()..sort((a, b) => a.durationMs.compareTo(b.durationMs));
                  final best = counted.isEmpty ? null : counted.first;
                  final sectors = <SectorTime>[];
                  if (best != null) {
                    for (var i = 0; i < best.sectorsMs.length; i++) {
                      var sBest = best.sectorsMs[i];
                      for (final l in counted) {
                        if (i < l.sectorsMs.length && l.sectorsMs[i] < sBest) sBest = l.sectorsMs[i];
                      }
                      sectors.add(SectorTime(durationMs: best.sectorsMs[i], sessionBestMs: sBest, personalBestMs: sBest));
                    }
                  }
                  final half = t.points.length ~/ 2;
                  final firstAvg = t.points.isEmpty ? 0.0 : t.points.sublist(0, half == 0 ? t.points.length : half).map((p) => p.speed * 3.6).reduce((a, b) => a + b) / (half == 0 ? t.points.length : half);
                  final secondAvg = t.points.isEmpty || half == 0 ? 0.0 : t.points.sublist(half).map((p) => p.speed * 3.6).reduce((a, b) => a + b) / (t.points.length - half);
                  final bestSeg = math.max(firstAvg, secondAvg);
                  return TrackVizSection(
                    currentLapNumber: laps.length,
                    currentLapMs: null,
                    bestLap: best,
                    deltaMs: null,
                    sectors: sectors,
                    hasSectorPoints: false,
                    segmentSpeeds: [
                      SegmentSpeed(label: '前半圈', avgSpeedKmh: firstAvg, bestSpeedKmh: bestSeg),
                      SegmentSpeed(label: '后半圈', avgSpeedKmh: secondAvg, bestSpeedKmh: bestSeg),
                    ],
                  );
                }),
              ],
              if (t.mode == TripMode.moto) Text('最大压弯角 ${t.maxLean.toStringAsFixed(0)}°（仅固定+标定后可信）'),
              if (t.mode == TripMode.bike)
                Text('平均功率 ${avgPower.toStringAsFixed(0)}W${t.points.any((p) => p.powerEstimated) ? '（估算）' : ''} · 平均踏频 ${cads.isEmpty ? '未接入' : '${avgCad.toStringAsFixed(0)} rpm'}'),
              const SizedBox(height: 12),
              DrivingScoreCard(
                total: t.score,
                subScores: t.subScores,
                reasons: t.scoreReasons,
                isTrackMode: t.isTrackMode,
                selectedKey: selectedScoreKey.isEmpty ? null : selectedScoreKey,
                onFilterChanged: (k) => setState(() => selectedScoreKey = k),
              ),
              const SizedBox(height: 8),
              Text(s.t('历次同模式评分趋势（左旧右新）', 'Score trend for this mode (old on the left)')),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: trend.map((m) {
                  return Expanded(
                    child: Column(children: [
                      Text(m.score.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
                      Container(height: (m.score / 100 * 40).clamp(2, 40), color: Theme.of(context).colorScheme.primary, margin: const EdgeInsets.symmetric(horizontal: 2)),
                    ]),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(s.t('G 值复盘', 'G review'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              GScatter(points: t.points, threshold: ModeThresholds.of(t.mode).harshCorner, size: 220),
              Text(s.t('每个点是一秒轨迹点，橙圈是本趟最大合成 G；下方是纵向（青）/横向（品红）G 随时间变化', 'Each dot is one second. The orange ring is this trip’s peak combined G. Below, long G is cyan and lat G is magenta.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              GWaveform(
                history: t.points.map((p) => GSample(p.timeMs, p.longG, p.latG)).toList(),
                threshold: ModeThresholds.of(t.mode).harshCorner,
              ),
              const SizedBox(height: 12),
              if (corners.isNotEmpty) ...[
                Text(s.t('过弯榜（按横向 G 排序）', 'Corners (by lateral G)'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (final e in corners)
                  ListTile(
                    title: Text('入弯 ${(e.entrySpeed * 3.6).toStringAsFixed(0)} → 弯中 ${(e.minSpeed * 3.6).toStringAsFixed(0)} → 出弯 ${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h'),
                    subtitle: Text('横向 ${e.peakLatG.abs().toStringAsFixed(2)}g · ${(e.endMs - e.startMs) ~/ 1000} 秒'
                        '${t.mode == TripMode.moto ? ' · 左倾 ${e.maxLeanLeft.toStringAsFixed(0)}° 右倾 ${e.maxLeanRight.toStringAsFixed(0)}°' : ''}'),
                    onTap: () => setState(() {
                      scrub = e.startIndex;
                      selectedEvent = e;
                    }),
                  ),
              ],
              if (t.mode == TripMode.moto) ...[
                Text(s.t('压弯分布', 'Lean'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('超 30° 累计：${t.points.where((p) => p.roll.abs() > 30).length} 秒 · 最大左倾 ${t.events.fold(0.0, (a, e) => math.max(a, e.maxLeanLeft)).toStringAsFixed(0)}° · 最大右倾 ${t.events.fold(0.0, (a, e) => math.max(a, e.maxLeanRight)).toStringAsFixed(0)}°'),
              ],
              if (others.isNotEmpty) ...[
                Text(s.t('全部事件', 'All events'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (final e in others)
                  ListTile(
                    title: Text('${e.label}：纵向 ${e.peakLongG.toStringAsFixed(2)}g · 横向 ${e.peakLatG.toStringAsFixed(2)}g'),
                    subtitle: Text('速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)} → ${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h · ${(e.endMs - e.startMs) ~/ 1000} 秒'),
                    onTap: () => setState(() {
                      scrub = e.startIndex;
                      selectedEvent = e;
                    }),
                  ),
              ],
              if (t.mode == TripMode.bike && splits.isNotEmpty) ...[
                Text(s.t('每公里配速', 'Pace per km'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (var i = 0; i < splits.length; i++) Text('第 ${i + 1} 公里：${splits[i].toStringAsFixed(2)} min/km'),
              ],
              if (selectedEvent != null) ...[
                Text(s.t('选中事件的 G 波形小图', 'G trace for the selected event'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${selectedEvent!.label} · 纵向峰值 ${selectedEvent!.peakLongG.toStringAsFixed(2)}g · 横向峰值 ${selectedEvent!.peakLatG.toStringAsFixed(2)}g'),
                GWaveform(
                  history: t.points
                      .sublist(selectedEvent!.startIndex, selectedEvent!.endIndex + 1)
                      .map((p) => GSample(p.timeMs, p.longG, p.latG))
                      .toList(),
                  threshold: ModeThresholds.of(t.mode).harshCorner,
                ),
              ],
              const SizedBox(height: 16),
              Text(s.t('同步视频', 'Video'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (t.videoPaths.isEmpty)
                Text(s.t('暂无关联视频', 'No linked video'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              if (t.videoPaths.isNotEmpty) ...[
                Text('共 ${t.videoPaths.length} 段（每段最长 10 分钟自动分段），视频仅存本机。',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                for (final vp in t.videoPaths)
                  ListTile(
                    leading: const Icon(Icons.videocam),
                    title: Text(vp.split('/').last),
                    // v0.1.7 追加项 3：首选应用内视频回顾（画面叠加 HUD），
                    // 系统播放器与分享作为备用入口保留；HUD 未烧录进视频文件。
                    subtitle: Text(s.t('点回顾进应用内播放，画面叠加速度/G 值', 'Opens in-app playback with speed and G on the picture')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Semantics(label: '视频回顾（应用内叠加）', child: IconButton(icon: const Icon(Icons.ondemand_video), onPressed: () => Navigator.push(context, DtPageRoute(builder: (_) => VideoReviewPage(trip: t, initialSegment: t.videoPaths.indexOf(vp)))))),
                      Semantics(label: '系统播放器播放', child: IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => Native.playVideo(vp))),
                      Semantics(label: '分享视频', child: IconButton(icon: const Icon(Icons.share), onPressed: () => Native.shareFiles([vp], 'video/mp4', '驰迹行程视频'))),
                    ]),
                  ),
              ],
              Row(children: [
                _pillButton(
                  t.isPublic ? '公开到我的动态 ✓' : '公开到我的动态',
                  Icons.public,
                  () async {
                    final nt = await widget.store.updateTripSocial(t.id, isPublic: !t.isPublic);
                    if (nt != null && mounted) setState(() => trip = nt);
                    // 已上传的行程改公开标记后重新发布（搬桶 + 改云端行）；
                    // 没上传过的下次上传时按新标记走对应桶。
                    if (nt != null &&
                        CloudService.instance.queueStatusFor(t.id) ==
                            CloudUploadStatus.done) {
                      final r =
                          await CloudService.instance.republishTrip(nt);
                      if (mounted) {
                        showAppNotice(
                          context,
                          r.message,
                          r.ok
                              ? AppNoticeKind.success
                              : AppNoticeKind.error,
                        );
                      }
                    }
                  },
                  selected: t.isPublic,
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: '点赞（本机计数）',
                  child: IconButton(
                    icon: Icon(t.liked ? Icons.favorite : Icons.favorite_border, color: t.liked ? Colors.red : null),
                    onPressed: () async {
                      final nt = await widget.store.updateTripSocial(t.id, toggleLike: true);
                      if (nt != null && mounted) setState(() => trip = nt);
                    },
                  ),
                ),
                Text('${t.likes}'),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pillButton('分享卡预览', Icons.share, loadingShareMap
                    ? null
                    : () async {
                        // 高德第一批：先取分享静态图（失败则 null 回落
                        // 卡面原有轨迹），再进预览页，绝不堵住分享。
                        setState(() => loadingShareMap = true);
                        Uint8List? mapBytes;
                        try {
                          mapBytes = await _ensureShareMapImage(t);
                        } finally {
                          if (mounted) {
                            setState(() => loadingShareMap = false);
                          }
                        }
                        if (!mounted) return;
                        // v1.2.18：分享卡分段行门控——赛道包有无真实
                        // 分段点；查不到包/查包失败时为 null（卡面走
                        // 保守门控，只显示 3 段分段行）。
                        bool? hasSectors;
                        final tid = t.trackId;
                        if (t.isTrackMode &&
                            tid != null &&
                            tid.isNotEmpty) {
                          try {
                            hasSectors = (await TrackLibraryService.instance
                                    .loadAll())
                                .packageById(tid)
                                ?.hasSectors;
                          } catch (_) {
                            hasSectors = null;
                          }
                        }
                        Navigator.push(
                            context,
                            DtPageRoute(
                                builder: (_) => ShareCardPreviewPage(
                      trip: t,
                      videoPath: t.videoPaths.isEmpty ? null : t.videoPaths.first,
                      trimPrivacy: previewTrim,
                      hasSectorPoints: hasSectors,
                      onTrimPrivacyChanged: (v) => setState(() => previewTrim = v),
                      cardBoundaryKey: _previewCardKey,
                      mapImageBytes: mapBytes,
                      trajectoryWidget: SizedBox(
                        height: 160,
                        child: CustomPaint(
                          size: const Size(double.infinity, 160),
                          painter: TrajectoryPainter(
                            shown,
                            shown.isEmpty ? 0 : shown.map((p) => p.lat).reduce((a, b) => a + b) / shown.length,
                            shown.isEmpty ? 0 : shown.map((p) => p.lon).reduce((a, b) => a + b) / shown.length,
                            _fitZoom(shown),
                            0,
                            -1,
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      onShareImage: _sharePreviewImage,
                      onShareGpx: () => _shareFile('gpx'),
                      onShareCsv: () => _shareFile('csv'),
                      onShareVideo: t.videoPaths.isEmpty ? null : () => Native.shareFiles([t.videoPaths.first], 'video/mp4', '驰迹行程视频'),
                                    )));
                      }),
                _pillButton('分享 GPX', Icons.file_download, sharingFile ? null : () => _shareFile('gpx')),
                _pillButton('分享 CSV', Icons.file_download, sharingFile ? null : () => _shareFile('csv')),
                _pillButton(_cloudUploadLabel, Icons.cloud_upload,
                    cloudUploading ? null : _uploadTripToCloud),
                _pillButton(
                  t.videoPaths.isEmpty ? '同步视频 · 暂无' : '同步视频',
                  Icons.videocam,
                  t.videoPaths.isEmpty
                      ? () { if (mounted) showAppNotice(context, '暂无关联视频', AppNoticeKind.info); }
                      : () => Native.shareFiles([t.videoPaths.first], 'video/mp4', '驰迹行程视频'),
                ),
              ]),
              const SizedBox(height: 8),
              Text(s.t('分享走系统分享，不登录不上传。GPX 默认按隐私开关截掉首尾；CSV 为完整数据，请自行注意隐私。上传到云端是手动上传完整轨迹（不截首尾），只传你点的这一条。', 'Sharing uses the system sheet. It does not sign you in or upload. GPX trims the ends when the privacy switch is on. CSV is the full file. A cloud upload is manual, complete, and only the trip you tap.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
