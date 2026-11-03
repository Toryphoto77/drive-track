/// 沿途照片打点（v0.1.7 追加项 2，新文件）。
///
/// 设计要点（不编造、不上传）：
/// - [PhotoPoint] 只存轨迹点坐标 + 时间 + 本机照片路径 + 备注；
///   无照片也可先打点，之后在详情相册里再附照片。
/// - 照片只存本机：相册选取复用现有 `Native.pickFile('image')`
///   （ACTION_GET_CONTENT），但该通道固定覆写 filesDir/avatar.jpg，
///   多个照片点绝不能直接存它返回的路径；本文件在拿到路径后立刻
///   拷贝到 filesDir/photo_points/photo_<时间戳>_<序号>.jpg 唯一副本，
///   之后各点互不覆盖。拍照走新增原生通道 `Native.takePhoto()`，
///   直接写进同一目录，同样是唯一文件。
/// - 删除语义：删单个照片点 / 删整趟行程时，只删 photo_points/
///   目录下的本 App 副本（见 [isManagedPhotoCopy] 守卫），绝不删
///   用户相册原图——原图从未被直接引用，pickFile 本来就是拷贝。
/// - 地图呈现：本文件与详情卡里的地图均为“示意轨迹 + 照片点”
///   CustomPaint，不叠加在 RefinedMap 瓦片地图上（RefinedMap
///   目前没有标记点接口，改它会动到所有地图调用方）；坐标与
///   时间、备注均为真实数据，不画假点。
/// - 上限：一趟最多 50 个照片点，每点最多 1 张照片；再附照片时
///   替换旧图并删旧副本，不囤多图。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'import_style.dart';
import 'native.dart';

/// 一趟行程最多照片点数；超限时记录页按钮拒绝并提示，不静默丢弃。
const int kMaxPhotoPointsPerTrip = 50;

/// 沿途照片点：坐标 + 时间必填，照片与备注可空。
class PhotoPoint {
  final double lat;
  final double lon;
  final int timeMs;
  final String? photoPath;
  final String? note;

  const PhotoPoint({
    required this.lat,
    required this.lon,
    required this.timeMs,
    this.photoPath,
    this.note,
  });

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;
  bool get hasNote => note != null && note!.trim().isNotEmpty;

  PhotoPoint copyWith({
    double? lat,
    double? lon,
    int? timeMs,
    String? photoPath,
    bool clearPhoto = false,
    String? note,
    bool clearNote = false,
  }) =>
      PhotoPoint(
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        timeMs: timeMs ?? this.timeMs,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        note: clearNote ? null : (note ?? this.note),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        't': timeMs,
        if (photoPath != null) 'photo': photoPath,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  static PhotoPoint fromJson(Map<String, dynamic> j) => PhotoPoint(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
        timeMs: (j['t'] as num?)?.toInt() ?? 0,
        photoPath: j['photo'] as String?,
        note: j['note'] as String?,
      );
}

String _fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';
}

String _fmtDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}月${d.day}日 ${_fmtClock(ms)}';
}

/// 本 App 管理的照片副本目录（filesDir 下），与头像/视频目录分开。
Future<Directory> _photoPointsDir(String filesDir) async {
  final dir = Directory('$filesDir/photo_points');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// 守卫：只有 photo_points/ 目录下的路径才算本 App 副本，才允许删除。
/// 相册原图、头像、视频等一律不在此列，删点 / 删行程时绝不动它们。
bool isManagedPhotoCopy(String path, String filesDir) {
  final dir = '$filesDir/photo_points/';
  return path.startsWith(dir) && !path.substring(dir.length).contains('/');
}

/// 把 pickFile('image') 返回的临时拷贝转存为唯一副本。
/// 返回唯一副本路径；源文件不是原图（pickFile 已从 content Uri 拷贝
/// 过一次），转存后源文件（avatar.jpg）留给头像流程复用，不删除。
Future<String?> copyPickedToPhotoPoints(String pickedPath) async {
  try {
    final filesDir = await Native.getFilesDir();
    final dir = await _photoPointsDir(filesDir);
    final src = File(pickedPath);
    if (!await src.exists()) return null;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    var dst = File('${dir.path}/photo_${stamp}.jpg');
    var n = 0;
    while (await dst.exists()) {
      n++;
      dst = File('${dir.path}/photo_${stamp}_$n.jpg');
    }
    await src.copy(dst.path);
    return dst.path;
  } catch (_) {
    return null;
  }
}

/// 删单个照片点 / 删行程时删副本：只删守卫通过的路径，其余一律不动。
Future<void> deleteManagedPhotoCopy(String? path, String filesDir) async {
  if (path == null || !isManagedPhotoCopy(path, filesDir)) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// 附照片二选一：拍照（新增原生通道）或相册选取（现有通道 + 转存）。
/// 返回最终的本 App 副本路径；用户取消 / 权限被拒 / 失败返回 null，
/// 调用方只提示、不把失败写成照片点。
/// 拍照前先走现有分步权限 `requestStep('camera')`（与同步视频同一步），
/// 权限未授予时不拉相机、不假装拍了。
Future<String?> pickOrTakePhoto(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('附照片'),
      content: const Text('拍照直接存本机；相册选取只拷贝副本，不动原图。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'camera'),
            child: const Text('拍照')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            child: const Text('相册选取')),
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;
  try {
    if (choice == 'camera') {
      final cam = await Native.requestStep('camera');
      if (cam['camera'] != true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('未授予相机权限，已取消拍照')));
        }
        return null;
      }
      final path = await Native.takePhoto();
      if (path == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('拍照已取消或失败，未附照片')));
      }
      return path;
    }
    final picked = await Native.pickFile('image');
    if (picked == null) return null;
    final copied = await copyPickedToPhotoPoints(picked);
    if (copied == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('照片转存失败，未附照片')));
    }
    return copied;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('附照片失败：$e')));
    }
    return null;
  }
}

