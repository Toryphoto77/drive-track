import 'dart:io';

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'native.dart';

/// v1.7.x App 内视频相册选择页（设备中心 / 记录页双向入口共用）。
///
/// 数据来源：
/// - 手机相册：原生 MediaStore 查询（[Native.listVideos]），含缩略图；
///   首次进入按需申请读取媒体权限，拒绝时退回系统选择器，不阻塞流程。
/// - 系统选择器：ACTION_GET_CONTENT（[Native.pickVideo]），选完直接
///   拷贝到本 App 私有目录，适合只授权单次素材的场景。
///
/// 选中后统一经 [Native.importVideoUri] 拷进 `filesDir/videos/`，
/// 回传 [VideoPickResult]；真正的关联行程与编辑由调用方接着做。
class VideoPickResult {
  const VideoPickResult({required this.path, required this.createdMs});

  final String path;
  final int createdMs;
}

class VideoGalleryPage extends StatefulWidget {
  const VideoGalleryPage({super.key, this.accent});

  /// 主色（默认跟主题 primary），调用方可传当前主题强调色。
  final Color? accent;

  @override
  State<VideoGalleryPage> createState() => _VideoGalleryPageState();
}

class _VideoGalleryPageState extends State<VideoGalleryPage> {
  bool _loading = true;
  bool _denied = false;
  bool _importing = false;
  List<Map<String, dynamic>> _items = const [];

  Color get _accent =>
      widget.accent ?? Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    setState(() => _loading = true);
    var list = await Native.listVideos();
    if (list.isEmpty) {
      // 未授权时先拉权限框再查一次；仍为空则按“无权限 / 无视频”空态处理。
      final perm = await Native.checkPermissions();
      if (perm['media'] != true) {
        try {
          await Native.requestStep('media');
        } catch (_) {}
        list = await Native.listVideos();
      }
    }
    if (!mounted) return;
    final permAfter = await Native.checkPermissions();
    setState(() {
      _items = list;
      _denied = list.isEmpty && permAfter['media'] != true;
      _loading = false;
    });
  }

  Future<void> _openSystemPicker() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final r = await Native.pickVideo();
      if (!mounted) return;
      if (r == null) {
        setState(() => _importing = false);
        return;
      }
      final path = r['path'] as String?;
      if (path == null) {
        setState(() => _importing = false);
        return;
      }
      final createdMs = (r['createdMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      Navigator.of(context).pop(
        VideoPickResult(path: path, createdMs: createdMs),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        showAppNotice(context, '导入失败：$e', AppNoticeKind.error);
      }
    }
  }

  Future<void> _pick(Map<String, dynamic> item) async {
    if (_importing) return;
    final uri = (item['uri'] ?? '').toString();
    if (uri.isEmpty) return;
    setState(() => _importing = true);
    final r = await Native.importVideoUri(uri);
    if (!mounted) return;
    if (r == null) {
      setState(() => _importing = false);
      showAppNotice(context, '读取这段视频失败，可改用系统相册选择。',
          AppNoticeKind.error);
      return;
    }
    final path = r['path'] as String?;
    if (path == null) {
      setState(() => _importing = false);
      showAppNotice(context, '读取这段视频失败，可改用系统相册选择。',
          AppNoticeKind.error);
      return;
    }
    final createdMs = (r['createdMs'] as num?)?.toInt() ??
        (item['dateTakenMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    Navigator.of(context).pop(
      VideoPickResult(path: path, createdMs: createdMs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          s.t('选择视频', 'Choose video'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: s.t('刷新', 'Refresh'),
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            _body(),
          if (_importing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        S.of(context).t('正在读取视频…', 'Importing…'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final s = S.of(context);
    if (_items.isEmpty) {
      return ListView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 24, 16, 24),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.video_library_outlined,
                    size: 32, color: Colors.white70),
                const SizedBox(height: 10),
                Text(
                  _denied
                      ? s.t('没有读取相册的权限', 'No gallery permission')
                      : s.t('手机相册里还没有视频', 'No videos in gallery'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _denied
                      ? s.t(
                          '可以重新授权，或直接用系统相册选择这一段素材。',
                          'Grant access, or pick the clip with the system picker.',
                        )
                      : s.t(
                          '运动相机素材先导出到手机相册，或直接用系统相册选择。',
                          'Export camera clips to the gallery, or use the system picker.',
                        ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _openSystemPicker,
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(s.t('打开系统相册选择', 'Open system picker')),
                  ),
                ),
                if (_denied) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      onPressed: _load,
                      child: Text(s.t('重新授权并刷新', 'Grant access and refresh')),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: withAppBarTopInset(
        context,
        const EdgeInsets.fromLTRB(16, 8, 16, 28),
      ),
      children: [
        Text(
          s.t('手机相册 · 最近视频', 'Gallery · recent videos'),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          s.t(
            '运动相机素材先从相机 App / Wi-Fi 导出到手机相册。',
            'Export camera clips to your gallery first.',
          ),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.32,
          ),
          itemCount: _items.length,
          itemBuilder: (ctx, i) => _videoCard(_items[i]),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _openSystemPicker,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(s.t('从系统相册选择', 'Pick from system gallery')),
          ),
        ),
      ],
    );
  }

  Widget _videoCard(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'video').toString();
    final durMs = (item['durationMs'] as num?)?.toInt() ?? 0;
    final thumb = (item['thumbPath'] ?? '').toString();
    final hasThumb = thumb.isNotEmpty && File(thumb).existsSync();
    return Material(
      color: const Color(0xFF1B1B1B),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _pick(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasThumb)
              Image.file(
                File(thumb),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ThumbFallback(),
              )
            else
              const _ThumbFallback(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                  stops: [0.5, 1],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _fmtDur(durMs),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.play_circle_fill,
                size: 22,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDur(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF232323),
      child: Center(
        child: Icon(
          Icons.videocam_outlined,
          size: 26,
          color: Colors.white24,
        ),
      ),
    );
  }
}
