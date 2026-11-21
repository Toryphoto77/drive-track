import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_bar_style.dart';
import 'blediy_gps.dart';
import 'models.dart';
import 'track_creation.dart';
import 'track_library.dart';

class CustomTrackResult {
  final TrackPackage package;
  final GeoPoint? initialCenter;
  final bool initialSatelliteOn;

  const CustomTrackResult({
    required this.package,
    this.initialCenter,
    this.initialSatelliteOn = false,
  });
}

/// 卡丁车现场建赛：只消费外接定位流，不启动行程 Recorder。
class CustomTrackCreatePage extends StatefulWidget {
  final CustomTrackMethod initialMethod;
  final Stream<ExternalGpsFix> fixStream;
  final ExternalGpsFix? initialFix;
  final int initialFixAtMs;
  final GeoPoint? initialAnchor;

  const CustomTrackCreatePage({
    super.key,
    this.initialMethod = CustomTrackMethod.measured,
    required this.fixStream,
    this.initialFix,
    this.initialFixAtMs = 0,
    this.initialAnchor,
  });

  @override
  State<CustomTrackCreatePage> createState() => _CustomTrackCreatePageState();
}

class _CustomTrackCreatePageState extends State<CustomTrackCreatePage> {
  late CustomTrackMethod _method;
  late final TextEditingController _nameCtrl;
  late final StreamSubscription<ExternalGpsFix> _sub;
  late final Timer _freshnessTimer;
  ExternalGpsFix? _latestFix;
  int _lastFixAtMs = 0;
  bool _measuring = false;

  /// 多圈采集：先跑 2–3 圈，生成时取“最后一次回到起点后的整圈”，
  /// 避免把出场圈 / 多圈重复轨迹整段塞进中心线。
  bool _multiLap = false;
  final List<TrackPoint> _points = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _method = widget.initialMethod;
    _nameCtrl = TextEditingController(text: '我的卡丁赛道');
    _latestFix = widget.initialFix;
    _lastFixAtMs = widget.initialFixAtMs;
    _sub = widget.fixStream.listen(_onFix);
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    _freshnessTimer.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _ready3D => external3DFixReady(_latestFix, _lastFixAtMs);

  GeoPoint? get _drawingAnchor {
    final fix = _latestFix;
    if (fix != null &&
        _lastFixAtMs > 0 &&
        DateTime.now().millisecondsSinceEpoch - _lastFixAtMs <= 10000 &&
        fix.lat.isFinite &&
        fix.lon.isFinite &&
        fix.lat.abs() <= 90 &&
        fix.lon.abs() <= 180) {
      return GeoPoint(fix.lat, fix.lon);
    }
    return widget.initialAnchor;
  }

  TrackPoint _trackPoint(ExternalGpsFix fix) => TrackPoint(
    timeMs: _lastFixAtMs,
    lat: fix.lat,
    lon: fix.lon,
    alt: fix.altitudeM ?? 0,
    speed: fix.speedMps ?? 0,
    bearing: fix.bearingDeg ?? 0,
    hAcc: 999,
    vAcc: 999,
    speedAcc: 999,
    provider: 'external',
    longG: 0,
    latG: 0,
    vertG: 0,
    pitch: 0,
    roll: 0,
    heading: fix.bearingDeg ?? 0,
    pressureHpa: 0,
    calibrated: false,
    satCount: fix.usedSatellites ?? fix.satellites,
    locSource: 'external',
    altValid: fix.altitudeM != null,
  );

  void _onFix(ExternalGpsFix fix) {
    if (!mounted) return;
    setState(() {
      _latestFix = fix;
      _lastFixAtMs = DateTime.now().millisecondsSinceEpoch;
      if (_measuring && external3DFixReady(fix, _lastFixAtMs)) {
        _points.add(_trackPoint(fix));
        _error = null;
      }
    });
  }

  void _startMeasured() {
    setState(() {
      _measuring = true;
      _points.clear();
      _error = null;
      final fix = _latestFix;
      if (fix != null && _ready3D) _points.add(_trackPoint(fix));
    });
  }

  /// 生成中心线用的点：单圈直接整段；多圈取最后一次回到起点后的
  /// 一整圈（起点 25 m 内视为过线，圈长不足 150 m 不算，避免漂移误触）。
  List<TrackPoint> _pointsForPackage() {
    if (!_multiLap) return List.of(_points);
    final pts = _points;
    if (pts.length < 20) return List.of(pts);
    final start = pts.first;
    var lastCut = 0;
    for (var i = 10; i < pts.length; i++) {
      final p = pts[i];
      if (haversineM(start.lat, start.lon, p.lat, p.lon) > 25) continue;
      final seg = pts.sublist(lastCut, i + 1);
      final len = polylineLengthM(
        seg.map((e) => GeoPoint(e.lat, e.lon)).toList(),
      );
      if (len >= 150) lastCut = i;
    }
    if (lastCut == 0) return List.of(pts);
    return pts.sublist(lastCut);
  }

