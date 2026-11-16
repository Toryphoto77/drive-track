import 'dart:async';

import 'package:flutter/material.dart';

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
  static const _red = Color(0xFFE10600);
  late CustomTrackMethod _method;
  late final TextEditingController _nameCtrl;
  late final StreamSubscription<ExternalGpsFix> _sub;
  late final Timer _freshnessTimer;
  ExternalGpsFix? _latestFix;
  int _lastFixAtMs = 0;
  bool _measuring = false;
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

  void _finishMeasured() {
    final problem = measuredTrackProblem(_points);
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
          points: List.of(_points),
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
    final modeLabel = fix?.fixMode == 3
        ? '3D 定位'
        : fix?.fixMode == 2
        ? '2D 定位'
        : '等待外接定位';
    final lengthM = polylineLengthM(
      _points.map((p) => GeoPoint(p.lat, p.lon)).toList(),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: DtAppBar(title: const Text('创建自定义赛道')),
      body: SafeArea(
        child: ListView(
          padding: withAppBarTopInset(
            context,
            const EdgeInsets.fromLTRB(16, 12, 16, 24),
          ),
          children: [
            SegmentedButton<CustomTrackMethod>(
              segments: const [
                ButtonSegment(
                  value: CustomTrackMethod.measured,
                  icon: Icon(Icons.route),
                  label: Text('现场 3D 实测'),
                ),
                ButtonSegment(
                  value: CustomTrackMethod.satellite,
                  icon: Icon(Icons.satellite_alt),
                  label: Text('卫星图手动绘制'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: _measuring
                  ? null
                  : (selection) => setState(() {
                      _method = selection.first;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              enabled: !_measuring,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '赛道名称',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _ready3D ? const Color(0xFF22C55E) : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _ready3D ? Icons.check_circle : Icons.gps_not_fixed,
                        color: _ready3D
                            ? const Color(0xFF22C55E)
                            : Colors.white54,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _method == CustomTrackMethod.measured
                              ? '$modeLabel${_ready3D ? '，可以开始' : '，实测需要有效 3D 定位'}'
                              : (_drawingAnchor == null
                                    ? '等待当前定位作为卫星图中心'
                                    : '当前定位已就绪'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_method == CustomTrackMethod.measured) ...[
                    const SizedBox(height: 10),
                    Text(
                      '已采集 ${_points.length} 点 · ${lengthM.toStringAsFixed(0)} 米',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '开始后请驾车沿赛道正常行驶一整圈，回到起点附近后完成。至少 30 点、100 米，起终点需在 100 米内。',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Text(
                      '下一步在 Esri 卫星图上绘制中心线、起终点和分段点。定位只决定初始视图，不会自动生成赛道。',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
            ],
            const SizedBox(height: 20),
            if (_method == CustomTrackMethod.measured) ...[
              FilledButton.icon(
                key: const ValueKey('start-track-measure'),
                style: FilledButton.styleFrom(
                  backgroundColor: _red,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _measuring
                    ? _finishMeasured
                    : (_ready3D ? _startMeasured : null),
                icon: Icon(_measuring ? Icons.flag : Icons.play_arrow),
                label: Text(_measuring ? '完成整圈并编辑赛道' : '开始 3D 定位实测'),
              ),
              if (_measuring)
                TextButton(
                  onPressed: () => setState(() {
                    _measuring = false;
                    _points.clear();
                    _error = null;
                  }),
                  child: const Text('取消本次实测'),
                ),
            ] else
              FilledButton.icon(
                key: const ValueKey('start-track-draw'),
                style: FilledButton.styleFrom(
                  backgroundColor: _red,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _drawingAnchor == null ? null : _startDrawing,
                icon: const Icon(Icons.edit_location_alt),
                label: const Text('进入卫星图绘制'),
              ),
          ],
        ),
      ),
    );
  }
}
