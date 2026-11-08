/// 赛道库页：数据包管理器，不是信息浏览器。
///
/// - 只列赛道数据包：每行显示赛道名、数据包版本、来源、更新状态，
///   附操作（检查更新 / 更新 / 删除 / 导出 / 编辑）。
/// - 本页不显示赛道图、历史、最快圈等任何浏览信息（浏览收进
///   选赛道列表的 ⓘ 简介页）。
/// - 顶部版本卡片显示赛道库数据总版本；每条包自带自己的版本；更新按条进行。
/// - 提交入口必须隐藏：连点当前版本文本 7 次才解锁策展模式，常规界面
///   绝不出现它；本轮策展模式含包导出，完整发布流（应用内直发仓库）
///   暂未接入，见策展区说明。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'track_library.dart';
import 'track_package_editor.dart';

/// 策展模式 gate（纯逻辑，可单测）：2 秒内连点版本文本 7 次解锁。
/// tap() 返回此次点击后是否达到解锁条件；页面负责在首次解锁时
/// 置策展态并提示（仅本页会话有效由页面生命周期保证）。
class VersionTapGate {
  int _tapCount = 0;
  DateTime? _lastTap;

  bool tap({DateTime? now}) {
    final at = now ?? DateTime.now();
    if (_lastTap != null && at.difference(_lastTap!).inSeconds < 2) {
      _tapCount++;
    } else {
      _tapCount = 1;
    }
    _lastTap = at;
    return _tapCount >= 7;
  }
}

/// 赛道库页。
/// 官方包搜索匹配（v1.5.2）：中文名 / 英文名 / 地区子串匹配，不区分
/// 大小写；空查询返回 true（不过滤）。纯函数，便于测试。
bool matchesTrackSearch(TrackPackage p, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return p.nameCn.toLowerCase().contains(q) ||
      p.nameEn.toLowerCase().contains(q) ||
      p.region.toLowerCase().contains(q);
}

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
  final _versionTapGate = VersionTapGate();

  // v1.5.2：官方赛道包搜索（标题行右侧放大镜展开）：只过滤官方包，
  // 我的赛道不参与；按中文名 / 英文名 / 地区子串匹配（不区分大小写）。
  bool _showSearch = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    if (_versionTapGate.tap() && !_curation) {
      setState(() => _curation = true);
      showAppNotice(context, '策展模式已解锁', AppNoticeKind.success);
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
    // 三种状态都走卡片状态行 + 顶部自动消失提示：
    // 失败 → error，已是最新 → success，有更新 → info；文案取
    // 服务返回的 message（与卡片状态行同一口径）。
    switch (result.status) {
      case UpdateCheckStatus.error:
        showAppNotice(context, result.message, AppNoticeKind.error);
      case UpdateCheckStatus.upToDate:
        showAppNotice(context, result.message, AppNoticeKind.success);
      case UpdateCheckStatus.available:
        showAppNotice(context, result.message, AppNoticeKind.info);
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
                    '用户改过的包不会被覆盖。',
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
          '共 ${updates.length} 个包。用户改过的包不会被覆盖。',
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
    showAppNotice(
      context,
      msg.toString(),
      result.skippedReasons.isEmpty
          ? AppNoticeKind.success
          : AppNoticeKind.warning,
    );
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
      showAppNotice(context, '导出失败：$e', AppNoticeKind.error);
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
      await File(path)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(doc));
      await Native.shareFiles([path], 'application/json', '赛道库全部数据包');
    } catch (e) {
      if (!mounted) return;
      showAppNotice(context, '导出失败：$e', AppNoticeKind.error);
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
        content: const Text('本地版本将被删除，回到默认版本。'),
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
      showAppNotice(context, '暂无可导入的行程：先去首页记录一次行程', AppNoticeKind.warning);
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
              '取该行程的 GPS 轨迹作轮廓与起终点。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final m in trips)
              ListTile(
                title: Text(m.trackName.isNotEmpty ? m.trackName : '行程'),
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
      showAppNotice(context, '行程文件读取失败，请重试', AppNoticeKind.error);
      return;
    }
    final pkg = packageFromTrip(trip);
    if (pkg == null) {
      showAppNotice(context, '轨迹点不足（需至少 10 点），无法导入', AppNoticeKind.warning);
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
      if (!mounted) return;
      showAppNotice(context, '已导入我的赛道「${pkg.nameCn}」', AppNoticeKind.success);
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
    if (!mounted) return;
    showAppNotice(
      context,
      '已用行程更新「${target.nameCn}」',
      AppNoticeKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final check = _check;
    final updatesById = {
      for (final u in check?.updates ?? const <PackageUpdate>[]) u.id: u,
    };
    // v1.5.2：官方包搜索过滤（snap 为空时给空列表，页面仍显示加载中）。
    final query = _searchQuery.trim().toLowerCase();
    final official = snap == null
        ? const <TrackPackage>[]
        : query.isEmpty
            ? snap.official
            : snap.official
                .where((p) => matchesTrackSearch(p, query))
                .toList();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: const Text('赛道库'),
      ),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
              children: [
                // 顶部：赛道库版本卡片（标题 + 当前版本 + 状态行 + 两个主按钮）。
                // 显示的全部是本 App 真实数据：版本取 manifest 的 dataVersion，
                // 状态与包数取真实检查结果。版本文本仍可点，策展 gate 不变。
                LibraryVersionCard(
                  dataVersion: snap.dataVersion,
                  check: check,
                  checking: _checking,
                  applying: _applying,
                  onVersionTap: _onVersionTap,
                  onCheck: _checkUpdates,
                  onUpdateAll: _applyAll,
                  onImport: _importFromTrip,
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
                  for (final u in check.updates) _updateRow(u),
                ],
                const SizedBox(height: 20),
                // v1.5.2：官方赛道包标题行右侧放放大镜，点按展开搜索框
                // （与 App 同款深色样式）；输入即按名称/英文名/地区过滤，
                // 只过滤官方包，我的赛道不参与。
                Row(children: [
                  const Text(
                    '官方赛道包',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                        _showSearch ? Icons.close : Icons.search,
                        color: Colors.white70),
                    tooltip: _showSearch ? '关闭搜索' : '搜索赛道',
                    onPressed: () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) {
                          _searchQuery = '';
                          _searchCtrl.clear();
                        }
                      });
                    },
                  ),
                ]),
                if (_showSearch) ...[
                  const SizedBox(height: 8),
                  _searchField(),
                ],
                const SizedBox(height: 8),
                if (_showSearch && query.isNotEmpty) ...[
                  Text(
                    official.isEmpty
                        ? '没有匹配“${_searchQuery.trim()}”的赛道'
                        : '找到 ${official.length} 条（共 ${snap.official.length} 条）',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final p in official)
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
                  for (final p in snap.userTracks) _packageRow(p, isUser: true),
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
                          '更新 data/tracks-manifest.json（dataVersion 升一档，如 V1.0.1 → V1.0.2；包版本 +1）→ '
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

  /// 官方包搜索框（v1.5.2）：与 App 同款深色样式——卡片底色 #1E1E1E、
  /// 圆角 12、白字、灰色提示；前缀放大镜，有输入时后缀清空钮。
  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: '搜索赛道名称 / 地区',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon:
                    const Icon(Icons.clear, color: Colors.white54, size: 18),
                tooltip: '清空',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
      ),
      onChanged: (v) => setState(() => _searchQuery = v),
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
                TextButton(onPressed: () => _edit(p), child: const Text('编辑')),
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

