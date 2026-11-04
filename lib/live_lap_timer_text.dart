import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'rolling_digit.dart';
import 'track_timing.dart';

/// 显示层插值（纯函数，可单测，与 LapTimer 的权威计时严格分工）：
/// - anchor 为 null → null（占位）；
/// - paused → 冻结在 anchor；
/// - 否则 anchor +（当前 ticker 流逝 − 锚点处 ticker 流逝），下限 0。
/// 本函数只决定两帧之间显示什么，绝不算圈速：权威圈速仍以
/// LapTimer 在起终点穿越时算出的为准；新 GPS 点到达时调用方传
/// 新锚点，本函数下一次即以权威值校正（正常情况下校正量 =
/// 定位投递抖动，毫秒级；定位流 stall 后突发补点时，校正量
/// 等于该次投递延迟，属一次性纠正，不是持续误差）。
int? interpolatedLapMs({
  required int? anchorMs,
  required int elapsedMs,
  required int anchorElapsedMs,
  required bool paused,
}) {
  if (anchorMs == null) return null;
  if (paused) return anchorMs;
  final v = anchorMs + (elapsedMs - anchorElapsedMs);
  return v < 0 ? 0 : v;
}

/// 赛道大计时显示：以调用方传入的权威 currentLapMs 为锚点，
/// 用独立 vsync Ticker 按屏幕刷新率插值刷新，只重建本 widget，
/// 不再依赖 GPS 点到达（约 1Hz）才刷新；数值仍瞬间切换
/// （视频结论不变，不加回滑动动画）。
///
/// 正确性边界（调用方必须遵守，见 TrackSessionDisplay 接线）：
/// - 锚点只来自 LapTimer.currentLapMs，本 widget 不算圈速；
/// - [live] 为 false 时不 tick、不插值，显示静态锚点（供将来
///   静态复用，缺省即安全，误用也不会空转）；
/// - [paused] 为 true 时 ticker 停走、显示冻结在锚点；调用方
///   须把 LapTimer 自动暂停与记录手动暂停合并后传入；
/// - 圈号变化（完成一圈）时锚点重置，显示从新圈起点开始；
/// - 新 GPS 点到达时调用方传新锚点，本 widget 以权威值校正。
class LiveLapTimeText extends StatefulWidget {
  /// 权威锚点（LapTimer.currentLapMs）；null 时显示占位。
  final int? anchorMs;

  /// 当前圈号；变化即判定为完成一圈，锚点重置。
  final int lapNumber;

  /// 是否暂停（含自动暂停与手动暂停，调用方合并后传入）。
  final bool paused;

  /// 是否直播显示；false 时不 tick、不插值。
  final bool live;

  final TextStyle style;

  const LiveLapTimeText({
    super.key,
    required this.anchorMs,
    required this.lapNumber,
    required this.paused,
    required this.live,
    required this.style,
  });

  @override
  State<LiveLapTimeText> createState() => _LiveLapTimeTextState();
}

class _LiveLapTimeTextState extends State<LiveLapTimeText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 最近一次 tick 回调给出的流逝（自 ticker 启动起，ms）。
  /// Ticker 停走后重启会从 0 重新计，故锚点只在 ticker 活跃时
  /// 取该值；停走时锚点流逝记 0（重启后同样从 0 起算）。
  int _lastTickElapsedMs = 0;
  int? _anchorMs;
  int _anchorElapsedMs = 0;
  int? _displayMs;
  int _lapNumber = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _lapNumber = widget.lapNumber;
    _paused = widget.paused;
    _reanchor(force: true);
    _syncTicker();
  }

  @override
  void didUpdateWidget(LiveLapTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reanchor();
    _syncTicker();
  }

  /// 锚点处的 ticker 流逝：活跃时取最近一次回调值（与当前帧
  /// 最多差一帧，约 16ms 的恒定偏移，下次锚点更新即消除）；
  /// 停走时取 0（重启后流逝同样从 0 起算，正好对齐）。
  int get _anchorBaseMs =>
      _ticker.isActive ? _lastTickElapsedMs : 0;

  void _reanchor({bool force = false}) {
    final a = widget.anchorMs;
    if (!widget.live || a == null) {
      // 非直播或无锚点：显示静态值/占位，不插值。
      _anchorMs = a;
      _anchorElapsedMs = 0;
      _displayMs = a;
      _lapNumber = widget.lapNumber;
      _paused = widget.paused;
      return;
    }
    final lapChanged = widget.lapNumber != _lapNumber;
    final pausedChanged = widget.paused != _paused;
    if (force ||
        lapChanged ||
        pausedChanged ||
        _anchorMs == null ||
        a != _anchorMs) {
      // 锚点重置的几种情形：首次、完成一圈、暂停状态翻转、
      // 新 GPS 点到达（以权威值校正）。注意暂停翻转时必须重锚，
      // 否则恢复后插值会把整段暂停时长算进去、显示跳变。
      _lapNumber = widget.lapNumber;
      _paused = widget.paused;
      _anchorMs = a;
      _anchorElapsedMs = _anchorBaseMs;
      _displayMs = a;
    }
    // 锚点未变：不动 _anchorElapsedMs，继续插值，避免无关
    // 父重建打断滚动（否则每次父重建都会把显示拽回锚点）。
  }

  void _syncTicker() {
    final want = widget.live && widget.anchorMs != null && !widget.paused;
    if (want && !_ticker.isActive) {
      _ticker.start();
    } else if (!want && _ticker.isActive) {
      _ticker.stop();
      // 停走时显示冻结在锚点（暂停语义），不留插值尾巴。
      _displayMs = widget.anchorMs;
    }
  }

  void _onTick(Duration elapsed) {
    _lastTickElapsedMs = elapsed.inMilliseconds;
    final v = interpolatedLapMs(
      anchorMs: _anchorMs,
      elapsedMs: _lastTickElapsedMs,
      anchorElapsedMs: _anchorElapsedMs,
      paused: widget.paused,
    );
    if (v != _displayMs && mounted) setState(() => _displayMs = v);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RollingNumberText(
      value: LapTimer.formatLapTime(_displayMs),
      style: widget.style,
    );
  }
}
