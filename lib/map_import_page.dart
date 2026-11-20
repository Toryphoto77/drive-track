import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';

import 'import_style.dart';

/// 地图资源导入子页 UI（v0.1.4 外壳 UI 分工）。
///
/// 支持的三种导入（只认这三种，其余一律明确报错、不谎称已导入）：
/// 1. 离线瓦片包：zip 内按 z/x/y.png 结构放瓦片；
/// 2. 轨迹叠加层：GeoJSON 或 KML 文件；
/// 3. 自定义底图样式：JSON 文件（样式描述，非瓦片本身）。
///
/// 不支持的专有地图格式（明确报错，不导入）：.mbtiles、.shp、
/// .gdb、.kml 以外的厂商私有格式、高德 / 百度 / 谷歌的私有离线包、
/// 加密 zip、需要在线密钥的样式。页内与错误提示里都明说这一点。
///
/// 实现状态划分（回执里同样写清，总协调接线时不要把占位当已实现）：
/// - 已实现（纯 Dart，不依赖原生）：四种格式校验函数
///   [validateTileZipEntries] / [validateGeoJsonText] /
///   [validateKmlText] / [validateStyleJsonText]（返回 null = 通过，
///   返回字符串 = 错误原因，绝不抛异常）；已导入列表的启用 / 停用 /
///   删除（本页内部状态，即时回显）。
/// - UI 已实现、逻辑占位：文件选择与真正解包 / 解析 / 落盘 / 地图渲染。
///   本页不直接调文件选择器（现有 Native.pickFile 只支持 'font' /
///   'image' 两种 kind，zip / json / geojson 不在其列），而是走回调
///   [onRequestImport] / [onPickFile]，回调未传或返回 null 时只提示
///   “待总协调接线”，绝不伪造“导入成功”。
/// - 留给总协调：原生文件选择（zip / geojson / kml / json）、zip 解包
///   与 z/x/y 校验落盘、GeoJSON/KML 解析成地图叠加层、样式 JSON 应用
///   到地图层、已导入资源的持久化与 App 重启后恢复、地图层读取启用态。

/// 导入资源种类。
enum MapImportKind { tileZip, geojson, kml, styleJson }

extension MapImportKindLabel on MapImportKind {
  String label(S s) => switch (this) {
        MapImportKind.tileZip => s.t('离线瓦片包（zip）', 'Offline tile package (zip)'),
        MapImportKind.geojson => s.t('GeoJSON 叠加层', 'GeoJSON overlay'),
        MapImportKind.kml => s.t('KML 叠加层', 'KML overlay'),
        MapImportKind.styleJson =>
          s.t('自定义底图样式（JSON）', 'Custom basemap style (JSON)'),
      };
  String hint(S s) => switch (this) {
        MapImportKind.tileZip => s.t(
            'zip 内须为 z/x/y.png 结构，如 16/35234/21567.png',
            'The zip must use a z/x/y.png layout, e.g. 16/35234/21567.png'),
        MapImportKind.geojson => s.t(
            '须为 FeatureCollection 或 Feature 的 GeoJSON',
            'Must be GeoJSON with type FeatureCollection or Feature'),
        MapImportKind.kml => s.t(
            '须为 <kml> 文档，含 Placemark 或 Document',
            'Must be a <kml> document containing Placemark or Document'),
        MapImportKind.styleJson => s.t(
            '须为 JSON 对象，含 sources 或 layers 之一',
            'Must be a JSON object containing sources or layers'),
      };
}

/// 一条已导入资源（本页列表用；持久化格式由总协调定，见文末）。
class ImportedMapResource {
  final String id;
  final String name;
  final MapImportKind kind;
  final bool enabled;
  final int? sizeBytes;

  const ImportedMapResource({
    required this.id,
    required this.name,
    required this.kind,
    this.enabled = true,
    this.sizeBytes,
  });

  ImportedMapResource copyWith({bool? enabled}) => ImportedMapResource(
        id: id,
        name: name,
        kind: kind,
        enabled: enabled ?? this.enabled,
        sizeBytes: sizeBytes,
      );
}

