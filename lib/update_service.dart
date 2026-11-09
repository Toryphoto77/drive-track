import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'native.dart';
import 'sha256.dart';

/// 在线更新框架（v0.1.5：关于页预留并先行接线，为后续正式版准备）。
///
/// 正式版走通检查–下载–安装只改配置，不重写流程：
/// 1) 把正式发布仓库的版本清单地址填进 [UpdateConfig.manifestUrl]；
/// 2) 清单 JSON 须含 versionName（字符串）、versionCode（整数）、
///    apkUrl（新包直链）；可选 notes（更新说明字符串）；
/// 3) [UpdateService.check] 按 versionCode 与当前版比对；
/// 4) 有新版时 [downloadAndInstall] 把 APK 下到缓存目录，再走
///    原生 installApk（FileProvider + ACTION_VIEW，与视频播放 /
///    分享共用同一 FileProvider 配置），由系统安装器完成安装。
///
/// 当前状态：DriveTrack 没有正式发布仓库，[UpdateConfig] 默认
/// 未配置。[check] 在未配置时直接返回 [UpdateCheckStatus.unconfigured]，
/// 关于页如实显示“正式版更新通道待配置”，绝不
/// 伪造“已是最新版”，也不编造下载链接。清单拉取失败时返回
/// error 状态并带上原因，同样不谎称最新。

/// 更新源配置：只改这一处即可接通正式版。
class UpdateConfig {
  /// 版本清单地址；null/空 = 未配置。
  final String? manifestUrl;

  /// v1.0.7：是否走 GitHub Releases 接口（解析 tag_name 与 assets，
  /// 不再走旧的 versionName/versionCode/apkUrl 清单 JSON）。
  final bool githubReleases;

  /// 国内清单优先失败后的回落地址（GitHub Releases 接口）；
  /// 仅 [domestic] 配置使用，null = 无回落。
  final String? fallbackGithubUrl;

  const UpdateConfig(
      {this.manifestUrl, this.githubReleases = false, this.fallbackGithubUrl});

  /// 默认：未配置。
  const UpdateConfig.unconfigured()
      : manifestUrl = null,
        githubReleases = false,
        fallbackGithubUrl = null;

  /// v1.0.7：指向 Toryphoto77/drive-track 的最新 Release。
  /// （2026-11-08 修正：此前误写旧账号仓库；正式 Release 在 Toryphoto77/drive-track。）
  /// 注意：Release 本身由主代理后续走浏览器创建；建好之前接口
  /// 返回 404，检查会如实报失败，不谎称“已是最新版”。
  const UpdateConfig.githubReleases()
      : manifestUrl =
            'https://api.github.com/repos/Toryphoto77/drive-track/releases/latest',
        githubReleases = true,
        fallbackGithubUrl = null;

  /// 国内优先：先拉 jsDelivr 上的 update-manifest.json（国内可直连，
  /// 不走 api.github.com），清单格式沿用旧的
  /// versionName/versionCode/apkUrl；清单拉取失败时才回落到
  /// GitHub Releases 接口（修正后的 Toryphoto77/drive-track）。
  /// 清单里的 apkUrl 是下载间接层：发版流程可把它换成国内
  /// 存储（如 CloudBase 公共 URL）而无需改 App。
  static const String domesticManifestUrl =
      'https://cdn.jsdelivr.net/gh/Toryphoto77/drive-track@main/update-manifest.json';

  const UpdateConfig.domestic()
      : manifestUrl = domesticManifestUrl,
        githubReleases = false,
        fallbackGithubUrl =
            'https://api.github.com/repos/Toryphoto77/drive-track/releases/latest';

  bool get isConfigured => manifestUrl != null && manifestUrl!.trim().isNotEmpty;
}

