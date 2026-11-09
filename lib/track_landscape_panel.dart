/// 赛道模式横屏布局（竖屏不走这里）。
///
/// 左栏只有赛道地图，右栏是唯一的仪表列。圈速列表、预测圈、
/// 理论最优、段速明细默认不放在这一列里，由调用方用底部表打开。
/// 全图模式只在地图角上留圈时 + Delta 两个胶囊，不再叠第二列仪表。
import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'lean_estimator.dart';
import 'live_lap_timer_text.dart';
import 'track_live_g.dart';
import 'track_session_display.dart';
import 'track_timing.dart';

/// 左 58% 地图 / 右 42% 仪表。全图时只留地图和角标。
class TrackLandscapeSplit extends StatelessWidget {
  const TrackLandscapeSplit({
    super.key,
    required this.map,
    required this.instruments,
    this.fullMap = false,
    this.fullMapOverlay,
  });

  final Widget map;
  final Widget instruments;
  final bool fullMap;
  final Widget? fullMapOverlay;

  @override
  Widget build(BuildContext context) {
    if (fullMap) {
      return Stack(
        fit: StackFit.expand,
        children: [
          map,
          if (fullMapOverlay != null) fullMapOverlay!,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 58, child: map),
        Expanded(flex: 42, child: instruments),
      ],
    );
  }
}

/// 横屏赛道唯一仪表列。顺序固定：圈时、Delta、分段、速度、
/// 横向 G + 倾角、暂停条（仅暂停时）、本节页脚。
class TrackLandscapeInstruments extends StatefulWidget {
  const TrackLandscapeInstruments({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.timerPaused,
    required this.timerLive,
    required this.liveDeltaMs,
    required this.showDelta,
    required this.sectorLabels,
    required this.sectorTimesMs,
    required this.sectorDeltasMs,
    required this.speedKmh,
    required this.speedColor,
    required this.latG,
    required this.longG,
    this.peakLat,
    this.peakLong,
    this.gCalibrated = true,
    required this.leanDeg,
    required this.leanQuality,
    required this.leanCalibrated,
    required this.autoPaused,
    required this.distanceKm,
    required this.elapsedLabel,
    this.onOpenDetails,
    this.onToggleFullMap,
  });

  final int currentLapNumber;
  final int? currentLapMs;
  final bool timerPaused;
  final bool timerLive;
  final int? liveDeltaMs;
  final bool showDelta;
  final List<String> sectorLabels;
  final List<int> sectorTimesMs;
  final List<int?> sectorDeltasMs;
  final double speedKmh;
  final Color speedColor;
  final double latG;
  final double longG;
  final double? peakLat;
  final double? peakLong;
  final bool gCalibrated;
  final double leanDeg;
  final LeanQuality leanQuality;
  final bool leanCalibrated;
  final bool autoPaused;
  final double distanceKm;
  final String elapsedLabel;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onToggleFullMap;

  @override
  State<TrackLandscapeInstruments> createState() =>
      _TrackLandscapeInstrumentsState();
}

