import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'voice_service.dart';

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
/// 震动说明（v1.5.1 改原生可控时长震动）：Flutter 的 HapticFeedback
/// 没有时长参数，heavyImpact 只有约 20ms，用户反馈 321 强震感不够、
/// GO 要一次长震——现改走原生 Vibrator：每拍 200ms 强震、GO 时
/// 700ms 长震（见 [_vibrateTick] / [_vibrateGo]）；原生失败或无马达
/// 时回落 heavyImpact，不崩。全部 try/catch，静默。
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

  /// 倒数语音开关：总协调从语音设置页的“开始语音”开关传入。
  /// 为 true 时：进入本页先停掉未播完的安全播报，再按节拍报数
  /// （进页报起始数字，每拍报新数字，GO 时报“开始”）；为 false
  /// 时全程不发声、不停其他语音，倒计时本身完全不变。
  final bool speakCountdown;

  const CountdownPage({
    super.key,
    required this.onFinish,
    this.onCancel,
    this.vibrationEnabled = true,
    this.countFrom = 3,
    this.goHold = const Duration(milliseconds: 800),
    this.speakCountdown = true,
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
    // 倒数语音：进页先停掉未播完的安全播报（beginCountdown 内含
    // 停原生 + 推进世代），再报起始数字；两个都是 fire-and-forget，
    // 任何失败都不阻塞倒计时本身。顺序必须先停后报，否则“3”
    // 会被停安全播报的动作连带掐掉。
    if (widget.speakCountdown) {
      unawaited(_startCountdownVoice());
    }
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 进页语音序列：先停安全播报，再报起始数字（如 3）。
  Future<void> _startCountdownVoice() async {
    try {
      await VoiceService.instance.beginCountdown();
    } catch (_) {
      // 停失败不阻塞：报数照常入队，原生队列本身是串行的。
    }
    if (!mounted) return;
    try {
      await VoiceService.instance.speakCountdown('$_remaining');
    } catch (_) {
      // 报数失败静默，倒计时视觉与震动完全不受影响。
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _goTimer?.cancel();
    super.dispose();
  }

  /// 倒数每拍的强震：原生 200ms，失败回落 heavyImpact。
  Future<void> _vibrateTick() async {
    if (!widget.vibrationEnabled) return;
    if (!await Native.vibrate(200)) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  /// GO 时的长震：原生 700ms 一次，失败回落 heavyImpact。
  Future<void> _vibrateGo() async {
    if (!widget.vibrationEnabled) return;
    if (!await Native.vibrate(700)) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  void _tick() {
    if (_done || !mounted) return;
    if (_remaining > 1) {
      setState(() => _remaining--);
      // 倒数每拍都用强震动（用户要求），不再轻震。
      unawaited(_vibrateTick());
      // 报数与视觉节拍对齐：数字变到几就报几。
      if (widget.speakCountdown) {
        unawaited(VoiceService.instance.speakCountdown('$_remaining'));
      }
    } else if (_remaining == 1) {
      setState(() => _remaining = 0);
      // GO 时触发一次长震（用户要求）。
      unawaited(_vibrateGo());
      // GO 时报“开始”，与屏幕上的 GO / 出发同步。
      if (widget.speakCountdown) {
        unawaited(VoiceService.instance.speakCountdown('开始'));
      }
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
    // 取消返回时停掉未播完的倒数报数；完成（_finish）时不调，
    // 让“开始”播完，不掐尾音。
    if (widget.speakCountdown) {
      unawaited(VoiceService.instance.cancelAll());
    }
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
