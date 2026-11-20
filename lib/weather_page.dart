/// 驰迹独立天气页（v0.1.3 新文件，路由跳转用，不是弹窗）。
///
/// 构造：传入 [WeatherData] 模型与刷新回调 [onRefresh]；可选传入行进方向
/// [headingDeg]（度，0=北顺时针），有它才算侧风，没有它只显示风向，不编侧风。
/// 本页不自己拉接口、不改任何已有文件，接线（Navigator.push、刷新后重建）
/// 由总协调负责。
///
/// 显示规则：模型字段为 null 的项一律显示“暂无”，不编数；结冰风险只在
/// 低温 + 高湿时出现提示条，否则不出现；恶劣天气提示分两行说清——
/// “官方预警”恒为“暂无”（Open-Meteo 预报接口不提供官方预警文本），
/// 其余为“根据当前数据推导的驾驶提示，非官方预警”。
library;

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'weather_service.dart';

/// 独立天气页：Scaffold + AppBar 返回，点系统/导航返回即顺畅退出。
class WeatherPage extends StatelessWidget {
  final WeatherData? weather;

  /// 刷新回调（总协调传入，如重新拉取后 setState 重建本页）。
  final VoidCallback? onRefresh;

  /// 行进方向（度），为 null 时不计算侧风。
  final double? headingDeg;

  const WeatherPage({
    super.key,
    required this.weather,
    this.onRefresh,
    this.headingDeg,
  });

  static const _cardColor = Color(0xFF0B0E13);

  String _updatedLabel(S s, DateTime? t) {
    if (t == null) return s.t('暂无', 'N/A');
    final p = t;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${p.year}-${two(p.month)}-${two(p.day)} ${two(p.hour)}:${two(p.minute)}';
  }

