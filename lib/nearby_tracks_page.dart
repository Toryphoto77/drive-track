/// 附近的赛道（v1.6.0）。
///
/// 入口在赛道库页顶部。用当前位置把本地赛道库按直线距离排序，并尽量在地图上
/// 标出来；分类按赛道名称归类（卡丁车 / 摩托 / 汽车）。
///
/// 数据口径：
/// - 距离：当前位置到赛道起终点（没有起终点时取中心线首点）的直线距离，
///   用于排序，不是导航里程。
/// - 地图：高德静态地图（需要已配置 Web 服务 Key）。Key 缺失或取图失败时
///   只显示列表，功能不中断——不编造地图。
/// - 分类：赛道包没有类型字段，按中英文名里的关键词归类（卡丁/kart、
///   摩托/moto/superbike 等），其余算汽车赛道。列表里会注明“按名称归类”。
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'amap_service.dart';
import 'app_bar_style.dart';
import 'models.dart';
import 'native.dart';
import 'track_library.dart';
import 'track_timing.dart';

/// 赛道类型（仅用于“附近的赛道”的分类筛选）。
enum TrackKind { kart, moto, car }

extension TrackKindLabel on TrackKind {
  String get label => switch (this) {
        TrackKind.kart => '卡丁车',
        TrackKind.moto => '摩托',
        TrackKind.car => '汽车',
      };
}

/// 按赛道名称归类：赛道包目前没有类型字段，只能从名称关键词判断。
/// 归不了类的按汽车赛道处理（数量最多），并在页面上注明口径。
TrackKind trackKindOf(TrackPackage p) {
  final s = '${p.nameCn} ${p.nameEn}'.toLowerCase();
  if (s.contains('卡丁') || s.contains('kart')) return TrackKind.kart;
  if (s.contains('摩托') ||
      s.contains('moto') ||
      s.contains('superbike') ||
      s.contains('motorbike')) {
    return TrackKind.moto;
  }
  return TrackKind.car;
}

/// 赛道代表点：起终点优先，没有则用中心线首点。
GeoPoint? trackAnchor(TrackPackage p) {
  if (p.start != null) return p.start;
  if (p.finish != null) return p.finish;
  if (p.centerline.isNotEmpty) return p.centerline.first;
  return null;
}

class NearbyTrackHit {
  NearbyTrackHit(this.pkg, this.distanceM, this.anchor);
  final TrackPackage pkg;
  final double? distanceM;
  final GeoPoint? anchor;
}

class NearbyTracksPage extends StatefulWidget {
  const NearbyTracksPage({
    super.key,
    required this.official,
    required this.userTracks,
  });

  final List<TrackPackage> official;
  final List<TrackPackage> userTracks;

  @override
  State<NearbyTracksPage> createState() => _NearbyTracksPageState();
}

class _NearbyTracksPageState extends State<NearbyTracksPage> {
  StreamSubscription<Map<String, dynamic>>? _locSub;
  Timer? _locTimeout;
  (double lat, double lon)? _pos;
  bool _locating = true;
  String? _locError;

