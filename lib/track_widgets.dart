/// 赛道模式 widget（新文件，不改动已有文件）。
///
/// 约束：
/// - 全部用回调参数与纯数据入参，不直接引用 main.dart 的任何类，
///   不读 store、不读全局状态；接线由总协调在已有页面里组装。
/// - 样式：黑底 + 法拉利红主题（与 App 黑红主题一致），不引入新配色体系。
/// - 轮廓统一走 track_catalog.dart 的 TrackInfo.outline 数据源：
///   赛道选择页（TrackSelector）与赛道详情页（TrackDetailCard）用的
///   是同一 TrackSchematicDiagram、同一 TrackInfo.outline，不存在
///   第二套硬编码轮廓；录制页如需展示赛道图，同样复用本 widget。
/// - 所有示意图下方必须带“轮廓为按公开布局重绘的示意图，非官网原图”
///   文案：轮廓是按公开布局重绘的矢量示意图，不是官网原图，
///   不用于导航、计时判定或任何精确测量。

import 'package:flutter/material.dart';

import 'track_catalog.dart';
import 'track_timing.dart';

/// 黑红主题色（本文件自带，不依赖 main.dart 的主题对象）。
class TrackTheme {
  static const Color background = Color(0xFF0A0A0A);
  static const Color card = Color(0xFF141414);
  static const Color cardBorder = Color(0xFF2A2A2A);
  static const Color red = Color(0xFFE10600);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textDim = Colors.white38;
  static const Color faster = Color(0xFF22C55E); // Delta 为负（更快）时用绿字
}

/// 重绘轮廓图：按 TrackInfo.outline 画闭合折线。
/// - 起终点：startFinishPoint（与轮廓第一个点重合）标白芯红边圆点；
/// - 分段点（showSectors 为 true 时）：每个分段结束点标黄色菱形；
/// - 主要弯道（showCorners 为 true 时）：在弯道点旁标弯道号 / 路段名。
/// 下方固定带“轮廓为按公开布局重绘的示意图，非官网原图”文案，不得去掉。
/// 选择器小图默认不标弯道与分段（图小会糊），详情大图再打开两者。
class TrackSchematicDiagram extends StatelessWidget {
  final TrackInfo track;
  final double height;
  final bool showCaption;
  final bool showCorners;
  final bool showSectors;

