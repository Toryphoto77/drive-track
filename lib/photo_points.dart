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
/// v1.2.0：照片点升级为通用事件标记——新增 type/title/id，
/// TripAlbumPage 改为按时间排序的事件时间线 + 类型筛选 chips +
/// 分类型颜色 + focusPointId/initialPointId 定位参数；
/// 旧数据默认兼容（有照片 photo / 无照片 marker，id 由坐标时间派生）。
/// 入口文案改名、store 层上限、详情卡片接线由收口阶段统一做，
/// 本文件只提供上述 API，不动 main/store/models。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'app_notice.dart';

import 'import_style.dart';
import 'native.dart';

/// 一趟行程最多照片点数；超限时记录页按钮拒绝并提示，不静默丢弃。
const int kMaxPhotoPointsPerTrip = 50;

/// 标题与备注长度上限（v1.2.0 事件标记新增标题时定下；
/// 备注 200 字上限自 v0.1.7 沿用不变）。
const int kMaxEventMarkerTitleLength = 50;
const int kMaxPhotoPointNoteLength = 200;

/// v1.2.0 事件标记类型：小而通用，与传感器事件 [TripEvent]
/// （lib/models.dart，带 G 值、参与评分/事件统计）严格区分——
/// 这里的标记只是“人在某时某地记了一笔”，不进评分、不进事件统计。
/// 颜色固定不变，收口阶段与详情卡片共用同一映射，不要各处另起一套。
enum PhotoPointType {
  photo,
  marker,
  incident,
  fuel,
  rest,
  view;

  /// 中文标签。
  String get label => switch (this) {
        PhotoPointType.photo => '照片',
        PhotoPointType.marker => '标记',
        PhotoPointType.incident => '状况',
        PhotoPointType.fuel => '加油',
        PhotoPointType.rest => '休息',
        PhotoPointType.view => '风景',
      };

  /// 固定颜色：时间线 chip、卡片色点、示意地图圆点共用。
  Color get color => switch (this) {
        PhotoPointType.photo => const Color(0xFFE10600),
        PhotoPointType.marker => const Color(0xFF9E9E9E),
        PhotoPointType.incident => const Color(0xFFFF6D00),
        PhotoPointType.fuel => const Color(0xFFFFC107),
        PhotoPointType.rest => const Color(0xFF2196F3),
        PhotoPointType.view => const Color(0xFF00BFA5),
      };

  IconData get icon => switch (this) {
        PhotoPointType.photo => Icons.photo_camera,
        PhotoPointType.marker => Icons.place,
        PhotoPointType.incident => Icons.warning_amber,
        PhotoPointType.fuel => Icons.local_gas_station,
        PhotoPointType.rest => Icons.coffee,
        PhotoPointType.view => Icons.landscape,
      };
}

/// 按 JSON 名字解析类型；未知 / 空名字返回 null（由调用方走默认规则）。
PhotoPointType? photoPointTypeFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final t in PhotoPointType.values) {
    if (t.name == name) return t;
  }
  return null;
}

/// 沿途照片点（v1.2.0 起为通用事件标记）：坐标 + 时间必填，
/// 照片、备注、标题、类型、id 可空/可默认。
/// - [type] 为 null 时不存歧义：[effectiveType] 按“有照片则 photo，
///   否则 marker”默认，旧数据（无 type 键）因此自动归类。
/// - [id] 为 null 时 [resolvedId] 由 lat/lon/timeMs 生成稳定 id，
///   不用随机 uuid，同一旧数据每次加载得到同一个 id，排序/过滤后
///   仍能定位到同一个点；两个坐标时间完全相同的点会共享 id，
///   属极端重合场景，调用方不应依赖它做唯一键之外的事。
/// - [title] 建议 ≤50 字，[note] 仍限 200 字；超长部分在
///   fromJson / copyWith / toJson 时截断，不静默存超长文本。
class PhotoPoint {
  final double lat;
  final double lon;
  final int timeMs;
  final String? photoPath;
  final String? note;
  final PhotoPointType? type;
  final String? title;
  final String? id;

