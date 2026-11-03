import 'package:flutter/material.dart';

import 'checkered_flag.dart';

/// 首页下方并排大方块按钮行（v0.1.3 新建文件，不改旧文件）。
///
/// 左侧“标定”大方块、右侧带秒表标志的“开始记录”大方块，各高
/// [height]（默认 128，约定范围 120–140），圆角 20，左右 Expanded
/// 平分宽度、中间 12 间距。
///
/// 状态只由参数传入，本 widget 不读 Recorder、不调 Recorder：
/// - [calibrationState] 决定标定钮的配色与文字；
/// - [calibrationDetail] 是已标定后显示的第二行文字（如标定时间 /
///   车头方向，由总协调从 rec.calibrationNote 或标定完成时间拼），
///   未标定 / 标定中时不显示该行，改显示对应提示语；
/// - 两个按钮的回调全部走参数；开始记录的实际流程（安全守则、
///   倒计时、rec.start）由总协调在回调里做。

enum CalibrationButtonState {
  /// 未标定：深色默认态，文字写明“未标定”。
  uncalibrated,

  /// 标定中：琥珀色脉动（AnimationController 往复），文字写明“标定中”。
  calibrating,

  /// 已标定：绿色，文字写明“已标定 ✓”+ [BigActionButtons.calibrationDetail]。
  calibrated,
}

class BigActionButtons extends StatefulWidget {
  /// 标定钮状态。
  final CalibrationButtonState calibrationState;

  /// 已标定后显示的第二行文字，如“10:23 · 车头已锁定”。
  /// 总协调传入；为 null 或空时已标定态只显示“已标定 ✓”一行。
  final String? calibrationDetail;

  /// 标定钮回调（总协调传已有 _showCalibrationSheet）。
  final VoidCallback? onCalibrate;

  /// 开始记录钮回调（总协调传已有 _showSafety，或先推 CountdownPage
  /// 再开始的流程）。本 widget 不直接开始记录。
  final VoidCallback? onStartRecording;

  /// 两个方块的高度，默认 128（约定 120–140）。
  final double height;

  /// 开始记录钮是否可用（不可用时变暗且不响应，如记录中）。
  final bool startEnabled;

  /// 标定钮是否可用。
  final bool calibrateEnabled;

  /// 开始记录钮下方可选的小字副标题（如需提示安全守则流程时传入，
  /// 不传则不显示，不编造流程文案）。
  final String? startSubtitle;

  /// 赛道模式下开始记录大方块右上角的方格旗角标（v0.1.5）。
  /// true 时显示、false 时淡出消失；角标在右上角，不遮秒表标志与文字。
  final bool showTrackBadge;

  const BigActionButtons({
    super.key,
    required this.calibrationState,
    this.calibrationDetail,
    required this.onCalibrate,
    required this.onStartRecording,
    this.height = 128,
    this.startEnabled = true,
    this.calibrateEnabled = true,
    this.startSubtitle,
    this.showTrackBadge = false,
  });

  @override
  State<BigActionButtons> createState() => _BigActionButtonsState();
}

