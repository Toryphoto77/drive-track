import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'app_notice.dart';
import 'package:flutter/services.dart';
import 'app_locale.dart';
import 'models.dart';
import 'native.dart';
import 'video_map_gauge.dart';

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

_SegmentAlign _segmentAlign(S s, Trip trip, String path, int index) {
  final duration = trip.endMs - trip.startMs;
  final base = path.split('/').last;
  final m = RegExp(r'trip_(\d+)\.mp4$').firstMatch(base);
  if (m != null && duration > 0) {
    final fileMs = int.tryParse(m.group(1)!);
    if (fileMs != null) {
      final off = fileMs - trip.startMs;
      if (off >= -10000 && off <= duration) {
        if (off < 0) {
          return _SegmentAlign(
              0, s.t('视频比轨迹早 ${(-off)}ms，已按 0 对齐',
                  'Video starts ${(-off)}ms before the track; aligned to 0'));
        }
        return _SegmentAlign(
            off, s.t('按段文件名时间戳对齐', 'Aligned by segment filename timestamp'));
      }
    }
  }
  return _SegmentAlign(index * 10 * 60 * 1000,
      s.t('段起始按“段序号 × 10 分钟”估算', 'Segment start estimated as index × 10 minutes'));
}

/// 事件标签来自数据层（中文），英文界面在此转写。
String _eventLabel(S s, TripEvent e) {
  if (s.zh) return e.label;
  return switch (e.kind) {
    'corner' => 'Corner',
    'harshAccel' => 'Hard accel',
    'harshBrake' => 'Hard brake',
    'sensorDrop' => 'Sensor lost',
    _ => e.label,
  };
}