  void _finishMeasured() {
    final points = _pointsForPackage();
    final problem = measuredTrackProblem(points);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).pop(
      CustomTrackResult(
        package: measuredTrackPackage(
          id: id,
          name: _nameCtrl.text,
          points: points,
        ),
      ),
    );
  }

  void _startDrawing() {
    final anchor = _drawingAnchor;
    if (anchor == null) return;
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).pop(
      CustomTrackResult(
        package: emptyTrackPackageAt(
          id: id,
          name: _nameCtrl.text,
          anchor: anchor,
        ),
        initialCenter: anchor,
        initialSatelliteOn: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fix = _latestFix;
    final accent = Theme.of(context).colorScheme.primary;
    // 采集中：整屏切成驾驶 HUD（大速度 + 大按钮），不再和参数输入
    // 挤在同一页，避免开车时误触、看不清。
    if (_measuring) return _buildDrivingHud(accent);
    final lengthM = polylineLengthM(
      _points.map((p) => GeoPoint(p.lat, p.lon)).toList(),
    );
    final measured = _method == CustomTrackMethod.measured;
    final canStart = measured ? _ready3D : _drawingAnchor != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0F),
      appBar: DtAppBar(title: const Text('创建自定义赛道')),
      body: SafeArea(
        // 表单全部一次性构建（页面不长），避免长按/开始按钮落在
        // 屏幕外时被懒加载跳过——开车前需要随时能点到主按钮。
        child: SingleChildScrollView(
          padding: withAppBarTopInset(
            context,
            const EdgeInsets.fromLTRB(16, 12, 16, 28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 第 1 步：选择方式（现场实测 / 卫星绘制）。
              const Text(
                '第 1 步 · 选择建赛方式',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _methodSwitch(accent),
              const SizedBox(height: 16),
              _statusCard(accent: accent, measured: measured, fix: fix),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                enabled: !_measuring,
                maxLength: 24,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: '赛道名称',
                  counterText: '',
                  labelStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF17171A),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.4),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                ),
              ),
              if (measured) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _multiLap,
                  title: const Text(
                    '跑几圈再生成（取最后一整圈）',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    '适合临时场地：先跑 2–3 圈，长按完成时自动裁掉出场圈与重复圈。',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  onChanged: (v) => setState(() => _multiLap = v),
                ),
              ],
              const SizedBox(height: 16),
              _guideCard(measured: measured, measuring: _measuring),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x33FF5252),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x55FF5252)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Color(0xFFFF8A80),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Text(
                '第 2 步 · ${measured ? '驾驶采集' : '卫星图绘制'}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: ValueKey(
                  measured ? 'start-track-measure' : 'start-track-draw',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF232327),
                  disabledForegroundColor: Colors.white38,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: measured
                    ? (_ready3D ? _startMeasured : null)
                    : (_drawingAnchor == null ? null : _startDrawing),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(measured ? '开始 3D 定位实测' : '进入卫星图绘制'),
              ),
              if (!canStart) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    measured ? '已连接硬件时，请到空旷处等待 3D 定位' : '需要至少一次有效定位，用于确定卫星图中心',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
              if (_points.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '上次采集 ${_points.length} 点 · ${lengthM.toStringAsFixed(0)} 米',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 第 2 步：驾驶采集 HUD。
  ///
  /// 驾驶中可读性优先：速度一个超大数字，状态只留卫星 / 点数 / 长度，
  /// 名称等参数全部收起；底部只放“长按 1 秒完成”（防误触）与取消。
  Widget _buildDrivingHud(Color accent) {
    final fix = _latestFix;
    final kmh = (fix?.speedMps ?? 0) * 3.6;
    final sats = fix?.usedSatellites ?? fix?.satellites ?? 0;
    final lengthM = polylineLengthM(
      _points.map((p) => GeoPoint(p.lat, p.lon)).toList(),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF07080A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _ready3D
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '赛道采集中',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _hudPill(Icons.satellite_alt, '$sats 星'),
                  const SizedBox(width: 8),
                  _hudPill(Icons.timeline, '${_points.length} 点'),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kmh.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 104,
                        height: 0.95,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      'km/h',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '已采集 ${lengthM.toStringAsFixed(0)} 米',
                      style: TextStyle(
                        fontSize: 16,
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!_ready3D) ...[
                      const SizedBox(height: 10),
                      const Text(
                        '等待 3D 定位，信号弱时轨迹会跳点',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _HoldToFinishButton(
                    enabled: _points.length >= 2,
                    accent: accent,
                    onFinish: _finishMeasured,
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() {
                      _measuring = false;
                      _points.clear();
                      _error = null;
                    }),
                    child: const Text(
                      '取消本次采集',
                      style: TextStyle(color: Colors.white38),
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

  Widget _hudPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF17181C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// 自定义分段切换：统一走主题 accent，不再使用 Material 默认的
  /// 二级色（此前选中的一段是青绿色，与全 App 黑色 + 红色主题不一致）。
  Widget _methodSwitch(Color accent) {
    Widget pill(CustomTrackMethod value, IconData icon, String label) {
      final selected = _method == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _measuring
              ? null
              : () => setState(() {
                  _method = value;
                  _error = null;
                }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          pill(CustomTrackMethod.measured, Icons.route, '现场 3D 实测'),
          const SizedBox(width: 4),
          pill(CustomTrackMethod.satellite, Icons.satellite_alt, '卫星图手动绘制'),
        ],
      ),
    );
  }

  Widget _statusCard({
    required Color accent,
    required bool measured,
    required ExternalGpsFix? fix,
  }) {
    final ready = measured ? _ready3D : _drawingAnchor != null;
    final statusColor = ready ? const Color(0xFF22C55E) : Colors.white38;
    final headline = measured
        ? (fix?.fixMode == 3
              ? '3D 定位已就绪'
              : fix?.fixMode == 2
              ? '2D 定位，缺少海拔'
              : '等待外接定位')
        : (_drawingAnchor == null ? '等待当前定位' : '定位已就绪');
    final sub = measured
        ? (ready ? '可以开始跑圈采集中心线' : '实测需要有效 3D 定位与海拔')
        : '定位只作为卫星图初始中心，不会自动生成赛道';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1F), Color(0xFF121215)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ready ? accent.withValues(alpha: 0.55) : Colors.white10,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ready ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 20,
                  color: ready ? accent : Colors.white38,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white10),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('卫星', fix?.satellites?.toString() ?? '—'),
              _metric(
                '频率',
                fix?.hz == null ? '—' : '${fix!.hz!.toStringAsFixed(0)} Hz',
              ),
              _metric(
                '海拔',
                fix?.altitudeM == null
                    ? '—'
                    : '${fix!.altitudeM!.toStringAsFixed(1)} m',
              ),
              _metric('已采', '${_points.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideCard({required bool measured, required bool measuring}) {
    final steps = measured
        ? const ['驾车沿赛道正常行驶一整圈', '回到起点附近点击完成', '在编辑器里微调起终点与分段点']
        : const ['用定位锚定卫星图视野', '沿赛道绘制中心线', '设定起终点与分段点后保存'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141417),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 16, color: Colors.white38),
              const SizedBox(width: 6),
              Text(
                measured ? '现场实测要求' : '卫星图绘制说明',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (measuring)
                Text(
                  '至少 30 点 / 100 米',
                  style: TextStyle(
                    color: const Color(0xFFE10600).withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key + 1}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (measured)
            const Text(
              '起终点需在 100 米内闭合；点数或距离不足时不会生成赛道。',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 11,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}

/// 「长按 1 秒完成」大按钮：驾驶中防误触。
///
/// 普通点击无效（会立刻回弹），必须持续按住 1 秒，进度条走满后
/// 才触发 [onFinish] 并带一次震动反馈；松手立即反向退回。
class _HoldToFinishButton extends StatefulWidget {
  const _HoldToFinishButton({
    required this.enabled,
    required this.accent,
    required this.onFinish,
  });

  final bool enabled;
  final Color accent;
  final VoidCallback onFinish;

  @override
  State<_HoldToFinishButton> createState() => _HoldToFinishButtonState();
}

class _HoldToFinishButtonState extends State<_HoldToFinishButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed || _fired) return;
      _fired = true;
      unawaited(HapticFeedback.mediumImpact());
      widget.onFinish();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled
          ? (_) {
              _fired = false;
              _c.forward();
            }
          : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTapCancel: enabled ? _release : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: enabled ? widget.accent : const Color(0xFF232327),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 进度：按住时从左往右填满。
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _c.value.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        enabled ? '长按 1 秒完成' : '至少采集 2 个点',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled ? '松手即取消，防误触' : '等待 GPS 采集轨迹',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _release() {
    if (_fired) return;
    _c.reverse();
  }
}
