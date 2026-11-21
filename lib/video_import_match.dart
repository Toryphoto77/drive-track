import 'dart:io';

import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_notice.dart';
import 'dt_page_route.dart';
import 'models.dart';
import 'store.dart';
import 'video_gallery_page.dart';
import 'video_hud_page.dart';

/// v1.7.x 视频与赛道记录关联（双向入口统一收口）。
///
/// 两个入口、同一条结果链：
/// - 设备中心「视频同步」→ 先选视频（App 内相册页）→ 再选行程 → 编辑页；
/// - 记录详情「添加视频」→ 已带行程 → 只选视频 → 编辑页。
///
/// 关联动作本身仍沿用旧规则：把素材重命名为 `trip_<开录ms>.mp4` 后
/// 追加进 `trip.videoPaths`，使编辑页的自动对齐能直接读到开录时间。
/// 偏移微调不再在导入时做，全部放进编辑页的「调整画面对齐」。

/// 关联结果：更新后的行程 + 这段视频在磁盘上的最终路径。
///
/// 关联时素材会被重命名为 `trip_<开录ms>.mp4`，调用方必须拿 [path]
/// （而不是重命名前的旧路径）去打开编辑页：旧路径已不存在，
/// `File(path).existsSync()` 为 false，预览区只会剩下空框。
class VideoLinkResult {
  const VideoLinkResult({required this.trip, required this.path});

  final Trip trip;
  final String path;
}

/// 关联结果：更新后的行程（已写入新的视频路径）与最终文件路径。
Future<VideoLinkResult?> linkVideoToTrip(
  Store store, {
  required Trip trip,
  required String videoPath,
  required int createdMs,
}) async {
  try {
    // 重命名为 trip_<startMs>.mp4 → 编辑页按文件名自动对齐；
    // 同目录 instant rename，撞名 +1ms 避让。
    final src = File(videoPath);
    final dir = src.parent;
    var ms = createdMs;
    var target = File('${dir.path}/trip_$ms.mp4');
    while (target.existsSync()) {
      ms += 1;
      target = File('${dir.path}/trip_$ms.mp4');
    }
    src.renameSync(target.path);

    final existing = trip.videoPaths;
    final paths = <String>[...existing, target.path];
    final updated = await store.updateTripVideoPaths(trip.id, paths);
    if (updated == null) return null;
    return VideoLinkResult(trip: updated, path: target.path);
  } catch (e) {
    throw Exception('导入失败：$e');
  }
}

/// 统一入口：选视频 → （可选）选行程 → 关联 → 视频编辑页。
///
/// [preselectedTrip] 非空 = 记录页入口，跳过选行程。
/// [initialVideoPath] 非空 = 已有素材（如编辑页空态里重导），跳过选视频。
/// 返回最终更新后的行程（用户取消返回 null）。
Future<Trip?> openVideoSyncFlow(
  BuildContext context, {
  required Store store,
  Trip? preselectedTrip,
  String? initialVideoPath,
  int? initialCreatedMs,
}) async {
  String? path = initialVideoPath;
  int createdMs = initialCreatedMs ?? DateTime.now().millisecondsSinceEpoch;
  final freshlyCopied = initialVideoPath == null;

  if (path == null) {
    final picked = await Navigator.of(context).push<VideoPickResult>(
      DtPageRoute(builder: (_) => const VideoGalleryPage()),
    );
    if (picked == null) return null;
    path = picked.path;
    createdMs = picked.createdMs;
  }

  var trip = preselectedTrip;
  if (trip == null) {
    trip = await showVideoTripPickerSheet(
      context,
      store: store,
      createdMs: createdMs,
    );
    if (trip == null) {
      // 用户取消了选行程：刚拷进 App 目录的副本没有用途，清掉避免占空间。
      if (freshlyCopied) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      return null;
    }
  }

  VideoLinkResult? linked;
  try {
    linked = await linkVideoToTrip(
      store,
      trip: trip,
      videoPath: path,
      createdMs: createdMs,
    );
  } catch (e) {
    if (context.mounted) {
      showAppNotice(context, '$e', AppNoticeKind.error);
    }
    return null;
  }
  if (linked == null) {
    if (context.mounted) {
      showAppNotice(context, '视频关联失败，请重试。', AppNoticeKind.error);
    }
    return null;
  }
  final result = linked;
  if (!context.mounted) return result.trip;

  await Navigator.of(context).push(
    DtPageRoute(
      builder: (_) => VideoHudPage(
        trip: result.trip,
        store: store,
        // 素材已被重命名为 trip_<ms>.mp4，必须传最终路径。
        initialVideoPath: result.path,
      ),
    ),
  );
  // 编辑页里可能解除关联：返回前重新读一次行程，调用方据此刷新列表。
  final latest = await store.loadTrip(result.trip.id);
  return latest ?? result.trip;
}

