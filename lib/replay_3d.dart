/// v1.8.3：赛后分析页「3D 回放」。
///
/// 对齐竞品（Dragy 式）：真实卫星底图 + 速度彩色轨迹 + 相机跟随/
/// 全程俯瞰切换 + 速度/G 标注 + 参考圈 VS 双轨迹对比。
///
/// 只画本行程实测轨迹点（`Trip.points`），不插值、不编数：
/// - 轨迹点过少（<2 个）时显示占位文案，不启动回放；
/// - 回放按轨迹点时间戳推进（Timer 100ms 一跳 × 倍速），
///   位置取 [replayPointAt] 二分到的实测点，不插值造点；
/// - 速度/时间取当前实测点的 `speed` / `timeMs`，速度无效
///   （NaN / 负值）时不显示速度、不编数；
/// - 底图走 [mapTileSourceStore]（高德卫星 GCJ-02 / 谷歌卫星
///   WGS-84，与分析页同源同口径），叠加层坐标随源切换，保证
///   轨迹压在真实道路上；瓦片全失败时回落到深色网格，绝不纯黑；
/// - 速度着色复用 lib/track_analysis_geo.dart 的彩虹色阶。
///
/// 相机：跟随模式以当前点为中心拉近；全程模式把整条轨迹等比入画。
/// 不引入重型 3D 引擎，瓦片与投影复用分析页既有能力，保持流畅。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'amap_service.dart';
import 'map_tile_source.dart';
import 'models.dart';
import 'perspective_projection.dart';
import 'satellite_tiles.dart';
import 'track_analysis_geo.dart';
import 'video_map_gauge.dart';

/// 回放倍速（0.5×–4×：慢放看走线，4× 快速过整段）。
enum ReplaySpeed { x05, x1, x2, x4 }

extension ReplaySpeedLabel on ReplaySpeed {
  double get factor => switch (this) {
        ReplaySpeed.x05 => 0.5,
        ReplaySpeed.x1 => 1,
        ReplaySpeed.x2 => 2,
        ReplaySpeed.x4 => 4,
      };

  String get label => switch (this) {
        ReplaySpeed.x05 => '0.5x',
        ReplaySpeed.x1 => '1x',
        ReplaySpeed.x2 => '2x',
        ReplaySpeed.x4 => '4x',
      };
}

/// 回放总时长（毫秒，末点 − 首点）；点不足 2 个时为 0，不启动回放。
int replayTotalMs(List<TrackPoint> points) {
  if (points.length < 2) return 0;
  final total = points.last.timeMs - points.first.timeMs;
  return total > 0 ? total : 0;
}

