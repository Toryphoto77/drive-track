import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏倒计时页（v0.1.3 新建文件，不改旧文件）。
///
/// 流程：3-2-1-GO，每秒一次短震动，GO 时一次长震动（见下方震动说明），
/// GO 亮约 800ms 后自动调用 [onFinish]；倒计时中点“取消”或按系统返回键
/// 则取消，不调用 [onFinish]。
///
/// 本页不碰 Recorder、不开始记录、不自己决定记录逻辑：开始记录是
/// 总协调在 [onFinish] 里做的事；取消后同样由总协调决定（且必须不开始
/// 记录）。导航方面本页自理：完成与取消时本页自己 Navigator.pop，
/// 再调回调，因此总协调的 onFinish/onCancel 里不要再 pop 一次
/// （否则会多弹一层路由）。
///
/// 震动说明（必须如实传达）：Flutter 的 HapticFeedback 没有时长参数，
/// “短震动”用 HapticFeedback.lightImpact()，“长震动”用最强的
/// HapticFeedback.heavyImpact() 近似，没有原生震动马达或系统关闭触感
/// 反馈时无震动但不崩（全部 try/catch）。如需真正可控时长的长震动
/// （如 500ms），总协调需补一个原生震动方法，本页再换调该方法。
/// [vibrationEnabled] 为 false 时全程不震动。

class CountdownPage extends StatefulWidget {
  /// GO 结束后的回调：总协调在此 pop 后的逻辑里开始记录
  /// （如调已有 _showSafety 或直接开始流程）。本页调 onFinish 前
  /// 已经自己 pop 掉倒计时页。
  final VoidCallback onFinish;

  /// 取消回调：用户点“取消”或按系统返回键时调用；本页调 onCancel 前
  /// 已经自己 pop 掉倒计时页。总协调收到后必须不开始记录。
  final VoidCallback? onCancel;

  /// 震动是否开启（总协调从设置页的倒计时震动开关传入）。
  final bool vibrationEnabled;

  /// 倒计时起始秒数，默认 3（即 3-2-1-GO）。
  final int countFrom;

  /// GO 亮起后、调用 onFinish 前的停留时长，默认 800ms。
  final Duration goHold;

  const CountdownPage({
    super.key,
    required this.onFinish,
    this.onCancel,
    this.vibrationEnabled = true,
    this.countFrom = 3,
    this.goHold = const Duration(milliseconds: 800),
  });

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> {
  /// >0 表示剩余秒数，0 表示 GO。
  late int _remaining = widget.countFrom;
  Timer? _tickTimer;
  Timer? _goTimer;

  /// 完成或取消已触发过（防重复回调与重复 pop）。
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _goTimer?.cancel();
    super.dispose();
  }

  void _vibrateShort() {
    if (!widget.vibrationEnabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {
      // 无震动马达 / 系统关闭触感反馈时静默，不崩。
    }
  }

  void _vibrateLong() {
    if (!widget.vibrationEnabled) return;
    try {
      // HapticFeedback 无时长参数，heavyImpact 是最强的近似长震动。
      HapticFeedback.heavyImpact();
    } catch (_) {
      // 同上，静默。
    }
  }

  void _tick() {
    if (_done || !mounted) return;
    if (_remaining > 1) {
      setState(() => _remaining--);
      _vibrateShort();
    } else if (_remaining == 1) {
      setState(() => _remaining = 0);
      _vibrateLong();
      _tickTimer?.cancel();
      _tickTimer = null;
      _goTimer = Timer(widget.goHold, _finish);
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _tickTimer?.cancel();
    _goTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context);
    widget.onFinish();
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    _tickTimer?.cancel();
    _goTimer?.cancel();
    if (!mounted) return;
    Navigator.pop(context);
    widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isGo = _remaining == 0;
    return PopScope(
      // 系统返回键同样走取消路径，不直接放行（否则 onCancel 收不到，
      // 总协调无法区分“用户放弃”与“倒计时走完”）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: Tween<double>(begin: 0.7, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: Text(
                  isGo ? 'GO' : '$_remaining',
                  key: ValueKey<int>(_remaining),
                  // 继承主题字体（DriveTrackSans / 自带字体覆盖时为
                  // DriveTrackCustom），不硬编码 fontFamily。
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 140,
                        fontWeight: FontWeight.bold,
                        color: isGo ? accent : Colors.white,
                      ) ??
                      TextStyle(
                        fontSize: 140,
                        fontWeight: FontWeight.bold,
                        color: isGo ? accent : Colors.white,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isGo ? '出发！' : '即将开始记录',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (!widget.vibrationEnabled)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '震动提醒已关闭',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('取消'),
                  onPressed: _cancel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 总协调接线提示（不执行，仅供参考） ----------
// 典型流程：首页大方块“开始记录” -> 安全守则确认 -> 推倒计时页 ->
// onFinish 里开始记录；onCancel 里什么都不做（绝不开始记录）。
// Navigator.push(context, MaterialPageRoute(
//   builder: (_) => CountdownPage(
//     vibrationEnabled: <设置页的倒计时震动开关值>,
//     onFinish: () {
//       // 注意：本页已自己 pop，不要再 pop；这里只做开始记录，
//       // 如：await rec.start(); 或复用已有流程（视频勾选等在
//       // _showSafety 里，倒计时应放在 _showSafety 确认之后推）。
//     },
//     onCancel: () {
//       // 注意：本页已自己 pop，不要再 pop；这里什么都不做，
//       // 绝不开始记录。
//     },
//   ),
// ));