/// 选择这段视频对应的行程；返回更新后的行程，取消返回 null。
Future<Trip?> showVideoTripPickerSheet(
  BuildContext context, {
  required Store store,
  required int createdMs,
}) {
  return showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B0E13),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _TripPickerSheet(
      store: store,
      createdMs: createdMs,
    ),
  );
}

class _TripPickerSheet extends StatefulWidget {
  final Store store;
  final int createdMs;

  const _TripPickerSheet({required this.store, required this.createdMs});

  @override
  State<_TripPickerSheet> createState() => _TripPickerSheetState();
}

class _TripPickerSheetState extends State<_TripPickerSheet> {
  String? _tripId;
  TripMeta? _selected;
  bool _busy = false;

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _dur(int start, int end) {
    final s = ((end - start) ~/ 1000).abs();
    if (s < 60) return '${s}秒';
    if (s < 3600) return '${s ~/ 60}分${s % 60}秒';
    return '${s ~/ 3600}小时${(s % 3600) ~/ 60}分';
  }

  Future<void> _confirm() async {
    final meta = _selected;
    if (meta == null || _busy) return;
    setState(() => _busy = true);
    Trip? trip;
    try {
      trip = await widget.store.loadTrip(meta.id);
      if (!mounted) return;
      if (trip == null) {
        setState(() => _busy = false);
        showAppNotice(context, '行程文件读取失败，请重试。', AppNoticeKind.error);
        return;
      }
      Navigator.of(context).pop(trip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(context, '读取行程失败：$e', AppNoticeKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.t('关联到哪条赛道记录', 'Which trip is this video for?'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                s.t(
                  '选择后进入视频编辑页，可再调整画面对齐与 HUD 信息。',
                  'You can adjust sync and HUD after choosing.',
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<TripMeta>>(
                future: widget.store.loadIndex(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final metas = snap.data!;
                  if (metas.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        s.t('还没有行程记录', 'No trips yet'),
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  // 推荐：拍摄时间落在行程时间窗内；否则取开始时间最近的。
                  TripMeta? recommended;
                  for (final m in metas) {
                    if (widget.createdMs >= m.startMs &&
                        widget.createdMs <= m.endMs) {
                      recommended = m;
                      break;
                    }
                  }
                  recommended ??= metas.reduce((a, b) =>
                      (widget.createdMs - a.startMs).abs() <=
                              (widget.createdMs - b.startMs).abs()
                          ? a
                          : b);
                  _tripId ??= recommended.id;
                  _selected ??= recommended;
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: metas.length,
                    itemBuilder: (ctx, i) {
                      final m = metas[i];
                      final selected = _tripId == m.id;
                      final isRec = recommended?.id == m.id;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white54,
                        ),
                        title: Text('${m.mode.label} · ${_fmt(m.startMs)}'),
                        subtitle: Text(
                          '${_dur(m.startMs, m.endMs)}'
                          '${isRec ? ' · 推荐匹配' : ''}',
                        ),
                        onTap: () => setState(() {
                          _tripId = m.id;
                          _selected = m;
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selected == null || _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.movie_filter_outlined),
                  label: Text(
                    _busy ? s.t('正在进入…', 'Opening…') : s.t('关联并编辑', 'Link and edit'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
