/// 赛道可视化组件（v0.1.4 新文件，不改动已有文件）。
///
/// 分段着色规则（F1 惯例，组件内小字注明，绝不写反）：
/// - 紫 = 全场最快分段：该段用时等于本次行程所有计入圈里该段的最快用时；
/// - 绿 = 个人最快分段：该段用时等于调用方传入的该段个人最好用时，
///   且不是全场最快（紫优先于绿）；
/// - 黄 = 慢于个人最快：既不是全场最快，也慢于个人最好用时。
/// 本地单人场景说明：App 是本机存储、没有其他车手，TripMeta 里也不存
/// 跨行程分段历史（见 store.dart），所以调用方若只拿本行程的圈算
/// personalBestMs，它会等于 sessionBestMs，绿永远被紫优先覆盖——
/// 这是数据口径所致，不是着色写反。调用方如有跨行程个人最好成绩，
/// 传入不同的 personalBestMs 即可让绿正常出现；缺省时 personalBestMs
/// 不传，组件按 sessionBestMs 计，绿不出现也不冒充。
/// Delta：负为更快（绿字），正为更慢（红字），一律带 +/- 号，
/// 格式化复用 LapTimer.formatDelta。
/// 分段退化：Lap.sectorsMs 只有 2 段且调用方声明无分段点
/// （[hasSectorPoints] == false）时，标签为“前半圈 / 后半圈”并注明
/// “无分段点，前后半圈示意”，绝不标成 S1/S2/S3；有分段点时
/// 2 段标 S1/S2，3 段标 S1/S2/S3。段数既不是 2 也不是 3 时显示“暂无”。
/// 每段速度趋势：Lap 里没有分段速度字段（只有分段用时），所以
/// 段平均速度与个人最好成绩必须由调用方以 [SegmentSpeed] 传入，
/// 本文件不从圈速反推速度、不编造。

import 'package:flutter/material.dart';

import 'track_catalog.dart';
import 'track_timing.dart';

const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);
const Color _kRed = Color(0xFFE10600);
const Color _kPurple = Color(0xFFA855F7); // 全场最快
const Color _kGreen = Color(0xFF22C55E); // 个人最快 / Delta 更快
const Color _kYellow = Color(0xFFEAB308); // 慢于个人最快

/// 一段的分段用时与参照最好成绩（全部 ms，调用方算好传入）。
class SectorTime {
  /// 分段用时（ms）。
  final int durationMs;

  /// 本次行程所有计入圈里该段的最快用时（ms）；为 null 时不判紫。
  final int? sessionBestMs;

  /// 该段个人最好用时（ms）；为 null 时默认等于 sessionBestMs。
  final int? personalBestMs;

  const SectorTime({
    required this.durationMs,
    this.sessionBestMs,
    this.personalBestMs,
  });
}

/// 分段着色结果（纯函数，可单测）。
enum SectorPace { overallFastest, personalFastest, slower }

SectorPace sectorPaceOf(SectorTime s) {
  final personal = s.personalBestMs ?? s.sessionBestMs;
  if (s.sessionBestMs != null && s.durationMs <= s.sessionBestMs! + 1) {
    return SectorPace.overallFastest;
  }
  if (personal != null && s.durationMs <= personal + 1) {
    return SectorPace.personalFastest;
  }
  return SectorPace.slower;
}

Color sectorPaceColor(SectorPace p) => switch (p) {
      SectorPace.overallFastest => _kPurple,
      SectorPace.personalFastest => _kGreen,
      SectorPace.slower => _kYellow,
    };

String sectorPaceLabel(SectorPace p) => switch (p) {
      SectorPace.overallFastest => '全场最快',
      SectorPace.personalFastest => '个人最快',
      SectorPace.slower => '慢于个人最快',
    };

