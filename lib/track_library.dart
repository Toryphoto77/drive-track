/// 赛道库：数据包模型、合并规则、更新检测、本地持久化。
///
/// 设计（用户定稿）：
/// - 库页是数据包管理器，不是信息浏览器：只列包（名 / 版本 / 来源 /
///   更新状态）+ 操作（检查更新 / 更新 / 删除 / 导出 / 编辑）。
/// - 版本号两层：库页顶部显示数据总版本（manifest dataVersion），
///   每条包自带自己的版本，更新按条进行。
/// - 更新走公开拉取：manifest（JSON，含 dataVersion 与各包文件地址）
///   与包 JSON 放工程 data/ 目录，随推仓库进仓库，App 先走
///   jsDelivr（cdn.jsdelivr.net/gh，GitHub 仓库的 CDN 镜像）拉取，
///   失败再自动回落 raw.githubusercontent.com。manifest 不可用时优雅失败，
///   绝不崩溃、绝不清空本地数据。
/// - 合并规则（远端只覆盖远端覆盖的包）：
///   1. 用户改过 / 自建的包永不被远端覆盖；
///   2. 远端包仅当版本号高于本地同 id 包时才覆盖；
///   3. 远端 manifest 里没有的本地包（用户赛道、本地改动）原样保留；
///   4. 用户赛道（isUserTrack）与官方包分开存放，官方更新永不触碰。
/// - 坐标空间严格区分：包里的 centerline / start / finish / gantry /
///   sectorPoints 一律是经纬度（GeoPoint）；旧目录的归一化 0~1 示意
///   点列绝不换算成经纬度写入包里（否则计时错圈）。
/// - 来源红线：只用 OSM（ODbL，库页署名 © OpenStreetMap contributors）
///   + 开源社区数据 + 官方公开事实 + 用户 GPS 实测；绝不复制专有库数据。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';
import 'native.dart';
import 'track_catalog.dart';
import 'track_encyclopedia.dart';
import 'track_sector_data.dart';
import 'track_timing.dart';

/// 赛道库 manifest 地址（公开拉取，随仓库 main 分支走）。
///
/// 更新源双链路（v1.2.11）：主用 jsDelivr，备用 GitHub raw。
/// 清单里各包 url 字段写的是 raw 地址，走 jsDelivr 源时须把包地址
/// 按同一源重写为 cdn 前缀（见 rewriteManifestPackageUrls），不能
/// 清单走 CDN、包还走 raw；走 raw 源时用清单原地址。
/// 注意：jsDelivr 对 GitHub 新提交有几分钟缓存，刚推的包可能要等
/// 几分钟才在 CDN 上可见，属正常现象（不等就走 raw 回落兜底）。
/// 单源超时 10 秒，两源串行总等待约 20 秒。
const String kTrackLibraryManifestUrlCdn =
    'https://cdn.jsdelivr.net/gh/wangtao969/drive-track@main/data/tracks-manifest.json';

/// GitHub raw 备用源（jsDelivr 失败时回落）。
const String kTrackLibraryManifestUrl =
    'https://raw.githubusercontent.com/wangtao969/drive-track/main/data/tracks-manifest.json';

/// 清单包地址的 raw 前缀（与 cdn 前缀一一对应，仅用于源重写）。
const String kTrackPackageRawPrefix =
    'https://raw.githubusercontent.com/wangtao969/drive-track/main/data/packages/';
const String kTrackPackageCdnPrefix =
    'https://cdn.jsdelivr.net/gh/wangtao969/drive-track@main/data/packages/';

/// 单个更新源的超时（连接与响应各 10 秒）。

/// 随 App 打包的种子 manifest（工程 data/ 目录，进 assets）。
const String kBundledManifestAsset = 'data/tracks-manifest.json';

/// OSM 署名（ODbL 要求保留，库页与关于页展示）。
const String kOsmAttribution = '© OpenStreetMap contributors，ODbL';

/// 包来源。
enum TrackPackageSource {
  /// 官方公布（赛道官网 / FIA / 赛事方公布的几何或长度）。
  official,

  /// 用户 GPS 实测（含从行程导入的轨迹）。
  measured,

  /// OpenStreetMap（ODbL）。
  osm,

  /// 按公开布局估算 / 重绘的示意数据（非经纬度实测）。
  estimated,

  /// 未核实（长度、起终点、分段等任一关键项待核）。
  pending,

  /// 开源社区数据集。
  community,

  /// 用户自建赛道。
  user,
}

extension TrackPackageSourceLabel on TrackPackageSource {
  String get label => switch (this) {
    TrackPackageSource.official => '官方',
    TrackPackageSource.measured => '实测',
    TrackPackageSource.osm => 'OSM',
    TrackPackageSource.estimated => '估算',
    TrackPackageSource.pending => '待核',
    TrackPackageSource.community => '社区',
    TrackPackageSource.user => '用户',
  };

  static TrackPackageSource fromJson(String? v) => switch (v) {
    'official' => TrackPackageSource.official,
    'measured' => TrackPackageSource.measured,
    'osm' => TrackPackageSource.osm,
    'estimated' => TrackPackageSource.estimated,
    'pending' => TrackPackageSource.pending,
    'community' => TrackPackageSource.community,
    'user' => TrackPackageSource.user,
    _ => TrackPackageSource.pending,
  };

  String get jsonValue => name;
}

/// 核对状态：已核对 / 待核。未核对的一律不得标为实测或官方。
enum TrackPackageVerification { verified, pending }

extension TrackPackageVerificationLabel on TrackPackageVerification {
  String get label => this == TrackPackageVerification.verified ? '已核对' : '待核';

  static TrackPackageVerification fromJson(String? v) => v == 'verified'
      ? TrackPackageVerification.verified
      : TrackPackageVerification.pending;
}