/// 顶部版本卡片（截图样式，纯渲染，不碰服务与磁盘，可直接 widget 测试）：
/// 标题“赛道库” + 当前版本（manifest dataVersion，原样显示）+
/// 状态行（绿点已是最新 / 橙点有更新 / 灰点未检查或失败）+
/// [赛道库版本检测]（描边）与 [更新赛道库]（实心，有更新时可用）+
/// [从行程导入]（原样保留）。
class LibraryVersionCard extends StatelessWidget {
  final String dataVersion;
  final UpdateCheckResult? check;
  final bool checking;
  final bool applying;
  final VoidCallback onVersionTap;
  final VoidCallback onCheck;
  final VoidCallback onUpdateAll;
  final VoidCallback onImport;

  const LibraryVersionCard({
    super.key,
    required this.dataVersion,
    required this.check,
    required this.checking,
    required this.applying,
    required this.onVersionTap,
    required this.onCheck,
    required this.onUpdateAll,
    required this.onImport,
  });

  /// 状态行文案（三态：未检查 / 已是最新 / 有更新；检查失败时显示
  /// 错误信息原文）。
  String get statusText {
    if (checking) return '正在检测…';
    final c = check;
    if (c == null) return '尚未检测';
    switch (c.status) {
      case UpdateCheckStatus.upToDate:
        return '赛道库已是最新版本';
      case UpdateCheckStatus.available:
        return '${c.updates.length} 个包可更新';
      case UpdateCheckStatus.error:
        return c.message;
    }
  }

  /// 状态行圆点颜色：已是最新为绿、有更新为橙、其余为灰。
  Color get statusDotColor {
    final c = check;
    if (!checking && c != null) {
      switch (c.status) {
        case UpdateCheckStatus.upToDate:
          return Colors.green;
        case UpdateCheckStatus.available:
          return Colors.orange;
        case UpdateCheckStatus.error:
          return Colors.white54;
      }
    }
    return Colors.white54;
  }

  /// [更新赛道库] 按钮可用条件：检查出可更新包且不在检测/更新中。
  bool get updateButtonEnabled {
    final c = check;
    return !checking &&
        !applying &&
        c != null &&
        c.status == UpdateCheckStatus.available &&
        c.updates.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final c = check;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.map_outlined, color: Colors.white70, size: 22),
              SizedBox(width: 8),
              Text(
                '赛道库',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onVersionTap,
            child: Text(
              '当前版本：$dataVersion',
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusDotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          if (c != null && c.skippedUserModified.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${c.skippedUserModified.length} 个包因本地改动未列入更新',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: checking ? null : onCheck,
              child: Text(checking ? '检测中…' : '赛道库版本检测'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: updateButtonEnabled ? onUpdateAll : null,
              child: Text(applying ? '更新中…' : '更新赛道库'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onImport, child: const Text('从行程导入')),
          const SizedBox(height: 8),
          Text(
            '$kOsmAttribution；OSM 数据遵循 ODbL，署名见本页。',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