/// v1.0.7：语义版本比较（1.0.7 > 1.0.6），非数字段按 0 计。
int compareSemver(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

enum UpdateCheckStatus {
  /// 未配置正式源（当前正式版未配置的正常状态，不是错误）。
  unconfigured,

  /// 清单已拉到且 versionCode 不高于当前版。
  upToDate,

  /// 清单已拉到且 versionCode 高于当前版，可下载安装。
  available,

  /// 清单拉取/解析失败（原因在 message 里，不谎称最新）。
  error,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String message;
  final String? remoteVersionName;
  final int? remoteVersionCode;
  final String? downloadUrl;
  final String? notes;

  /// 发布方给出的安装包 SHA-256（小写 hex）；null = 没有可信摘要，
  /// 下载后无法校验完整性（见 [UpdateService.downloadAndInstallChecked]）。
  final String? sha256;

  /// 选中的安装包架构（如 arm64-v8a）。
  final String? abi;

  /// 按优先顺序尝试的下载地址。[downloadUrl] 仍是清单里的规范
  /// 地址（旧测试与旧调用只认它）；新下载逻辑先走这里面的国内源。
  final List<DownloadSource> downloadSources;

  const UpdateCheckResult({
    required this.status,
    required this.message,
    this.remoteVersionName,
    this.remoteVersionCode,
    this.downloadUrl,
    this.notes,
    this.sha256,
    this.abi,
    this.downloadSources = const [],
  });
}

/// 一个可下载的安装包：直链 + 可选 SHA-256 + 可选国内镜像。
///
/// [url] 仍是清单里的 `url` / `apkUrl`（旧客户端只读这一处）。
/// [cdnUrl] / [mirrors] 是同一文件的国内地址，新客户端优先尝试。
class ApkChoice {
  final String abi;
  final String url;
  final String? sha256;
  final String? cdnUrl;
  final List<String> mirrors;
  const ApkChoice(this.abi, this.url, this.sha256,
      {this.cdnUrl, this.mirrors = const []});
}

/// 下载源种类，用来写进度文案。
enum DownloadSourceKind {
  /// 清单里的 cdnUrl / mirrors，或本身就不是 GitHub 的直链。
  cdn,

  /// github.com 的 Release 附件。
  github,

  /// 内置或清单指定的 GitHub Release 代理前缀。
  githubProxy,

  /// 无法归类的直链。
  direct,
}

class DownloadSource {
  final String url;
  final DownloadSourceKind kind;
  const DownloadSource(this.url, this.kind);
}

/// 一次下载尝试的进度。换源时 [restarted] 为 true、[received] 从 0 起。
class DownloadProgress {
  final int received;
  final int? total;
  final DownloadSourceKind kind;
  final int index;
  final int count;
  final double? bytesPerSecond;
  final bool restarted;
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.kind,
    required this.index,
    required this.count,
    required this.bytesPerSecond,
    required this.restarted,
  });
}

/// 国内常用的 GitHub Release 文件代理。只在主地址失败或长时间
/// 几乎没有数据之后才用，且只改写 `github.com/.../releases/download/`。
///
/// 都是第三方前缀（`前缀 + 原始 https URL`），与本仓库无关，可能失效：
/// - `https://ghfast.top/` — ghfast，社区文件加速
/// - `https://gh-proxy.com/` — gh-proxy 反向代理
/// - `https://mirror.ghproxy.com/` — 早期 ghproxy 镜像
///
/// 清单 `"githubProxyFallback": false` 可关掉。
/// 清单 `"githubProxies": ["https://example/"]` 可换成自己的前缀列表
/// （空数组 = 不用任何代理）。
const List<String> kDefaultGithubReleaseProxyPrefixes = [
  'https://ghfast.top/',
  'https://gh-proxy.com/',
  'https://mirror.ghproxy.com/',
];

String? _manifestString(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

List<String> _manifestStringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final e in value)
      if (e is String && e.trim().isNotEmpty) e.trim(),
  ];
}

bool isGithubReleaseUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (uri.host.toLowerCase() != 'github.com') return false;
  return uri.path.contains('/releases/download/');
}

