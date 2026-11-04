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

import 'package:flutter/material.dart';

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

  /// 分段标签；默认 S1/S2/S3。扇区待核的赛道调用方应传
  /// [] 或通用标签并配 [sectorSourceNote]，不得硬标 S1/S2/S3。
  final List<String> sectorLabels;

  /// 上一圈圈速（ms）；无上一圈时为 null，显示占位。
  final int? lastLapMs;

  /// 最佳圈圈速（ms，本节最佳圈）；无时为 null，显示占位。
  final int? bestLapMs;

  /// 预测圈圈速（ms）；调用方按“已跑部分 + 参照圈剩余分段”算好
  /// 传入，本 widget 不反推；无时为 null，显示占位。
  final int? predictedLapMs;

  /// 参照圈说明；默认“参照圈：本节最佳圈”。
  final String referenceNote;

  /// 扇区来源说明：如“估算分段”“扇区待核”；为 null 时不显示该行。
  /// 调用方应从 TrackSectorData.sourceLabel / note 取值传入。
  final String? sectorSourceNote;

  /// 是否因停车处于自动暂停中；为 true 时显示暂停提示行。
  final bool isPaused;

  const TrackSessionDisplay({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.sectorDeltasMs,
    this.sectorLabels = const ['S1', 'S2', 'S3'],
    required this.lastLapMs,
    required this.bestLapMs,
    required this.predictedLapMs,
    this.referenceNote = '参照圈：本节最佳圈',
    this.sectorSourceNote,
    this.isPaused = false,
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
          // 大数字当前圈计时（方案 A 的地图区替代主体）。
          Text(
            LapTimer.formatLapTime(currentLapMs),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isPaused)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '已自动暂停：停车超 30 秒，暂停时长不计入圈速',
                style: TextStyle(color: _kRed, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          // 一行分段色块：格里写带正负号的 delta 数字。
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
                                i < sectorDeltasMs.length
                                    ? sectorDeltasMs[i]
                                    : null)
                            .withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sectorDeltaColor(
                              i < sectorDeltasMs.length
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
                            i < sectorDeltasMs.length
                                ? LapTimer.formatDelta(sectorDeltasMs[i])
                                : '--',
                            style: TextStyle(
                              color: sectorDeltaColor(
                                  i < sectorDeltasMs.length
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
          // 下方小字：上一圈、最佳圈、预测圈。
          Row(
            children: [
              Expanded(
                child: _smallStat(
                    '上一圈', LapTimer.formatLapTime(lastLapMs)),
              ),
              Expanded(
                child: _smallStat(
                    '最佳圈', LapTimer.formatLapTime(bestLapMs)),
              ),
              Expanded(
                child: _smallStat(
                    '预测圈', LapTimer.formatLapTime(predictedLapMs)),
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