  const PhotoPoint({
    required this.lat,
    required this.lon,
    required this.timeMs,
    this.photoPath,
    this.note,
    this.type,
    this.title,
    this.id,
  });

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;
  bool get hasNote => note != null && note!.trim().isNotEmpty;
  bool get hasTitle => title != null && title!.trim().isNotEmpty;

  /// 生效类型：显式 type 优先，否则有照片为 photo、无照片为 marker。
  PhotoPointType get effectiveType =>
      type ?? (hasPhoto ? PhotoPointType.photo : PhotoPointType.marker);

  /// 类型名字符串（与 TripEvent.kind 的字符串风格对齐，
  /// 但两者不互通：本标记不进传感器事件统计）。
  String get kind => effectiveType.name;

  /// 稳定 id：显式 id 优先，否则由坐标 + 时间派生。
  String get resolvedId => id ?? stableId(lat, lon, timeMs);

  /// 由 lat/lon/timeMs 派生的稳定 id（纯函数，可单测）。
  static String stableId(double lat, double lon, int timeMs) =>
      'pp_${lat.toStringAsFixed(6)}_${lon.toStringAsFixed(6)}_$timeMs';

  static String? _trunc(String? s, int max) =>
      s == null ? null : (s.length <= max ? s : s.substring(0, max));

  PhotoPoint copyWith({
    double? lat,
    double? lon,
    int? timeMs,
    String? photoPath,
    bool clearPhoto = false,
    String? note,
    bool clearNote = false,
    PhotoPointType? type,
    bool clearType = false,
    String? title,
    bool clearTitle = false,
    String? id,
  }) =>
      PhotoPoint(
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        timeMs: timeMs ?? this.timeMs,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        note: clearNote
            ? null
            : _trunc(note ?? this.note, kMaxPhotoPointNoteLength),
        type: clearType ? null : (type ?? this.type),
        title: clearTitle
            ? null
            : _trunc(title ?? this.title, kMaxEventMarkerTitleLength),
        id: id ?? this.id,
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        't': timeMs,
        if (photoPath != null) 'photo': photoPath,
        if (note != null && note!.isNotEmpty)
          'note': _trunc(note, kMaxPhotoPointNoteLength),
        // v1.2.0 新增 JSON 键：type / title / id。
        // 显式 type 才写键（null 时不写，加载端走默认规则）；
        // id 恒写 resolvedId，保证旧数据一经加载落盘就有稳定 id。
        if (type != null) 'type': type!.name,
        if (title != null && title!.isNotEmpty)
          'title': _trunc(title, kMaxEventMarkerTitleLength),
        'id': resolvedId,
      };

  static PhotoPoint fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble() ?? 0;
    final lon = (j['lon'] as num?)?.toDouble() ?? 0;
    final timeMs = (j['t'] as num?)?.toInt() ?? 0;
    final photoPath = j['photo'] as String?;
    // 旧数据兼容：无 type 键时 type 保持 null，effectiveType 默认
    // 有照片 photo / 无照片 marker；同时接受 'kind' 作 type 的别名键。
    final parsedType = photoPointTypeFromName(j['type'] as String?) ??
        photoPointTypeFromName(j['kind'] as String?);
    final rawId = j['id'] as String?;
    return PhotoPoint(
      lat: lat,
      lon: lon,
      timeMs: timeMs,
      photoPath: photoPath,
      note: _trunc(j['note'] as String?, kMaxPhotoPointNoteLength),
      type: parsedType,
      title: _trunc(j['title'] as String?, kMaxEventMarkerTitleLength),
      id: (rawId != null && rawId.isNotEmpty)
          ? rawId
          : stableId(lat, lon, timeMs),
    );
  }
}

/// 按时间升序排（时间相同按稳定 id 二次排序，保证顺序确定）；
/// 不改原列表，返回新列表。时间线页与调用方共用同一排序。
List<PhotoPoint> sortPhotoPointsByTime(List<PhotoPoint> points) {
  final sorted = List<PhotoPoint>.of(points);
  sorted.sort((a, b) {
    final byTime = a.timeMs.compareTo(b.timeMs);
    if (byTime != 0) return byTime;
    return a.resolvedId.compareTo(b.resolvedId);
  });
  return sorted;
}

