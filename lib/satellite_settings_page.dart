import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'glass_button.dart';
import 'satellite_pill.dart';
import 'satellite_service.dart';

/// v0.1.9 外部 GPS 可视化配置页（原“定位 · 直连卫星”页重构）。
///
/// 原来为什么全是文字：此前只做了说明/向导文案（直连开关 +
/// 一行卫星数字 + 一段限制说明），从未接可视化状态——卫星数、
/// 星座、CN0 只有数字文本，没有状态卡、没有信号可视化、没有
/// 连接步骤、没有参数卡。本页把已有的真实数据（SatelliteService
/// 快照）画出来，不编任何新数字。
///
/// - 顶部设备连接状态卡：已连接/未连接、设备名、信号状态 pill；
/// - 卫星状态可视化：卫星数、星座分布条、CN0 信号格；
/// - 连接步骤图：搜索 → 配对 → 解析 NMEA → 定位，当前步高亮；
class SatelliteSettingsPage extends StatefulWidget {
  const SatelliteSettingsPage({super.key});
  @override
  State<SatelliteSettingsPage> createState() => _SatelliteSettingsPageState();
}

class _SatelliteSettingsPageState extends State<SatelliteSettingsPage> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SatelliteService.instance.start();
    SatelliteService.instance.addListener(_tick);
    SatelliteService.instance.refreshSnapshot();
  }

  @override
  void dispose() {
    SatelliteService.instance.removeListener(_tick);
    super.dispose();
  }

  void _tick() => mounted ? setState(() {}) : null;

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    final r = await SatelliteService.instance.setDirectMode(v);
    if (mounted) {
      setState(() => _busy = false);
      if ((r['ok'] as bool?) != true) {
        setState(() => _error = '切换失败：${r['error'] ?? '请先授予定位权限'}');
      } else {
        setState(() => _error = null);
      }
    }
  }

  /// 信号状态 pill：按平均 CN0 划分（本页划分，非设备标称）：
  /// ≥35 强，≥25 中，有数据但更低为弱，无数据为无信号。
  (String, Color) _signalState(double? cn0) {
    if (cn0 == null) return ('无信号', Colors.white38);
    if (cn0 >= 35) return ('信号强', Colors.greenAccent);
    if (cn0 >= 25) return ('信号中', Colors.yellowAccent);
    return ('信号弱', Colors.orange);
  }

  /// 连接步骤当前步（本页映射，如实按快照状态推导，不伪造设备状态）：
  /// 0 搜索（无快照）→ 1 配对（直连已开启、等待卫星/设备）
  /// → 2 解析 NMEA（已见卫星、尚未参与解算）
  /// → 3 定位（有卫星参与解算）。
  int _stepIndex(SatelliteService svc) {
    final snap = svc.latest;
    if (snap == null) return 0;
    if (svc.usedCount > 0) return 3;
    if (svc.visibleCount > 0) return 2;
    return svc.directMode ? 1 : 0;
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _bar(String label, int count, int total) {
    final frac = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 8,
              color: Colors.white12,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 24, child: Text('$count', style: const TextStyle(fontSize: 12), textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _cn0Grid(double? cn0) {
    // 信号格：5 格，平均 CN0 按 0–50 dB-Hz 映射（无数据 0 格）。
    final filled = cn0 == null ? 0 : (cn0 / 50 * 5).round().clamp(0, 5);
    return Row(children: [
      for (var i = 0; i < 5; i++) ...[
        Container(
          width: 10,
          height: 6 + i * 4.0,
          decoration: BoxDecoration(
            color: i < filled ? Colors.greenAccent : Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
      ],
      const SizedBox(width: 6),
      Text(cn0 == null ? 'CN0 —' : 'CN0 ${cn0.toStringAsFixed(1)} dB-Hz',
          style: const TextStyle(fontSize: 12, color: Colors.white70)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final svc = SatelliteService.instance;
    final snap = svc.latest;
    final connected = snap != null && svc.usedCount > 0;
    final signal = _signalState(svc.avgCn0DbHz);
    final step = _stepIndex(svc);
    const steps = ['搜索', '配对', '解析 NMEA', '定位'];
    final by = snap?.visibleByConstellation ?? const <GnssConstellation, int>{};
    final totalVisible = svc.visibleCount;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('外部 GPS · 可视化配置'),
      ),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.only(bottom: 24)),
        children: [
          // 顶部设备连接状态卡。
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('设备连接状态', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _pill(connected ? '已连接' : '未连接',
                      connected ? Colors.greenAccent : Colors.orange),
                  const SizedBox(width: 8),
                  _pill(signal.$1, signal.$2),
                ]),
                const SizedBox(height: 10),
                Text(
                  svc.directMode ? '设备：手机内置 GNSS（直连卫星模式）' : '设备：手机内置 GNSS（融合定位模式）',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  '外接 GPS：暂无 NMEA 数据流。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CompactSatellitePill(
                    value: svc.directMode,
                    onChanged: _busy ? null : _toggle,
                    satelliteCount: snap == null ? null : svc.visibleCount,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_error!, style: const TextStyle(color: Colors.orange)),
                  ),
              ]),
            ),
          ),
          // 卫星状态可视化。
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '卫星状态 · 可见 ${svc.visibleCount} · 参与解算 ${svc.usedCount}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _cn0Grid(svc.avgCn0DbHz),
                const SizedBox(height: 8),
                if (snap == null)
                  const Text('暂无卫星数据（请在室外开阔处等待首次定位）',
                      style: TextStyle(color: Colors.white54, fontSize: 12))
                else ...[
                  _bar('GPS', by[GnssConstellation.gps] ?? 0, totalVisible),
                  _bar('北斗', by[GnssConstellation.beidou] ?? 0, totalVisible),
                  _bar('Galileo', by[GnssConstellation.galileo] ?? 0, totalVisible),
                  _bar('GLONASS', by[GnssConstellation.glonass] ?? 0, totalVisible),
                  if (snap.l5Seen)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('本历元见过 L5 信号（不等同于支持双频）',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新卫星快照'),
                  onPressed: () => svc.refreshSnapshot(),
                ),
              ]),
            ),
          ),
          // 连接步骤图：当前步高亮。
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('连接步骤', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i <= step
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white24,
                          ),
                        ),
                      Column(children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: i == step
                              ? Theme.of(context).colorScheme.primary
                              : (i < step ? Colors.green : Colors.white24),
                          child: Icon(
                            i < step
                                ? Icons.check
                                : (i == 0
                                    ? Icons.search
                                    : i == 1
                                        ? Icons.bluetooth
                                        : i == 2
                                            ? Icons.code
                                            : Icons.location_on),
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(steps[i],
                            style: TextStyle(
                                fontSize: 11,
                                color: i == step ? Colors.white : Colors.white54,
                                fontWeight: i == step ? FontWeight.bold : FontWeight.normal)),
                      ]),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text('当前：${steps[step]}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(kDirectSatelliteLimitations, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }

}
