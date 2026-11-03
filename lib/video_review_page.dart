import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'native.dart';

/// v0.1.7 追加项 3：视频回顾页（诚实回放叠加）。
///
/// 实现方式：应用内画面叠加（首选方案）。
/// - 播放器：Flutter 内置 AndroidView + 原生 VideoView（MainActivity.kt
///   注册的 `drivetrack/video_view` PlatformView 工厂），零第三方插件。
/// - HUD：Flutter 层 Stack 叠加在视频画面上的半透明数据条（速度 / G 值 /
///   时间），另在视频下方同步显示一份同样的数值——即使个别机型上平台视图
///   层叠表现异常，下方数值仍可读，不假装叠加成功。
/// - 同步：原生方法通道轮询（每 250ms 取 position / duration / isPlaying）
///   + 原生回调（onPrepared / onCompleted / onError）。轮询意味着 HUD 与
///   画面之间存在 ≤250ms 级延迟，页面与回执均如实写明，不宣称帧级同步。
/// - 未做烧录重编码：没有 ffmpeg、没有重编码。HUD 只存在于本页回放时，
///   分享 / 导出的原视频文件里不含 HUD 数据。这一点在页面底部与清单里
///   都写明。
///
/// 时间对齐（诚实版）：
/// - 录制逻辑（main.dart + MainActivity）：行程开始时启动视频，每段最长
///   10 分钟自动分段；段文件名形如 trip_<建段毫秒时间戳>.mp4。
/// - 本页按“视频段起始时间 = 行程开始时间 + 段偏移”对齐轨迹：
///   段偏移优先取文件名时间戳 − 行程开始时间（视频启动在 rec.start() 之前，
///   故首段偏移可能为小负值，钳制为 0 并在页面注明约早几百毫秒）；
///   文件名解析失败或偏移超出合理范围时，退回“段序号 × 10 分钟”估算，
///   并在页面注明是估算。段与段之间重启有短暂间隔，对齐精度为秒级，
///   不是帧级——页面不假装全程精确同步。
/// - 边界情况一律明示：视频启动失败（行程未关联视频）、段文件缺失、
///   行程轨迹点过少、应用内播放出错时，均显示警告条并保留时间轴回顾
///   与系统播放器备用入口，不静默失败。
class VideoReviewPage extends StatefulWidget {
  final Trip trip;
  final int initialSegment;
  const VideoReviewPage({super.key, required this.trip, this.initialSegment = 0});
  @override
  State<VideoReviewPage> createState() => _VideoReviewPageState();
}

