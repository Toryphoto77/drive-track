import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'glass_button.dart';
import 'import_style.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'track_library.dart';
import 'track_timing.dart';

/// 数据导出 / 备份页（v0.1.5：侧拉菜单“数据导出/备份”的落点）。
///
/// 不是重复页：此前导出只在单个行程详情页里（分享 GPX/CSV），
/// 没有一个集中导出入口。本页只复用 Store 已有的 toGpx/toCsv
/// 与 Native.shareFiles（系统分享），不另写导出格式：
/// - GPX 默认按隐私开关截掉首尾（与详情页一致）；
/// - CSV 为完整数据（与详情页一致，页内有提示）。
/// “备份”即把文件经系统分享发出去保存，本机不设云备份，
/// 不宣称有云端备份。
///
/// v1.0.0 新增“设置备份”区（顶部，行程为空时也显示）：
/// - 导出：把 filesDir 下已存在的设置文件读出，打包成一个 JSON
///   （{"format":"drivetrack-settings-backup-v1","files":{文件名: 内容字符串}}），
///   写到 cacheDir 后经 Native.shareFiles 分享出去，用户自行存到
///   微信 / 网盘 / 文件里；不上传任何服务器。
/// - 恢复：用 Native.pickFile('file') 让用户选之前导出的备份 JSON，
///   解析后把其中每个文件写回 filesDir，只写白名单里的 5 个文件名，
///   拒绝其他文件名、拒绝非 JSON 备份、拒绝内容不是合法 JSON 的条目。
///   成功后提示已恢复几个文件并提示“重启 App 后生效”（AppPrefs 只在
///   启动时加载一次）。
/// - 已知缺口（页面文案与回执均如实写明，不宣称备份包含全部状态）：
///   传感器校准的零偏是运行时内存值、未持久化，备份里没有它，
///   重装后需重新校零。
/// - pickFile 通道说明：原生侧对非图片 kind 会把所选文件先拷贝到
///   filesDir/custom_font.ttf 再返回该路径（见 MainActivity），恢复时
///   Dart 侧读完该临时拷贝后即删掉它，不留一个 JSON 内容顶着 .ttf
///   名的文件；但若用户此前确有一个自定义字体文件正在该路径，原生
///   拷贝一步本身就会先覆盖它——这是复用现有通道的已知代价，恢复
///   前请确认没有正在用的自定义字体文件在该路径。
class DataExportPage extends StatefulWidget {
  final Store store;

  const DataExportPage({super.key, required this.store});

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

/// 设置备份格式标识；恢复时必须精确匹配，否则拒绝。
const _settingsBackupFormat = 'drivetrack-settings-backup-v1';

/// 设置备份白名单：只导出、只写回这 5 个文件。id.json 若不存在则跳过。
const _settingsBackupFiles = [
  'profile.json',
  'track_settings.json',
  'voice_settings.json',
  'favorites.json',
  'id.json',
];

class _DataExportPageState extends State<DataExportPage> {
  List<TripMeta> _metas = [];
  bool _loading = true;
  String? _busyId;
  bool _settingsBusy = false;
  String? _settingsMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.store.init();
    final metas = await widget.store.loadIndex();
    if (mounted) {
      setState(() {
        _metas = metas;
        _loading = false;
      });
    }
  }

