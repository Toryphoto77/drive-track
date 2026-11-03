/// 驰迹天气扩展服务（v0.1.3 新文件，不改动 lib/store.dart 的旧 fetchWeather）。
///
/// 数据源：只有 Open-Meteo 预报接口（https://api.open-meteo.com/v1/forecast），
/// 无需 key。请求参数是在旧请求基础上的扩展，旧请求只拉了
/// current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,visibility
/// 与 hourly=precipitation_probability&forecast_days=1。
/// 本文件扩展后拉取的全部字段均为 Open-Meteo 预报接口文档内的真实变量，
/// 没有编造数据源字段。接口没给的字段一律返回 null，界面层显示“暂无”，不编数。
///
/// Open-Meteo 预报接口不提供官方预警文本：[WeatherData.officialWarning]
/// 恒为 null，天气页里“官方预警”一行因此显示“暂无”，驾驶提示一律标注为
/// “根据当前数据推导，非官方预警”，不冒充官方预警。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// 统一来源标注，界面层直接用它，不各自硬编码。
const String weatherSourceName = 'Open-Meteo';

/// 未来 1 条逐小时预报。
class HourlyForecast {
  final DateTime time;
  final double? temperature;
  final int? weatherCode;
  final double? precipitationProbability;
  final double? precipitation;

  const HourlyForecast({
    required this.time,
    this.temperature,
    this.weatherCode,
    this.precipitationProbability,
    this.precipitation,
  });
}

/// 未来 1 天预报。
class DailyForecast {
  final DateTime date;
  final double? tempMax;
  final double? tempMin;
  final int? weatherCode;
  final double? precipitationProbabilityMax;

  const DailyForecast({
    required this.date,
    this.tempMax,
    this.tempMin,
    this.weatherCode,
    this.precipitationProbabilityMax,
  });
}

/// 由当前数据推导出的驾驶提示（非官方预警，见文件头注释）。
class DrivingAlert {
  final String title;
  final String advice;

  const DrivingAlert(this.title, this.advice);
}

/// 侧风估算结果：风速在垂直于行进方向上的分量。
class Crosswind {
  /// 侧风分量大小（km/h，恒为非负）。
  final double speed;

  /// 风从哪一侧吹来：'左侧' 或 '右侧'。
  final String fromSide;

  const Crosswind(this.speed, this.fromSide);
}

/// Open-Meteo 扩展天气模型：所有扩展字段均可为 null。
class WeatherData {
  final DateTime fetchedAt;

  /// 当前：温度（℃）、体感（℃）、天气代码、云量（%）。
  final double? temperature;
  final double? apparentTemperature;
  final int? weatherCode;
  final double? cloudCover;

  /// 降水：降水概率（%）、降水量（mm）、雨量（mm）、阵雨量（mm）、降雪量（cm）。
  /// 雨/雪区分优先看 rain/showers/snowfall 的量，其次看天气代码区间。
  final double? precipitationProbability;
  final double? precipitation;
  final double? rain;
  final double? showers;
  final double? snowfall;

  /// 风：风速（km/h）、阵风（km/h）、风向（度，风从该方向吹来）。
  final double? windSpeed;
  final double? windGusts;
  final double? windDirection;

  /// 能见度（m）、湿度（%）、气压（hPa）、露点（℃）。
  final double? visibility;
  final double? humidity;
  final double? pressure;
  final double? dewPoint;

  /// 日出 / 日落（接口 timezone=auto，返回当地时间）。
  final DateTime? sunrise;
  final DateTime? sunset;

  /// 未来 24 小时逐小时、未来 7 天。
  final List<HourlyForecast> hourly24;
  final List<DailyForecast> daily7;

  /// 官方预警文本：Open-Meteo 预报接口不提供，恒为 null，界面显示“暂无”。
  final String? officialWarning = null;

  const WeatherData({
    required this.fetchedAt,
    this.temperature,
    this.apparentTemperature,
    this.weatherCode,
    this.cloudCover,
    this.precipitationProbability,
    this.precipitation,
    this.rain,
    this.showers,
    this.snowfall,
    this.windSpeed,
    this.windGusts,
    this.windDirection,
    this.visibility,
    this.humidity,
    this.pressure,
    this.dewPoint,
    this.sunrise,
    this.sunset,
    this.hourly24 = const [],
    this.daily7 = const [],
  });

  String get conditionText => codeText(weatherCode);

  /// 降水类型：有量先看量，无量再看代码；都无法判断时返回 null（界面显示“暂无”）。
  String? get precipitationType {
    if ((snowfall ?? 0) > 0) return '雪';
    if ((rain ?? 0) > 0 || (showers ?? 0) > 0) return '雨';
    final c = weatherCode;
    if (c == null) return null;
    if (c >= 71 && c <= 77 || c == 85 || c == 86) return '雪';
    if (c >= 51 && c <= 67 || c >= 80 && c <= 82 || c >= 95) return '雨';
    return null;
  }