/// 一个弯角（经纬度位置；几何推导的弯角须在 cornerSource 注明，
/// 绝不冒充官方弯角数据）。
class TrackCorner {
  final int number;

  /// 'left' / 'right'（车手视角）。
  final String direction;
  final int radiusM;
  final int angleDeg;
  final GeoPoint point;

  const TrackCorner({
    required this.number,
    required this.direction,
    required this.radiusM,
    required this.angleDeg,
    required this.point,
  });

  String get directionLabel => direction == 'left' ? '左弯' : '右弯';

  factory TrackCorner.fromJson(Map<String, dynamic> j) => TrackCorner(
    number: (j['number'] as num?)?.toInt() ?? 0,
    direction: (j['direction'] as String?) ?? 'right',
    radiusM: (j['radiusM'] as num?)?.toInt() ?? 0,
    angleDeg: (j['angleDeg'] as num?)?.toInt() ?? 0,
    point: _geoFromJson(j),
  );

  Map<String, dynamic> toJson() => {
    'number': number,
    'direction': direction,
    'radiusM': radiusM,
    'angleDeg': angleDeg,
    'lat': point.lat,
    'lon': point.lon,
  };
}

GeoPoint _geoFromJson(Map<String, dynamic> j) => GeoPoint(
  (j['lat'] as num?)?.toDouble() ?? 0,
  (j['lon'] as num?)?.toDouble() ?? 0,
);

Map<String, dynamic>? _geoToJson(GeoPoint? p) =>
    p == null ? null : {'lat': p.lat, 'lon': p.lon};

List<GeoPoint> _geoListFromJson(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map<String, dynamic>>().map(_geoFromJson).toList();
}

/// 一个赛道数据包：真实可用的赛道数据（不只是轮廓）。
class TrackPackage {
  final String id;
  final String nameCn;
  final String nameEn;
  final String region;

  /// 包版本（整数；更新比对按此值，越大越新）。
  final int version;
  final TrackPackageSource source;
  final String sourceDetail;
  final TrackPackageVerification verification;
  final String verificationNote;

  /// 详细赛道图中心线：高密度经纬度点列（闭合回路首尾重合）。
  final List<GeoPoint> centerline;

  /// 真实长度（米，由中心线累加得出；示意包则为目录约数换算）。
  final int? lengthM;

  /// 官方公布长度（米；无公布值时为 null，不得编数）。
  final int? publishedLengthM;

  /// 弯角表（每弯：弯号、方向、半径、角度、经纬度位置）。
  final List<TrackCorner> corners;

  /// 弯角表来源：'osm-derived'（OSM 几何推导）/ 'user' / null（无表）。
  final String? cornerSource;

  /// 分段点（经纬度；空 = 待核，绝不用归一化点冒充）。
  final List<GeoPoint> sectorPoints;
  final String sectorNote;

  /// 龙门架位置（经纬度；null = 待核）。
  final GeoPoint? gantry;

  /// 起点 / 终点（经纬度；赛道起终线通常同点；null = 待核）。
  final GeoPoint? start;
  final GeoPoint? finish;
  final String startNote;

  /// 维修区入口 / 出口（经纬度；null = 待核）。
  final GeoPoint? pitIn;
  final GeoPoint? pitOut;

  /// 本地改动标记：用户在编辑器 / 导入里改过，远端更新永不覆盖。
  final bool userModified;

  /// 用户赛道：与官方库分开存放，官方更新永不触碰。
  final bool isUserTrack;

  const TrackPackage({
    required this.id,
    required this.nameCn,
    required this.nameEn,
    required this.region,
    required this.version,
    required this.source,
    this.sourceDetail = '',
    required this.verification,
    this.verificationNote = '',
    this.centerline = const [],
    this.lengthM,
    this.publishedLengthM,
    this.corners = const [],
    this.cornerSource,
    this.sectorPoints = const [],
    this.sectorNote = '',
    this.gantry,
    this.start,
    this.finish,
    this.startNote = '',
    this.pitIn,
    this.pitOut,
    this.userModified = false,
    this.isUserTrack = false,
  });

  bool get hasCenterline => centerline.length >= 3;
  bool get hasStartFinish => start != null;
  bool get hasSectors => sectorPoints.isNotEmpty;
  bool get hasPitLane => pitIn != null && pitOut != null;
  bool get isVerified => verification == TrackPackageVerification.verified;

  double? get lengthKm => lengthM == null ? null : lengthM! / 1000.0;

  String get lengthLabel {
    final km = lengthKm;
    if (km == null) return '长度待核';
    if (source == TrackPackageSource.osm ||
        source == TrackPackageSource.measured ||
        source == TrackPackageSource.official) {
      return '${km.toStringAsFixed(3)} km';
    }
    return '约 ${km.toStringAsFixed(3)} km';
  }

  String get sourceLabel => source.label;
  String get verificationLabel => verification.label;