/// 按类型筛选：[type] 为 null 时返回全部（“全部” chip 对应此分支）。
List<PhotoPoint> filterPhotoPointsByType(
    List<PhotoPoint> points, PhotoPointType? type) {
  if (type == null) return List<PhotoPoint>.of(points);
  return points.where((p) => p.effectiveType == type).toList();
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
      content: const Text('拍照存本机；相册选取只拷贝副本，不动原图。'),
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
          showAppNotice(context, '未授予相机权限，已取消拍照', AppNoticeKind.error);
        }
        return null;
      }
      final path = await Native.takePhoto();
      if (path == null && context.mounted) {
        showAppNotice(context, '拍照已取消或失败，未附照片', AppNoticeKind.error);
      }
      return path;
    }
    final picked = await Native.pickFile('image');
    if (picked == null) return null;
    final copied = await copyPickedToPhotoPoints(picked);
    if (copied == null && context.mounted) {
      showAppNotice(context, '照片转存失败，未附照片', AppNoticeKind.error);
    }
    return copied;
  } catch (e) {
    if (context.mounted) {
      showAppNotice(context, '附照片失败：$e', AppNoticeKind.error);
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
      // v1.2.0：圆点按事件类型着色（photo 沿用旧红），不再全红。
      canvas.drawCircle(
          o, sel ? 15 : 12, Paint()..color = photos[i].effectiveType.color);
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

/// 行程相册页（v1.2.0 起为事件时间线）：顶部示意地图 + 按时间排序的
/// 事件列表，带类型筛选 chips 与分类型颜色，点开看大图 / 改标题 /
/// 改备注 / 删点。内部一律按 [PhotoPoint.resolvedId] 定位，
/// 不再用列表下标做身份，排序/过滤后操作不会错位。
/// 不读 store：初始点与轨迹由调用方传入，改动经 [onChanged] 回传，
/// 由调用方（详情页）落盘；onChanged 为 null 时只看不改。
/// [focusPointId]：打开后定位到指定点（收口阶段从详情卡片点缩略图
/// 时传入该点的 resolvedId）；[initialPointId] 为同义旧名，
/// focusPointId 优先，两者都空时不定位。
class TripAlbumPage extends StatefulWidget {
  final List<PhotoPoint> initialPhotoPoints;
  final List<({double lat, double lon})> trackPoints;
  final String title;
  final ValueChanged<List<PhotoPoint>>? onChanged;
  final String? focusPointId;
  final String? initialPointId;

  const TripAlbumPage({
    super.key,
    required this.initialPhotoPoints,
    required this.trackPoints,
    this.title = '行程相册',
    this.onChanged,
    this.focusPointId,
    this.initialPointId,
  });

  @override
  State<TripAlbumPage> createState() => _TripAlbumPageState();
}

class _TripAlbumPageState extends State<TripAlbumPage> {
  // 时间升序（sortPhotoPointsByTime），与传入顺序无关。
  late List<PhotoPoint> _points =
      sortPhotoPointsByTime(widget.initialPhotoPoints);
  String? _selectedId;
  PhotoPointType? _filter;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  /// 定位目标 id：focusPointId 优先，initialPointId 兜底。
  String? get _focusId {
    final f = widget.focusPointId;
    if (f != null && f.isNotEmpty) return f;
    final i = widget.initialPointId;
    if (i != null && i.isNotEmpty) return i;
    return null;
  }

  /// 当前筛选后的时间线（仍按时间升序）。
  List<PhotoPoint> get _visible =>
      filterPhotoPointsByType(_points, _filter);

  @override
  void initState() {
    super.initState();
    _selectedId = _focusId;
    final focus = _focusId;
    if (focus != null && _points.any((p) => p.resolvedId == focus)) {
      // 首帧后滚到目标卡片；目标被筛选外时不滚动（不静默改筛选）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final key = _itemKeys[focus];
        final ctx = key?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged?.call(List.of(_points));

  int _indexOfId(String id) =>
      _points.indexWhere((p) => p.resolvedId == id);

  GlobalKey _keyFor(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey());

  Future<void> _attach(PhotoPoint point) async {
    final path = await pickOrTakePhoto(context);
    if (path == null || !mounted) return;
    final i = _indexOfId(point.resolvedId);
    if (i < 0) return;
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

  Future<void> _editNote(PhotoPoint point) async {
    final i = _indexOfId(point.resolvedId);
    if (i < 0) return;
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
    final j = _indexOfId(point.resolvedId);
    if (j < 0) return;
    setState(() => _points[j] =
        text.isEmpty ? _points[j].copyWith(clearNote: true) : _points[j].copyWith(note: text));
    _emit();
  }

  Future<void> _editTitle(PhotoPoint point) async {
    final i = _indexOfId(point.resolvedId);
    if (i < 0) return;
    final ctrl = TextEditingController(text: _points[i].title ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标题'),
        content: TextField(
            controller: ctrl,
            maxLength: 50,
            decoration:
                const InputDecoration(hintText: '例如：垭口停车拍照')),
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
    final j = _indexOfId(point.resolvedId);
    if (j < 0) return;
    setState(() => _points[j] = text.isEmpty
        ? _points[j].copyWith(clearTitle: true)
        : _points[j].copyWith(title: text));
    _emit();
  }

  Future<void> _changeType(PhotoPoint point, PhotoPointType type) async {
    final i = _indexOfId(point.resolvedId);
    if (i < 0) return;
    setState(() => _points[i] = _points[i].copyWith(type: type));
    _emit();
  }

  Future<void> _deletePoint(PhotoPoint point) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个事件？'),
        content: const Text('只删本 App 内的打点与副本照片，不删相册原图。'),
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
    final i = _indexOfId(point.resolvedId);
    if (i < 0) return;
    final old = _points[i].photoPath;
    setState(() {
      _points.removeAt(i);
      if (_selectedId == point.resolvedId) _selectedId = null;
    });
    _emit();
    if (old != null) {
      try {
        final dir = await Native.getFilesDir();
        await deleteManagedPhotoCopy(old, dir);
      } catch (_) {}
    }
  }

  void _view(PhotoPoint point, int timelineIndex) {
    if (!point.hasPhoto) {
      _attach(point);
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                _PhotoViewerPage(point: point, index: timelineIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onChanged != null;
    final visible = _visible;
    final selectedIndex =
        _selectedId == null ? null : visible.indexWhere((p) => p.resolvedId == _selectedId);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text('${widget.title}（${_points.length}）')),
      body: _points.isEmpty
          ? const Center(
              child: Text('暂无照片点\n记录中点“事件标记”添加，结束后可附照片',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)))
          : Column(children: [
              Container(
                height: 180,
                margin: EdgeInsets.fromLTRB(16, 16 + appBarTopInset(context), 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: CustomPaint(
                  size: const Size(double.infinity, 180),
                  painter: PhotoPointsMapPainter(
                      track: widget.trackPoints,
                      photos: visible,
                      selectedIndex:
                          selectedIndex != null && selectedIndex >= 0 ? selectedIndex : null),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('示意地图：白线为轨迹，彩点为事件',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
              ),
              const SizedBox(height: 8),
              // 类型筛选 chips：全部 + 6 种类型；筛选只影响展示，
              // 操作仍按 resolvedId 落到 _points，不会错位。
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _filterChip(null, '全部'),
                  for (final t in PhotoPointType.values)
                    _filterChip(t, t.label),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text('该类型暂无事件',
                            style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: visible.length,
                        itemBuilder: (ctx, i) {
                          final p = visible[i];
                          final type = p.effectiveType;
                          final isFocus = p.resolvedId == _focusId;
                          // v1.0.2：照片导入入口只换 UI 为统一导入画风
                          // （ImportCard 大卡 #1E1E1E + 圆角 16）；_attach
                          // （pickOrTakePhoto / 唯一副本转存 / 旧副本删除）未动。
                          return Container(
                            key: _keyFor(p.resolvedId),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: isFocus
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: type.color, width: 1.5),
                                  )
                                : null,
                            child: ImportCard(
                              margin: EdgeInsets.zero,
                              padding: EdgeInsets.zero,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(
                                      () => _selectedId = p.resolvedId);
                                  _view(p, i);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: p.hasPhoto &&
                                              File(p.photoPath!)
                                                  .existsSync()
                                          ? Image.file(
                                              File(p.photoPath!),
                                              width: 64,
                                              height: 64,
                                              fit: BoxFit.cover,
                                              cacheWidth: 128,
                                              errorBuilder: (_, __,
                                                      ___) =>
                                                  _photoPlaceholder(
                                                      type),
                                            )
                                          : _photoPlaceholder(type),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: type.color
                                                      .withValues(
                                                          alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8),
                                                ),
                                                child: Text(type.label,
                                                    style: TextStyle(
                                                        color: type.color,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                    p.hasTitle
                                                        ? p.title!
                                                        : '${i + 1} · ${_fmtDateTime(p.timeMs)}',
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                              ),
                                            ]),
                                            if (p.hasTitle)
                                              Text(
                                                  '${i + 1} · ${_fmtDateTime(p.timeMs)}',
                                                  style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12)),
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
                                                padding:
                                                    const EdgeInsets.only(
                                                        top: 6),
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: ImportPrimaryButton(
                                                    label: '附照片',
                                                    expanded: false,
                                                    onPressed: () =>
                                                        _attach(p),
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
                                          if (v == 'photo') _attach(p);
                                          if (v == 'title') _editTitle(p);
                                          if (v == 'note') _editNote(p);
                                          if (v == 'del') _deletePoint(p);
                                          if (v.startsWith('type:')) {
                                            final t =
                                                photoPointTypeFromName(
                                                    v.substring(5));
                                            if (t != null) {
                                              _changeType(p, t);
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                              value: 'photo',
                                              child: Text('附照片 / 换照片')),
                                          const PopupMenuItem(
                                              value: 'title',
                                              child: Text('改标题')),
                                          const PopupMenuItem(
                                              value: 'note',
                                              child: Text('写备注')),
                                          for (final t
                                              in PhotoPointType.values)
                                            PopupMenuItem(
                                                value: 'type:${t.name}',
                                                child: Text(
                                                    '设为${t.label}${t == type ? ' ✓' : ''}')),
                                          const PopupMenuItem(
                                              value: 'del',
                                              child: Text('删除该点')),
                                        ],
                                      ),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }

  Widget _filterChip(PhotoPointType? type, String label) {
    final selected = _filter == type;
    final color = type?.color ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = type),
        selectedColor: type == null
            ? Colors.white.withValues(alpha: 0.2)
            : color.withValues(alpha: 0.25),
        labelStyle: TextStyle(
            color: selected ? color : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal),
        backgroundColor: const Color(0xFF1E1E1E),
        side: BorderSide(
            color: selected ? color : const Color(0xFF2A2A2A)),
      ),
    );
  }

  Widget _photoPlaceholder([PhotoPointType? type]) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: importInnerCardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: importBorderColor),
        ),
        child: Icon(type?.icon ?? Icons.photo_camera,
            color: type?.color ?? Colors.white54),
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
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
          title: Text(point.hasTitle
              ? point.title!
              : '照片点 ${index + 1} · ${_fmtDateTime(point.timeMs)}')),
      body: Column(children: [
        Expanded(
          child: Center(
            child: f != null && f.existsSync()
                ? Image.file(f, fit: BoxFit.contain)
                : const Text('照片文件已不在本机',
                    style: TextStyle(color: Colors.white54)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${point.effectiveType.label} · ${_fmtDateTime(point.timeMs)}',
                    style: TextStyle(
                        color: point.effectiveType.color,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
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
