import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'native.dart';
import 'store.dart';

/// v1.7.x 导入运动相机视频：系统选择器选完视频后，弹出本底栏
/// 「匹配行程 + 校正首帧拍摄时刻」。
///
/// [preselectedTrip] 非空时跳过选行程（如从行程详情 / HUD 空态进入），
/// 只校正拍摄时刻。确认后把视频重命名为 `trip_<startMs>.mp4`，使
/// [VideoHudPage] 的 `_autoOffset` 自动算出偏移（零改动复用现有对齐），
/// 并把路径写回 `trip.videoPaths`。
///
/// 返回已落盘的更新后 [Trip]；用户取消返回 null。
Future<Trip?> showVideoImportSheet(
  BuildContext context, {
  required Store store,
  required String videoPath,
  required int createdMs,
  Trip? preselectedTrip,
}) {
  return showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B0E13),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _VideoImportSheet(
      store: store,
      videoPath: videoPath,
      createdMs: createdMs,
      preselectedTrip: preselectedTrip,
    ),
  );
}

/// 一步式便捷入口：直接拉起系统视频选择器，选完弹匹配面板。
/// [preselectedTrip] 非空时跳过选行程。返回更新后 Trip；取消/失败返回 null。
Future<Trip?> pickAndImportVideo(
  BuildContext context, {
  required Store store,
  Trip? preselectedTrip,
}) async {
  final r = await Native.pickVideo();
  if (r == null) return null;
  final path = r['path'] as String?;
  final createdMs = (r['createdMs'] as num?)?.toInt() ??
      DateTime.now().millisecondsSinceEpoch;
  if (path == null || !context.mounted) return null;
  return showVideoImportSheet(
    context,
    store: store,
    videoPath: path,
    createdMs: createdMs,
    preselectedTrip: preselectedTrip,
  );
}

class _VideoImportSheet extends StatefulWidget {
  final Store store;
  final String videoPath;
  final int createdMs;
  final Trip? preselectedTrip;

  const _VideoImportSheet({
    required this.store,
    required this.videoPath,
    required this.createdMs,
    this.preselectedTrip,
  });

  @override
  State<_VideoImportSheet> createState() => _VideoImportSheetState();
}

class _VideoImportSheetState extends State<_VideoImportSheet> {
  String? _tripId;
  late int _startMs = widget.createdMs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tripId = widget.preselectedTrip?.id;
  }

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _dur(int start, int end) {
    final s = ((end - start) ~/ 1000).abs();
    if (s < 60) return '${s}秒';
    return '${s ~/ 60}分${s % 60}秒';
  }

  Future<void> _confirm() async {
    final id = _tripId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      // 重命名为 trip_<startMs>.mp4 → VideoHudPage._autoOffset 自动对齐：
      // 偏移 = startMs - trip.startMs。同目录 instant rename；撞名 +1ms 避让。
      final src = File(widget.videoPath);
      final dir = src.parent;
      var ms = _startMs;
      var target = File('${dir.path}/trip_$ms.mp4');
      while (target.existsSync()) {
        ms += 1;
        target = File('${dir.path}/trip_$ms.mp4');
      }
      src.renameSync(target.path);

      final existing = widget.preselectedTrip?.videoPaths ??
          (await widget.store.loadTrip(id))?.videoPaths ??
          const <String>[];
      final paths = <String>[...existing, target.path];
      final updated = await widget.store.updateTripVideoPaths(id, paths);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    child: Text(
                      '导入运动相机视频',
                      style: TextStyle(
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
            if (widget.preselectedTrip == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  '选择这段视频对应的行程',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            if (widget.preselectedTrip == null)
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
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('还没有行程记录',
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    // 推荐：createdMs 落在行程时间窗内；否则取开始时间最近的。
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
                            color: selected ? Colors.redAccent : Colors.white54,
                          ),
                          title: Text('${m.mode.label} · ${_fmt(m.startMs)}'),
                          subtitle: Text(
                            '${_dur(m.startMs, m.endMs)}'
                            '${isRec ? ' · 推荐匹配' : ''}',
                          ),
                          onTap: () => setState(() => _tripId = m.id),
                        );
                      },
                    );
                  },
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '匹配到：${widget.preselectedTrip!.mode.label} · '
                  '${_fmt(widget.preselectedTrip!.startMs)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            const Divider(color: Colors.white12, height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                '视频首帧拍摄时刻（用于与行程自动对齐）',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _fmt(_startMs),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Wrap(
                spacing: 6,
                children: [
                  _stepButton('-10秒', -10000),
                  _stepButton('-1秒', -1000),
                  _stepButton('+1秒', 1000),
                  _stepButton('+10秒', 10000),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _startMs = widget.createdMs),
                    child: const Text('用拍摄时间'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_tripId == null || _busy) ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_busy ? '正在导入…' : '关联到此行程'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton(String label, int delta) => TextButton(
        onPressed: _busy ? null : () => setState(() => _startMs += delta),
        child: Text(label),
      );
}