  String _hhmm(S s, DateTime? t) {
    if (t == null) return s.t('暂无', 'N/A');
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _orNone(S s, String? v) =>
      (v == null || v.isEmpty) ? s.t('暂无', 'N/A') : v;

  String _numOrNone(S s, double? v, String unit, [int digits = 0]) =>
      v == null ? s.t('暂无', 'N/A') : '${v.toStringAsFixed(digits)} $unit';

  String _weekday(S s, DateTime d) {
    const zhNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const enNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return s.t(zhNames[d.weekday - 1], enNames[d.weekday - 1]);
  }

  IconData _iconForCode(int? code) {
    if (code == null) return Icons.help_outline;
    if (code == 0) return Icons.wb_sunny;
    if (code == 1 || code == 2) return Icons.cloud;
    if (code == 3) return Icons.cloud_queue;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return Icons.umbrella;
    if (code >= 71 && code <= 77 || code == 85 || code == 86) return Icons.ac_unit;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.help_outline;
  }

  Widget _sourceLine(WeatherData? w, S s) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        s.t(
          '来源：$weatherSourceName · 更新：${_updatedLabel(s, w?.fetchedAt)}',
          'Source: $weatherSourceName · Updated: ${_updatedLabel(s, w?.fetchedAt)}',
        ),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children, WeatherData? w) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                          fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
          _sourceLine(w, s),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final w = weather;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(
          s.t('天气', 'Weather'),
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          if (onRefresh != null)
            Semantics(label: s.t('刷新', 'Refresh'), child: IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: onRefresh)),
        ],
      ),
      body: w == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 40, color: Colors.white54),
                  const SizedBox(height: 12),
                  Text(s.t('暂无天气数据', 'No weather data'), style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                    s.t(
                      '来源：$weatherSourceName · 更新：暂无',
                      'Source: $weatherSourceName · Updated: N/A',
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  if (onRefresh != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onRefresh,
                      child: Text(s.t('重新获取', 'Reload')),
                    ),
                  ],
                ],
              ),
            )
          : ListView(
              padding: withAppBarTopInset(context, const EdgeInsets.all(16)),
              children: [
                _section(context, s.t('当前天气', 'Current'), [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconForCode(w.weatherCode), size: 40, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.temperature == null ? s.t('暂无', 'N/A') : '${w.temperature!.toStringAsFixed(0)}°C',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              w.conditionText,
                              style: const TextStyle(fontSize: 15, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _row(Icons.thermostat, s.t('体感温度', 'Feels like'), _numOrNone(s, w.apparentTemperature, '°C')),
                  _row(Icons.cloud, s.t('云量', 'Cloud cover'), _numOrNone(s, w.cloudCover, '%')),
                ], w),
                _section(context, s.t('降水', 'Precipitation'), [
                  _row(Icons.umbrella, s.t('降水概率（未来1小时）', 'Precip. chance (next hour)'), _numOrNone(s, w.precipitationProbability, '%')),
                  _row(Icons.water_drop, s.t('降水量', 'Precipitation'), _numOrNone(s, w.precipitation, 'mm', 1)),
                  _row(Icons.grain, s.t('降水类型', 'Precip. type'), _orNone(s, w.precipitationType)),
                  _row(Icons.ac_unit, s.t('降雪量', 'Snowfall'), w.snowfall == null ? s.t('暂无', 'N/A') : '${w.snowfall!.toStringAsFixed(1)} cm'),
                ], w),
                _section(context, s.t('风', 'Wind'), [
                  _row(Icons.air, s.t('风速', 'Wind speed'), _numOrNone(s, w.windSpeed, 'km/h')),
                  _row(Icons.wind_power, s.t('阵风', 'Gusts'), _numOrNone(s, w.windGusts, 'km/h')),
                  _row(
                    Icons.navigation,
                    s.t('风向', 'Wind direction'),
                    w.windDirection == null
                        ? s.t('暂无', 'N/A')
                        : '${WeatherData.compass(w.windDirection)} ${w.windDirection!.toStringAsFixed(0)}°',
                  ),
                  Builder(
                    builder: (_) {
                      final cross = w.crosswind(headingDeg);
                      if (headingDeg == null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            s.t(
                              '未提供行进方向，未计算侧风。',
                              'Heading not provided; crosswind not calculated.',
                            ),
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        );
                      }
                      if (cross == null) {
                        return _row(Icons.air, s.t('侧风', 'Crosswind'), s.t('暂无', 'N/A'));
                      }
                      return _row(
                        Icons.air,
                        s.t('侧风', 'Crosswind'),
                        s.t(
                          '来自${cross.fromSide} ${cross.speed.toStringAsFixed(0)} km/h',
                          'from ${cross.fromSide} ${cross.speed.toStringAsFixed(0)} km/h',
                        ),
                      );
                    },
                  ),
                ], w),
                _section(context, s.t('能见度 · 湿度 · 气压 · 露点', 'Visibility · Humidity · Pressure · Dew point'), [
                  _row(Icons.visibility, s.t('能见度', 'Visibility'), w.visibility == null ? s.t('暂无', 'N/A') : '${(w.visibility! / 1000).toStringAsFixed(1)} km'),
                  _row(Icons.water, s.t('湿度', 'Humidity'), _numOrNone(s, w.humidity, '%')),
                  _row(Icons.speed, s.t('气压', 'Pressure'), _numOrNone(s, w.pressure, 'hPa')),
                  _row(Icons.dew_point, s.t('露点', 'Dew point'), _numOrNone(s, w.dewPoint, '°C', 1)),
                  // 结冰风险：仅低温 + 高湿时出现，否则本条不渲染。
                  if (w.icingRisk)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE10600).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE10600).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.t(
                                '结冰风险：低温高湿，路面可能结冰，谨慎驾驶。',
                                'Icing risk: cold and humid; roads may freeze. Drive carefully.',
                              ),
                              style: const TextStyle(fontSize: 13, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                ], w),
                _section(context, s.t('日出日落', 'Sunrise & sunset'), [
                  _row(Icons.wb_twilight, s.t('日出', 'Sunrise'), _hhmm(s, w.sunrise)),
                  _row(Icons.nights_stay, s.t('日落', 'Sunset'), _hhmm(s, w.sunset)),
                ], w),
                _section(context, s.t('未来 24 小时（逐小时）', 'Next 24 hours (hourly)'), [
                  if (w.hourly24.isEmpty)
                    Text(s.t('暂无', 'N/A'), style: const TextStyle(color: Colors.white))
                  else
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: w.hourly24.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final h = w.hourly24[i];
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_hhmm(s, h.time),
                                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              const SizedBox(height: 4),
                              Icon(_iconForCode(h.weatherCode), size: 18, color: Colors.white),
                              const SizedBox(height: 4),
                              Text(h.temperature == null ? s.t('暂无', 'N/A') : '${h.temperature!.toStringAsFixed(0)}°',
                                  style: const TextStyle(fontSize: 13, color: Colors.white)),
                              Text(h.precipitationProbability == null ? s.t('暂无', 'N/A') : '${h.precipitationProbability!.toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
                            ],
                          );
                        },
                      ),
                    ),
                ], w),
                _section(context, s.t('未来 7 天', 'Next 7 days'), [
                  if (w.daily7.isEmpty)
                    Text(s.t('暂无', 'N/A'), style: const TextStyle(color: Colors.white))
                  else
                    for (final d in w.daily7)
                      _row(
                        _iconForCode(d.weatherCode),
                        '${_weekday(s, d.date)} ${d.date.month}/${d.date.day} ${WeatherData.codeText(d.weatherCode)}',
                        '${d.tempMin == null ? s.t('暂无', 'N/A') : d.tempMin!.toStringAsFixed(0)}° / ${d.tempMax == null ? s.t('暂无', 'N/A') : d.tempMax!.toStringAsFixed(0)}°'
                        '${d.precipitationProbabilityMax == null ? '' : ' · ${d.precipitationProbabilityMax!.toStringAsFixed(0)}%'}',
                      ),
                ], w),
                _section(context, s.t('恶劣天气预警', 'Severe weather alerts'), [
                  _row(Icons.warning_amber, s.t('官方预警', 'Official alerts'), s.t('暂无', 'N/A')),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      s.t(
                        '预报接口不提供官方预警文本。',
                        'The forecast API does not provide official alert text.',
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                  Text(
                    s.t('驾驶提示（非官方预警）：', 'Driving tips (not official alerts):'),
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  if (w.drivingAlerts.isEmpty)
                    Text(
                        s.t('暂无恶劣天气驾驶提示。',
                            'No severe-weather driving tips.'),
                        style: const TextStyle(fontSize: 13, color: Colors.white))
                  else
                    for (final a in w.drivingAlerts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.t('${a.title}：${a.advice}', '${a.title}: ${a.advice}'),
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                ], w),
              ],
            ),
    );
  }
}
