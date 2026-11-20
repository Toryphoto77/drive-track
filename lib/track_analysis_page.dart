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

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ai_analysis_service.dart';
import 'ai_settings_page.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'corner_analysis.dart';
import 'dt_page_route.dart';
import 'lap_speed_delta.dart';
import 'logic.dart';
import 'models.dart';
import 'replay_3d.dart';
import 'satellite_tiles.dart';
import 'track_analysis_geo.dart';
import 'trip_detail_modules.dart';
import 'track_catalog.dart';
import 'track_sector_data.dart';
import 'track_session_display.dart';
import 'track_timing.dart';
import 'track_widgets.dart';
import 'voice_service.dart';

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
    dists.add(
      dists.last +
          haversineM(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon),
    );
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
  bool _hideAltitude = false;
  bool _hideTrackLine = false;

  // v1.3.1：全程走线图底图切换（默认卫星；只影响本页会话状态）。
  // true = 卫星地图，false = 归一化示意图（弱网与色弱用户兜底）。
  bool _satelliteMap = true;

  // 赛道库轮廓视图：与赛道库/赛道详情页同一 TrackInfo.outline 数据源，
  // 保证结算页看到的赛道形状与赛道库一致（轮廓为示意，非官方测绘）。
  bool _catalogView = false;

  // v1.3.7：全程走线图 3D 回放模式（默认关，用户主动切过去；
  // 只影响本页会话状态；开时卫星/示意两 chip 均不选中，走线图
  // 区改画 Replay3dView，参考圈叠加开关与图例不出现）。
  bool _replay3d = false;

  // v1.3.4：全程走线图参考圈叠加开关（默认开，只影响本页会话状态；
  // 无参照圈时开关不出现，见 _tripOverviewSection）。
  bool _showReferenceOverlay = true;

  // v1.7.0：AI 分析。配置只从本机读取；只有用户点“生成分析”时
  // 才发请求，结果不落盘，切走即丢。
  final AiAnalysisService _aiService = AiAnalysisService();
  AiSettings _aiSettings = AiSettings.defaults;
  bool _aiBusy = false;
  String? _aiResult;
  String? _aiError;

  TrackSectorData? get _sectorData => sectorDataFor(widget.trip.trackId);

  /// 赛道库目录里的同名赛道（用于轮廓对齐；查不到返回 null，不编造）。
  TrackInfo? get _catalogTrack => trackById(widget.trip.trackId);

  @override
  void initState() {
    super.initState();
    AiSettingsStore.load().then((settings) {
      if (mounted) setState(() => _aiSettings = settings);
    });
    final best = sessionBestLap(widget.laps);
    Lap? byNumber(int? n) {
      if (n == null) return null;
      for (final l in widget.laps) {
        if (l.number == n) return l;
      }
      return null;
    }

    _selected =
        byNumber(widget.initialLapNumber) ??
        best ??
        (widget.laps.isEmpty ? null : widget.laps.first);
    _reference =
        widget.referenceLap ??
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
    final s = S.of(context);
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
          tooltip: hidden
              ? s.t('显示$title', 'Show $title')
              : s.t('隐藏$title', 'Hide $title'),
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(!hidden),
        ),
      ],
    );
  }

  /// 扇区来源标签来自数据层（中文），英文界面在此转写。
  String _sectorSourceLabel(S s, String label) {
    if (s.zh) return label;
    return switch (label) {
      '官方扇区' => 'Official sectors',
      '估算分段' => 'Estimated sectors',
      '扇区待核' => 'Sector data pending',
      _ => label,
    };
  }

  /// 无效圈原因来自数据层（中文），英文界面在此转写，不改数据源。
  String _invalidReasonText(S s, Lap lap) {
    final reason = lapInvalidReason(lap);
    if (reason == null) return '';
    if (s.zh) return reason;
    return switch (reason) {
      '无效圈 · 停留不计圈' => 'Invalid · stopped, not counted',
      '无效圈 · 分段缺失' => 'Invalid · missing sectors',
      _ => reason,
    };
  }

  /// v1.3.1 本节传感器总览：全部由 widget.trip 的实测点算出，
  /// 点数不足时各复用组件自行显示“暂无”，不画假曲线、不编数。
  List<Widget> _tripOverviewSection() {
    final s = S.of(context);
    final trip = widget.trip;
    final pts = trip.points;
    final durMs = trip.endMs - trip.startMs;
    final avgKmh = durMs > 0
        ? (trip.distanceM / 1000) / (durMs / 3600000.0)
        : 0.0;
    final maxLong = pts.isEmpty
        ? 0.0
        : pts.map((p) => p.longG).reduce(math.max);
    final maxBrake = pts.isEmpty
        ? 0.0
        : -pts.map((p) => p.longG).reduce(math.min);
    final maxLat = pts.isEmpty
        ? 0.0
        : pts.map((p) => p.latG.abs()).reduce(math.max);
    final validAlts = pts.where((p) => p.altValid).map((p) => p.alt).toList();
    final altRange = validAlts.isEmpty
        ? s.t('暂无海拔数据', 'No altitude data')
        : s.t(
            '${validAlts.reduce(math.min).toStringAsFixed(0)}–${validAlts.reduce(math.max).toStringAsFixed(0)} m · 累计爬升 ${trip.climbM.toStringAsFixed(0)} m',
            '${validAlts.reduce(math.min).toStringAsFixed(0)}–${validAlts.reduce(math.max).toStringAsFixed(0)} m · climb ${trip.climbM.toStringAsFixed(0)} m',
          );
    // 全程走线切片（复用本页 _TrackLineDiagram，按速度着色）。
    _LapSlice? wholeSlice;
    if (pts.length >= 2) {
      final dists = <double>[0];
      for (var i = 1; i < pts.length; i++) {
        dists.add(
          dists.last +
              haversineM(
                pts[i - 1].lat,
                pts[i - 1].lon,
                pts[i].lat,
                pts[i].lon,
              ),
        );
      }
      wholeSlice = _LapSlice(
        pts,
        dists,
        pts.map((p) => p.timeMs - pts.first.timeMs).toList(),
      );
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
    final splits = trip.mode == TripMode.bike
        ? paceSplitsKm(pts)
        : const <double>[];
    final leanOver30 = trip.mode == TripMode.moto
        ? pts.where((p) => p.roll.abs() > 30).length
        : 0;
    // 赛道库轮廓：与赛道库/赛道详情页同一 TrackInfo.outline 数据源。
    final catalog = _catalogTrack;
    final catalogOutline = (catalog != null && catalog.outline.length >= 3)
        ? catalog.outline
        : null;
    return [
      Text(
        s.t('本节行程总览 · 传感器实测', 'Session overview · measured'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      _sectionHeader(
        s.t('总览', 'Overview'),
        'hide-overview',
        _hideOverview,
        (v) => setState(() => _hideOverview = v),
      ),
      if (!_hideOverview) ...[
        TripOverviewCard(trip: trip),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('关键极值', 'Key extremes'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _stat(
                    s.t('总里程', 'Total distance'),
                    '${(trip.distanceM / 1000).toStringAsFixed(2)} km',
                  ),
                  _stat(s.t('总时长', 'Duration'), _fmtDur(durMs)),
                  _stat(
                    s.t('平均时速', 'Avg speed'),
                    '${avgKmh.toStringAsFixed(0)} km/h',
                  ),
                  _stat(
                    s.t('极速', 'Top speed'),
                    '${(trip.maxSpeed * 3.6).toStringAsFixed(0)} km/h',
                  ),
                  _stat(
                    s.t('纵向 G 极值', 'Long. G extremes'),
                    s.t(
                      '加速 ${maxLong.toStringAsFixed(2)}g / 刹车 ${maxBrake.toStringAsFixed(2)}g',
                      'Accel ${maxLong.toStringAsFixed(2)}g / brake ${maxBrake.toStringAsFixed(2)}g',
                    ),
                  ),
                  _stat(
                    s.t('横向 G 极值', 'Lat. G extremes'),
                    '${maxLat.toStringAsFixed(2)}g',
                  ),
                  _stat(
                    s.t('最大合成 G', 'Max combined G'),
                    pts.isEmpty ? s.t('暂无', 'None') : '${trip.maxG.toStringAsFixed(2)}g',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.t('海拔变化：$altRange', 'Altitude: $altRange'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      _sectionHeader(
        s.t('速度曲线', 'Speed chart'),
        'hide-speed',
        _hideSpeed,
        (v) => setState(() => _hideSpeed = v),
      ),
      // 结算页只画速度曲线，不再叠加事件标记（事件功能页已下线）。
      if (!_hideSpeed) TripSpeedChartCard(points: pts),
      const SizedBox(height: 12),
      // G 值不再单开一页复盘：极值在“关键极值”里、纵向/横向 G 曲线
      // 已在下方“曲线（距离轴）”中，重复的大卡去掉。
      _sectionHeader(
        s.t('海拔', 'Altitude'),
        'hide-altitude',
        _hideAltitude,
        (v) => setState(() => _hideAltitude = v),
      ),
      if (!_hideAltitude) TripAltitudeCard(points: pts),
      const SizedBox(height: 12),
      _sectionHeader(
        s.t('轨迹走线图', 'Track line'),
        'hide-track-line',
        _hideTrackLine,
        (v) => setState(() => _hideTrackLine = v),
      ),
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
                    label: Text(s.t('卫星地图', 'Satellite')),
                    selected: _satelliteMap && !_replay3d && !_catalogView,
                    onSelected: (_) => setState(() {
                      _satelliteMap = true;
                      _replay3d = false;
                      _catalogView = false;
                    }),
                  ),
                  ChoiceChip(
                    key: const ValueKey('analysis-map-schematic'),
                    label: Text(s.t('示意地图', 'Schematic')),
                    selected: !_satelliteMap && !_replay3d && !_catalogView,
                    onSelected: (_) => setState(() {
                      _satelliteMap = false;
                      _replay3d = false;
                      _catalogView = false;
                    }),
                  ),
                  // 结算页与赛道库对齐：直接复用赛道库同一个 TrackInfo.outline
                  // 轮廓组件，保证两处看到的是同一形状。
                  if (catalogOutline != null)
                    ChoiceChip(
                      key: const ValueKey('analysis-map-catalog'),
                      label: Text(s.t('赛道库轮廓', 'Track outline')),
                      selected: _catalogView && !_replay3d,
                      onSelected: (_) => setState(() {
                        _catalogView = true;
                        _replay3d = false;
                      }),
                    ),
                  // v1.3.7：3D 回放模式（与卫星/示意并列的切换，
                  // 不取代原有内容；默认仍是现有视图）。
                  ChoiceChip(
                    key: const ValueKey('analysis-map-3d-replay'),
                    label: Text(s.t('3D 回放', '3D replay')),
                    selected: _replay3d,
                    onSelected: (_) => setState(() {
                      _replay3d = true;
                      _catalogView = false;
                    }),
                  ),
                  // v1.3.4：参考圈叠加开关（默认开，只影响本页会话；
                  // 无参照圈时不出现，参照圈切片点数 < 2 时不画线；
                  // 3D 回放 / 赛道库轮廓模式下不出现）。
                  if (_reference != null && !_replay3d && !_catalogView)
                    ChoiceChip(
                      key: const ValueKey('reference-overlay-toggle'),
                      label: Text(s.t('参考圈叠加', 'Reference lap')),
                      selected: _showReferenceOverlay,
                      onSelected: (_) => setState(
                        () => _showReferenceOverlay = !_showReferenceOverlay,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_replay3d)
                Replay3dView(points: pts)
              else if (_catalogView && catalog != null)
                TrackSchematicDiagram(
                  track: catalog,
                  height: 220,
                  showCorners: true,
                  showSectors: true,
                )
              else if (wholeSlice == null)
                Text(
                  s.t('暂无轨迹点，走线为空', 'No track points; line is empty'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                )
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
                  catalogOutline: catalogOutline,
                ),
              const SizedBox(height: 6),
              Text(
                _replay3d
                    ? s.t('3D 透视回放：仅作复盘示意，不用于计时判定',
                        '3D replay: review only, not for timing')
                    : _catalogView
                    ? s.t('与赛道库同一轮廓数据源（按公开布局重绘的示意图，非官网原图）',
                        'Same outline source as the track library (redrawn schematic, not the official map)')
                    : s.t('走线按速度着色，仅作复盘示意，不用于计时判定',
                        'Line colored by speed; review only, not for timing'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              // 示意地图叠加赛道库轮廓时说明灰线来源。
              if (!_replay3d && !_catalogView && catalogOutline != null && !_satelliteMap)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('灰色细线 = 赛道库轮廓（与赛道库同一数据源）',
                        'Thin gray line = track library outline (same source)'),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              // v1.3.4：参考圈叠加图例（开关关 / 无参照圈 / 点数 < 2
              // 时不出现；圈号取自 _reference，不冒充最佳圈；
              // 3D 回放模式下不出现）。
              if (showRefOverlay && !_replay3d)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('青色 = 参照圈（第 $refLapNumber 圈）',
                        'Cyan = reference lap (lap $refLapNumber)'),
                    style: const TextStyle(color: _kGhostCyan, fontSize: 11),
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
              Text(
                s.t('压弯数据', 'Lean data'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.t(
                  '最大压弯角 ${trip.maxLean.toStringAsFixed(0)}° · 超 30° 约 $leanOver30 秒（1Hz 采样点数）',
                  'Max lean ${trip.maxLean.toStringAsFixed(0)}° · over 30° for about $leanOver30 s (1 Hz samples)',
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              Text(
                s.t('仅手机固定在车上且标定后可信；未确认固定时仅作参考。',
                    'Reliable only with the phone mounted and calibrated; otherwise a guide.'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
      // 压弯只属于摩托；汽车 / 卡丁车换成弯道与横向 G 数据。
      if (trip.mode == TripMode.car || trip.mode == TripMode.kart) ...[
        const SizedBox(height: 12),
        _carCornerCard(),
      ],
      if (trip.mode == TripMode.bike) ...[
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('配速分段', 'Pace splits'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              if (splits.isEmpty)
                Text(
                  s.t('不足 1 公里，暂无整公里配速分段',
                      'Under 1 km; no whole-kilometer splits'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                )
              else
                for (var i = 0; i < splits.length; i++)
                  Text(
                    s.t(
                      '第 ${i + 1} 公里：${splits[i].toStringAsFixed(2)} min/km',
                      'Km ${i + 1}: ${splits[i].toStringAsFixed(2)} min/km',
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
            ],
          ),
        ),
      ],
    ];
  }

  /// 汽车 / 卡丁车的替代数据卡：压弯只对摩托有意义，这里用同一批
  /// 实测点做弯道与横向 G 汇总，不补造摩托压弯数据。
  Widget _carCornerCard() {
    final s = S.of(context);
    final pts = widget.trip.points;
    final corners = analyzeCorners(pts);
    final left = corners
        .where((c) => c.direction == CornerDirection.left)
        .length;
    final right = corners.length - left;
    final calibrated = pts.any((p) => p.calibrated);
    final maxLat = !calibrated || pts.isEmpty
        ? null
        : pts.map((p) => p.latG.abs()).reduce(math.max);
    final avgApex = corners.isEmpty
        ? null
        : corners.map((c) => c.apexKmh).reduce((a, b) => a + b) /
              corners.length;
    final slowest = [...corners]
      ..sort((a, b) => a.apexKmh.compareTo(b.apexKmh));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.t('弯道与横向 G', 'Corners and lateral G'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (corners.isEmpty)
            Text(
              s.t('本趟未识别到弯道：轨迹点不足，或全程为直道。',
                  'No corners detected: too few points or a straight route.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          else ...[
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _stat(s.t('弯道数', 'Corners'), '${corners.length}'),
                _stat(s.t('左弯 / 右弯', 'Left / right'), '$left / $right'),
                _stat(
                  s.t('最大横向 G', 'Max lateral G'),
                  maxLat == null ? '—' : '${maxLat.toStringAsFixed(2)}g',
                ),
                if (avgApex != null)
                  _stat(
                    s.t('平均弯心速度', 'Avg apex speed'),
                    '${avgApex.toStringAsFixed(0)} km/h',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.t('最慢弯心（入弯 → 弯心 → 出弯）',
                  'Slowest apex (entry → apex → exit)'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 2),
            for (final c in slowest.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  s.t(
                    '第 ${c.index} 弯 ${c.direction == CornerDirection.right ? '右' : '左'}：'
                    '${c.entryKmh.toStringAsFixed(0)} → '
                    '${c.apexKmh.toStringAsFixed(0)} → '
                    '${c.exitKmh.toStringAsFixed(0)} km/h · '
                    '弯长 ${c.lengthM.toStringAsFixed(0)} m',
                    'Corner ${c.index} ${c.direction == CornerDirection.right ? 'right' : 'left'}: '
                    '${c.entryKmh.toStringAsFixed(0)} → '
                    '${c.apexKmh.toStringAsFixed(0)} → '
                    '${c.exitKmh.toStringAsFixed(0)} km/h · '
                    'length ${c.lengthM.toStringAsFixed(0)} m',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 4),
          Text(
            s.t('弯道由轨迹曲率与航向变化识别；横向 G 仅在传感器标定后显示。',
                'Corners are detected from track curvature and heading change; lateral G shows only after calibration.'),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// OBD 通道：只读本趟 [Trip.obdSamples]（每秒一条实测采样）。
  /// 有采样：画真实 OBD 车速曲线 + 极值（最高车速 / 转速 / 油门 /
  /// 水温，缺值那项不写数、不编数）；无采样：保留占位文案。
  Widget _obdSection() {
    final tr = S.of(context);
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
      final times = samples.map((s) => (s['t'] as num?)?.toInt() ?? 0).toList();
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
          Text(
            tr.t('OBD 通道', 'OBD channels'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr.t('通道：车速 / 转速 / 油门 / 水温（ELM327 实测采样）',
                'Channels: speed / RPM / throttle / coolant (ELM327 samples)'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (!hasSamples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                widget.obdConnected
                    ? tr.t('OBD 已连接，暂无数据', 'OBD connected, no data yet')
                    : tr.t('未连接 OBD，暂无此通道',
                        'OBD not connected; channel unavailable'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _stat(tr.t('实测采样', 'Samples'), '${samples.length}'),
                _stat(
                  tr.t('最高车速', 'Top speed'),
                  '${maxSpeed.toStringAsFixed(0)} km/h',
                ),
                _stat(
                  tr.t('最高转速', 'Max RPM'),
                  maxRpm == null ? '—' : '${maxRpm.toStringAsFixed(0)} rpm',
                ),
                _stat(
                  tr.t('最大油门', 'Max throttle'),
                  maxThr == null ? '—' : '${maxThr.toStringAsFixed(0)} %',
                ),
                _stat(
                  tr.t('最高水温', 'Max coolant'),
                  maxCool == null ? '—' : '${maxCool.toStringAsFixed(0)} ℃',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _chartTitle(
                tr.t('OBD 车速（实测采样，未连接时段无曲线）',
                    'OBD speed (measured samples; no curve when disconnected)')),
            _SeriesChart(
              xs: xs,
              series: [_Series(values: speeds, color: const Color(0xFF38BDF8))],
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
    final tr = S.of(context);
    final sec = ms ~/ 1000;
    if (sec < 60) return tr.t('$sec 秒', '${sec}s');
    final m = sec ~/ 60;
    if (m < 60) {
      return tr.t('$m 分 ${sec % 60} 秒', '${m}m ${sec % 60}s');
    }
    return tr.t('${m ~/ 60} 时 ${m % 60} 分', '${m ~/ 60}h ${m % 60}m');
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
  void dispose() {
    _aiService.close();
    super.dispose();
  }

  Future<void> _openAiSettings() async {
    await Navigator.of(context)
        .push(DtPageRoute(builder: (_) => const AiSettingsPage()));
    final settings = await AiSettingsStore.load();
    if (!mounted) return;
    setState(() => _aiSettings = settings);
  }

  Future<void> _runAiAnalysis() async {
    if (_aiBusy) return;
    final s = S.of(context);
    final zh = LocaleScope.of(context).lang == AppLang.zh;
    final facts = _aiFactsJson();
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiResult = null;
    });
    try {
      final text = await _aiService.analyze(
        settings: _aiSettings,
        factsJson: facts,
        zh: zh,
      );
      if (!mounted) return;
      setState(() {
        _aiBusy = false;
        _aiResult = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiBusy = false;
        _aiError = e is AiAnalysisException
            ? e.message
            : s.t('AI 请求失败：$e', 'AI request failed: $e');
      });
    }
  }

  /// 组装发给 AI 的事实 JSON：只放本页实测值，缺失通道单独列出，
  /// 明确告诉模型哪些不可用——避免它自行补数。
  String _aiFactsJson() {
    final trip = widget.trip;
    final selected = _selected;
    final reference = _reference;
    final selSlice = selected == null ? null : _sliceLap(trip, selected);
    final refSlice = reference == null ? null : _sliceLap(trip, reference);
    final corners = selSlice == null
        ? const <CornerAnalysis>[]
        : analyzeCorners(selSlice.points);
    final speedDelta =
        (selSlice != null &&
            refSlice != null &&
            selected != null &&
            reference != null &&
            selected.number != reference.number)
        ? compareLapSpeeds(
            selDistances: selSlice.distances,
            selSpeedsKmh: selSlice.points.map((p) => p.speed * 3.6).toList(),
            refDistances: refSlice.distances,
            refSpeedsKmh: refSlice.points.map((p) => p.speed * 3.6).toList(),
          )
        : null;

    double? maxSpeedKmh;
    double? avgSpeedKmh;
    double? maxLateralG;
    double? maxAccelG;
    double? maxBrakeG;
    if (selSlice != null && selSlice.points.isNotEmpty) {
      var sum = 0.0;
      var calibrated = false;
      var accel = 0.0;
      var brake = 0.0;
      var lat = 0.0;
      for (final p in selSlice.points) {
        final kmh = p.speed * 3.6;
        sum += kmh;
        if (maxSpeedKmh == null || kmh > maxSpeedKmh) maxSpeedKmh = kmh;
        if (!p.calibrated) continue;
        calibrated = true;
        if (p.longG > accel) accel = p.longG;
        if (-p.longG > brake) brake = -p.longG;
        if (p.latG.abs() > lat) lat = p.latG.abs();
      }
      avgSpeedKmh = sum / selSlice.points.length;
      if (calibrated) {
        maxLateralG = lat;
        maxAccelG = accel;
        maxBrakeG = brake;
      }
    }

    final counted = widget.laps.where((l) => l.counted).toList();
    final best = sessionBestLap(widget.laps);
    final facts = <String, dynamic>{
      'app': 'DriveTrack',
      'mode': trip.mode.name,
      'track': trip.trackName.isEmpty ? null : trip.trackName,
      'session': {
        'lapCount': counted.length,
        'allLapCount': widget.laps.length,
        'bestLapMs': best?.durationMs,
        'laps': [
          for (final l in counted)
            {
              'number': l.number,
              'durationMs': l.durationMs,
              'sectorsMs': l.sectorsMs,
              'kind': l.kind.name,
            },
        ],
      },
      'analyzedLap': selected == null
          ? null
          : {
              'number': selected.number,
              'durationMs': selected.durationMs,
              'sectorsMs': selected.sectorsMs,
              'distanceM': selSlice?.totalDistance.round(),
              'maxSpeedKmh': maxSpeedKmh == null ? null : maxSpeedKmh.round(),
              'avgSpeedKmh': avgSpeedKmh == null ? null : avgSpeedKmh.round(),
              'maxLateralG': maxLateralG == null
                  ? null
                  : double.parse(maxLateralG.toStringAsFixed(2)),
              'maxAccelG': maxAccelG == null
                  ? null
                  : double.parse(maxAccelG.toStringAsFixed(2)),
              'maxBrakeG': maxBrakeG == null
                  ? null
                  : double.parse(maxBrakeG.toStringAsFixed(2)),
            },
      'referenceLap': reference == null
          ? null
          : {'number': reference.number, 'durationMs': reference.durationMs},
      'corners': [
        for (final c in corners.take(20))
          {
            'index': c.index,
            'direction': c.direction.name,
            'entryKmh': double.parse(c.entryKmh.toStringAsFixed(0)),
            'apexKmh': double.parse(c.apexKmh.toStringAsFixed(0)),
            'exitKmh': double.parse(c.exitKmh.toStringAsFixed(0)),
            'minKmh': double.parse(c.minKmh.toStringAsFixed(0)),
            'lengthM': double.parse(c.lengthM.toStringAsFixed(0)),
            'lineSpanM': double.parse(c.lineSpanM.toStringAsFixed(1)),
            'maxLateralG': c.maxLateralG == null
                ? null
                : double.parse(c.maxLateralG!.toStringAsFixed(2)),
          },
      ],
      'cornerCount': corners.length,
      'speedDelta': speedDelta == null
          ? null
          : {
              'avgDeltaKmh': double.parse(
                speedDelta.avgDeltaKmh.toStringAsFixed(1),
              ),
              'medianDeltaKmh': double.parse(
                speedDelta.medianDeltaKmh.toStringAsFixed(1),
              ),
              'maxGainKmh': double.parse(
                speedDelta.maxGainKmh.toStringAsFixed(0),
              ),
              'maxGainAtPercent': (speedDelta.maxGainFraction * 100).round(),
              'maxLossKmh': double.parse(
                speedDelta.maxLossKmh.toStringAsFixed(0),
              ),
              'maxLossAtPercent': (speedDelta.maxLossFraction * 100).round(),
            },
      'unavailableChannels': const [
        'steeringAngle',
        'throttle',
        'brakePedal',
        'rpm',
        'coolantTemp',
        'tyreTemp',
        'trackLimits',
        'otherDrivers',
      ],
      'dataNote':
          'Only fields present above are measured. Missing channels are unavailable '
          'and must be reported as such, never estimated.',
    };
    return jsonEncode(facts);
  }

  Widget _aiAnalysisCard() {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final configured = _aiSettings.usable;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.t('AI 分析', 'AI analysis'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!configured)
                Text(
                  s.t('未配置', 'Not set up'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.t('只把本页的实测摘要发给 AI（圈速、分段、速度/G 极值、弯角、速度差），不含账号与轨迹原始点。',
                'Only the measured summary on this page is sent (laps, sectors, speed/G extremes, corners, speed delta); no account or raw track points.'),
            style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (!configured) ...[
            Text(
              s.t('尚未配置 AI 服务。配置 Base URL、API Key 与模型后即可在这里生成分析。',
                  'AI is not configured. Set the base URL, API key, and model to generate an analysis here.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openAiSettings,
              icon: const Icon(Icons.settings, size: 18),
              label: Text(s.t('打开 AI 设置', 'Open AI settings')),
            ),
          ] else if (_aiBusy) ...[
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  s.t('正在请求 AI…', 'Requesting AI…'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ] else if (_aiResult != null) ...[
            SelectableText(
              _aiResult!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => VoiceService.instance.speakText(_aiResult!),
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: Text(s.t('朗读', 'Read aloud')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _runAiAnalysis,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(s.t('重新生成', 'Regenerate')),
                ),
              ],
            ),
          ] else
            FilledButton.icon(
              onPressed: _runAiAnalysis,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(s.t('生成 AI 分析', 'Generate AI analysis')),
            ),
          if (_aiError != null) ...[
            const SizedBox(height: 10),
            Text(
              _aiError!,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _openAiSettings,
              child: Text(s.t('检查 AI 设置', 'Check AI settings')),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            s.t('AI 只依据上面这些实测值回答；未接入的通道会标注“无数据”，不会编造。结果仅供参考。',
                'AI answers only from the measured values above. Missing channels are marked "no data"; nothing is invented. Results are for reference only.'),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final laps = widget.laps;
    final best = sessionBestLap(laps);
    // v1.2.15：理论最佳圈与直播页同口径（见
    // analysisTheoreticalBestLapMs）：先按最佳圈段数过滤，再加
    // 真实分段门控（最佳圈须 3 段）；无真实分段点时为 null，显示
    // 占位，不拿前后半圈拼一个假理论圈。
    final theoretical = analysisTheoreticalBestLapMs(laps);
    final counted = laps.where((l) => lapInvalidReason(l) == null).length;
    final sectorData = _sectorData;
    final catalog = _catalogTrack;
    final catalogOutline = (catalog != null && catalog.outline.length >= 3)
        ? catalog.outline
        : null;
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
        deltaCurve = List<double>.filled(selSlice.points.length, 0);
      }
    }
    final fractions = selSlice == null || selSlice.totalDistance <= 0
        ? <double>[]
        : selSlice.distances.map((d) => d / selSlice!.totalDistance).toList();
    // v1.3.4：速度曲线参照圈第二条线——参照圈存在且不是当前分析圈
    // 且切片点数 >= 2 时才画；参照圈 = 分析圈时只画一条，不画假线。
    final showRefSpeedLine =
        selected != null &&
        reference != null &&
        reference.number != selected.number &&
        refSlice != null &&
        refSlice.points.length >= 2 &&
        selSlice != null;
    final refSpeedValues = showRefSpeedLine
        ? [for (final d in selSlice.distances) _refSpeedAt(refSlice, d)]
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
    // 弯角与速度差（v1.7.0）：只用分析圈的实测点，不补点、不猜值。
    final corners = selSlice == null
        ? const <CornerAnalysis>[]
        : analyzeCorners(selSlice.points);
    final speedDelta =
        (selSlice != null &&
            refSlice != null &&
            selected != null &&
            reference != null &&
            selected.number != reference.number)
        ? compareLapSpeeds(
            selDistances: selSlice.distances,
            selSpeedsKmh: selSlice.points.map((p) => p.speed * 3.6).toList(),
            refDistances: refSlice.distances,
            refSpeedsKmh: refSlice.points.map((p) => p.speed * 3.6).toList(),
          )
        : null;

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: Text(
          widget.trip.trackName.isEmpty
              ? s.t('赛道分析', 'Track analysis')
              : s.t('${widget.trip.trackName} · 赛道分析',
                  '${widget.trip.trackName} · Track analysis'),
        ),
      ),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 12, 16, 24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.t('赛道模式不评分', 'Track mode is not scored'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
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
              Text(
                s.t('暂无圈速数据：本节无计入圈。',
                    'No lap times: this session has no counted laps.'),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ] else ...[
              // 圈速总览。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('圈速总览', 'Lap summary'),
                      style: const TextStyle(
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
                            s.t('最佳圈', 'Best lap'),
                            best == null
                                ? '--:--.---'
                                : LapTimer.formatLapTime(best.durationMs),
                          ),
                        ),
                        Expanded(
                          child: _stat(
                            s.t('理论最佳圈', 'Theoretical best'),
                            theoretical == null
                                ? '--:--.---'
                                : LapTimer.formatLapTime(theoretical),
                          ),
                        ),
                        Expanded(
                          child: _stat(
                            s.t('计入圈 / 全部', 'Counted / all'),
                            '$counted / ${laps.length}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t('理论最佳圈 = 各分段最佳相加；无效圈不进统计',
                          'Theoretical best = sum of best sectors; invalid laps are excluded'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // v1.5.7 完赛汇总：每圈条形（越高越快）+ 圈速标准差。
              _sessionSummaryCard(laps),
              const SizedBox(height: 12),
              // 圈次与参照圈选择器。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('分析圈', 'Analyzed lap'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final l in laps)
                          ChoiceChip(
                            label: Text(
                              '${s.t('第 ${l.number} 圈', 'Lap ${l.number}')}'
                              '${lapInvalidReason(l) == null ? '' : s.t(' · 无效', ' · invalid')}',
                            ),
                            selected: selected.number == l.number,
                            onSelected: (_) => setState(() {
                              _selected = l;
                              _scrub = 0;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.t('参照圈（默认本节最佳圈）',
                          'Reference lap (defaults to session best)'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final l in laps.where(
                          (x) => lapInvalidReason(x) == null,
                        ))
                          ChoiceChip(
                            label: Text(s.t('第 ${l.number} 圈', 'Lap ${l.number}')),
                            selected: reference?.number == l.number,
                            onSelected: (_) => setState(() => _reference = l),
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
                    Text(
                      s.t('分段对比', 'Sector comparison'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sectorData == null
                          ? s.t('扇区待核：未查到该赛道扇区数据，分段按计时分段显示',
                              'Sector data pending: none found for this track; timing sectors are shown')
                          : sectorData.sourceLabel == '扇区待核'
                          ? s.t('${sectorData.note}分段按计时分段显示，不标官方 S1/S2/S3',
                              '${sectorData.note}Timing sectors are shown; official S1/S2/S3 are not labeled.')
                          : '${_sectorSourceLabel(s, sectorData.sourceLabel)}：${sectorData.note}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._sectorRows(selected, reference, sectorData),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _cornerAnalysisCard(corners),
              const SizedBox(height: 12),
              _speedDeltaCard(speedDelta, deltaCurve, selected, reference),
              const SizedBox(height: 12),
              _aiAnalysisCard(),
              const SizedBox(height: 12),
              // 图表区：捏合缩放 + 双击复位 + 单指 scrub 联动。
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.t('曲线（距离轴）', 'Curves (distance)'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _resetView,
                          child: Text(s.t('整圈', 'Whole lap')),
                        ),
                      ],
                    ),
                    Text(
                      s.t('捏合缩放 · 双击复位整圈 · 横向拖动联动图表与走线 · 点分段缩放到该分段',
                          'Pinch to zoom · double-tap to reset · drag to scrub · tap a sector to zoom'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    if (sectorData != null && sectorData.hasBoundaries) ...[
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
                            final newWidth = (width / d.scale).clamp(0.05, 1.0);
                            final center = (_viewStart + _viewEnd) / 2;
                            _viewStart = (center - newWidth / 2).clamp(
                              0.0,
                              1.0,
                            );
                            _viewEnd = (_viewStart + newWidth).clamp(0.0, 1.0);
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
                          _scrub =
                              (_scrub +
                                      d.delta.dx /
                                          300 *
                                          (_viewEnd - _viewStart))
                                  .clamp(0.0, 1.0);
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _chartTitle(s.t('速度', 'Speed')),
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
                                s.t(
                                  '红色 = 第 ${selected.number} 圈 · 青色 = 参照圈（第 ${reference.number} 圈）',
                                  'Red = lap ${selected.number} · cyan = reference lap (${reference.number})',
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _chartTitle(s.t('累计得失（相对参照圈，负 = 更快）',
                              'Cumulative delta (vs reference; negative = faster)')),
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
                          _chartTitle(s.t('横向 / 纵向 G', 'Lateral / longitudinal G')),
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
                        s.t(
                          '进度：${(_scrub * 100).toStringAsFixed(0)}% · '
                          '速度 ${(selSlice.points[scrubIndex].speed * 3.6).toStringAsFixed(0)} km/h · '
                          '得失 ${deltaCurve.isEmpty ? '--' : '${deltaCurve[scrubIndex] >= 0 ? '+' : ''}${(deltaCurve[scrubIndex] / 1000).toStringAsFixed(3)}s'} · '
                          '横向 G ${selSlice.points[scrubIndex].latG.toStringAsFixed(2)} · '
                          '纵向 G ${selSlice.points[scrubIndex].longG.toStringAsFixed(2)}',
                          'Progress: ${(_scrub * 100).toStringAsFixed(0)}% · '
                          'speed ${(selSlice.points[scrubIndex].speed * 3.6).toStringAsFixed(0)} km/h · '
                          'delta ${deltaCurve.isEmpty ? '--' : '${deltaCurve[scrubIndex] >= 0 ? '+' : ''}${(deltaCurve[scrubIndex] / 1000).toStringAsFixed(3)}s'} · '
                          'lat G ${selSlice.points[scrubIndex].latG.toStringAsFixed(2)} · '
                          'long G ${selSlice.points[scrubIndex].longG.toStringAsFixed(2)}',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      )
                    else
                      Text(
                        s.t('该圈暂无轨迹点，曲线为空',
                            'No track points for this lap; curves are empty'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    Text(
                      s.t('走线', 'Track line'),
                      style: const TextStyle(
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
                          label: Text(s.t('按速度着色', 'Color by speed')),
                          selected: _colorMode == TrackLineColorMode.speed,
                          onSelected: (_) => setState(
                            () => _colorMode = TrackLineColorMode.speed,
                          ),
                        ),
                        ChoiceChip(
                          label: Text(s.t('按 delta 着色', 'Color by delta')),
                          selected: _colorMode == TrackLineColorMode.delta,
                          onSelected: (_) => setState(
                            () => _colorMode = TrackLineColorMode.delta,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (selSlice == null || selSlice.points.length < 2)
                      Text(
                        s.t('该圈暂无轨迹点，走线为空',
                            'No track points for this lap; line is empty'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      )
                    else
                      _TrackLineDiagram(
                        slice: selSlice,
                        deltaCurve: deltaCurve,
                        mode: _colorMode,
                        scrubIndex: scrubIndex,
                        catalogOutline: catalogOutline,
                      ),
                    if (catalogOutline != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          s.t('灰色细线 = 赛道库轮廓（同一 TrackInfo 数据源）',
                              'Thin gray line = track library outline (same TrackInfo source)'),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    Text(
                      s.t('仅作复盘示意，不用于计时判定',
                          'Review only, not for timing'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                    Text(
                      s.t('圈速列表', 'Lap list'),
                      style: const TextStyle(
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
                                s.t('第 ${l.number} 圈', 'Lap ${l.number}'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
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
                                _invalidReasonText(s, l),
                                style: const TextStyle(
                                  color: _kRed,
                                  fontSize: 12,
                                ),
                              )
                            else if (best?.number == l.number)
                              Text(
                                s.t('最佳圈', 'Best'),
                                style: const TextStyle(color: _kGreen, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.t('第一版不做视频联动', 'No video sync in this version'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// v1.7.0 弯角分析卡：只用分析圈实测点；无弯或点数不足时明说，
  /// 不补造弯角。OBD 转向角 / 油门 / 刹车尚未接入，卡内如实标注。
  Widget _cornerAnalysisCard(List<CornerAnalysis> corners) {
    final s = S.of(context);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.t('弯角分析', 'Corner analysis'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                corners.isEmpty
                    ? '—'
                    : s.t('${corners.length} 个弯', '${corners.length} corners'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.t('按轨迹曲率与航向变化识别；速度为 GPS 实测，横向 G 仅在传感器标定后显示。',
                'Detected from track curvature and heading change; speed is GPS-measured, lateral G shows only after calibration.'),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (corners.isEmpty)
            Text(
              s.t('本圈未识别到弯角：轨迹点不足，或全程为直道。',
                  'No corners on this lap: too few points or a straight route.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          else ...[
            for (final c in corners.take(12)) _cornerRow(c),
            if (corners.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  s.t('仅显示前 12 个弯，共 ${corners.length} 个。',
                      'Showing the first 12 of ${corners.length} corners.'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            s.t('弯中转向角 / 油门 / 刹车 / 转速 / 水温：当前数据源未提供，OBD 接入后在此显示，本卡不做推算。',
                'Steering / throttle / brake / RPM / coolant in corners are not provided by the current data source; they will appear after OBD integration. No estimates here.'),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerRow(CornerAnalysis c) {
    final s = S.of(context);
    final dir = c.direction == CornerDirection.right
        ? s.t('右弯', 'Right')
        : s.t('左弯', 'Left');
    final lat = c.maxLateralG == null
        ? s.t('横向 G —', 'Lat G —')
        : s.t('横向 G ${c.maxLateralG!.toStringAsFixed(2)}',
            'Lat G ${c.maxLateralG!.toStringAsFixed(2)}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${c.index}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                dir,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${c.entryKmh.toStringAsFixed(0)} → '
                '${c.apexKmh.toStringAsFixed(0)} → '
                '${c.exitKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            s.t(
              '最短 ${c.minKmh.toStringAsFixed(0)} km/h · '
              '弯长 ${c.lengthM.toStringAsFixed(0)} m · '
              '走线跨度 ${c.lineSpanM.toStringAsFixed(1)} m · '
              '$lat · ${(c.durationMs / 1000).toStringAsFixed(1)} s',
              'Min ${c.minKmh.toStringAsFixed(0)} km/h · '
              'length ${c.lengthM.toStringAsFixed(0)} m · '
              'line span ${c.lineSpanM.toStringAsFixed(1)} m · '
              '$lat · ${(c.durationMs / 1000).toStringAsFixed(1)} s',
            ),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// v1.7.0 速度差分析卡：分析圈相对参照圈，按距离对齐后的速度差，
  /// 作为评估项展示。只统计两圈都有数据的区间。
  Widget _speedDeltaCard(
    LapSpeedDeltaSummary? summary,
    List<double> deltaCurve,
    Lap? selected,
    Lap? reference,
  ) {
    final timeDeltaMs = deltaCurve.isEmpty
        ? null
        : deltaCurve.last; // 分析圈 − 参照圈
    final s = S.of(context);
    final hasBoth = selected != null && reference != null;
    final sameLap = selected != null &&
        reference != null &&
        selected.number == reference.number;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.t('速度差分析', 'Speed delta'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (selected != null && reference != null)
                ? s.t(
                    '第 ${selected.number} 圈 − 第 ${reference.number} 圈（按距离对齐，正值 = 分析圈更快）',
                    'Lap ${selected.number} − lap ${reference.number} (distance-aligned; positive = analyzed lap faster)',
                  )
                : s.t('需要同时选中分析圈与参照圈才能比较。',
                    'Select both an analyzed and a reference lap to compare.'),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (!hasBoth)
            Text(
              s.t('数据不足：没有可用的分析圈或参照圈。',
                  'Not enough data: no analyzed or reference lap.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          else if (sameLap)
            Text(
              s.t('分析圈与参照圈相同：在上方选择另一圈作为参照后显示速度差。',
                  'Analyzed and reference laps are the same. Pick another reference lap above.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          else if (summary == null)
            Text(
              s.t('数据不足：两圈可对齐的距离区间太短，无法比较。',
                  'Not enough data: the laps overlap over too short a distance.'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          else ...[
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _stat(
                  s.t('平均速度差', 'Avg delta'),
                  '${summary.avgDeltaKmh >= 0 ? '+' : ''}'
                      '${summary.avgDeltaKmh.toStringAsFixed(1)} km/h',
                ),
                _stat(
                  s.t('中位速度差', 'Median delta'),
                  '${summary.medianDeltaKmh >= 0 ? '+' : ''}'
                      '${summary.medianDeltaKmh.toStringAsFixed(1)} km/h',
                ),
                _stat(
                  s.t('最大领先', 'Max gain'),
                  '+${summary.maxGainKmh.toStringAsFixed(0)} km/h'
                      ' @ ${formatPercent(summary.maxGainFraction)}',
                ),
                _stat(
                  s.t('最大落后', 'Max loss'),
                  '-${summary.maxLossKmh.toStringAsFixed(0)} km/h'
                      ' @ ${formatPercent(summary.maxLossFraction)}',
                ),
                if (timeDeltaMs != null)
                  _stat(s.t('时间差', 'Time delta'),
                      formatDeltaSeconds(timeDeltaMs / 1000)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.t(
                '评估：${_verdictText(s, summary.avgDeltaKmh)}'
                '${timeDeltaMs == null
                    ? ''
                    : timeDeltaMs <= 0
                    ? '，本圈用时更短'
                    : '，本圈用时更长'}。',
                'Assessment: ${_verdictText(s, summary.avgDeltaKmh)}'
                '${timeDeltaMs == null
                    ? ''
                    : timeDeltaMs <= 0
                    ? ', this lap is faster'
                    : ', this lap is slower'}.',
              ),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.t('有效对比点 ${summary.pointCount} 个；超出参照圈距离范围的点不参与比较。',
                  '${summary.pointCount} comparison points; points outside the reference distance are ignored.'),
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
          ],
        ],
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
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
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

  /// 速度差结论来自数据层（中文），英文界面在此转写，不改数据源。
  String _verdictText(S s, double avgDeltaKmh) {
    final verdict = speedDeltaVerdict(avgDeltaKmh);
    if (s.zh) return verdict;
    return switch (verdict) {
      '整体明显更快' => 'Clearly faster overall',
      '整体略快' => 'Slightly faster overall',
      '整体明显更慢' => 'Clearly slower overall',
      '整体略慢' => 'Slightly slower overall',
      _ => 'About the same overall',
    };
  }

  /// 完赛汇总：圈速折线图（越高越慢，个人最佳红点）+ 逐圈时间数据 +
  /// 圈数 / 中位圈 / 平均圈 / 圈速标准差 σ。只用计入圈：无效圈不参与
  /// 一致性统计，避免维修区、出界把 σ 拉大。
  Widget _sessionSummaryCard(List<Lap> laps) {
    final s = S.of(context);
    final counted = laps.where((l) => lapInvalidReason(l) == null).toList();
    if (counted.isEmpty) return const SizedBox.shrink();
    final durations = counted.map((l) => l.durationMs).toList();
    final fastest = durations.reduce(math.min);
    final mean = durations.reduce((a, b) => a + b) / durations.length;
    final sigma = math.sqrt(
      durations.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) /
          durations.length,
    );
    final spreadPct = mean > 0 ? sigma / mean * 100 : 0.0;
    final sorted = [...durations]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.t('本会话', 'This session'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _LapTrendChart(laps: counted, fastestMs: fastest),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _stat(s.t('计入圈数', 'Counted laps'), '${counted.length}'),
              _stat(s.t('中位圈', 'Median lap'), LapTimer.formatLapTime(median.round())),
              _stat(s.t('平均圈', 'Mean lap'), LapTimer.formatLapTime(mean.round())),
              _stat(s.t('标准差 σ', 'Std dev σ'), LapTimer.formatLapTime(sigma.round())),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            spreadPct <= 1.0
                ? s.t('一致性 ${spreadPct.toStringAsFixed(1)}% · 圈速很稳',
                    'Consistency ${spreadPct.toStringAsFixed(1)}% · very steady')
                : s.t('一致性 ${spreadPct.toStringAsFixed(1)}%（σ 越小越稳）',
                    'Consistency ${spreadPct.toStringAsFixed(1)}% (lower σ is steadier)'),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          // 折线图下方给出逐圈数据，读数不用看图估。
          for (final l in counted.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.t('圈 ${l.number}', 'Lap ${l.number}'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    LapTimer.formatLapTime(l.durationMs),
                    style: TextStyle(
                      color: l.durationMs == fastest ? _kGreen : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: Text(
                      l.durationMs == fastest
                          ? s.t('最佳', 'Best')
                          : LapTimer.formatDelta(l.durationMs - fastest),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (counted.length > 20)
            Text(
              s.t('仅列前 20 圈，共 ${counted.length} 圈。',
                  'Showing the first 20 of ${counted.length} laps.'),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
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
    Lap selected,
    Lap? reference,
    TrackSectorData? sectorData,
  ) {
    final n = math.max(
      selected.sectorsMs.length,
      reference?.sectorsMs.length ?? 0,
    );
    final s = S.of(context);
    if (n == 0) {
      return [
        Text(
          s.t('暂无分段数据', 'No sector data'),
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ];
    }
    final rows = <Widget>[];
    for (var i = 0; i < n; i++) {
      final label = sectorData != null && sectorData.hasBoundaries && n == 3
          ? sectorData.sectorLabels[i]
          : s.t('第 ${i + 1} 段', 'Sector ${i + 1}');
      final sel = i < selected.sectorsMs.length ? selected.sectorsMs[i] : null;
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
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  sel == null ? '--' : LapTimer.formatLapTime(sel),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  ref == null
                      ? '--'
                      : s.t('参照 ${LapTimer.formatLapTime(ref)}',
                          'Ref ${LapTimer.formatLapTime(ref)}'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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

/// 圈速折线图：X 为圈序，Y 为圈速（越高越慢）；最佳圈红点 + 红色虚线，
/// 其余白点连线。下方逐圈数据由调用方列出，本图只负责趋势。
class _LapTrendChart extends StatelessWidget {
  final List<Lap> laps;
  final int fastestMs;

  const _LapTrendChart({required this.laps, required this.fastestMs});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final durations = laps.map((l) => l.durationMs).toList();
    var minMs = durations.reduce(math.min).toDouble();
    var maxMs = durations.reduce(math.max).toDouble();
    if (maxMs <= minMs) maxMs = minMs + 1000;
    final pad = (maxMs - minMs) * 0.15;
    final lo = minMs - pad;
    final hi = maxMs + pad;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.t('慢 ${LapTimer.formatLapTime(maxMs.round())}',
                  'Slow ${LapTimer.formatLapTime(maxMs.round())}'),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              s.t('快 ${LapTimer.formatLapTime(minMs.round())}',
                  'Fast ${LapTimer.formatLapTime(minMs.round())}'),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
        Container(
          height: 118,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: CustomPaint(
            painter: _LapTrendPainter(
              laps: laps,
              fastestMs: fastestMs,
              minMs: lo,
              maxMs: hi,
            ),
          ),
        ),
      ],
    );
  }
}

class _LapTrendPainter extends CustomPainter {
  final List<Lap> laps;
  final int fastestMs;
  final double minMs;
  final double maxMs;

  _LapTrendPainter({
    required this.laps,
    required this.fastestMs,
    required this.minMs,
    required this.maxMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (laps.isEmpty) return;
    const padL = 16.0;
    const padR = 16.0;
    const padT = 12.0;
    const padB = 18.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    double yOf(double ms) {
      final frac = maxMs <= minMs ? 0.0 : (ms - minMs) / (maxMs - minMs);
      return padT + (1 - frac.clamp(0.0, 1.0)) * h;
    }

    double xOf(int i) =>
        laps.length == 1 ? padL + w / 2 : padL + w * i / (laps.length - 1);

    // 网格 + 最佳圈基准虚线。
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = padT + h * i / 2;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
    }
    final bestY = yOf(fastestMs.toDouble());
    final dash = Paint()
      ..color = _kRed.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var x = padL; x < padL + w; x += 8) {
      canvas.drawLine(Offset(x, bestY), Offset(x + 4, bestY), dash);
    }

    // 折线。
    if (laps.length >= 2) {
      final path = Path()..moveTo(xOf(0), yOf(laps[0].durationMs.toDouble()));
      for (var i = 1; i < laps.length; i++) {
        path.lineTo(xOf(i), yOf(laps[i].durationMs.toDouble()));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 点 + 圈号。
    for (var i = 0; i < laps.length; i++) {
      final c = Offset(xOf(i), yOf(laps[i].durationMs.toDouble()));
      final isBest = laps[i].durationMs == fastestMs;
      canvas.drawCircle(
        c,
        isBest ? 4.5 : 3,
        Paint()..color = isBest ? _kRed : Colors.white,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${laps[i].number}',
          style: const TextStyle(color: Colors.white54, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx - tp.width / 2, size.height - 13));
    }
  }

  @override
  bool shouldRepaint(_LapTrendPainter old) =>
      old.laps != laps || old.fastestMs != fastestMs;
}

/// 一条曲线序列。
class _Series {
  final List<double> values;
  final Color color;

  /// v1.3.4：虚线（参照圈速度线用，与分析圈实线区分）。
  final bool dashed;
  const _Series({
    required this.values,
    required this.color,
    this.dashed = false,
  });
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
            Text(
              '${fmt(maxY)} $unit',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              '${fmt(minY)} $unit',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
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

  /// 赛道库轮廓（TrackInfo.outline，归一化 0..1）；非空时以灰色细线
  /// 叠在实测走线下方，让结算页与赛道库看到同一形状。
  final List<OutlinePoint>? catalogOutline;

  const _TrackLineDiagram({
    required this.slice,
    required this.deltaCurve,
    required this.mode,
    required this.scrubIndex,
    this.referenceSlice,
    this.catalogOutline,
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
          catalogOutline: catalogOutline,
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
  final List<OutlinePoint>? catalogOutline;

  _TrackLinePainter({
    required this.slice,
    required this.deltaCurve,
    required this.mode,
    required this.scrubIndex,
    this.referenceSlice,
    this.catalogOutline,
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

    // 赛道库轮廓：按实测轨迹的包围盒等比铺开，灰色细线画在最底层。
    // 轮廓与轨迹都是归一化/实测独立数据，此处只做形状对照示意。
    final outline = catalogOutline;
    if (outline != null && outline.length >= 3) {
      final path = Path();
      for (var i = 0; i < outline.length; i++) {
        final p = Offset(
          offX + outline[i].x * spanLon * scale,
          offY + outline[i].y * spanLat * scale,
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }

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
          ? Color.lerp(
                  Colors.white54,
                  _kRed,
                  (pts[i].speed - minSpeed) / (maxSpeed - minSpeed),
                ) ??
                Colors.white54
          : (i < deltaCurve.length
                ? sectorDeltaColor(
                    deltaCurve[i].abs() < 0.5 ? 0 : deltaCurve[i].round(),
                  )
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
        offsets[scrubIndex],
        3.5,
        Paint()..color = Colors.white,
      );
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

  bool get _fallback => shouldFallbackToSchematic(_failedTileUrls.length);

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
    final tr = S.of(context);
    final pts = widget.slice.points;
    if (pts.length < 2) {
      return Text(
        tr.t('暂无轨迹点，走线为空', 'No track points; line is empty'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }
    if (_fallback) {
      // 回落示意图：复用现有归一化走线图，不画假线。
      // v1.3.4：回落时参考圈叠加同样保留（经 _TrackLineDiagram）。
      final refSlice = widget.referenceSlice;
      final showRef =
          widget.showReferenceOverlay &&
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
          Text(
            tr.t('卫星图未加载，已显示示意图',
                'Satellite tiles failed; showing schematic'),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
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
          return Text(
            tr.t('暂无轨迹点，走线为空', 'No track points; line is empty'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          );
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
                  for (
                    var y = projector.tileRange.y0;
                    y <= projector.tileRange.y1;
                    y++
                  )
                    for (
                      var x = projector.tileRange.x0;
                      x <= projector.tileRange.x1;
                      x++
                    )
                      Positioned.fromRect(
                        rect: projector.tileScreenRect(x, y),
                        child: Image.network(
                          satelliteTileUrl(zoom, x, y),
                          key: ValueKey('analysis-sat-$zoom-$x-$y'),
                          headers: const {'User-Agent': 'DriveTrack/1.7.4'},
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) {
                            _onTileError(satelliteTileUrl(zoom, x, y));
                            return Container(color: const Color(0xFF0A0A0A));
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
                          color: Colors.white70,
                          fontSize: 11,
                        ),
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
    final offsets = points.map((p) => projector.project(p.lat, p.lon)).toList();
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
      final refOffsets = ref
          .map((p) => projector.project(p.lat, p.lon))
          .toList();
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
