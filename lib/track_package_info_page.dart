/// 赛道信息简介页（包版）：用于没有图鉴条目的赛道
/// （主要是用户赛道；官方 21 条走 TrackDetailPage）。
///
/// 内容：名称、长度、来源、核对状态、中心线示意图、弯角表、
/// 分段、起终点 / 龙门架；无办赛历史与最快圈时明写待核，绝不编数。

import 'package:flutter/material.dart';

import 'track_guide.dart';
import 'track_library.dart';
import 'track_satellite_preview.dart';

/// 包版赛道简介页。
class TrackPackageInfoPage extends StatelessWidget {
  final TrackPackage package;

  const TrackPackageInfoPage({super.key, required this.package});

  @override
  Widget build(BuildContext context) {
    final pkg = package;
    final info = trackInfoForPackage(pkg);
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(pkg.nameCn),
        backgroundColor: const Color(0xFF121212),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部大轮廓图：有经纬度中心线的包优先用卫星预览（卫星底图 +
            // 真实中心线 + 起终点）；瓦片失败时回落原归一化轮廓示意图。
            if (pkg.hasCenterline)
              TrackSatellitePreview(
                centerline: pkg.centerline,
                start: pkg.start,
                finish: pkg.finish,
                height: 220,
                showStatusLine: true,
                fallback: OutlineDiagram(
                  outline: info.outline,
                  height: 220,
                ),
              )
            else if (info.outline.length >= 3)
              OutlineDiagram(
                outline: info.outline,
                height: 220,
                caption: '轮廓来源：赛道库数据包',
              )
            else
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: const Center(
                  child: Text(
                    '轮廓待补',
                    style: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              pkg.nameCn,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (pkg.nameEn.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                pkg.nameEn,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(pkg.lengthLabel),
                _chip('来源：${pkg.sourceLabel}'),
                _chip('核对：${pkg.verificationLabel}'),
                _chip('数据包 v${pkg.version}'),
                if (pkg.corners.isNotEmpty) _chip('共 ${pkg.corners.length} 弯'),
              ],
            ),
            if (pkg.sourceDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pkg.sourceDetail,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (pkg.verificationNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                pkg.verificationNote,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('弯角'),
            const SizedBox(height: 8),
            if (pkg.corners.isEmpty)
              const Text(
                '弯角表：待核',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              )
            else
              for (final c in pkg.corners)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'T${c.number} ${c.directionLabel} · 半径约 ${c.radiusM}m · 转角 ${c.angleDeg}°',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
            if (pkg.cornerSource != null) ...[
              const SizedBox(height: 2),
              Text(
                pkg.cornerSource == 'osm-derived'
                    ? '弯角表来源：OSM 几何推导，非官方弯角数据'
                    : '弯角表来源：${pkg.cornerSource}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('分段 / 起终点 / 龙门架'),
            const SizedBox(height: 8),
            Text(
              pkg.sectorNote.isNotEmpty ? pkg.sectorNote : '分段：待核',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              pkg.start != null
                  ? '起点：${pkg.start!.lat.toStringAsFixed(5)}, ${pkg.start!.lon.toStringAsFixed(5)}'
                  : '起点：待核',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              pkg.finish != null
                  ? '终点：${pkg.finish!.lat.toStringAsFixed(5)}, ${pkg.finish!.lon.toStringAsFixed(5)}'
                  : '终点：待核',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              pkg.gantry != null
                  ? '龙门架：${pkg.gantry!.lat.toStringAsFixed(5)}, ${pkg.gantry!.lon.toStringAsFixed(5)}'
                  : '龙门架：待核',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (pkg.startNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                pkg.startNote,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle('办赛历史'),
            const SizedBox(height: 8),
            const Text(
              '办赛历史：待核',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 16),
            _sectionTitle('最快圈速'),
            const SizedBox(height: 8),
            const Text(
              '最快圈速：待核',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(pkg),
              child: const Text('在赛道模式中使用该赛道'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 18, color: const Color(0xFFE10600)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
