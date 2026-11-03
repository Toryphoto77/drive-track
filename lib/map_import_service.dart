import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'native.dart';

/// 地图资源导入逻辑（v0.1.4 新增文件，纯 Dart，不新增 pub 插件）。
///
/// 支持的格式（其余一律报 unsupported_format，不静默跳过）：
/// - 离线瓦片包：.zip，内含 z/x/y.png 结构（见 [_validateTileEntry]）。
/// - 轨迹叠加层：.geojson（LineString / MultiLineString）与 .kml
///  （LineString 的 <coordinates>，MultiGeometry 内多个 LineString 也接受）。
/// - 自定义底图样式：.json，键与值见 [_styleColorKeys] / [_styleNumberKeys]。
/// 明确不支持（报 unsupported_format，不尝试解包）：.mbtiles、.shp、
/// .kmz（压缩过的 KML 不代解）、.gdb、.tab、.tif/.tiff 等专有/栅格格式。
/// KML 解析用正则抽取 LineString 坐标，不是完整 XML 解析器：
/// 严重畸形的 XML、带命名空间前缀变体的非标准写法可能解析失败，
/// 此时报 invalid_kml，调用方如实提示用户，不要宣称“已支持全部 KML”。

/// 导入失败。调用方按 [code] 给用户可读提示，不要把原始异常堆栈贴给用户。
class MapImportException implements Exception {
  /// invalid_zip / not_png / empty_package / too_large /
  /// invalid_geojson / invalid_kml / invalid_style /
  /// unsupported_format / io_error
  final String code;
  final String message;
  const MapImportException(this.code, this.message);
  @override
  String toString() => 'MapImportException($code): $message';
}

/// 已导入资源的一条记录（本机 map_imports.json 索引 + 文件）。
class ImportedMapResource {
  /// kind: 'tiles'（离线瓦片包）/ 'overlay'（轨迹叠加层）/ 'style'（底图样式）。
  final String id;
  final String name;
  final String kind;

  /// overlay 时为 'geojson' / 'kml'；tiles 时为 'zip'；style 时为 'style'。
  final String format;

  /// tiles: 瓦片根目录；overlay/style: 本机文件路径。
  final String path;

  /// 是否启用。停用只改索引标志，不删文件；底图/叠加层渲染时跳过停用项。
  final bool enabled;

  final int? minZoom;
  final int? maxZoom;
  final int? tileCount;
  final int? featureCount;
  final int importedAtMs;

