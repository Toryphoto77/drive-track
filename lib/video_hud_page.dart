/// 视频处理 / HUD 合成（v1.6.0，第 3 项 + 第 7 项）。
///
/// 场景：连接运动相机录完整场 → 完成赛道记录 → 回到行程详情，进本页。
///
/// 本页解决三件事：
/// 1. 对齐：把视频段与遥测时间轴对上（默认按文件名里的开录时间戳自动算，
///    可手动 ±0.1s 微调）；对齐结果实时反映到下方预览与导出文件里。
/// 2. 预览：按当前播放头取遥测值（速度 / 圈号 / 圈时 / G / 倾角），用最终
///    会出现在视频里的同一套排版画一遍，所见即所得。
/// 3. 出片：两条路——
///    - 手机内直接烧录（v1.6.0）：FFmpegKit 把 ASS 字幕烧进视频，硬件
///      H.264 编码，出成片后直接分享；可选 1080p 降分辨率控制体积与耗时；
///    - 三件套导出：`hud_<id>.ass` + `hud_<id>.json` + 合成说明，交给电脑
///      用 ffmpeg 处理（4K 素材想保留原画质时走这条）。
///
/// 边界：手机烧录会重新编码，原视频不改、成片另存；4K 原画在手机上很慢，
/// 默认建议 1080p。App 内不覆盖原文件，也不做联网上传。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_video/session.dart';
import 'package:ffmpeg_kit_flutter_new_video/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';
import 'app_notice.dart';
import 'dt_page_route.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'track_timing.dart';
import 'video_gallery_page.dart';
import 'video_import_match.dart';

const Color _kHudRed = Color(0xFFE10600);

/// HUD 版式。三种都只改“显示什么”，坐标系与安全区一致。
enum HudStyle { minimal, race, moto }

extension HudStyleLabel on HudStyle {
  String get label => switch (this) {
        HudStyle.minimal => '极简',
        HudStyle.race => '赛道',
        HudStyle.moto => '摩托',
      };
}

class VideoHudPage extends StatefulWidget {
  const VideoHudPage({
    super.key,
    required this.trip,
    required this.store,
    this.initialVideoPath,
  });

  final Trip trip;
  final Store store;

  /// 从某一段视频直接进入（记录详情 / 新导入流程都会带上）。
  /// 为空时默认第一段。
  final String? initialVideoPath;

  @override
  State<VideoHudPage> createState() => _VideoHudPageState();
}