String _mmss(int ms) {
  final s = (ms / 1000).round();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String _dateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 段偏移计算结果（供页面与导出清单共用）。
class _SegmentAlign {
  final int offsetMs;
  final String note;
  const _SegmentAlign(this.offsetMs, this.note);
}

_SegmentAlign _segmentAlign(Trip trip, String path, int index) {
  final duration = trip.endMs - trip.startMs;
  final base = path.split('/').last;
  final m = RegExp(r'trip_(\d+)\.mp4$').firstMatch(base);
  if (m != null && duration > 0) {
    final fileMs = int.tryParse(m.group(1)!);
    if (fileMs != null) {
      final off = fileMs - trip.startMs;
      if (off >= -10000 && off <= duration) {
        if (off < 0) {
          return _SegmentAlign(0, '视频启动约比轨迹早 ${(-off)}ms，已按 0 对齐（秒级精度）');
        }
        return _SegmentAlign(off, '按段文件名时间戳对齐（秒级精度）');
      }
    }
  }
  return _SegmentAlign(
      index * 10 * 60 * 1000, '文件名无可用时间戳，段起始按“段序号 × 10 分钟”估算（秒级精度）');
}

class _VideoReviewPageState extends State<VideoReviewPage> {
  late int _segmentIndex;
  MethodChannel? _channel;
  Timer? _poll;
  bool _prepared = false;
  bool _playing = false;
  int _positionMs = 0;
  int _durationMs = 0;
  String? _playerError;
  bool _dragging = false;
  int _sliderMs = 0;
  bool _exporting = false;

  Trip get _trip => widget.trip;
  List<String> get _videos => _trip.videoPaths;
  String? get _currentPath => _videos.isEmpty ? null : _videos[_segmentIndex];
  _SegmentAlign get _align => _videos.isEmpty
      ? const _SegmentAlign(0, '')
      : _segmentAlign(_trip, _videos[_segmentIndex], _segmentIndex);
  bool get _segmentMissing {
    final p = _currentPath;
    if (p == null) return true;
    try {
      return !File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 当前显示位置：拖动时用滑杆值，否则用轮询位置。
  int get _displayMs => _dragging ? _sliderMs : _positionMs;

  /// 视频内位置 → 行程绝对时间；超出轨迹范围时钳制到首尾点。
  int get _displayTripMs => _trip.startMs + _align.offsetMs + _displayMs;

  TrackPoint? _pointAt(int tripMs) {
    final pts = _trip.points;
    if (pts.isEmpty) return null;
    var lo = 0, hi = pts.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (pts[mid].timeMs <= tripMs) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return pts[ans];
  }

  /// 事件在当前段内的视频位置（毫秒）；不在本段内返回 null。
  int? _eventSegmentMs(TripEvent e) {
    final segMs = (e.startMs - _trip.startMs) - _align.offsetMs;
    final cap = _durationMs > 0 ? _durationMs : 10 * 60 * 1000;
    if (segMs < 0 || segMs > cap) return null;
    return segMs;
  }

  List<TripEvent> get _segmentEvents {
    final list = <TripEvent>[];
    for (final e in _trip.events) {
      if (_eventSegmentMs(e) != null) list.add(e);
    }
    list.sort((a, b) => a.startMs.compareTo(b.startMs));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _segmentIndex = _videos.isEmpty
        ? 0
        : widget.initialSegment.clamp(0, _videos.length - 1);
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollOnce());
  }

  @override
  void dispose() {
    _poll?.cancel();
    try {
      _channel?.invokeMethod('pause');
    } catch (_) {}
    super.dispose();
  }

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
            if (d is num) _durationMs = d.toInt();
          });
          // 准备好即自动播放；失败时走 catch，不假装在播。
          try {
            await ch.invokeMethod('play');
            if (mounted) setState(() => _playing = true);
          } catch (_) {}
        case 'onCompleted':
          setState(() {
            _playing = false;
            if (_durationMs > 0) _positionMs = _durationMs;
          });
        case 'onError':
          final args = call.arguments as Map?;
          setState(() {
            _playerError =
                '应用内播放失败（what=${args?['what']} extra=${args?['extra']}），请用系统播放器打开';
            _playing = false;
          });
      }
      return null;
    });
    _channel = ch;
    setState(() {
      _prepared = false;
      _playing = false;
      _positionMs = 0;
      _durationMs = 0;
      _playerError = null;
    });
  }

  Future<void> _pollOnce() async {
    final ch = _channel;
    if (!mounted || ch == null || !_prepared) return;
    try {
      final results = await Future.wait([
        ch.invokeMethod<int>('getPosition'),
        ch.invokeMethod<int>('getDuration'),
        ch.invokeMethod<bool>('isPlaying'),
      ]);
      final pos = (results[0] as int?) ?? _positionMs;
      final dur = (results[1] as int?) ?? _durationMs;
      final playing = (results[2] as bool?) ?? _playing;
      if (!mounted || _dragging) return;
      if ((pos - _positionMs).abs() >= 100 || dur != _durationMs || playing != _playing) {
        setState(() {
          _positionMs = pos;
          _durationMs = dur;
          _playing = playing;
        });
      }
    } catch (_) {
      // 轮询失败不弹错：下次 tick 再试；持续失败时用户仍可用滑杆时间轴回顾。
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

  /// 事件跳转：seek 到事件开始前约 3 秒（已钳制到段内），跳转后自动播放。
  /// seek 精度说明：VideoView.seekTo 按关键帧就近定位，实际落点与目标
  /// 可能差 1 帧组（通常 <1 秒），不是帧精确。
  Future<void> _jumpToEvent(TripEvent e) async {
    final segMs = _eventSegmentMs(e);
    if (segMs == null) return;
    var target = segMs - 3000;
    if (target < 0) target = 0;
    if (_durationMs > 0 && target > _durationMs) target = _durationMs;
    final ch = _channel;
    setState(() {
      _positionMs = target;
      _sliderMs = target;
    });
    if (ch != null && _prepared) {
      try {
        await ch.invokeMethod('seekTo', {'position': target});
        await ch.invokeMethod('play');
        if (mounted) setState(() => _playing = true);
      } catch (_) {}
    }
  }

  void _switchSegment(int i) {
    if (i == _segmentIndex || i < 0 || i >= _videos.length) return;
    setState(() {
      _segmentIndex = i;
      _channel = null;
      _prepared = false;
      _playing = false;
      _positionMs = 0;
      _durationMs = 0;
      _playerError = null;
    });
  }

  String _eventLine(TripEvent e) {
    final tripOff = e.startMs - _trip.startMs;
    final segIdx = _segmentIndexOfEvent(e);
    final segMs = segIdx == null ? null : (e.startMs - _trip.startMs) - _segmentAlign(_trip, _videos[segIdx], segIdx).offsetMs;
    return '- [${e.label}] 行程+${_mmss(tripOff)}'
        '${segIdx == null ? '' : ' · 第 ${segIdx + 1} 段视频内 ${_mmss(segMs ?? 0)}（跳转落点为事件前 3 秒）'}'
        ' · 纵向 ${e.peakLongG.toStringAsFixed(2)}g · 横向 ${e.peakLatG.toStringAsFixed(2)}g'
        ' · 速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h'
        ' · 持续 ${(e.endMs - e.startMs) ~/ 1000} 秒';
  }

  int? _segmentIndexOfEvent(TripEvent e) {
    for (var i = 0; i < _videos.length; i++) {
      final off = _segmentAlign(_trip, _videos[i], i).offsetMs;
      final segMs = (e.startMs - _trip.startMs) - off;
      final cap = 10 * 60 * 1000;
      if (segMs >= 0 && segMs <= cap) return i;
    }
    return null;
  }

  String _exportText() {
    final b = StringBuffer();
    b.writeln('驰迹 DriveTrack · 事件时间戳清单');
    b.writeln('行程：${_trip.mode.label} · ${_dateTime(_trip.startMs)} 开始 · ${_trip.id}');
    b.writeln('视频段数：${_videos.length}（每段最长 10 分钟自动分段）');
    b.writeln('对齐方式：视频段起始时间 = 行程开始时间 + 段偏移；段偏移优先取段文件名时间戳，'
        '否则按段序号 × 10 分钟估算。对齐精度为秒级，不是帧级。');
    b.writeln('重要：本清单与本页 HUD 均为回放时叠加/标注，未做烧录重编码；'
        '原视频文件本身不含速度、G 值与事件标注。');
    b.writeln('事件跳转：点事件跳到该事件前约 3 秒；seek 按关键帧就近定位，落点可能差 <1 秒。');
    if (_trip.events.isEmpty) {
      b.writeln('本行程无事件。');
    } else {
      for (final e in _trip.events) {
        b.writeln(_eventLine(e));
      }
    }
    return b.toString();
  }

  Future<void> _shareEventList() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await Native.getCacheDir();
      final file = File('$dir/drivetrack_events_${_trip.id}.txt');
      await file.writeAsString(_exportText());
      await Native.shareFiles([file.path], 'text/plain', '驰迹事件时间戳清单（未烧录进视频，仅文本清单）');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出失败，可改用“复制清单”')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final point = _pointAt(_displayTripMs);
    final hasVideo = _currentPath != null && !_segmentMissing;
    final maxMs = _durationMs > 0 ? _durationMs : 10 * 60 * 1000;
    final events = _segmentEvents;
    return Scaffold(
      appBar: AppBar(title: const Text('视频回顾 · 数据叠加')),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ---- 段切换 ----
          if (_videos.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _videos.length; i++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text('第 ${i + 1} 段'),
                      selected: i == _segmentIndex,
                      onSelected: (_) => _switchSegment(i),
                    ),
                  ),
              ]),
            ),
          // ---- 视频画面 + Flutter HUD 叠加层 ----
          Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(children: [
                if (hasVideo && Platform.isAndroid)
                  AndroidView(
                    key: ValueKey(_currentPath),
                    viewType: 'drivetrack/video_view',
                    creationParams: <String, dynamic>{'path': _currentPath},
                    onPlatformViewCreated: _onPlatformViewCreated,
                  )
                else
                  const Center(
                    child: Text('暂无可播放的视频段', style: TextStyle(color: Colors.white54)),
                  ),
                // HUD 叠加层（IgnorePointer，不挡播放控制；下方另有一份同样数值）。
                if (point != null)
                  IgnorePointer(
                    child: Stack(children: [
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _hudChip('${(point.speed * 3.6).toStringAsFixed(0)} km/h'),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: _hudChip('行程+${_mmss(_displayTripMs - trip.startMs)}'),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _hudChip(
                            '纵向 ${point.longG.toStringAsFixed(2)}g · 横向 ${point.latG.toStringAsFixed(2)}g'),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          // ---- 播放控制 ----
          Row(children: [
            IconButton(
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              tooltip: _playing ? '暂停' : '播放',
              onPressed: hasVideo && _prepared ? _togglePlay : null,
            ),
            Expanded(
              child: Slider(
                value: _displayMs.clamp(0, maxMs).toDouble(),
                max: maxMs.toDouble(),
                onChangeStart: (v) => setState(() {
                  _dragging = true;
                  _sliderMs = v.toInt();
                }),
                onChanged: (v) => setState(() => _sliderMs = v.toInt()),
                onChangeEnd: (v) async {
                  setState(() {
                    _dragging = false;
                    _positionMs = v.toInt();
                  });
                  final ch = _channel;
                  if (ch != null && _prepared) {
                    try {
                      await ch.invokeMethod('seekTo', {'position': v.toInt()});
                    } catch (_) {}
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${_mmss(_displayMs)} / ${_durationMs > 0 ? _mmss(_durationMs) : '--:--'}',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          // ---- 事件时间轴标点 ----
          if (events.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(builder: (context, c) {
                return SizedBox(
                  height: 28,
                  child: Stack(children: [
                    Container(
                      margin: const EdgeInsets.only(top: 13),
                      height: 2,
                      color: Colors.white24,
                    ),
                    for (final e in events)
                      Positioned(
                        left: ((_eventSegmentMs(e)! / maxMs) * c.maxWidth - 6)
                            .clamp(0.0, math.max(0.0, c.maxWidth - 12)),
                        top: 4,
                        child: GestureDetector(
                          onTap: () => _jumpToEvent(e),
                          child: Container(
                            width: 12,
                            height: 20,
                            alignment: Alignment.center,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      ),
                  ]),
                );
              }),
            ),
          if (events.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('时间轴红点为本段事件，点红点或下方事件即跳到该事件前约 3 秒',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          // ---- HUD 数值（视频下方同步一份） ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: point == null
                ? const Text('无轨迹点，HUD 无数据')
                : Wrap(spacing: 16, runSpacing: 8, children: [
                    Text('速度 ${(point.speed * 3.6).toStringAsFixed(0)} km/h',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('纵向 ${point.longG.toStringAsFixed(2)}g'),
                    Text('横向 ${point.latG.toStringAsFixed(2)}g'),
                    Text('合成 ${point.combinedG.toStringAsFixed(2)}g'),
                    if (trip.mode == TripMode.moto) Text('侧倾 ${point.roll.toStringAsFixed(0)}°'),
                    Text('行程 ${_dateTime(_displayTripMs)}'),
                  ]),
          ),
          // ---- 边界情况明示 ----
          if (_videos.isEmpty)
            const _WarnBanner('本行程未关联视频：可能视频启动失败、未勾选同步视频，或行程太短未保存。'
                '下方仍可查看事件清单与导出时间戳。'),
          if (_videos.isNotEmpty && _segmentMissing)
            const _WarnBanner('当前段视频文件已缺失（可能被清理），无法应用内播放；可切换其他段，或用下方事件时间轴回顾数据。'),
          if (trip.points.length < 10)
            const _WarnBanner('轨迹点过少（少于 10 个），HUD 与事件可能不完整。'),
          if (_playerError != null) _WarnBanner(_playerError!),
          if (_videos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('对齐：${_align.note}；HUD 每 250ms 轮询同步，画面与数值有 ≤250ms 级延迟；'
                  'seek 按关键帧就近定位，落点可能差 <1 秒。',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('未做烧录重编码：HUD 只在本页回放时叠加，分享 / 导出的原视频文件不含 HUD 数据。',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
          // ---- 本段事件 ----
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('本段事件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('本段无事件', style: TextStyle(color: Colors.white54)),
            ),
          for (final e in events)
            ListTile(
              title: Text('${e.label} · 视频内 ${_mmss(_eventSegmentMs(e)!)}（跳转到前 3 秒）'),
              subtitle: Text('纵向 ${e.peakLongG.toStringAsFixed(2)}g · 横向 ${e.peakLatG.toStringAsFixed(2)}g · '
                  '速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h'),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => _jumpToEvent(e),
            ),
          // ---- 导出与备用入口 ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('复制事件清单'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _exportText()));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('事件时间戳清单已复制')));
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share),
                label: Text(_exporting ? '导出中…' : '分享事件清单文件'),
                onPressed: _exporting ? null : _shareEventList,
              ),
              if (_currentPath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('系统播放器播放（备用）'),
                  onPressed: () => Native.playVideo(_currentPath!),
                ),
              if (_currentPath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.video_library),
                  label: const Text('分享视频'),
                  onPressed: () =>
                      Native.shareFiles([_currentPath!], 'video/mp4', '驰迹行程视频'),
                ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 24),
            child: Text('已知限制（待真机验证）：各品牌播放器 / 解码表现、seek 精度、横竖屏下的叠加层与控制条、'
                '多段切换后的对齐；本页未经过真机实测，结论以总协调编包后的真机验证为准。',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _hudChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      );
}

class _WarnBanner extends StatelessWidget {
  final String text;
  const _WarnBanner(this.text);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.orange, fontSize: 12)),
      );
}