  const TrackSchematicDiagram({
    super.key,
    required this.track,
    this.height = 120,
    this.showCaption = true,
    this.showCorners = false,
    this.showSectors = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: TrackTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TrackTheme.cardBorder),
          ),
          child: CustomPaint(
            painter: _TrackOutlinePainter(
              track,
              showCorners: showCorners,
              showSectors: showSectors,
            ),
          ),
        ),
        if (showCaption)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '轮廓为按公开布局重绘的示意图，非官网原图',
              style: TextStyle(color: TrackTheme.textDim, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _TrackOutlinePainter extends CustomPainter {
  final TrackInfo track;
  final bool showCorners;
  final bool showSectors;
  const _TrackOutlinePainter(
    this.track, {
    this.showCorners = false,
    this.showSectors = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outline = track.outline;
    if (outline.length < 3) return;
    const pad = 12.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    Offset toOffset(OutlinePoint p) => Offset(pad + p.x * w, pad + p.y * h);
    final pts = outline.map(toOffset).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = TrackTheme.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    // 分段点：黄色菱形（仅详情大图）。
    if (showSectors) {
      final labels = track.sectorLabels;
      for (var i = 0; i < track.sectorPoints.length; i++) {
        final c = toOffset(track.sectorPoints[i]);
        final diamond = Path()
          ..moveTo(c.dx, c.dy - 6)
          ..lineTo(c.dx + 6, c.dy)
          ..lineTo(c.dx, c.dy + 6)
          ..lineTo(c.dx - 6, c.dy)
          ..close();
        canvas.drawPath(
            diamond, Paint()..color = const Color(0xFFEAB308));
        _drawLabel(canvas, labels[i], Offset(c.dx + 8, c.dy - 14));
      }
    }
    // 主要弯道：编号 / 路段名小字（仅详情大图）。
    if (showCorners) {
      for (final corner in track.corners) {
        final c = toOffset(corner.point);
        canvas.drawCircle(c, 3, Paint()..color = Colors.white70);
        _drawLabel(canvas, corner.label, Offset(c.dx + 5, c.dy - 13));
      }
    }
    // 起终点：startFinishPoint（与轮廓第一个点重合）标白芯红边圆点。
    final start = track.startFinishPoint == null
        ? pts.first
        : toOffset(track.startFinishPoint!);
    canvas.drawCircle(
      start,
      5,
      Paint()..color = TrackTheme.red,
    );
    canvas.drawCircle(
      start,
      2.5,
      Paint()..color = Colors.white,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrackOutlinePainter old) =>
      old.track != track ||
      old.showCorners != showCorners ||
      old.showSectors != showSectors;
}

/// 赛道详情卡：详情 / 录制页复用，与选择器同一 TrackInfo.outline 数据源。
/// 大图打开弯道与分段标注，下方列出弯道数、方向、走向特征、起终点、
/// 分段说明与布局来源，并固定带重绘示意图声明。
class TrackDetailCard extends StatelessWidget {
  final TrackInfo track;
  const TrackDetailCard({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TrackTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrackTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${track.nameCn} · ${track.nameEn}',
            style: const TextStyle(
              color: TrackTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${track.region} · ${track.lengthLabel}',
            style: const TextStyle(
              color: TrackTheme.red,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          TrackSchematicDiagram(
            track: track,
            height: 200,
            showCorners: true,
            showSectors: true,
          ),
          const SizedBox(height: 10),
          _row('弯道', track.cornerLabel),
          if (track.direction.isNotEmpty) _row('方向', track.direction),
          if (track.shapeNote.isNotEmpty) _row('走向特征', track.shapeNote),
          if (track.startFinishNote.isNotEmpty)
            _row('起终点', track.startFinishNote),
          if (track.sectorNote.isNotEmpty) _row('分段', track.sectorNote),
          _row('布局参考', track.layoutSourceLabel),
          const SizedBox(height: 8),
          const Text(
            '轮廓为按公开布局重绘的示意图，非官网原图；'
            '弯道与分段点为示意位置，不用于导航与计时判定。',
            style: TextStyle(color: TrackTheme.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(
                    color: TrackTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: TrackTheme.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 赛道选择器：列表形式（国内 / 国外分组），每项显示示意轮廓图、
/// 中英文名、地区与“约 X km”长度。
/// 入参只有数据 + 回调，不引用 main.dart 的类。
class TrackSelector extends StatelessWidget {
  final List<TrackInfo> tracks;
  final String? selectedId;
  final ValueChanged<TrackInfo> onSelected;

  const TrackSelector({
    super.key,
    required this.tracks,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final domestic = tracks.where((t) => t.isDomestic).toList();
    final overseas = tracks.where((t) => !t.isDomestic).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            '轮廓为按公开布局重绘的示意图，非官网原图；不用于导航与计时判定',
            style: TextStyle(color: TrackTheme.textDim, fontSize: 11),
          ),
        ),
        if (domestic.isNotEmpty) ...[
          _sectionTitle('国内'),
          ...domestic.map(_tile),
        ],
        if (overseas.isNotEmpty) ...[
          _sectionTitle('国外'),
          ...overseas.map(_tile),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: TrackTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tile(TrackInfo track) {
    final selected = track.id == selectedId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TrackTheme.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelected(track),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? TrackTheme.red : TrackTheme.cardBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TrackSchematicDiagram(
                    track: track,
                    height: 64,
                    showCaption: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.nameCn,
                        style: const TextStyle(
                          color: TrackTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.nameEn,
                        style: const TextStyle(
                          color: TrackTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${track.region} · ${track.lengthLabel}',
                        style: const TextStyle(
                          color: TrackTheme.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      color: TrackTheme.red, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圈速表：当前圈 / 上一圈 / 最快圈 / Delta / 圈速榜 + 圈速稳定性。
/// 全部入参为纯数据（调用方从 LapTimer 取值后传入），不持有 LapTimer 本身；
/// [laps] 请传计时器的圈速榜（timer.leaderboard，已排除停留不计圈的圈）。
/// 点某一圈时通过 [onTapLap] 回传圈号（供详情页按圈高亮轨迹用），可不传。
class LapTable extends StatelessWidget {
  final int? currentLapMs;
  final Lap? lastLap;
  final Lap? bestLap;
  final int? deltaMs;
  final List<Lap> laps;
  final LapStability? stability;
  final bool isPaused;
  final int dwellLapCount;
  final bool hasSectorPoints;
  final ValueChanged<int>? onTapLap;

  const LapTable({
    super.key,
    required this.currentLapMs,
    required this.lastLap,
    required this.bestLap,
    required this.deltaMs,
    required this.laps,
    required this.stability,
    this.isPaused = false,
    this.dwellLapCount = 0,
    this.hasSectorPoints = true,
    this.onTapLap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TrackTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrackTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '圈速',
            style: TextStyle(
              color: TrackTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isPaused)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '已自动暂停，暂停时长不计入圈速',
                style: TextStyle(color: TrackTheme.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          _row('当前圈', LapTimer.formatLapTime(currentLapMs)),
          _row('上一圈',
              lastLap == null ? '--:--.---' : LapTimer.formatLapTime(lastLap!.durationMs)),
          _row('最快圈',
              bestLap == null ? '--:--.---' : LapTimer.formatLapTime(bestLap!.durationMs)),
          _deltaRow(),
          if (lastLap != null && lastLap!.sectorsMs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              hasSectorPoints
                  ? '上一圈分段：${lastLap!.sectorsMs.map(LapTimer.formatLapTime).join(' / ')}'
                  : '上一圈分段（无分段点，前后半圈示意）：${lastLap!.sectorsMs.map(LapTimer.formatLapTime).join(' / ')}',
              style: const TextStyle(color: TrackTheme.textSecondary, fontSize: 12),
            ),
          ],
          if (dwellLapCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '停留不计圈：$dwellLapCount 圈',
                style: const TextStyle(color: TrackTheme.textSecondary, fontSize: 12),
              ),
            ),
          if (stability != null) ...[
            const Divider(color: TrackTheme.cardBorder, height: 24),
            const Text(
              '圈速稳定性（仅计入圈）',
              style: TextStyle(
                color: TrackTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            _row('计入圈数', '${stability!.count} 圈'),
            _row('平均圈速', LapTimer.formatLapTime(stability!.meanMs.round())),
            _row('标准差', LapTimer.formatLapTime(stability!.stdDevMs.round())),
            _row('极差', LapTimer.formatLapTime(stability!.rangeMs.round())),
          ],
          if (laps.isNotEmpty) ...[
            const Divider(color: TrackTheme.cardBorder, height: 24),
            const Text(
              '圈速榜',
              style: TextStyle(
                color: TrackTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ...laps.asMap().entries.map((e) {
              final rank = e.key + 1;
              final lap = e.value;
              return InkWell(
                onTap: onTapLap == null ? null : () => onTapLap!(lap.number),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            color: rank == 1 ? TrackTheme.red : TrackTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: rank == 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      Text(
                        '第 ${lap.number} 圈',
                        style: const TextStyle(color: TrackTheme.textPrimary, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        LapTimer.formatLapTime(lap.durationMs),
                        style: const TextStyle(color: TrackTheme.textPrimary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: TrackTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: TrackTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _deltaRow() {
    final d = deltaMs;
    final color = d == null
        ? TrackTheme.textPrimary
        : (d < 0 ? TrackTheme.faster : TrackTheme.red);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Text('Delta（当前圈 - 最快圈，负为更快）',
              style: TextStyle(color: TrackTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(LapTimer.formatDelta(d),
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