  TrackKind? _kindFilter; // null = 全部
  Uint8List? _mapBytes;
  bool _mapLoading = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _locTimeout?.cancel();
    super.dispose();
  }

  void _locate() {
    _locSub?.cancel();
    _locTimeout?.cancel();
    setState(() {
      _locating = true;
      _locError = null;
    });
    // 主流程已在跑定位；这里再要一次，拿到的第一条有效定位就用。
    unawaited(Native.startLocation());
    _locSub = Native.locationStream.listen((e) {
      final lat = (e['lat'] as num?)?.toDouble() ?? 0;
      final lon = (e['lon'] as num?)?.toDouble() ?? 0;
      if (lat == 0 && lon == 0) return;
      _locSub?.cancel();
      _locTimeout?.cancel();
      if (!mounted) return;
      setState(() {
        _pos = (lat, lon);
        _locating = false;
      });
      _loadMap();
    }, onError: (_) {});
    // 8 秒还没拿到定位就停掉“定位中”，列表按库内顺序显示。
    _locTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _locSub?.cancel();
      setState(() {
        _locating = false;
        _locError = '拿不到当前位置（检查系统定位权限），列表未按距离排序';
      });
    });
  }

  List<NearbyTrackHit> get _hits {
    final all = <NearbyTrackHit>[];
    for (final p in [...widget.official, ...widget.userTracks]) {
      if (_kindFilter != null && trackKindOf(p) != _kindFilter) continue;
      final a = trackAnchor(p);
      final d = (_pos != null && a != null)
          ? haversineM(_pos!.$1, _pos!.$2, a.lat, a.lon)
          : null;
      all.add(NearbyTrackHit(p, d, a));
    }
    all.sort((x, y) {
      if (x.distanceM == null && y.distanceM == null) return 0;
      if (x.distanceM == null) return 1;
      if (y.distanceM == null) return -1;
      return x.distanceM!.compareTo(y.distanceM!);
    });
    return all;
  }

  Future<void> _loadMap() async {
    final pos = _pos;
    if (pos == null) return;
    final marks = <(double lat, double lon)>[];
    final nearest = _hits.where((h) => h.anchor != null).take(9).toList();
    for (final h in nearest) {
      marks.add((h.anchor!.lat, h.anchor!.lon));
    }
    if (marks.isEmpty) return;
    // 中心：所有点的平均（比用当前位置更稳，赛道群不在地图边缘）。
    var latSum = pos.$1, lonSum = pos.$2;
    for (final m in marks) {
      latSum += m.$1;
      lonSum += m.$2;
    }
    final n = marks.length + 1;
    final center = (latSum / n, lonSum / n);
    // zoom：按最远点距离粗估（10km 以内 13，30km 12，100km 11，其余 10）。
    var maxD = 0.0;
    for (final m in marks) {
      maxD = math.max(maxD, haversineM(center.$1, center.$2, m.$1, m.$2));
    }
    final zoom = maxD < 10000
        ? 13
        : maxD < 30000
            ? 12
            : maxD < 100000
                ? 11
                : 10;
    setState(() => _mapLoading = true);
    final bytes = await fetchNearbyStaticMap(center, zoom: zoom, marks: marks);
    if (!mounted) return;
    setState(() {
      _mapBytes = bytes;
      _mapLoading = false;
    });
  }

  String _distLabel(double? m) {
    if (m == null) return '—';
    if (m < 1000) return '${m.toStringAsFixed(0)} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('附近的赛道')),
      body: ListView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 12, 16, 24),
        ),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          if (_mapBytes != null || _mapLoading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 2, // 与 kStaticMapSize 1024*512 一致
                child: _mapLoading
                    ? Container(
                        color: const Color(0xFF1E1E1E),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Image.memory(_mapBytes!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '地图标注：白色 A 为定位中心，数字与下方列表序号对应',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            children: [
              _kindChip(null, '全部'),
              for (final k in TrackKind.values) _kindChip(k, k.label),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '分类：赛道包暂无类型字段，按中文/英文名称关键词归类',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (hits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '该分类下暂无赛道',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < hits.length; i++)
              _hitRow(i + 1, hits[i]),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final pos = _pos;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            _locating ? Icons.gps_not_fixed : Icons.gps_fixed,
            color: _locating ? Colors.orange : const Color(0xFF22C55E),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _locating
                  ? '正在定位…'
                  : pos == null
                      ? (_locError ?? '未定位')
                      : '已定位 ${pos.$1.toStringAsFixed(4)}, ${pos.$2.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _locating ? null : _locate,
            child: const Text('重新定位'),
          ),
        ],
      ),
    );
  }

  Widget _kindChip(TrackKind? kind, String label) {
    final selected = _kindFilter == kind;
    return GestureDetector(
      onTap: () {
        setState(() => _kindFilter = kind);
        if (_pos != null) _loadMap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _hitRow(int index, NearbyTrackHit hit) {
    final p = hit.pkg;
    return Card(
      color: const Color(0xFF1E1E1E),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          child: Text(
            '$index',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        title: Text(
          p.nameCn,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: Text(
          [
            if (p.region.isNotEmpty) p.region,
            trackKindOf(p).label,
            if (hit.anchor != null)
              '${hit.anchor!.lat.toStringAsFixed(4)}, ${hit.anchor!.lon.toStringAsFixed(4)}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        trailing: Text(
          _distLabel(hit.distanceM),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}
