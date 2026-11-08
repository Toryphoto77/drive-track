/// v1.2.1：赛道结束页永远不为空——无圈速时也完整展示本节传感器
/// 实测总览（里程/时长/平均/极速、速度曲线、G 值分布与 G-G 图、
/// 横/纵向 G 极值、海拔变化、轨迹走线图；摩托加压弯数据，骑行加
/// 配速分段），图表全部复用街道详情页的 trip_detail_modules.dart
/// 组件，不另造一套；有圈速时再叠加原有圈速总览/分段对比/得失曲线。
/// OBD 通道有实测采样时画真实 OBD 车速曲线 + 极值（只画实测采样，
/// 无采样不画曲线、不补点）；无采样时保留“未连接 OBD，暂无此通道”占位，
/// 绝不反推油门/刹车/转速曲线。赛道行程继续不评分。
///
/// v1.2.0 第 6 项：赛后独立赛道分析页（新增文件，不改动已有文件）。
///
/// 注意：这是独立的赛道分析页，不是街道版结束页的改版——收口接线时
/// 赛道行程结束跳转到本页，街道行程仍走原结束页。
///
/// 内容（用户定版）：
/// - 圈速总览：最佳圈、理论最佳圈（= 各分段最佳相加，见
///   track_sector_data.dart 的 analysisTheoreticalBestLapMs，与
///   直播页同口径并加真实分段门控）、圈速列表 +
///   无效圈标注（停留不计圈 / 分段缺失的圈不进最佳圈与理论圈统计）。
/// - 分段对比表：与赛中同色规则（delta < 0 绿、> 0 红、== 0 灰，
///   格里写带正负号的 delta 数字，不写中文“快/慢”）；注意与
///   track_viz.dart 的紫/绿/黄规则不同，本页不复用那套。
/// - 速度曲线 + 距离轴上的累计得失曲线、横向/纵向 G 曲线、按速度或
///   delta 着色的走线图；图表 X 轴捏合缩放 + 双击复位，单指 scrub
///   联动所有图表与走线，点分段可缩放到该分段。
/// - 圈次与参照圈选择器：参照圈默认本节最佳圈。
/// - OBD：已接 ELM327：行程 obdSamples（每秒一条实测采样）有数据时
///   画真实 OBD 车速曲线 + 极值；无采样时按 obdConnected 显示
///   “OBD 已连接，暂无数据”或“未连接 OBD，暂无此通道”，绝不反推
///   假油门/刹车/转速曲线。TrackPoint 本来就没有油门/刹车字段，
///   本页不造任何此类曲线。
/// - 赛道模式不评分：本页不显示、不计算任何评分。
/// - 第一版不做视频联动：本页不读 trip.videoPaths、不做视频同步。
///
/// v1.3.4：参考圈叠加——全程走线图卡（卫星 / 回落示意）叠加参照圈
/// 青色轨迹（开关默认开，只影响本页会话；无参照圈时开关不出现）；
/// 速度曲线在参照圈 ≠ 分析圈时加第二条青色虚线（按距离插值速度，
/// 见 _refSpeedAt）。只动这两处显示，不动任何计时与统计口径。
///
/// 数据口径：
/// - [laps] 由调用方传入（LapTimer.laps，或 Trip.lapsJson 解码
///   `trip.lapsJson.map((j) => Lap.fromJson(j)).toList()`）。
/// - 轨迹按 Lap.startMs/endMs 从 [trip].points 里按时间切片；
///   距离轴为切片内逐点 haversine 累计（实测轨迹距离，非目录长度）。
/// - 累计得失曲线 = 分析圈在某距离处的累计用时 − 参照圈在同一距离
///   处的累计用时（线性插值）；负 = 在该距离处比参照圈快。
/// - 扇区待核的赛道：分段表用“第 1 段/第 2 段…”通用标签，分段点
///   缩放不可用（无分界点可缩），界面写明原因，不硬标 S1/S2/S3。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'logic.dart';
import 'models.dart';
import 'replay_3d.dart';
import 'satellite_tiles.dart';
import 'track_analysis_geo.dart';
import 'trip_detail_modules.dart';
import 'track_sector_data.dart';
import 'track_session_display.dart';
import 'track_timing.dart';

const Color _kBg = Color(0xFF121212);
const Color _kCard = Color(0xFF141414);
const Color _kBorder = Color(0xFF2A2A2A);
const Color _kRed = Color(0xFFE10600);
const Color _kGreen = Color(0xFF22C55E);

/// v1.3.4：参考圈 / 幽灵车青色（与速度彩虹线、分析圈红色区分）。
const Color _kGhostCyan = Color(0xFF22D3EE);

/// 走线着色模式。
enum TrackLineColorMode { speed, delta }

/// 赛后独立赛道分析页。
class TrackAnalysisPage extends StatefulWidget {
  /// 赛道行程（含轨迹点；圈速见 [laps]）。
  final Trip trip;

  /// 本节全部圈（含无效圈；无效圈由 lapInvalidReason 标注并排除统计）。
  final List<Lap> laps;

  /// 参照圈；为 null 时默认本节最佳圈（sessionBestLap）。
  final Lap? referenceLap;

  /// OBD 是否已连接（行程结束时状态）；有实测采样时以采样为准，
  /// 无采样时按它显示“已连接暂无数据”或“未连接暂无此通道”，
  /// 不影响任何曲线（只画实测采样）。
  final bool obdConnected;

  /// 初始分析圈号；为 null 时默认最佳圈（无计入圈时取第一圈）。
  final int? initialLapNumber;

  /// 初始参照圈号；为 null 时默认最佳圈。
  final int? initialReferenceLapNumber;

  const TrackAnalysisPage({
    super.key,
    required this.trip,
    required this.laps,
    this.referenceLap,
    this.obdConnected = false,
    this.initialLapNumber,
    this.initialReferenceLapNumber,
  });

  @override
  State<TrackAnalysisPage> createState() => _TrackAnalysisPageState();
}

/// 一圈切片：轨迹点 + 累计距离 + 相对用时。
class _LapSlice {
  final List<TrackPoint> points;
  final List<double> distances; // m，首点为 0
  final List<int> elapsedMs; // 相对圈起点的 ms
  double get totalDistance => distances.isEmpty ? 0 : distances.last;
  _LapSlice(this.points, this.distances, this.elapsedMs);
}