/// `prefix + 原始 GitHub Release URL`。不是 Release 附件时返回 null。
String? githubProxyUrl(String releaseUrl, String prefix) {
  if (!isGithubReleaseUrl(releaseUrl)) return null;
  var p = prefix.trim();
  if (p.isEmpty) return null;
  if (!p.endsWith('/')) p = '$p/';
  return '$p${releaseUrl.trim()}';
}

DownloadSourceKind classifyDownloadUrl(String url) {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  final host = uri?.host.toLowerCase() ?? '';
  if (host == 'github.com' || host.endsWith('.github.com')) {
    return DownloadSourceKind.github;
  }
  if (trimmed.contains('github.com/') && trimmed.contains('/releases/download/')) {
    return DownloadSourceKind.githubProxy;
  }
  if (host == 'ghfast.top' ||
      host == 'gh-proxy.com' ||
      host == 'mirror.ghproxy.com' ||
      host.endsWith('.ghproxy.com')) {
    return DownloadSourceKind.githubProxy;
  }
  if (host.isEmpty) return DownloadSourceKind.direct;
  return DownloadSourceKind.cdn;
}

/// 下载顺序：cdnUrl → mirrors → 清单 url →（GitHub Release 才有）代理。
/// 重复地址只保留第一次。旧客户端不读这些字段，只认 [url]。
List<DownloadSource> buildDownloadSources({
  required String url,
  String? cdnUrl,
  List<String> mirrors = const [],
  bool githubProxyFallback = true,
  List<String>? githubProxies,
}) {
  final ordered = <String>[];
  void add(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty || ordered.contains(t)) return;
    ordered.add(t);
  }

  add(cdnUrl);
  for (final m in mirrors) {
    add(m);
  }
  add(url);
  if (githubProxyFallback && isGithubReleaseUrl(url)) {
    final prefixes = githubProxies ?? kDefaultGithubReleaseProxyPrefixes;
    for (final prefix in prefixes) {
      add(githubProxyUrl(url, prefix));
    }
  }
  return [for (final u in ordered) DownloadSource(u, classifyDownloadUrl(u))];
}

String formatDownloadSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

/// 本 App 发布的三种架构（与构建脚本产物文件名一致）。
const List<String> kPublishedAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

/// 从清单里按设备支持的架构（[deviceAbis]，按系统偏好排序）挑安装包。
///
/// 新清单格式：`apks: {"arm64-v8a": {"url": ..., "sha256": ...}, ...}`；
/// 旧格式只有 `apkUrl`（+ 可选 `sha256`），一直是 arm64-v8a 包，
/// 只在设备支持 arm64-v8a 时才用它——不再把 arm64 包发给 32 位 / x86 设备。
/// 找不到匹配架构返回 null。
ApkChoice _apkWithMirrors({
  required String abi,
  required String url,
  required String? sha256,
  required Map<String, dynamic> json,
  Map<dynamic, dynamic>? entry,
  required String? legacyUrl,
}) {
  final entryCdn = entry == null ? null : _manifestString(entry['cdnUrl']);
  final entryMirrors =
      entry == null ? const <String>[] : _manifestStringList(entry['mirrors']);
  final sameFile = legacyUrl != null && legacyUrl == url;
  final topCdn = _manifestString(json['cdnUrl']);
  final topMirrors = _manifestStringList(json['mirrors']);
  final useTop = entry == null || sameFile;
  return ApkChoice(
    abi,
    url,
    sha256,
    cdnUrl: entryCdn ?? (useTop ? topCdn : null),
    mirrors: [
      ...entryMirrors,
      if (useTop && topCdn != null && topCdn != entryCdn) topCdn,
      if (useTop) ...topMirrors,
    ],
  );
}

/// 清单是否允许在 GitHub 主地址之后再试内置/自定义代理。
/// 缺省为 true。`"githubProxies"` 出现时替换内置列表（可为空）。
bool manifestAllowsGithubProxies(Map<String, dynamic> json) =>
    json['githubProxyFallback'] != false;

List<String>? manifestGithubProxyOverride(Map<String, dynamic> json) {
  if (!json.containsKey('githubProxies')) return null;
  return _manifestStringList(json['githubProxies']);
}

