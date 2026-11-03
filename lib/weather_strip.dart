/// 驰迹全新天气条（v0.1.3 新文件，不改动 lib/widgets.dart 的旧 WeatherMarquee）。
///
/// 旧条重叠根因（见回执结论，这里只写本文件的对策）：
/// 旧条用 Stack + 两份 Positioned 文本做无缝循环，循环周期取的是视口宽度，
/// 而不是实测文本宽度，且每份文本内部又重复了两遍原文。两份起点间距 ≠ 文本
/// 实测宽度时，两份文字必然在同一 y 轴上错位重叠，出现鬼影。
///
/// 本文件对策：
/// 1. 只用 TextPainter 实测每段文本宽度，算出整条内容的实测总宽 [contentWidth]；
/// 2. 循环周期 = contentWidth + 固定份间间距，两份起点间距严格等于该周期，
///    动画值 1→0 跳变时两份位置视觉上完全重合，无缝且永不重叠；
/// 3. 内容短于视口时不滚动、不复制，只居中显示一份；
/// 4. 图标是每段 Row 的一部分，随文字一起滚动，不存在固定图标；
/// 5. 点按走 Material + InkWell 水波纹，只调 widget.onTap，不碰动画控制器。
library;

import 'package:flutter/material.dart';

/// 天气条的一段：图标 + 一段文字。图标与文字同为白色，随文字一起滚动。
class WeatherStripSegment {
  final IconData icon;
  final String text;

  const WeatherStripSegment(this.icon, this.text);
}

/// 固定高度 30px 的单行细长天气条，超出宽度时循环滚动。
class WeatherStrip extends StatefulWidget {
  final List<WeatherStripSegment> segments;

  /// 点按回调（由总协调传入，如跳转独立天气页）。点按不暂停、不重置滚动。
  final VoidCallback? onTap;

  /// 每秒滚动像素数，固定速度而非固定时长，文本长短不影响速度感。
  final double speedPxPerSecond;

  const WeatherStrip({
    super.key,
    required this.segments,
    this.onTap,
    this.speedPxPerSecond = 45,
  });

  /// 便捷构造：只有一段文字时用（图标默认云）。
  factory WeatherStrip.simple({required String text, IconData icon = Icons.cloud}) {
    return WeatherStrip(segments: [WeatherStripSegment(icon, text)]);
  }

  @override
  State<WeatherStrip> createState() => _WeatherStripState();
}

class _WeatherStripState extends State<WeatherStrip>
    with SingleTickerProviderStateMixin {
  static const double _height = 30;
  static const double _iconSize = 14;
  static const double _iconTextGap = 6;
  static const double _copyGap = 48;
  static const String _separator = '   •   ';

  static const TextStyle _textStyle = TextStyle(
    fontFamily: 'DriveTrackSans',
    fontSize: 13,
    color: Colors.white,
  );

  // v0.1.3 统合修复：控制器必须先有 duration 才能 repeat，否则首帧
  // 在 _remeasure 设时长前 repeat 会抛错（真机同样会炸）。先给默认时长，
  // _remeasure 再按实测宽度重设时长并重启。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  double _contentWidth = 0;
  String _segmentsKey = '';

  @override
  void initState() {
    super.initState();
    _remeasure();
  }

  @override
  void didUpdateWidget(covariant WeatherStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _remeasure();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _keyOf(List<WeatherStripSegment> segments) =>
      segments.map((s) => '${s.icon.codePoint}:${s.text}').join('|');

  double _measureText(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  /// 用 TextPainter 实测整条内容宽度，并按实测周期重设动画时长（速度恒定）。
  void _remeasure() {
    final key = _keyOf(widget.segments);
    if (key == _segmentsKey && _contentWidth > 0) return;
    _segmentsKey = key;
    var width = 0.0;
    final separatorWidth = _measureText(_separator);
    for (var i = 0; i < widget.segments.length; i++) {
      if (i > 0) width += separatorWidth;
      width += _iconSize + _iconTextGap;
      width += _measureText(widget.segments[i].text);
    }
    _contentWidth = width;
    final period = _contentWidth + _copyGap;
    final seconds = (period / widget.speedPxPerSecond).clamp(4.0, 120.0);
    _controller.duration = Duration(milliseconds: (seconds * 1000).round());
    if (!_controller.isAnimating) _controller.repeat();
  }

  Widget _contentRow() {
    final children = <Widget>[];
    for (var i = 0; i < widget.segments.length; i++) {
      if (i > 0) {
        children.add(Text(_separator, style: _textStyle, maxLines: 1, softWrap: false));
      }
      final segment = widget.segments[i];
      children.add(Icon(segment.icon, size: _iconSize, color: Colors.white));
      children.add(const SizedBox(width: _iconTextGap));
      children.add(Text(
        segment.text,
        style: _textStyle,
        maxLines: 1,
        softWrap: false,
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 内容为空时不滚动、不复制，只显示一份占位文字。
    final effectiveRow = widget.segments.isEmpty
        ? const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: _iconSize, color: Colors.white),
              SizedBox(width: _iconTextGap),
              Text('暂无天气', style: _textStyle, maxLines: 1, softWrap: false),
            ],
          )
        : _contentRow();

    return SizedBox(
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: Colors.black.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = constraints.maxWidth;
                  final scrolling =
                      widget.segments.isNotEmpty && _contentWidth > viewport;
                  if (!scrolling) {
                    return Center(child: effectiveRow);
                  }
                  final period = _contentWidth + _copyGap;
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      final offset = -_controller.value * period;
                      return SizedBox(
                        width: viewport,
                        height: _height,
                        child: Stack(
                          children: [
                            Positioned(
                              left: offset,
                              top: 0,
                              child: SizedBox(height: _height, child: effectiveRow),
                            ),
                            Positioned(
                              left: offset + period,
                              top: 0,
                              child: SizedBox(height: _height, child: effectiveRow),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