/// 已播毫秒 → 轨迹点下标（二分取 timeMs ≤ 目标的最后一点，
/// 与 videoGaugePointIndex 同口径）；越界钳制到首/末点；
/// 点不足 2 个时返回 -1。
int replayPointIndex(List<TrackPoint> points, int elapsedMs) {
  if (points.length < 2) return -1;
  final target = points.first.timeMs + elapsedMs;
  if (target <= points.first.timeMs) return 0;
  if (target >= points.last.timeMs) return points.length - 1;
  var lo = 0, hi = points.length - 1, ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (points[mid].timeMs <= target) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// 已播毫秒 → 当前实测点；点不足 2 个时返回 null（不编点）。
TrackPoint? replayPointAt(List<TrackPoint> points, int elapsedMs) {
  final i = replayPointIndex(points, elapsedMs);
  return i < 0 ? null : points[i];
}

/// 已播毫秒 → 进度 0..1；总时长 ≤ 0 时为 0。
double replayProgressMs(int elapsedMs, int totalMs) {
  if (totalMs <= 0) return 0;
  return (elapsedMs / totalMs).clamp(0.0, 1.0);
}

/// 进度 0..1 → 已播毫秒（Slider 拖动后从拖到的点继续播）；
/// 越界钳制到 [0, totalMs]。
int replayElapsedFromProgress(double progress, int totalMs) {
  if (totalMs <= 0) return 0;
  return (progress.clamp(0.0, 1.0) * totalMs).round();
}

/// 一跳推进的毫秒数（定时器间隔 × 倍速）。
int replayAdvanceMs(int tickMs, ReplaySpeed speed) =>
    (tickMs * speed.factor).round();

/// 毫秒 → m:ss（≥ 1 小时时 h:mm:ss），只用于回放读数显示。
String replayTimeLabel(int ms) {
  final totalSeconds = (ms / 1000).round();
  final s = totalSeconds % 60;
  final m = (totalSeconds ~/ 60) % 60;
  final h = totalSeconds ~/ 3600;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$m:$ss';
}

/// 圈速差文本（当前圈 − 对比圈）：负 = 更快，正 = 更慢。
/// 任一圈速缺失时返回 null（不编数）；|差| < 0.05s 记为持平。
String? replayLapDeltaLabel(int? currentLapMs, int? referenceLapMs) {
  if (currentLapMs == null || referenceLapMs == null) return null;
  final diffSec = (currentLapMs - referenceLapMs) / 1000.0;
  final abs = diffSec.abs().toStringAsFixed(1);
  if (diffSec.abs() < 0.05) return '±0.0 s';
  return diffSec > 0 ? '+$abs s' : '−$abs s';
}

/// 3D 回放投影中心：北向上固定视口，中心纬度取轨迹南缘外
/// 约 55 米（0.0005 度），使全部点前向距离 > 0、透视因子 < 1；
/// 中心经度取轨迹东西中点。点不足 2 个或全部重合时返回 null。
({double centerLat, double centerLon})? replayProjectionCenter(
    List<TrackPoint> points) {
  if (points.length < 2) return null;
  var minLat = points.first.lat;
  var maxLat = points.first.lat;
  var minLon = points.first.lon;
  var maxLon = points.first.lon;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  if ((maxLat - minLat).abs() < 1e-9 && (maxLon - minLon).abs() < 1e-9) {
    return null;
  }
  return (
    centerLat: minLat - 0.0005,
    centerLon: (minLon + maxLon) / 2,
  );
}

/// 3D 回放横向比例（像素/米）：以 pxPerM=1 投影全部实测点，
/// 取横向跨度，等比适配到画布宽度的 92%；跨度 < 1 米时回落
/// 记录页 zoom 16 默认比例（画布宽 / 170），不除零、不爆缩。
double replayPxPerM({
  required Size size,
  required List<TrackPoint> points,
  required double centerLat,
  required double centerLon,
}) {
  if (size.width <= 0) return 1;
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  for (final p in points) {
    final o = perspectiveProjectLatLon(
      size: size,
      centerLat: centerLat,
      centerLon: centerLon,
      headingDeg: 0,
      headingUp: false,
      lat: p.lat,
      lon: p.lon,
      pxPerM: 1,
      is3d: true,
    );
    if (o.dx < minX) minX = o.dx;
    if (o.dx > maxX) maxX = o.dx;
  }
  final span = maxX - minX;
  if (span < 1) return size.width / 170;
  return size.width * 0.92 / span;
}

/// 3D 回放视图：3D 透视地图 + 播放条（播放/暂停、进度拖动、
/// 倍速）+ 当前速度与时间读数。只动回放显示，不动任何计时与
/// 统计口径；切出页面 / dispose 时停掉定时器，不泄漏。
class Replay3dView extends StatefulWidget {
  final List<TrackPoint> points;

  /// 参考圈实测点（VS 对比用）；为空时只画本圈。
  final List<TrackPoint>? referencePoints;
  final double height;

  /// 当前圈圈号 / 用时（圈速差用）；无圈（公路行程）时为 null。
  final int? currentLapNumber;
  final int? referenceLapNumber;
  final int? currentLapMs;
  final int? referenceLapMs;

  const Replay3dView({
    super.key,
    required this.points,
    this.referencePoints,
    this.height = 260,
    this.currentLapNumber,
    this.referenceLapNumber,
    this.currentLapMs,
    this.referenceLapMs,
  });

  @override
  State<Replay3dView> createState() => _Replay3dViewState();
}

class _Replay3dViewState extends State<Replay3dView> {
  int _elapsedMs = 0;
  bool _playing = false;
  ReplaySpeed _speed = ReplaySpeed.x1;

  /// 相机模式：true = 跟随车头（默认，与记录页一致）；false = 全程俯瞰
  /// （整条轨迹固定入画，便于看整体走线）。
  bool _follow = true;
  Timer? _timer;

  int get _totalMs => replayTotalMs(widget.points);

  int get _index => replayPointIndex(widget.points, _elapsedMs);

  TrackPoint? get _current =>
      _index < 0 ? null : widget.points[_index];

  @override
  void initState() {
    super.initState();
    // 地图源切换（高德 ↔ 谷歌）时重建底图与坐标口径。
    mapTileSourceStore.addListener(_onMapSourceChanged);
    mapTileSourceStore.load();
  }

  void _onMapSourceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant Replay3dView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换分析圈 / 轨迹集合时从头回放，避免沿旧进度显示新轨迹。
    // 用端点内容比较而非 List 身份：父级每次 build 都会重建切片列表，
    // 若按身份比较会导致回放进度被反复清零。
    if (!_sameTrack(oldWidget.points, widget.points)) {
      _stopTimer();
      _playing = false;
      _elapsedMs = 0;
    } else if (_elapsedMs > _totalMs) {
      _elapsedMs = _totalMs;
    }
  }

  static bool _sameTrack(List<TrackPoint> a, List<TrackPoint> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length || a.isEmpty) return a.length == b.length;
    final f1 = a.first, f2 = b.first, l1 = a.last, l2 = b.last;
    return f1.timeMs == f2.timeMs &&
        f1.lat == f2.lat &&
        f1.lon == f2.lon &&
        l1.timeMs == l2.timeMs &&
        l1.lat == l2.lat &&
        l1.lon == l2.lon;
  }

  @override
  void dispose() {
    mapTileSourceStore.removeListener(_onMapSourceChanged);
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final next = _elapsedMs + replayAdvanceMs(100, _speed);
      if (next >= _totalMs) {
        setState(() {
          _elapsedMs = _totalMs;
          _playing = false;
        });
        _stopTimer();
      } else {
        setState(() => _elapsedMs = next);
      }
    });
  }

  void _togglePlay() {
    if (_totalMs <= 0) return;
    if (_playing) {
      setState(() => _playing = false);
      _stopTimer();
      return;
    }
    setState(() {
      if (_elapsedMs >= _totalMs) _elapsedMs = 0;
      _playing = true;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            '轨迹点不足，无法 3D 回放',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final totalMs = _totalMs;
    if (totalMs <= 0) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            '轨迹时长无效，无法 3D 回放',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final current = _current;
    final speedKmh =
        current == null ? null : videoGaugeSpeedKmh(current);
    final rawG = current == null ? null : current.combinedG;
    final g = (rawG != null && rawG.isFinite) ? rawG : null;
    final hasRef =
        widget.referencePoints != null && widget.referencePoints!.length >= 2;
    final deltaLabel =
        replayLapDeltaLabel(widget.currentLapMs, widget.referenceLapMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      if (size.isEmpty) return const SizedBox.shrink();
                      final useGcj = mapTileSourceStore.source.usesGcj;
                      final cur = _current;
                      // 坐标口径随底图源：高德 GCJ-02 需先转换，谷歌 WGS-84 直用。
                      List<(double lat, double lon)> convert(
                              List<TrackPoint> ps) =>
                          useGcj
                              ? [
                                  for (final p in ps)
                                    wgsToGcjLocal(p.lat, p.lon)
                                ]
                              : [for (final p in ps) (p.lat, p.lon)];
                      final geo = convert(widget.points);
                      final refGeo = widget.referencePoints == null
                          ? null
                          : convert(widget.referencePoints!);
                      final maxZoom =
                          useGcj ? amapSatelliteMaxZoom : googleTileMaxZoom;
                      List<({double lat, double lon})> named(
                              List<(double, double)> ps) =>
                          [for (final g in ps) (lat: g.$1, lon: g.$2)];
                      // 相机：跟随 = 当前点小框拉近；全程 = 整条轨迹等比入画。
                      final curGeo = cur == null ? null : convert([cur]).first;
                      final followNamed = curGeo == null
                          ? null
                          : [
                              (lat: curGeo.$1 - 0.002, lon: curGeo.$2 - 0.002),
                              (lat: curGeo.$1 + 0.002, lon: curGeo.$2 + 0.002),
                            ];
                      final bounds = (_follow && followNamed != null)
                          ? analysisGeoBounds(followNamed)
                          : analysisGeoBounds(named(geo));
                      if (bounds == null) {
                        return const Center(
                          child: Text(
                            '轨迹范围无效',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        );
                      }
                      final zoom = analysisGeoZoom(
                        bounds: bounds,
                        widthPx: size.width,
                        heightPx: size.height,
                        maxZoom: maxZoom,
                      );
                      final projector = AnalysisGeoProjector(
                        bounds: bounds,
                        zoom: zoom,
                        size: size,
                      );
                      return ColoredBox(
                        color: const Color(0xFF0A0A0A),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _ReplaySatelliteLayer(
                                projector: projector,
                                useGcj: useGcj,
                              ),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ReplayOverlayPainter(
                                  projector: projector,
                                  geo: geo,
                                  refGeo: refGeo,
                                  points: widget.points,
                                  currentIndex: _index,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // 左上：当前速度 / G 值徽标（实测读数，无效不显示）。
                if (speedKmh != null || g != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _ReplayBadge(
                      key: const ValueKey('replay-3d-readout'),
                      text: [
                        if (speedKmh != null)
                          '${speedKmh.toStringAsFixed(0)} km/h',
                        if (g != null) '${g.toStringAsFixed(2)} G',
                      ].join(' · '),
                    ),
                  ),
                // 右上：当前底图源（高德 / 谷歌），随设置切换。
                Positioned(
                  right: 8,
                  top: 8,
                  child: _ReplayBadge(
                    text: '${mapTileSourceStore.source.label}卫星',
                    color: const Color(0xFF22D3EE),
                  ),
                ),
                // 左下：VS 双轨迹图例。
                if (hasRef)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        _ReplayBadge(
                          text:
                              '本圈${widget.currentLapNumber != null ? ' ${widget.currentLapNumber}' : ''}',
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        _ReplayBadge(
                          text:
                              '对比圈${widget.referenceLapNumber != null ? ' ${widget.referenceLapNumber}' : ''}',
                          color: const Color(0xFF22D3EE),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // VS 圈速差：有当前圈与对比圈用时才显示（不编数）。
        if (deltaLabel != null && hasRef)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '第 ${widget.currentLapNumber ?? '-'} 圈 '
              '${replayTimeLabel(widget.currentLapMs ?? 0)} vs 第 '
              '${widget.referenceLapNumber ?? '-'} 圈 '
              '${replayTimeLabel(widget.referenceLapMs ?? 0)} · VS $deltaLabel',
              key: const ValueKey('replay-3d-lap-delta'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              key: const ValueKey('replay-3d-play-pause'),
              icon: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              tooltip: _playing ? '暂停' : '播放',
              onPressed: _togglePlay,
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('replay-3d-slider'),
                value: _elapsedMs.toDouble().clamp(
                    0.0, totalMs > 0 ? totalMs.toDouble() : 1.0),
                min: 0,
                max: totalMs > 0 ? totalMs.toDouble() : 1.0,
                onChanged: totalMs > 0
                    ? (v) => setState(() => _elapsedMs = v.round())
                    : null,
              ),
            ),
            Text(
              '${replayTimeLabel(_elapsedMs)} / ${replayTimeLabel(totalMs)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        Row(
          children: [
            // 速度无效时不显示速度，不编数。
            if (speedKmh != null)
              Text(
                '${speedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (g != null)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  'G ${g.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            const Spacer(),
            ChoiceChip(
              key: const ValueKey('replay-3d-follow'),
              label: Text(_follow ? '跟随' : '全程'),
              selected: _follow,
              onSelected: (v) => setState(() => _follow = v),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in ReplaySpeed.values)
              ChoiceChip(
                key: ValueKey('replay-3d-speed-${s.label}'),
                label: Text(s.label),
                selected: _speed == s,
                onSelected: (_) => setState(() => _speed = s),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }
}

/// 回放地图上的小徽标（深色半透明底 + 彩点 / 文本）。
class _ReplayBadge extends StatelessWidget {
  final String text;
  final Color? color;

  const _ReplayBadge({super.key, this.text = '', this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// 回放卫星底图层：按地图源设置拉真实卫星瓦片（高德 GCJ-02 / 谷歌
/// WGS-84），与叠加层共用同一 [AnalysisGeoProjector]，保证轨迹压在
/// 真实道路上。瓦片累计失败达阈值时回落到深色网格 + 重试，绝不纯黑。
class _ReplaySatelliteLayer extends StatefulWidget {
  final AnalysisGeoProjector projector;
  final bool useGcj;

  const _ReplaySatelliteLayer({
    required this.projector,
    required this.useGcj,
  });

  @override
  State<_ReplaySatelliteLayer> createState() => _ReplaySatelliteLayerState();
}

class _ReplaySatelliteLayerState extends State<_ReplaySatelliteLayer> {
  final Set<String> _failed = {};
  int _retryKey = 0;

  @override
  void initState() {
    super.initState();
    mapTileSourceStore.addListener(_onStoreChanged);
    mapTileSourceStore.load();
  }

  @override
  void dispose() {
    mapTileSourceStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {
        _failed.clear();
        _retryKey++;
      });
    }
  }

  void _retry() {
    setState(() {
      _failed.clear();
      _retryKey++;
    });
  }

  String _tileUrl(int z, int x, int y) => widget.useGcj
      ? amapSatelliteTileUrl(z, x, y)
      : satelliteTileUrlFor(MapTileSource.google, z, x, y);

  Widget _tile(AnalysisGeoProjector p, int x, int y) {
    final r = p.tileScreenRect(x, y);
    final url = _tileUrl(p.zoom, x, y);
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: Image.network(
        url,
        // 重试 / 切源时换 key，强制重新发起请求。
        key: ValueKey(
          'replay-sat-${widget.useGcj ? 'gcj' : 'wgs'}'
          '-$_retryKey-${p.zoom}-$x-$y',
        ),
        fit: BoxFit.fill,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) {
          if (_failed.add(url)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projector = widget.projector;
    if (shouldFallbackToSchematic(_failed.length)) {
      // 深色网格占位 + 重试：绝不整屏纯黑，也不贴错误码图。
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ReplayGridPainter(),
              size: Size.infinite,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.satellite_alt_outlined,
                    color: Colors.white38, size: 30),
                const SizedBox(height: 6),
                const Text(
                  '卫星底图加载失败',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _retry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      '重试',
                      style: TextStyle(
                        color: Color(0xFF22D3EE),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final tr = projector.tileRange;
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: const Color(0xFF0A0A0A)),
        ),
        for (var x = tr.x0; x <= tr.x1; x++)
          for (var y = tr.y0; y <= tr.y1; y++) _tile(projector, x, y),
      ],
    );
  }
}

/// 回放叠加层：速度彩色轨迹（已播彩虹 / 未播暗）、参考圈 VS 对比、
/// 起终点 / 当前点标记、速度标注与图例。与底图共用同一投影。
class _ReplayOverlayPainter extends CustomPainter {
  final AnalysisGeoProjector projector;
  final List<(double lat, double lon)> geo;
  final List<(double lat, double lon)>? refGeo;
  final int currentIndex;
  final List<TrackPoint> points;

  _ReplayOverlayPainter({
    required this.projector,
    required this.geo,
    this.refGeo,
    required this.currentIndex,
    required this.points,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (geo.length < 2) return;
    Offset proj((double lat, double lon) g) => projector.project(g.$1, g.$2);
    final projected = geo.map(proj).toList();

    // 未播部分：暗色主线。
    final dimPath = Path();
    for (var i = 0; i < projected.length; i++) {
      if (i == 0) {
        dimPath.moveTo(projected[i].dx, projected[i].dy);
      } else {
        dimPath.lineTo(projected[i].dx, projected[i].dy);
      }
    }
    canvas.drawPath(
      dimPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // 已播部分：速度彩虹着色（区间取自本节实测速度）。
    final speedsKmh =
        points.map((p) => p.speed * 3.6).where((v) => v.isFinite).toList();
    final minKmh = speedsKmh.isEmpty ? 0.0 : speedsKmh.reduce(math.min);
    final maxKmh = speedsKmh.isEmpty ? 0.0 : speedsKmh.reduce(math.max);
    final playedEnd = currentIndex.clamp(0, points.length - 1);
    for (var i = 1; i <= playedEnd; i++) {
      final midKmh = (points[i - 1].speed + points[i].speed) / 2 * 3.6;
      canvas.drawLine(
        projected[i - 1],
        projected[i],
        Paint()
          ..color = speedToRainbowColor(midKmh, minKmh, maxKmh)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // 参考圈 VS 对比：青色单色线画在本圈之上，两条轨迹同屏可辨。
    final ref = refGeo;
    if (ref != null && ref.length >= 2) {
      final rp = ref.map(proj).toList();
      final paint = Paint()
        ..color = const Color(0xFF22D3EE)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < rp.length; i++) {
        canvas.drawLine(rp[i - 1], rp[i], paint);
      }
    }

    // 起点绿点 / 终点白点（实测首末点，不编位置）。
    canvas.drawCircle(projected.first, 5, Paint()..color = Colors.greenAccent);
    canvas.drawCircle(projected.last, 5, Paint()..color = Colors.white);

    // 当前位置：白心红环。
    if (currentIndex >= 0 && currentIndex < projected.length) {
      final pos = projected[currentIndex];
      canvas.drawCircle(pos, 4, Paint()..color = Colors.white);
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 速度标注 + 图例（画在最上层，不随相机变形）。
    _paintSpeedLabels(canvas, size, projected, minKmh, maxKmh);
    _paintLegend(canvas, size, minKmh, maxKmh);
  }

  void _paintSpeedLabels(
    Canvas canvas,
    Size size,
    List<Offset> projected,
    double minKmh,
    double maxKmh,
  ) {
    if (projected.length < 3) return;
    const ts = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );
    const samples = 5;
    final step =
        (projected.length / samples).floor().clamp(1, projected.length);
    for (var i = 0; i < projected.length; i += step) {
      final kmh = points[i].speed * 3.6;
      if (!kmh.isFinite || kmh < 0) continue;
      final tp = TextPainter(
        text: TextSpan(text: '${kmh.toStringAsFixed(0)}', style: ts),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = projected[i];
      final bg = Rect.fromLTWH(
        pos.dx - tp.width / 2 - 2,
        pos.dy - tp.height - 6,
        tp.width + 4,
        tp.height + 2,
      );
      canvas.drawRect(
        bg,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height - 5));
    }
  }

  void _paintLegend(
    Canvas canvas,
    Size size,
    double minKmh,
    double maxKmh,
  ) {
    const w = 110.0;
    const h = 6.0;
    final left = size.width - w - 10;
    final top = size.height - 18;
    final rect = Rect.fromLTWH(left, top, w, h);
    final shader = const LinearGradient(
      colors: [
        Color(0xFF2563EB),
        Color(0xFF22C55E),
        Color(0xFFFACC15),
        Color(0xFFE10600),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
    const ts = TextStyle(color: Colors.white70, fontSize: 9);
    final a = TextPainter(
      text: TextSpan(text: '${minKmh.toStringAsFixed(0)}', style: ts),
      textDirection: TextDirection.ltr,
    )..layout();
    final b = TextPainter(
      text: TextSpan(text: '${maxKmh.toStringAsFixed(0)} km/h', style: ts),
      textDirection: TextDirection.ltr,
    )..layout();
    a.paint(canvas, Offset(left, top - 12));
    b.paint(canvas, Offset(left + w - b.width, top - 12));
  }

  @override
  bool shouldRepaint(covariant _ReplayOverlayPainter old) =>
      old.currentIndex != currentIndex ||
      old.projector != projector ||
      old.geo != geo ||
      old.refGeo != refGeo;
}

/// 瓦片失败回落：深色网格，避免纯黑。
class _ReplayGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0A0A),
    );
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReplayGridPainter old) => false;
}