List<DownloadSource> sourcesForChoice(ApkChoice choice, Map<String, dynamic> json) {
  return buildDownloadSources(
    url: choice.url,
    cdnUrl: choice.cdnUrl,
    mirrors: choice.mirrors,
    githubProxyFallback: manifestAllowsGithubProxies(json),
    githubProxies: manifestGithubProxyOverride(json),
  );
}

ApkChoice? selectManifestApk(Map<String, dynamic> json, List<String> deviceAbis) {
  final legacyUrl = _manifestString(json['apkUrl'] ?? json['downloadUrl']);
  final apks = json['apks'];
  if (apks is Map) {
    for (final abi in deviceAbis) {
      final e = apks[abi];
      if (e is Map && e['url'] is String && (e['url'] as String).trim().isNotEmpty) {
        final url = (e['url'] as String).trim();
        return _apkWithMirrors(
          abi: abi,
          url: url,
          sha256: normalizeSha256(e['sha256'] as String?),
          json: json,
          entry: e,
          legacyUrl: legacyUrl,
        );
      }
    }
  }
  if (legacyUrl != null && deviceAbis.contains('arm64-v8a')) {
    return _apkWithMirrors(
      abi: 'arm64-v8a',
      url: legacyUrl,
      sha256: normalizeSha256(json['sha256'] as String?),
      json: json,
      entry: null,
      legacyUrl: legacyUrl,
    );
  }
  return null;
}

/// 从 GitHub Release 附件里按设备架构挑安装包；摘要取 GitHub 提供的
/// `digest`（形如 "sha256:…"），没有则为 null。
ApkChoice? selectGithubApk(List assets, List<String> deviceAbis) {
  for (final abi in deviceAbis) {
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] as String?) ?? '';
      if (name.endsWith('.apk') && name.contains('-$abi')) {
        final url = a['browser_download_url'] as String?;
        if (url == null) continue;
        return ApkChoice(abi, url, normalizeSha256(a['digest'] as String?));
      }
    }
  }
  return null;
}

/// 下载安装结果。[verified] 只有在拿到发布方摘要且与下载内容一致时才为 true。
class UpdateInstallResult {
  final bool ok;
  final bool verified;
  final String message;
  const UpdateInstallResult({required this.ok, required this.verified, required this.message});
}

class UpdateService {
  static const String currentVersionName = '1.5.6';
  static const int currentVersionCode = 61;
  static const String packageName = 'com.chixi.drive_track';
  static const String channelLabel = '正式版';

  /// 更新检查用的直连 HttpClient：findProxy 恒返回 DIRECT，
  /// 不受残留代理环境变量 / 系统代理影响（手机关代理直连国内
  /// CDN 时尤其关键）。调用方注入的 client 原样使用（测试用）。
  static HttpClient _directClient() {
    final c = HttpClient();
    c.findProxy = (_) => 'DIRECT';
    c.connectionTimeout = const Duration(seconds: 15);
    return c;
  }

