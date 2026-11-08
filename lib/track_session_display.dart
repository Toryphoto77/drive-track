/// v1.2.0 第 6 项：赛中显示方案 A（新增文件，不改动已有文件）。
///
/// 用户定版方案 A，严格执行：
/// - 地图区不再显示地图：本 widget 不含任何地图，只显示大数字当前圈
///   计时 + 一行分段色块，下方小字给上一圈、最佳圈、预测圈。
/// - 分段色块规则（与赛中同色，分析页分段对比表复用同一规则）：
///   delta < 0（比参照圈快）= 绿，delta > 0（比参照圈慢）= 红，
///   delta == 0 = 灰（持平）。格里写 delta 本身，保持正负号数字，
///   绝不改成中文“快/慢”。
/// - 参照圈默认本节最佳圈：[sectorDeltasMs] 与 [bestLapMs] 的参照圈
///   口径均为本节最佳圈（调用方用 LapTimer.bestLap / sessionBestLap
///   算好传入）；[referenceNote] 默认文案即“参照圈：本节最佳圈”。
/// - 未完成分段：对应位置显示 '--'（灰框），不补 0、不冒充已完成。
/// - 赛道模式不评分：本 widget 不显示任何评分。
/// - 本 widget 不做计时、不算 delta、不碰 GPS：全部输入由调用方
///   （收口接线方）从 LapTimer / 轨迹算好传入，接线时只替换录制页
///   的地图区即可。
///
/// 职业赛道面板布局（用户 2026-11-04 定，参考专业赛道软件的
/// 信息架构，不照搬皮肤）：
/// - 主角是当前圈大计时，其下是大的实时 Delta 数字 + 一条细的红绿
///   Delta 条；分段行每段给分段用时 + Delta，当前段高亮；目标行
///   并排预测圈 / 最佳圈 / 理论最优（理论最优 = 各段历史最快相加，
///   调用方用 track_sector_data.dart 的 theoreticalBestLapMs 算；
///   标签写“理论最优”不写“最优圈”，与实测最佳圈区分，不得混淆）。
/// - 诚实口径（绝不冒充）：
///   实时 Delta 是分段级的：[liveDeltaMs] = 预测圈 - 最佳圈，即已
///   完成分段 delta 之和，只在分段点触发时变化，不是基于距离的
///   连续 Delta；计时器未配置真实扇区点时调用方传 null，显示
///   '--'。绝不拿“当前圈已用 - 最佳圈总时长”冒充——开圈不久时
///   那个数恒为很大的负值，会误导。
///   最优圈只认调用方算好的值；无计入圈或分段数据不足时为 null，
///   显示占位，不拼假圈。
///
/// 大计时显示刷新（用户 2026-11-04 反馈“数字根本不滚动”后的修复）：
/// 大数字不用父级重建驱动，改由 [LiveLapTimeText] 的独立 vsync
/// Ticker 按屏幕刷新率插值刷新，只重建大数字本身；锚点仍是调用方
/// 传入的权威 currentLapMs，暂停/完成一圈/新 GPS 点到达时的行为
/// 见 live_lap_timer_text.dart。分段格与 Delta 是分段级数据，
/// 本来就只在分段点触发时变化，不走 ticker。

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'live_lap_timer_text.dart';

import 'track_live_g.dart';
import 'track_timing.dart';

const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);
const Color _kGreen = Color(0xFF22C55E);
const Color _kRed = Color(0xFFE10600);
const Color _kGray = Color(0xFF9CA3AF);

/// 分段 delta 着色（纯函数，与分析页共用）：
/// 负 = 更快（绿），正 = 更慢（红），0 或 null = 灰（持平/未完成）。
Color sectorDeltaColor(int? deltaMs) {
  if (deltaMs == null || deltaMs == 0) return _kGray;
  return deltaMs < 0 ? _kGreen : _kRed;
}

/// 实时 Delta（ms，分段级，纯函数）：预测圈 - 最佳圈，即已完成
/// 分段 delta 之和。仅当计时器配置了真实扇区点时有效；无扇区点
/// 时返回 null（调用方显示 '--'），因为此时预测圈恒等于最佳圈、
/// 算出的 0 只是“尚无偏差数据”，不是“正好跑在最佳节奏上”。
int? liveDeltaMsFor({
  required int? predictedLapMs,
  required int? bestLapMs,
  required bool hasSectorPoints,
}) {
  if (!hasSectorPoints || predictedLapMs == null || bestLapMs == null) {
    return null;
  }
  return predictedLapMs - bestLapMs;
}