  TrackPackage copyWith({
    String? id,
    String? nameCn,
    String? nameEn,
    String? region,
    int? version,
    TrackPackageSource? source,
    String? sourceDetail,
    TrackPackageVerification? verification,
    String? verificationNote,
    List<GeoPoint>? centerline,
    int? lengthM,
    int? publishedLengthM,
    List<TrackCorner>? corners,
    String? cornerSource,
    List<GeoPoint>? sectorPoints,
    String? sectorNote,
    GeoPoint? gantry,
    GeoPoint? start,
    GeoPoint? finish,
    String? startNote,
    GeoPoint? pitIn,
    GeoPoint? pitOut,
    bool? userModified,
    bool? isUserTrack,
  }) {
    return TrackPackage(
      id: id ?? this.id,
      nameCn: nameCn ?? this.nameCn,
      nameEn: nameEn ?? this.nameEn,
      region: region ?? this.region,
      version: version ?? this.version,
      source: source ?? this.source,
      sourceDetail: sourceDetail ?? this.sourceDetail,
      verification: verification ?? this.verification,
      verificationNote: verificationNote ?? this.verificationNote,
      centerline: centerline ?? this.centerline,
      lengthM: lengthM ?? this.lengthM,
      publishedLengthM: publishedLengthM ?? this.publishedLengthM,
      corners: corners ?? this.corners,
      cornerSource: cornerSource ?? this.cornerSource,
      sectorPoints: sectorPoints ?? this.sectorPoints,
      sectorNote: sectorNote ?? this.sectorNote,
      gantry: gantry ?? this.gantry,
      start: start ?? this.start,
      finish: finish ?? this.finish,
      startNote: startNote ?? this.startNote,
      pitIn: pitIn ?? this.pitIn,
      pitOut: pitOut ?? this.pitOut,
      userModified: userModified ?? this.userModified,
      isUserTrack: isUserTrack ?? this.isUserTrack,
    );
  }

  factory TrackPackage.fromJson(Map<String, dynamic> j) => TrackPackage(
    id: (j['id'] as String?) ?? '',
    nameCn: (j['nameCn'] as String?) ?? '',
    nameEn: (j['nameEn'] as String?) ?? '',
    region: (j['region'] as String?) ?? '',
    version: (j['version'] as num?)?.toInt() ?? 0,
    source: TrackPackageSourceLabel.fromJson(j['source'] as String?),
    sourceDetail: (j['sourceDetail'] as String?) ?? '',
    verification: TrackPackageVerificationLabel.fromJson(
      j['verification'] as String?,
    ),
    verificationNote: (j['verificationNote'] as String?) ?? '',
    centerline: _geoListFromJson(j['centerline']),
    lengthM: (j['lengthM'] as num?)?.toInt(),
    publishedLengthM: (j['publishedLengthM'] as num?)?.toInt(),
    corners: (j['corners'] is List)
        ? (j['corners'] as List)
              .whereType<Map<String, dynamic>>()
              .map(TrackCorner.fromJson)
              .toList()
        : const [],
    cornerSource: j['cornerSource'] as String?,
    sectorPoints: _geoListFromJson(j['sectorPoints']),
    sectorNote: (j['sectorNote'] as String?) ?? '',
    gantry: j['gantry'] is Map<String, dynamic>
        ? _geoFromJson(j['gantry'] as Map<String, dynamic>)
        : null,
    start: j['start'] is Map<String, dynamic>
        ? _geoFromJson(j['start'] as Map<String, dynamic>)
        : null,
    finish: j['finish'] is Map<String, dynamic>
        ? _geoFromJson(j['finish'] as Map<String, dynamic>)
        : null,
    startNote: (j['startNote'] as String?) ?? '',
    pitIn: j['pitIn'] is Map<String, dynamic>
        ? _geoFromJson(j['pitIn'] as Map<String, dynamic>)
        : null,
    pitOut: j['pitOut'] is Map<String, dynamic>
        ? _geoFromJson(j['pitOut'] as Map<String, dynamic>)
        : null,
    userModified: (j['userModified'] as bool?) ?? false,
    isUserTrack: (j['isUserTrack'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nameCn': nameCn,
    'nameEn': nameEn,
    'region': region,
    'version': version,
    'source': source.jsonValue,
    'sourceDetail': sourceDetail,
    'verification': verification.name,
    'verificationNote': verificationNote,
    'centerline': centerline.map((p) => {'lat': p.lat, 'lon': p.lon}).toList(),
    'lengthM': lengthM,
    'publishedLengthM': publishedLengthM,
    'corners': corners.map((c) => c.toJson()).toList(),
    'cornerSource': cornerSource,
    'sectorPoints': sectorPoints
        .map((p) => {'lat': p.lat, 'lon': p.lon})
        .toList(),
    'sectorNote': sectorNote,
    'gantry': _geoToJson(gantry),
    'start': _geoToJson(start),
    'finish': _geoToJson(finish),
    'startNote': startNote,
    'pitIn': _geoToJson(pitIn),
    'pitOut': _geoToJson(pitOut),
    'userModified': userModified,
    'isUserTrack': isUserTrack,
  };
}

/// manifest 里的一个包条目。
class ManifestPackage {
  final String id;
  final String nameCn;
  final int version;
  final String url;
  final TrackPackageSource source;
  final TrackPackageVerification verification;

  const ManifestPackage({
    required this.id,
    required this.nameCn,
    required this.version,
    required this.url,
    required this.source,
    required this.verification,
  });

  factory ManifestPackage.fromJson(Map<String, dynamic> j) => ManifestPackage(
    id: (j['id'] as String?) ?? '',
    nameCn: (j['nameCn'] as String?) ?? '',
    version: (j['version'] as num?)?.toInt() ?? 0,
    url: (j['url'] as String?) ?? '',
    source: TrackPackageSourceLabel.fromJson(j['source'] as String?),
    verification: TrackPackageVerificationLabel.fromJson(
      j['verification'] as String?,
    ),
  );

  ManifestPackage copyWith({String? url}) => ManifestPackage(
    id: id,
    nameCn: nameCn,
    version: version,
    url: url ?? this.url,
    source: source,
    verification: verification,
  );
}

/// 单个包地址按更新源重写（纯函数，可单测）：走 jsDelivr 源时把
/// raw 前缀换成 cdn 前缀；非 raw 地址（如以后清单直接写 cdn 或
/// 别的源）原样不动；走 raw 源时不调用本函数，用清单原地址。
String rewriteTrackPackageUrl(String url, {required bool useCdn}) {
  if (!useCdn) return url;
  if (url.startsWith(kTrackPackageRawPrefix)) {
    return kTrackPackageCdnPrefix +
        url.substring(kTrackPackageRawPrefix.length);
  }
  return url;
}

/// 整份 manifest 的包地址按更新源重写（纯函数，可单测）。
TrackLibraryManifest rewriteManifestPackageUrls(
  TrackLibraryManifest manifest, {
  required bool useCdn,
}) {
  if (!useCdn) return manifest;
  return TrackLibraryManifest(
    dataVersion: manifest.dataVersion,
    updatedAt: manifest.updatedAt,
    attribution: manifest.attribution,
    packages: manifest.packages
        .map(
          (p) => p.copyWith(url: rewriteTrackPackageUrl(p.url, useCdn: true)),
        )
        .toList(),
  );
}

class TrackLibraryManifest {
  final String dataVersion;
  final String updatedAt;
  final String attribution;
  final List<ManifestPackage> packages;

  const TrackLibraryManifest({
    required this.dataVersion,
    required this.updatedAt,
    required this.attribution,
    required this.packages,
  });

  factory TrackLibraryManifest.fromJson(Map<String, dynamic> j) =>
      TrackLibraryManifest(
        dataVersion: (j['dataVersion'] as String?) ?? '',
        updatedAt: (j['updatedAt'] as String?) ?? '',
        attribution: (j['attribution'] as String?) ?? '',
        packages: (j['packages'] is List)
            ? (j['packages'] as List)
                  .whereType<Map<String, dynamic>>()
                  .map(ManifestPackage.fromJson)
                  .toList()
            : const [],
      );
}

/// 一条可更新的包（检查结果）。
class PackageUpdate {
  final String id;
  final String nameCn;

  /// 本地版本；-1 表示本地尚未安装（远端新增包）。
  final int localVersion;
  final int remoteVersion;
  final String url;
  final bool isNew;

  const PackageUpdate({
    required this.id,
    required this.nameCn,
    required this.localVersion,
    required this.remoteVersion,
    required this.url,
    this.isNew = false,
  });
}

enum UpdateCheckStatus { upToDate, available, error }

/// 检查更新结果（仿照 update_service.dart 的状态口径）。
class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String message;

  /// 远端 manifest 的数据总版本（失败时为空）。
  final String remoteDataVersion;
  final List<PackageUpdate> updates;

  /// 因本地改动而跳过的包（用户改过的包永不被远端覆盖，故不列入更新）。
  final List<PackageUpdate> skippedUserModified;

  const UpdateCheckResult({
    required this.status,
    required this.message,
    this.remoteDataVersion = '',
    this.updates = const [],
    this.skippedUserModified = const [],
  });
}

/// 应用更新结果。
class ApplyResult {
  final List<String> appliedIds;
  final Map<String, String> skippedReasons;

