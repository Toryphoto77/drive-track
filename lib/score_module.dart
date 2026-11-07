/// 驾驶评分模块（v0.1.4 新文件，不改动已有文件）。
///
/// 真联动说明（不是静态图）：
/// - 点分项行 → 通过 [onFilterChanged] 回传该分项的原始 key
///   （汽车 / 摩托为 logic.dart 的 '平顺' / '过弯' / '速度稳定'；
///   骑行为 '配速稳定' / '功率稳定'）。
/// - 调用方（详情页）收到 key 后用 [scoreKeyToEventKinds] 换成事件 kind
///   再过滤 / 定位事件列表；返回空列表的分项（如骑行分项、速度稳定）
///   表示该分项没有对应事件，调用方应取消过滤而不是硬套事件。
/// - 点“全部”行 → 回传空字符串 ''，表示取消过滤。
/// 总分与分项全部由调用方传入（来自 Trip.score / Trip.subScores），
/// 本文件不算分、不读 store。

import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _kRed = Color(0xFFE10600);
const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);

/// 分项 key → 可过滤的事件 kind。
/// '平顺' 由急加速 / 急刹车构成；'过弯' 对应 corner；
/// 其余分项（速度稳定、骑行配速 / 功率）没有逐条事件，返回空列表。
List<String> scoreKeyToEventKinds(String key) {
  switch (key) {
    case '平顺':
      return const ['harshAccel', 'harshBrake'];
    case '过弯':
      return const ['corner'];
    default:
      return const [];
  }
}

/// 大号评分圆环：从 0 扫到 [total] 的动画。
/// [total] 为 0–100 分，超出范围会被 clamp，不画超量圆弧。
class DrivingScoreRing extends StatefulWidget {
  final double total;
  final double size;
  final Duration duration;

  const DrivingScoreRing({
    super.key,
    required this.total,
    this.size = 160,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<DrivingScoreRing> createState() => _DrivingScoreRingState();
}

class _DrivingScoreRingState extends State<DrivingScoreRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: widget.duration)
    ..forward();

  @override
  void didUpdateWidget(DrivingScoreRing old) {
    super.didUpdateWidget(old);
    if (old.total != widget.total) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total.clamp(0, 100).toDouble();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final shown = total * Curves.easeOutCubic.transform(_ctrl.value);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(progress: shown / 100),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(shown.toStringAsFixed(0),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.bold)),
              const Text('分',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ]),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0–1
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12);
    if (progress <= 0) return;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0, 1),
        false,
        Paint()
          ..color = _kRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// 驾驶评分卡：大号圆环动画 + 总分 + 平顺 / 过弯 / 速度稳定等分项条。
/// 点分项行即回调 [onFilterChanged]（传该分项 key）；点“全部”传 ''。
/// [selectedKey] 为当前被选中的分项 key（'' 或 null 表示全部），用于高亮。
/// [isTrackMode] 为真时显示“赛道模式不评分”，不渲染分数与分项。
class DrivingScoreCard extends StatelessWidget {
  final double total;
  final Map<String, double> subScores;
  final List<String> reasons;
  final bool isTrackMode;
  final String? selectedKey;
  final ValueChanged<String>? onFilterChanged;

  const DrivingScoreCard({
    super.key,
    required this.total,
    required this.subScores,
    this.reasons = const [],
    this.isTrackMode = false,
    this.selectedKey,
    this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('驾驶习惯评分',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (isTrackMode)
          const Text('赛道模式不评分 · 看圈速与稳定性',
              style: TextStyle(color: Colors.white70, fontSize: 14))
        else ...[
          Center(child: DrivingScoreRing(total: total)),
          const SizedBox(height: 12),
          _filterRow('', '全部', null),
          if (subScores.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('暂无',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            )
          else
            for (final e in subScores.entries)
              _filterRow(e.key, e.key, e.value),
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $r',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('注：无可靠限速源时不算超速分',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ]),
    );
  }

  Widget _filterRow(String key, String label, double? value) {
    final selected = (selectedKey ?? '') == key;
    return Material(
      color: selected ? _kRed.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onFilterChanged == null ? null : () => onFilterChanged!(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal)),
            ),
            if (value != null) ...[
              SizedBox(
                width: 110,
                child: LinearProgressIndicator(
                  value: (value.clamp(0, 100) / 100).toDouble(),
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  color: _kRed,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(value.toStringAsFixed(0),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ] else
              const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ]),
        ),
      ),
    );
  }
}