/// 按赛道目录的分段点生成分段标签：与 TrackInfo.sectorLabels 同口径，
/// 调用方应优先用它（而非手写段数），保证分段着色条与赛道详情页的
/// 分段说明一致；目录无分段点时返回前后半圈，不冒充 S1/S2/S3。
List<String> trackSectorLabels(TrackInfo track) => track.sectorLabels;

/// 根据段数与有无分段点生成分段标签；段数非法时返回空列表
/// （调用方据此显示“暂无”，不要硬标 S1/S2/S3）。
List<String> sectorLabels(int count, bool hasSectorPoints) {
  if (count == 3) return const ['S1', 'S2', 'S3'];
  if (count == 2) {
    return hasSectorPoints ? const ['S1', 'S2'] : const ['前半圈', '后半圈'];
  }
  return const [];
}

/// 一段的速度趋势（调用方传入，不由圈速反推）。
class SegmentSpeed {
  /// 分段标签（如 S1 / 前半圈，调用方与分段标签保持一致）。
  final String label;

  /// 本圈该段平均速度（km/h）。
  final double avgSpeedKmh;

  /// 该段个人最好平均速度（km/h）；为 null 时不画最好成绩标记。
  final double? bestSpeedKmh;

  const SegmentSpeed({
    required this.label,
    required this.avgSpeedKmh,
    this.bestSpeedKmh,
  });
}

Widget _card({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _kBorder),
    ),
    child: child,
  );
}

const Widget _emptyNote =
    Text('暂无', style: TextStyle(color: Colors.white54, fontSize: 13));

/// 大号当前圈 / 最快圈显示 + Delta 正负读数。
/// [currentLapMs] 为 null 时当前圈显示占位；[bestLap] 为 null 时最快圈
/// 显示占位；[deltaMs] 为 null 时 Delta 显示 '--'。
class CurrentAndBestLapCard extends StatelessWidget {
  final int currentLapNumber;
  final int? currentLapMs;
  final Lap? bestLap;
  final int? deltaMs;
  final bool isPaused;

  const CurrentAndBestLapCard({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.bestLap,
    required this.deltaMs,
    this.isPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  currentLapNumber <= 0
                      ? '发车圈'
                      : '当前圈 · 第 $currentLapNumber 圈',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 2),
              Text(LapTimer.formatLapTime(currentLapMs),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('最快圈',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
                bestLap == null
                    ? '--:--.---'
                    : LapTimer.formatLapTime(bestLap!.durationMs),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            DeltaReadout(deltaMs: deltaMs),
          ]),
        ]),
        if (isPaused)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('已自动暂停，暂停时长不计入圈速',
                style: TextStyle(color: _kRed, fontSize: 12)),
          ),
      ]),
    );
  }
}

/// Delta 正负读数：负为更快（绿），正为更慢（红），带 +/- 号。
class DeltaReadout extends StatelessWidget {
  final int? deltaMs;
  const DeltaReadout({super.key, required this.deltaMs});