_LapSlice _sliceLap(Trip trip, Lap lap) {
  final pts = trip.points
      .where((p) => p.timeMs >= lap.startMs && p.timeMs <= lap.endMs)
      .toList();
  final dists = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    dists.add(dists.last +
        haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon));
  }
  final elapsed = pts.map((p) => p.timeMs - lap.startMs).toList();
  return _LapSlice(pts, dists, elapsed);
}

/// 参照圈在距离 [d] 处的累计用时（线性插值，超界钳制到端点）。
double _refElapsedAt(_LapSlice ref, double d) {
  if (ref.points.isEmpty) return 0;
  if (d <= 0) return ref.elapsedMs.first.toDouble();
  if (d >= ref.totalDistance) return ref.elapsedMs.last.toDouble();
  for (var i = 1; i < ref.distances.length; i++) {
    if (ref.distances[i] >= d) {
      final d0 = ref.distances[i - 1];
      final d1 = ref.distances[i];
      final t0 = ref.elapsedMs[i - 1].toDouble();
      final t1 = ref.elapsedMs[i].toDouble();
      if (d1 <= d0) return t1;
      return t0 + (t1 - t0) * (d - d0) / (d1 - d0);
    }
  }
  return ref.elapsedMs.last.toDouble();
}

/// v1.3.4：参照圈在距离 [d] 处的速度（km/h，线性插值，超界钳制
/// 到端点）。口径与 [_refElapsedAt] 一致，只把插值量换成速度，
/// 供速度曲线画参照圈第二条线用。
double _refSpeedAt(_LapSlice ref, double d) {
  if (ref.points.isEmpty) return 0;
  double kmhAt(int i) => ref.points[i].speed * 3.6;
  if (d <= 0) return kmhAt(0);
  if (d >= ref.totalDistance) return kmhAt(ref.points.length - 1);
  for (var i = 1; i < ref.distances.length; i++) {
    if (ref.distances[i] >= d) {
      final d0 = ref.distances[i - 1];
      final d1 = ref.distances[i];
      final v0 = kmhAt(i - 1);
      final v1 = kmhAt(i);
      if (d1 <= d0) return v1;
      return v0 + (v1 - v0) * (d - d0) / (d1 - d0);
    }
  }
  return kmhAt(ref.points.length - 1);
}

class _TrackAnalysisPageState extends State<TrackAnalysisPage> {
  late Lap? _selected;
  late Lap? _reference;
  TrackLineColorMode _colorMode = TrackLineColorMode.speed;
  double _viewStart = 0;
  double _viewEnd = 1;
  double _scrub = 0;

  // v1.3.1：各区块隐藏开关（默认全部展开；只影响本页会话状态，
  // 不持久化、不影响任何统计口径）。
  bool _hideOverview = false;
  bool _hideSpeed = false;
  bool _hideG = false;
  bool _hideAltitude = false;
  bool _hideTrackLine = false;

  // v1.3.1：全程走线图底图切换（默认卫星；只影响本页会话状态）。
  // true = 卫星地图，false = 归一化示意图（弱网与色弱用户兜底）。
  bool _satelliteMap = true;

  // v1.3.7：全程走线图 3D 回放模式（默认关，用户主动切过去；
  // 只影响本页会话状态；开时卫星/示意两 chip 均不选中，走线图
  // 区改画 Replay3dView，参考圈叠加开关与图例不出现）。
  bool _replay3d = false;

  // v1.3.4：全程走线图参考圈叠加开关（默认开，只影响本页会话状态；
  // 无参照圈时开关不出现，见 _tripOverviewSection）。
  bool _showReferenceOverlay = true;

  TrackSectorData? get _sectorData => sectorDataFor(widget.trip.trackId);

  @override
  void initState() {
    super.initState();
    final best = sessionBestLap(widget.laps);
    Lap? byNumber(int? n) {
      if (n == null) return null;
      for (final l in widget.laps) {
        if (l.number == n) return l;
      }
      return null;
    }

    _selected = byNumber(widget.initialLapNumber) ??
        best ??
        (widget.laps.isEmpty ? null : widget.laps.first);
    _reference = widget.referenceLap ??
        byNumber(widget.initialReferenceLapNumber) ??
        best;
  }

  void _resetView() {
    setState(() {
      _viewStart = 0;
      _viewEnd = 1;
    });
  }

