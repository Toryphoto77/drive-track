/// 分享卡预览页（v0.1.4 新文件，不改动已有文件）。
///
/// 这是预览页，不是系统分享 sheet：页面内先让用户看卡面、换风格、
/// 切隐私开关，再点下方小按钮分享。
/// 预览页用毛玻璃与黑红主题一致（深色风格）；极简白底风格仅卡面变白，
/// 页面底色仍为黑，避免整页风格跳变。
/// 分享动作全部由调用方注入回调（[ShareCardPreviewPage.onShareImage] /
/// [ShareCardPreviewPage.onShareGpx] / [ShareCardPreviewPage.onShareCsv]），
/// 本文件不直连系统分享、不读 store、不写文件，总协调在详情页把
/// 已有分享逻辑接进来即可。
/// 轨迹图：调用方可传 [trajectoryWidget]（例如已有的轨迹 CustomPaint）；
/// 不传时只显示占位框，不画假轨迹、不拿未截断轨迹冒充截断后轨迹。
/// 里程 / 时长 / 最高速度 / 最大 G / 评分取自 Trip 的真实 getter 与字段；
/// [trimPrivacy] 为真时卡面只标注“轨迹已截掉首尾”，不改写统计数字
/// （统计口径与现有详情页分享卡一致：统计为整趟，轨迹显示截断）。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'models.dart';

/// 卡面风格。
enum ShareCardStyle {
  /// 黑红赛车。
  racing,

  /// 深色科幻。
  sciFi,

  /// 极简白底。
  minimal,
}

extension ShareCardStyleLabel on ShareCardStyle {
  String get label => switch (this) {
        ShareCardStyle.racing => '黑红赛车',
        ShareCardStyle.sciFi => '深色科幻',
        ShareCardStyle.minimal => '极简白底',
      };
}

String _fmtDur(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 3600).toString().padLeft(2, '0')}:'
      '${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
}

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}年${d.month}月${d.day}日 '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 模式亮点：只用 Trip 自带事件 / 轨迹算出，不编造。
/// 汽车取横向 G 最大的过弯；摩托取最大压弯角（仅作展示，是否可信
/// 由详情页的标定门控另行把关，本预览不重复断言）；骑行取平均功率
/// （估算时标注“估算”）。
String shareCardHighlight(Trip trip) {
  switch (trip.mode) {
    case TripMode.car:
      final corners = trip.events.where((e) => e.kind == 'corner').toList();
      if (corners.isEmpty) return '无偏急过弯';
      final c = corners.reduce(
          (a, b) => a.peakLatG.abs() > b.peakLatG.abs() ? a : b);
      return '最快过弯：入弯 ${(c.entrySpeed * 3.6).toStringAsFixed(0)} km/h · '
          '横向 ${c.peakLatG.abs().toStringAsFixed(2)}g';
    case TripMode.moto:
      return trip.points.isEmpty
          ? '暂无压弯数据'
          : '最大压弯角：${trip.maxLean.toStringAsFixed(0)}°';
    case TripMode.bike:
      final powers =
          trip.points.where((p) => p.powerW != null).map((p) => p.powerW!).toList();
      final avgPow = powers.isEmpty
          ? 0.0
          : powers.reduce((a, b) => a + b) / powers.length;
      final est = trip.points.any((p) => p.powerEstimated);
      return '平均功率 ${avgPow.toStringAsFixed(0)}W${est ? '（估算）' : ''}';
  }
}

/// 纯卡面（不带 Scaffold / 按钮组）：详情页如需把卡面嵌进已有页面
/// 用这个；需要完整预览流程（含风格切换与按钮组）用
/// [ShareCardPreviewPage]，它内部复用同一张卡面。
class ShareCardView extends StatelessWidget {
  final Trip trip;
  final String? videoPath;
  final bool trimPrivacy;
  final Widget? trajectoryWidget;
  final ShareCardStyle style;
  final GlobalKey? cardBoundaryKey;