  static Future<UpdateCheckResult> _checkGithub(
      HttpClient client, String url, List<String> abis) async {
    final req = await client.getUrl(Uri.parse(url)).timeout(_requestTimeout);
    final resp = await req.close().timeout(_requestTimeout);
    final body = await resp.transform(utf8.decoder).join().timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: 'GitHub Release 请求失败，未确认是否有新版',
      );
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String?;
    final remoteName = tag?.replaceFirst(RegExp(r'^v'), '');
    if (remoteName == null || remoteName.isEmpty) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: 'GitHub Release 信息不完整，未确认是否有新版',
      );
    }
    final assets = (json['assets'] as List?) ?? const [];
    final choice = selectGithubApk(assets, abis);
    if (choice == null) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: 'GitHub Release 里没有适合本机架构（${abis.join('/')}）的 APK 附件，未确认是否有新版',
      );
    }
    // Release 不带 versionCode：下载文件名用的合成码仅作文件名，
    // 不参与版本比较；比较只用语义版本 tag。
    final parts =
        remoteName.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final syntheticCode = (parts.isNotEmpty ? parts[0] : 0) * 10000 +
        (parts.length > 1 ? parts[1] : 0) * 100 +
        (parts.length > 2 ? parts[2] : 0);
    if (compareSemver(remoteName, currentVersionName) > 0) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.available,
        message: '发现新版 $remoteName',
        remoteVersionName: remoteName,
        remoteVersionCode: syntheticCode,
        downloadUrl: choice.url,
        notes: json['body'] as String?,
        sha256: choice.sha256,
        abi: choice.abi,
        downloadSources: buildDownloadSources(url: choice.url),
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.upToDate,
      message: '已是最新版（正式版 $remoteName）',
      remoteVersionName: remoteName,
      remoteVersionCode: syntheticCode,
    );
  }

  /// 国内清单（manifest JSON）检查：成功且格式完整时返回结果；
  /// 失败（非 200 / 解析失败 / 字段缺失）返回 null，调用方决定
  /// 是否回落 GitHub，绝不谎称最新。
  static Future<UpdateCheckResult?> _checkManifest(
      HttpClient client, String url, List<String> abis) async {
    final req = await client.getUrl(Uri.parse(url)).timeout(_requestTimeout);
    final resp = await req.close().timeout(_requestTimeout);
    final body = await resp.transform(utf8.decoder).join().timeout(_requestTimeout);
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(body) as Map<String, dynamic>;
    final remoteCode = (json['versionCode'] as num?)?.toInt();
    final remoteName = json['versionName'] as String?;
    final hasAnyApk = json['apks'] is Map ||
        ((json['apkUrl'] ?? json['downloadUrl']) as String?) != null;
    if (remoteCode == null || remoteName == null || !hasAnyApk) {
      return null;
    }
    if (remoteCode > currentVersionCode) {
      final choice = selectManifestApk(json, abis);
      if (choice == null) {
        // 清单有新版但没有本机架构的包：不回落、不装错架构的包。
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          message: '发现新版 $remoteName，但清单里没有适合本机架构（${abis.join('/')}）的安装包',
          remoteVersionName: remoteName,
          remoteVersionCode: remoteCode,
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.available,
        message: '发现新版 $remoteName',
        remoteVersionName: remoteName,
        remoteVersionCode: remoteCode,
        downloadUrl: choice.url,
        notes: json['notes'] as String?,
        sha256: choice.sha256,
        abi: choice.abi,
        downloadSources: sourcesForChoice(choice, json),
      );
    }
    return UpdateCheckResult(
      status: UpdateCheckStatus.upToDate,
      message: '已是最新版（正式版 $remoteName）',
      remoteVersionName: remoteName,
      remoteVersionCode: remoteCode,
    );
  }

  /// 比对清单与当前版。未配置时不发任何网络请求，直接返回未配置。
  /// 国内配置（[UpdateConfig.domestic]）：先拉 jsDelivr 清单，
  /// 失败才回落 GitHub Releases 接口；两路都失败时返回 error，
  /// 不谎称最新。
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// 下载时单次读不到数据的最长等待；超过即判失败（弱网不无限挂起）。
  static const Duration downloadIdleTimeout = Duration(seconds: 30);

  /// 设备支持的 ABI（系统偏好顺序）。取不到时按旧行为只认 arm64-v8a。
  static Future<List<String>> deviceAbis() async {
    try {
      final abis = await Native.supportedAbis();
      if (abis.isNotEmpty) return abis;
    } catch (_) {}
    return const ['arm64-v8a'];
  }

  static Future<UpdateCheckResult> check({
    required UpdateConfig config,
    HttpClient? httpClient,
    List<String>? abis,
  }) async {
    if (!config.isConfigured) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.unconfigured,
        message: '正式版更新通道待配置',
      );
    }
    final deviceAbiList = abis ?? await deviceAbis();
    final client = httpClient ?? _directClient();
    final closeClient = httpClient == null;
    try {
      if (config.githubReleases) {
        return await _checkGithub(client, config.manifestUrl!.trim(), deviceAbiList);
      }
      UpdateCheckResult? manifestResult;
      try {
        manifestResult =
            await _checkManifest(client, config.manifestUrl!.trim(), deviceAbiList);
      } catch (_) {
        manifestResult = null;
      }
      if (manifestResult != null) return manifestResult;
      final fallback = config.fallbackGithubUrl;
      if (fallback != null && fallback.trim().isNotEmpty) {
        try {
          return await _checkGithub(client, fallback.trim(), deviceAbiList);
        } catch (e) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.error,
            message: '更新检查失败：$e，未确认是否有新版',
          );
        }
      }
      return const UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: '更新清单请求失败，未确认是否有新版',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        message: '更新检查失败：$e，未确认是否有新版',
      );
    } finally {
      if (closeClient) client.close();
    }
  }

  /// 兼容旧调用：只返回是否已调起安装器。
  static Future<bool> downloadAndInstall({
    required String url,
    required int remoteVersionCode,
    String? expectedSha256,
    HttpClient? httpClient,
  }) async {
    final r = await downloadAndInstallChecked(
      url: url,
      remoteVersionCode: remoteVersionCode,
      expectedSha256: expectedSha256,
      httpClient: httpClient,
    );
    return r.ok;
  }

  /// 下载 APK 到缓存目录（边下边算 SHA-256），校验后再调原生安装。
  ///
  /// - 有发布方摘要 [expectedSha256]：不一致即删除下载文件、绝不安装，
  ///   并继续试下一个地址（代理有时会回一页 HTML）；
  /// - 没有摘要：照常安装，但结果 verified=false 并明说“未校验”；
  /// - [sources] 为空时只用 [url]。顺序由 [buildDownloadSources] 决定；
  /// - 换源时删掉半截 .part，进度从 0 重计（不同主机不能续传）；
  /// - 除最后一个地址外，若 [stallWindow] 内收到的字节少于
  ///   [stallMinBytes]，放弃该地址改试下一个。最后一个地址只受
  ///   [downloadIdleTimeout] 限制，避免把唯一一条慢链路掐掉。
  static Future<UpdateInstallResult> downloadAndInstallChecked({
    required String url,
    required int remoteVersionCode,
    String? expectedSha256,
    List<DownloadSource>? sources,
    HttpClient? httpClient,
    Future<String> Function()? cacheDir,
    Future<bool> Function(String path)? install,
    void Function(int received, int? total)? onProgress,
    void Function(DownloadProgress progress)? onProgressDetail,
    Duration stallWindow = const Duration(seconds: 8),
    int stallMinBytes = 64 * 1024,
  }) async {
    final expected = normalizeSha256(expectedSha256);
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty && expected == null) {
      return const UpdateInstallResult(
          ok: false, verified: false, message: 'Invalid checksum in update manifest; download not started');
    }
    final plan = (sources != null && sources.isNotEmpty)
        ? sources
        : [DownloadSource(url, classifyDownloadUrl(url))];
    final client = httpClient ?? _directClient();
    final closeClient = httpClient == null;
    UpdateInstallResult? last;
    try {
      for (var i = 0; i < plan.length; i++) {
        final source = plan[i];
        void report(int received, int? total, double? bps) {
          onProgress?.call(received, total);
          onProgressDetail?.call(DownloadProgress(
            received: received,
            total: total,
            kind: source.kind,
            index: i,
            count: plan.length,
            bytesPerSecond: bps,
            restarted: i > 0 && received == 0,
          ));
        }

        report(0, null, null);
        last = await _downloadOne(
          client: client,
          source: source,
          remoteVersionCode: remoteVersionCode,
          expected: expected,
          cacheDir: cacheDir ?? Native.getCacheDir,
          install: install ?? Native.installApk,
          onProgress: report,
          stallCheck: i < plan.length - 1,
          stallWindow: stallWindow,
          stallMinBytes: stallMinBytes,
        );
        if (last.ok) return last;
      }
      return last ??
          const UpdateInstallResult(ok: false, verified: false, message: 'Download failed');
    } finally {
      if (closeClient) client.close();
    }
  }

  static Future<UpdateInstallResult> _downloadOne({
    required HttpClient client,
    required DownloadSource source,
    required int remoteVersionCode,
    required String? expected,
    required Future<String> Function() cacheDir,
    required Future<bool> Function(String path) install,
    required void Function(int received, int? total, double? bps) onProgress,
    required bool stallCheck,
    required Duration stallWindow,
    required int stallMinBytes,
  }) async {
    File? part;
    try {
      final dir = await cacheDir();
      final path = '$dir/update-$remoteVersionCode.apk';
      part = File('$path.part');
      if (await part.exists()) await part.delete();
      final req = await client.getUrl(Uri.parse(source.url)).timeout(_requestTimeout);
      final resp = await req.close().timeout(_requestTimeout);
      if (resp.statusCode != 200) {
        return UpdateInstallResult(
            ok: false, verified: false, message: 'Download failed (HTTP ${resp.statusCode})');
      }
      final hasher = Sha256();
      var received = 0;
      final sink = part.openWrite();
      final clock = Stopwatch()..start();
      var speedMark = Duration.zero;
      var speedBytes = 0;
      var stallMark = Duration.zero;
      var stallBytes = 0;
      double? bps;
      try {
        final total = resp.contentLength >= 0 ? resp.contentLength : null;
        // 非最后一源：静默超过 stallWindow 就换源，不必干等 30 秒。
        final idle = stallCheck ? stallWindow : downloadIdleTimeout;
        await for (final chunk in resp.timeout(idle)) {
          hasher.add(chunk);
          received += chunk.length;
          speedBytes += chunk.length;
          stallBytes += chunk.length;
          sink.add(chunk);
          final now = clock.elapsed;
          if (now - speedMark >= const Duration(milliseconds: 400)) {
            final secs = (now - speedMark).inMicroseconds / 1e6;
            if (secs > 0) bps = speedBytes / secs;
            speedMark = now;
            speedBytes = 0;
          }
          if (stallCheck && now - stallMark >= stallWindow) {
            if (stallBytes < stallMinBytes) {
              throw const _DownloadStalled();
            }
            stallMark = now;
            stallBytes = 0;
          }
          onProgress(received, total, bps);
        }
      } finally {
        await sink.close();
      }
      if (resp.contentLength >= 0 && received != resp.contentLength) {
        await part.delete();
        part = null;
        return const UpdateInstallResult(ok: false, verified: false, message: 'Download incomplete; please retry');
      }
      final actual = hasher.hexDigest();
      if (expected != null && actual != expected) {
        await part.delete();
        part = null;
        return const UpdateInstallResult(
            ok: false, verified: false, message: 'Checksum mismatch; download discarded and not installed');
      }
      final apk = await part.rename(path);
      part = null;
      final launched = await install(apk.path);
      if (!launched) {
        return UpdateInstallResult(ok: false, verified: expected != null, message: 'Could not open the system installer');
      }
      return UpdateInstallResult(
        ok: true,
        verified: expected != null,
        message: expected != null
            ? 'Checksum verified; installer opened'
            : 'No checksum published for this package; integrity NOT verified. Android will still reject a package signed with a different key.',
      );
    } on _DownloadStalled {
      return const UpdateInstallResult(ok: false, verified: false, message: 'Download stalled; trying next source');
    } on TimeoutException {
      return const UpdateInstallResult(ok: false, verified: false, message: 'Download timed out; please retry');
    } catch (e) {
      return UpdateInstallResult(ok: false, verified: false, message: 'Download failed: $e');
    } finally {
      if (part != null) {
        try {
          if (await part.exists()) await part.delete();
        } catch (_) {}
      }
    }
  }
}

class _DownloadStalled implements Exception {
  const _DownloadStalled();
}