  /// v1.3.1：区块标题行 + 隐藏开关（眼睛图标；默认展开）。
  /// [keyName] 供 widget 测试定位开关；[hidden] 为当前隐藏状态。
  Widget _sectionHeader(
    String title,
    String keyName,
    bool hidden,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          key: ValueKey(keyName),
          icon: Icon(
            hidden ? Icons.visibility_off : Icons.visibility,
            color: Colors.white70,
            size: 20,
          ),
          tooltip: hidden ? '显示$title' : '隐藏$title',
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(!hidden),
        ),
      ],
    );
  }

  /// v1.2.1 本节传感器总览：全部由 widget.trip 的实测点算出，
  /// 点数不足时各复用组件自行显示“暂无”，不画假曲线、不编数。
  List<Widget> _tripOverviewSection() {
    final trip = widget.trip;
    final pts = trip.points;
    final durMs = trip.endMs - trip.startMs;
    final avgKmh =
        durMs > 0 ? (trip.distanceM / 1000) / (durMs / 3600000.0) : 0.0;
    final maxLong = pts.isEmpty
        ? 0.0
        : pts.map((p) => p.longG).reduce(math.max);
    final maxBrake = pts.isEmpty
        ? 0.0
        : -pts.map((p) => p.longG).reduce(math.min);
    final maxLat = pts.isEmpty
        ? 0.0
        : pts.map((p) => p.latG.abs()).reduce(math.max);
    final validAlts =
        pts.where((p) => p.altValid).map((p) => p.alt).toList();
    final altRange = validAlts.isEmpty
        ? '暂无海拔数据'
        : '${validAlts.reduce(math.min).toStringAsFixed(0)}–${validAlts.reduce(math.max).toStringAsFixed(0)} m · 累计爬升 ${trip.climbM.toStringAsFixed(0)} m';
    // 全程走线切片（复用本页 _TrackLineDiagram，按速度着色）。
    _LapSlice? wholeSlice;
    if (pts.length >= 2) {
      final dists = <double>[0];
      for (var i = 1; i < pts.length; i++) {
        dists.add(dists.last +
            haversineM(
                pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon));
      }
      wholeSlice = _LapSlice(
          pts, dists, pts.map((p) => p.timeMs - pts.first.timeMs).toList());
    }
    // v1.3.4：参照圈切片（与 Delta 用同一个 _reference 对象；点数
    // < 2 时不画叠加线）。全程走线图的底线是整节轨迹、不是分析圈，
    // 因此参照圈 = 分析圈时叠加仍有意义（青色标出该圈轨迹），不按
    // 速度曲线的“只画一条”门控隐藏。
    _LapSlice? refSlice;
    int? refLapNumber;
    if (_reference != null) {
      final s = _sliceLap(trip, _reference!);
      if (s.points.length >= 2) {
        refSlice = s;
        refLapNumber = _reference!.number;
      }
    }
    final showRefOverlay = _showReferenceOverlay && refSlice != null;
    final splits =
        trip.mode == TripMode.bike ? paceSplitsKm(pts) : const <double>[];
    final leanOver30 =
        trip.mode == TripMode.moto ? pts.where((p) => p.roll.abs() > 30).length : 0;
    return [
      const Text('本节行程总览 · 传感器实测',
          style: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _sectionHeader('总览', 'hide-overview', _hideOverview,
          (v) => setState(() => _hideOverview = v)),
      if (!_hideOverview) ...[
        TripOverviewCard(trip: trip),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('关键极值',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: [
                _stat('总里程', '${(trip.distanceM / 1000).toStringAsFixed(2)} km'),
                _stat('总时长', _fmtDur(durMs)),
                _stat('平均时速', '${avgKmh.toStringAsFixed(0)} km/h'),
                _stat('极速', '${(trip.maxSpeed * 3.6).toStringAsFixed(0)} km/h'),
                _stat('纵向 G 极值', '加速 ${maxLong.toStringAsFixed(2)}g / 刹车 ${maxBrake.toStringAsFixed(2)}g'),
                _stat('横向 G 极值', '${maxLat.toStringAsFixed(2)}g'),
                _stat('最大合成 G',
                    pts.isEmpty ? '暂无' : '${trip.maxG.toStringAsFixed(2)}g'),
              ]),
              const SizedBox(height: 8),
              Text('海拔变化：$altRange',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      _sectionHeader('速度曲线', 'hide-speed', _hideSpeed,
          (v) => setState(() => _hideSpeed = v)),
      if (!_hideSpeed) TripSpeedChartCard(points: pts, events: trip.events),
      const SizedBox(height: 12),
      _sectionHeader('G 值', 'hide-g', _hideG,
          (v) => setState(() => _hideG = v)),
      if (!_hideG) TripGChartCard(points: pts),
      const SizedBox(height: 12),
      _sectionHeader('海拔', 'hide-altitude', _hideAltitude,
          (v) => setState(() => _hideAltitude = v)),
      if (!_hideAltitude) TripAltitudeCard(points: pts),
      const SizedBox(height: 12),
      _sectionHeader('轨迹走线图', 'hide-track-line', _hideTrackLine,
          (v) => setState(() => _hideTrackLine = v)),
      if (!_hideTrackLine)
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // v1.3.1：底图切换（默认卫星；只影响本页会话状态）。
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    key: const ValueKey('analysis-map-satellite'),
                    label: const Text('卫星地图'),
                    selected: _satelliteMap && !_replay3d,
                    onSelected: (_) => setState(() {
                      _satelliteMap = true;
                      _replay3d = false;
                    }),
                  ),
                  ChoiceChip(
                    key: const ValueKey('analysis-map-schematic'),
                    label: const Text('示意地图'),
                    selected: !_satelliteMap && !_replay3d,
                    onSelected: (_) => setState(() {
                      _satelliteMap = false;
                      _replay3d = false;
                    }),
                  ),
                  // v1.3.7：3D 回放模式（与卫星/示意并列的切换，
                  // 不取代原有内容；默认仍是现有视图）。
                  ChoiceChip(
                    key: const ValueKey('analysis-map-3d-replay'),
                    label: const Text('3D 回放'),
                    selected: _replay3d,
                    onSelected: (_) =>
                        setState(() => _replay3d = true),
                  ),
                  // v1.3.4：参考圈叠加开关（默认开，只影响本页会话；
                  // 无参照圈时不出现，参照圈切片点数 < 2 时不画线；
                  // 3D 回放模式下不出现，叠加只属于卫星/示意图）。
                  if (_reference != null && !_replay3d)
                    ChoiceChip(
                      key: const ValueKey('reference-overlay-toggle'),
                      label: const Text('参考圈叠加'),
                      selected: _showReferenceOverlay,
                      onSelected: (_) => setState(() =>
                          _showReferenceOverlay = !_showReferenceOverlay),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_replay3d)
                Replay3dView(points: pts)
              else if (wholeSlice == null)
                const Text('暂无轨迹点，走线为空',
                    style: TextStyle(color: Colors.white54, fontSize: 12))
              else if (_satelliteMap)
                _SatelliteTrackMap(
                  slice: wholeSlice,
                  referenceSlice: refSlice,
                  referenceLapNumber: refLapNumber,
                  showReferenceOverlay: _showReferenceOverlay,
                )
              else
                _TrackLineDiagram(
                  slice: wholeSlice,
                  deltaCurve: List<double>.filled(pts.length, 0),
                  mode: TrackLineColorMode.speed,
                  scrubIndex: 0,
                  referenceSlice: showRefOverlay ? refSlice : null,
                ),
              const SizedBox(height: 6),
              Text(
                _replay3d
                    ? '3D 透视回放：仅作复盘示意，不用于计时判定'
                    : '走线按速度着色，仅作复盘示意，不用于计时判定',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              // v1.3.4：参考圈叠加图例（开关关 / 无参照圈 / 点数 < 2
              // 时不出现；圈号取自 _reference，不冒充最佳圈；
              // 3D 回放模式下不出现）。
              if (showRefOverlay && !_replay3d)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '青色 = 参照圈（第 $refLapNumber 圈）',
                    style: const TextStyle(
                        color: _kGhostCyan, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      if (trip.mode == TripMode.moto) ...[
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('压弯数据',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                  '最大压弯角 ${trip.maxLean.toStringAsFixed(0)}° · 超 30° 约 $leanOver30 秒（1Hz 采样点数）',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              const Text('仅手机固定在车上且标定后可信；未确认固定时仅作参考。',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ],
      if (trip.mode == TripMode.bike) ...[
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('配速分段',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (splits.isEmpty)
                const Text('不足 1 公里，暂无整公里配速分段',
                    style: TextStyle(color: Colors.white54, fontSize: 12))
              else
                for (var i = 0; i < splits.length; i++)
                  Text('第 ${i + 1} 公里：${splits[i].toStringAsFixed(2)} min/km',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ],
    ];
  }

  /// OBD 通道：只读本趟 [Trip.obdSamples]（每秒一条实测采样）。
  /// 有采样：画真实 OBD 车速曲线 + 极值（最高车速 / 转速 / 油门 /
  /// 水温，缺值那项不写数、不编数）；无采样：保留占位文案。
  Widget _obdSection() {
    final samples = widget.trip.obdSamples;
    final hasSamples = samples.isNotEmpty;
    List<double> speeds = const [];
    List<double> xs = const [];
    double? maxRpm;
    double? maxThr;
    double? maxCool;
    if (hasSamples) {
      speeds = samples
          .map((s) => (s['vKmh'] as num?)?.toDouble() ?? 0)
          .toList();
      final times =
          samples.map((s) => (s['t'] as num?)?.toInt() ?? 0).toList();
      final span = times.last - times.first;
      xs = span > 0
          ? times.map((t) => (t - times.first) / span).toList()
          : List<double>.filled(times.length, 0);
      for (final s in samples) {
        final rpm = (s['rpm'] as num?)?.toDouble();
        if (rpm != null) maxRpm = maxRpm == null ? rpm : math.max(maxRpm, rpm);
        final thr = (s['thr'] as num?)?.toDouble();
        if (thr != null) maxThr = maxThr == null ? thr : math.max(maxThr, thr);
        final cool = (s['cool'] as num?)?.toDouble();
        if (cool != null) {
          maxCool = maxCool == null ? cool : math.max(maxCool, cool);
        }
      }
    }
    final maxSpeed = speeds.isEmpty ? 0.0 : speeds.reduce(math.max);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OBD 通道',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('通道：车速 / 转速 / 油门 / 水温（ELM327 实测采样）',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          if (!hasSamples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                widget.obdConnected ? 'OBD 已连接，暂无数据' : '未连接 OBD，暂无此通道',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _stat('实测采样', '${samples.length} 条'),
              _stat('最高车速', '${maxSpeed.toStringAsFixed(0)} km/h'),
              _stat('最高转速',
                  maxRpm == null ? '—' : '${maxRpm.toStringAsFixed(0)} rpm'),
              _stat('最大油门',
                  maxThr == null ? '—' : '${maxThr.toStringAsFixed(0)} %'),
              _stat('最高水温',
                  maxCool == null ? '—' : '${maxCool.toStringAsFixed(0)} ℃'),
            ]),
            const SizedBox(height: 8),
            _chartTitle('OBD 车速（实测采样，未连接时段无曲线）'),
            _SeriesChart(
              xs: xs,
              series: [
                _Series(values: speeds, color: const Color(0xFF38BDF8)),
              ],
              viewStart: 0,
              viewEnd: 1,
              scrub: 0,
              unit: 'km/h',
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDur(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    if (m < 60) return '$m 分 ${s % 60} 秒';
    return '${m ~/ 60} 时 ${m % 60} 分';
  }

  void _zoomToSector(int index) {
    final range = sectorFractionRange(_sectorData, index);
    if (range == null) return;
    setState(() {
      // 留一点边距，避免分段恰好贴边。
      _viewStart = (range.start - 0.02).clamp(0.0, 1.0);
      _viewEnd = (range.end + 0.02).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final laps = widget.laps;
    final best = sessionBestLap(laps);
    // v1.2.15：理论最佳圈与直播页同口径（见
    // analysisTheoreticalBestLapMs）：先按最佳圈段数过滤，再加
    // 真实分段门控（最佳圈须 3 段）；无真实分段点时为 null，显示
    // 占位，不拿前后半圈拼一个假理论圈。
    final theoretical = analysisTheoreticalBestLapMs(laps);
    final counted = laps.where((l) => lapInvalidReason(l) == null).length;
    final sectorData = _sectorData;
    final selected = _selected;
    final reference = _reference;

    _LapSlice? selSlice;
    _LapSlice? refSlice;
    List<double> deltaCurve = const [];
    if (selected != null) {
      selSlice = _sliceLap(widget.trip, selected);
      if (reference != null && reference != selected) {
        refSlice = _sliceLap(widget.trip, reference);
        deltaCurve = [
          for (var i = 0; i < selSlice.points.length; i++)
            selSlice.elapsedMs[i].toDouble() -
                _refElapsedAt(refSlice, selSlice.distances[i]),
        ];
      } else {
        deltaCurve =
            List<double>.filled(selSlice.points.length, 0);
      }
    }
    final fractions = selSlice == null || selSlice.totalDistance <= 0
        ? <double>[]
        : selSlice.distances
            .map((d) => d / selSlice!.totalDistance)
            .toList();
    // v1.3.4：速度曲线参照圈第二条线——参照圈存在且不是当前分析圈
    // 且切片点数 >= 2 时才画；参照圈 = 分析圈时只画一条，不画假线。
    final showRefSpeedLine = selected != null &&
        reference != null &&
        reference.number != selected.number &&
        refSlice != null &&
        refSlice.points.length >= 2 &&
        selSlice != null;
    final refSpeedValues = showRefSpeedLine
        ? [
            for (final d in selSlice.distances) _refSpeedAt(refSlice, d),
          ]
        : null;
    // scrub 最近点下标（联动读数与走线高亮）。
    var scrubIndex = 0;
    if (fractions.isNotEmpty) {
      var bestDist = double.infinity;
      for (var i = 0; i < fractions.length; i++) {
        final d = (fractions[i] - _scrub).abs();
        if (d < bestDist) {
          bestDist = d;
          scrubIndex = i;
        }
      }
    }

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(widget.trip.trackName.isEmpty
            ? '赛道分析'
            : '${widget.trip.trackName} · 赛道分析'),
      ),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '赛道模式不评分',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            // v1.2.1：本节行程总览（传感器实测，永远展示）——无圈速时
            // 本节同样有内容，结束页绝不只剩标题。图表复用街道详情页
            // 的 TripOverviewCard / TripSpeedChartCard / TripGChartCard
            // / TripAltitudeCard，不另造一套；走线复用本页 _TrackLineDiagram。
            ..._tripOverviewSection(),
            const SizedBox(height: 12),
            // OBD 通道（实测采样才画曲线）：有 obdSamples 时画真实
            // OBD 车速曲线 + 极值；无采样时按 obdConnected 保留占位，
            // 绝不反推油门/刹车/转速曲线。
            _obdSection(),
            const SizedBox(height: 12),
            if (selected == null) ...[
              const Text(
                '暂无圈速数据：本节无计入圈。',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ] else ...[
              // 圈速总览。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '圈速总览',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _stat(
                              '最佳圈',
                              best == null
                                  ? '--:--.---'
                                  : LapTimer.formatLapTime(
                                      best.durationMs)),
                        ),
                        Expanded(
                          child: _stat(
                              '理论最佳圈',
                              theoretical == null
                                  ? '--:--.---'
                                  : LapTimer.formatLapTime(theoretical)),
                        ),
                        Expanded(
                          child: _stat('计入圈 / 全部',
                              '$counted / ${laps.length}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '理论最佳圈 = 各分段最佳相加；无效圈不进统计',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 圈次与参照圈选择器。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '分析圈',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final l in laps)
                          ChoiceChip(
                            label: Text(
                                '第 ${l.number} 圈'
                                '${lapInvalidReason(l) == null ? '' : ' · 无效'}'),
                            selected: selected.number == l.number,
                            onSelected: (_) => setState(() {
                              _selected = l;
                              _scrub = 0;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '参照圈（默认本节最佳圈）',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final l in laps
                            .where((x) => lapInvalidReason(x) == null))
                          ChoiceChip(
                            label: Text('第 ${l.number} 圈'),
                            selected: reference?.number == l.number,
                            onSelected: (_) =>
                                setState(() => _reference = l),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 分段对比表（与赛中同色规则）。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '分段对比',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sectorData == null
                          ? '扇区待核：未查到该赛道扇区数据，分段按计时分段显示'
                          : sectorData.sourceLabel == '扇区待核'
                              ? '${sectorData.note}分段按计时分段显示，不标官方 S1/S2/S3'
                              : '${sectorData.sourceLabel}：${sectorData.note}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    ..._sectorRows(selected, reference, sectorData),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 图表区：捏合缩放 + 双击复位 + 单指 scrub 联动。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '曲线（距离轴）',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _resetView,
                          child: const Text('整圈'),
                        ),
                      ],
                    ),
                    const Text(
                      '捏合缩放 · 双击复位整圈 · 横向拖动联动图表与走线 · 点分段缩放到该分段',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    if (sectorData != null &&
                        sectorData.hasBoundaries) ...[
                      Wrap(
                        spacing: 6,
                        children: [
                          for (var i = 0; i < 3; i++)
                            ActionChip(
                              label: Text('S${i + 1}'),
                              onPressed: () => _zoomToSector(i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    GestureDetector(
                      onDoubleTap: _resetView,
                      onScaleUpdate: (d) {
                        setState(() {
                          if (d.scale != 1.0) {
                            // 捏合缩放：以当前窗口中心缩放（手势区域宽度
                            // 未经布局确认时，不用 focalPoint 猜比例）。
                            final width = _viewEnd - _viewStart;
                            final newWidth =
                                (width / d.scale).clamp(0.05, 1.0);
                            final center = (_viewStart + _viewEnd) / 2;
                            _viewStart =
                                (center - newWidth / 2).clamp(0.0, 1.0);
                            _viewEnd =
                                (_viewStart + newWidth).clamp(0.0, 1.0);
                            if (_viewEnd - _viewStart < newWidth) {
                              _viewStart = _viewEnd - newWidth;
                            }
                          }
                          // scale == 1 时的单指拖动由
                          // onHorizontalDragUpdate 处理为 scrub。
                        });
                      },
                      onHorizontalDragUpdate: (d) {
                        // 以拖动增量按当前窗口宽度换算 scrub 步进：
                        // 整屏宽对应一个窗口宽度，方向与拖动一致。
                        setState(() {
                          _scrub = (_scrub +
                                  d.delta.dx /
                                      300 *
                                      (_viewEnd - _viewStart))
                              .clamp(0.0, 1.0);
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _chartTitle('速度'),
                          _SeriesChart(
                            xs: fractions,
                            series: [
                              _Series(
                                values: selSlice == null
                                    ? const <double>[]
                                    : selSlice.points
                                        .map((p) => p.speed * 3.6)
                                        .toList(),
                                color: _kRed,
                              ),
                              // v1.3.4：参照圈速度线（青色虚线，按距离
                              // 插值到分析圈的距离轴上；门控见
                              // showRefSpeedLine）。
                              if (showRefSpeedLine)
                                _Series(
                                  values: refSpeedValues!,
                                  color: _kGhostCyan,
                                  dashed: true,
                                ),
                            ],
                            viewStart: _viewStart,
                            viewEnd: _viewEnd,
                            scrub: _scrub,
                            sectorBoundaries:
                                sectorData?.boundaries ?? const [],
                            unit: 'km/h',
                          ),
                          // v1.3.4：速度曲线图例（只在画了第二条线时出现）。
                          if (showRefSpeedLine)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '红色 = 第 ${selected.number} 圈 · 青色 = 参照圈（第 ${reference.number} 圈）',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _chartTitle('累计得失（相对参照圈，负 = 更快）'),
                          _SeriesChart(
                            xs: fractions,
                            series: [
                              _Series(values: deltaCurve, color: _kGreen),
                            ],
                            viewStart: _viewStart,
                            viewEnd: _viewEnd,
                            scrub: _scrub,
                            sectorBoundaries:
                                sectorData?.boundaries ?? const [],
                            unit: 's',
                            isDeltaSeconds: true,
                            showZeroLine: true,
                          ),
                          const SizedBox(height: 8),
                          _chartTitle('横向 / 纵向 G'),
                          _SeriesChart(
                            xs: fractions,
                            series: [
                              _Series(
                                values: selSlice == null
                                    ? const <double>[]
                                    : selSlice.points
                                        .map((p) => p.latG)
                                        .toList(),
                                color: const Color(0xFF38BDF8),
                              ),
                              _Series(
                                values: selSlice == null
                                    ? const <double>[]
                                    : selSlice.points
                                        .map((p) => p.longG)
                                        .toList(),
                                color: const Color(0xFFF59E0B),
                              ),
                            ],
                            viewStart: _viewStart,
                            viewEnd: _viewEnd,
                            scrub: _scrub,
                            sectorBoundaries:
                                sectorData?.boundaries ?? const [],
                            unit: 'g',
                            showZeroLine: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // scrub 联动读数。
                    if (selSlice != null && selSlice.points.isNotEmpty)
                      Text(
                        '进度：${(_scrub * 100).toStringAsFixed(0)}% · '
                        '速度 ${(selSlice.points[scrubIndex].speed * 3.6).toStringAsFixed(0)} km/h · '
                        '得失 ${deltaCurve.isEmpty ? '--' : '${deltaCurve[scrubIndex] >= 0 ? '+' : ''}${(deltaCurve[scrubIndex] / 1000).toStringAsFixed(3)}s'} · '
                        '横向 G ${selSlice.points[scrubIndex].latG.toStringAsFixed(2)} · '
                        '纵向 G ${selSlice.points[scrubIndex].longG.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      )
                    else
                      const Text(
                        '该圈暂无轨迹点，曲线为空',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 走线图（按速度或 delta 着色）。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '走线',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('按速度着色'),
                          selected:
                              _colorMode == TrackLineColorMode.speed,
                          onSelected: (_) => setState(() =>
                              _colorMode = TrackLineColorMode.speed),
                        ),
                        ChoiceChip(
                          label: const Text('按 delta 着色'),
                          selected:
                              _colorMode == TrackLineColorMode.delta,
                          onSelected: (_) => setState(() =>
                              _colorMode = TrackLineColorMode.delta),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (selSlice == null || selSlice.points.length < 2)
                      const Text(
                        '该圈暂无轨迹点，走线为空',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12),
                      )
                    else
                      _TrackLineDiagram(
                        slice: selSlice,
                        deltaCurve: deltaCurve,
                        mode: _colorMode,
                        scrubIndex: scrubIndex,
                      ),
                    const Text(
                      '仅作复盘示意，不用于计时判定',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 圈速列表 + 无效圈标注。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '圈速列表',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final l in laps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '第 ${l.number} 圈',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ),
                            Text(
                              LapTimer.formatLapTime(l.durationMs),
                              style: TextStyle(
                                color: best?.number == l.number
                                    ? _kGreen
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (lapInvalidReason(l) != null)
                              Text(
                                lapInvalidReason(l)!,
                                style: const TextStyle(
                                    color: _kRed, fontSize: 12),
                              )
                            else if (best?.number == l.number)
                              const Text(
                                '最佳圈',
                                style: TextStyle(
                                    color: _kGreen, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '第一版不做视频联动',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: child,
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _chartTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  List<Widget> _sectorRows(
      Lap selected, Lap? reference, TrackSectorData? sectorData) {
    final n = math.max(
        selected.sectorsMs.length, reference?.sectorsMs.length ?? 0);
    if (n == 0) {
      return const [
        Text('暂无分段数据',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      ];
    }
    final rows = <Widget>[];
    for (var i = 0; i < n; i++) {
      final label = sectorData != null &&
              sectorData.hasBoundaries &&
              n == 3
          ? sectorData.sectorLabels[i]
          : '第 ${i + 1} 段';
      final sel = i < selected.sectorsMs.length
          ? selected.sectorsMs[i]
          : null;
      final ref = reference != null && i < reference.sectorsMs.length
          ? reference.sectorsMs[i]
          : null;
      final delta = (sel != null && ref != null) ? sel - ref : null;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ),
              Expanded(
                child: Text(
                  sel == null ? '--' : LapTimer.formatLapTime(sel),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  ref == null
                      ? '--'
                      : '参照 ${LapTimer.formatLapTime(ref)}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  LapTimer.formatDelta(delta),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: sectorDeltaColor(delta),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return rows;
  }
}

/// 一条曲线序列。
class _Series {
  final List<double> values;
  final Color color;

  /// v1.3.4：虚线（参照圈速度线用，与分析圈实线区分）。
  final bool dashed;
  const _Series(
      {required this.values, required this.color, this.dashed = false});
}

/// 距离轴曲线：X 为圈距离分数（受 viewStart/viewEnd 窗口缩放），
/// scrub 处画竖线；分段分界处画虚线；delta 曲线单位为 ms，显示时
/// 换算为秒（[isDeltaSeconds] 为 true 时 y 值除以 1000 取整显示）。
class _SeriesChart extends StatelessWidget {
  final List<double> xs;
  final List<_Series> series;
  final double viewStart;
  final double viewEnd;
  final double scrub;
  final List<double> sectorBoundaries;
  final String unit;
  final bool isDeltaSeconds;
  final bool showZeroLine;

  const _SeriesChart({
    required this.xs,
    required this.series,
    required this.viewStart,
    required this.viewEnd,
    required this.scrub,
    this.sectorBoundaries = const [],
    this.unit = '',
    this.isDeltaSeconds = false,
    this.showZeroLine = false,
  });

  @override
  Widget build(BuildContext context) {
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final s in series) {
      for (final v in s.values) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    if (minY == double.infinity) {
      minY = 0;
      maxY = 1;
    }
    if (minY == maxY) maxY = minY + 1;
    final pad = (maxY - minY) * 0.1;
    minY -= pad;
    maxY += pad;
    String fmt(double v) =>
        isDeltaSeconds ? (v / 1000).toStringAsFixed(2) : v.toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${fmt(maxY)} $unit',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
            Text('${fmt(minY)} $unit',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
          ],
        ),
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: CustomPaint(
            painter: _SeriesPainter(
              xs: xs,
              series: series,
              viewStart: viewStart,
              viewEnd: viewEnd,
              scrub: scrub,
              sectorBoundaries: sectorBoundaries,
              minY: minY,
              maxY: maxY,
              showZeroLine: showZeroLine,
            ),
          ),
        ),
      ],
    );
  }
}

class _SeriesPainter extends CustomPainter {
  final List<double> xs;
  final List<_Series> series;
  final double viewStart;
  final double viewEnd;
  final double scrub;
  final List<double> sectorBoundaries;
  final double minY;
  final double maxY;
  final bool showZeroLine;

  _SeriesPainter({
    required this.xs,
    required this.series,
    required this.viewStart,
    required this.viewEnd,
    required this.scrub,
    required this.sectorBoundaries,
    required this.minY,
    required this.maxY,
    required this.showZeroLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double xToDx(double x) {
      final t = ((x - viewStart) / (viewEnd - viewStart)).clamp(0.0, 1.0);
      return pad + t * w;
    }

    double yToDy(double y) {
      final t = ((y - minY) / (maxY - minY)).clamp(0.0, 1.0);
      return pad + (1 - t) * h;
    }

    // 分段分界虚线。
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (final b in sectorBoundaries) {
      if (b < viewStart || b > viewEnd) continue;
      final dx = xToDx(b);
      for (var y = pad; y < pad + h; y += 8) {
        canvas.drawLine(Offset(dx, y), Offset(dx, y + 4), dashPaint);
      }
    }
    // 零线（得失 / G 曲线）。
    if (showZeroLine && minY <= 0 && maxY >= 0) {
      canvas.drawLine(
        Offset(pad, yToDy(0)),
        Offset(pad + w, yToDy(0)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
    for (final s in series) {
      if (s.values.length < 2 || xs.length != s.values.length) continue;
      final pts = <Offset>[];
      for (var i = 0; i < xs.length; i++) {
        if (xs[i] < viewStart || xs[i] > viewEnd) continue;
        pts.add(Offset(xToDx(xs[i]), yToDy(s.values[i])));
      }
      if (pts.length < 2) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;
      if (s.dashed) {
        // v1.3.4：虚线（6px 线 / 4px 空，跨段连续不断档）。
        var drawOn = true;
        var remaining = 6.0;
        for (var i = 1; i < pts.length; i++) {
          final a = pts[i - 1];
          final b = pts[i];
          final segLen = (b - a).distance;
          if (segLen <= 0) continue;
          final dir = (b - a) / segLen;
          var travelled = 0.0;
          while (travelled < segLen) {
            final step = math.min(remaining, segLen - travelled);
            final p0 = a + dir * travelled;
            final p1 = a + dir * (travelled + step);
            if (drawOn) canvas.drawLine(p0, p1, paint);
            travelled += step;
            remaining -= step;
            if (remaining <= 0) {
              drawOn = !drawOn;
              remaining = drawOn ? 6.0 : 4.0;
            }
          }
        }
      } else {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    // scrub 竖线。
    if (scrub >= viewStart && scrub <= viewEnd) {
      final dx = xToDx(scrub);
      canvas.drawLine(
        Offset(dx, pad),
        Offset(dx, pad + h),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeriesPainter old) => true;
}

/// 走线图：归一化实测轨迹，按速度（白→红）或 delta（绿/红/灰）着色，
/// scrub 点画白芯红边圆点。
/// v1.3.4：[referenceSlice] 非 null 时把参照圈轨迹以青色单色线叠在
/// 其上（3px，与主线区分；全程走线卡的卫星回落 / 示意模式共用）。
class _TrackLineDiagram extends StatelessWidget {
  final _LapSlice slice;
  final List<double> deltaCurve;
  final TrackLineColorMode mode;
  final int scrubIndex;
  final _LapSlice? referenceSlice;

  const _TrackLineDiagram({
    required this.slice,
    required this.deltaCurve,
    required this.mode,
    required this.scrubIndex,
    this.referenceSlice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: CustomPaint(
        painter: _TrackLinePainter(
          slice: slice,
          deltaCurve: deltaCurve,
          mode: mode,
          scrubIndex: scrubIndex,
          referenceSlice: referenceSlice,
        ),
      ),
    );
  }
}

class _TrackLinePainter extends CustomPainter {
  final _LapSlice slice;
  final List<double> deltaCurve;
  final TrackLineColorMode mode;
  final int scrubIndex;
  final _LapSlice? referenceSlice;

  _TrackLinePainter({
    required this.slice,
    required this.deltaCurve,
    required this.mode,
    required this.scrubIndex,
    this.referenceSlice,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = slice.points;
    if (pts.length < 2) return;
    var minLat = pts.first.lat;
    var maxLat = pts.first.lat;
    var minLon = pts.first.lon;
    var maxLon = pts.first.lon;
    for (final p in pts) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    final spanLat = (maxLat - minLat).abs() < 1e-9 ? 1 : maxLat - minLat;
    final spanLon = (maxLon - minLon).abs() < 1e-9 ? 1 : maxLon - minLon;
    const pad = 14.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    // 等比缩放，居中。
    final scale = math.min(w / spanLon, h / spanLat);
    final offX = pad + (w - spanLon * scale) / 2;
    final offY = pad + (h - spanLat * scale) / 2;
    Offset toOffset(TrackPoint p) => Offset(
          offX + (p.lon - minLon) * scale,
          offY + (maxLat - p.lat) * scale,
        );
    final offsets = pts.map(toOffset).toList();

    var minSpeed = double.infinity;
    var maxSpeed = double.negativeInfinity;
    for (final p in pts) {
      if (p.speed < minSpeed) minSpeed = p.speed;
      if (p.speed > maxSpeed) maxSpeed = p.speed;
    }
    if (minSpeed == double.infinity) {
      minSpeed = 0;
      maxSpeed = 1;
    }
    if (maxSpeed <= minSpeed) maxSpeed = minSpeed + 1;

    for (var i = 1; i < offsets.length; i++) {
      final color = mode == TrackLineColorMode.speed
          ? Color.lerp(Colors.white54, _kRed,
                  (pts[i].speed - minSpeed) / (maxSpeed - minSpeed)) ??
              Colors.white54
          : (i < deltaCurve.length
              ? sectorDeltaColor(
                  deltaCurve[i].abs() < 0.5 ? 0 : deltaCurve[i].round())
              : Colors.white54);
      canvas.drawLine(
        offsets[i - 1],
        offsets[i],
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    // v1.3.4：参照圈叠加（青色单色 3px，画在主线之上；点数 < 2 不画）。
    final refPts = referenceSlice?.points;
    if (refPts != null && refPts.length >= 2) {
      final refOffsets = refPts.map(toOffset).toList();
      for (var i = 1; i < refOffsets.length; i++) {
        canvas.drawLine(
          refOffsets[i - 1],
          refOffsets[i],
          Paint()
            ..color = _kGhostCyan
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (scrubIndex >= 0 && scrubIndex < offsets.length) {
      canvas.drawCircle(offsets[scrubIndex], 7, Paint()..color = _kRed);
      canvas.drawCircle(
          offsets[scrubIndex], 3.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackLinePainter old) => true;
}

/// v1.3.1：全程走线卫星底图（地理版）。
///
/// 瓦片走 lib/satellite_tiles.dart（Esri World Imagery，z/y/x 顺序，
/// WGS-84 直用），落点换算走 lib/track_analysis_geo.dart 的
/// [AnalysisGeoProjector]（分析页自有 Mercator 投影，不复用编辑页
/// 的 EditorViewTransform）。轨迹只用 GPS 实测点，按速度彩虹着色
/// （蓝→绿→黄→红），图例区间取自本节实测最低–最高速度。
///
/// 回落：瓦片累计失败达到 [satelliteFallbackFailureThreshold]
/// （3 张）即自动回落归一化示意图，不弹错、不白屏，状态行写明
/// “卫星图未加载，已显示示意图”；卫星显示时写明署名
/// [satelliteTileAttribution]。不做离线瓦片下载，不做 3D 回放。
///
/// v1.3.4：参考圈叠加——[referenceSlice] 非 null 且
/// [showReferenceOverlay] 为真时，参照圈轨迹以青色单色线（3px）
/// 叠在速度彩虹轨迹之上；回落示意图时同样经 _TrackLineDiagram
/// 叠加，不丢参考圈。图例在调用方卡片内统一写（不冒充最佳圈）。
class _SatelliteTrackMap extends StatefulWidget {
  final _LapSlice slice;
  final _LapSlice? referenceSlice;
  final int? referenceLapNumber;
  final bool showReferenceOverlay;

  const _SatelliteTrackMap({
    required this.slice,
    this.referenceSlice,
    this.referenceLapNumber,
    this.showReferenceOverlay = true,
  });

  @override
  State<_SatelliteTrackMap> createState() => _SatelliteTrackMapState();
}

class _SatelliteTrackMapState extends State<_SatelliteTrackMap> {
  /// 已失败过的瓦片 URL（去重计数；单张失败只计一次）。
  final Set<String> _failedTileUrls = {};

  bool get _fallback =>
      shouldFallbackToSchematic(_failedTileUrls.length);

  void _onTileError(String url) {
    if (_failedTileUrls.contains(url)) return;
    _failedTileUrls.add(url);
    // 图片加载失败发生在帧外，此处经 post-frame 再刷新，避免
    // 在 build 期间 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.slice.points;
    if (pts.length < 2) {
      return const Text('暂无轨迹点，走线为空',
          style: TextStyle(color: Colors.white54, fontSize: 12));
    }
    if (_fallback) {
      // 回落示意图：复用现有归一化走线图，不画假线。
      // v1.3.4：回落时参考圈叠加同样保留（经 _TrackLineDiagram）。
      final refSlice = widget.referenceSlice;
      final showRef = widget.showReferenceOverlay &&
          refSlice != null &&
          refSlice.points.length >= 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrackLineDiagram(
            slice: widget.slice,
            deltaCurve: List<double>.filled(pts.length, 0),
            mode: TrackLineColorMode.speed,
            scrubIndex: 0,
            referenceSlice: showRef ? refSlice : null,
          ),
          const SizedBox(height: 6),
          const Text('卫星图未加载，已显示示意图',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );
    }
    final speedsKmh = pts.map((p) => p.speed * 3.6).toList();
    final minKmh = speedsKmh.reduce(math.min);
    final maxKmh = speedsKmh.reduce(math.max);
    final segments = speedLegendSegments(minKmh, maxKmh);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        const height = 220.0;
        final bounds = analysisGeoBounds(
          pts.map((p) => (lat: p.lat, lon: p.lon)).toList(),
        );
        if (bounds == null) {
          return const Text('暂无轨迹点，走线为空',
              style: TextStyle(color: Colors.white54, fontSize: 12));
        }
        final zoom = analysisGeoZoom(
          bounds: bounds,
          widthPx: width,
          heightPx: height,
        );
        final projector = AnalysisGeoProjector(
          bounds: bounds,
          zoom: zoom,
          size: Size(width, height),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  for (var y = projector.tileRange.y0;
                      y <= projector.tileRange.y1;
                      y++)
                    for (var x = projector.tileRange.x0;
                        x <= projector.tileRange.x1;
                        x++)
                      Positioned.fromRect(
                        rect: projector.tileScreenRect(x, y),
                        child: Image.network(
                          satelliteTileUrl(zoom, x, y),
                          key: ValueKey('analysis-sat-$zoom-$x-$y'),
                          headers: const {
                            'User-Agent': 'DriveTrack/1.5.3',
                          },
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) {
                            _onTileError(satelliteTileUrl(zoom, x, y));
                            return Container(
                                color: const Color(0xFF0A0A0A));
                          },
                        ),
                      ),
                  CustomPaint(
                    size: Size(width, height),
                    painter: _GeoTrackPainter(
                      projector: projector,
                      points: pts,
                      speedsKmh: speedsKmh,
                      minKmh: minKmh,
                      maxKmh: maxKmh,
                      // v1.3.4：参考圈叠加（青色单色线，画在彩虹轨迹之上）。
                      referencePoints:
                          (widget.showReferenceOverlay &&
                                  widget.referenceSlice != null &&
                                  widget.referenceSlice!.points.length >= 2)
                              ? widget.referenceSlice!.points
                              : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 速度图例：区间取自本节实测最低–最高速度。
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final s in segments)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${s.fromKmh.toStringAsFixed(0)}–${s.toKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              satelliteTileAttribution,
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

/// 地理版速度着色轨迹：按实测点投影落点，逐段彩虹着色。
/// v1.3.4：[referencePoints] 非 null 时再叠一条青色单色参考圈轨迹。
class _GeoTrackPainter extends CustomPainter {
  final AnalysisGeoProjector projector;
  final List<TrackPoint> points;
  final List<double> speedsKmh;
  final double minKmh;
  final double maxKmh;
  final List<TrackPoint>? referencePoints;

  _GeoTrackPainter({
    required this.projector,
    required this.points,
    required this.speedsKmh,
    required this.minKmh,
    required this.maxKmh,
    this.referencePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final offsets = points
        .map((p) => projector.project(p.lat, p.lon))
        .toList();
    for (var i = 1; i < offsets.length; i++) {
      canvas.drawLine(
        offsets[i - 1],
        offsets[i],
        Paint()
          ..color = speedToRainbowColor(speedsKmh[i], minKmh, maxKmh)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    final ref = referencePoints;
    if (ref != null && ref.length >= 2) {
      final refOffsets =
          ref.map((p) => projector.project(p.lat, p.lon)).toList();
      for (var i = 1; i < refOffsets.length; i++) {
        canvas.drawLine(
          refOffsets[i - 1],
          refOffsets[i],
          Paint()
            ..color = _kGhostCyan
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GeoTrackPainter old) => true;
}