  const ImportedMapResource({
    required this.id,
    required this.name,
    required this.kind,
    required this.format,
    required this.path,
    required this.enabled,
    this.minZoom,
    this.maxZoom,
    this.tileCount,
    this.featureCount,
    required this.importedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'format': format,
        'path': path,
        'enabled': enabled,
        if (minZoom != null) 'minZoom': minZoom,
        if (maxZoom != null) 'maxZoom': maxZoom,
        if (tileCount != null) 'tileCount': tileCount,
        if (featureCount != null) 'featureCount': featureCount,
        'importedAt': importedAtMs,
      };

  static ImportedMapResource fromJson(Map<String, dynamic> j) =>
      ImportedMapResource(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? j['id'] as String,
        kind: (j['kind'] as String?) ?? 'overlay',
        format: (j['format'] as String?) ?? '',
        path: (j['path'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
        minZoom: (j['minZoom'] as num?)?.toInt(),
        maxZoom: (j['maxZoom'] as num?)?.toInt(),
        tileCount: (j['tileCount'] as num?)?.toInt(),
        featureCount: (j['featureCount'] as num?)?.toInt(),
        importedAtMs: (j['importedAt'] as num?)?.toInt() ?? 0,
      );

  /// 交给底图/地图组件的源描述。tiles 由调用方按 [MapImportService.tilePathFor]
  /// 取文件；overlay/style 由调用方读 [path] 的文件内容。
  Map<String, dynamic> get sourceDescription => {
        'id': id,
        'name': name,
        'kind': kind,
        'format': format,
        'path': path,
        'enabled': enabled,
        if (minZoom != null) 'minZoom': minZoom,
        if (maxZoom != null) 'maxZoom': maxZoom,
      };
}

class MapImportService {
  MapImportService._();
  static final MapImportService instance = MapImportService._();

  static const String indexFileName = 'map_imports.json';
  static const String importsDirName = 'map_imports';

  /// 安全上限：防 zip 炸弹与无意义大包。超限报 too_large，不写盘。
  static const int maxTileEntries = 20000;
  static const int maxTotalUncompressedBytes = 512 * 1024 * 1024;
  static const int maxSingleFileBytes = 32 * 1024 * 1024;

  static const List<String> supportedExtensions = [
    '.zip',
    '.geojson',
    '.kml',
    '.json',
  ];

  Future<Directory> _importsDir() async {
    final dir = await Native.getFilesDir();
    final d = Directory('$dir/$importsDirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<ImportedMapResource>> listResources() async {
    try {
      final dir = await Native.getFilesDir();
      final f = File('$dir/$indexFileName');
      if (!await f.exists()) return const [];
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => ImportedMapResource.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveIndex(List<ImportedMapResource> list) async {
    final dir = await Native.getFilesDir();
    await File('$dir/$indexFileName')
        .writeAsString(jsonEncode(list.map((r) => r.toJson()).toList()));
  }

  Future<ImportedMapResource> _addToIndex(ImportedMapResource r) async {
    final list = await listResources();
    list.insert(0, r);
    await _saveIndex(list);
    return r;
  }

  /// 启用 / 停用：只改索引标志，不动文件。渲染方必须跳过 enabled=false 的项。
  Future<void> setEnabled(String id, bool enabled) async {
    final list = await listResources();
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) {
      throw const MapImportException('io_error', '找不到该导入资源');
    }
    final old = list[i];
    list[i] = ImportedMapResource(
      id: old.id,
      name: old.name,
      kind: old.kind,
      format: old.format,
      path: old.path,
      enabled: enabled,
      minZoom: old.minZoom,
      maxZoom: old.maxZoom,
      tileCount: old.tileCount,
      featureCount: old.featureCount,
      importedAtMs: old.importedAtMs,
    );
    await _saveIndex(list);
  }

  /// 删除：文件级操作——删瓦片目录或叠加层/样式文件，并从索引移除。
  /// 失败时报 io_error，索引不动（不要删索引留孤文件，也不要删文件留孤索引）。
  Future<void> deleteResource(String id) async {
    final list = await listResources();
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) {
      throw const MapImportException('io_error', '找不到该导入资源');
    }
    final target = list[i];
    try {
      final type = await FileSystemEntity.type(target.path);
      if (type == FileSystemEntityType.directory) {
        await Directory(target.path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(target.path).delete();
      }
    } catch (e) {
      throw MapImportException('io_error', '删除文件失败：$e');
    }
    list.removeAt(i);
    await _saveIndex(list);
  }

  /// 按后缀分发导入。displayName 为空时用文件名。
  /// .json 按内容嗅探：含 GeoJSON 标记走轨迹层，否则按样式校验
  /// （样式键都不含、又不是 GeoJSON 时报 invalid_style，不猜）。
  Future<ImportedMapResource> importFile(File file,
      {String? displayName}) async {
    if (!await file.exists()) {
      throw const MapImportException('io_error', '文件不存在');
    }
    final name = displayName ??
        file.path.split(Platform.pathSeparator).last;
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.zip')) {
      return _importTileZip(file, name);
    }
    if (lower.endsWith('.geojson')) {
      return _importGeoJsonText(await file.readAsString(), name, 'geojson');
    }
    if (lower.endsWith('.kml')) {
      return _importKmlText(await file.readAsString(), name);
    }
    if (lower.endsWith('.json')) {
      final text = await file.readAsString();
      final decoded = _tryDecodeJson(text);
      if (decoded is Map<String, dynamic> && _looksLikeGeoJson(decoded)) {
        return _importGeoJsonText(text, name, 'geojson');
      }
      // 其余 .json 一律按样式校验：非法键/非法值报 invalid_style。
      return _importStyleText(text, name);
    }
    throw MapImportException('unsupported_format',
        '不支持的格式：仅支持离线瓦片包 .zip、轨迹 .geojson / .kml、底图样式 .json；'
        '不支持 .mbtiles、.shp、.kmz、.gdb 等专有地图格式');
  }

  // ---------------- 离线瓦片包 ----------------

  Future<ImportedMapResource> _importTileZip(File file, String name) async {
    final bytes = await file.readAsBytes();
    final tiles = _parseTileZip(bytes); // 校验不过直接抛错，不写盘
    final root = await _importsDir();
    final id = 'imp_${DateTime.now().millisecondsSinceEpoch}';
    final outDir = Directory('${root.path}/tiles_$id');
    await outDir.create(recursive: true);
    try {
      for (final t in tiles) {
        final f = File('${outDir.path}/${t.path}');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(t.pngBytes);
      }
    } catch (e) {
      // 写盘中途失败：清掉半成品目录，不留坏包。
      try {
        await outDir.delete(recursive: true);
      } catch (_) {}
      throw MapImportException('io_error', '写入瓦片失败：$e');
    }
    var minZ = 99, maxZ = -1;
    for (final t in tiles) {
      if (t.z < minZ) minZ = t.z;
      if (t.z > maxZ) maxZ = t.z;
    }
    return _addToIndex(ImportedMapResource(
      id: id,
      name: name,
      kind: 'tiles',
      format: 'zip',
      path: outDir.path,
      enabled: true,
      minZoom: minZ,
      maxZoom: maxZ,
      tileCount: tiles.length,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---------------- GeoJSON / KML 轨迹层 ----------------

  Future<ImportedMapResource> _importGeoJsonText(
      String text, String name, String format) async {
    final decoded = _tryDecodeJson(text);
    if (decoded == null) {
      throw const MapImportException('invalid_geojson', '不是合法 JSON');
    }
    final lines = _extractGeoJsonLines(decoded);
    return _storeOverlay(
        name: name, format: format, lines: lines, sourceText: text);
  }

  Future<ImportedMapResource> _importKmlText(String text, String name) async {
    final lines = _extractKmlLines(text);
    if (lines.isEmpty) {
      throw const MapImportException(
          'invalid_kml', '未找到 LineString 轨迹：KML 里没有可用的线坐标');
    }
    // 统一存为 GeoJSON 文本，叠加层渲染方只需读一种格式。
    final geo = {
      'type': 'FeatureCollection',
      'features': [
        for (final line in lines)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': line
                  .map((p) => [p.$1, p.$2])
                  .toList(),
            },
          },
      ],
    };
    return _storeOverlay(
        name: name, format: 'kml', lines: lines, sourceText: jsonEncode(geo));
  }

  Future<ImportedMapResource> _storeOverlay({
    required String name,
    required String format,
    required List<List<(double, double)>> lines,
    required String sourceText,
  }) async {
    final root = await _importsDir();
    final id = 'imp_${DateTime.now().millisecondsSinceEpoch}';
    final out = File('${root.path}/overlay_$id.geojson');
    await out.writeAsString(sourceText);
    final featureCount = lines.length;
    return _addToIndex(ImportedMapResource(
      id: id,
      name: name,
      kind: 'overlay',
      format: format,
      path: out.path,
      enabled: true,
      featureCount: featureCount,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---------------- 底图样式 ----------------

  Future<ImportedMapResource> _importStyleText(
      String text, String name) async {
    final decoded = _tryDecodeJson(text);
    if (decoded is! Map<String, dynamic>) {
      throw const MapImportException('invalid_style', '样式文件必须是 JSON 对象');
    }
    _validateStyle(decoded);
    final root = await _importsDir();
    final id = 'imp_${DateTime.now().millisecondsSinceEpoch}';
    final out = File('${root.path}/style_$id.json');
    await out.writeAsString(text);
    return _addToIndex(ImportedMapResource(
      id: id,
      name: name,
      kind: 'style',
      format: 'style',
      path: out.path,
      enabled: true,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---------------- 校验细节 ----------------

  dynamic _tryDecodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeGeoJson(Map<String, dynamic> j) {
    final type = j['type'] as String?;
    if (type == 'Feature' ||
        type == 'FeatureCollection' ||
        type == 'LineString' ||
        type == 'MultiLineString') {
      return true;
    }
    return j.containsKey('features') || j.containsKey('geometry');
  }

  /// 从 GeoJSON 解码结果抽线。只接受 LineString / MultiLineString；
  /// Point / Polygon 等报 invalid_geojson（不是轨迹层，不静默丢弃）。
  List<List<(double, double)>> _extractGeoJsonLines(dynamic decoded) {
    final lines = <List<(double, double)>>[];
    void addGeometry(Map<String, dynamic> geom) {
      final type = geom['type'] as String?;
      if (type == 'LineString') {
        lines.add(_parsePositionList(geom['coordinates']));
      } else if (type == 'MultiLineString') {
        final raw = geom['coordinates'];
        if (raw is! List) {
          throw const MapImportException(
              'invalid_geojson', 'MultiLineString 的 coordinates 不是数组');
        }
        for (final line in raw) {
          lines.add(_parsePositionList(line));
        }
      } else {
        throw MapImportException(
            'invalid_geojson', '轨迹层只接受 LineString / MultiLineString，遇到 $type');
      }
    }

    if (decoded is Map<String, dynamic>) {
      final type = decoded['type'] as String?;
      if (type == 'FeatureCollection') {
        final features = decoded['features'];
        if (features is! List || features.isEmpty) {
          throw const MapImportException(
              'invalid_geojson', 'FeatureCollection 为空或 features 不是数组');
        }
        for (final f in features) {
          if (f is! Map) {
            throw const MapImportException(
                'invalid_geojson', 'Feature 不是对象');
          }
          final geom = f['geometry'];
          if (geom is! Map) {
            throw const MapImportException(
                'invalid_geojson', 'Feature 缺少 geometry');
          }
          addGeometry(Map<String, dynamic>.from(geom));
        }
      } else if (type == 'Feature') {
        final geom = decoded['geometry'];
        if (geom is! Map) {
          throw const MapImportException(
              'invalid_geojson', 'Feature 缺少 geometry');
        }
        addGeometry(Map<String, dynamic>.from(geom));
      } else if (type == 'LineString' || type == 'MultiLineString') {
        addGeometry(decoded);
      } else {
        throw const MapImportException(
            'invalid_geojson', '不是 GeoJSON 轨迹（Feature / FeatureCollection / 线几何）');
      }
    } else {
      throw const MapImportException('invalid_geojson', '顶层不是 JSON 对象');
    }
    if (lines.isEmpty) {
      throw const MapImportException('invalid_geojson', '没有可用的线坐标');
    }
    return lines;
  }

  /// 坐标合法性：[经度, 纬度]，经度 -180~180，纬度 -90~90，有限数；
  /// 一条线至少 2 个点。非法直接抛错，不截断、不补点。
  List<(double, double)> _parsePositionList(dynamic raw) {
    if (raw is! List || raw.length < 2) {
      throw const MapImportException(
          'invalid_geojson', '一条线至少需要 2 个坐标点');
    }
    final out = <(double, double)>[];
    for (final p in raw) {
      if (p is! List || p.length < 2) {
        throw const MapImportException(
            'invalid_geojson', '坐标点必须是 [经度, 纬度]');
      }
      final lon = (p[0] as num?)?.toDouble();
      final lat = (p[1] as num?)?.toDouble();
      if (lon == null ||
          lat == null ||
          lon.isNaN ||
          lat.isNaN ||
          lon.isInfinite ||
          lat.isInfinite ||
          lon < -180 ||
          lon > 180 ||
          lat < -90 ||
          lat > 90) {
        throw MapImportException(
            'invalid_geojson', '非法坐标：经度 $lon，纬度 $lat');
      }
      out.add((lon, lat));
    }
    return out;
  }

  List<List<(double, double)>> _extractKmlLines(String text) {
    final lines = <List<(double, double)>>[];
    final lineBlocks =
        RegExp(r'<LineString[\s\S]*?</LineString>', caseSensitive: false)
            .allMatches(text);
    for (final block in lineBlocks) {
      final coordMatch = RegExp(
              r'<coordinates>([\s\S]*?)</coordinates>',
              caseSensitive: false)
          .firstMatch(block.group(0)!);
      if (coordMatch == null) continue;
      final tokens = coordMatch
          .group(1)!
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty);
      final pts = <(double, double)>[];
      for (final token in tokens) {
        final parts = token.split(',');
        if (parts.length < 2) {
          throw MapImportException(
              'invalid_kml', '非法 KML 坐标：$token');
        }
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lon == null ||
            lat == null ||
            lon.isNaN ||
            lat.isNaN ||
            lon < -180 ||
            lon > 180 ||
            lat < -90 ||
            lat > 90) {
          throw MapImportException(
              'invalid_kml', '非法 KML 坐标：$token');
        }
        pts.add((lon, lat));
      }
      if (pts.length < 2) {
        throw const MapImportException(
            'invalid_kml', '一条 KML 线至少需要 2 个坐标点');
      }
      lines.add(pts);
    }
    return lines;
  }

  /// 样式 JSON 校验：颜色键必须是 #RRGGBB 或 #AARRGGBB；数值键必须
  /// 为正数；未知键直接报 invalid_style 并点名，不静默忽略。
  static const Set<String> _styleColorKeys = {
    'backgroundColor',
    'routeColor',
    'poiColor',
    'waterColor',
    'landColor',
    'roadColor',
    'labelColor',
  };
  static const Set<String> _styleNumberKeys = {'routeWidth'};
  static const Set<String> _styleIntKeys = {'minZoom', 'maxZoom'};

  void _validateStyle(Map<String, dynamic> style) {
    if (style.isEmpty) {
      throw const MapImportException('invalid_style', '样式文件为空对象');
    }
    final colorRe = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
    for (final entry in style.entries) {
      final k = entry.key;
      final v = entry.value;
      if (_styleColorKeys.contains(k)) {
        if (v is! String || !colorRe.hasMatch(v)) {
          throw MapImportException(
              'invalid_style', '样式颜色 $k 非法，应为 #RRGGBB 格式');
        }
      } else if (_styleNumberKeys.contains(k)) {
        final n = (v as num?)?.toDouble();
        if (n == null || n <= 0 || n > 50) {
          throw MapImportException(
              'invalid_style', '样式数值 $k 非法，应为 0~50 的正数');
        }
      } else if (_styleIntKeys.contains(k)) {
        final n = (v as num?)?.toInt();
        if (n == null || n < 0 || n > 22) {
          throw MapImportException(
              'invalid_style', '样式缩放 $k 非法，应为 0~22 的整数');
        }
      } else {
        throw MapImportException('invalid_style', '未知样式键：$k');
      }
    }
  }

  // ---------------- ZIP 解析（无第三方包，手写中央目录解析） ----------------

  List<_TileEntry> _parseTileZip(Uint8List bytes) {
    // 用中央目录定位各条目，避开 local header 后可能跟的数据描述符问题。
    final eocd = _findEocd(bytes);
    if (eocd < 0) {
      throw const MapImportException('invalid_zip', '找不到 ZIP 中央目录，不是合法 zip');
    }
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint16(eocd + 10, Endian.little);
    final cdOffset = bd.getUint32(eocd + 16, Endian.little);
    if (count == 0) {
      throw const MapImportException('empty_package', '瓦片包为空');
    }
    if (count > maxTileEntries) {
      throw MapImportException(
          'too_large', '瓦片包条目过多（上限 $maxTileEntries）');
    }
    final tiles = <_TileEntry>[];
    final seen = <String>{};
    var totalUncompressed = 0;
    var off = cdOffset;
    for (var i = 0; i < count; i++) {
      if (off + 46 > bytes.length ||
          bd.getUint32(off, Endian.little) != 0x02014b50) {
        throw const MapImportException(
            'invalid_zip', '中央目录损坏，无法解析瓦片包');
      }
      final method = bd.getUint16(off + 10, Endian.little);
      final compSize = bd.getUint32(off + 20, Endian.little);
      final uncompSize = bd.getUint32(off + 24, Endian.little);
      final nameLen = bd.getUint16(off + 28, Endian.little);
      final extraLen = bd.getUint16(off + 30, Endian.little);
      final commentLen = bd.getUint16(off + 32, Endian.little);
      final localOff = bd.getUint32(off + 42, Endian.little);
      final nameBytes =
          bytes.sublist(off + 46, off + 46 + nameLen);
      late final String name;
      try {
        name = utf8.decode(nameBytes, allowMalformed: false);
      } catch (_) {
        throw const MapImportException(
            'invalid_zip', '瓦片包内有非 UTF-8 文件名');
      }
      off += 46 + nameLen + extraLen + commentLen;
      if (name.endsWith('/')) continue; // 目录条目，跳过
      if (uncompSize > maxSingleFileBytes) {
        throw MapImportException(
            'too_large', '单个瓦片过大：$name');
      }
      totalUncompressed += uncompSize;
      if (totalUncompressed > maxTotalUncompressedBytes) {
        throw const MapImportException(
            'too_large', '瓦片包解压后过大（上限 512MB）');
      }
      final tile = _readTileEntry(bytes, bd, localOff, method, compSize, name);
      if (!seen.add(tile.path)) {
        throw MapImportException(
            'invalid_zip', '瓦片包内重复瓦片：${tile.path}');
      }
      tiles.add(tile);
    }
    if (tiles.isEmpty) {
      throw const MapImportException(
          'empty_package', '瓦片包内没有 z/x/y.png 瓦片');
    }
    if (tiles.length > maxTileEntries) {
      throw MapImportException(
          'too_large', '瓦片数量超限（上限 $maxTileEntries）');
    }
    return tiles;
  }

  _TileEntry _readTileEntry(Uint8List bytes, ByteData bd, int localOff,
      int method, int compSize, String name) {
    // 路径校验：拒绝绝对路径与 .. 穿越，z/x/y.png 结构，z 0~22，
    // x/y 必须落在该缩放级别的瓦片范围内。
    if (name.startsWith('/') || name.contains('..')) {
      throw MapImportException('invalid_zip', '非法瓦片路径：$name');
    }
    final m = RegExp(r'^(\d{1,2})/(\d+)/(\d+)\.png$').firstMatch(name);
    if (m == null) {
      throw MapImportException(
          'not_png', '瓦片包内含非 z/x/y.png 条目：$name');
    }
    final z = int.parse(m.group(1)!);
    final x = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (z > 22 || x >= (1 << z) || y >= (1 << z)) {
      throw MapImportException(
          'invalid_zip', '瓦片坐标超出缩放级别范围：$name');
    }
    if (localOff + 30 > bytes.length ||
        bd.getUint32(localOff, Endian.little) != 0x04034b50) {
      throw MapImportException(
          'invalid_zip', '本地文件头损坏：$name');
    }
    final nameLen = bd.getUint16(localOff + 26, Endian.little);
    final extraLen = bd.getUint16(localOff + 28, Endian.little);
    final dataStart = localOff + 30 + nameLen + extraLen;
    if (dataStart + compSize > bytes.length) {
      throw MapImportException(
          'invalid_zip', '瓦片数据截断：$name');
    }
    final comp = bytes.sublist(dataStart, dataStart + compSize);
    late final List<int> raw;
    if (method == 0) {
      raw = comp;
    } else if (method == 8) {
      try {
        raw = ZLibCodec(raw: true).decode(comp);
      } catch (_) {
        throw MapImportException(
            'invalid_zip', '瓦片解压失败：$name');
      }
    } else {
      throw MapImportException(
          'invalid_zip', '不支持的压缩方式（method=$method）：$name');
    }
    const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (raw.length < 8) {
      throw MapImportException('not_png', '瓦片不是 PNG：$name');
    }
    for (var i = 0; i < 8; i++) {
      if (raw[i] != pngMagic[i]) {
        throw MapImportException('not_png', '瓦片不是 PNG：$name');
      }
    }
    return _TileEntry('$z/$x/$y.png', z, Uint8List.fromList(raw));
  }

  int _findEocd(Uint8List bytes) {
    // EOCD 在文件尾 22 字节内起，注释最长 64KB，从尾部向前扫。
    if (bytes.length < 22) return -1;
    final start = bytes.length - 22;
    final floor = (bytes.length - 22 - 65535) < 0
        ? 0
        : bytes.length - 22 - 65535;
    for (var i = start; i >= floor; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    return -1;
  }

  /// 离线瓦片取文件路径：供地图组件按 z/x/y 取本机 PNG。
  /// 资源不是 tiles、或该瓦片不存在时返回 null（调用方回退在线源）。
  static String? tilePathFor(ImportedMapResource r, int z, int x, int y) {
    if (r.kind != 'tiles') return null;
    final p = '${r.path}/$z/$x/$y.png';
    return File(p).existsSync() ? p : null;
  }
}

class _TileEntry {
  final String path;
  final int z;
  final Uint8List pngBytes;
  _TileEntry(this.path, this.z, this.pngBytes);
}