  const ApplyResult({
    this.appliedIds = const [],
    this.skippedReasons = const {},
  });
}

/// 可注入的拉取函数（生产走 HttpClient，测试走 fake，不依赖真实网络）。
typedef TrackLibraryFetcher = Future<String> Function(Uri uri);

Future<String> _defaultFetcher(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return body;
  } finally {
    client.close();
  }
}

/// 合并规则（纯函数，可单测）：
/// 内置迁移包 → 打包种子包（版本更高才覆盖）→ 本地覆盖层
/// （用户改动无条件胜出；远端包仅当版本高于本地才覆盖；用户赛道
/// 编辑器保存时的分段注记规则（纯函数，可单测）：
/// - 分段没动 → 原注记不动（只改轮廓/起终点不影响分段来源）；
/// - 分段被改动 → 实测口径（用户手动落点覆盖推导值，注记必须同步，
///   否则界面仍会把实测点标成“模拟器数据推导”）；
/// - 分段被清空 → 待补口径。
String sectorNoteAfterEdit({
  required List<GeoPoint> original,
  required List<GeoPoint> edited,
  required String originalNote,
}) {
  final changed =
      edited.length != original.length ||
      edited.asMap().entries.any(
        (e) =>
            e.value.lat != original[e.key].lat ||
            e.value.lon != original[e.key].lon,
      );
  if (!changed) return originalNote;
  if (edited.isEmpty) return '分段点待核：用户已清除原分段，待重新落点';
  return '用户实测分段点（编辑器手动落点），以实测为准';
}

/// 绝不进入官方列表）。
List<TrackPackage> mergePackages({
  required List<TrackPackage> builtin,
  required List<TrackPackage> bundled,
  required List<TrackPackage> overrides,
}) {
  final map = <String, TrackPackage>{for (final p in builtin) p.id: p};
  for (final p in bundled) {
    final cur = map[p.id];
    if (cur == null || p.version > cur.version) map[p.id] = p;
  }
  for (final p in overrides) {
    if (p.isUserTrack) continue;
    final cur = map[p.id];
    if (cur == null) {
      map[p.id] = p;
      continue;
    }
    if (cur.isUserTrack) continue;
    if (p.userModified) {
      map[p.id] = p;
      continue;
    }
    if (p.version > cur.version) map[p.id] = p;
  }
  final list = map.values.toList()
    ..sort((a, b) => a.nameCn.compareTo(b.nameCn));
  return list;
}