String _modeName(S s, TripMode mode) => switch (mode) {
      TripMode.car => s.t('汽车', 'Car'),
      TripMode.moto => s.t('摩托', 'Moto'),
      TripMode.kart => s.t('卡丁车', 'Kart'),
      TripMode.bike => s.t('骑行', 'Ride'),
    };

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
  // v1.3.6：地图仪表位置与显隐（只影响本页会话；跟随播放位置实时
  // 更新，复用既有 250ms 轮询，不另起高频定时器）。
  VideoGaugePosition _gaugePosition = VideoGaugePosition.topRight;
  bool _gaugeHidden = false;

  Trip get _trip => widget.trip;
  List<String> get _videos => _trip.videoPaths;
  String? get _currentPath => _videos.isEmpty ? null : _videos[_segmentIndex];
  _SegmentAlign get _align => _videos.isEmpty
      ? const _SegmentAlign(0, '')
      : _segmentAlign(
          S.of(context), _trip, _videos[_segmentIndex], _segmentIndex);
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
          setState(() {
            _playerError = S.of(context).t(
              '应用内播放失败，请用系统播放器打开',
              'In-app playback failed; open it with the system player',
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

  String _eventLine(S s, TripEvent e) {
    final tripOff = e.startMs - _trip.startMs;
    final segIdx = _segmentIndexOfEvent(s, e);
    final segMs = segIdx == null
        ? null
        : (e.startMs - _trip.startMs) -
            _segmentAlign(s, _trip, _videos[segIdx], segIdx).offsetMs;
    return s.t(
      '- [${_eventLabel(s, e)}] 行程+${_mmss(tripOff)}'
      '${segIdx == null ? '' : ' · 第 ${segIdx + 1} 段视频内 ${_mmss(segMs ?? 0)}（跳转落点为事件前 3 秒）'}'
      ' · 纵向 ${e.peakLongG.toStringAsFixed(2)}g · 横向 ${e.peakLatG.toStringAsFixed(2)}g'
      ' · 速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h'
      ' · 持续 ${(e.endMs - e.startMs) ~/ 1000} 秒',
      '- [${_eventLabel(s, e)}] trip+${_mmss(tripOff)}'
      '${segIdx == null ? '' : ' · in segment ${segIdx + 1} at ${_mmss(segMs ?? 0)} (jumps to 3 s before the event)'}'
      ' · long ${e.peakLongG.toStringAsFixed(2)}g · lat ${e.peakLatG.toStringAsFixed(2)}g'
      ' · speed ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h'
      ' · lasts ${(e.endMs - e.startMs) ~/ 1000} s',
    );
  }

  int? _segmentIndexOfEvent(S s, TripEvent e) {
    for (var i = 0; i < _videos.length; i++) {
      final off = _segmentAlign(s, _trip, _videos[i], i).offsetMs;
      final segMs = (e.startMs - _trip.startMs) - off;
      final cap = 10 * 60 * 1000;
      if (segMs >= 0 && segMs <= cap) return i;
    }
    return null;
  }

  String _exportText() {
    final s = S.of(context);
    final b = StringBuffer();
    b.writeln(s.t('驰迹 DriveTrack · 事件时间戳清单',
        'DriveTrack · Event timestamp list'));
    b.writeln(s.t(
      '行程：${_modeName(s, _trip.mode)} · ${_dateTime(_trip.startMs)} 开始 · ${_trip.id}',
      'Trip: ${_modeName(s, _trip.mode)} · started ${_dateTime(_trip.startMs)} · ${_trip.id}',
    ));
    b.writeln(s.t('视频段数：${_videos.length}（每段最长 10 分钟）',
        'Video segments: ${_videos.length} (up to 10 minutes each)'));
    b.writeln(s.t(
      '对齐方式：段偏移优先取段文件名时间戳，否则按段序号 × 10 分钟估算；精度为秒级。',
      'Alignment: segment offset uses the filename timestamp when available, otherwise index × 10 minutes; second-level accuracy.',
    ));
    b.writeln(s.t('本清单与 HUD、地图仪表仅为回放叠加，未烧录进原视频。',
        'This list, the HUD, and the map gauge are replay overlays only and are not burned into the original video.'));
    b.writeln(s.t('点事件跳到该事件前约 3 秒。',
        'Tap an event to jump to about 3 seconds before it.'));
    if (_trip.events.isEmpty) {
      b.writeln(s.t('本行程无事件。', 'This trip has no events.'));
    } else {
      for (final e in _trip.events) {
        b.writeln(_eventLine(s, e));
      }
    }
    return b.toString();
  }

  Future<void> _shareEventList() async {
    if (_exporting) return;
    final s = S.of(context);
    setState(() => _exporting = true);
    try {
      final dir = await Native.getCacheDir();
      final file = File('$dir/drivetrack_events_${_trip.id}.txt');
      await file.writeAsString(_exportText());
      await Native.shareFiles([file.path], 'text/plain',
          s.t('驰迹事件时间戳清单', 'DriveTrack event timestamp list'));
    } catch (_) {
      if (mounted) {
        showAppNotice(context,
            s.t('导出失败，可改用“复制清单”', 'Export failed; try Copy list instead'),
            AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final trip = _trip;
    final point = _pointAt(_displayTripMs);
    final hasVideo = _currentPath != null && !_segmentMissing;
    final maxMs = _durationMs > 0 ? _durationMs : 10 * 60 * 1000;
    final events = _segmentEvents;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(s.t('视频回顾', 'Video review'))),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, EdgeInsets.zero),
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
                      label: Text(s.t('第 ${i + 1} 段', 'Segment ${i + 1}')),
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
                  Center(
                    child: Text(s.t('暂无可播放的视频段', 'No playable video segment'),
                        style: const TextStyle(color: Colors.white54)),
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
                        child: _hudChip(s.t('行程+${_mmss(_displayTripMs - trip.startMs)}',
                            'Trip+${_mmss(_displayTripMs - trip.startMs)}')),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _hudChip(s.t(
                            '纵向 ${point.longG.toStringAsFixed(2)}g · 横向 ${point.latG.toStringAsFixed(2)}g',
                            'Long ${point.longG.toStringAsFixed(2)}g · lat ${point.latG.toStringAsFixed(2)}g')),
                      ),
                    ]),
                  ),
                // v1.3.6：地图仪表（与 HUD 同层逻辑，只在本页回放时叠加，
                // 不同步进导出的视频文件；同步精度为秒级，不是帧级）。
                // 画布区 IgnorePointer，只让角上的两个小按钮接收点击。
                if (!_gaugeHidden)
                  _gaugePositioned(
                    child: Stack(children: [
                      IgnorePointer(
                        child: VideoMapGauge(
                          points: trip.points,
                          current: point,
                          width: _gaugeWidth(context),
                          height: _gaugeWidth(context) * 112 / 148,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _gaugeButton(
                            Icons.swap_horiz,
                            s.t('切换位置（当前${_gaugePositionName(s)}）',
                                'Change position (now ${_gaugePositionName(s)})'),
                            () => setState(
                                () => _gaugePosition = _gaugePosition.next),
                          ),
                          _gaugeButton(
                            Icons.visibility_off,
                            s.t('隐藏地图仪表', 'Hide map gauge'),
                            () => setState(() => _gaugeHidden = true),
                          ),
                        ]),
                      ),
                    ]),
                  )
                else
                  Positioned(
                    right: 8,
                    top: 40,
                    child: _gaugeButton(
                      Icons.map,
                      s.t('显示地图仪表', 'Show map gauge'),
                      () => setState(() => _gaugeHidden = false),
                    ),
                  ),
              ]),
            ),
          ),
          // ---- 播放控制 ----
          Row(children: [
            Semantics(
              label: _playing ? s.t('暂停', 'Pause') : s.t('播放', 'Play'),
              child: IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: hasVideo && _prepared ? _togglePlay : null,
              ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  s.t('红点为本段事件，点即跳到事件前约 3 秒',
                      'Red dots mark events in this segment; tap to jump about 3 s before'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          // ---- HUD 数值（视频下方同步一份） ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: point == null
                ? Text(s.t('无轨迹点，HUD 无数据', 'No track points; no HUD data'))
                : Wrap(spacing: 16, runSpacing: 8, children: [
                    Text(
                        s.t('速度 ${(point.speed * 3.6).toStringAsFixed(0)} km/h',
                            'Speed ${(point.speed * 3.6).toStringAsFixed(0)} km/h'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(s.t('纵向 ${point.longG.toStringAsFixed(2)}g',
                        'Long ${point.longG.toStringAsFixed(2)}g')),
                    Text(s.t('横向 ${point.latG.toStringAsFixed(2)}g',
                        'Lat ${point.latG.toStringAsFixed(2)}g')),
                    Text(s.t('合成 ${point.combinedG.toStringAsFixed(2)}g',
                        'Combined ${point.combinedG.toStringAsFixed(2)}g')),
                    if (trip.mode == TripMode.moto)
                      Text(s.t('侧倾 ${point.roll.toStringAsFixed(0)}°',
                          'Lean ${point.roll.toStringAsFixed(0)}°')),
                    Text(s.t('行程 ${_dateTime(_displayTripMs)}',
                        'Trip ${_dateTime(_displayTripMs)}')),
                  ]),
          ),
          // ---- 边界情况明示 ----
          if (_videos.isEmpty)
            _WarnBanner(s.t('本行程未关联视频。下方仍可查看事件清单。',
                'No video is linked to this trip. The event list below is still available.')),
          if (_videos.isNotEmpty && _segmentMissing)
            _WarnBanner(s.t('当前段视频文件已缺失，无法应用内播放；可切换其他段。',
                'The current segment file is missing and cannot play in-app; switch to another segment.')),
          if (trip.points.length < 10)
            _WarnBanner(s.t('轨迹点过少（少于 10 个），HUD 与事件可能不完整。',
                'Too few track points (under 10); the HUD and events may be incomplete.')),
          if (_playerError != null) _WarnBanner(_playerError!),
          if (_videos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                  s.t('对齐：${_align.note}；画面与数值可能有 ≤250ms 延迟；跳转落点可能差 <1 秒。',
                      'Alignment: ${_align.note}; video and values may lag by up to 250 ms; jumps may be off by under 1 s.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                s.t('HUD 与地图仪表仅本页回放时叠加，未烧录进原视频；同步精度为秒级。',
                    'The HUD and map gauge are overlaid only during replay here and are not burned into the original video; sync is second-level.'),
                style: const TextStyle(color: Colors.orange, fontSize: 12)),
          ),
          // ---- 本段事件 ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(s.t('本段事件', 'Events in this segment'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(s.t('本段无事件', 'No events in this segment'),
                  style: const TextStyle(color: Colors.white54)),
            ),
          for (final e in events)
            ListTile(
              title: Text(s.t(
                '${_eventLabel(s, e)} · 视频内 ${_mmss(_eventSegmentMs(e)!)}（跳转到前 3 秒）',
                '${_eventLabel(s, e)} · at ${_mmss(_eventSegmentMs(e)!)} in video (jumps back 3 s)',
              )),
              subtitle: Text(s.t(
                '纵向 ${e.peakLongG.toStringAsFixed(2)}g · 横向 ${e.peakLatG.toStringAsFixed(2)}g · '
                '速度 ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h',
                'Long ${e.peakLongG.toStringAsFixed(2)}g · lat ${e.peakLatG.toStringAsFixed(2)}g · '
                'speed ${(e.entrySpeed * 3.6).toStringAsFixed(0)}→${(e.exitSpeed * 3.6).toStringAsFixed(0)} km/h',
              )),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => _jumpToEvent(e),
            ),
          // ---- 导出与备用入口 ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(s.t('复制事件清单', 'Copy event list')),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _exportText()));
                  if (mounted) {
                    showAppNotice(context,
                        s.t('事件时间戳清单已复制', 'Event timestamp list copied'),
                        AppNoticeKind.success);
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share),
                label: Text(_exporting
                    ? s.t('导出中…', 'Exporting…')
                    : s.t('分享事件清单文件', 'Share event list file')),
                onPressed: _exporting ? null : _shareEventList,
              ),
              if (_currentPath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text(s.t('系统播放器播放', 'Open in system player')),
                  onPressed: () => Native.playVideo(_currentPath!),
                ),
              if (_currentPath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.video_library),
                  label: Text(s.t('分享视频', 'Share video')),
                  onPressed: () => Native.shareFiles(
                      [_currentPath!], 'video/mp4',
                      s.t('驰迹行程视频', 'DriveTrack trip video')),
                ),
            ]),
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

  /// M5：回放地图仪表宽按屏宽比例缩放（窄屏/横屏不再占近半宽）。
  double _gaugeWidth(BuildContext context) =>
      math.min(148, MediaQuery.of(context).size.width * 0.36);

  /// v1.3.6：地图仪表按当前位置定位（默认右上，位于 HUD 时间条下方，
  /// 不遮 HUD；右下位于 G 值条对侧，同样不遮 HUD）。
  String _gaugePositionName(S s) => switch (_gaugePosition) {
        VideoGaugePosition.topLeft => s.t('左上', 'Top left'),
        VideoGaugePosition.topRight => s.t('右上', 'Top right'),
        VideoGaugePosition.bottomRight => s.t('右下', 'Bottom right'),
      };

  Widget _gaugePositioned({required Widget child}) {
    switch (_gaugePosition) {
      case VideoGaugePosition.topLeft:
        return Positioned(left: 8, top: 40, child: child);
      case VideoGaugePosition.topRight:
        return Positioned(right: 8, top: 40, child: child);
      case VideoGaugePosition.bottomRight:
        return Positioned(right: 8, bottom: 8, child: child);
    }
  }

  /// v1.3.6：仪表角上的小按钮（切换位置 / 隐藏 / 恢复显示）。
  Widget _gaugeButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Semantics(
        label: tooltip,
        button: true,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tooltip,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(icon, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
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