  Future<void> _export(TripMeta meta, String kind) async {
    setState(() => _busyId = '${meta.id}:$kind');
    try {
      final trip = await widget.store.loadTrip(meta.id);
      if (trip == null) return;
      final dir = await widget.store.cacheDir();
      // v1.2.18：赛道包只查一次，GPX 航点与 CSV 分段门控共用。
      // 注：TrackPackage 无 startFinish 字段，起终线取 pkg.start
      //（与计时接线 _buildLapTimer 同口径），缺失时回落 pkg.finish。
      GeoPoint? startFinish;
      var sectorPoints = const <GeoPoint>[];
      bool? hasSectorPoints;
      final trackId = trip.trackId;
      if (trip.isTrackMode && trackId != null && trackId.isNotEmpty) {
        final pkg = (await TrackLibraryService.instance.loadAll())
            .packageById(trackId);
        if (pkg != null) {
          hasSectorPoints = pkg.hasSectors;
          if (pkg.hasSectors || pkg.start != null || pkg.finish != null) {
            startFinish = pkg.start ?? pkg.finish;
            sectorPoints = pkg.sectorPoints;
          }
        }
      }
      if (kind == 'gpx') {
        final path = '$dir/trip_${trip.id}.gpx';
        // 赛道行程且赛道包有起终点/分段点时，GPX 加分段航点（写在
        // <trk> 之前）；查不到包或包无分段点时不传参数（老行为不变）。
        await File(path).writeAsString(widget.store.toGpx(trip,
            trimmed: trip.trimPrivacy,
            startFinish: startFinish,
            sectorPoints: sectorPoints));
        await Native.shareFiles([path], 'application/gpx+xml', '驰迹 GPX（${trip.trimPrivacy ? '已截掉首尾' : '完整轨迹'}）');
      } else {
        final path = '$dir/trip_${trip.id}.csv';
        await File(path).writeAsString(widget.store.toCsv(trip,
            trimmed: false, hasSectorPoints: hasSectorPoints));
        await Native.shareFiles([path], 'text/csv', '驰迹 CSV（完整数据）');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _exportSettingsBackup() async {
    setState(() {
      _settingsBusy = true;
      _settingsMsg = null;
    });
    try {
      final dir = await Native.getFilesDir();
      final files = <String, String>{};
      for (final name in _settingsBackupFiles) {
        final f = File('$dir/$name');
        if (await f.exists()) {
          files[name] = await f.readAsString();
        }
      }
      if (files.isEmpty) {
        setState(() => _settingsMsg = '本机暂无可备份的设置文件。');
        return;
      }
      final cache = await widget.store.cacheDir();
      final path = '$cache/drivetrack-settings-backup.json';
      await File(path).writeAsString(jsonEncode({
        'format': _settingsBackupFormat,
        'files': files,
      }));
      await Native.shareFiles([path], 'application/json', '驰迹设置备份');
      setState(() => _settingsMsg =
          '已导出 ${files.length} 个设置文件，请存到微信 / 网盘 / 文件里。');
    } catch (_) {
      setState(() => _settingsMsg = '导出失败，请重试。');
    } finally {
      if (mounted) setState(() => _settingsBusy = false);
    }
  }

  Future<void> _restoreSettingsBackup() async {
    setState(() {
      _settingsBusy = true;
      _settingsMsg = null;
    });
    try {
      final picked = await Native.pickFile('file');
      if (picked == null) {
        setState(() => _settingsMsg = '已取消选择。');
        return;
      }
      final raw = await File(picked).readAsString();
      // 读完即删临时拷贝：原生侧把所选文件拷到了 filesDir/custom_font.ttf，
      // 不删会留一个 JSON 内容顶着 .ttf 名的文件；见文件头通道说明。
      if (picked.split('/').last == 'custom_font.ttf') {
        try {
          await File(picked).delete();
        } catch (_) {}
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _settingsBackupFormat ||
          decoded['files'] is! Map) {
        setState(() => _settingsMsg = '不是有效的驰迹设置备份文件，未恢复任何设置。');
        return;
      }
      final dir = await Native.getFilesDir();
      var restored = 0;
      for (final entry in (decoded['files'] as Map).entries) {
        final name = entry.key.toString();
        // 白名单外文件名一律拒绝，不写回。
        if (!_settingsBackupFiles.contains(name)) continue;
        final content = entry.value;
        if (content is! String) continue;
        // 内容必须是合法 JSON，否则跳过该条，不写坏文件。
        try {
          jsonDecode(content);
        } catch (_) {
          continue;
        }
        await File('$dir/$name').writeAsString(content);
        restored++;
      }
      setState(() => _settingsMsg = restored > 0
          ? '已恢复 $restored 个设置文件，重启 App 后生效。传感器校准零偏不在备份里，重装后需重新校零。'
          : '备份里没有可恢复的设置文件，未恢复任何设置。');
    } catch (_) {
      setState(() => _settingsMsg = '恢复失败：文件无法读取或不是有效的备份 JSON，未恢复任何设置。');
    } finally {
      if (mounted) setState(() => _settingsBusy = false);
    }
  }

  // v1.0.2：只换 UI 为统一导入画风（ImportCard / 蓝色主按钮 /
  // ImportNotice）；导出、恢复、白名单、备份格式一律未动。
  Widget _settingsBackupSection() {
    return ImportCard(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('设置备份', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            '备份本机设置文件，经系统分享存到微信 / 网盘 / 文件里，不上传服务器。'
            '恢复后需重启 App 才生效。传感器校准零偏不在备份里，重装后需重新校零。',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ImportFileRow(
            fileName: null,
            placeholder: '未选择备份文件',
            pickLabel: _settingsBusy ? '处理中…' : '恢复设置备份',
            onPick: _settingsBusy ? null : _restoreSettingsBackup,
          ),
          const SizedBox(height: 8),
          ImportPrimaryButton(
            label: _settingsBusy ? '导出中…' : '导出设置备份',
            icon: Icons.ios_share,
            onPressed: _settingsBusy ? null : _exportSettingsBackup,
          ),
          if (_settingsMsg != null) ...[
            const SizedBox(height: 8),
            ImportNotice(
              message: _settingsMsg!,
              kind: ImportNotice.kindFromMessage(_settingsMsg!),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('数据导出 / 备份'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _settingsBackupSection(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '导出走系统分享，数据仅存本机，不上传。GPX 默认截掉首尾；CSV 为完整数据，请注意隐私。',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                if (_metas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无行程可导出\n先去首页开始一次记录'),
                  )
                else
                  for (final m in _metas)
                    ImportCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${m.mode.label} · ${(m.distanceM / 1000).toStringAsFixed(2)} km'),
                        subtitle: Text(DateTime.fromMillisecondsSinceEpoch(m.startMs).toString().substring(0, 16)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _busyId == '${m.id}:gpx' ? null : () => _export(m, 'gpx'),
                              child: const Text('GPX'),
                            ),
                            TextButton(
                              onPressed: _busyId == '${m.id}:csv' ? null : () => _export(m, 'csv'),
                              child: const Text('CSV'),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
