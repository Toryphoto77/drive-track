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

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'track_timing.dart';
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
  const VideoHudPage({super.key, required this.trip, required this.store});

  final Trip trip;
  final Store store;

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
  }

  int _segment = 0;
  int _manualOffsetMs = 0;
  int _scrubMs = 0;

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

  /// 倾角只对摩托有意义：非摩托行程即便勾了也不输出。
  bool get _leanEnabled => _showLean && trip.mode == TripMode.moto;

  Trip get trip => _trip;

  List<String> get _videos => trip.videoPaths;

  /// v1.7.x：空态下直接导入运动相机视频并关联到本行程，成功后刷新列表，
  /// 之后即可走现有的对齐 / HUD 编辑 / 烧录 / 分享流程。
  Future<void> _importVideo() async {
    final updated = await pickAndImportVideo(
      context,
      store: widget.store,
      preselectedTrip: _trip,
    );
    if (updated != null && mounted) {
      setState(() {
        _trip = updated;
        _segment = 0;
        _manualOffsetMs = 0;
      });
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
    return _videos[i];
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _burning = false;
          _burnError = '$e';
        });
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
          }
          if (!done.isCompleted) done.complete(true);
        } else if (ReturnCode.isCancel(code)) {
          if (mounted) {
            setState(() {
              _burning = false;
              _burnProgress = 0;
            });
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

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final f = _frameAt(_tripMs);
    final laps = _laps;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('视频 HUD 合成')),
      body: ListView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 12, 16, 28),
        ),
        children: [
          if (_videos.isEmpty) ...[
            _warn('这条行程没有关联视频。可导入运动相机拍摄的素材，'
                '在此对齐并添加 HUD 后分享。'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _importVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('导入运动相机视频'),
              ),
            ),
          ] else ...[
            _sectionTitle('1. 选择视频段'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _videos.length; i++)
                  ChoiceChip(
                    label: Text('第 ${i + 1} 段'),
                    selected: _segment == i,
                    onSelected: (_) {
                      setState(() {
                        _segment = i;
                        _manualOffsetMs = 0;
                        _scrubMs = 0;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _currentPath.split('/').last,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _sectionTitle('2. 时间对齐'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CardStyle.innerCardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CardStyle.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前偏移：${_offsetMs >= 0 ? '+' : ''}$_offsetMs ms'
                    '（自动 ${_autoOffset(_currentPath)} ms，手动 $_manualOffsetMs ms）',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '自动对齐取视频文件名里的开录时间戳。若画面首发点与数据差一截，'
                    '用下面的按钮微调：让“画面出现起跑线”的时刻对应下方圈时归零。',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in const [-1000, -500, -100, 100, 500, 1000])
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => _manualOffsetMs += d),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: Text('${d > 0 ? '+' : ''}$d ms'),
                        ),
                      TextButton(
                        onPressed: () => setState(() => _manualOffsetMs = 0),
                        child: const Text('复位'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('3. 预览'),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF1B2430),
                            Color(0xFF0B0E13),
                            Color(0xFF05070A),
                          ],
                        ),
                      ),
                    ),
                    // 预览底图只是示意：真实画面来自视频，这里只画 HUD 层。
                    const Center(
                      child: Text(
                        '画面示意（HUD 层预览）',
                        style: TextStyle(color: Colors.white12, fontSize: 11),
                      ),
                    ),
                    _hudOverlay(f),
                    if (_showBrand)
                      const Positioned(
                        top: 8,
                        right: 10,
                        child: Text(
                          '驰迹 DriveTrack',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              value: _durationMs <= 0
                  ? 0
                  : _scrubMs.clamp(0, _durationMs).toDouble(),
              max: math.max(1, _durationMs).toDouble(),
              onChanged: (v) => setState(() => _scrubMs = v.round()),
            ),
            Text(
              '播放头 ${_fmtLap(_scrubMs)} / ${_fmtLap(_durationMs)}'
              ' · 对应行程时刻 ${_fmtLap(_tripMs - trip.startMs)}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _sectionTitle('4. HUD 版式'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in HudStyle.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _style == s,
                    onSelected: (_) => setState(() {
                      _style = s;
                      // 摩托版默认带倾角；其他版式默认不带。
                      _showLean = s == HudStyle.moto &&
                          trip.mode == TripMode.moto;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _toggle('速度', _showSpeed, (v) => setState(() => _showSpeed = v)),
                _toggle('圈号/圈时', _showLap, (v) => setState(() => _showLap = v)),
                _toggle('G 值', _showG, (v) => setState(() => _showG = v)),
                // 倾角只给摩托：非摩托行程不出现这个开关。
                if (trip.mode == TripMode.moto)
                  _toggle('倾角', _showLean, (v) => setState(() => _showLean = v)),
                _toggle('品牌角标', _showBrand, (v) => setState(() => _showBrand = v)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '倾角只对摩托有效：汽车行程打开也不会显示读数（数据本身是车身横滚角）。',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _sectionTitle('5. 导出起点'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('行程开始'),
                  selected: _trimLap == null,
                  onSelected: (_) => setState(() => _trimLap = null),
                ),
                for (final l in laps)
                  ChoiceChip(
                    label: Text('第 ${l.number} 圈起'),
                    selected: _trimLap == l.number,
                    onSelected: (_) => setState(() => _trimLap = l.number),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '导出范围：${_fmtLap(_exportStartTripMs - trip.startMs)} → '
              '${_fmtLap(_exportEndTripMs - trip.startMs)}'
              '（约 ${_fmtLap(_exportEndTripMs - _exportStartTripMs)}）',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 22),
            _sectionTitle('6. 手机内直接出片'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('1080p（推荐）'),
                  selected: _burnHeight == 1080,
                  onSelected: (_) => setState(() => _burnHeight = 1080),
                ),
                ChoiceChip(
                  label: const Text('原画质'),
                  selected: _burnHeight == null,
                  onSelected: (_) => setState(() => _burnHeight = null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_burning) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _burnProgress,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  color: _kHudRed,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '正在烧录：${(_burnProgress * 100).toStringAsFixed(0)}%'
                      '${_burnEncoder.isEmpty ? '' : ' · $_burnEncoder'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  TextButton(onPressed: _cancelBurn, child: const Text('取消')),
                ],
              ),
              const SizedBox(height: 4),
            ] else ...[
              SizedBox(
                height: 50,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _burnInApp,
                  style: FilledButton.styleFrom(backgroundColor: _kHudRed),
                  icon: const Icon(Icons.movie_creation_outlined, size: 18),
                  label: const Text('直接在手机上烧录成片'),
                ),
              ),
              if (_burnOutput != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '成片已生成，原视频未改动',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _burnOutput!.split('/').last,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: _shareBurn,
                          icon: const Icon(Icons.ios_share, size: 16),
                          label: const Text('分享成片'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_burnError != null) ...[
                const SizedBox(height: 8),
                _warn(
                  '烧录失败：$_burnError\n'
                  '个别机型的硬件编码器不兼容，可改用下面的三件套到电脑合成。',
                ),
              ],
            ],
            const SizedBox(height: 8),
            const Text(
              '手机烧录会重新编码：1080p 更快、体积更小，适合直接发到网上；'
              '原画质更慢也更热，4K 长片建议用电脑合成。',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.computer, size: 18),
                label: Text(_exporting ? '正在生成…' : '导出三件套（电脑合成）'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '三件套：HUD 字幕轨（.ass）+ 数据轨（.json）+ 合成说明（.txt），'
              '连同原视频一起分享。电脑上一条 ffmpeg 命令即可烧录，4K 素材原样保留。',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
            if (_style == HudStyle.minimal &&
                (_showLap || _showG || _showLean))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '提示：极简版式通常只留速度与品牌角标，勾选项仍会生效。',
                  style: TextStyle(color: accent.withValues(alpha: 0.8), fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
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

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
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
