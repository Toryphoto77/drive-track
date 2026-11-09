/// v1.2.0 第 5 项：行程分析页（新增文件）。
///
/// 口径（写死在这里，不编数据）：
/// - 演示行程一律排除；街道组与赛道组按 TripMeta.isTrackMode 分组
///   （旧索引经 Store.migrateIndexTrackFields 回填后才可信）。
/// - 街道组：总里程 / 总时长 / 平均速度（总里程 ÷ 总时长，时长为
///   0 时为 null 不显示）/ 极速（各趟极速的最大值）/ G 值分布与
///   评分分布——两者均为“按行程分档计趟数”，不是逐点分布：
///   G 档按每趟最大合成 G，评分档按每趟评分；赛道行程不评分，
///   不进街道组评分分布。
/// - 赛道组：总圈数（计入圈之和）、最佳圈（全部计入圈的最快）、
///   圈速稳定性（计入圈的总体标准差与极差；计入圈不足 2 圈时
///   为 null，显示“圈数不足，暂无稳定性”）。
/// - 时间范围：全部 / 近 30 天 / 近 90 天 / 自定义区间（左闭右开，
///   按行程开始时间过滤）；自定义区间起止由调用方在界面上选，
///   本文件不猜日期。
/// - 本页不读 store：行程元数据由调用方传入，完整行程（极速 /
///   G / 圈速）由调用方经 loadTrip 回调提供；加载失败的行程跳过，
///   不编数补位。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'card_style.dart';
import 'empty_hud.dart';
import 'models.dart';
import 'store.dart';
import 'track_timing.dart';

/// 分析时间范围。
enum AnalyticsRange { all, last30, last90, custom }

/// 行程是否落在分析区间内（纯函数，可单测）。
/// 区间左闭右开；all 恒 true；last30/last90 按 nowMs 往前推；
/// custom 要求起止都给齐，否则不过滤（返回 true，不静默丢数据）。
bool analyticsTripInRange({
  required int startMs,
  required AnalyticsRange range,
  required int nowMs,
  int? customStartMs,
  int? customEndMs,
}) {
  switch (range) {
    case AnalyticsRange.all:
      return true;
    case AnalyticsRange.last30:
      return startMs >= nowMs - 30 * 24 * 3600 * 1000 && startMs <= nowMs;
    case AnalyticsRange.last90:
      return startMs >= nowMs - 90 * 24 * 3600 * 1000 && startMs <= nowMs;
    case AnalyticsRange.custom:
      if (customStartMs == null || customEndMs == null) return true;
      return startMs >= customStartMs && startMs < customEndMs;
  }
}

/// 分析输入（一趟的聚合值，由调用方从 TripMeta + Trip 拼出，
/// 本文件不读轨迹点、不重算里程）。
class AnalyticsTripInput {
  final String id;
  final TripMode mode;
  final bool isTrackMode;
  final String? trackId;
  final String trackName;
  final int startMs;
  final int endMs;
  final double distanceM;
  final double score;
  final bool demo;
  final double maxSpeedKmh;
  final double maxG;
  final List<int> countedLapDurationsMs;
  const AnalyticsTripInput({
    required this.id,
    required this.mode,
    required this.isTrackMode,
    required this.trackId,
    required this.trackName,
    required this.startMs,
    required this.endMs,
    required this.distanceM,
    required this.score,
    required this.demo,
    required this.maxSpeedKmh,
    required this.maxG,
    required this.countedLapDurationsMs,
  });

  int get durationMs => endMs - startMs;
}

/// 街道组汇总。
class AnalyticsStreetSummary {
  final int tripCount;
  final double totalDistanceKm;
  final int totalDurationMs;
  final double? avgSpeedKmh;
  final double maxSpeedKmh;
  final double maxG;
  final Map<String, int> gBuckets;
  final Map<String, int> scoreBuckets;
  const AnalyticsStreetSummary({
    required this.tripCount,
    required this.totalDistanceKm,
    required this.totalDurationMs,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.maxG,
    required this.gBuckets,
    required this.scoreBuckets,
  });
}