/// Delta 指示条填充比例（0~1，纯函数，可单测）：
/// 对数缩放口径（v1.2.15，由线性 10 秒满格改为对数，理由如下）：
/// - 分段级 Delta 的典型量级是几百毫秒：线性 10 秒满格下 500ms
///   只占半条的 5%，余光根本看不见，条形同虚设；
/// - 对数缩放让小 Delta 可见，同时不让小 Delta 看起来像大 Delta：
///   刻度是 ln(1 + |d| / τ) / ln(1 + 满格 / τ)，τ = 500ms、满格
///   = 10000ms：100ms → 0.06、500ms → 0.23、1s → 0.36、2s → 0.53、
///   5s → 0.79、10s → 1.0（≥ 10s 钳制到满格）。小 Delta 始终只占
///   条的一小截，大失误才顶满，两者量级一眼可分；
/// - 条只作方向与量级提示：精确值以条上方的 Delta 数字为准，
///   不得只看条读数。null 或 0 时返回 0，只画底条与中心刻度。
double deltaBarFraction(int? deltaMs) {
  if (deltaMs == null || deltaMs == 0) return 0;
  const tauMs = 500.0;
  const fullScaleMs = 10000.0;
  final frac = math.log(1 + deltaMs.abs() / tauMs) /
      math.log(1 + fullScaleMs / tauMs);
  return frac.clamp(0.0, 1.0);
}

/// 细的红绿 Delta 条：中心为 0，左红（比参照慢）、右绿（比参照快）。
/// 填充幅度见 [deltaBarFraction]（对数缩放，τ = 500ms、满格 10s）；
/// null 或 0 时只画底条与中心刻度。
class _DeltaBar extends StatelessWidget {
  final int? deltaMs;
  const _DeltaBar(this.deltaMs);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final d = deltaMs;
      final frac = deltaBarFraction(d);
      final half = w / 2;
      final fillW = half * frac;
      return SizedBox(
        height: 6,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (d != null && d < 0)
            Positioned(
              left: half,
              top: 0,
              bottom: 0,
              width: fillW,
              child: Container(
                decoration: BoxDecoration(
                  color: _kGreen,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          if (d != null && d > 0)
            Positioned(
              left: half - fillW,
              top: 0,
              bottom: 0,
              width: fillW,
              child: Container(
                decoration: BoxDecoration(
                  color: _kRed,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          Positioned(
            left: half - 1,
            top: 0,
            bottom: 0,
            width: 2,
            child: Container(color: Colors.white38),
          ),
        ]),
      );
    });
  }
}

/// 赛中显示方案 A：可直接嵌入录制页、替换原地图区的 widget。
class TrackSessionDisplay extends StatelessWidget {
  /// 当前圈号；0 表示还在发车圈（未第一次穿越起终点）。
  final int currentLapNumber;

  /// 当前圈已用时长（ms，已扣除暂停时长）；未开始计时时为 null。
  final int? currentLapMs;

  /// 已完成分段的 delta 列表（ms，相对参照圈本节最佳圈）：
  /// 第 i 项对应第 i 段；未完成的分段传 null 或直接缺失（按
  /// [sectorLabels] 长度补灰框）。负 = 更快，0 = 持平，正 = 更慢。
  final List<int?> sectorDeltasMs;

  /// 已完成分段的绝对用时（ms），第 i 项对应第 i 段；未完成分段
  /// 不在列表里（按 [sectorLabels] 长度补 '--'）。与 [sectorDeltasMs]
  /// 下标口径一致，均来自 LapTimer.currentCompletedSectorsMs。
  final List<int> sectorTimesMs;

  /// 当前正在跑的分段下标（0 起）；无真实扇区点、或无法确定时为
  /// null（不做高亮，不猜当前段）。
  final int? currentSectorIndex;

  /// 实时 Delta（ms，分段级，见 [liveDeltaMsFor]）；为 null 时显示
  /// '--'，不冒充连续 Delta。
  final int? liveDeltaMs;

  /// 是否显示 Delta（实时 Delta 数字/条 + 分段格的 delta 行）：
  /// 关掉时分段格只显示绝对分段用时，实时 Delta 显示 '--'、
  /// Delta 条只画底条。对应赛道设置页“显示 Delta”开关
  /// （专业软件“相对时间/绝对时间”切换的同款机制），默认 true。
  final bool showDelta;

  /// 分段标签；默认 S1/S2/S3。扇区待核的赛道调用方应传
  /// [] 或通用标签并配 [sectorSourceNote]，不得硬标 S1/S2/S3。
  final List<String> sectorLabels;

