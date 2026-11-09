/// 本机行程与云端行程的只读对比（不上传、不覆盖、不删）。
///
/// 冲突处理留给用户：本模块只报告「仅本机 / 仅云端 / 两边都有」，
/// 不做自动合并。现有 private backup / public share 路径不受影响。
class CloudLocalCompare {
  final int localCount;
  final int cloudCount;
  final List<String> onlyLocalIds;
  final List<String> onlyCloudIds;
  final List<String> bothIds;

  const CloudLocalCompare({
    required this.localCount,
    required this.cloudCount,
    required this.onlyLocalIds,
    required this.onlyCloudIds,
    required this.bothIds,
  });

  /// 英文摘要，给 UI / 测试用（界面文案保持英文关键句）。
  String get summary =>
      'Local $localCount / Cloud $cloudCount · '
      'only local ${onlyLocalIds.length} · '
      'only cloud ${onlyCloudIds.length} · '
      'both ${bothIds.length}';

  /// 纯函数：用本机 id 集合与云端 id 集合做差。
  /// 从云端 storage_path 抽出本机行程 id。
  /// 形如 `public-files/<uid>/<tripId>.json` 或 `<uid>/<tripId>.json`。
  static String? localIdFromStoragePath(String storagePath) {
    final p = storagePath.trim();
    if (p.isEmpty) return null;
    final name = p.split('/').last;
    if (!name.endsWith('.json')) return name.isEmpty ? null : name;
    final id = name.substring(0, name.length - 5);
    return id.isEmpty ? null : id;
  }

  static CloudLocalCompare fromIds(
      Iterable<String> localIds, Iterable<String> cloudIds) {
    final local = localIds.toSet();
    final cloud = cloudIds.toSet();
    final both = local.intersection(cloud).toList()..sort();
    final onlyLocal = local.difference(cloud).toList()..sort();
    final onlyCloud = cloud.difference(local).toList()..sort();
    return CloudLocalCompare(
      localCount: local.length,
      cloudCount: cloud.length,
      onlyLocalIds: onlyLocal,
      onlyCloudIds: onlyCloud,
      bothIds: both,
    );
  }
}