/// 检查更新（纯比对部分，可单测；网络部分由 fetcher 注入）。
UpdateCheckResult diffUpdates({
  required List<TrackPackage> localOfficial,
  required TrackLibraryManifest manifest,
}) {
  final byId = {for (final p in localOfficial) p.id: p};
  final updates = <PackageUpdate>[];
  final skipped = <PackageUpdate>[];
  for (final m in manifest.packages) {
    if (m.id.isEmpty || m.url.isEmpty) continue;
    final local = byId[m.id];
    if (local == null) {
      updates.add(
        PackageUpdate(
          id: m.id,
          nameCn: m.nameCn,
          localVersion: -1,
          remoteVersion: m.version,
          url: m.url,
          isNew: true,
        ),
      );
      continue;
    }
    if (local.isUserTrack) continue;
    if (local.userModified) {
      skipped.add(
        PackageUpdate(
          id: m.id,
          nameCn: m.nameCn,
          localVersion: local.version,
          remoteVersion: m.version,
          url: m.url,
        ),
      );
      continue;
    }
    if (m.version > local.version) {
      updates.add(
        PackageUpdate(
          id: m.id,
          nameCn: m.nameCn,
          localVersion: local.version,
          remoteVersion: m.version,
          url: m.url,
        ),
      );
    }
  }
  if (updates.isEmpty) {
    return UpdateCheckResult(
      status: UpdateCheckStatus.upToDate,
      message: '赛道库已是最新版本',
      remoteDataVersion: manifest.dataVersion,
      skippedUserModified: skipped,
    );
  }
  return UpdateCheckResult(
    status: UpdateCheckStatus.available,
    message: '${updates.length} 个包可更新',
    remoteDataVersion: manifest.dataVersion,
    updates: updates,
    skippedUserModified: skipped,
  );
}

/// 库快照：数据总版本 + 官方包 + 用户赛道 + 本地覆盖层 id 集
/// （覆盖层存在即表示该包有本地版本：用户改动或远端更新，可恢复默认）。
class LibrarySnapshot {
  final String dataVersion;
  final List<TrackPackage> official;
  final List<TrackPackage> userTracks;
  final Set<String> overrideIds;

  const LibrarySnapshot({
    required this.dataVersion,
    required this.official,
    required this.userTracks,
    this.overrideIds = const {},
  });

