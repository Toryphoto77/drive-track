/// 赛道库页：数据包管理器，不是信息浏览器。
///
/// - 只列赛道数据包：每行显示赛道名、数据包版本、来源、更新状态，
///   附操作（检查更新 / 更新 / 删除 / 导出 / 编辑）。
/// - 本页不显示赛道图、历史、最快圈等任何浏览信息（浏览收进
///   选赛道列表的 ⓘ 简介页）。
/// - 顶部显示赛道库数据总版本；每条包自带自己的版本；更新按条进行。
/// - 提交入口必须隐藏：连点数据总版本 7 次才解锁策展模式，常规界面
///   绝不出现它；本轮策展模式含包导出，完整发布流（应用内直发仓库）
///   暂未接入，见策展区说明。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'track_library.dart';
import 'track_package_editor.dart';

/// 赛道库页。
class TrackLibraryPage extends StatefulWidget {
  /// 全部行程索引（调用方已排除演示行程；导入时再按 demo 过滤一次）。
  final List<TripMeta> metas;

  /// 按行程 id 加载完整 Trip（用于从行程导入）。
  final Future<Trip?> Function(String tripId) loadTrip;

  const TrackLibraryPage({
    super.key,
    required this.metas,
    required this.loadTrip,
  });

  @override
  State<TrackLibraryPage> createState() => _TrackLibraryPageState();
}

class _TrackLibraryPageState extends State<TrackLibraryPage> {
  final _service = TrackLibraryService.instance;
  LibrarySnapshot? _snap;
  UpdateCheckResult? _check;
  bool _checking = false;
  bool _applying = false;

