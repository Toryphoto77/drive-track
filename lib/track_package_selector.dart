/// 赛道模式选赛道列表（赛道库版）：按包选择，不再只走目录 14 条。
///
/// - 每行前面一个 ⓘ：点开是赛道信息简介（办赛历史 + 按车型分栏的
///   最快圈速），点 ⓘ 不选中该赛道；点行内其他区域才选中。
/// - 分组：国内 / 国外 / 我的赛道；组内按中文名排序。
/// - 示意图：有经纬度中心线的包用真实中心线归一化显示；无中心线的
///   回落旧目录示意；都没有时显示“轮廓待补”，绝不编造轮廓。

import 'package:flutter/material.dart';

import 'track_library.dart';
import 'track_satellite_preview.dart';
import 'track_widgets.dart';

/// 选赛道列表（包版）。
class TrackPackageSelector extends StatelessWidget {
  final List<TrackPackage> packages;

  /// 用户赛道（单独成组，排在最后）。
  final List<TrackPackage> userTracks;
  final String? selectedId;
  final ValueChanged<TrackPackage> onSelected;
  final ValueChanged<TrackPackage> onInfo;

  const TrackPackageSelector({
    super.key,
    required this.packages,
    this.userTracks = const [],
    required this.selectedId,
    required this.onSelected,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final domestic =
        packages.where((p) => p.region == '中国').toList()
          ..sort((a, b) => a.nameCn.compareTo(b.nameCn));
    final overseas =
        packages.where((p) => p.region != '中国').toList()
          ..sort((a, b) => a.nameCn.compareTo(b.nameCn));
    final mine = userTracks.toList()
      ..sort((a, b) => a.nameCn.compareTo(b.nameCn));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            '点行首 ⓘ 看赛道简介（办赛历史与最快圈速）；点行内其他区域选为本次赛道。卡片为卫星预览（加载失败时回落示意图），仅作示意，不用于导航与计时判定',
            style: TextStyle(color: TrackTheme.textDim, fontSize: 11),
          ),
        ),
        if (domestic.isNotEmpty) ...[
          _sectionTitle('国内'),
          ...domestic.map(_tile),
        ],
        if (overseas.isNotEmpty) ...[
          _sectionTitle('国外'),
          ...overseas.map(_tile),
        ],
        if (mine.isNotEmpty) ...[
          _sectionTitle('我的赛道'),
          ...mine.map(_tile),
        ],
        if (domestic.isEmpty && overseas.isEmpty && mine.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '暂无赛道包',
              style: TextStyle(color: TrackTheme.textDim, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: TrackTheme.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tile(TrackPackage pkg) {
    final selected = pkg.id == selectedId;
    final info = trackInfoForPackage(pkg);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TrackTheme.card,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? TrackTheme.red : TrackTheme.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // 行首 ⓘ：只打开简介，不选中。
              IconButton(
                icon: const Icon(Icons.info_outline, size: 22),
                color: TrackTheme.textDim,
                tooltip: '赛道简介',
                onPressed: () => onInfo(pkg),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(pkg),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: pkg.hasCenterline
                            ? TrackSatellitePreview(
                                centerline: pkg.centerline,
                                start: pkg.start,
                                finish: pkg.finish,
                                height: 64,
                                fallback: TrackSchematicDiagram(
                                  track: info,
                                  height: 64,
                                  showCaption: false,
                                ),
                              )
                            : Container(
                                height: 64,
                                alignment: Alignment.center,
                                child: const Text(
                                  '轮廓待补',
                                  style: TextStyle(
                                    color: TrackTheme.textDim,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkg.nameCn,
                              style: const TextStyle(
                                color: TrackTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (pkg.nameEn.isNotEmpty) pkg.nameEn,
                                if (pkg.region.isNotEmpty) pkg.region,
                                pkg.lengthLabel,
                              ].join(' · '),
                              style: const TextStyle(
                                color: TrackTheme.textDim,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                _badge(
                                  '${pkg.sourceLabel} · ${pkg.verificationLabel}',
                                ),
                                _badge('v${pkg.version}'),
                                if (pkg.hasCenterline) _badge('经纬度'),
                                if (pkg.hasStartFinish) _badge('起终点'),
                                if (pkg.hasSectors) _badge('分段'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(
                          Icons.check_circle,
                          color: TrackTheme.red,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: TrackTheme.cardBorder.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: TrackTheme.textDim, fontSize: 11),
      ),
    );
  }
}