  TrackPackage? packageById(String id) {
    for (final p in official) {
      if (p.id == id) return p;
    }
    for (final p in userTracks) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class _LocalLibrary {
  final String dataVersion;
  final List<TrackPackage> overrides;
  final List<TrackPackage> userTracks;

  const _LocalLibrary({
    required this.dataVersion,
    required this.overrides,
    required this.userTracks,
  });
}

/// 赛道库服务：打包种子 + 本地覆盖层 + 用户赛道的合并与持久化。
class TrackLibraryService {
  static final TrackLibraryService instance = TrackLibraryService._();
  TrackLibraryService._();

  static const String _localFileName = 'track_library.json';

  Future<File> _localFile() async {
    final dir = await Native.getFilesDir();
    return File('$dir/$_localFileName');
  }

  Future<_LocalLibrary> _loadLocal() async {
    try {
      final f = await _localFile();
      if (!await f.exists()) {
        return const _LocalLibrary(
          dataVersion: '',
          overrides: [],
          userTracks: [],
        );
      }
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      List<TrackPackage> pkgs(dynamic v) {
        if (v is! List) return const [];
        return v
            .whereType<Map<String, dynamic>>()
            .map(TrackPackage.fromJson)
            .toList();
      }

      return _LocalLibrary(
        dataVersion: (j['dataVersion'] as String?) ?? '',
        overrides: pkgs(j['overrides']),
        userTracks: pkgs(j['userTracks']),
      );
    } catch (_) {
      // 本地文件损坏 / 缺失时回落为空，绝不抛错、绝不清空远端数据。
      return const _LocalLibrary(
        dataVersion: '',
        overrides: [],
        userTracks: [],
      );
    }
  }

  Future<void> _saveLocal(_LocalLibrary local) async {
    final f = await _localFile();
    await f.writeAsString(
      jsonEncode({
        'dataVersion': local.dataVersion,
        'overrides': local.overrides.map((p) => p.toJson()).toList(),
        'userTracks': local.userTracks.map((p) => p.toJson()).toList(),
      }),
    );
  }

  /// 打包的种子包（assets data/；缺失时回落为空，不抛错）。
  Future<List<TrackPackage>> bundledPackages() async {
    try {
      final manifestJson = await rootBundle.loadString(kBundledManifestAsset);
      final manifest = TrackLibraryManifest.fromJson(
        jsonDecode(manifestJson) as Map<String, dynamic>,
      );
      final out = <TrackPackage>[];
      for (final m in manifest.packages) {
        try {
          final pkgJson = await rootBundle.loadString(
            'data/packages/${m.id}.json',
          );
          out.add(
            TrackPackage.fromJson(jsonDecode(pkgJson) as Map<String, dynamic>),
          );
        } catch (_) {
          // 单个包缺失时跳过，不影响其他包。
          continue;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 打包 manifest 的数据总版本（缺失时为空）。
  Future<String> bundledDataVersion() async {
    try {
      final manifestJson = await rootBundle.loadString(kBundledManifestAsset);
      final manifest = TrackLibraryManifest.fromJson(
        jsonDecode(manifestJson) as Map<String, dynamic>,
      );
      return manifest.dataVersion;
    } catch (_) {
      return '';
    }
  }

  /// 合并后的完整快照（内置迁移 + 打包种子 + 本地覆盖 + 用户赛道）。
  Future<LibrarySnapshot> loadAll() async {
    final local = await _loadLocal();
    final bundled = await bundledPackages();
    final official = mergePackages(
      builtin: builtinPackages(),
      bundled: bundled,
      overrides: local.overrides,
    );
    var dataVersion = local.dataVersion;
    if (dataVersion.isEmpty) {
      dataVersion = await bundledDataVersion();
    }
    if (dataVersion.isEmpty) {
      // 无任何 manifest 时的本地示意基线（非远端版本，不得冒充）。
      dataVersion = '0.1（本地示意）';
    }
    return LibrarySnapshot(
      dataVersion: dataVersion,
      official: official,
      userTracks: local.userTracks,
      overrideIds: local.overrides.map((p) => p.id).toSet(),
    );
  }

  /// 保存一个包：
  /// - 用户赛道 → 用户赛道区；
  /// - 官方包的本地编辑 / 导入 → 覆盖层（userModified=true，远端永不覆盖）。
  Future<void> savePackage(TrackPackage pkg) async {
    final local = await _loadLocal();
    if (pkg.isUserTrack) {
      final list = local.userTracks.where((p) => p.id != pkg.id).toList()
        ..add(pkg);
      await _saveLocal(
        _LocalLibrary(
          dataVersion: local.dataVersion,
          overrides: local.overrides,
          userTracks: list,
        ),
      );
      return;
    }
    final marked = pkg.copyWith(userModified: true);
    final list = local.overrides.where((p) => p.id != pkg.id).toList()
      ..add(marked);
    await _saveLocal(
      _LocalLibrary(
        dataVersion: local.dataVersion,
        overrides: list,
        userTracks: local.userTracks,
      ),
    );
  }

  /// 删除一条用户赛道（官方包不可删，只能恢复默认）。
  Future<void> deleteUserTrack(String id) async {
    final local = await _loadLocal();
    await _saveLocal(
      _LocalLibrary(
        dataVersion: local.dataVersion,
        overrides: local.overrides,
        userTracks: local.userTracks.where((p) => p.id != id).toList(),
      ),
    );
  }

  /// 恢复官方包默认（删掉本地覆盖层，回到打包种子 / 内置迁移）。
  Future<void> resetOverride(String id) async {
    final local = await _loadLocal();
    await _saveLocal(
      _LocalLibrary(
        dataVersion: local.dataVersion,
        overrides: local.overrides.where((p) => p.id != id).toList(),
        userTracks: local.userTracks,
      ),
    );
  }

  /// 导出包 JSON 到本机文件，返回文件路径（调用方走系统分享）。
  Future<String> exportPackage(TrackPackage pkg) async {
    final dir = await Native.getFilesDir();
    final path = '$dir/track_package_export_${pkg.id}.json';
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(pkg.toJson()));
    return path;
  }

  /// 检查更新：拉 manifest → 按条比对版本。失败时返回 error 状态，
  /// 绝不改动本地数据。
  ///
  /// 双源串行（v1.2.11）：先 jsDelivr，失败再回落 GitHub raw；单源
  /// 超时 10 秒，两源总等待约 20 秒。任一源拉到的 manifest 为空
  /// （dataVersion 与 packages 双空）视为该源失败，继续试下一源；
  /// 两源都失败才报网络问题。清单走哪个源，包地址就按同一源重写
  /// （jsDelivr 源时包走 cdn 前缀，raw 源时用清单原地址）。
  Future<UpdateCheckResult> checkForUpdates({
    TrackLibraryFetcher? fetcher,
  }) async {
    final snap = await loadAll();
    final fetch = fetcher ?? _defaultFetcher;
    var sawEmptyManifest = false;
    for (final entry in [
      (kTrackLibraryManifestUrlCdn, true),
      (kTrackLibraryManifestUrl, false),
    ]) {
      final (manifestUrl, useCdn) = entry;
      try {
        final body = await fetch(Uri.parse(manifestUrl))
            .timeout(const Duration(seconds: 10));
        final manifest = TrackLibraryManifest.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        if (manifest.dataVersion.isEmpty && manifest.packages.isEmpty) {
          sawEmptyManifest = true;
          continue;
        }
        final sourced = rewriteManifestPackageUrls(manifest, useCdn: useCdn);
        return diffUpdates(localOfficial: snap.official, manifest: sourced);
      } catch (_) {
        // 该源失败，继续试下一源；两源都失败才在循环后统一报错。
        continue;
      }
    }
    if (sawEmptyManifest) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: '更新清单为空，请稍后重试',
      );
    }
    return const UpdateCheckResult(
      status: UpdateCheckStatus.error,
      message: '网络不通，请检查网络或代理后重试',
    );
  }

  /// 应用更新：逐条下载包 JSON → 校验 → 写入覆盖层（非用户改动）。
  /// 用户改过 / 用户赛道绝不被覆盖，跳过的写入原因。
  Future<ApplyResult> applyUpdates({
    required List<PackageUpdate> updates,
    required String manifestDataVersion,
    TrackLibraryFetcher? fetcher,
  }) async {
    final fetch = fetcher ?? _defaultFetcher;
    final local = await _loadLocal();
    final applied = <String>[];
    final skipped = <String, String>{};
    var overrides = List<TrackPackage>.from(local.overrides);
    var userTracks = List<TrackPackage>.from(local.userTracks);
    final seenIds = <String>{};
    for (final u in updates) {
      if (!seenIds.add(u.id)) continue;
      try {
        final body = await fetch(Uri.parse(u.url))
            .timeout(const Duration(seconds: 10));
        final pkg = TrackPackage.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        if (pkg.id != u.id) {
          skipped[u.id] = '下载的包 id 与清单不一致，已跳过';
          continue;
        }
        if (userTracks.any((p) => p.id == pkg.id)) {
          skipped[u.id] = '用户赛道，官方更新不覆盖';
          continue;
        }
        final curOverride = overrides.where((p) => p.id == pkg.id).firstOrNull;
        if (curOverride != null && curOverride.userModified) {
          skipped[u.id] = '本地已改动，官方更新不覆盖';
          continue;
        }
        final snap = await loadAll();
        final cur = snap.packageById(pkg.id);
        if (cur != null && pkg.version <= cur.version) {
          skipped[u.id] = '本地版本已更新，无需覆盖';
          continue;
        }
        overrides = overrides.where((p) => p.id != pkg.id).toList()
          ..add(pkg.copyWith(userModified: false));
        applied.add(pkg.id);
      } catch (e) {
        skipped[u.id] = '下载失败：$e';
      }
    }
    await _saveLocal(
      _LocalLibrary(
        dataVersion: manifestDataVersion.isEmpty
            ? local.dataVersion
            : manifestDataVersion,
        overrides: overrides,
        userTracks: userTracks,
      ),
    );
    return ApplyResult(appliedIds: applied, skippedReasons: skipped);
  }
}

/// ---------------------------------------------------------------------------
/// 迁移：现有 21 条原样保留为示意包（版本 0，低于种子包版本 1）。
/// - 来源标估算；摩纳哥 / 雪邦 / 巴瑟斯特 3 条 OSM 真实轮廓标 OSM
///   （但轮廓仍是归一化示意，非经纬度，故核对状态一律待核）。
/// - 绝不凭空编造任何新坐标：中心线 / 起终点 / 龙门架 / 经纬度分段点
///   全部留空标待核；分段沿用原 sectorDataFor 的估算 / 待核口径。
/// ---------------------------------------------------------------------------

const Set<String> _osmOutlineIds = {'monaco', 'sepang', 'bathurst'};

List<TrackPackage> builtinPackages() {
  final out = <TrackPackage>[];
  for (final e in encyclopediaTracks) {
    final km = e.resolvedLengthKm;
    final sector = sectorDataFor(e.id);
    final isOsm = _osmOutlineIds.contains(e.id);
    out.add(
      TrackPackage(
        id: e.id,
        nameCn: e.nameCn,
        nameEn: e.nameEn,
        region: e.region,
        version: 0,
        source: isOsm ? TrackPackageSource.osm : TrackPackageSource.estimated,
        sourceDetail: isOsm
            ? 'OSM 真实走线（归一化示意，非经纬度，待经纬度化）'
            : '原赛道目录示意数据（归一化轮廓，非经纬度）',
        verification: TrackPackageVerification.pending,
        verificationNote: isOsm
            ? '示意数据：OSM 走线仅归一化示意，经纬度几何、分段、起终点待核对后覆盖'
            : '示意数据：轮廓 / 弯角为归一化示意，非经纬度；分段为估算 / 待核；经纬度几何待种子数据核对后覆盖',
        lengthM: km == null ? null : (km * 1000).round(),
        publishedLengthM: km == null ? null : (km * 1000).round(),
        sectorNote: sector == null
            ? '分段待核'
            : '${sector.sourceLabel}：${sector.note}（经纬度点待补）',
        startNote: '起终点待核：公开资料起终点坐标未经核实，未写入',
      ),
    );
  }
  return out;
}

/// ---------------------------------------------------------------------------
/// 几何工具（纯函数，可单测）。
/// ---------------------------------------------------------------------------

double _haversineM(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  final p1 = a.lat * math.pi / 180;
  final p2 = b.lat * math.pi / 180;
  final dphi = (b.lat - a.lat) * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final x =
      math.sin(dphi / 2) * math.sin(dphi / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.sqrt(x));
}

/// 折线总长（米）。
double polylineLengthM(List<GeoPoint> pts) {
  var total = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    total += _haversineM(pts[i], pts[i + 1]);
  }
  return total;
}

/// 经纬度包围盒（供同一坐标系下多组点共用，避免各自归一化错位）。
class _LatLonBounds {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final double cosLat;
  final double span;

  _LatLonBounds(List<GeoPoint> pts)
    : minLat = pts.map((p) => p.lat).reduce(math.min),
      maxLat = pts.map((p) => p.lat).reduce(math.max),
      minLon = pts.map((p) => p.lon).reduce(math.min),
      maxLon = pts.map((p) => p.lon).reduce(math.max),
      cosLat = math.cos(
        (pts.map((p) => p.lat).reduce(math.min) +
                pts.map((p) => p.lat).reduce(math.max)) /
            2 *
            math.pi /
            180,
      ),
      span = _spanOf(pts);

  static double _spanOf(List<GeoPoint> pts) {
    final minLat = pts.map((p) => p.lat).reduce(math.min);
    final maxLat = pts.map((p) => p.lat).reduce(math.max);
    final minLon = pts.map((p) => p.lon).reduce(math.min);
    final maxLon = pts.map((p) => p.lon).reduce(math.max);
    final cosLat = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    return math.max(maxLat - minLat, (maxLon - minLon) * cosLat);
  }

  OutlinePoint project(GeoPoint p) {
    final latSpan = maxLat - minLat;
    final lonSpan = (maxLon - minLon) * cosLat;
    if (span <= 0) return const OutlinePoint(0.5, 0.5);
    final x = ((p.lon - minLon) * cosLat + (span - lonSpan) / 2) / span;
    final y = 1 - ((p.lat - minLat) + (span - latSpan) / 2) / span;
    return OutlinePoint(x, y);
  }
}

/// 经纬度点列 → 归一化 0~1 示意点列（等距圆柱近似，保长宽比，
/// 居中进正方形；仅用于界面示意，绝不反向当经纬度用）。
List<OutlinePoint> normalizeLatLon(List<GeoPoint> pts) {
  if (pts.isEmpty) return const [];
  final b = _LatLonBounds(pts);
  return pts.map(b.project).toList();
}

/// 编辑器用投影：经纬度 ↔ 画布坐标（等距圆柱近似，保长宽比居中）。
class LatLonProjection {
  final _LatLonBounds _b;

  LatLonProjection(List<GeoPoint> pts) : _b = _LatLonBounds(pts);

  /// 画布尺寸 → 投影参数（scale, offsetX, offsetY），供 project/unproject 共用。
  (double, double, double) _params(double width, double height) {
    final latSpan = _b.maxLat - _b.minLat;
    final lonSpan = (_b.maxLon - _b.minLon) * _b.cosLat;
    final scale = math.min(width / _b.span, height / _b.span);
    final ox = (width - lonSpan * scale) / 2 - _b.minLon * _b.cosLat * scale;
    final oy = (height - latSpan * scale) / 2 + _b.maxLat * scale;
    return (scale, ox, oy);
  }

  /// 经纬度 → 画布坐标（x 向右，y 向下，北在上）。
  (double, double) project(GeoPoint p, double width, double height) {
    final (scale, ox, oy) = _params(width, height);
    return (p.lon * _b.cosLat * scale + ox, oy - p.lat * scale);
  }

  /// 画布坐标 → 经纬度。
  GeoPoint unproject(double x, double y, double width, double height) {
    final (scale, ox, oy) = _params(width, height);
    final lon = (x - ox) / (_b.cosLat * scale);
    final lat = (oy - y) / scale;
    return GeoPoint(lat, lon);
  }
}

/// Douglas-Peucker 简化（容差米；端点必保留；超 800 点时等距抽稀兜底）。
List<GeoPoint> simplifyPolyline(List<GeoPoint> pts, double toleranceM) {
  if (pts.length <= 2) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;

  double perpDistM(GeoPoint p, GeoPoint a, GeoPoint b) {
    // 局部等距圆柱投影下的点到线段距离（米）。
    final cosLat = math.cos(a.lat * math.pi / 180);
    final ax = 0.0;
    final ay = 0.0;
    final bx = (b.lon - a.lon) * cosLat * 111320;
    final by = (b.lat - a.lat) * 110540;
    final px = (p.lon - a.lon) * cosLat * 111320;
    final py = (p.lat - a.lat) * 110540;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return _haversineM(p, a);
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  void recurse(int first, int last) {
    var maxD = 0.0;
    var maxI = -1;
    for (var i = first + 1; i < last; i++) {
      final d = perpDistM(pts[i], pts[first], pts[last]);
      if (d > maxD) {
        maxD = d;
        maxI = i;
      }
    }
    if (maxI >= 0 && maxD > toleranceM) {
      keep[maxI] = true;
      recurse(first, maxI);
      recurse(maxI, last);
    }
  }

  recurse(0, pts.length - 1);
  var out = <GeoPoint>[];
  for (var i = 0; i < pts.length; i++) {
    if (keep[i]) out.add(pts[i]);
  }
  if (out.length > 800) {
    final step = out.length / 800;
    final sampled = <GeoPoint>[];
    for (var i = 0; i < 800; i++) {
      sampled.add(out[(i * step).floor()]);
    }
    sampled.add(out.last);
    out = sampled;
  }
  return out;
}

/// 从一次实测行程导成用户赛道包（轨迹点列即轮廓与起终点）。
/// 点数不足时返回 null（调用方提示用户，不编数据）。
TrackPackage? packageFromTrip(Trip trip, {String? name}) {
  final raw = trip.points.map((p) => GeoPoint(p.lat, p.lon)).toList();
  if (raw.length < 10) return null;
  final centerline = simplifyPolyline(raw, 3.0);
  final first = centerline.first;
  var last = centerline.last;
  // 闭合回路：末点落在首点 100m 内时，起终点归一为同一点。
  if (_haversineM(first, last) < 100) last = first;
  final date = DateTime.fromMillisecondsSinceEpoch(trip.startMs);
  final dateLabel =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return TrackPackage(
    id: 'user_${trip.startMs}',
    nameCn:
        name ??
        (trip.trackName.isNotEmpty ? trip.trackName : '我的赛道 $dateLabel'),
    nameEn: '',
    region: '',
    version: 1,
    source: TrackPackageSource.user,
    sourceDetail: '用户行程导入（GPS 实测轨迹）',
    verification: TrackPackageVerification.pending,
    verificationNote: '用户行程导入：轮廓与起终点取轨迹实测点，弯角 / 分段 / 龙门架待编辑器补录',
    centerline: centerline,
    lengthM: polylineLengthM(centerline).round(),
    publishedLengthM: null,
    start: first,
    finish: last,
    startNote: '行程轨迹首末点（闭合回路时起终点同点）',
    isUserTrack: true,
  );
}

/// 包 → 选赛道用的 TrackInfo（适配器）：
/// - 有经纬度中心线时，用真实中心线归一化成示意图（优先于旧示意）；
/// - 无中心线时回落旧目录条目（仍是示意）；
/// - 目录外的新包合成最小条目（轮廓待补）。
/// 注意：合成的 outline 只是显示用归一化示意，绝不反向写回包里。
TrackInfo trackInfoForPackage(TrackPackage p) {
  if (p.hasCenterline) {
    // 同一包围盒归一化，保证起终点 / 弯角 / 分段点与轮廓对齐。
    final b = _LatLonBounds(p.centerline);
    final outline = p.centerline.map(b.project).toList();
    OutlinePoint? sf;
    if (p.start != null) sf = b.project(p.start!);
    return TrackInfo(
      id: p.id,
      nameCn: p.nameCn,
      nameEn: p.nameEn,
      region: p.region,
      lengthKm: p.lengthKm,
      source: '赛道库数据包',
      outline: outline,
      totalCorners: p.corners.length,
      corners: p.corners
          .map((c) => CornerMark(c.number, b.project(c.point)))
          .toList(),
      startFinishPoint: sf,
      startFinishNote: p.startNote,
      sectorPoints: p.sectorPoints.map(b.project).toList(),
      sectorNote: p.sectorNote,
      layoutSource: p.sourceDetail,
    );
  }
  final catalog = trackById(p.id);
  if (catalog != null) return catalog;
  return TrackInfo(
    id: p.id,
    nameCn: p.nameCn,
    nameEn: p.nameEn,
    region: p.region,
    lengthKm: p.lengthKm,
    source: '赛道库数据包',
    outline: const [],
    totalCorners: p.corners.length,
    layoutSource: p.sourceDetail,
  );
}