/// 赛道组汇总。
class AnalyticsTrackSummary {
  final int tripCount;
  final int totalLaps;
  final int? bestLapMs;
  final double? meanLapMs;
  final double? stdDevLapMs;
  final int? lapRangeMs;
  const AnalyticsTrackSummary({
    required this.tripCount,
    required this.totalLaps,
    required this.bestLapMs,
    required this.meanLapMs,
    required this.stdDevLapMs,
    required this.lapRangeMs,
  });
  bool get hasStability => totalLaps >= 2 && stdDevLapMs != null;
}

String _gBucket(double maxG) {
  if (maxG < 0.3) return '<0.3g';
  if (maxG < 0.5) return '0.3–0.5g';
  if (maxG < 0.8) return '0.5–0.8g';
  return '≥0.8g';
}

String _scoreBucket(double score) {
  if (score >= 90) return '90+';
  if (score >= 75) return '75–89';
  if (score >= 60) return '60–74';
  return '<60';
}

/// 分组汇总（纯函数，可单测）：演示行程排除；街道组只含非赛道
/// 行程，赛道组只含赛道行程。空输入时两组均为 0 / null，不编数。
({AnalyticsStreetSummary street, AnalyticsTrackSummary track})
    summarizeAnalyticsTrips(List<AnalyticsTripInput> trips) {
  final real = trips.where((t) => !t.demo).toList();
  final streetTrips = real.where((t) => !t.isTrackMode).toList();
  final trackTrips = real.where((t) => t.isTrackMode).toList();

  var distKm = 0.0;
  var durMs = 0;
  var maxSpeed = 0.0;
  var maxG = 0.0;
  final gBuckets = <String, int>{'<0.3g': 0, '0.3–0.5g': 0, '0.5–0.8g': 0, '≥0.8g': 0};
  final scoreBuckets = <String, int>{'90+': 0, '75–89': 0, '60–74': 0, '<60': 0};
  for (final t in streetTrips) {
    distKm += t.distanceM / 1000;
    durMs += t.durationMs;
    if (t.maxSpeedKmh > maxSpeed) maxSpeed = t.maxSpeedKmh;
    if (t.maxG > maxG) maxG = t.maxG;
    gBuckets[_gBucket(t.maxG)] = (gBuckets[_gBucket(t.maxG)] ?? 0) + 1;
    scoreBuckets[_scoreBucket(t.score)] = (scoreBuckets[_scoreBucket(t.score)] ?? 0) + 1;
  }
  final street = AnalyticsStreetSummary(
    tripCount: streetTrips.length,
    totalDistanceKm: distKm,
    totalDurationMs: durMs,
    avgSpeedKmh: durMs > 0 ? distKm / (durMs / 3600000) : null,
    maxSpeedKmh: maxSpeed,
    maxG: maxG,
    gBuckets: gBuckets,
    scoreBuckets: scoreBuckets,
  );

  final laps = <int>[];
  for (final t in trackTrips) {
    laps.addAll(t.countedLapDurationsMs);
  }
  int? best;
  double? mean;
  double? std;
  int? range;
  if (laps.isNotEmpty) {
    best = laps.reduce(math.min);
    mean = laps.reduce((a, b) => a + b) / laps.length;
    if (laps.length >= 2) {
      var sq = 0.0;
      final meanValue = mean;
      for (final l in laps) {
        sq += (l - meanValue) * (l - meanValue);
      }
      std = math.sqrt(sq / laps.length);
      range = laps.reduce(math.max) - laps.reduce(math.min);
    }
  }
  final track = AnalyticsTrackSummary(
    tripCount: trackTrips.length,
    totalLaps: laps.length,
    bestLapMs: best,
    meanLapMs: mean,
    stdDevLapMs: std,
    lapRangeMs: range,
  );
  return (street: street, track: track);
}