class _TrackLandscapeInstrumentsState extends State<TrackLandscapeInstruments> {
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final delta = widget.showDelta ? widget.liveDeltaMs : null;
    final lapLabel = widget.currentLapNumber <= 0
        ? s.t('发车圈', 'Out lap')
        : s.t('第 ${widget.currentLapNumber} 圈', 'Lap ${widget.currentLapNumber}');
    return ColoredBox(
      color: const Color(0xFF1E1E1E),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: LiveLapTimeText(
                      anchorMs: widget.currentLapMs,
                      lapNumber: widget.currentLapNumber,
                      paused: widget.timerPaused,
                      live: widget.timerLive,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  lapLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Delta',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                LapTimer.formatDelta(delta),
                key: const Key('track-landscape-delta'),
                style: TextStyle(
                  color: sectorDeltaColor(delta),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (widget.sectorLabels.isNotEmpty)
              Row(
                children: [
                  for (var i = 0; i < widget.sectorLabels.length; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                            right: i == widget.sectorLabels.length - 1 ? 0 : 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2A2A2A)),
                        ),
                        child: Column(children: [
                          Text(widget.sectorLabels[i],
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            i < widget.sectorTimesMs.length
                                ? LapTimer.formatLapTime(widget.sectorTimesMs[i])
                                : '--:--.---',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ]),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  widget.speedKmh.toStringAsFixed(0),
                  style: TextStyle(
                    color: widget.speedColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                const Text('km/h',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            TrackGCross(
              longG: widget.longG,
              latG: widget.latG,
              peakLong: widget.peakLong,
              peakLat: widget.peakLat,
              calibrated: widget.gCalibrated,
            ),
            const SizedBox(height: 4),
            Text(
              _leanLabel(s),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (widget.autoPaused) ...[
              const SizedBox(height: 4),
              Container(
                key: const Key('track-landscape-pause'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Text(
                  s.t('已自动暂停 · 等待起步', 'Auto-paused · waiting to roll'),
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${s.t('本节', 'Session')} ${widget.elapsedLabel} · ${widget.distanceKm.toStringAsFixed(2)} km',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            Row(
              children: [
                if (widget.onOpenDetails != null)
                  TextButton(
                    key: const Key('track-landscape-details'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: widget.onOpenDetails,
                    child: Text(s.t('圈速明细', 'Lap detail'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                const Spacer(),
                if (widget.onToggleFullMap != null)
                  TextButton(
                    key: const Key('track-landscape-fullmap'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: widget.onToggleFullMap,
                    child: Text(s.t('全图', 'Full map'),
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _leanLabel(S s) {
    if (!widget.leanCalibrated) return s.t('倾角未标定', 'Lean n/a');
    if (widget.leanQuality == LeanQuality.unreliable) {
      return s.t('倾角 —', 'Lean —');
    }
    final lean = widget.leanDeg;
    final side = lean > 1
        ? s.t('右倾', 'right')
        : lean < -1
            ? s.t('左倾', 'left')
            : s.t('正直', 'upright');
    final weak = widget.leanQuality == LeanQuality.degraded
        ? s.t(' · 信号弱', ' · weak')
        : '';
    return s.t('倾角 ${lean.abs().toStringAsFixed(0)}° $side$weak',
        'Lean ${lean.abs().toStringAsFixed(0)}° $side$weak');
  }
}

/// 全图角标：只留圈时和 Delta，不放第二列仪表。
class TrackLandscapeMapCapsules extends StatelessWidget {
  const TrackLandscapeMapCapsules({
    super.key,
    required this.currentLapNumber,
    required this.currentLapMs,
    required this.timerPaused,
    required this.timerLive,
    required this.liveDeltaMs,
    required this.showDelta,
    this.onExitFullMap,
  });

  final int currentLapNumber;
  final int? currentLapMs;
  final bool timerPaused;
  final bool timerLive;
  final int? liveDeltaMs;
  final bool showDelta;
  final VoidCallback? onExitFullMap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final delta = showDelta ? liveDeltaMs : null;
    final lapLabel = currentLapNumber <= 0
        ? s.t('发车圈', 'Out lap')
        : s.t('第 $currentLapNumber 圈', 'Lap $currentLapNumber');
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _capsule(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lapLabel,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 8),
                    LiveLapTimeText(
                      anchorMs: currentLapMs,
                      lapNumber: currentLapNumber,
                      paused: timerPaused,
                      live: timerLive,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      LapTimer.formatDelta(delta),
                      style: TextStyle(
                        color: sectorDeltaColor(delta),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onExitFullMap != null)
                _capsule(
                  onTap: onExitFullMap,
                  child: Text(s.t('仪表', 'Gauges'),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capsule({required Widget child, VoidCallback? onTap}) {
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC121212),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }
}