class _BigActionButtonsState extends State<BigActionButtons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant BigActionButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calibrationState != widget.calibrationState) _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (widget.calibrationState == CalibrationButtonState.calibrating) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  Widget _buildBlock({
    required Widget child,
    required Color background,
    required Color border,
    required VoidCallback? onTap,
    required bool enabled,
  }) {
    final content = Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: enabled ? background : background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled ? onTap : null,
          child: Center(child: child),
        ),
      ),
    );
    return Opacity(opacity: enabled ? 1.0 : 0.55, child: content);
  }

  Widget _calibrateContent() {
    switch (widget.calibrationState) {
      case CalibrationButtonState.uncalibrated:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.my_location, size: 34, color: Colors.orange),
            SizedBox(height: 8),
            Text('标定',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 4),
            Text('未标定', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        );
      case CalibrationButtonState.calibrating:
        return AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.radar, size: 34, color: Colors.amber.withValues(alpha: 0.6 + 0.4 * _pulse.value)),
                const SizedBox(height: 8),
                const Text('标定中…',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('正在锁定车头方向', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            );
          },
        );
      case CalibrationButtonState.calibrated:
        final detail = widget.calibrationDetail;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 34, color: Colors.white),
            const SizedBox(height: 8),
            const Text('已标定 ✓',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  detail,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final (calBg, calBorder) = switch (widget.calibrationState) {
      // 未标定：深色默认态（不是主题色，避免与开始记录混淆）。
      // v1.0.9 方案 A：底色与导航栏一致的 #2A2A2A、边框白 14%，
      // 与导航炭灰玻璃同风格；圆角/高度/禁用变暗逻辑不动。
      CalibrationButtonState.uncalibrated =>
        (const Color(0xFF2A2A2A), Colors.white.withValues(alpha: 0.14)),
      // 标定中：琥珀色底 + 脉动（脉动幅度由 _pulse 在内容层做，
      // 底色本身保持琥珀，避免整块闪烁刺眼）。
      CalibrationButtonState.calibrating =>
        (Colors.amber.withValues(alpha: 0.22), Colors.amber),
      // 已标定：绿色实底，状态一眼可辨。
      CalibrationButtonState.calibrated =>
        (const Color(0xFF16A34A), const Color(0xFF16A34A)),
    };
    return Row(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final glow = widget.calibrationState == CalibrationButtonState.calibrating
                  ? 0.25 + 0.45 * _pulse.value
                  : 0.0;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: glow > 0
                      ? [BoxShadow(color: Colors.amber.withValues(alpha: glow * 0.5), blurRadius: 18)]
                      : null,
                ),
                child: child,
              );
            },
            child: _buildBlock(
              background: calBg,
              border: calBorder,
              onTap: widget.onCalibrate,
              enabled: widget.calibrateEnabled,
              child: _calibrateContent(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            // 不用 StackFit.expand：Row 里的 Stack 高度由子项决定，
            // expand 会把无限高约束传给子项导致布局报错；改用定宽
            // SizedBox 撑满 Expanded 的宽度，高度仍由大方块本身（128）定。
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _buildBlock(
                  background: accent,
                  border: accent,
                  onTap: widget.onStartRecording,
                  enabled: widget.startEnabled,
                  child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 秒表标志：开始记录的视觉区分，不用纯文字按钮。
                const Icon(Icons.timer, size: 34, color: Colors.white),
                const SizedBox(height: 8),
                const Text('开始记录',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                if (widget.startSubtitle != null && widget.startSubtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.startSubtitle!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
                ),
                // 赛道模式角标：右上角小方格旗，淡入淡出（200ms），
                // 不遮中央的秒表标志与“开始记录”文字。
                Positioned(
                  top: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: widget.showTrackBadge ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: const CheckeredFlag(width: 20, height: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- 总协调接线提示（不执行，仅供参考） ----------
// 位置：_buildModePages 里删掉旧标定 pill 行（_buildCalibrationRow，
// 含 ActionChip“已标定/未标定·点此标定”）后，在首页下方（_buildIdleHome
// 顶部或 _buildModePages 底部，取代旧圆形 180px 开始记录钮的位置，
// 二者只能留其一，否则首页出现两个开始入口）放：
// Padding(
//   padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//   child: BigActionButtons(
//     calibrationState: rec.calibrated
//         ? CalibrationButtonState.calibrated
//         : <标定进行中时传 calibrating，否则 uncalibrated>,
//     // 标定进行中判定：总协调需从 rec 状态取（如 beginCalibration 后、
//     // calibrated 变 true 之前）；rec 目前没有公开的 calibrating 布尔量，
//     // 若无现成量，先用 uncalibrated/calibrated 两态，calibrating 态
//     // 待总协调补状态后再启用，见回执已知限制。
//     calibrationDetail: rec.calibrated ? rec.calibrationNote : null,
//     onCalibrate: _showCalibrationSheet,
//     onStartRecording: _showSafety, // 或先推 CountdownPage 的流程
//     startEnabled: !rec.isRecording,
//   ),
// );
// 注意：旧圆形开始钮在 _buildIdleHome 里（180x180 圆形 Container +
// RippleTap onTap: _showSafety）；换成大方块行时删掉该圆形钮，
// 保留其下方的实时速度 / 视频提示 / 传感器入口等行。
