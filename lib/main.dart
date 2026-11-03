import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'models.dart';
import 'logic.dart';
import 'native.dart';
import 'tappable.dart';
import 'permission_gate.dart';
import 'recording_3d_map.dart';
import 'recorder.dart';
import 'store.dart';
import 'widgets.dart';
// v0.1.3 新模块（统合）
import 'countdown_page.dart';
import 'big_action_buttons.dart';
import 'device_center.dart';
import 'blediy_gps.dart';
import 'track_catalog.dart';
import 'track_timing.dart';
import 'track_widgets.dart';
import 'my_page.dart';
import 'refined_map.dart';
import 'weather_strip.dart';
import 'weather_service.dart';
import 'weather_page.dart';
// v0.1.4 新模块（统合）
import 'glass_button.dart';
import 'mode_switch.dart';
import 'theme_settings_page.dart';
import 'vehicle_markers.dart';
import 'map_import_page.dart';
import 'map_import_service.dart' as mis;
import 'trip_detail_modules.dart';
import 'photo_points.dart';
import 'score_module.dart';
import 'lean_chart.dart';
import 'accel_module.dart';
import 'share_card_preview.dart';
import 'track_viz.dart';
import 'voice_service.dart';
import 'satellite_service.dart';
import 'track_settings_page.dart';
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
import 'track_encyclopedia.dart';
import 'performance_challenge.dart';

void main() => runApp(const DriveTrackApp());

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
  // v1.0.3：可切换启动图标（profile.json 'appIcon'，'red' 默认 / 'blue'）。
  String appIcon = 'red';
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

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// v0.1.5 安全守则分街道 / 赛道：
// - 街道模式（含骑行，骑行无赛道模式）：最前面放两条醒目声明
//   “不要在公开道路上追逐竞技驾驶”“不要超速驾驶”，与关于页
//   安全区最前面的两条置顶声明对应，用户开始前就能看到；
// - 赛道模式：最前面放“仅在正规封闭赛道使用”，街道的两条
//   不适用于封闭赛道，不放进赛道守则。
List<String> safetyItems(TripMode m, {bool isTrack = false}) {
  final base = switch (m) {
    TripMode.car => ['手机已固定在支架上', '不开车时操作手机', '已系好安全带', '出发前已检查车况'],
    TripMode.moto => ['头盔、手套已戴好', '手机支架已锁紧', '不开车时操作手机', '出发前已检查车况'],
    TripMode.bike => ['头盔已戴好', '已检查刹车与轮胎', '夜骑已准备灯光', '骑行中不操作手机'],
  };
  if (isTrack) return ['仅在正规封闭赛道使用', ...base];
  return ['不要在公开道路上追逐竞技驾驶', '不要超速驾驶', ...base];
}

