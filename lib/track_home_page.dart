/// v1.2.1：赛道专门入口页（新建）。
///
/// 赛道相关的信息全部收进这一个页面，记录页只留一个醒目的
/// “赛道”入口跳过来，不再把赛道卡片、赛道分析、赛道库散落
/// 在记录页各处；左抽屉的赛道库入口直推库页，本页的库按钮亦然。
///
/// 内容：
/// - 我的赛道行程列表：按赛道分组，每组含该赛道的最佳圈
///   （组内各行程最佳圈的最小值；无计入圈时写“暂无圈速”，不编数）。
/// - 赛道库入口、赛道分析入口（最新赛道行程分析；点组内
///   某条行程进该行程的赛道分析页，即赛道结束页）。
/// - 赛道模式说明（含 OBD 未连接提示与扇区诚实口径）。
///
/// 数据口径：
/// - 演示行程不进本页：调用方传入的 metas 应已排除 demo，
///   本页再按 isTrackMode 过滤一次，双保险；演示行程不计入
///   任何一组的最佳圈与行程数。
/// - 扇区口径：官方扇区 0 条可核实（track_sector_data.dart 文件头：
///   本轮 21 条全部空缺）；估算的标“估算分段”、待核的标“扇区待核”，
///   绝不冒充官方。赛道行程不评分。

import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'models.dart';
import 'store.dart';
import 'track_analysis_page.dart';
import 'track_library_page.dart';
import 'track_sector_data.dart';
import 'track_timing.dart';

const Color _kBg = Color(0xFF121212);
const Color _kCard = Color(0xFF1E1E1E);
const Color _kBorder = Color(0xFFFFFFFF);
const Color _kRed = Color(0xFFE10600);

/// 赛道页。
class TrackHomePage extends StatelessWidget {
  /// 全部行程索引（调用方已排除演示行程；本页仍按 demo 再过滤一次）。
  final List<TripMeta> metas;

  /// 行程 id → 该行程最佳圈（毫秒；null = 无计入圈），由调用方
  /// 的 _refreshTrackBestLaps 维护，加载中/无圈时均为 null。
  final Map<String, int?> bestLapMsByTripId;

  /// 按行程 id 加载完整 Trip（用于进赛道分析页与从行程导入赛道）。
  final Future<Trip?> Function(String tripId) loadTrip;

  const TrackHomePage({
    super.key,
    required this.metas,
    required this.bestLapMsByTripId,
    required this.loadTrip,
  });

  List<TripMeta> get _trackTrips {
    final list = metas.where((m) => m.isTrackMode && !m.demo).toList()
      ..sort((a, b) => b.startMs.compareTo(a.startMs));
    return list;
  }

  Future<void> _openTripAnalysis(BuildContext context, TripMeta m) async {
    final trip = await loadTrip(m.id);
    if (!context.mounted) return;
    if (trip == null) {
      showAppNotice(context, '行程文件读取失败，请重试', AppNoticeKind.error);
      return;
    }
    final laps = trip.lapsJson.map((j) => Lap.fromJson(j)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackAnalysisPage(trip: trip, laps: laps),
      ),
    );
  }

  void _openLibrary(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackLibraryPage(metas: metas, loadTrip: loadTrip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackTrips = _trackTrips;
    // 按赛道分组：key 为 trackId（无 id 时按赛道名兜底）。
    final groups = <String, List<TripMeta>>{};
    for (final m in trackTrips) {
      final key = (m.trackId != null && m.trackId!.isNotEmpty)
          ? m.trackId!
          : m.trackName;
      (groups[key] ??= []).add(m);
    }
    final groupKeys = groups.keys.toList()
      ..sort(
        (a, b) => groups[b]!.first.startMs.compareTo(groups[a]!.first.startMs),
      );

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(title: const Text('赛道'), backgroundColor: _kBg),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 入口区：图鉴 + 分析，两个入口都在本页，不再散落记录页。
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '赛道入口',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kRed,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.flag),
                      label: const Text(
                        '赛道库',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _openLibrary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: _kRed),
                      ),
                      icon: const Icon(Icons.analytics_outlined),
                      label: Text(
                        trackTrips.isEmpty ? '赛道分析 · 暂无赛道行程' : '赛道分析 · 最新一趟',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: trackTrips.isEmpty
                          ? null
                          : () => _openTripAnalysis(context, trackTrips.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '赛道详情、图鉴、分析统一走本页；记录页顶部的“赛道”只是筛选，不进详情。',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 赛道模式说明（含 OBD 未连接提示与扇区诚实口径）。
            _card(
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '赛道模式说明',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '· 赛道模式只在汽车 / 摩托下计时，骑行不进赛道计时。',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '· 赛道行程不评分；结束页永远展示本节传感器实测总览，无圈速时也不为空。',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '· 未连接 OBD，暂无此通道：油门 / 刹车 / 转速均无数据，不反推曲线。',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '· 扇区口径：官方扇区 0 条可核实；估算的标“估算分段”、待核的标“扇区待核”，绝不冒充官方。',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '我的赛道行程 · 按赛道分组',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (trackTrips.isEmpty)
              const Text(
                '暂无赛道行程\n去首页选赛道开始一次记录',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              )
            else
              for (final key in groupKeys) ...[
                _groupCard(context, groups[key]!),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _groupCard(BuildContext context, List<TripMeta> trips) {
    final first = trips.first;
    final name = first.trackName.isEmpty ? '赛道行程' : first.trackName;
    final bests = trips
        .map((m) => bestLapMsByTripId[m.id])
        .whereType<int>()
        .toList();
    final groupBest = bests.isEmpty
        ? null
        : bests.reduce((a, b) => a < b ? a : b);
    final sector = sectorDataFor(first.trackId);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${trips.length} 趟',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            groupBest == null
                ? '最佳圈：暂无圈速'
                : '最佳圈：${LapTimer.formatLapTime(groupBest)}',
            style: const TextStyle(
              color: _kRed,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sector == null
                ? '扇区待核：未查到该赛道扇区数据'
                : '${sector.sourceLabel}：${sector.note}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const Divider(color: Colors.white12, height: 20),
          for (final m in trips)
            InkWell(
              onTap: () => _openTripAnalysis(context, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fmtDate(m.startMs),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(m.distanceM / 1000).toStringAsFixed(2)} km · ${_fmtDur(m.endMs - m.startMs)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      bestLapMsByTripId[m.id] == null
                          ? '暂无圈速'
                          : LapTimer.formatLapTime(bestLapMsByTripId[m.id]!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 2),
          const Text(
            '点某条行程进该行程的赛道分析页。',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtDur(int ms) {
  final s = ms ~/ 1000;
  if (s < 60) return '$s 秒';
  final m = s ~/ 60;
  if (m < 60) return '$m 分 ${s % 60} 秒';
  return '${m ~/ 60} 时 ${m % 60} 分';
}