  @override
  Widget build(BuildContext context) {
    final d = deltaMs;
    final color = d == null ? Colors.white : (d < 0 ? _kGreen : _kRed);
    return Text(
      LapTimer.formatDelta(d),
      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

/// 分段着色条：每段一块，按紫 / 绿 / 黄着色并标用时与规则小字。
/// [sectors] 长度非法（非 2 / 3）时显示“暂无”，不冒充分段。
class SectorColorBar extends StatelessWidget {
  final List<SectorTime> sectors;
  final bool hasSectorPoints;

  const SectorColorBar({
    super.key,
    required this.sectors,
    required this.hasSectorPoints,
  });

  @override
  Widget build(BuildContext context) {
    final labels = sectorLabels(sectors.length, hasSectorPoints);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('分段',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (labels.isEmpty)
          _emptyNote
        else ...[
          Row(children: [
            for (var i = 0; i < sectors.length; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                      right: i == sectors.length - 1 ? 0 : 6),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: sectorPaceColor(sectorPaceOf(sectors[i]))
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: sectorPaceColor(sectorPaceOf(sectors[i]))),
                  ),
                  child: Column(children: [
                    Text(labels[i],
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(LapTimer.formatLapTime(sectors[i].durationMs),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    Text(sectorPaceLabel(sectorPaceOf(sectors[i])),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          const Text('紫=全场最快分段 · 绿=个人最快分段 · 黄=慢于个人最快',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          if (!hasSectorPoints && sectors.length == 2)
            const Text('无分段点，前后半圈示意',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ]),
    );
  }
}

/// 每段速度趋势小图：每段一条平均速度条 + 个人最好成绩刻度线；
/// 平均速度高于最好成绩时条为绿色，否则为白色；无数据时显示“暂无”。
class SegmentSpeedTrend extends StatelessWidget {
  final List<SegmentSpeed> segments;
  const SegmentSpeedTrend({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('每段速度趋势',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (segments.isEmpty)
          _emptyNote
        else
          for (final s in segments) _row(s),
        const SizedBox(height: 6),
        const Text('条为本圈段平均速度，竖线为该段个人最好平均速度',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    );
  }

  Widget _row(SegmentSpeed s) {
    final scale = (s.bestSpeedKmh != null && s.bestSpeedKmh! > 0)
        ? (s.avgSpeedKmh > s.bestSpeedKmh! ? s.avgSpeedKmh : s.bestSpeedKmh!)
        : (s.avgSpeedKmh > 0 ? s.avgSpeedKmh : 1);
    final frac = (s.avgSpeedKmh / scale).clamp(0.0, 1.0);
    final bestFrac = s.bestSpeedKmh == null
        ? null
        : (s.bestSpeedKmh! / scale).clamp(0.0, 1.0);
    final beatsBest =
        s.bestSpeedKmh != null && s.avgSpeedKmh >= s.bestSpeedKmh!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Text(s.label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            return Stack(children: [
              Container(
                  height: 14,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7))),
              FractionallySizedBox(
                widthFactor: frac,
                child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: beatsBest ? _kGreen : Colors.white70,
                        borderRadius: BorderRadius.circular(7))),
              ),
              if (bestFrac != null)
                Positioned(
                  left: bestFrac * c.maxWidth - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: _kRed),
                ),
            ]);
          }),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 118,
          child: Text(
              '${s.avgSpeedKmh.toStringAsFixed(0)} km/h'
              '${s.bestSpeedKmh == null ? '' : ' / 最好 ${s.bestSpeedKmh!.toStringAsFixed(0)}'}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ]),
    );
  }
}

/// 赛道可视化组合卡：大号当前圈 / 最快圈 + Delta + 分段着色 + 速度趋势。
/// [sectors] 为当前圈（或上一圈）的分段用时，调用方从 Lap.sectorsMs
/// 转成 SectorTime（并算好各段 sessionBest / personalBest）后传入；
/// [segmentSpeeds] 为空时速度趋势区显示“暂无”，不反推。
class TrackVizSection extends StatelessWidget {
  final int currentLapNumber;
  final int? currentLapMs;
  final Lap? bestLap;
  final int? deltaMs;
  final bool isPaused;
  final List<SectorTime> sectors;
  final bool hasSectorPoints;
  final List<SegmentSpeed> segmentSpeeds;

  const TrackVizSection({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.bestLap,
    required this.deltaMs,
    this.isPaused = false,
    required this.sectors,
    required this.hasSectorPoints,
    this.segmentSpeeds = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      CurrentAndBestLapCard(
        currentLapNumber: currentLapNumber,
        currentLapMs: currentLapMs,
        bestLap: bestLap,
        deltaMs: deltaMs,
        isPaused: isPaused,
      ),
      const SizedBox(height: 12),
      SectorColorBar(sectors: sectors, hasSectorPoints: hasSectorPoints),
      const SizedBox(height: 12),
      SegmentSpeedTrend(segments: segmentSpeeds),
    ]);
  }
}