  // 策展模式 gate：2 秒内连点数据总版本 7 次解锁，仅本页会话有效。
  bool _curation = false;
  int _tapCount = 0;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final snap = await _service.loadAll();
    if (!mounted) return;
    setState(() => _snap = snap);
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds < 2) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTap = now;
    if (_tapCount >= 7 && !_curation) {
      setState(() => _curation = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('策展模式已解锁')),
      );
    }
  }

  Future<void> _checkUpdates() async {
    setState(() {
      _checking = true;
      _check = null;
    });
    final result = await _service.checkForUpdates();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _check = result;
    });
    if (result.status == UpdateCheckStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _applyOne(PackageUpdate u) async {
    if (_check == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('更新「${u.nameCn}」？'),
        content: Text(
          u.isNew
              ? '远端新增包 v${u.remoteVersion}，下载后加入本地库。'
              : '本地 v${u.localVersion} → 远端 v${u.remoteVersion}。'
              '用户改过的包不会被覆盖；更新失败不影响本地数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('更新'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _apply([u]);
  }

  Future<void> _applyAll() async {
    final updates = _check?.updates ?? const [];
    if (updates.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新全部可更新包？'),
        content: Text(
          '共 ${updates.length} 个包。用户改过的包不会被覆盖；'
          '单个包下载失败不影响其他包与本地数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部更新'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _apply(updates);
  }

  Future<void> _apply(List<PackageUpdate> updates) async {
    setState(() => _applying = true);
    final result = await _service.applyUpdates(
      updates: updates,
      manifestDataVersion: _check?.remoteDataVersion ?? '',
    );
    await _refresh();
    if (!mounted) return;
    setState(() {
      _applying = false;
      _check = null;
    });
    final msg = StringBuffer('已更新 ${result.appliedIds.length} 个包');
    if (result.skippedReasons.isNotEmpty) {
      msg.write('；跳过 ${result.skippedReasons.length} 个');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
  }

  Future<void> _export(TrackPackage pkg) async {
    try {
      final path = await _service.exportPackage(pkg);
      await Native.shareFiles(
        [path],
        'application/json',
        '赛道数据包 ${pkg.nameCn} v${pkg.version}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _exportAll() async {
    final snap = _snap;
    if (snap == null) return;
    try {
      final dir = await Native.getFilesDir();
      final path = '$dir/track_library_export_all.json';
      final doc = {
        'dataVersion': snap.dataVersion,
        'packages': [
          ...snap.official.map((p) => p.toJson()),
          ...snap.userTracks.map((p) => p.toJson()),
        ],
      };
      await File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(doc),
      );
      await Native.shareFiles([path], 'application/json', '赛道库全部数据包');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _edit(TrackPackage pkg) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackPackageEditorPage(
          package: pkg,
          onSave: (updated) async {
            await _service.savePackage(updated);
          },
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _deleteUserTrack(TrackPackage pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${pkg.nameCn}」？'),
        content: const Text('该用户赛道将从本地删除，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteUserTrack(pkg.id);
    await _refresh();
  }

  Future<void> _resetOverride(TrackPackage pkg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('恢复「${pkg.nameCn}」默认？'),
        content: const Text(
          '本地版本（用户改动或远端更新）将被删除，回到打包种子 / 内置迁移版本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.resetOverride(pkg.id);
    await _refresh();
  }

  Future<void> _importFromTrip() async {
    final trips = widget.metas.where((m) => !m.demo).toList()
      ..sort((a, b) => b.startMs.compareTo(a.startMs));
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导入的行程')),
      );
      return;
    }
    final picked = await showModalBottomSheet<TripMeta>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '选择一次行程，导成赛道',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '取该行程的 GPS 轨迹作轮廓与起终点（闭合回路时起终点同点）。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final m in trips)
              ListTile(
                title: Text(
                  m.trackName.isNotEmpty ? m.trackName : '行程',
                ),
                subtitle: Text(
                  '${DateTime.fromMillisecondsSinceEpoch(m.startMs)}'
                  ' · ${(m.distanceM / 1000).toStringAsFixed(1)} km'
                  '${m.isTrackMode ? ' · 赛道模式' : ''}',
                ),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final trip = await widget.loadTrip(picked.id);
    if (!mounted) return;
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程文件读取失败，请重试')),
      );
      return;
    }
    final pkg = packageFromTrip(trip);
    if (pkg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('轨迹点不足（需至少 10 点），无法导入')),
      );
      return;
    }
    // 目标：新建我的赛道，或更新到现有官方包（成为本地改动）。
    final snap = _snap;
    final target = await showDialog<TrackPackage?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('导入到哪里？'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('新建我的赛道'),
          ),
          if (snap != null)
            for (final p in snap.official)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text('更新到「${p.nameCn}」（成为本地改动）'),
              ),
        ],
      ),
    );
    if (!mounted) return;
    if (target == null) {
      await _service.savePackage(pkg);
      await _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入我的赛道「${pkg.nameCn}」')),
      );
      return;
    }
    final updated = target.copyWith(
      centerline: pkg.centerline,
      start: pkg.start,
      finish: pkg.finish,
      lengthM: pkg.lengthM,
      verification: TrackPackageVerification.pending,
      verificationNote: '用户行程导入更新，待核对',
    );
    await _service.savePackage(updated);
    await _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已用行程更新「${target.nameCn}」（本地改动，远端不覆盖）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final check = _check;
    final updatesById = {
      for (final u in check?.updates ?? const <PackageUpdate>[]) u.id: u,
    };
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('赛道库'),
        backgroundColor: const Color(0xFF121212),
      ),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // 顶部：数据总版本 + 检查更新。
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _onVersionTap,
                        child: Text(
                          '赛道库数据 v${snap.dataVersion}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$kOsmAttribution；OSM 数据遵循 ODbL，署名见本页。',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _checking ? null : _checkUpdates,
                            child: Text(_checking ? '检查中…' : '检查更新'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _importFromTrip,
                            child: const Text('从行程导入'),
                          ),
                        ],
                      ),
                      if (check != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          check.message,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        if (check.skippedUserModified.isNotEmpty)
                          Text(
                            '${check.skippedUserModified.length} 个包因本地改动未列入更新（远端不覆盖本地改动）',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        if (check.updates.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _applying ? null : _applyAll,
                              child: const Text('全部更新'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (check != null && check.updates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '可更新的包',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final u in check.updates)
                    _updateRow(u),
                ],
                const SizedBox(height: 20),
                const Text(
                  '官方赛道包',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                for (final p in snap.official)
                  _packageRow(
                    p,
                    update: updatesById[p.id],
                    canReset: snap.overrideIds.contains(p.id),
                    isUser: false,
                  ),
                const SizedBox(height: 20),
                const Text(
                  '我的赛道',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                if (snap.userTracks.isEmpty)
                  const Text(
                    '暂无我的赛道：用“从行程导入”把一次实测行程导成赛道，或在编辑器里新建。',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  )
                else
                  for (final p in snap.userTracks)
                    _packageRow(p, isUser: true),
                if (_curation) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1A00),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '策展模式',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '发布流（当前）：导出包 JSON → 提交到仓库 data/packages/ → '
                          '更新 data/tracks-manifest.json（dataVersion +1、包版本 +1）→ '
                          '用户在库页检查更新即收到。应用内直发仓库需 GitHub 凭证，暂未接入，'
                          '不得伪装已发布。',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _exportAll,
                              child: const Text('导出全部包'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _updateRow(PackageUpdate u) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: ListTile(
        title: Text(u.nameCn),
        subtitle: Text(
          u.isNew
              ? '远端新增包 v${u.remoteVersion}'
              : '本地 v${u.localVersion} → 远端 v${u.remoteVersion}',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: TextButton(
          onPressed: _applying ? null : () => _applyOne(u),
          child: const Text('更新'),
        ),
      ),
    );
  }

  Widget _packageRow(
    TrackPackage p, {
    PackageUpdate? update,
    bool canReset = false,
    required bool isUser,
  }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.nameCn,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _badge('v${p.version}'),
                const SizedBox(width: 6),
                _badge('${p.sourceLabel} · ${p.verificationLabel}'),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (p.nameEn.isNotEmpty) p.nameEn,
                if (p.region.isNotEmpty) p.region,
                p.lengthLabel,
                if (p.userModified) '本地改动',
              ].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            if (update != null)
              Text(
                update.isNew
                    ? '可更新：远端新增包 v${update.remoteVersion}'
                    : '可更新：v${update.localVersion} → v${update.remoteVersion}',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                if (update != null)
                  TextButton(
                    onPressed: _applying ? null : () => _applyOne(update),
                    child: const Text('更新'),
                  ),
                TextButton(
                  onPressed: () => _edit(p),
                  child: const Text('编辑'),
                ),
                TextButton(
                  onPressed: () => _export(p),
                  child: const Text('导出'),
                ),
                if (isUser)
                  TextButton(
                    onPressed: () => _deleteUserTrack(p),
                    child: const Text(
                      '删除',
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else if (canReset)
                  TextButton(
                    onPressed: () => _resetOverride(p),
                    child: const Text('恢复默认'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}