  const ShareCardView({
    super.key,
    required this.trip,
    this.videoPath,
    this.trimPrivacy = true,
    this.trajectoryWidget,
    this.style = ShareCardStyle.racing,
    this.cardBoundaryKey,
  });

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    final dark = style != ShareCardStyle.minimal;
    final bg = switch (style) {
      ShareCardStyle.racing => const Color(0xFF0B1226),
      ShareCardStyle.sciFi => const Color(0xFF0A1A1A),
      ShareCardStyle.minimal => Colors.white,
    };
    final accent = style == ShareCardStyle.sciFi
        ? const Color(0xFF22D3EE)
        : const Color(0xFFE10600);
    final titleColor = dark ? Colors.white : Colors.black87;
    final subColor = dark ? Colors.white70 : Colors.black54;
    final highlightColor =
        style == ShareCardStyle.minimal ? const Color(0xFFE10600) : const Color(0xFF7DD3FC);
    final dateWeather = trip.weatherSummary.isEmpty
        ? _fmtDate(trip.startMs)
        : '${_fmtDate(trip.startMs)} · ${trip.weatherSummary}';
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: style == ShareCardStyle.sciFi
                ? accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('驰迹 DriveTrack · ${trip.mode.label}',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: accent)),
          ),
          if (trip.score > 0 && !trip.isTrackMode)
            Text('${trip.score.toStringAsFixed(0)} 分',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: titleColor)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 160,
          child: trajectoryWidget ??
              Container(
                decoration: BoxDecoration(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text('轨迹缩略图占位',
                      style: TextStyle(color: subColor, fontSize: 13)),
                ),
              ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _kv('里程', '${(trip.distanceM / 1000).toStringAsFixed(2)} km',
              titleColor, subColor),
          _kv('时长', _fmtDur(trip.endMs - trip.startMs), titleColor, subColor),
          _kv('最高', '${(trip.maxSpeed * 3.6).toStringAsFixed(0)} km/h',
              titleColor, subColor),
          _kv('最大 G',
              trip.points.isEmpty ? '暂无' : trip.maxG.toStringAsFixed(2),
              titleColor, subColor),
          if (!trip.isTrackMode)
            _kv('评分', trip.score.toStringAsFixed(0), titleColor, subColor),
        ]),
        const SizedBox(height: 8),
        Text(shareCardHighlight(trip),
            style: TextStyle(color: highlightColor, fontSize: 13)),
        const SizedBox(height: 4),
        Text(dateWeather, style: TextStyle(color: subColor, fontSize: 12)),
        if (videoPath != null) ...[
          const SizedBox(height: 4),
          Text('含同步视频：${videoPath!.split('/').last}',
              style: TextStyle(color: subColor, fontSize: 12)),
        ],
        if (trimPrivacy)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('隐私：分享轨迹已截掉首尾',
                style: TextStyle(color: subColor, fontSize: 12)),
          ),
      ]),
    );
    if (cardBoundaryKey != null) {
      return RepaintBoundary(key: cardBoundaryKey, child: card);
    }
    return card;
  }

  Widget _kv(String label, String value, Color titleColor, Color subColor) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: TextStyle(color: subColor, fontSize: 12)),
      Text(value,
          style: TextStyle(
              color: titleColor, fontSize: 13, fontWeight: FontWeight.bold)),
    ]);
  }
}

/// 分享卡预览页：风格切换 + 毛玻璃外框 + 隐私开关 + 下方分享按钮组。
class ShareCardPreviewPage extends StatefulWidget {
  final Trip trip;

  /// 关联视频路径（可选）；不传则卡面不显示视频行、不显示分享视频按钮。
  final String? videoPath;

  /// 是否截断首尾隐私（开关状态由调用方持有，变化时回传）。
  final bool trimPrivacy;

  /// 隐私开关变化回调；不传则开关只读显示。
  final ValueChanged<bool>? onTrimPrivacyChanged;

  /// 调用方传入的轨迹图 Widget；不传则显示占位框。
  final Widget? trajectoryWidget;

  /// 卡面风格初始值；页内可切换，切换状态只留本页。
  final ShareCardStyle initialStyle;

  /// 供调用方截图分享用的卡面 boundary key（可选）：
  /// 调用方把同一个 key 传给本页，并在 onShareImage 里用它截图。
  final GlobalKey? cardBoundaryKey;

  /// 下方小按钮组回调，全部由调用方注入；为 null 的按钮不显示。
  final VoidCallback? onShareImage;
  final VoidCallback? onShareGpx;
  final VoidCallback? onShareCsv;
  final VoidCallback? onShareVideo;

  const ShareCardPreviewPage({
    super.key,
    required this.trip,
    this.videoPath,
    this.trimPrivacy = true,
    this.onTrimPrivacyChanged,
    this.trajectoryWidget,
    this.initialStyle = ShareCardStyle.racing,
    this.cardBoundaryKey,
    this.onShareImage,
    this.onShareGpx,
    this.onShareCsv,
    this.onShareVideo,
  });

  @override
  State<ShareCardPreviewPage> createState() => _ShareCardPreviewPageState();
}

class _ShareCardPreviewPageState extends State<ShareCardPreviewPage> {
  late ShareCardStyle _style = widget.initialStyle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(title: const Text('分享卡预览')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<ShareCardStyle>(
            segments: ShareCardStyle.values
                .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                .toList(),
            selected: {_style},
            onSelectionChanged: (v) => setState(() => _style = v.first),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF000000).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: const EdgeInsets.all(10),
                child: ShareCardView(
                  trip: widget.trip,
                  videoPath: widget.videoPath,
                  trimPrivacy: widget.trimPrivacy,
                  trajectoryWidget: widget.trajectoryWidget,
                  style: _style,
                  cardBoundaryKey: widget.cardBoundaryKey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('截断首尾隐私',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const Spacer(),
            Switch(
              value: widget.trimPrivacy,
              onChanged: widget.onTrimPrivacyChanged,
            ),
          ]),
          if (widget.trimPrivacy)
            const Text('开启后分享的轨迹将截掉首尾，统计数字仍为整趟',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.onShareImage != null)
              FilledButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('分享图片'),
                  onPressed: widget.onShareImage),
            if (widget.onShareGpx != null)
              OutlinedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('分享 GPX'),
                  onPressed: widget.onShareGpx),
            if (widget.onShareCsv != null)
              OutlinedButton.icon(
                  icon: const Icon(Icons.file_download),
                  label: const Text('分享 CSV'),
                  onPressed: widget.onShareCsv),
            if (widget.onShareVideo != null && widget.videoPath != null)
              OutlinedButton.icon(
                  icon: const Icon(Icons.videocam),
                  label: const Text('分享视频'),
                  onPressed: widget.onShareVideo),
          ]),
          const SizedBox(height: 8),
          const Text('分享走系统分享，不登录不上传；CSV 为完整数据，请自行注意隐私。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      ),
    );
  }
}