/// 行程分析页：范围 chips + 街道组 + 赛道组。
class TripAnalyticsPage extends StatefulWidget {
  final List<TripMeta> metas;
  final Future<Trip?> Function(String id) loadTrip;
  const TripAnalyticsPage({super.key, required this.metas, required this.loadTrip});

  @override
  State<TripAnalyticsPage> createState() => _TripAnalyticsPageState();
}

class _TripAnalyticsPageState extends State<TripAnalyticsPage> {
  List<AnalyticsTripInput>? _inputs;
  int _failedLoads = 0;
  AnalyticsRange _range = AnalyticsRange.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inputs = <AnalyticsTripInput>[];
    var failed = 0;
    for (final m in widget.metas) {
      final t = await widget.loadTrip(m.id);
      if (t == null) {
        failed++;
        continue;
      }
      final laps = t.lapsJson.map((j) => Lap.fromJson(j)).where((l) => l.counted).map((l) => l.durationMs).toList();
      inputs.add(AnalyticsTripInput(
        id: m.id,
        mode: m.mode,
        isTrackMode: m.isTrackMode,
        trackId: m.trackId,
        trackName: m.trackName,
        startMs: m.startMs,
        endMs: m.endMs,
        distanceM: m.distanceM,
        score: m.score,
        demo: m.demo,
        maxSpeedKmh: t.maxSpeed * 3.6,
        maxG: t.maxG,
        countedLapDurationsMs: laps,
      ));
    }
    if (!mounted) return;
    setState(() {
      _inputs = inputs;
      _failedLoads = failed;
    });
  }

  List<AnalyticsTripInput> get _filtered {
    final inputs = _inputs ?? const <AnalyticsTripInput>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    int? cs;
    int? ce;
    if (_customRange != null) {
      cs = _customRange!.start.millisecondsSinceEpoch;
      // 自定义区间按整天计：结束日 +1 天，左闭右开。
      ce = _customRange!.end.add(const Duration(days: 1)).millisecondsSinceEpoch;
    }
    return inputs
        .where((t) => analyticsTripInRange(
            startMs: t.startMs, range: _range, nowMs: now, customStartMs: cs, customEndMs: ce))
        .toList();
  }

  String _fmtDur(S s, int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    if (h > 0) return s.t('$h小时$m分', '${h}h ${m}m');
    return s.t('$m分', '${m}m');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final inputs = _inputs;
    final summary = inputs == null ? null : summarizeAnalyticsTrips(_filtered);
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(s.t('行程分析', 'Trip analysis'))),
      body: inputs == null
          ? Padding(
              padding: EdgeInsets.only(top: appBarTopInset(context)),
              child: const Center(child: CircularProgressIndicator()),
            )
          : ListView(
              padding: withAppBarTopInset(
                  context, EdgeInsets.fromLTRB(16, 12, 16, bottom)),
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _rangeChip(s, AnalyticsRange.all, s.t('全部', 'All')),
                  _rangeChip(s, AnalyticsRange.last30, s.t('近 30 天', '30 days')),
                  _rangeChip(s, AnalyticsRange.last90, s.t('近 90 天', '90 days')),
                  _pill(
                    label: _customRange == null
                        ? s.t('自定义区间', 'Custom')
                        : '${_customRange!.start.month}/${_customRange!.start.day}–${_customRange!.end.month}/${_customRange!.end.day}',
                    selected: _range == AnalyticsRange.custom,
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _customRange,
                        helpText: s.t('选择区间', 'Select range'),
                        cancelText: s.t('取消', 'Cancel'),
                        confirmText: s.t('确定', 'OK'),
                        saveText: s.t('保存', 'Save'),
                      );
                      if (picked == null || !mounted) return;
                      setState(() {
                        _customRange = picked;
                        _range = AnalyticsRange.custom;
                      });
                    },
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  s.t('演示行程不计入；赛道行程只统计圈速。',
                      'Demo trips excluded. Track trips count laps only.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (_failedLoads > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.t('$_failedLoads 趟行程文件未能加载，已跳过',
                        '$_failedLoads trip file(s) failed to load and were skipped'),
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                if (summary == null ||
                    (summary.street.tripCount == 0 && summary.track.tripCount == 0))
                  EmptyHud(
                    icon: Icons.insights,
                    status: s.t('暂无数据', 'No data yet'),
                    actionLabel: s.t('查看全部', 'Show all'),
                    onAction: () => setState(() => _range = AnalyticsRange.all),
                  )
                else ...[
                  _sectionTitle(s.t('街道', 'Street')),
                  DriveTrackCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _row(s.t('行程数', 'Trips'), s.t('${summary.street.tripCount} 趟', '${summary.street.tripCount}')),
                        _row(s.t('总里程', 'Distance'), '${summary.street.totalDistanceKm.toStringAsFixed(1)} km'),
                        _row(s.t('总时长', 'Time'), _fmtDur(s, summary.street.totalDurationMs)),
                        _row(s.t('平均速度', 'Avg speed'),
                            summary.street.avgSpeedKmh == null ? s.t('暂无', '—') : '${summary.street.avgSpeedKmh!.toStringAsFixed(1)} km/h'),
                        _row(s.t('极速', 'Top speed'), '${summary.street.maxSpeedKmh.toStringAsFixed(0)} km/h'),
                        _row(s.t('最大合成 G', 'Peak G'), '${summary.street.maxG.toStringAsFixed(2)}g'),
                        const SizedBox(height: 8),
                        Text(s.t('G 值分布（单位：趟）', 'G spread (trips)'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        for (final e in summary.street.gBuckets.entries) _row(e.key, '${e.value}'),
                        const SizedBox(height: 6),
                        Text(s.t('评分分布（单位：趟）', 'Score spread (trips)'),
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        for (final e in summary.street.scoreBuckets.entries) _row(e.key, '${e.value}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(s.t('赛道', 'Track')),
                  DriveTrackCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _row(s.t('赛道行程数', 'Track trips'), s.t('${summary.track.tripCount} 趟', '${summary.track.tripCount}')),
                        _row(s.t('总圈数（计入圈）', 'Counted laps'), s.t('${summary.track.totalLaps} 圈', '${summary.track.totalLaps}')),
                        _row(s.t('最佳圈', 'Best lap'),
                            summary.track.bestLapMs == null ? s.t('暂无圈速', 'No lap') : LapTimer.formatLapTime(summary.track.bestLapMs)),
                        _row(s.t('平均圈速', 'Avg lap'),
                            summary.track.meanLapMs == null ? s.t('暂无圈速', 'No lap') : LapTimer.formatLapTime(summary.track.meanLapMs!.round())),
                        _row(s.t('圈速稳定性（标准差）', 'Lap consistency (SD)'),
                            summary.track.hasStability
                                ? s.t('${(summary.track.stdDevLapMs! / 1000).toStringAsFixed(3)} 秒',
                                    '${(summary.track.stdDevLapMs! / 1000).toStringAsFixed(3)} s')
                                : s.t('圈数不足，暂无稳定性', 'Need more laps')),
                        if (summary.track.hasStability)
                          _row(s.t('圈速极差', 'Lap spread'), LapTimer.formatLapTime(summary.track.lapRangeMs)),
                        const SizedBox(height: 6),
                        Text(s.t('无效圈不进统计。', 'Invalid laps are excluded.'),
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _rangeChip(S s, AnalyticsRange r, String label) => _pill(
        label: label,
        selected: _range == r,
        onTap: () => setState(() => _range = r),
      );

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = CardStyle.accent(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.black54,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? accent : CardStyle.borderColor),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      );
}