/// 导入请求结果（总协调回调返回用；ok=false 时必须给 reason）。
class MapImportResult {
  final bool ok;
  final ImportedMapResource? resource;
  final String? reason;
  const MapImportResult.ok(this.resource)
      : ok = true,
        reason = null;
  const MapImportResult.fail(this.reason)
      : ok = false,
        resource = null;
}

// ------------------------------------------------------------------
// 格式校验（已实现，纯 Dart；返回 null = 通过，否则为错误原因）
// ------------------------------------------------------------------

/// 离线瓦片包结构校验：入参为 zip 内条目名列表（总协调解包时传入）。
/// 规则：至少 1 个条目；每个瓦片条目须匹配 z/x/y.png（z 0–22 的整数，
/// x/y 为整数）；允许夹带 README / LICENSE 等非瓦片文件，但瓦片条目
/// 全不合规则时报错；非 .png 瓦片（如 .jpg 瓦片）明确报错。
String? validateTileZipEntries(List<String> entries) {
  final s = S.current;
  if (entries.isEmpty) {
    return s.t('zip 为空，没有任何文件', 'The zip is empty; it contains no files');
  }
  final tileRe = RegExp(r'^\d{1,2}/\d+/\d+\.png$');
  final badTile = <String>[];
  var tiles = 0;
  for (final e in entries) {
    if (e.endsWith('/')) continue;
    final base = e.split('/').last;
    if (base.toLowerCase().startsWith('readme') ||
        base.toLowerCase().startsWith('license')) {
      continue;
    }
    if (tileRe.hasMatch(e)) {
      final z = int.tryParse(e.split('/').first) ?? 99;
      if (z > 22) {
        badTile.add(e);
      } else {
        tiles++;
      }
    } else if (RegExp(r'\.(png|jpg|jpeg)$', caseSensitive: false).hasMatch(e)) {
      badTile.add(e);
    }
    // 其他非图片文件（如 .json 说明）不计入瓦片，也不报错。
  }
  if (tiles == 0) {
    return s.t('zip 内没有 z/x/y.png 结构的瓦片，如 16/35234/21567.png',
        'The zip has no z/x/y.png tiles, e.g. 16/35234/21567.png');
  }
  if (badTile.isNotEmpty) {
    return s.t(
        '有 ${badTile.length} 个瓦片路径不符合 z/x/y.png 或层级超过 22，'
            '如 ${badTile.first}',
        '${badTile.length} tile paths are not z/x/y.png or exceed zoom 22, '
            'e.g. ${badTile.first}');
  }
  return null;
}

/// GeoJSON 校验：须能解析为 JSON 对象，且 type 为 FeatureCollection
/// 或 Feature；坐标内容本身不由本函数校验（渲染层负责）。
String? validateGeoJsonText(String text) {
  final s = S.current;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      return s.t('GeoJSON 顶层须为 JSON 对象', 'GeoJSON top level must be a JSON object');
    }
    final type = j['type'] as String?;
    if (type != 'FeatureCollection' && type != 'Feature') {
      return s.t(
          'GeoJSON 的 type 须为 FeatureCollection 或 Feature，当前为 ${type ?? '缺失'}',
          'GeoJSON type must be FeatureCollection or Feature, got ${type ?? 'none'}');
    }
    return null;
  } catch (e) {
    return s.t('GeoJSON 解析失败：$e', 'Failed to parse GeoJSON: $e');
  }
}

/// KML 校验：文本须含 <kml 且含 Placemark 或 Document；不做完整 XML 解析。
String? validateKmlText(String text) {
  final s = S.current;
  if (!text.contains('<kml')) {
    return s.t('不是 KML 文件：缺少 <kml> 根元素',
        'Not a KML file: missing the <kml> root element');
  }
  if (!text.contains('<Placemark') && !text.contains('<Document')) {
    return s.t('KML 内没有 Placemark 或 Document，没有可叠加的内容',
        'KML has no Placemark or Document, so there is nothing to overlay');
  }
  return null;
}

