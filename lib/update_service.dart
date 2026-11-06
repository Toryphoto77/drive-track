import 'dart:convert';
import 'dart:io';

import 'native.dart';

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

  const UpdateConfig({this.manifestUrl, this.githubReleases = false});

  /// 默认：未配置。
  const UpdateConfig.unconfigured()
      : manifestUrl = null,
        githubReleases = false;

  /// v1.0.7：指向 wangtao969/drive-track 的最新 Release。
  /// 注意：Release 本身由主代理后续走浏览器创建；建好之前接口
  /// 返回 404，检查会如实报失败，不谎称“已是最新版”。
  const UpdateConfig.githubReleases()
      : manifestUrl =
            'https://api.github.com/repos/wangtao969/drive-track/releases/latest',
        githubReleases = true;

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

  const UpdateCheckResult({
    required this.status,
    required this.message,
    this.remoteVersionName,
    this.remoteVersionCode,
    this.downloadUrl,
    this.notes,
  });
}

class UpdateService {
  static const String currentVersionName = '1.4.0';
  static const int currentVersionCode = 53;
  static const String packageName = 'com.chixi.drive_track';
  static const String channelLabel = '正式版';

  /// 比对清单与当前版。未配置时不发任何网络请求，直接返回未配置。
  static Future<UpdateCheckResult> check({
    required UpdateConfig config,
    HttpClient? httpClient,
  }) async {
    if (!config.isConfigured) {
      return const UpdateCheckResult(
        status: UpdateCheckStatus.unconfigured,
        message: '正式版更新通道待配置',
      );
    }
    final client = httpClient ?? HttpClient();
    final closeClient = httpClient == null;
    try {
      final req = await client.getUrl(Uri.parse(config.manifestUrl!.trim()));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          message: '更新清单请求失败（HTTP ${resp.statusCode}），未确认是否有新版',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (config.githubReleases) {
        final tag = json['tag_name'] as String?;
        final remoteName = tag?.replaceFirst(RegExp(r'^v'), '');
        if (remoteName == null || remoteName.isEmpty) {
          return const UpdateCheckResult(
            status: UpdateCheckStatus.error,
            message: 'GitHub Release 未含 tag_name，未确认是否有新版',
          );
        }
        final assets = (json['assets'] as List?) ?? const [];
        String? apkUrl;
        for (final a in assets) {
          if (a is Map) {
            final name = (a['name'] as String?) ?? '';
            if (name.endsWith('.apk') && name.contains('arm64')) {
              apkUrl = a['browser_download_url'] as String?;
              break;
            }
          }
        }
        if (apkUrl == null) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.error,
            message: 'GitHub Release 里没有 arm64 APK 附件（Release 待主代理创建或补附件），未确认是否有新版',
          );
        }
        // Release 不带 versionCode：下载文件名用的合成码仅作文件名，
        // 不参与版本比较；比较只用语义版本 tag。
        final parts = remoteName.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final syntheticCode = (parts.isNotEmpty ? parts[0] : 0) * 10000 +
            (parts.length > 1 ? parts[1] : 0) * 100 +
            (parts.length > 2 ? parts[2] : 0);
        if (compareSemver(remoteName, currentVersionName) > 0) {
          return UpdateCheckResult(
            status: UpdateCheckStatus.available,
            message: '发现新版 $remoteName',
            remoteVersionName: remoteName,
            remoteVersionCode: syntheticCode,
            downloadUrl: apkUrl,
            notes: json['body'] as String?,
          );
        }
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          message: '已是最新版（正式版 $remoteName）',
          remoteVersionName: remoteName,
          remoteVersionCode: syntheticCode,
        );
      }
      final remoteCode = (json['versionCode'] as num?)?.toInt();
      final remoteName = json['versionName'] as String?;
      final apkUrl = (json['apkUrl'] ?? json['downloadUrl']) as String?;
      if (remoteCode == null || remoteName == null || apkUrl == null) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.error,
          message: '更新清单格式不完整（缺 versionName / versionCode / apkUrl），未确认是否有新版',
        );
      }
      if (remoteCode > currentVersionCode) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.available,
          message: '发现新版 $remoteName（versionCode $remoteCode）',
          remoteVersionName: remoteName,
          remoteVersionCode: remoteCode,
          downloadUrl: apkUrl,
          notes: json['notes'] as String?,
        );
      }
      return UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
        message: '已是最新版（正式版 $remoteName，versionCode $remoteCode）',
        remoteVersionName: remoteName,
        remoteVersionCode: remoteCode,
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

  /// 下载 APK 到缓存目录后调原生安装。返回 true = 已调起系统安装器
  /// （安装本身由用户在系统安装器里确认，本方法不等安装结果）。
  static Future<bool> downloadAndInstall({
    required String url,
    required int remoteVersionCode,
    HttpClient? httpClient,
  }) async {
    final client = httpClient ?? HttpClient();
    final closeClient = httpClient == null;
    try {
      final dir = await Native.getCacheDir();
      final path = '$dir/update-$remoteVersionCode.apk';
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return false;
      final file = File(path);
      final sink = file.openWrite();
      await resp.pipe(sink);
      await sink.close();
      return await Native.installApk(path);
    } catch (_) {
      return false;
    } finally {
      if (closeClient) client.close();
    }
  }
}