class _VideoHudPageState extends State<VideoHudPage> {
  /// 本地可变副本：导入运动相机视频后刷新关联列表（widget.trip 是 final）。
  late Trip _trip;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    final p = widget.initialVideoPath;
    if (p != null) {
      final i = _trip.videoPaths.indexOf(p);
      if (i >= 0) {
        _segment = i;
      } else if (_trip.videoPaths.isNotEmpty) {
        // 导入流程会把素材重命名（imported_*.mp4 → trip_<ms>.mp4），
        // 传进来的旧路径已不在列表里。新追加的一段在末尾，直接选中它，
        // 否则会停在第 0 段，看起来像“选完视频什么都没发生”。
        _segment = _trip.videoPaths.length - 1;
      }
    }
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollOnce());
    _loadFrames();
  }

  @override
  void dispose() {
    _poll?.cancel();
    try {
      _channel?.invokeMethod('pause');
    } catch (_) {}
    super.dispose();
  }

  int _segment = 0;
  int _manualOffsetMs = 0;
  int _scrubMs = 0;

  /// 撤销 / 重做只记录手动对齐偏移（±步进）。
  final List<int> _offsetHistory = [];
  final List<int> _redoStack = [];

  // ---- 原生视频预览（复用 drivetrack/video_view 平台视图）----
  MethodChannel? _channel;
  Timer? _poll;
  bool _prepared = false;
  bool _playing = false;
  bool _dragging = false;
  int _playerMs = 0;
  int _playerDurationMs = 0;
  String? _playerError;
  List<String> _frames = const [];

  /// 底部弹层（对齐 / HUD / 导出）在父级 setState 后需要刷新自身。
  VoidCallback? _sheetRefresh;

  HudStyle _style = HudStyle.race;
  bool _showSpeed = true;
  bool _showLap = true;
  bool _showG = true;
  bool _showLean = false;
  bool _showBrand = true;
  bool _exporting = false;

  // ---- v1.6.0：手机内直接烧录（FFmpegKit）----
  bool _burning = false;
  double _burnProgress = 0;
  String _burnEncoder = '';
  String? _burnOutput;
  String? _burnError;
  int? _burnSessionId;
  /// 烧录输出高度档：null = 原画不缩放；1080 = 长边压到 1080p。
  int? _burnHeight = 1080;

  /// 导出起点：null = 行程开始；否则 = 第几圈（1 起）的开始。
  int? _trimLap;

  /// 当前时间轴选中的圈（null = 未选，时间轴显示全片）。
  int? _activeLap;

  /// 倾角只对摩托有意义：非摩托行程即便勾了也不输出。
  bool get _leanEnabled => _showLean && trip.mode == TripMode.moto;

  Trip get trip => _trip;

  List<String> get _videos => trip.videoPaths;

  /// v1.7.x：空态下从相册选一段视频关联到本行程，成功后刷新列表，
  /// 直接留在编辑页继续对齐 / HUD / 烧录。
  Future<void> _importVideo() async {
    final picked = await Navigator.of(context).push<VideoPickResult>(
      DtPageRoute(builder: (_) => const VideoGalleryPage()),
    );
    if (picked == null || !mounted) return;
    try {
      final linked = await linkVideoToTrip(
        widget.store,
        trip: _trip,
        videoPath: picked.path,
        createdMs: picked.createdMs,
      );
      if (linked != null && mounted) {
        setState(() {
          _trip = linked.trip;
          final i = linked.trip.videoPaths.indexOf(linked.path);
          _segment = i >= 0 ? i : linked.trip.videoPaths.length - 1;
          _manualOffsetMs = 0;
          _scrubMs = 0;
          _playerMs = 0;
          _frames = const [];
        });
        _loadFrames();
      }
    } catch (e) {
      if (mounted) showAppNotice(context, '$e', AppNoticeKind.error);
    }
  }

  int get _durationMs {
    final d = trip.endMs - trip.startMs;
    return d <= 0 ? 0 : d;
  }

  /// 自动对齐：优先用文件名里的开录时间戳（trip_<epoch>.mp4），
  /// 与行程开始时间之差即偏移；没有可解析时间戳就是 0（首帧对齐）。
  int _autoOffset(String path) {
    final base = path.split('/').last;
    final m = RegExp(r'trip_(\d+)\.mp4$').firstMatch(base);
    final fileMs = m == null ? null : int.tryParse(m.group(1)!);
    if (fileMs == null) return 0;
    final off = fileMs - trip.startMs;
    // 超过 10 分钟的偏移多半是文件名不是开录时间，按 0 处理并在页面提示。
    return off.abs() <= 10 * 60 * 1000 ? off : 0;
  }

  String get _currentPath {
    if (_videos.isEmpty) return '';
    final i = _segment < 0
        ? 0
        : (_segment >= _videos.length ? _videos.length - 1 : _segment);
    final path = _videos[i];
    if (File(path).existsSync()) return path;
    // 历史关联里的文件被移动 / 重命名后，回落到列表里第一个真实存在的
    // 文件，避免预览区只剩一个空框；全都缺失时仍返回原路径，
    // 由预览区给出“文件不存在，请重新导入”的明确提示。
    for (final p in _videos) {
      if (File(p).existsSync()) return p;
    }
    return path;
  }

  int get _offsetMs => _autoOffset(_currentPath) + _manualOffsetMs;

  /// 播放头对应的行程时间。
  int get _tripMs => trip.startMs + _offsetMs + _scrubMs;

  List<Lap> get _laps {
    final list = <Lap>[];
    for (final j in trip.lapsJson) {
      try {
        list.add(Lap.fromJson(j));
      } catch (_) {
        // 旧数据字段缺失时跳过，不让 HUD 页面打不开。
      }
    }
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    return list;
  }

  TrackPoint? _pointAt(int tripMs) {
    final pts = trip.points;
    if (pts.isEmpty) return null;
    var lo = 0, hi = pts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (pts[mid].timeMs < tripMs) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final i = lo < 0
        ? 0
        : (lo >= pts.length ? pts.length - 1 : lo);
    return pts[i];
  }

  int get _exportStartTripMs {
    final laps = _laps;
    final n = _trimLap;
    if (n != null && n >= 1 && n <= laps.length) return laps[n - 1].startMs;
    return trip.startMs;
  }

  int get _exportEndTripMs => trip.endMs;

  String _fmtLap(int ms) {
    final total = ms.abs();
    final m = total ~/ 60000;
    final s = (total % 60000) / 1000;
    return m > 0
        ? '$m:${s.toStringAsFixed(2).padLeft(5, '0')}'
        : s.toStringAsFixed(2);
  }

  String _assTime(int ms) {
    final t = ms < 0 ? 0 : ms;
    final h = t ~/ 3600000;
    final m = (t % 3600000) ~/ 60000;
    final s = (t % 60000) ~/ 1000;
    final cs = (t % 1000) ~/ 10;
    return '$h:${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  /// 当前时刻该显示的 HUD 文本（预览与 ASS 共用同一套取数逻辑）。
  _HudFrame _frameAt(int tripMs) {
    final p = _pointAt(tripMs);
    final speedKmh = (p == null ? 0.0 : p.speed * 3.6);
    final g = p == null ? 0.0 : p.combinedG;
    final lean = p == null ? 0.0 : p.roll;
    final laps = _laps;
    var lapNo = 0;
    var lapElapsed = 0;
    for (final l in laps) {
      if (tripMs >= l.startMs) {
        lapNo = l.number;
        lapElapsed = tripMs - l.startMs;
      }
    }
    return _HudFrame(
      speedKmh: speedKmh,
      g: g,
      lean: lean,
      lapNo: lapNo,
      lapElapsedMs: lapElapsed,
      tripElapsedMs: tripMs - trip.startMs,
    );
  }

  /// 生成 ASS：PlayRes 384×216（16:9），libass 会按输出分辨率等比放大。
  /// 10Hz 采样，每帧一条 Dialogue（中间用 \pos 定位两块文本）。
  String _buildAss() {
    final start = _exportStartTripMs;
    final end = _exportEndTripMs;
    final b = StringBuffer();
    b.writeln('[Script Info]');
    b.writeln('ScriptType: v4.00+');
    b.writeln('PlayResX: 384');
    b.writeln('PlayResY: 216');
    b.writeln('WrapStyle: 2');
    b.writeln('ScaledBorderAndShadow: yes');
    b.writeln();
    b.writeln('[V4+ Styles]');
    b.writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
        'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
        'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
        'Alignment, MarginL, MarginR, MarginV, Encoding');
    b.writeln('Style: Big,Arial,52,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,'
        '-1,0,0,0,100,100,0,0,3,2,1,7,0,0,0,1');
    b.writeln('Style: Small,Arial,19,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,'
        '0,0,0,0,100,100,0,0,3,1,0,7,0,0,0,1');
    b.writeln('Style: Brand,Arial,13,&H00B4B4B4,&H000000FF,&H00000000,&H80000000,'
        '-1,0,0,0,100,100,1,0,3,1,0,9,0,0,0,1');
    b.writeln();
    b.writeln('[Events]');
    b.writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
        'MarginV, Effect, Text');

    const stepMs = 100;
    var t = start;
    while (t < end) {
      final f = _frameAt(t);
      final text = _assLine(f);
      final s = _assTime(t - start);
      final e = _assTime(math.min(t + stepMs, end) - start);
      if (text.isNotEmpty) {
        b.writeln('Dialogue: 0,$s,$e,Small,,0,0,0,,$text');
      }
      t += stepMs;
    }
    return b.toString();
  }

  String _assLine(_HudFrame f) {
    final parts = <String>[];
    if (_showBrand) {
      parts.add(r'{\an9\pos(366,8)\fs13}驰迹 DriveTrack');
    }
    if (_showSpeed) {
      parts.add(r'{\an7\pos(16,132)\fs52\b1}'
          '${f.speedKmh.toStringAsFixed(0)}'
          r'{\fs20\b0} km/h');
    }
    final sub = <String>[];
    if (_showLap && f.lapNo > 0) {
      sub.add('L${f.lapNo.toString().padLeft(2, '0')} ${_fmtLap(f.lapElapsedMs)}');
    }
    if (_showG) sub.add('G ${f.g.toStringAsFixed(2)}');
    if (_leanEnabled && _style != HudStyle.moto) {
      sub.add('倾角 ${f.lean.toStringAsFixed(0)}°');
    }
    if (sub.isNotEmpty) {
      parts.add(r'{\an7\pos(16,188)\fs18}' + sub.join('  ·  '));
    }
    // 摩托版式：倾角单独放右下角大字，和速度形成左右对称。
    if (_leanEnabled && _style == HudStyle.moto) {
      parts.add(r'{\an3\pos(368,190)\fs34\b1}'
          '${f.lean.toStringAsFixed(0)}'
          r'{\fs16\b0}°');
    }
    if (_showLap && f.lapNo == 0) {
      parts.add(r'{\an7\pos(16,188)\fs18}发车圈');
    }
    return parts.join();
  }

  String _buildJson() {
    final start = _exportStartTripMs;
    final end = _exportEndTripMs;
    final rows = <Map<String, dynamic>>[];
    const stepMs = 100;
    var t = start;
    while (t < end) {
      final f = _frameAt(t);
      rows.add({
        'tMs': t - start,
        'tripMs': t,
        'speedKmh': double.parse(f.speedKmh.toStringAsFixed(2)),
        'g': double.parse(f.g.toStringAsFixed(3)),
        'leanDeg': double.parse(f.lean.toStringAsFixed(2)),
        'lap': f.lapNo,
        'lapMs': f.lapElapsedMs,
      });
      t += stepMs;
    }
    return const JsonEncoder.withIndent(' ').convert({
      'schema': 'drivetrack.hud.track/1',
      'tripId': trip.id,
      'mode': trip.mode.name,
      'video': _currentPath,
      'offsetMs': _offsetMs,
      'exportStartTripMs': start,
      'samples': rows,
    });
  }

  String _buildReadme(String videoName) {
    final base = 'hud_${trip.id}';
    return '驰迹 DriveTrack · 视频 HUD 合成说明\n'
        '================================\n\n'
        '1) 本包内容\n'
        '   - $base.ass    HUD 字幕轨（ASS，10Hz，PlayRes 384x216）\n'
        '   - $base.json   HUD 数据轨（给后期 / 电脑端复用）\n'
        '   - $videoName   原视频（未改动）\n\n'
        '2) 一条命令烧录 HUD（需电脑装好 ffmpeg）\n'
        '   ffmpeg -i "$videoName" -vf "ass=$base.ass" '
        '-c:v libx264 -crf 20 -preset medium -c:a copy "$base-HUD.mp4"\n\n'
        '3) 对齐参数（本页导出时采用的值）\n'
        '   视频相对行程开始偏移：$_offsetMs ms\n'
        '   导出起点：${_trimLap == null ? '行程开始' : '第 $_trimLap 圈起点'}\n\n'
        '4) 说明\n'
        '   - App 内不做重编码，HUD 以字幕轨形式给出，4K 素材不会被压缩。\n'
        '   - 字幕时间已从导出起点归零，烧录后与视频开头对齐。\n'
        '   - 若视频比数据长，尾部没有 HUD 属正常（数据已结束）。\n';
  }

  // -------------------------------------------------------------------
  // v1.6.0：手机内直接烧录（FFmpegKit）
  // -------------------------------------------------------------------

  /// 烧录起点在视频里的位置（ms）：导出起点相对视频开头的偏移。
  int get _burnStartVideoMs => _exportStartTripMs - (trip.startMs + _offsetMs);

  /// 选视频编码器：_video 是 LGPL 构建（没有 x264），优先用硬件 MediaCodec，
  /// 再回落内置 mpeg4。探测失败时先按硬件编码试，失败后自动回落 mpeg4。
  Future<String> _pickEncoder() async {
    final set = await _availableEncoders();
    if (set.isEmpty) return 'h264_mediacodec';
    if (set.contains('h264_mediacodec')) return 'h264_mediacodec';
    if (set.contains('libx264')) return 'libx264';
    if (set.contains('libopenh264')) return 'libopenh264';
    return 'mpeg4';
  }

  /// 跑一次 `ffmpeg -encoders` 取可用编码器名（这个 fork 没有
  /// getSupportedEncoders，只能读日志）。
  Future<Set<String>> _availableEncoders() async {
    try {
      final session = await FFmpegKit.execute('-hide_banner -encoders');
      final out = await session.getOutput() ?? '';
      final set = <String>{};
      final re = RegExp(r'^\s*[VAS][A-Z.]{5}\s+(\S+)');
      for (final line in out.split('\n')) {
        final m = re.firstMatch(line);
        if (m != null) set.add(m.group(1)!);
      }
      return set;
    } catch (_) {
      return const <String>{};
    }
  }

  /// ffmpeg 滤镜串里的路径转义：反斜杠 / 冒号 / 单引号不转义会把滤镜串截断。
  String _filterPath(String p) =>
      p.replaceAll(r'\', r'\\').replaceAll(':', r'\:').replaceAll("'", r"\'");

  /// 视频滤镜：可选缩放（横屏压高、竖屏压宽，另一侧 -2 取偶数）+ 烧 ASS。
  String _burnVideoFilter(String assPath) {
    final parts = <String>[];
    final h = _burnHeight;
    if (h != null) {
      parts.add("scale='if(gte(iw,ih),-2,$h)':'if(gte(iw,ih),$h,-2)'");
    }
    parts.add('ass=${_filterPath(assPath)}');
    return parts.join(',');
  }

  /// 编码参数按编码器分派：mediacodec 不吃 crf/pix_fmt，只能给码率。
  List<String> _encoderArgs(String enc) {
    final h = _burnHeight ?? 2160;
    final bitrate = h >= 2000
        ? '24M'
        : h >= 1080
            ? '12M'
            : '6M';
    return switch (enc) {
      'h264_mediacodec' => ['-c:v', 'h264_mediacodec', '-b:v', bitrate],
      'libx264' => [
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '21',
          '-pix_fmt',
          'yuv420p',
        ],
      'libopenh264' => [
          '-c:v',
          'libopenh264',
          '-b:v',
          bitrate,
          '-pix_fmt',
          'yuv420p',
        ],
      _ => ['-c:v', 'mpeg4', '-q:v', '3', '-pix_fmt', 'yuv420p'],
    };
  }

  String _quoteArg(String s) =>
      s.contains(RegExp(r'[\s"]')) ? '"${s.replaceAll('"', r'\"')}"' : s;

  /// 视频时长（ms）：只用作进度分母；探测失败用行程时长兜底。
  Future<int> _probeDurationMs(String src) async {
    try {
      final session = await FFprobeKit.getMediaInformation(src);
      final info = session.getMediaInformation();
      final d = info?.getDuration();
      final sec = d == null ? null : double.tryParse(d);
      if (sec != null && sec > 0) return (sec * 1000).round();
    } catch (_) {
      // 探测失败不影响烧录，进度按行程时长估算。
    }
    return _durationMs;
  }

  /// 取日志末尾几行做错误提示，避免把几千行 ffmpeg 输出甩给用户。
  String _tail(String? out) {
    if (out == null || out.trim().isEmpty) return '未知错误（编码器没有返回日志）';
    final lines =
        out.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final last = lines.length <= 4 ? lines : lines.sublist(lines.length - 4);
    final text = last.join(' / ');
    return text.length > 220 ? '${text.substring(0, 220)}…' : text;
  }

  Future<void> _burnInApp() async {
    if (_burning) return;
    final src = _currentPath;
    if (src.isEmpty) {
      showAppNotice(context, '这条行程没有关联视频，先连接运动相机再记录。',
          AppNoticeKind.warning);
      return;
    }
    setState(() {
      _burning = true;
      _burnProgress = 0;
      _burnOutput = null;
      _burnError = null;
      _burnEncoder = '';
    });
    _sheetRefresh?.call();
    try {
      final dir = await Native.getCacheDir();
      final base = 'hud_${trip.id}';
      final assPath = '$dir/$base.ass';
      // 与预览、三件套共用同一份 ASS，保证所见即所得。
      await File(assPath).writeAsString(_buildAss());
      final outPath = '$dir/$base-HUD.mp4';
      final totalMs = await _probeDurationMs(src);
      final primary = await _pickEncoder();
      // 个别机型的硬件编码器不可用：主编码器失败时自动再试一次 mpeg4。
      final attempts =
          primary == 'mpeg4' ? <String>['mpeg4'] : <String>[primary, 'mpeg4'];
      for (final enc in attempts) {
        final r = await _runBurnSession(
          enc: enc,
          src: src,
          assPath: assPath,
          outPath: outPath,
          totalMs: totalMs,
        );
        if (r != false || !mounted) return;
        // 失败：清掉错误与进度，进入下一次尝试（UI 仍停在“烧录中”）。
        setState(() {
          _burnError = null;
          _burnProgress = 0;
        });
        _sheetRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _burning = false;
          _burnError = '$e';
        });
        _sheetRefresh?.call();
      }
    }
  }

  /// 跑一次烧录会话：成功 true / 失败 false / 取消 null。
  Future<bool?> _runBurnSession({
    required String enc,
    required String src,
    required String assPath,
    required String outPath,
    required int totalMs,
  }) async {
    final startMs = _burnStartVideoMs;
    final args = <String>[
      '-y',
      // 从指定圈开始导出时先跳转，ASS 的时间已从导出起点归零。
      if (startMs > 0) ...['-ss', (startMs / 1000).toStringAsFixed(3)],
      '-i',
      src,
      '-vf',
      _burnVideoFilter(assPath),
      ..._encoderArgs(enc),
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      outPath,
    ];
    final cmd = args.map(_quoteArg).join(' ');
    final done = Completer<bool?>();
    if (mounted) {
      setState(() {
        _burning = true;
        _burnEncoder = enc;
      });
      _sheetRefresh?.call();
    }
    final session = await FFmpegKit.executeAsync(
      cmd,
      (Session s) async {
        final code = await s.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          if (mounted) {
            setState(() {
              _burning = false;
              _burnProgress = 1;
              _burnOutput = outPath;
            });
            _sheetRefresh?.call();
          }
          if (!done.isCompleted) done.complete(true);
        } else if (ReturnCode.isCancel(code)) {
          if (mounted) {
            setState(() {
              _burning = false;
              _burnProgress = 0;
            });
            _sheetRefresh?.call();
            showAppNotice(context, '已取消烧录。', AppNoticeKind.info);
          }
          if (!done.isCompleted) done.complete(null);
        } else {
          final out = await s.getOutput();
          if (mounted) {
            setState(() {
              _burning = false;
              _burnError = _tail(out);
            });
            _sheetRefresh?.call();
          }
          if (!done.isCompleted) done.complete(false);
        }
      },
      null,
      (Statistics st) {
        if (!mounted || totalMs <= 0) return;
        final span = totalMs - math.max(0, startMs);
        if (span <= 0) return;
        final p = (st.getTime() / span).clamp(0.0, 0.99);
        setState(() => _burnProgress = p.toDouble());
        _sheetRefresh?.call();
      },
    );
    if (mounted) {
      setState(() => _burnSessionId = session.getSessionId());
    }
    return done.future;
  }

  void _cancelBurn() {
    final id = _burnSessionId;
    if (id != null) FFmpegKit.cancel(id);
  }

  Future<void> _shareBurn() async {
    final p = _burnOutput;
    if (p == null) return;
    try {
      await Native.shareFiles([p], 'video/mp4', '驰迹 HUD 成片');
    } catch (e) {
      if (mounted) showAppNotice(context, '分享失败：$e', AppNoticeKind.error);
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    if (_videos.isEmpty) {
      showAppNotice(context, '这条行程没有关联视频，先连接运动相机再记录。',
          AppNoticeKind.warning);
      return;
    }
    setState(() => _exporting = true);
    try {
      final dir = await Native.getCacheDir();
      final base = 'hud_${trip.id}';
      final assPath = '$dir/$base.ass';
      final jsonPath = '$dir/$base.json';
      final readmePath = '$dir/${base}_说明.txt';
      await File(assPath).writeAsString(_buildAss());
      await File(jsonPath).writeAsString(_buildJson());
      await File(readmePath).writeAsString(
        _buildReadme(_currentPath.split('/').last),
      );
      await Native.shareFiles(
        [assPath, jsonPath, readmePath, if (_currentPath.isNotEmpty) _currentPath],
        'application/octet-stream',
        '驰迹 HUD 三件套：用说明里的 ffmpeg 命令烧进视频',
      );
      if (mounted) {
        showAppNotice(context, '已生成 HUD 字幕轨与数据轨，可分享到电脑合成。',
            AppNoticeKind.success);
      }
    } catch (e) {
      if (mounted) {
        showAppNotice(context, '导出失败：$e', AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------------------------------------------------------
  // v1.7.x 全新编辑页（参考 "Video Sync"）：
  // 顶栏（返回 / 视频同步 / 删除）→ 视频预览 + HUD 叠加 →
  // 调整画面对齐 / HUD 信息 → 时间轴（刻度 + 选区 + 游标 + 速度曲线
  // + 胶片条）→ 底部圈选择。导出/烧录收进"导出成片"弹层，
  // 原有 FFmpegKit 与三件套逻辑全部保留。
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final laps = _laps;
    final f = _frameAt(_tripMs);
    final hasVideo = _videos.isNotEmpty && File(_currentPath).existsSync();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(),
            Expanded(
              child: _videos.isEmpty
                  ? _emptyVideoState(accent)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      children: [
                        _preview(f, hasVideo, accent),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _actionPill(
                                icon: Icons.center_focus_strong,
                                label: S.of(context)
                                    .t('调整画面对齐', 'Adjust video sync'),
                                onTap: _showSyncSheet,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionPill(
                                icon: Icons.tune,
                                label: S.of(context).t('HUD 信息', 'HUD info'),
                                onTap: _showHudSheet,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _timeRow(accent),
                        const SizedBox(height: 2),
                        _timeline(accent),
                        const SizedBox(height: 14),
                        _curveBand(accent),
                        const SizedBox(height: 1),
                        _filmstrip(),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 46,
                          child: FilledButton.icon(
                            onPressed: _showExportSheet,
                            style: FilledButton.styleFrom(
                              backgroundColor: _kHudRed,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.movie_filter_outlined,
                                size: 18),
                            label: Text(
                              S.of(context)
                                  .t('导出 HUD 成片', 'Export HUD video'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            _offsetMs == 0
                                ? S.of(context).t(
                                    '已按开录时间自动对齐',
                                    'Auto-aligned by clip start time',
                                  )
                                : S.of(context).t(
                                    '对齐偏移 ${_fmtOffset(_offsetMs)}',
                                    'Sync offset ${_fmtOffset(_offsetMs)}',
                                  ),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (_videos.isNotEmpty) _lapBar(laps, accent),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final s = S.of(context);
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 12,
            child: _circleButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Text(
            s.t('视频同步', 'Video Sync'),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          Positioned(
            right: 12,
            child: _circleButton(
              icon: Icons.delete_outline,
              onTap: _deleteCurrentVideo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1C1C1E),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      ),
    );
  }

  Widget _emptyVideoState(Color accent) {
    final s = S.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.videocam_off_outlined,
                  size: 30, color: Colors.white54),
              const SizedBox(height: 10),
              Text(
                s.t('这条行程还没有关联视频', 'No video linked to this trip'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.t(
                  '从手机相册选择一段素材，关联后即可对齐画面、添加 HUD。',
                  'Pick a clip from your gallery, then sync it and add HUD.',
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
                  onPressed: _importVideo,
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  icon: const Icon(Icons.video_library_outlined, size: 18),
                  label: Text(s.t('选择视频', 'Choose video')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(_HudFrame f, bool hasVideo, Color accent) {
    final s = S.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo && Platform.isAndroid)
              AndroidView(
                key: ValueKey(_currentPath),
                viewType: 'drivetrack/video_view',
                creationParams: <String, dynamic>{'path': _currentPath},
                onPlatformViewCreated: _onPlatformViewCreated,
              )
            else if (!hasVideo)
              // 文件被移动 / 删除，或路径对不上：给明确文案与重新导入入口，
              // 不再只显示一个黑框让用户以为页面坏了。
              _MissingVideoPlaceholder(onRetry: () => _importVideo())
            else
              const _PreviewPlaceholder(),
            // 首帧缩略图兜底：原生首帧解码出来前（或非 Android 没有平台
            // 视图时）先盖一张抽帧缩略图，保证预览区立刻有内容，而不是
            // 一块纯灰 / 纯黑空框；无分圈行程也能直接看到画面。
            if (hasVideo && !_prepared && _frames.isNotEmpty)
              Builder(
                builder: (ctx) {
                  final f = _frames.first;
                  if (!File(f).existsSync()) return const SizedBox.shrink();
                  return Image.file(
                    File(f),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
            IgnorePointer(
              child: Stack(
                children: [
                  if (_showLap && _laps.isNotEmpty) _lapStack(),
                  _hudOverlay(f),
                ],
              ),
            ),
            if (_playerError != null)
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _playerError!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    s.t('已导入视频', 'Imported Video'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 预览左上角的圈列表（参考图）：当前圈高亮，最多显示 5 行。
  Widget _lapStack() {
    final laps = _laps;
    final shown = laps.take(5).toList();
    return Positioned(
      left: 8,
      top: 8,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shown.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _activeLap == shown[i].number
                      ? const Color(0xFF1E78D2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${shown[i].number}',
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      _fmtLap(shown[i].endMs - shown[i].startMs),
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF2C2C2E),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeRow(Color accent) {
    final dur = _videoDurationMs;
    final pos = _posMs;
    return Row(
      children: [
        Text(
          '${_fmtClock(pos)}/${_fmtClock(dur)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _togglePlay,
          icon: Icon(
            _playing ? Icons.pause : Icons.play_arrow_rounded,
            size: 32,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _offsetHistory.isEmpty ? null : _undoOffset,
          icon: Icon(
            Icons.undo,
            size: 21,
            color: _offsetHistory.isEmpty ? Colors.white24 : Colors.white70,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _redoStack.isEmpty ? null : _redoOffset,
          icon: Icon(
            Icons.redo,
            size: 21,
            color: _redoStack.isEmpty ? Colors.white24 : Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _timeline(Color accent) {
    final dur = _videoDurationMs;
    return SizedBox(
      height: 58,
      child: LayoutBuilder(
        builder: (ctx, c) {
          void seek(double dx) {
            if (dur <= 0 || c.maxWidth <= 0) return;
            final ms = (dx / c.maxWidth * dur).round().clamp(0, dur);
            _seekVideo(ms);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition.dx),
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              seek(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              _seekVideo(_scrubMs);
            },
            child: CustomPaint(
              painter: _TimelinePainter(
                durationMs: dur,
                positionMs: _posMs,
                accent: accent,
                // 刻度文字继承页面字体（TextPainter 不读主题，
                // 不显式传入会落回系统默认字体，与其它文字不统一）。
                labelStyle: DefaultTextStyle.of(ctx).style,
                lapLabel: _activeLap == null
                    ? null
                    : S.of(context).t('第 $_activeLap 圈', 'Lap $_activeLap'),
              ),
              size: Size(c.maxWidth, 58),
            ),
          );
        },
      ),
    );
  }

  Widget _curveBand(Color accent) {
    final dur = _videoDurationMs;
    final win = _activeLapWindow();
    final startMs = win?.$1 ?? 0;
    final endMs = win?.$2 ?? dur;
    final samples = <Offset>[];
    if (dur > 0 && endMs > startMs) {
      const n = 72;
      for (var i = 0; i <= n; i++) {
        final videoMs = startMs + (endMs - startMs) * i ~/ n;
        final p = _pointAt(trip.startMs + _offsetMs + videoMs);
        samples.add(Offset(
          dur == 0 ? 0 : videoMs / dur,
          p == null ? 0 : p.speed * 3.6,
        ));
      }
    }
    return SizedBox(
      height: 52,
      child: CustomPaint(
        painter: _CurvePainter(
          samples: samples,
          positionRatio: dur <= 0 ? 0 : (_posMs / dur).clamp(0.0, 1.0),
          accent: accent,
        ),
        size: const Size(double.infinity, 52),
      ),
    );
  }

  Widget _filmstrip() {
    final frames = _frames;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 54,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (frames.isEmpty)
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            const Color(0xFF1B1B1B),
                            const Color(0xFF2A2A2A),
                            i / 6,
                          ),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.6),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            else
              Row(
                children: [
                  for (final p in frames)
                    Expanded(
                      child: Image.file(
                        File(p),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF1B1B1B)),
                      ),
                    ),
                ],
              ),
            Positioned(
              left: 4,
              top: 2,
              child: Text(
                S.of(context).t('已导入视频', 'Imported Video'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ignorePointerLine(),
            ),
          ],
        ),
      ),
    );
  }

  Widget ignorePointerLine() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CursorLinePainter(
          ratio: _videoDurationMs <= 0
              ? 0
              : (_posMs / _videoDurationMs).clamp(0.0, 1.0),
        ),
        size: const Size(double.infinity, 54),
      ),
    );
  }

  Widget _lapBar(List<Lap> laps, Color accent) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(color: Color(0xFF0B0B0C)),
      child: SizedBox(
        height: 46,
        child: laps.isEmpty
            ? Center(
                child: Text(
                  S.of(context).t('本次行程没有分圈', 'No laps in this trip'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            : laps.length <= 5
                // ≤5 圈：等分铺满，和参考图一样五个圈号一眼可见。
                ? Row(
                    children: [
                      for (var i = 0; i < laps.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _LapChip(
                            label: 'Lap${laps[i].number}',
                            selected: _activeLap == laps[i].number,
                            accent: accent,
                            onTap: () => _selectLap(laps[i]),
                          ),
                        ),
                      ],
                    ],
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: laps.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final l = laps[i];
                      final selected = _activeLap == l.number;
                      return _LapChip(
                        label: 'Lap${l.number}',
                        selected: selected,
                        accent: accent,
                        onTap: () => _selectLap(l),
                      );
                    },
                  ),
      ),
    );
  }

  // ---- 播放器 ----
  void _onPlatformViewCreated(int id) {
    final ch = MethodChannel('drivetrack/video_view_$id');
    ch.setMethodCallHandler((call) async {
      if (!mounted) return null;
      switch (call.method) {
        case 'onPrepared':
          final d = (call.arguments as Map?)?['duration'];
          setState(() {
            _prepared = true;
            _playerError = null;
            if (d is num) _playerDurationMs = d.toInt();
          });
        case 'onCompleted':
          setState(() {
            _playing = false;
            if (_playerDurationMs > 0) _playerMs = _playerDurationMs;
          });
        case 'onError':
          setState(() {
            _playerError = S.of(context).t(
              '应用内播放失败，可改用系统播放器',
              'In-app playback failed',
            );
            _playing = false;
          });
      }
      return null;
    });
    _channel = ch;
    setState(() {
      _prepared = false;
      _playing = false;
      _playerMs = 0;
      _scrubMs = 0;
      _playerDurationMs = 0;
      _playerError = null;
    });
  }

  Future<void> _pollOnce() async {
    final ch = _channel;
    if (!mounted || ch == null || !_prepared || _dragging) return;
    try {
      final results = await Future.wait([
        ch.invokeMethod<int>('getPosition'),
        ch.invokeMethod<int>('getDuration'),
        ch.invokeMethod<bool>('isPlaying'),
      ]);
      final pos = (results[0] as int?) ?? _playerMs;
      final dur = (results[1] as int?) ?? _playerDurationMs;
      final playing = (results[2] as bool?) ?? _playing;
      if (!mounted || _dragging) return;
      if ((pos - _playerMs).abs() >= 100 ||
          dur != _playerDurationMs ||
          playing != _playing) {
        setState(() {
          _playerMs = pos;
          _scrubMs = pos;
          _playerDurationMs = dur;
          _playing = playing;
        });
      }
    } catch (_) {
      // 轮询失败不弹错，下次 tick 再试。
    }
  }

  Future<void> _togglePlay() async {
    final ch = _channel;
    if (ch == null || !_prepared) return;
    try {
      if (_playing) {
        await ch.invokeMethod('pause');
        setState(() => _playing = false);
      } else {
        await ch.invokeMethod('play');
        setState(() => _playing = true);
      }
    } catch (_) {}
  }

  Future<void> _seekVideo(int ms) async {
    var target = ms;
    final dur = _videoDurationMs;
    if (dur > 0) target = target.clamp(0, dur);
    setState(() {
      _scrubMs = target;
      _playerMs = target;
    });
    final ch = _channel;
    if (ch != null && _prepared) {
      try {
        await ch.invokeMethod('seekTo', {'position': target});
      } catch (_) {}
    }
  }

  Future<void> _loadFrames() async {
    final path = _currentPath;
    if (path.isEmpty) return;
    final frames = await Native.videoThumbnails(path, count: 7);
    if (!mounted || _currentPath != path) return;
    setState(() => _frames = frames);
  }

  int get _videoDurationMs =>
      _playerDurationMs > 0 ? _playerDurationMs : _durationMs;

  int get _posMs => _dragging ? _scrubMs : _playerMs;

  /// 选中圈的视频时间窗（已钳制到视频长度）；未选圈返回 null。
  (int, int)? _activeLapWindow() {
    final n = _activeLap;
    if (n == null) return null;
    final laps = _laps;
    final idx = laps.indexWhere((l) => l.number == n);
    if (idx < 0) return null;
    final dur = _videoDurationMs;
    final start = (laps[idx].startMs - trip.startMs - _offsetMs).clamp(0, dur);
    final end = (laps[idx].endMs - trip.startMs - _offsetMs).clamp(0, dur);
    if (end <= start) return null;
    return (start, end);
  }

  void _selectLap(Lap l) {
    setState(() {
      _activeLap = l.number;
      _trimLap = l.number;
    });
    final start = l.startMs - trip.startMs - _offsetMs;
    _seekVideo(start < 0 ? 0 : start);
  }

  void _bumpOffset(int delta) {
    if (_videos.isEmpty) return;
    setState(() {
      _offsetHistory.add(_manualOffsetMs);
      _redoStack.clear();
      _manualOffsetMs += delta;
    });
    _sheetRefresh?.call();
  }

  void _undoOffset() {
    if (_offsetHistory.isEmpty) return;
    setState(() {
      _redoStack.add(_manualOffsetMs);
      _manualOffsetMs = _offsetHistory.removeLast();
    });
    _sheetRefresh?.call();
  }

  void _redoOffset() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _offsetHistory.add(_manualOffsetMs);
      _manualOffsetMs = _redoStack.removeLast();
    });
    _sheetRefresh?.call();
  }

  void _switchSegment(int i) {
    if (i == _segment || i < 0 || i >= _videos.length) return;
    final ch = _channel;
    try {
      ch?.invokeMethod('pause');
    } catch (_) {}
    setState(() {
      _segment = i;
      _channel = null;
      _prepared = false;
      _playing = false;
      _playerMs = 0;
      _scrubMs = 0;
      _playerDurationMs = 0;
      _playerError = null;
      _frames = const [];
      _manualOffsetMs = 0;
      _offsetHistory.clear();
      _redoStack.clear();
      _activeLap = null;
      _trimLap = null;
    });
    _loadFrames();
  }

  Future<void> _deleteCurrentVideo() async {
    final path = _currentPath;
    if (path.isEmpty) return;
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('解除视频关联？', 'Unlink this video?')),
        content: Text(
          s.t(
            '只会把这段视频从当前行程移除，不会删除手机里的原文件。',
            'The clip is removed from this trip; the original file is kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('解除关联', 'Unlink')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final paths = <String>[..._videos]..remove(path);
    final updated =
        await widget.store.updateTripVideoPaths(trip.id, paths);
    if (!mounted) return;
    if (updated == null) {
      showAppNotice(context, s.t('解除关联失败', 'Unlink failed'),
          AppNoticeKind.error);
      return;
    }
    if (updated.videoPaths.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _trip = updated;
      _segment = 0;
      _manualOffsetMs = 0;
      _scrubMs = 0;
      _playerMs = 0;
      _activeLap = null;
      _trimLap = null;
      _offsetHistory.clear();
      _redoStack.clear();
      _frames = const [];
    });
    _loadFrames();
  }

  // ---- 底部弹层 ----
  void _showSyncSheet() {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          _sheetRefresh = () => refresh(() {});
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              20 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('调整画面对齐', 'Adjust video sync'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                Text(
                  s.t(
                    '拖动按钮逐帧微调；正偏移 = 视频画面前移。',
                    'Fine-tune the offset; positive = video ahead.',
                  ),
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                if (_videos.length > 1) ...[
                  Text(
                    s.t('视频段', 'Segment'),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _videos.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${i + 1}'),
                              selected: _segment == i,
                              onSelected: (_) {
                                _switchSegment(i);
                                refresh(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _fmtOffset(_offsetMs),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final d in <int>[-10000, -1000, -100])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _bumpOffset(d),
                            child: Text(
                              _fmtOffset(d),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final d in <int>[100, 1000, 10000])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _bumpOffset(d),
                            child: Text(
                              _fmtOffset(d),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _bumpOffset(-_manualOffsetMs);
                          refresh(() {});
                        },
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: Text(
                          s.t('恢复自动对齐', 'Reset to auto'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  s.t(
                    '自动对齐：${_fmtOffset(_autoOffset(_currentPath))}（文件名开录时间）',
                    'Auto offset: ${_fmtOffset(_autoOffset(_currentPath))}',
                  ),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }

  void _showHudSheet() {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          _sheetRefresh = () => refresh(() {});
          void toggle(VoidCallback fn) {
            setState(fn);
            refresh(() {});
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              20 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.t('画面上显示什么', 'What to show on screen'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                Text(
                  s.t('版式', 'Style'),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final st in HudStyle.values)
                      ChoiceChip(
                        label: Text(st.label),
                        selected: _style == st,
                        onSelected: (_) => toggle(() => _style = st),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _toggle('速度', _showSpeed,
                    (v) => toggle(() => _showSpeed = v)),
                _toggle('圈号 / 圈时', _showLap,
                    (v) => toggle(() => _showLap = v)),
                _toggle('G 值', _showG, (v) => toggle(() => _showG = v)),
                if (trip.mode == TripMode.moto)
                  _toggle('倾角', _showLean,
                      (v) => toggle(() => _showLean = v)),
                _toggle('品牌角标', _showBrand,
                    (v) => toggle(() => _showBrand = v)),
                if (_style == HudStyle.minimal &&
                    (_showLap || _showG || _showLean))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      s.t(
                        '极简版式通常只留速度与品牌角标，勾选项仍会生效。',
                        'Minimal style usually keeps speed and brand only.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }

  void _showExportSheet() {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) {
          _sheetRefresh = () => refresh(() {});
          final laps = _laps;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t('导出 HUD 成片', 'Export HUD video'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  Text(
                    s.t('从第几圈开始', 'Start from lap'),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(s.t('行程开始', 'Trip start')),
                        selected: _trimLap == null,
                        onSelected: (_) {
                          setState(() => _trimLap = null);
                          refresh(() {});
                        },
                      ),
                      for (final l in laps)
                        ChoiceChip(
                          label: Text('Lap${l.number}'),
                          selected: _trimLap == l.number,
                          onSelected: (_) {
                            setState(() {
                              _trimLap = l.number;
                              _activeLap = l.number;
                            });
                            refresh(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.t('输出清晰度', 'Resolution'),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(s.t('原画质', 'Original')),
                        selected: _burnHeight == null,
                        onSelected: (_) {
                          setState(() => _burnHeight = null);
                          refresh(() {});
                        },
                      ),
                      ChoiceChip(
                        label: const Text('1080p'),
                        selected: _burnHeight == 1080,
                        onSelected: (_) {
                          setState(() => _burnHeight = 1080);
                          refresh(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_burning) ...[
                    LinearProgressIndicator(value: _burnProgress),
                    const SizedBox(height: 6),
                    Text(
                      '烧录中 ${(_burnProgress * 100).toStringAsFixed(0)}%'
                      '${_burnEncoder.isEmpty ? '' : ' · $_burnEncoder'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: _cancelBurn,
                        child: Text(s.t('取消烧录', 'Cancel')),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: _burnInApp,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kHudRed,
                        ),
                        icon: const Icon(Icons.local_fire_department,
                            size: 18),
                        label: Text(
                          s.t('开始烧录（手机内出片）', 'Burn in-app'),
                        ),
                      ),
                    ),
                    if (_burnOutput != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${s.t('成片已生成', 'Output ready')}\n$_burnOutput',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _shareBurn,
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: Text(s.t('分享成片', 'Share')),
                        ),
                      ),
                    ],
                    if (_burnError != null) ...[
                      const SizedBox(height: 8),
                      _warn(
                        '${s.t('烧录失败', 'Burn failed')}：$_burnError\n'
                        '${s.t(
                          '个别机型的硬件编码器不兼容，可改用三件套到电脑合成。',
                          'Some hardware encoders are incompatible; use the 3-file export.',
                        )}',
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '手机烧录会重新编码：1080p 更快、体积更小；原画质更慢也更热，'
                    '4K 长片建议用电脑合成。',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _exporting
                          ? null
                          : () async {
                              await _export();
                              if (mounted) refresh(() {});
                            },
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.computer, size: 18),
                      label: Text(
                        _exporting
                            ? '正在生成…'
                            : '导出三件套（电脑合成）',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '三件套：HUD 字幕轨（.ass）+ 数据轨（.json）+ 合成说明（.txt），'
                    '连同原视频一起分享。电脑上一条 ffmpeg 命令即可烧录，4K 素材原样保留。',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => _sheetRefresh = null);
  }

  String _fmtOffset(int ms) {
    final sign = ms < 0 ? '-' : '+';
    final abs = ms.abs();
    if (abs >= 10000) return '$sign${(abs / 1000).round()}s';
    return '$sign${(abs / 1000).toStringAsFixed(1)}s';
  }

  String _fmtClock(int ms) {
    final total = ms < 0 ? 0 : ms;
    final m = total ~/ 60000;
    final sec = (total % 60000) / 1000;
    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }


  Widget _warn(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5)),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// 预览里的 HUD 层：与 ASS 同一套信息，只是用 Flutter 排版。
  /// 版式差异：极简=更小字号、只留一行；赛道=左下沉底两行；
  /// 摩托=速度在左、倾角在右下大号。
  Widget _hudOverlay(_HudFrame f) {
    final minimal = _style == HudStyle.minimal;
    final moto = _style == HudStyle.moto;
    return Stack(
      children: [
        if (_showSpeed)
          Positioned(
            left: 12,
            bottom: minimal ? 12 : 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  f.speedKmh.toStringAsFixed(0),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: minimal ? 30 : 40,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 3, bottom: 4),
                  child: Text(
                    'km/h',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        if (moto && _leanEnabled)
          Positioned(
            right: 14,
            bottom: minimal ? 12 : 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  f.lean.toStringAsFixed(0),
                  style: const TextStyle(
                    color: _kHudRed,
                    fontSize: 34,
                    height: 0.95,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 3),
                  child: Text('°',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
        if (!minimal && ((_showLap && f.lapNo > 0) || _showG ||
            (_leanEnabled && !moto)))
          Positioned(
            left: 12,
            bottom: 12,
            child: Text(
              [
                if (_showLap && f.lapNo > 0)
                  'L${f.lapNo.toString().padLeft(2, '0')} ${_fmtLap(f.lapElapsedMs)}',
                if (_showLap && f.lapNo == 0) '发车圈',
                if (_showG) 'G ${f.g.toStringAsFixed(2)}',
                if (_leanEnabled) '倾角 ${f.lean.toStringAsFixed(0)}°',
              ].join('  ·  '),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
      ],
    );
  }
}

class _HudFrame {
  const _HudFrame({
    required this.speedKmh,
    required this.g,
    required this.lean,
    required this.lapNo,
    required this.lapElapsedMs,
    required this.tripElapsedMs,
  });

  final double speedKmh;
  final double g;
  final double lean;
  final int lapNo;
  final int lapElapsedMs;
  final int tripElapsedMs;
}

/// 时间轴：刻度 + 当前刻度蓝色高亮 + 白色游标 + "Lap N" 标签。
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.durationMs,
    required this.positionMs,
    required this.accent,
    required this.labelStyle,
    this.lapLabel,
  });

  final int durationMs;
  final int positionMs;
  final Color accent;

  /// 页面默认文字样式（字体族从这里继承）。
  final TextStyle labelStyle;
  final String? lapLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final w = size.width;
    final dur = durationMs <= 0 ? 1 : durationMs;
    double x(int ms) => (ms.clamp(0, dur) / dur) * w;

    // 刻度：自适应步长，保证不超过 6 个标签。
    var stepMs = 300000;
    for (final s in <int>[1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800]) {
      if (dur / (s * 1000) <= 6) {
        stepMs = s * 1000;
        break;
      }
    }
    final labelStyle = this.labelStyle.copyWith(
      color: const Color(0xFFDADADA),
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final centerStyle = labelStyle.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );

    // 参考图：只有离播放头最近的那个刻度被蓝色圆角块托起，
    // 不是整段选区，避免盖住相邻标签。
    final ticks = <int>[];
    for (var ms = 0; ms <= dur; ms += stepMs) {
      ticks.add(ms);
    }
    var nearest = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < ticks.length; i++) {
      final d = (x(ticks[i]) - x(positionMs)).abs();
      if (d < nearestDist) {
        nearestDist = d;
        nearest = i;
      }
    }
    for (final ms in ticks) {
      final px = x(ms);
      final inSel = ms == ticks[nearest];
      final tp = TextPainter(
        text: TextSpan(
          text: _tl(ms),
          style: inSel ? centerStyle : labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var tx = px - tp.width / 2;
      if (tx < 0) tx = 0;
      if (tx + tp.width > w) tx = w - tp.width;
      if (inSel) {
        canvas.drawRRect(
          RRect.fromLTRBR(tx - 6, 1, tx + tp.width + 6, 27, const Radius.circular(5)),
          Paint()..color = accent,
        );
      }
      tp.paint(canvas, Offset(tx, 6));
      // 小圆点刻度，参考图两个标签之间各点一个。
      if (ms + stepMs <= dur) {
        final mid = x(ms + stepMs ~/ 2);
        canvas.drawCircle(
          Offset(mid, 22),
          1,
          Paint()..color = const Color(0xFF8A8A8A),
        );
      }
    }

    // 游标：贯穿时间轴的白色竖线。
    final cx = x(positionMs);
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.6,
    );

    // 圈标签：参考图在游标下沿贴一个浅灰圆角块。
    final lbl = lapLabel;
    if (lbl != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: lbl,
          style: this.labelStyle.copyWith(
            color: const Color(0xFF111111),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final boxW = tp.width + 12;
      final left = (cx - boxW / 2).clamp(0.0, w - boxW);
      final rect = RRect.fromLTRBR(
        left,
        30,
        left + boxW,
        48,
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFE9E9E9));
      tp.paint(canvas, Offset(left + 6, 32));
    }
  }

  String _tl(int ms) {
    final total = ms ~/ 1000;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.durationMs != durationMs ||
      old.positionMs != positionMs ||
      old.accent != accent ||
      old.labelStyle != labelStyle ||
      old.lapLabel != lapLabel;
}

/// 速度曲线：参考图是蓝色实心带，底部一条亮边。
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.samples,
    required this.positionRatio,
    required this.accent,
  });

  /// 归一化时间（0-1）× 速度（km/h）。
  final List<Offset> samples;
  final double positionRatio;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    if (samples.isEmpty || w <= 0) return;
    var maxV = 1.0;
    for (final p in samples) {
      if (p.dy > maxV) maxV = p.dy;
    }
    final path = Path();
    final top = h - 6;
    path.moveTo(0, top);
    for (final p in samples) {
      final px = p.dx * w;
      final py = top - (p.dy / maxV).clamp(0.0, 1.0) * (h - 12);
      path.lineTo(px, py);
    }
    path.lineTo(w, top);
    path.close();
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.55),
          ],
        ).createShader(rect),
    );
    // 底部亮边（参考图的蓝色横条）。
    canvas.drawRect(
      Rect.fromLTWH(0, h - 3, w, 3),
      Paint()..color = accent,
    );
    final cx = positionRatio * w;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, h),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.samples != samples ||
      old.positionRatio != positionRatio ||
      old.accent != accent;
}

class _CursorLinePainter extends CustomPainter {
  _CursorLinePainter({required this.ratio});

  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final x = ratio.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _CursorLinePainter old) =>
      old.ratio != ratio;
}

/// 平台视图不可用 / 文件缺失时的视频位（不伪造画面）。
class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF151515),
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: Colors.white24,
        ),
      ),
    );
  }
}

/// 关联路径在磁盘上不存在时的占位：说明原因并给出重新导入入口。
class _MissingVideoPlaceholder extends StatelessWidget {
  const _MissingVideoPlaceholder({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ColoredBox(
      color: const Color(0xFF151515),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined,
                  size: 34, color: Colors.white38),
              const SizedBox(height: 8),
              Text(
                s.t(
                  '视频文件不存在或已被移动',
                  'Video file missing or moved',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.t(
                  '请重新导入这段素材后再继续对齐与导出。',
                  'Import the clip again to sync and export.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.video_library_outlined, size: 16),
                label: Text(s.t('重新导入视频', 'Import again')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部圈选择按钮：选中实心主题色，未选中深灰。
class _LapChip extends StatelessWidget {
  const _LapChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : const Color(0xFF2A2A2C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 46,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFFD4D4D4),
            ),
          ),
        ),
      ),
    );
  }
}