  /// 结冰风险：仅“低温 + 高湿”同时满足时为 true，否则 false，界面不提示。
  /// 阈值只是本地风险提示口径（≤3℃ 且湿度 ≥80%），不是路面结冰的实测结论。
  bool get icingRisk =>
      temperature != null &&
      temperature! <= 3 &&
      humidity != null &&
      humidity! >= 80;

  /// 侧风：无行进方向（headingDeg 为 null）或无风数据时返回 null，
  /// 调用方此时只显示风向，不编侧风。
  ///
  /// 算法：风向 windDirection 是“风从哪来”。行进方向 headingDeg 为 0=北，
  /// 顺时针为正。相对角 r = windDirection - headingDeg，侧风分量
  /// signed = windSpeed * sin(r)。r=90°（风从右侧来）时 signed 为正，
  /// r=270°（风从左侧来）时 signed 为负，据此定 fromSide。
  Crosswind? crosswind(double? headingDeg) {
    if (headingDeg == null || windSpeed == null || windDirection == null) {
      return null;
    }
    final r = (windDirection! - headingDeg) * math.pi / 180;
    final signed = windSpeed! * math.sin(r);
    if (signed.abs() < 1) return Crosswind(signed.abs(), signed >= 0 ? '右侧' : '左侧');
    return Crosswind(signed.abs(), signed > 0 ? '右侧' : '左侧');
  }

  /// 根据当前数据推导的驾驶提示（非官方预警）。无触发项时返回空列表。
  List<DrivingAlert> get drivingAlerts {
    final alerts = <DrivingAlert>[];
    if (visibility != null && visibility! < 1000) {
      alerts.add(DrivingAlert(
        visibility! < 200 ? '大雾：能见度极低' : '雾：能见度低',
        '能见度 ${(visibility! / 1000).toStringAsFixed(1)} km，减速、开雾灯、拉大车距。',
      ));
    }
    final c = weatherCode;
    if (c != null && c >= 51 && c <= 67 || c != null && c >= 80 && c <= 82) {
      alerts.add(const DrivingAlert('雨天：路面湿滑', '刹车距离变长，避开急刹急转，留意积水。'));
    }
    if (c != null && c >= 71 && c <= 77 || c != null && c == 85 || c != null && c == 86) {
      alerts.add(const DrivingAlert('降雪：路面易滑', '减速慢行，避开急加速急刹，留意桥面结冰。'));
    }
    if (c != null && c >= 95) {
      alerts.add(const DrivingAlert('雷阵雨', '能见度与路面条件可能骤变，必要时靠边停车等待。'));
    }
    if ((windSpeed ?? 0) >= 50 || (windGusts ?? 0) >= 70) {
      alerts.add(const DrivingAlert('大风：注意侧风', '阵风较强，握稳方向，超车与过桥时留意横风。'));
    }
    if (temperature != null && temperature! >= 35) {
      alerts.add(const DrivingAlert('高温', '留意轮胎与人员状态，补水，避免长时间暴晒驾驶。'));
    }
    if (temperature != null && temperature! <= 0) {
      alerts.add(const DrivingAlert('低温', '留意路面暗冰，起步与刹车放缓。'));
    }
    if ((precipitationProbability ?? 0) >= 70) {
      alerts.add(const DrivingAlert('降水概率高', '出发前确认雨具与雨刮状态，行程留出余量。'));
    }
    return alerts;
  }

  /// 天气代码中文，与旧 lib/store.dart 的 WeatherInfo.codeText 口径一致，
  /// 补 85/86（阵雪）与 96/99（冰雹雷阵雨）两档；code 为 null 时返回“暂无”。
  static String codeText(int? c) {
    if (c == null) return '暂无';
    if (c == 0) return '晴';
    if (c == 1 || c == 2) return '多云';
    if (c == 3) return '阴';
    if (c == 45 || c == 48) return '雾';
    if (c >= 51 && c <= 67) return '雨';
    if (c >= 71 && c <= 77) return '雪';
    if (c >= 80 && c <= 82) return '阵雨';
    if (c == 85 || c == 86) return '阵雪';
    if (c >= 95) return '雷阵雨';
    return '未知';
  }

  /// 风向 16 方位中文（0=北，顺时针）。
  static String compass(double? deg) {
    if (deg == null) return '暂无';
    const dirs = [
      '北', '北东北', '东北', '东东北', '东', '东东南', '东南', '南东南',
      '南', '南西南', '西南', '西西南', '西', '西西北', '西北', '北西北',
    ];
    final idx = ((deg % 360) / 22.5).round() % 16;
    return dirs[idx];
  }
}