/// 自定义底图样式 JSON 校验：须为 JSON 对象，且含 sources 或 layers 之一。
String? validateStyleJsonText(String text) {
  final s = S.current;
  try {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      return s.t('底图样式须为 JSON 对象', 'The basemap style must be a JSON object');
    }
    if (!j.containsKey('sources') && !j.containsKey('layers')) {
      return s.t('底图样式 JSON 须含 sources 或 layers 之一',
          'The basemap style JSON must contain sources or layers');
    }
    return null;
  } catch (e) {
    return s.t('底图样式 JSON 解析失败：$e', 'Failed to parse basemap style JSON: $e');
  }
}

/// 按文件名后缀判断是否支持：不支持的专有格式直接返回错误原因，
/// 调用方（总协调的文件选择回调里）应在导入前先调本函数。
String? checkSupportedExtension(String fileName) {
  final s = S.current;
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.zip')) return null;
  if (lower.endsWith('.geojson') || lower.endsWith('.json')) return null;
  if (lower.endsWith('.kml')) return null;
  if (lower.endsWith('.mbtiles') || lower.endsWith('.shp') || lower.endsWith('.gdb')) {
    return s.t('不支持 $fileName：专有地图格式（.mbtiles / .shp / .gdb）未导入',
        'Unsupported $fileName: proprietary map formats (.mbtiles / .shp / .gdb) are not imported');
  }
  return s.t(
      '不支持的文件类型：$fileName（仅支持 .zip 瓦片包、.geojson / .kml 叠加层、.json 底图样式）',
      'Unsupported file type: $fileName (only .zip tile packages, .geojson / .kml overlays and .json basemap styles)');
}

/// 地图资源导入子页。
///
/// [initialResources] 为已导入列表（总协调从持久化读出后传入；不传
/// 时为空列表）；[onRequestImport] 为真正的导入回调（总协调接原生
/// 文件选择 + 解包 + 校验 + 落盘后返回结果）；[onToggle] / [onDelete]
/// 为启用 / 删除的持久化回调（不传时只改本页内部状态并提示未接线）。
class MapImportPage extends StatefulWidget {
  final List<ImportedMapResource> initialResources;
  final Future<MapImportResult?> Function(MapImportKind kind)? onRequestImport;
  final ValueChanged<ImportedMapResource>? onToggle;
  final ValueChanged<ImportedMapResource>? onDelete;

  const MapImportPage({
    super.key,
    this.initialResources = const [],
    this.onRequestImport,
    this.onToggle,
    this.onDelete,
  });

  @override
  State<MapImportPage> createState() => _MapImportPageState();
}

class _MapImportPageState extends State<MapImportPage> {
  late List<ImportedMapResource> _resources = List.of(widget.initialResources);
  final Map<MapImportKind, String?> _errors = {};
  bool _busyKind = false;

  void _show(String msg) {
    if (!mounted) return;
    showAppNotice(context, msg, appNoticeKindFromMessage(msg));
  }