  /// 最佳圈圈速（ms，本节最佳圈）；无时为 null，显示占位。
  final int? bestLapMs;

  /// 预测圈圈速（ms）；调用方按“已跑部分 + 参照圈剩余分段”算好
  /// 传入，本 widget 不反推；无时为 null，显示占位。
  final int? predictedLapMs;

  /// 最优圈圈速（ms）= 各段历史最快相加；调用方用
  /// theoreticalBestLapMs 算好传入，无数据时为 null，显示占位。
  /// 界面标签为“理论最优”，与实测最佳圈区分，不得只写“最优圈”。
  final int? optimalLapMs;

  /// 参照圈说明；默认“参照圈：本节最佳圈”。
  final String referenceNote;

  /// 扇区来源说明：如“估算分段”“扇区待核”；为 null 时不显示该行。
  /// 调用方应从 TrackSectorData.sourceLabel / note 取值传入。
  final String? sectorSourceNote;

  /// 是否因停车处于自动暂停中；为 true 时显示暂停提示行。
  final bool isPaused;

  /// 大计时是否为直播显示；为 true 时大数字走独立 ticker 插值
  /// 刷新（见 live_lap_timer_text.dart），缺省 false 即静态显示。
  final bool timerLive;

  /// 大计时是否暂停（调用方须把 LapTimer 自动暂停与记录手动
  /// 暂停合并后传入）；为 true 时 ticker 停走、显示冻结。
  final bool timerPaused;

  /// 实时 G 值数据源（可选，见 track_live_g.dart 的 [LiveGSource]）。
  /// 接线时调用方应传 Recorder（listenable）+ smoothLong/smoothLat
  /// + tripPeakLong/tripPeakLat + calibrated；为 null 时 G 值行整
  /// 行不显示，面板其余部分完全不变。G 值行内部用 ListenableBuilder
  /// 只重建自身，不重建整个面板、不干扰大计时 ticker。
  final LiveGSource? liveGSource;

  const TrackSessionDisplay({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.sectorDeltasMs,
    this.sectorTimesMs = const [],
    this.currentSectorIndex,
    this.liveDeltaMs,
    this.showDelta = true,
    this.sectorLabels = const ['S1', 'S2', 'S3'],
    required this.bestLapMs,
    required this.predictedLapMs,
    this.optimalLapMs,
    this.referenceNote = '参照圈：本节最佳圈',
    this.sectorSourceNote,
    this.isPaused = false,
    this.timerLive = false,
    this.timerPaused = false,
    this.liveGSource,
  });