double? _num(dynamic v) => (v as num?)?.toDouble();
int? _int(dynamic v) => (v as num?)?.toInt();
DateTime? _time(dynamic v) {
  if (v is! String) return null;
  return DateTime.tryParse(v);
}

List<T> _list<T>(dynamic v, T? Function(dynamic) f) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v) {
    final parsed = f(e);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

/// 扩展拉取：失败（网络、超时、解析）返回 null，与旧 fetchWeather 的失败口径一致。
Future<WeatherData?> fetchExtendedWeather(double lat, double lon) async {
  try {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,'
      'cloud_cover,precipitation,rain,showers,snowfall,pressure_msl,'
      'wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility,dew_point_2m'
      '&hourly=temperature_2m,weather_code,precipitation_probability,precipitation'
      '&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code,'
      'precipitation_probability_max'
      '&timezone=auto&forecast_days=7',
    );
    final req = await HttpClient().getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>? ?? {};
    final hourly = j['hourly'] as Map<String, dynamic>? ?? {};
    final daily = j['daily'] as Map<String, dynamic>? ?? {};

    // 未来 24 小时：从当前时间所在的那一小时起取 24 条，取不到则取前 24 条。
    final hourlyTimes = _list<String>(hourly['time'], (e) => e as String?);
    final hourlyParsed = <HourlyForecast>[];
    for (var i = 0; i < hourlyTimes.length; i++) {
      final t = DateTime.tryParse(hourlyTimes[i]);
      if (t == null) continue;
      T? at<T>(String key, T? Function(dynamic) f) {
        final list = hourly[key] as List?;
        if (list == null || i >= list.length) return null;
        return f(list[i]);
      }

      hourlyParsed.add(HourlyForecast(
        time: t,
        temperature: at('temperature_2m', _num),
        weatherCode: at('weather_code', _int),
        precipitationProbability: at('precipitation_probability', _num),
        precipitation: at('precipitation', _num),
      ));
    }
    final anchor = _time(cur['time']) ?? DateTime.now();
    var start = hourlyParsed.indexWhere((h) => !h.time.isBefore(anchor));
    if (start < 0) start = 0;
    final hourly24 = hourlyParsed.skip(start).take(24).toList();

    final dailyTimes = _list<String>(daily['time'], (e) => e as String?);
    final daily7 = <DailyForecast>[];
    for (var i = 0; i < dailyTimes.length && daily7.length < 7; i++) {
      final t = DateTime.tryParse(dailyTimes[i]);
      if (t == null) continue;
      T? at<T>(String key, T? Function(dynamic) f) {
        final list = daily[key] as List?;
        if (list == null || i >= list.length) return null;
        return f(list[i]);
      }

      daily7.add(DailyForecast(
        date: t,
        tempMax: at('temperature_2m_max', _num),
        tempMin: at('temperature_2m_min', _num),
        weatherCode: at('weather_code', _int),
        precipitationProbabilityMax: at('precipitation_probability_max', _num),
      ));
    }

    // 未来 1 小时降水概率：沿用旧口径，取逐小时第一条的概率；无数据则为 null。
    double? firstProb;
    if (hourly24.isNotEmpty) {
      firstProb = hourly24.first.precipitationProbability;
    }

    // 日出日落取当日（daily 第一条）；接口没给则为 null。
    DateTime? sunrise;
    DateTime? sunset;
    final sunrises = daily['sunrise'] as List?;
    final sunsets = daily['sunset'] as List?;
    if (sunrises != null && sunrises.isNotEmpty) sunrise = _time(sunrises.first);
    if (sunsets != null && sunsets.isNotEmpty) sunset = _time(sunsets.first);

    return WeatherData(
      fetchedAt: DateTime.now(),
      temperature: _num(cur['temperature_2m']),
      apparentTemperature: _num(cur['apparent_temperature']),
      weatherCode: _int(cur['weather_code']),
      cloudCover: _num(cur['cloud_cover']),
      precipitationProbability: firstProb,
      precipitation: _num(cur['precipitation']),
      rain: _num(cur['rain']),
      showers: _num(cur['showers']),
      snowfall: _num(cur['snowfall']),
      windSpeed: _num(cur['wind_speed_10m']),
      windGusts: _num(cur['wind_gusts_10m']),
      windDirection: _num(cur['wind_direction_10m']),
      visibility: _num(cur['visibility']),
      humidity: _num(cur['relative_humidity_2m']),
      pressure: _num(cur['pressure_msl']),
      dewPoint: _num(cur['dew_point_2m']),
      sunrise: sunrise,
      sunset: sunset,
      hourly24: hourly24,
      daily7: daily7,
    );
  } catch (_) {
    return null;
  }
}