/// 示意轨迹 + 照片点画笔：轨迹归一化连线，照片点为带序号的红点。
/// 不是瓦片地图；点少于 2 个时只画照片点，不画假轨迹。
class PhotoPointsMapPainter extends CustomPainter {
  final List<({double lat, double lon})> track;
  final List<PhotoPoint> photos;
  final int? selectedIndex;

  const PhotoPointsMapPainter({
    required this.track,
    required this.photos,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 18.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    if (w <= 0 || h <= 0) return;
    final allLat = <double>[
      for (final p in track) p.lat,
      for (final p in photos) p.lat,
    ];
    final allLon = <double>[
      for (final p in track) p.lon,
      for (final p in photos) p.lon,
    ];
    if (allLat.isEmpty) return;
    var minLat = allLat.reduce(math.min), maxLat = allLat.reduce(math.max);
    var minLon = allLon.reduce(math.min), maxLon = allLon.reduce(math.max);
    if ((maxLat - minLat).abs() < 1e-9) {
      maxLat += 0.001;
      minLat -= 0.001;
    }
    if ((maxLon - minLon).abs() < 1e-9) {
      maxLon += 0.001;
      minLon -= 0.001;
    }
    Offset xy(double lat, double lon) => Offset(
          pad + w * (lon - minLon) / (maxLon - minLon),
          pad + h * (1 - (lat - minLat) / (maxLat - minLat)),
        );
    if (track.length >= 2) {
      final path = Path()..moveTo(xy(track.first.lat, track.first.lon).dx, xy(track.first.lat, track.first.lon).dy);
      for (var i = 1; i < track.length; i++) {
        final o = xy(track[i].lat, track[i].lon);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    for (var i = 0; i < photos.length; i++) {
      final o = xy(photos[i].lat, photos[i].lon);
      final sel = selectedIndex == i;
      canvas.drawCircle(
          o, sel ? 15 : 12, Paint()..color = const Color(0xFFE10600));
      canvas.drawCircle(o, sel ? 15 : 12,
          Paint()..color = Colors.white.withValues(alpha: 0.25));
      final tp = TextPainter(
          text: TextSpan(
              text: '${i + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(PhotoPointsMapPainter old) =>
      old.track != track || old.photos != photos || old.selectedIndex != selectedIndex;
}

/// 行程相册页：顶部示意地图 + 照片点列表，点开看大图 / 改备注 / 删点。
/// 不读 store：初始点与轨迹由调用方传入，改动经 [onChanged] 回传，
/// 由调用方（详情页）落盘；onChanged 为 null 时只看不改。
class TripAlbumPage extends StatefulWidget {
  final List<PhotoPoint> initialPhotoPoints;
  final List<({double lat, double lon})> trackPoints;
  final String title;
  final ValueChanged<List<PhotoPoint>>? onChanged;

  const TripAlbumPage({
    super.key,
    required this.initialPhotoPoints,
    required this.trackPoints,
    this.title = '行程相册',
    this.onChanged,
  });

  @override
  State<TripAlbumPage> createState() => _TripAlbumPageState();
}

class _TripAlbumPageState extends State<TripAlbumPage> {
  late List<PhotoPoint> _points = List.of(widget.initialPhotoPoints);
  int? _selected;

  void _emit() => widget.onChanged?.call(List.of(_points));

  Future<void> _attach(int i) async {
    final path = await pickOrTakePhoto(context);
    if (path == null || !mounted) return;
    final old = _points[i].photoPath;
    setState(() => _points[i] = _points[i].copyWith(photoPath: path));
    _emit();
    if (old != null) {
      try {
        final dir = await Native.getFilesDir();
        await deleteManagedPhotoCopy(old, dir);
      } catch (_) {}
    }
  }

  Future<void> _editNote(int i) async {
    final ctrl = TextEditingController(text: _points[i].note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备注'),
        content: TextField(
            controller: ctrl,
            maxLength: 200,
            decoration: const InputDecoration(hintText: '例如：垭口风很大，在此停车拍照')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final text = ctrl.text.trim();
    setState(() => _points[i] =
        text.isEmpty ? _points[i].copyWith(clearNote: true) : _points[i].copyWith(note: text));
    _emit();
  }

  Future<void> _deletePoint(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个照片点？'),
        content: const Text('只删本 App 内的打点与副本照片，不删用户相册原图。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final old = _points[i].photoPath;
    setState(() {
      _points.removeAt(i);
      if (_selected != null && _selected! >= _points.length) _selected = null;
    });
    _emit();
    if (old != null) {
      try {
        final dir = await Native.getFilesDir();
        await deleteManagedPhotoCopy(old, dir);
      } catch (_) {}
    }
  }

  void _view(int i) {
    final p = _points[i];
    if (!p.hasPhoto) {
      _attach(i);
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _PhotoViewerPage(point: p, index: i)));
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onChanged != null;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(title: Text('${widget.title}（${_points.length}）')),
      body: _points.isEmpty
          ? const Center(
              child: Text('暂无照片点\n记录中点“拍照打点”可先存坐标，\n结束后在这里附照片',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)))
          : Column(children: [
              Container(
                height: 180,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: CustomPaint(
                  size: const Size(double.infinity, 180),
                  painter: PhotoPointsMapPainter(
                      track: widget.trackPoints,
                      photos: _points,
                      selectedIndex: _selected),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('示意地图：白线为轨迹，红点为照片点（序号与下方列表一致），不是瓦片地图',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _points.length,
                  itemBuilder: (ctx, i) {
                    final p = _points[i];
                    // v1.0.2：照片导入入口只换 UI 为统一导入画风
                    // （ImportCard 大卡 #1E1E1E + 圆角 16）；_attach
                    // （pickOrTakePhoto / 唯一副本转存 / 旧副本删除）未动。
                    return ImportCard(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() => _selected = i);
                          _view(i);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: p.hasPhoto &&
                                      File(p.photoPath!).existsSync()
                                  ? Image.file(File(p.photoPath!),
                                      width: 64,
                                      height: 64,
                                      fit: BoxFit.cover,
                                      cacheWidth: 128,
                                      errorBuilder: (_, __, ___) =>
                                          _photoPlaceholder())
                                  : _photoPlaceholder(),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${i + 1} · ${_fmtDateTime(p.timeMs)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    if (p.hasNote)
                                      Text(p.note!,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    if (!p.hasPhoto && editable)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: ImportPrimaryButton(
                                            label: '附照片',
                                            expanded: false,
                                            onPressed: () => _attach(i),
                                          ),
                                        ),
                                      )
                                    else if (!p.hasPhoto)
                                      const Text('暂无照片',
                                          style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12)),
                                  ]),
                            ),
                            if (editable)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert,
                                    color: Colors.white54),
                                onSelected: (v) {
                                  if (v == 'photo') _attach(i);
                                  if (v == 'note') _editNote(i);
                                  if (v == 'del') _deletePoint(i);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'photo',
                                      child: Text('附照片 / 换照片')),
                                  PopupMenuItem(
                                      value: 'note', child: Text('写备注')),
                                  PopupMenuItem(
                                      value: 'del', child: Text('删除该点')),
                                ],
                              ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }

  Widget _photoPlaceholder() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: importInnerCardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: importBorderColor),
        ),
        child: const Icon(Icons.photo_camera, color: Colors.white54),
      );
}

/// 大图页：原图查看 + 备注 + 坐标时间；不做裁剪/滤镜/分享。
class _PhotoViewerPage extends StatelessWidget {
  final PhotoPoint point;
  final int index;
  const _PhotoViewerPage({required this.point, required this.index});

  @override
  Widget build(BuildContext context) {
    final f = point.photoPath == null ? null : File(point.photoPath!);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text('照片点 ${index + 1} · ${_fmtDateTime(point.timeMs)}')),
      body: Column(children: [
        Expanded(
          child: Center(
            child: f != null && f.existsSync()
                ? Image.file(f, fit: BoxFit.contain)
                : const Text('照片文件已不在本机（仅存引用时会出现）',
                    style: TextStyle(color: Colors.white54)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${point.lat.toStringAsFixed(6)}, ${point.lon.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.white70)),
                if (point.hasNote) ...[
                  const SizedBox(height: 6),
                  Text(point.note!,
                      style: const TextStyle(color: Colors.white)),
                ],
                const SizedBox(height: 4),
                const Text('照片只存本机，不上传',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
        ),
      ]),
    );
  }
}