Future<void> unawaitedSaveBle(String address) async {
  try {
    final dir = await Native.getFilesDir();
    await File('$dir/last_ble.txt').writeAsString(address);
  } catch (_) {}
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
  LapTimer? liveLapTimer;
  int _lapFedCount = 0;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rec.addListener(() => mounted ? setState(() {}) : null);
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
    SatelliteService.instance.start();
    if (appPrefs.directSatellite) SatelliteService.instance.setDirectMode(true);
    await store.init();
    await appPrefs.load();
    trips = await store.loadIndex();
    favorites = await store.loadFavorites();
    await _loadCachedWeather();
    if (mounted) setState(() {});
    // v0.1.9：进首页即触发天气（见 _triggerWeatherOnLaunch 注释的根因）。
    await _triggerWeatherOnLaunch();
    _locSub = Native.locationStream.listen((e) async {
      // v0.1.3 外接 GPS 超时回落：5 秒无新定位即切回手机 GPS。
      if (_blediyActive && _blediyFeed.shouldFallbackToPhoneGps()) {
        _blediyActive = false;
        rec.externalGpsActive = false;
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
      // v0.1.3 赛道实时计时：赛道模式下，首点定为起终点，逐点喂 LapTimer。
      if (trackMode && selectedTrack != null && rec.isRecording && rec.points.isNotEmpty) {
        liveLapTimer ??= await _buildLapTimer();
        final prevBest = liveLapTimer!.bestLap?.durationMs;
        final prevLapCount = liveLapTimer!.laps.length;
        while (_lapFedCount < rec.points.length) {
          final p = rec.points[_lapFedCount++];
          liveLapTimer!.addPoint(TimedPoint(lat: p.lat, lon: p.lon, speed: p.speed, timeMs: p.timeMs));
        }
        final nb = liveLapTimer!.bestLap;
        if (liveLapTimer!.laps.length > prevLapCount) {
          final done = liveLapTimer!.laps.last;
          if (done.counted) VoiceService.instance.announceLap(lapNumber: done.number, lapMs: done.durationMs, isBest: nb != null && done.durationMs == nb.durationMs);
        } else if (nb != null && nb.counted && prevBest != null && nb.durationMs < prevBest) {
          VoiceService.instance.announceLap(lapNumber: nb.number, lapMs: nb.durationMs, isBest: true);
        }
      }
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
      // v0.1.3 BleDIY 外接 GPS：通用通知按特征 UUID 分发，NUS TX(0003)
      // 的字节喂给 NMEA 解析器；有效定位注入 Recorder（provider='external'），
      // 超时/断线立即回落手机 GPS（Recorder.externalGpsActive=false）。
      if (e['type'] == 'bleNotification') {
        final uuid = (e['characteristicUuid'] as String? ?? '').toLowerCase();
        final bytes = (e['bytes'] as List?)?.map((v) => (v as num).toInt()).toList() ?? <int>[];
        if (uuid.contains('0003') && bytes.isNotEmpty) {
          _blediyFeed.feedBytes(bytes);
          final fix = _blediyFeed.latest;
          if (fix != null && !_blediyFeed.shouldFallbackToPhoneGps()) {
            _blediyActive = true;
            rec.externalGpsActive = true;
            rec.onExternalFix(fix.lat, fix.lon, fix.speedMps ?? rec.curSpeed,
                fix.bearingDeg ?? rec.curHeading, DateTime.now().millisecondsSinceEpoch,
                altM: fix.altitudeM);
          }
        }
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

  Future<LapTimer> _buildLapTimer() async {
    final ts = await TrackSettingsStore.load();
    final args = ts.lapTimerArgs;
    return LapTimer(
      startFinish: GeoPoint(rec.points.first.lat, rec.points.first.lon),
      crossingRadiusM: args.crossingRadiusM,
      dwellThresholdMs: args.dwellThresholdMs,
      dwellSpeedMs: args.dwellSpeedMs,
    );
  }

  /// 模式切换只改 rec.mode，不触碰记录流程；记录中不展示模式切换器。
  void _selectMode(TripMode m) {
    if (rec.mode == m) return;
    _modeController.animateToPage(m.index, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void _goTab(int i) => setState(() => tab = i);

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
      MaterialPageRoute(builder: (_) => const DisclaimerPage()),
    );
  }

  // v0.1.5：关于从弹窗改成独立路由页（AboutPage）。v1.0.3 起关于
  // 只在左拉菜单里（设置页入口已删），点进同一页。
  void _showAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AboutPage(
          // v1.0.3 正式版显示：版本号显示值由本任务定为 1.0.3，
          // pubspec.yaml 同步改 1.0.3+15；
          // versionCode 不再在关于页展示，此处不再传旧值 10。
          versionName: '1.0.7',
          packageName: 'com.chixi.drive_track',
          channelLabel: '正式版',
          displayFont: appPrefs.displayFont,
          appIconKey: appPrefs.appIcon,
          updateConfig: const UpdateConfig.githubReleases(),
          onOpenBackup: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DataExportPage(store: store)),
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
    _locSub?.cancel();
    _senSub?.cancel();
    _bleDevSub?.cancel();
    _bleDataSub?.cancel();
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
    var need = force || weather == null || now - weatherMs > 10 * 60 * 1000;
    if (weatherLat != null && weatherLon != null) {
      if (haversineM(weatherLat!, weatherLon!, lat, lon) > 10000) need = true;
    }
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
    // v0.1.9：本次启动内刚给上定位权限也要立即拉天气。
    if (permGranted) await _triggerWeatherOnLaunch();
  }

  Future<void> _showSafety() async {
    var goCalibrate = false;
    final mode = rec.mode;
    final isTrack = trackMode && mode != TripMode.bike;
    // v1.0.7：今日同一模式 + 同一档位已确认过，直接进倒计时，不再弹守则。
    if (!appPrefs.safetyAckedToday(mode, isTrack: isTrack)) {
      final items = safetyItems(mode, isTrack: isTrack);
      // 街道前两条、赛道首条为红字置顶声明，其余正常显示。
      final redCount = isTrack ? 1 : 2;
      var skipToday = false;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: Text('${mode.label}安全守则'),
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
                  const Text('开录后界面锁定为 HUD，只留暂停 / 结束；结束需长按，防误触。',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  if (!rec.calibrated)
                    const Text('未标定提示：G 值暂不进评分；开始后也可直线行驶标定，或点“先去标定”。',
                        style: TextStyle(color: Colors.orange, fontSize: 12)),
                  SwitchListTile(
                    value: skipToday,
                    title: const Text('今日内不再弹出', style: TextStyle(fontSize: 14)),
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
                  child: const Text('先去标定'),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('一键确认，开始记录'),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要定位权限才能记录轨迹')));
      return;
    }
    // v0.1.3：安全守则 + 权限通过后不立刻开录，先推全屏倒计时页；
    // 倒计时页自己 pop 后调 onFinish，取消则什么都不做、不开录。
    if (!mounted) return;
    final countdownMode = mode;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CountdownPage(
          vibrationEnabled: appPrefs.countdownVibration,
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
    // v0.1.8 熄屏根因是系统锁屏超时自动熄屏，不是定位权限问题：
    // 记录开始后按设置开关自动开常亮；暂停时仍在记录页，保持开启
    // 更安全（暂停 ≠ 结束，用户随时恢复，不应中途熄屏）。
    _keepScreenOnActual = false;
    _keepScreenOnFailed = false;
    if (appPrefs.keepScreenOn) {
      final ok = await _setKeepScreenOn(true);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('常亮未开启：请检查系统设置，记录仍在继续')));
      }
    }
    if (mounted) setState(() {});
  }

  /// v0.1.7 记录中一键打点：取最新轨迹点坐标，无轨迹点时用当前
  /// 定位快照；无定位时拒绝并提示，不存 (0,0) 假点。
  /// 无照片也可先打点，之后在详情相册附照片；一趟上限 50 个。
  void _addPhotoPoint() {
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无定位，等定位出来后再打点')));
      return;
    }
    if (livePhotoPoints.length >= kMaxPhotoPointsPerTrip) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('一趟最多 50 个照片点，已达上限')));
      return;
    }
    setState(() => livePhotoPoints.add(
        PhotoPoint(lat: lat!, lon: lon!, timeMs: timeMs)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已打点 ${livePhotoPoints.length} 个 · 结束后在详情相册附照片')));
  }

  Future<void> _endTrip() async {
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
    // v0.1.8：记录结束（无论行程是否够长保存）都关闭常亮。
    await _setKeepScreenOn(false);
    if (pts.length < 10) {
      livePhotoPoints = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(videoPaths.isEmpty ? '行程太短，未保存（少于 10 个轨迹点）' : '行程太短未保存，但视频文件仍在本机视频目录，未关联行程')));
      }
      return;
    }
    final isTrack = trackMode && selectedTrack != null && mode != TripMode.bike;
    final lapsJson = (isTrack && liveLapTimer != null)
        ? liveLapTimer!.laps.map((l) => l.toJson()).toList()
        : <Map<String, dynamic>>[];
    final trip = await store.saveTrip(mode, startMs, endMs, pts,
        trim: trimPrivacy, riderKg: riderKg, weatherSummary: weather?.summary ?? '', videoPaths: videoPaths,
        trackId: isTrack ? selectedTrack!.id : null, trackName: isTrack ? selectedTrack!.nameCn : '',
        isTrackMode: isTrack, lapsJson: lapsJson,
        photoPoints: livePhotoPoints,
        startFinishLat: isTrack && pts.isNotEmpty ? pts.first.lat : null,
        startFinishLon: isTrack && pts.isNotEmpty ? pts.first.lon : null);
    livePhotoPoints = [];
    liveLapTimer = null;
    _lapFedCount = 0;
    trips = await store.loadIndex();
    VoiceService.instance.announceSummary(
      distanceKm: trip.distanceM / 1000,
      durationMs: endMs - startMs,
      score: trip.score,
      bestLapMs: (() { final cs = trip.lapsJson.map((j) => Lap.fromJson(j)).where((l) => l.counted).map((l) => l.durationMs).toList()..sort(); return cs.isEmpty ? null : cs.first; })(),
    );
    if (mounted) {
      setState(() {});
      Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(store: store, tripId: trip.id)));
    }
  }

  Future<void> _makeDemo() async {
    final trip = await store.makeDemo(rec.mode);
    trips = await store.loadIndex();
    if (mounted) {
      setState(() {});
      Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(store: store, tripId: trip.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // v0.1.3 菜单手感：改前 350ms 线性 → 改后 200ms easeOutCubic（起手快），
    // 位移/缩放/圆角由同一动画值同步驱动；AnimatedBuilder 的 child 参数
    // 缓存主界面，动画帧不再重建地图/轨迹/G 图（只做变换），避免重活拖帧。
    // 只改菜单这一处，页面切换、倒计时等节奏不动。
    const menuW = 280.0;
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

  Widget _buildMainScaffold() {
    final recording = rec.isRecording || rec.state == RecState.paused;
    // v1.0.5：删掉 navSafe 底部安全区公式。内容不再为药丸留空，
    // 直接延伸到屏幕底边、从药丸下方划过；药丸周边不再是空底色条，
    // 而是页面内容本身透过毛玻璃可见。用户明确不要为“最后一条完整
    // 露出”再把底部 padding 加回去。
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        // v1.0.2 顶部按钮去边框：无圆形外框/圆形背景块的纯图标按钮，
        // 图标保留、点击区 44×44（SizedBox 定死，不用 GlassButton 的圆底）。
        leading: SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            icon: const Icon(Icons.menu, size: 22),
            tooltip: '菜单',
            padding: EdgeInsets.zero,
            onPressed: _toggleMenu,
          ),
        ),
        centerTitle: true,
        title: Text('DriveTrack', style: TextStyle(fontFamily: appPrefs.displayFont, fontWeight: FontWeight.w700)),
        actions: [
          // v1.0.2 同上：右设置钮去边框，点击区 44×44。
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              icon: const Icon(Icons.settings, size: 22),
              tooltip: '设置',
              padding: EdgeInsets.zero,
              onPressed: _openSettings,
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
                selectedIndex: tab,
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
    // v1.1.0 菜单底部描述溢出根因与修法：
    // 根因：面板在 Stack 里没有宽度约束，ListView 把面板撑到全屏宽，
    // 副标题按全屏宽排版成单行；但主界面只右移 280px，面板实际只露
    // 左边 280px 一条，底部较长的副标题（如性能测试、设备管理）在主
    // 界面边缘被硬裁，看起来就是“底部描述超出显示范围”。不是底部
    // inset 或药丸遮挡：SafeArea 已处理系统 inset，药丸随主界面右移、
    // 并不压在菜单上；也不是 ListTile 本身不换行——它在 280px 内会换行，
    // 只是之前从没拿到过 280px 的约束。
    // 修法：面板定宽 280（与主界面右移量 menuW 一致），副标题在 280px
    // 内自动换行，列表本身已是 ListView（可滚动），小屏与大字体下
    // 最后一项也可滚出来，不再被裁切。
    const menuW = 280.0;
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
          // 移入菜单（红字加粗）：赛道图鉴 / 性能测试 / 连接的设备管理 /
          // 数据导出/备份 / 免责声明 / 关于六项。首页与记录页入口已删，
          // 性能测试只剩这一处入口，仍进同一 performance_challenge.dart。
          // 关闭动画仍为 200ms easeOutCubic 主界面右移（build 里
          // 的 _menuAnim，不动）。
          Expanded(
            child: ListView(children: [
              ListTile(leading: const Icon(Icons.flag), title: const Text('赛道图鉴'), subtitle: const Text('国内外赛道资料、赛道图与赛事'), onTap: () => _menuAction(_openTrackEncyclopedia)),
              ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.red),
                  title: const Text('性能测试', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('0-100 加速 / 100-0 刹停 · 仅封闭场地测试'),
                  onTap: () => _menuAction(_openPerformanceChallenge)),
              ListTile(leading: const Icon(Icons.devices), title: const Text('连接的设备管理'), subtitle: const Text('设备中心：相机、传感器、外接 GPS'), onTap: () => _menuAction(_openDeviceCenter)),
              ListTile(leading: const Icon(Icons.file_download), title: const Text('数据导出/备份'), subtitle: const Text('按行程分享 GPX / CSV'), onTap: () => _menuAction(_openDataExport)),
              ListTile(leading: const Icon(Icons.warning_amber_rounded), title: const Text('免责声明'), subtitle: const Text('独立页面'), onTap: () => _menuAction(_openSafetySection)),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('关于'), subtitle: const Text('驰迹 DriveTrack · 正式版'), onTap: () => _menuAction(_showAbout)),
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
      MaterialPageRoute(
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
        if (!trackMode) selectedTrack = null;
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: WeatherStrip(segments: _weatherSegments, onTap: _openWeatherPage),
      ),
      // v0.1.9：拉取失败才出现的重试入口（加载中与已有天气时不出现）。
      // v1.0.6：跟天气条一起移到模式行上方，逻辑不动。
      if (weatherFailed && weather == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试获取天气'),
              onPressed: _retryWeather,
            ),
          ),
        ),
      _buildModeSwitcher(),
      Expanded(
        child: PageView(
          controller: _modeController,
          onPageChanged: (i) => rec.setMode(TripMode.values[i]),
          children: [for (final _ in TripMode.values) _buildIdleHome()],
        ),
      ),
      _buildSurfaceSwitch(),
      // v1.0.6：只修首页大方块贴底回归。首页是固定 Column（非滚动页），
      // v1.0.5 删掉主框架 navSafe 后大方块直接贴底边、与悬浮药丸重叠。
      // 只给大方块外层 Padding 加底部留白，不把主框架 Positioned.fill
      // 的底部 padding 加回去，不动滚动页（我的页/记录页仍从药丸下方
      // 划过、透过毛玻璃可见）。
      // 底部留白 = 药丸高 56 + 药丸底部 12 + 系统底部 inset + 间隙 12
      //          = 80 + MediaQuery.of(context).padding.bottom（实时算，
      //            不写死固定数）；大方块本身 128 高、圆角、内容、逻辑不动。
      Padding(
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
      ),
      // v1.0.4：首页性能测试入口卡已删，入口只在左拉菜单（红字加粗）。
    ]);
  }

  void _showCalibrationSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rec.calibrationNote, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('标定方法：把手机固定在支架上，点“开始标定”后直线行驶至 18 km/h 以上，App 自动锁定车头方向。未标定时 G 圆灰色，不进评分和事件统计。'),
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

  // v0.1.7 当月油耗汇总（记录页与我的页共用同一函数、同一口径）：
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

  /// 记录页顶部的当月汇总卡（演示卡之后、行程列表之前）。
  Widget _monthlyFuelCard() {
    final s = _monthlyFuelSummary();
    final fuelText = s.totalLiters == null ? '未填写' : '${s.totalLiters!.toStringAsFixed(2)} L';
    final costText = s.totalCost == null ? '未填写' : '${s.totalCost!.toStringAsFixed(2)} 元';
    return DriveTrackCard(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('本月汇总 · ${s.year}年${s.month}月（${s.tripCount} 次行程）',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('总里程\n${s.totalDistanceKm.toStringAsFixed(1)} km')),
            Expanded(child: Text('总油耗\n$fuelText')),
            Expanded(child: Text('总花费\n$costText')),
          ]),
          const SizedBox(height: 6),
          const Text('口径：总里程含汽车/摩托/骑行；油耗与花费仅汽车/摩托，按填写油耗估算，非加油实测；演示行程不计入。未填油耗/油价时油耗与花费显示“未填写”。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
    );
  }

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

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: appPrefs.username);
    final bioCtrl = TextEditingController(text: appPrefs.bio);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑个人资料'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '用户名')),
          TextField(controller: bioCtrl, decoration: const InputDecoration(labelText: '简介')),
          const SizedBox(height: 8),
          Text('ID：${appPrefs.userId}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      appPrefs.username = nameCtrl.text.trim().isEmpty ? appPrefs.username : nameCtrl.text.trim();
      appPrefs.bio = bioCtrl.text.trim();
      await appPrefs.save();
      if (mounted) setState(() {});
    }
  }

  Future<void> _shareInvite() async {
    try {
      await Native.shareFiles([], 'text/plain', '来驰迹 DriveTrack 看看我的行程：${appPrefs.username}（${appPrefs.userId}）。行程数据仅存本机，分享走系统分享。');
    } catch (_) {}
  }

  // v0.1.3：我的页换新版 MyPage（卡片化、细圆角进度条、药丸按钮），
  // 数据全部来自真实行程；关注/粉丝本机为 0 时新页显示“暂无”，不造假。
  Widget _buildMyPage() {
    final real = _realTrips;
    final totalDist = real.fold(0.0, (a, m) => a + m.distanceM);
    final totalDur = real.fold(0, (a, m) => a + (m.endMs - m.startMs));
    final avgScore = real.isEmpty ? 0.0 : real.fold(0.0, (a, m) => a + m.score) / real.length;
    final totalLikes = real.where((m) => m.isPublic).fold(0, (a, m) => a + m.likes);
    MyTripItem item(TripMeta m) => MyTripItem(
          id: m.id,
          title: '${m.mode.label} · ${(m.distanceM / 1000).toStringAsFixed(2)} km · 评分 ${m.score.toStringAsFixed(0)}${m.demo ? ' · 演示' : ''}',
          subtitle: fmtDate(m.startMs),
          isFavorite: favorites.contains(m.id),
          isPublic: m.isPublic,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(store: store, tripId: m.id))),
          onToggleFavorite: () async {
            favorites = await store.toggleFavorite(m.id);
            if (mounted) setState(() {});
          },
          onTogglePublic: () async {
            await store.updateTripSocial(m.id, isPublic: !m.isPublic);
            trips = await store.loadIndex();
            if (mounted) setState(() {});
          },
        );
    return MyPage(
      avatarPath: appPrefs.avatarPath,
      username: appPrefs.username,
      userId: appPrefs.userId,
      bio: appPrefs.bio,
      email: appPrefs.email,
      onEditProfile: _editProfile,
      onProfileSaved: (r) async {
        appPrefs.username = r.username;
        appPrefs.bio = r.bio;
        appPrefs.email = r.email;
        if (r.avatarPath != null) appPrefs.avatarPath = r.avatarPath;
        await appPrefs.save();
        if (mounted) setState(() {});
      },
      onPickAvatar: () async => await Native.pickFile('image'),
      onShareInvite: _shareInvite,
      stats: [
        MyStat(label: '行程', value: '${real.length}'),
        // v0.1.9：千分位 + 自适应字号（my_page.dart 内 FittedBox 不换行），
        // 如 123456.7 km → “123,456.7 km”，不截断、不折行。
        MyStat(label: '总里程', value: formatDistanceKm(totalDist / 1000)),
        MyStat(label: '总时长', value: fmtDur(totalDur)),
        MyStat(label: '平均评分', value: avgScore.toStringAsFixed(0)),
      ],
      // v0.1.7 当月汇总：与记录页同一函数、同一口径；未填写时
      // 油耗/花费显示“未填写”，不是 0。
      monthlyStats: (() {
        final s = _monthlyFuelSummary();
        return [
          MyStat(label: '本月里程', value: '${s.totalDistanceKm.toStringAsFixed(1)} km'),
          MyStat(label: '本月油耗', value: s.totalLiters == null ? '未填写' : '${s.totalLiters!.toStringAsFixed(2)} L'),
          MyStat(label: '本月花费', value: s.totalCost == null ? '未填写' : '${s.totalCost!.toStringAsFixed(2)} 元'),
        ];
      })(),
      monthlyNote: '口径：总里程含汽车/摩托/骑行；油耗与花费仅汽车/摩托，按填写油耗估算，非加油实测；演示行程不计入。',
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
      MaterialPageRoute(
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
          onOpenFuel: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FuelSettingsPage(
                initialConsumption: appPrefs.fuelConsumptionLPer100Km,
                initialPrice: appPrefs.fuelPricePerLiter,
                onSaved: (c, p) => appPrefs.setFuelSettings(c, p),
              ))),
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
  void _openPermissionSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
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
      MaterialPageRoute(
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

  // v1.0.2：抽屉“赛道图鉴”——推图鉴页；目录条目选为本次赛道时
  // 复用原有选赛道流程（trackMode=true + selectedTrack）。
  void _openTrackEncyclopedia() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackEncyclopediaPage(
          onSelectCatalogTrack: (t) {
            setState(() {
              trackMode = true;
              selectedTrack = t;
            });
          },
        ),
      ),
    );
  }

  // v1.0.2：性能测试挑战主入口（首页）与记录页小入口共用同一页。
  void _openPerformanceChallenge() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceChallengePage(
          onBack: () => Navigator.of(context).pop(),
          recorder: rec,
        ),
      ),
    );
  }

  void _openVoiceSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceSettingsPage()));
  }

  void _openTrackSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TrackSettingsPage()));
  }

  void _openLocationSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SatelliteSettingsPage()));
  }

  // v0.1.9 传感器校准页：车头标定启动复用旧标定底部表同一流程
  // （权限复查 + beginCalibration + startLocation + startSensors）。
  void _openSensorCalibration() {
    Navigator.push(
      context,
      MaterialPageRoute(
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
      MaterialPageRoute(
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
      MaterialPageRoute(builder: (_) => DataExportPage(store: store)),
    );
  }

  /// 赛道目录（v0.1.5 菜单“赛道目录”与首页赛道选择器共用）：
  /// 底部弹出赛道列表，选中即把该赛道定为本次赛道（trackMode=true）。
  /// 骑行模式下选了赛道也不会进赛道计时（_endTrip 的 isTrack 判定
  /// 排除骑行），切回汽车/摩托后该选择仍有效。
  void _openTrackCatalogSheet() {
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
            child: TrackSelector(
              tracks: allTracks,
              selectedId: selectedTrack?.id,
              onSelected: (t) {
                setState(() {
                  trackMode = true;
                  selectedTrack = t;
                });
                Navigator.pop(ctx);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openDeviceCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceCenterPage()),
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
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已向功率计发送归零请求（设备支持时生效）')));
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
            label: '同步视频记录',
            value: videoEnabled,
            onChanged: (v) => setState(() => videoEnabled = v),
          ),
        ),
      // v1.0.0：两颗药丸之间明确间距 10（框线/阴影只在各自药丸
      // 容器内，不再视觉挤在一起）；骑行模式无视频药丸时此间距
      // 不出现，卫星药丸直接接在实时行下方。
      if (rec.mode != TripMode.bike) const SizedBox(height: 10),
      if (videoEnabled && rec.mode != TripMode.bike)
        const Center(child: Text('同步视频：已开启（开始后以后置摄像头录像）', style: TextStyle(color: Colors.white54, fontSize: 12))),
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
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('直连卫星切换失败：${r['error'] ?? '请先授予定位权限'}')));
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

  Widget _buildRecording() {
    final cLat = rec.curLat != 0 ? rec.curLat : (rec.points.isNotEmpty ? rec.points.last.lat : 31.2304);
    final cLon = rec.curLon != 0 ? rec.curLon : (rec.points.isNotEmpty ? rec.points.last.lon : 121.4737);
    final now = DateTime.now().millisecondsSinceEpoch;
    final trail = rec.gHistory.where((g) => now - g.timeMs <= 5000).toList();
    return Column(children: [
      RippleTap(
        onTap: _openWeatherPage,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF0F172A),
          child: Row(children: [
            const Icon(Icons.cloud, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(child: Text(weather?.summary ?? '天气', style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
            if (_blediyActive)
              Text('外接 GPS · ${_blediyFeed.hz.toStringAsFixed(0)} Hz', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
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
      // v1.0.4：记录页性能测试小入口已删，入口只在左拉菜单（红字加粗）。
      // v0.1.3 赛道实时圈速条（仅赛道模式）：当前圈/上一圈/最快圈/Delta。
      if (trackMode && selectedTrack != null && liveLapTimer != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF111111),
          child: Row(children: [
            const Icon(Icons.flag, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${selectedTrack!.nameCn} · 第 ${liveLapTimer!.currentLapNumber} 圈'
                '${liveLapTimer!.currentLapMs == null ? '' : ' · 当前 ${LapTimer.formatLapTime(liveLapTimer!.currentLapMs!)}'}'
                '${liveLapTimer!.bestLap == null ? '' : ' · 最快 ${LapTimer.formatLapTime(liveLapTimer!.bestLap!.durationMs)}'}'
                '${liveLapTimer!.currentDeltaMs == null ? '' : ' · Delta ${LapTimer.formatDelta(liveLapTimer!.currentDeltaMs!)}'}'
                '${liveLapTimer!.isPaused ? ' · 已自动暂停' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      // v0.1.8：记录页地图改 3D 黑色风格自绘（Recording3dMap），
      // 不再用 RefinedMap 瓦片、瓦片源选择器在记录页不再展示；
      // 详情页的 RefinedMap 这一处不动。速度/G/时间/圈速/语音/
      // 拍照打点/事件标记都在本页其余部分原样保留。
      Expanded(
        child: Recording3dMap(
          centerLat: cLat,
          centerLon: cLon,
          headingDeg: rec.curHeading,
          points: rec.points.map((p) => Recording3dPoint(lat: p.lat, lon: p.lon, speedKmh: p.speed * 3.6)).toList(),
          photoPoints: livePhotoPoints,
          is3d: appPrefs.recordingMap3d,
          onModeChanged: (v) => appPrefs.setRecordingMap3d(v),
          zoom: mapZoom,
          onZoomChanged: (z) => setState(() => mapZoom = z),
          headingUp: mapHeadingUp,
          onCompassTap: () => setState(() => mapHeadingUp = false),
          accentColor: Theme.of(context).colorScheme.primary,
          vehicleColor: _vehicleColor(rec.mode),
          vehicleMarkerPainter: markerPainterFor(appPrefs.vehicleSelection, rec.mode, bodyColor: _vehicleColor(rec.mode)),
        ),
      ),
      // v1.0.2 记录页底部面板底色统一为卡片色 #1E1E1E（仅改色，不改结构/逻辑）。
      Container(
        padding: const EdgeInsets.all(12),
        color: CardStyle.cardColor,
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(rec.curSpeed * 3.6).toStringAsFixed(0)}', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: _speedColor(rec.curSpeed * 3.6))),
                const Text('km/h', style: TextStyle(color: Colors.white60)),
                const Text('时速区间：<60 白 · 60–100 黄 · >100 红', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                Text('里程 ${(rec.distanceM / 1000).toStringAsFixed(2)} km · ${fmtDur(rec.elapsedMs)}', style: const TextStyle(color: Colors.white70)),
                Text('定位精度 ${rec.curHAcc >= 999 ? '—' : '${rec.curHAcc.toStringAsFixed(0)} m'}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (rec.mode == TripMode.moto) Text('倾角 ${rec.rollDeg.toStringAsFixed(0)}°', style: const TextStyle(color: Colors.white, fontSize: 14)),
                if (rec.mode == TripMode.bike)
                  Text(
                    '功率 ${rec.powerW == null ? '—' : '${rec.powerW!.toStringAsFixed(0)}W${rec.powerEstimated ? '（估算）' : ''}'} · 踏频 ${rec.cadenceRpm == null ? '未接入' : '${rec.cadenceRpm!.toStringAsFixed(0)} rpm'} · 心率 ${rec.heartRate ?? '—'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ]),
            ),
            RippleTap(
              circular: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GPage(rec: rec))),
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
          const SizedBox(height: 10),
          // v0.1.7 拍照打点：街道/赛道记录页共用，醒目全宽按钮，位于
          // 暂停/长按结束上方；一键只存当前轨迹点坐标+时间，无照片
          // 也可先打点，照片之后在详情相册附。
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: Text(
                  '拍照打点${livePhotoPoints.isEmpty ? '' : '（已打 ${livePhotoPoints.length} 个）'}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _addPhotoPoint,
            ),
          ),
          const SizedBox(height: 4),
          const Text('一键存当前坐标与时间，无照片也可先打点；结束后在详情页“行程相册”附照片、写备注',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final now = DateTime.now();
                  if (_lastPauseTap != null && now.difference(_lastPauseTap!).inMilliseconds < 500) return;
                  _lastPauseTap = now;
                  if (rec.isRecording) {
                    await rec.pause();
                  } else {
                    await rec.resume();
                  }
                  setState(() {});
                },
                child: Text(rec.isRecording ? '暂停' : '恢复'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RippleTap(
                borderRadius: BorderRadius.circular(24),
                onLongPress: _endTrip,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(24)),
                  child: const Text('长按结束', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(rec.calibrationNote, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    ]);
  }

  Widget _buildList() {
    final accent = Theme.of(context).colorScheme.primary;
    final demoCard = DriveTrackCard(
      borderColor: accent.withValues(alpha: 0.5),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.science_outlined, color: accent, size: 18),
            const SizedBox(width: 6),
            const Text('体验演示', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
              child: const Text('演示 · 不计入真实统计', style: TextStyle(fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('合成路线，仅用于体验界面。', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.play_circle), label: const Text('生成演示行程'), onPressed: _makeDemo),
        ]),
    );
    if (trips.isEmpty) {
      return SingleChildScrollView(
        child: Column(children: [
          demoCard,
          _monthlyFuelCard(),
          const SizedBox(height: 24),
          const Center(child: Text('还没有行程\n去首页开始一次记录', textAlign: TextAlign.center)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: trips.length + 2,
      itemBuilder: (ctx, i) {
        if (i == 0) return demoCard;
        if (i == 1) return _monthlyFuelCard();
        final m = trips[i - 2];
        return DriveTrackCard(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text('${m.mode.label} · ${(m.distanceM / 1000).toStringAsFixed(2)} km · 评分 ${m.score.toStringAsFixed(0)}${m.demo ? ' · 演示' : ''}'),
            subtitle: Text('${fmtDate(m.startMs)} · 时长 ${fmtDur(m.endMs - m.startMs)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailPage(store: store, tripId: m.id))),
          ),
        );
      },
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
    final rec = widget.rec;
    final now = DateTime.now().millisecondsSinceEpoch;
    final trail = rec.gHistory.where((g) => now - g.timeMs <= 5000).toList();
    final mag = math.sqrt(rec.smoothLong * rec.smoothLong + rec.smoothLat * rec.smoothLat);
    return Scaffold(
      appBar: AppBar(title: const Text('G 值实时')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
          Text('当前纵向 ${rec.smoothLong.toStringAsFixed(2)}g · 横向 ${rec.smoothLat.toStringAsFixed(2)}g · 合成 ${mag.toStringAsFixed(2)}g',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('峰值保持：纵向 ${rec.peakHoldLong.toStringAsFixed(2)}g · 横向 ${rec.peakHoldLat.toStringAsFixed(2)}g（保持 2 秒）',
              style: const TextStyle(color: Colors.white70)),
          Text('本趟峰值：纵向 ${rec.tripPeakLong.toStringAsFixed(2)}g · 横向 ${rec.tripPeakLat.toStringAsFixed(2)}g',
              style: const TextStyle(color: Colors.white70)),
          Text('姿态：俯仰 ${rec.pitchDeg.toStringAsFixed(1)}° · 横滚 ${rec.rollDeg.toStringAsFixed(1)}°',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft, child: Text('最近 60 秒波形（青=纵向，品红=横向，橙虚线=阈值）')),
          const SizedBox(height: 6),
          GWaveform(history: rec.gHistory, threshold: ModeThresholds.of(rec.mode).harshCorner),
          const SizedBox(height: 8),
          Text(rec.calibrated ? '已标定' : '未标定：G 值仅作参考，不进评分和事件统计',
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
  int scrub = -1;
  TripEvent? selectedEvent;
  bool sharing = false;
  bool sharingFile = false;
  final GlobalKey _previewCardKey = GlobalKey();
  String selectedScoreKey = '';
  bool leanMountedConfirmed = false;
  bool previewTrim = true;

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败：$e')));
    }
    if (mounted) setState(() => sharing = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    trip = await widget.store.loadTrip(widget.tripId);
    metas = await widget.store.loadIndex();
    if (mounted) setState(() {});
  }

  /// v0.1.7 行程相册：改动（附照片/改备注/删点）经相册页 onChanged
  /// 回传后落盘；失败时提示且不改界面上的 trip，避免假装已保存。
  Future<void> _savePhotoPoints(List<PhotoPoint> pts) async {
    final t = trip;
    if (t == null) return;
    final nt = await widget.store.updateTripPhotoPoints(t.id, pts);
    if (nt != null && mounted) setState(() => trip = nt);
  }

  void _openAlbum() {
    final t = trip;
    if (t == null) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TripAlbumPage(
                  initialPhotoPoints: t.photoPoints,
                  trackPoints:
                      t.points.map((p) => (lat: p.lat, lon: p.lon)).toList(),
                  onChanged: _savePhotoPoints,
                )));
  }

  /// 给最新一个未附照片的打点附照片（拍照或相册选取二选一，
  /// 见 photo_points.dart 的 pickOrTakePhoto）。
  Future<void> _attachToLatestUnphotographed() async {
    final t = trip;
    if (t == null) return;
    final idx = t.photoPoints.lastIndexWhere((p) => !p.hasPhoto);
    if (idx < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全部照片点都已有照片')));
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
    if (kind == 'gpx') {
      final path = '$dir/trip_${trip!.id}.gpx';
      await File(path).writeAsString(widget.store.toGpx(trip!, trimmed: trimmed));
      await Native.shareFiles([path], 'application/gpx+xml', '驰迹 GPX（${trimmed ? '已截掉首尾' : '完整轨迹'}）');
    } else {
      final path = '$dir/trip_${trip!.id}.csv';
      await File(path).writeAsString(widget.store.toCsv(trip!, trimmed: false));
      await Native.shareFiles([path], 'text/csv', '驰迹 CSV（完整数据）');
    }
    } finally {
      if (mounted) setState(() => sharingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = trip;
    if (t == null) return Scaffold(appBar: AppBar(title: const Text('行程详情')), body: const Center(child: CircularProgressIndicator()));
    final _fk = selectedScoreKey.isEmpty ? null : scoreKeyToEventKinds(selectedScoreKey);
    final _kinds = (_fk == null || _fk.isEmpty) ? null : _fk;
    final corners = t.events.where((e) => e.kind == 'corner' && (_kinds == null || _kinds.contains(e.kind))).toList()..sort((a, b) => b.peakLatG.abs().compareTo(a.peakLatG.abs()));
    final others = t.events.where((e) => e.kind != 'corner' && (_kinds == null || _kinds.contains(e.kind))).toList();
    final splits = paceSplitsKm(t.points);
    final shown = widget.store.trimmedPoints(t);
    final centerPt = scrub >= 0 && scrub < t.points.length ? t.points[scrub] : t.points[t.points.length ~/ 2];
    final trend = metas.where((m) => m.mode == t.mode).take(6).toList().reversed.toList();
    final powers = t.points.where((p) => p.powerW != null).map((p) => p.powerW!).toList();
    final avgPower = powers.isEmpty ? 0.0 : powers.reduce((a, b) => a + b) / powers.length;
    final cads = t.points.where((p) => p.cadenceRpm != null).map((p) => p.cadenceRpm!).toList();
    final avgCad = cads.isEmpty ? 0.0 : cads.reduce((a, b) => a + b) / cads.length;
    return Scaffold(
      appBar: AppBar(leading: GlassButton.back(onPressed: () => Navigator.pop(context)), title: Text('${t.mode.label}行程 · ${fmtDate(t.startMs)}')),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // v0.1.3 详情页地图同步精细化（跟随关闭、北向上、源切换回调为空时内部切换）。
          RefinedMap(
            centerLat: centerPt.lat,
            centerLon: centerPt.lon,
            headingDeg: centerPt.heading,
            accuracyMeters: centerPt.hAcc >= 999 ? 0 : centerPt.hAcc,
            zoom: _fitZoom(t.points),
            points: t.points.map((p) => RefinedTrackPoint(lat: p.lat, lon: p.lon, speedKmh: p.speed * 3.6)).toList(),
            follow: false,
            headingUp: false,
            height: 320,
            accentColor: Theme.of(context).colorScheme.primary,
            vehicleMarkerKind: _vehicleKind(t.mode),
            vehicleMarkerColor: _vehicleColor(t.mode),
            vehicleMarkerPainter: markerPainterFor(appPrefs.vehicleSelection, t.mode, bodyColor: _vehicleColor(t.mode)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Text('拖动回放：'),
              Expanded(
                child: Slider(
                  value: (scrub < 0 ? t.points.length - 1 : scrub).toDouble(),
                  min: 0,
                  max: (t.points.length - 1).toDouble(),
                  onChanged: (v) => setState(() => scrub = v.toInt()),
                ),
              ),
              Text(scrub < 0 ? '终点' : fmtDate(t.points[scrub].timeMs)),
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
              const Text('数据分析 · 遥测',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('仅行程实测数据，非任何车队官方分析页；拖动上方回放滑块或点选曲线时，各图当前点一起联动；速度曲线顶部的三角标记为事件（急加速绿 / 急刹红 / 弯道黄），点事件列表也可跳到该点。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                  const Expanded(child: Text('本次手机已固定在车上（勾选后才显示压弯曲线）', style: TextStyle(fontSize: 12))),
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
                onPhotoTap: (_) => _openAlbum(),
                onAttachToLatestUnphotographed:
                    _attachToLatestUnphotographed,
              ),
              if (t.mode != TripMode.bike) ...[
                const SizedBox(height: 12),
                TripFuelCard(
                  trip: t,
                  consumptionLPer100Km: appPrefs.fuelConsumptionLPer100Km,
                  fuelPricePerLiter: appPrefs.fuelPricePerLiter,
                ),
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
                Text('赛道：${t.trackName} · 赛道模式（示意轮廓，非官方测绘）', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              const Text('历次同模式评分趋势（左旧右新）'),
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
              const Text('G 值复盘', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              GScatter(points: t.points, threshold: ModeThresholds.of(t.mode).harshCorner, size: 220),
              Text('整趟 G-G 散点图：每个点是一秒轨迹点，橙圈为本趟最大合成 G 包络；下方波形为整趟纵向（青）/横向（品红）G 随时间变化',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              GWaveform(
                history: t.points.map((p) => GSample(p.timeMs, p.longG, p.latG)).toList(),
                threshold: ModeThresholds.of(t.mode).harshCorner,
              ),
              const SizedBox(height: 12),
              if (corners.isNotEmpty) ...[
                const Text('过弯榜（按横向 G 排序）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                const Text('压弯分布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('超 30° 累计：${t.points.where((p) => p.roll.abs() > 30).length} 秒 · 最大左倾 ${t.events.fold(0.0, (a, e) => math.max(a, e.maxLeanLeft)).toStringAsFixed(0)}° · 最大右倾 ${t.events.fold(0.0, (a, e) => math.max(a, e.maxLeanRight)).toStringAsFixed(0)}°'),
              ],
              if (others.isNotEmpty) ...[
                const Text('全部事件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                const Text('每公里配速', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (var i = 0; i < splits.length; i++) Text('第 ${i + 1} 公里：${splits[i].toStringAsFixed(2)} min/km'),
              ],
              if (selectedEvent != null) ...[
                const Text('选中事件的 G 波形小图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              const Text('同步视频', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (t.videoPaths.isEmpty)
                const Text('暂无关联视频', style: TextStyle(color: Colors.white54, fontSize: 12)),
              if (t.videoPaths.isNotEmpty) ...[
                Text('共 ${t.videoPaths.length} 段（每段最长 10 分钟自动分段），视频仅存本机。',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                for (final vp in t.videoPaths)
                  ListTile(
                    leading: const Icon(Icons.videocam),
                    title: Text(vp.split('/').last),
                    // v0.1.7 追加项 3：首选应用内视频回顾（画面叠加 HUD），
                    // 系统播放器与分享作为备用入口保留；HUD 未烧录进视频文件。
                    subtitle: const Text('点回顾进应用内播放（画面叠加速度/G 值），系统播放与分享为备用'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.ondemand_video), tooltip: '视频回顾（应用内叠加）', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoReviewPage(trip: t, initialSegment: t.videoPaths.indexOf(vp))))),
                      IconButton(icon: const Icon(Icons.play_arrow), tooltip: '系统播放器播放', onPressed: () => Native.playVideo(vp)),
                      IconButton(icon: const Icon(Icons.share), tooltip: '分享视频', onPressed: () => Native.shareFiles([vp], 'video/mp4', '驰迹行程视频')),
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
                  },
                  selected: t.isPublic,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(t.liked ? Icons.favorite : Icons.favorite_border, color: t.liked ? Colors.red : null),
                  tooltip: '点赞（本机计数）',
                  onPressed: () async {
                    final nt = await widget.store.updateTripSocial(t.id, toggleLike: true);
                    if (nt != null && mounted) setState(() => trip = nt);
                  },
                ),
                Text('${t.likes}'),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pillButton('分享卡预览', Icons.share, () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShareCardPreviewPage(
                      trip: t,
                      videoPath: t.videoPaths.isEmpty ? null : t.videoPaths.first,
                      trimPrivacy: previewTrim,
                      onTrimPrivacyChanged: (v) => setState(() => previewTrim = v),
                      cardBoundaryKey: _previewCardKey,
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
                    )))),
                _pillButton('分享 GPX', Icons.file_download, sharingFile ? null : () => _shareFile('gpx')),
                _pillButton('分享 CSV', Icons.file_download, sharingFile ? null : () => _shareFile('csv')),
                _pillButton(
                  t.videoPaths.isEmpty ? '同步视频 · 暂无' : '同步视频',
                  Icons.videocam,
                  t.videoPaths.isEmpty
                      ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无关联视频')))
                      : () => Native.shareFiles([t.videoPaths.first], 'video/mp4', '驰迹行程视频'),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('分享走系统分享，不登录不上传。GPX 默认按隐私开关截掉首尾；CSV 为完整数据，请自行注意隐私。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}
