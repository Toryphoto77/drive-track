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

  String _updatedLabel(DateTime? t) {
    if (t == null) return '暂无';
    final p = t;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${p.year}-${two(p.month)}-${two(p.day)} ${two(p.hour)}:${two(p.minute)}';
  }

  String _hhmm(DateTime? t) {
    if (t == null) return '暂无';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _orNone(String? v) => (v == null || v.isEmpty) ? '暂无' : v;

  String _numOrNone(double? v, String unit, [int digits = 0]) =>
      v == null ? '暂无' : '${v.toStringAsFixed(digits)} $unit';

  String _weekday(DateTime d) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[d.weekday - 1];
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

  Widget _sourceLine(WeatherData? w) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '来源：$weatherSourceName · 更新：${_updatedLabel(w?.fetchedAt)}',
        style: const TextStyle(
          fontFamily: 'DriveTrackSans',
          fontSize: 11,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children, WeatherData? w) {
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
                  fontFamily: 'DriveTrackSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
          _sourceLine(w),
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
            style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white70),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = weather;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        title: const Text(
          '天气',
          style: TextStyle(fontFamily: 'DriveTrackDisplay', fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          if (onRefresh != null)
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: onRefresh, tooltip: '刷新'),
        ],
      ),
      body: w == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 40, color: Colors.white54),
                  const SizedBox(height: 12),
                  const Text('暂无天气数据', style: TextStyle(fontFamily: 'DriveTrackSans', color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                    '来源：$weatherSourceName · 更新：暂无',
                    style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 12, color: Colors.white54),
                  ),
                  if (onRefresh != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRefresh, child: const Text('重新获取')),
                  ],
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(context, '当前天气', [
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
                              w.temperature == null ? '暂无' : '${w.temperature!.toStringAsFixed(0)}°C',
                              style: const TextStyle(
                                fontFamily: 'DriveTrackDisplay',
                                fontSize: 44,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              w.conditionText,
                              style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 15, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _row(Icons.thermostat, '体感温度', _numOrNone(w.apparentTemperature, '°C')),
                  _row(Icons.cloud, '云量', _numOrNone(w.cloudCover, '%')),
                ], w),
                _section(context, '降水', [
                  _row(Icons.umbrella, '降水概率（未来1小时）', _numOrNone(w.precipitationProbability, '%')),
                  _row(Icons.water_drop, '降水量', _numOrNone(w.precipitation, 'mm', 1)),
                  _row(Icons.grain, '降水类型', _orNone(w.precipitationType)),
                  _row(Icons.ac_unit, '降雪量', w.snowfall == null ? '暂无' : '${w.snowfall!.toStringAsFixed(1)} cm'),
                ], w),
                _section(context, '风', [
                  _row(Icons.air, '风速', _numOrNone(w.windSpeed, 'km/h')),
                  _row(Icons.wind_power, '阵风', _numOrNone(w.windGusts, 'km/h')),
                  _row(
                    Icons.navigation,
                    '风向',
                    w.windDirection == null
                        ? '暂无'
                        : '${WeatherData.compass(w.windDirection)} ${w.windDirection!.toStringAsFixed(0)}°',
                  ),
                  Builder(
                    builder: (_) {
                      final cross = w.crosswind(headingDeg);
                      if (headingDeg == null) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '未传入行进方向，仅显示风向，未计算侧风。',
                            style: TextStyle(fontFamily: 'DriveTrackSans', fontSize: 12, color: Colors.white54),
                          ),
                        );
                      }
                      if (cross == null) {
                        return _row(Icons.air, '侧风', '暂无');
                      }
                      return _row(Icons.air, '侧风', '来自${cross.fromSide} ${cross.speed.toStringAsFixed(0)} km/h');
                    },
                  ),
                ], w),
                _section(context, '能见度 · 湿度 · 气压 · 露点', [
                  _row(Icons.visibility, '能见度', w.visibility == null ? '暂无' : '${(w.visibility! / 1000).toStringAsFixed(1)} km'),
                  _row(Icons.water, '湿度', _numOrNone(w.humidity, '%')),
                  _row(Icons.speed, '气压', _numOrNone(w.pressure, 'hPa')),
                  _row(Icons.dew_point, '露点', _numOrNone(w.dewPoint, '°C', 1)),
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
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '结冰风险提示：低温高湿，路面可能结冰，谨慎驾驶。',
                              style: TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                ], w),
                _section(context, '日出日落', [
                  _row(Icons.wb_twilight, '日出', _hhmm(w.sunrise)),
                  _row(Icons.nights_stay, '日落', _hhmm(w.sunset)),
                ], w),
                _section(context, '未来 24 小时（逐小时）', [
                  if (w.hourly24.isEmpty)
                    const Text('暂无', style: TextStyle(fontFamily: 'DriveTrackSans', color: Colors.white))
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
                              Text(_hhmm(h.time),
                                  style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 12, color: Colors.white70)),
                              const SizedBox(height: 4),
                              Icon(_iconForCode(h.weatherCode), size: 18, color: Colors.white),
                              const SizedBox(height: 4),
                              Text(h.temperature == null ? '暂无' : '${h.temperature!.toStringAsFixed(0)}°',
                                  style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white)),
                              Text(h.precipitationProbability == null ? '暂无' : '${h.precipitationProbability!.toStringAsFixed(0)}%',
                                  style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 11, color: Colors.white54)),
                            ],
                          );
                        },
                      ),
                    ),
                ], w),
                _section(context, '未来 7 天', [
                  if (w.daily7.isEmpty)
                    const Text('暂无', style: TextStyle(fontFamily: 'DriveTrackSans', color: Colors.white))
                  else
                    for (final d in w.daily7)
                      _row(
                        _iconForCode(d.weatherCode),
                        '${_weekday(d.date)} ${d.date.month}/${d.date.day} ${WeatherData.codeText(d.weatherCode)}',
                        '${d.tempMin == null ? '暂无' : d.tempMin!.toStringAsFixed(0)}° / ${d.tempMax == null ? '暂无' : d.tempMax!.toStringAsFixed(0)}°'
                        '${d.precipitationProbabilityMax == null ? '' : ' · ${d.precipitationProbabilityMax!.toStringAsFixed(0)}%'}',
                      ),
                ], w),
                _section(context, '恶劣天气预警', [
                  _row(Icons.warning_amber, '官方预警', '暂无'),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 8),
                    child: Text(
                      'Open-Meteo 预报接口不提供官方预警文本，本行不编预警。',
                      style: TextStyle(fontFamily: 'DriveTrackSans', fontSize: 12, color: Colors.white54),
                    ),
                  ),
                  const Text(
                    '根据当前数据推导的驾驶提示（非官方预警）：',
                    style: TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  if (w.drivingAlerts.isEmpty)
                    const Text('当前数据未触发恶劣天气驾驶提示。',
                        style: TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white))
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
                                '${a.title}：${a.advice}',
                                style: const TextStyle(fontFamily: 'DriveTrackSans', fontSize: 13, color: Colors.white),
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