  @override
  Widget build(BuildContext context) {
    final labels = sectorLabels;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentLapNumber <= 0
                ? '发车圈'
                : '当前圈 · 第 $currentLapNumber 圈',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 2),
          // 大数字当前圈计时（方案 A 的地图区替代主体）：整串一个
          // 纯 Text 原地换字，所有字符共用同一基线，不做任何竖直
          // 位移（旧竖条切片法会因行高对不上而上下错位，已弃用）；
          // 刷新节奏由独立 ticker 插值驱动，不再依赖 GPS 点到达才刷新。
          // M1：大计时包一层 scaleDown，系统大字体下窄屏也不溢出。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: LiveLapTimeText(
              anchorMs: currentLapMs,
              lapNumber: currentLapNumber,
              paused: timerPaused,
              live: timerLive,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (isPaused)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '已自动暂停，暂停时长不计入圈速',
                style: TextStyle(color: _kRed, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          // 职业面板主角之二：大的实时 Delta 数字 + 细的红绿 Delta 条。
          // Delta 为分段级（见 liveDeltaMsFor），无扇区点时为 '--'。
          // 横屏窄栏：Delta 数字 28 号（"-0:00.170" 9 字）在 310 宽
          // 下会溢出，与大计时同款处理——包 Flexible + scaleDown，
          // 极窄/大字体时数字等比缩小不断行、不溢出。
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '实时 Delta',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    LapTimer.formatDelta(showDelta ? liveDeltaMs : null),
                    style: TextStyle(
                      color: sectorDeltaColor(showDelta ? liveDeltaMs : null),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _DeltaBar(showDelta ? liveDeltaMs : null),
          const SizedBox(height: 10),
          // 实时 G 值行（G 圆 + 纵向/横向数值 + 本节峰值）：放在主角
          // 区（大计时 + Delta）下方、分段块上方，驾驶中一抬眼就能
          // 看到；不传 liveGSource 时整行不显示。
          if (liveGSource != null) ...[
            TrackLiveGRow(source: liveGSource!),
            const SizedBox(height: 10),
          ],
          // 一行分段色块：每段给分段用时 + 带正负号的 delta 数字；
          // 当前跑的段白边高亮；未完成分段两项均为 '--'，不补数。
          if (labels.isEmpty)
            const Text(
              '分段：扇区待核',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            )
          else
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(
                          right: i == labels.length - 1 ? 0 : 6),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: sectorDeltaColor(
                                showDelta && i < sectorDeltasMs.length
                                    ? sectorDeltasMs[i]
                                    : null)
                            .withValues(
                                alpha: currentSectorIndex == i
                                    ? 0.30
                                    : 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: currentSectorIndex == i
                              ? Colors.white
                              : sectorDeltaColor(
                                  showDelta && i < sectorDeltasMs.length
                                      ? sectorDeltasMs[i]
                                      : null),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            labels[i],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            i < sectorTimesMs.length
                                ? LapTimer.formatLapTime(sectorTimesMs[i])
                                : '--',
                            style: TextStyle(
                              color: i < sectorTimesMs.length
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            showDelta && i < sectorDeltasMs.length
                                ? LapTimer.formatDelta(sectorDeltasMs[i])
                                : '--',
                            style: TextStyle(
                              color: sectorDeltaColor(
                                  showDelta && i < sectorDeltasMs.length
                                      ? sectorDeltasMs[i]
                                      : null),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          // 目标行：预测圈、最佳圈、理论最优（上一圈已在下方圈速列表
          // 最新一行，不在这里重复占位）。
          Row(
            children: [
              Expanded(
                child: _smallStat(
                    '预测圈', LapTimer.formatLapTime(predictedLapMs)),
              ),
              Expanded(
                child: _smallStat(
                    '最佳圈', LapTimer.formatLapTime(bestLapMs)),
              ),
              Expanded(
                child: _smallStat(
                    '理论最优', LapTimer.formatLapTime(optimalLapMs)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            referenceNote,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (sectorSourceNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sectorSourceNote!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// v1.2.17 赛道页：段速 + 到下一计时线距离行（放在 TrackSessionDisplay
/// 下方，赛道页内）。
///
/// - 段速：调用方传计时器 [LapTimer.sectorSpeeds]（与分段标签等长，
///   只取 GPS 实测点；未开始的段为 null）。有真实分段点时每段显示
///   “Si 最低–最高”（km/h，取整）；某段为 null 时该段显示“Si --”。
///   无真实分段点时整段只显示占位“段速 --”，不编数。
/// - 到下一计时线距离：取计时器 [LapTimer.nextLineDistanceM]（沿中心线
///   到下一边界点的米数）；有值时显示“距下一计时线 XXX m”，为 null
///   时该段不显示、不编数。
/// - 本 widget 不做计时、不算速度、不碰 GPS：全部输入由调用方从
///   LapTimer 算好传入。
class TrackSectorSpeedRow extends StatelessWidget {
  /// 每段段内速度（最低/最高 km/h），与 [sectorLabels] 等长；
  /// 未开始的段为 null。
  final List<SectorSpeed?> sectorSpeeds;

  /// 分段标签；默认 S1/S2/S3。
  final List<String> sectorLabels;

  /// 计时器是否有真实分段点；为 false 时只显示占位“段速 --”。
  final bool hasSectorPoints;

  /// 沿中心线到下一计时线边界点的距离（米）；无中心线或无边界点
  /// 时为 null，该段不显示。
  final double? nextLineDistanceM;

  const TrackSectorSpeedRow({
    super.key,
    required this.sectorSpeeds,
    this.sectorLabels = const ['S1', 'S2', 'S3'],
    required this.hasSectorPoints,
    this.nextLineDistanceM,
  });

  @override
  Widget build(BuildContext context) {
    final speedText = hasSectorPoints
        ? [
            for (var i = 0; i < sectorLabels.length; i++)
              i < sectorSpeeds.length && sectorSpeeds[i] != null
                  ? '${sectorLabels[i]} ${sectorSpeeds[i]!.minKmh.toStringAsFixed(0)}–${sectorSpeeds[i]!.maxKmh.toStringAsFixed(0)}'
                  : '${sectorLabels[i]} --',
          ].join(' · ')
        : '段速 --';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              speedText,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (nextLineDistanceM != null) ...[
            const SizedBox(width: 8),
            Text(
              '距下一计时线 ${nextLineDistanceM!.toStringAsFixed(0)} m',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}