  Future<void> _import(MapImportKind kind) async {
    if (_busyKind) return;
    final s = S.of(context);
    if (widget.onRequestImport == null) {
      // 占位：没有总协调回调时绝不伪造成功。
      setState(() => _errors[kind] = s.t('本页暂不导入任何文件。',
          'This page does not import any files yet.'));
      return;
    }
    setState(() {
      _busyKind = true;
      _errors[kind] = null;
    });
    try {
      final result = await widget.onRequestImport!(kind);
      if (!mounted) return;
      if (result == null) {
        setState(() => _errors[kind] = s.t('已取消导入。', 'Import cancelled.'));
      } else if (result.ok && result.resource != null) {
        setState(() {
          _resources.add(result.resource!);
          _errors[kind] = null;
        });
        _show(s.t('已导入 ${result.resource!.name}',
            'Imported ${result.resource!.name}'));
      } else {
        setState(() => _errors[kind] = result.reason ??
            s.t('导入失败（未说明原因）。', 'Import failed (no reason given).'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errors[kind] = s.t(
            '导入失败：$e（未导入任何文件）',
            'Import failed: $e (no files were imported)'));
      }
    } finally {
      if (mounted) setState(() => _busyKind = false);
    }
  }

  // v1.0.2：只换 UI 为统一导入画风（ImportCard / 蓝色主按钮 /
  // ImportNotice）；导入回调、校验、白名单、存储逻辑一律未动。
  Widget _importCard(MapImportKind kind, S s) {
    return ImportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind.label(s),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(kind.hint(s),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          ImportFileRow(
            fileName: null,
            pickLabel: _busyKind
                ? s.t('导入中…', 'Importing…')
                : s.t('选择文件并导入', 'Choose a file and import'),
            onPick: _busyKind ? null : () => _import(kind),
          ),
          if (_errors[kind] != null) ...[
            const SizedBox(height: 8),
            ImportNotice(message: _errors[kind]!, kind: ImportNoticeKind.error),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(s.t('地图资源导入', 'Import map resources'))),
      body: ListView(
        padding: withAppBarTopInset(context, const EdgeInsets.only(bottom: 24)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              s.t(
                '导入离线瓦片包、轨迹叠加层与自定义底图样式。格式不对会报错且不导入；'
                '导入的资源只存本机。',
                'Import offline tile packages, track overlays and custom basemap styles. Invalid formats are rejected; imported resources stay on this device.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          _importCard(MapImportKind.tileZip, s),
          _importCard(MapImportKind.geojson, s),
          _importCard(MapImportKind.kml, s),
          _importCard(MapImportKind.styleJson, s),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(s.t('已导入资源', 'Imported resources'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          if (_resources.isEmpty)
            ImportCard(
              child: Text(
                  s.t('暂无已导入资源\n用上方卡片导入',
                      'No imported resources yet\nUse the cards above to import'),
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
            )
          else
            for (final r in _resources)
              ImportCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(r.name),
                  subtitle: Text('${r.kind.label(s)}${r.sizeBytes != null ? ' · ${(r.sizeBytes! / 1024).toStringAsFixed(0)} KB' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: r.enabled,
                        onChanged: (v) {
                          final next = r.copyWith(enabled: v);
                          setState(() {
                            final i = _resources.indexWhere((e) => e.id == r.id);
                            if (i >= 0) _resources[i] = next;
                          });
                          widget.onToggle?.call(next);
                          if (widget.onToggle == null) {
                            _show(s.t('启用状态已切换。', 'Enabled state toggled.'));
                          }
                        },
                      ),
                      Semantics(
                        label: s.t('删除', 'Delete'),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            setState(() => _resources.removeWhere((e) => e.id == r.id));
                            widget.onDelete?.call(r);
                            if (widget.onDelete == null) {
                              _show(s.t('已从列表删除。', 'Removed from the list.'));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------- 总协调接线（不执行，仅供参考） ----------
// 1) 原生文件选择：现有 Native.pickFile 只支持 'font' / 'image'，
//    zip / geojson / kml / json 需原生新增 kind 或另起选择通道，
//    选到文件后先调 checkSupportedExtension 挡掉专有格式。
// 2) onRequestImport(kind) 内：读文件 → 按种类调对应 validate* 函数
//    （瓦片 zip 先解包出条目名列表再调 validateTileZipEntries）→
//    校验通过才落盘（建议目录：filesDir/map_imports/<id>/），
//    失败返回 MapImportResult.fail(校验返回的错误原因)，不要抛异常
//    让页崩溃；成功返回 MapImportResult.ok(ImportedMapResource(...))。
// 3) 持久化：已导入列表建议存 filesDir/map_imports.json，字段至少
//    id / name / kind / enabled / sizeBytes；App 启动时读回并传给
//    MapImportPage(initialResources: ...)，地图层只渲染 enabled=true 的项。
// 4) 地图层渲染（refined_map.dart）：瓦片包按 z/x/y 读本地文件、
//    GeoJSON/KML 解析成叠加层、样式 JSON 应用到底图——三者都还没接，
//    本页目前不渲染任何导入内容，接线前不要对外称“已支持离线地图”。
