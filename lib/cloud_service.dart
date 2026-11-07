import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'gps_source.dart';
import 'models.dart';
import 'native.dart';

/// 云端二期（腾讯 CloudBase，上海区，PG 模式）。
///
/// 架构：[CloudService] 是唯一入口，管配置、匿名账号、上传队列与
/// 本地持久化；真正调 CloudBase 的活在 [CloudBackend] 后面，测试
/// 用 fake 替掉，绝不联网。
///
/// 后端选型（2026-11-07 已核）：走 CloudBase HTTP API，不用
/// `cloudbase_flutter` SDK。SDK 本身是纯 Dart 代码，但它依赖
/// `shared_preferences`（带 Android 原生插件），其 AAR 不在离线
/// Gradle 镜像里（镜像只有 Flutter 引擎产物，无
/// io/flutter/plugins/*），一旦接入离线构建直接断掉（此前纯 Dart
/// 包的选型正是为了避开这个坑）。本文件只用 dart:io 的
/// HttpClient 调网关，零新增 pub 依赖、零原生插件。
/// HTTP API 形态：认证照抄 cloudbase_flutter 1.2.2 的 SDK 源码
/// （端点、请求头、错误结构）；数据层走 PG 模式 PostgREST
/// （docs.cloudbase.net 的 PostgreSQL HTTP API：base
/// /v1/rdb/rest/{table}，public schema only，JWT 放
/// Authorization Bearer，不带 client_id）；存储上传照抄
/// @cloudbase/js-sdk 3.11.0 的 PG Storage 实现（POST
/// /v1/storages/object/<bucket>/<path>，raw body + x-upsert）。
/// 网关行为以官方文档与 SDK 源码为准。
///
/// 会话持久化：SDK 本身会用 SharedPreferences 存会话
/// （key 为 `credentials_<env>`），但我们没接 SDK，所以手动落盘
/// （cloud_session.json，见 [_persistSession]），跨启动保持同一个
/// 匿名 user id，否则每次
/// 启动换账号、云端行程全变别人的、自己读不到。

/// CloudBase 环境 ID：只从 --dart-define=CLOUDBASE_ENV_ID 读
/// （构建脚本读本地 .cloudbase-env 文件注入，文件不进仓库）。
/// 读不到时云端入口显示“未配置”、上传禁用，不崩。
/// 注意：env ID 是公开的环境标识（出现在请求地址里），不是密钥；
/// 但仍走本地文件注入，不写死在代码里、不进仓库、不进推送清单。
const String cloudBaseEnvId =
    String.fromEnvironment('CLOUDBASE_ENV_ID', defaultValue: '');

/// CloudBase 上海地域网关（region 固定 ap-shanghai；PG 模式与短信
/// 验证码登录目前仅支持上海地域环境）。
String cloudBaseGatewayUrl(String env) =>
    'https://$env.api.tcloudbasegateway.com';

/// PG 模式 trips 表（public schema；PostgREST 自动暴露，
/// 控制台先按 cloudbase/trips-rls.sql 建表 + 跑 RLS）。
const String cloudTripsTable = 'trips';

/// PG 模式轨迹文件桶（控制台 → 云存储 → Bucket 管理先建桶，
/// 见 cloudbase/README.md；对象路径 <user id>/<trip id>.json）。
const String cloudTripsBucket = 'trip-files';

/// PG 模式公开资料表（public schema；控制台先按
/// cloudbase/profiles-public.sql 建表 + 跑 RLS）。
/// 一行 = 一个云端账号的公开资料（昵称 / 简介 / 头像路径）。
const String cloudProfilesTable = 'profiles';

/// PG 模式公开文件桶（控制台 → 云存储 → Bucket 管理先建桶，
/// 名字 public-files；见 cloudbase/profiles-public-steps.md）。
/// 只放公开文件：公开行程的轨迹文件与公开头像；本人可写、他人只读。
/// 私有行程仍走 [cloudTripsBucket]，绝不放进这个桶。
const String cloudPublicBucket = 'public-files';

/// 公开资料昵称 / 简介长度上限（与 profiles 表的 varchar 一致；
/// 保存时超长直接拒绝，不静默截断）。
const int cloudProfileNicknameMaxLength = 32;
const int cloudProfileBioMaxLength = 200;

/// storage_path 的桶前缀约定：公开行存
/// `public-files/<user id>/<trip id>.json`，私有行存
/// `<user id>/<trip id>.json`（不带前缀 = trip-files 私有桶，
/// 与 v1.4.1 已有行兼容）。头像路径同样以前缀区分桶。
String cloudBucketForStoragePath(String storagePath) =>
    storagePath.startsWith('$cloudPublicBucket/')
        ? cloudPublicBucket
        : cloudTripsBucket;

/// storage_path 去掉桶前缀后的对象路径（传给 Storage API 用）。
String cloudObjectPathForStoragePath(String storagePath) =>
    storagePath.startsWith('$cloudPublicBucket/')
        ? storagePath.substring(cloudPublicBucket.length + 1)
        : storagePath;

/// 头像文件扩展名 → Content-Type（未知扩展名按通用二进制算）。
String cloudAvatarContentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}

/// PostgREST 根路径（public schema only，表名直接拼后面）。
const String _postgrestBasePath = '/v1/rdb/rest';

/// 网关返回的业务异常（HTTP 4xx/5xx 或 body 里带 error）。
class CloudBaseApiException implements Exception {
  final String code;
  final String message;
  const CloudBaseApiException(this.code, this.message);

  @override
  String toString() => 'CloudBaseApiException($code): $message';
}

/// v4 UUID（不用 package:uuid，只给 x-request-id / device id 用）。
String _newUuidV4() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// CloudBase 会话（内存 + cloud_session.json 落盘）。
class _CloudSession {
  final String accessToken;
  final String? refreshToken;
  final int? expiresAtMs;
  final String userId;
  final String? userEmail;
  final bool isAnonymous;

  const _CloudSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAtMs,
    required this.userId,
    required this.userEmail,
    required this.isAnonymous,
  });

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAtMs': expiresAtMs,
        'userId': userId,
        'userEmail': userEmail,
        'isAnonymous': isAnonymous,
      };

  static _CloudSession? fromJson(Map<String, dynamic> j) {
    final access = j['accessToken'] as String?;
    final userId = j['userId'] as String?;
    if (access == null || access.isEmpty || userId == null || userId.isEmpty) {
      return null;
    }
    return _CloudSession(
      accessToken: access,
      refreshToken: j['refreshToken'] as String?,
      expiresAtMs: (j['expiresAtMs'] as num?)?.toInt(),
      userId: userId,
      userEmail: j['userEmail'] as String?,
      isAnonymous: (j['isAnonymous'] as bool?) ?? true,
    );
  }

  bool get isExpired {
    final exp = expiresAtMs;
    if (exp == null) return false;
    // 提前 60 秒算过期（与 SDK 的 _isTokenExpired 一致）。
    return DateTime.now().millisecondsSinceEpoch > exp - 60000;
  }
}

/// CloudBase HTTP 网关客户端（dart:io 直调，零第三方依赖）。
///
/// 照抄 cloudbase_flutter 1.2.2 的 CloudBaseHttpClient 行为：
/// 每个请求带 client_id=env 查询参数；Content-Type、
/// Accept-Language、X-SDK-Version、x-device-id、x-request-id
/// 请求头；登录/注册/验证码类公开接口不带 Authorization，其余
/// 带 Bearer <accessToken>；401 时用 refresh token 换票后重试一次。
class _CloudBaseHttp {
  _CloudBaseHttp(this.envId, this.filesDir, {String? baseUrlOverride})
      : _baseUrlOverride = baseUrlOverride;

  final String envId;
  final String filesDir;
  final String? _baseUrlOverride;

  String get _baseUrl =>
      _baseUrlOverride ?? cloudBaseGatewayUrl(envId);

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  _CloudSession? session;

  /// 401 时换票的回调（由后端注入，避免循环依赖）。
  Future<bool> Function()? onRefreshSession;

  String get _deviceIdFile => '$filesDir/cloud_device_id';

  String? _deviceId;

  /// 设备 ID（SDK 每次请求都带 x-device-id；落盘保持稳定）。
  Future<String> _deviceIdValue() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final f = File(_deviceIdFile);
      if (await f.exists()) {
        final saved = (await f.readAsString()).trim();
        if (saved.isNotEmpty) {
          _deviceId = saved;
          return saved;
        }
      }
      final id = _newUuidV4();
      await f.writeAsString(id);
      _deviceId = id;
      return id;
    } catch (_) {
      _deviceId ??= _newUuidV4();
      return _deviceId!;
    }
  }

  /// 无需登录态的公开接口（照抄 SDK 的 _kPublicUnauthenticatedPaths）。
  static const _publicPaths = <String>{
    '/auth/v1/token',
    '/auth/v1/signin',
    '/auth/v1/signin/anonymously',
    '/auth/v1/signin/with/provider',
    '/auth/v1/signin/custom',
    '/auth/v1/signup',
    '/auth/v1/verification',
    '/auth/v1/verification/verify',
    '/auth/v1/provider/uri',
    '/auth/v1/provider/token',
    '/auth/v1/reset',
    '/auth/v1/revoke',
    '/auth/v1/captcha/data',
    '/auth/v1/captcha/data/verify',
  };

  Future<Map<String, dynamic>> post(String path,
      {Object? body, bool auth = true}) async {
    return _request('POST', path, body: body, auth: auth);
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query, bool auth = true}) async {
    return _request('GET', path, query: query, auth: auth);
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Object? body,
      Map<String, String>? query,
      bool auth = true,
      bool allowRetry = true}) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {
      'client_id': envId,
      ...?query,
    });
    final deviceId = await _deviceIdValue();
    HttpClientResponse resp;
    try {
      final req = await _http.openUrl(method, uri).timeout(
            const Duration(seconds: 30),
          );
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept-Language', 'zh-CN');
      req.headers.set('X-SDK-Version', '@cloudbase/flutter-sdk/1.2.2');
      req.headers.set('x-device-id', deviceId);
      req.headers.set('x-request-id', _newUuidV4());
      if (auth && !_publicPaths.contains(path)) {
        final token = session?.accessToken;
        if (token != null && token.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $token');
        }
      }
      if (body != null) req.write(jsonEncode(body));
      resp = await req.close().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const CloudBaseApiException(
          'timeout', '请求超时，请检查网络后重试');
    } on SocketException catch (e) {
      throw CloudBaseApiException('network', '网络不可用：$e');
    }
    final text = await resp.transform(utf8.decoder).join().timeout(
          const Duration(seconds: 30),
        );
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(text);
      data = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map ? decoded.cast<String, dynamic>() : {});
    } catch (_) {
      data = {};
    }
    if (resp.statusCode == 401 && auth && allowRetry) {
      // token 过期：换票后重试一次；换票失败按会话过期处理。
      final refreshed = await onRefreshSession?.call() ?? false;
      if (refreshed) {
        return _request(method, path,
            body: body, query: query, auth: auth, allowRetry: false);
      }
      throw const CloudBaseApiException(
          'session_expired', '登录已过期，请重新登录');
    }
    if (resp.statusCode >= 400) {
      throw CloudBaseApiException(
        _errorCode(data),
        _errorMessage(data, '请求失败（${resp.statusCode}）'),
      );
    }
    final error = data['error'];
    if (error is Map) {
      throw CloudBaseApiException(
        (error['code']?.toString() ?? 'unknown'),
        (error['message']?.toString() ?? '请求失败'),
      );
    }
    if (error is String && error.isNotEmpty) {
      throw CloudBaseApiException('unknown', error);
    }
    return data;
  }

  static String _errorCode(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map && error['code'] != null) {
      return error['code'].toString();
    }
    return (data['code']?.toString() ?? 'unknown');
  }

  static String _errorMessage(Map<String, dynamic> data, String fallback) {
    final error = data['error'];
    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }
    return (data['message']?.toString() ?? data['msg']?.toString() ?? fallback);
  }

  /// PostgREST 请求（PG 模式数据层，base /v1/rdb/rest/{table}）。
  ///
  /// 与认证调用不同：PostgREST 不认 `client_id` 查询参数
  /// （会被当成不存在的列过滤条件而报 400），所以这里不用
  /// [_request]，单独拼 URI；响应体通常是 JSON 数组（insert /
  /// select 都返回 `[...]`），由调用方按数组处理；错误体是
  /// gateway 风格的 `{"code": ..., "message": ...}` 或 PostgREST
  /// 风格的 `{"code": "PGRST...", "message": ...}`。
  /// 401 时换票重试一次（与 [_request] 同款逻辑）。
  Future<dynamic> postgrest(String method, String path,
      {Map<String, String>? query,
      Object? body,
      Map<String, String>? extraHeaders,
      bool auth = true,
      bool allowRetry = true}) async {
    final uri =
        Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final deviceId = await _deviceIdValue();
    HttpClientResponse resp;
    try {
      final req = await _http.openUrl(method, uri).timeout(
            const Duration(seconds: 30),
          );
      if (body != null) req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      req.headers.set('Accept-Language', 'zh-CN');
      req.headers.set('X-SDK-Version', '@cloudbase/flutter-sdk/1.2.2');
      req.headers.set('x-device-id', deviceId);
      req.headers.set('x-request-id', _newUuidV4());
      if (auth) {
        final token = session?.accessToken;
        if (token != null && token.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $token');
        }
      }
      if (extraHeaders != null) {
        for (final e in extraHeaders.entries) {
          req.headers.set(e.key, e.value);
        }
      }
      if (body != null) req.write(jsonEncode(body));
      resp = await req.close().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const CloudBaseApiException(
          'timeout', '请求超时，请检查网络后重试');
    } on SocketException catch (e) {
      throw CloudBaseApiException('network', '网络不可用：$e');
    }
    final text = await resp.transform(utf8.decoder).join().timeout(
          const Duration(seconds: 30),
        );
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = null;
    }
    if (resp.statusCode == 401 && auth && allowRetry) {
      final refreshed = await onRefreshSession?.call() ?? false;
      if (refreshed) {
        return postgrest(method, path,
            query: query,
            body: body,
            extraHeaders: extraHeaders,
            auth: auth,
            allowRetry: false);
      }
      throw const CloudBaseApiException(
          'session_expired', '登录已过期，请重新登录');
    }
    if (resp.statusCode >= 400) {
      final data =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      throw CloudBaseApiException(
        _errorCode(data),
        _errorMessage(data, '请求失败（${resp.statusCode}）'),
      );
    }
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map) {
        throw CloudBaseApiException(
          (error['code']?.toString() ?? 'unknown'),
          (error['message']?.toString() ?? '请求失败'),
        );
      }
      if (error is String && error.isNotEmpty) {
        throw CloudBaseApiException('unknown', error);
      }
    }
    return decoded;
  }

  /// 向 PG Storage API 直传字节（POST
  /// /v1/storages/object/<bucket>/<path>，raw body + x-upsert）。
  ///
  /// PG 模式不走传统模式的 get-objects-upload-info + COS 预签名
  /// 直传：上传经 Storage API 统一入口，RLS（storage.objects
  /// 策略）是唯一闸门，桶必须事先存在（见 cloudbase/README.md）。
  /// 401 时换票重试一次。
  Future<void> postStorageBytes(String path, Uint8List bytes,
      {required String contentType,
      bool upsert = true,
      bool allowRetry = true}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final deviceId = await _deviceIdValue();
    HttpClientResponse resp;
    String text = '';
    try {
      final req = await _http.postUrl(uri).timeout(
            const Duration(seconds: 30),
          );
      req.headers.set('Content-Type', contentType);
      req.headers.set('Content-Length', bytes.length);
      req.headers.set('x-upsert', upsert ? 'true' : 'false');
      req.headers.set('Accept-Language', 'zh-CN');
      req.headers.set('X-SDK-Version', '@cloudbase/flutter-sdk/1.2.2');
      req.headers.set('x-device-id', deviceId);
      req.headers.set('x-request-id', _newUuidV4());
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      req.add(bytes);
      resp = await req.close().timeout(const Duration(minutes: 5));
      text = await resp.transform(utf8.decoder).join().timeout(
            const Duration(seconds: 30),
          );
    } on TimeoutException {
      throw const CloudBaseApiException(
          'timeout', '上传超时，请检查网络后重试');
    } on SocketException catch (e) {
      throw CloudBaseApiException('network', '网络不可用：$e');
    }
    if (resp.statusCode == 401 && allowRetry) {
      final refreshed = await onRefreshSession?.call() ?? false;
      if (refreshed) {
        return postStorageBytes(path, bytes,
            contentType: contentType, upsert: upsert, allowRetry: false);
      }
      throw const CloudBaseApiException(
          'session_expired', '登录已过期，请重新登录');
    }
    if (resp.statusCode >= 400) {
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      throw CloudBaseApiException(
        _errorCode(data),
        _errorMessage(data, '文件上传失败（${resp.statusCode}）'),
      );
    }
  }

  void close() {
    _http.close(force: true);
  }

  /// 从 PG Storage API 直取对象字节（GET
  /// /v1/storages/object/<bucket>/<path>，与上传同一端点）。
  /// 公开桶的对象任何人可读（RLS 公开读策略放行），私有桶的
  /// 对象只放行本人；读不到时抛 CloudBaseApiException，不返回空字节。
  /// 注意：该端点形态按上传端点同款推断，未在真实网关上验证过，
  /// 联调时先核对（见 cloudbase/profiles-public-steps.md 步骤 4）。
  Future<Uint8List> getStorageBytes(String path,
      {bool allowRetry = true}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final deviceId = await _deviceIdValue();
    HttpClientResponse resp;
    try {
      final req = await _http.getUrl(uri).timeout(
            const Duration(seconds: 30),
          );
      req.headers.set('Accept-Language', 'zh-CN');
      req.headers.set('X-SDK-Version', '@cloudbase/flutter-sdk/1.2.2');
      req.headers.set('x-device-id', deviceId);
      req.headers.set('x-request-id', _newUuidV4());
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      resp = await req.close().timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw const CloudBaseApiException(
          'timeout', '下载超时，请检查网络后重试');
    } on SocketException catch (e) {
      throw CloudBaseApiException('network', '网络不可用：$e');
    }
    if (resp.statusCode == 401 && allowRetry) {
      final refreshed = await onRefreshSession?.call() ?? false;
      if (refreshed) {
        return getStorageBytes(path, allowRetry: false);
      }
      throw const CloudBaseApiException(
          'session_expired', '登录已过期，请重新登录');
    }
    if (resp.statusCode >= 400) {
      throw CloudBaseApiException(
          'download_failed', '文件下载失败（${resp.statusCode}）');
    }
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  /// 从 PG Storage API 删一个对象（DELETE
  /// /v1/storages/object/<bucket>/<path>）。
  /// 用途：行程改回仅自己可见时，删掉公开桶里的旧文件。
  /// 注意：该端点形态按上传端点同款推断，未在真实网关上验证过。
  Future<void> deleteStorageObject(String path,
      {bool allowRetry = true}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final deviceId = await _deviceIdValue();
    HttpClientResponse resp;
    try {
      final req = await _http.deleteUrl(uri).timeout(
            const Duration(seconds: 30),
          );
      req.headers.set('Accept-Language', 'zh-CN');
      req.headers.set('X-SDK-Version', '@cloudbase/flutter-sdk/1.2.2');
      req.headers.set('x-device-id', deviceId);
      req.headers.set('x-request-id', _newUuidV4());
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      resp = await req.close().timeout(const Duration(seconds: 30));
      await resp.transform(utf8.decoder).join().timeout(
            const Duration(seconds: 30),
          );
    } on TimeoutException {
      throw const CloudBaseApiException(
          'timeout', '删除超时，请检查网络后重试');
    } on SocketException catch (e) {
      throw CloudBaseApiException('network', '网络不可用：$e');
    }
    if (resp.statusCode == 401 && allowRetry) {
      final refreshed = await onRefreshSession?.call() ?? false;
      if (refreshed) {
        return deleteStorageObject(path, allowRetry: false);
      }
      throw const CloudBaseApiException(
          'session_expired', '登录已过期，请重新登录');
    }
    if (resp.statusCode >= 400) {
      throw CloudBaseApiException(
          'delete_failed', '文件删除失败（${resp.statusCode}）');
    }
  }
}

/// 云端初始化状态（My 页云端卡片与云端页共用）。
enum CloudStatus { uninitialized, unconfigured, ready, error }

extension CloudStatusLabel on CloudStatus {
  String get label => switch (this) {
        CloudStatus.uninitialized => '同步中…',
        CloudStatus.unconfigured => '云端未配置',
        CloudStatus.ready => '已连接',
        CloudStatus.error => '连接失败',
      };
}

/// 上传队列状态（本地持久化，见 cloud_upload_queue.json）。
enum CloudUploadStatus { pending, uploading, done, failed }

extension CloudUploadStatusLabel on CloudUploadStatus {
  String get label => switch (this) {
        CloudUploadStatus.pending => '待上传',
        CloudUploadStatus.uploading => '上传中',
        CloudUploadStatus.done => '已上传',
        CloudUploadStatus.failed => '上传失败',
      };

  static CloudUploadStatus fromKey(String k) =>
      CloudUploadStatus.values.firstWhere((e) => e.name == k,
          orElse: () => CloudUploadStatus.pending);
}

/// 上传队列表项：元数据快照随队列表项一起落盘，重试时不需要
/// 再读行程对象（暂存文件 + 队列表项 = 全部所需）。
/// [isPublic] 是入队时行程的公开标记：公开行程的轨迹文件传
/// public-files 公开桶、trips 行写 is_public = true；私有行程
/// 走 trip-files 私有桶、is_public = false。上传后改公开标记
/// 不改这条快照，走 [CloudService.republishTrip] 重新发布。
class CloudQueueEntry {
  final String tripId;
  final String mode;
  final int startedAtMs;
  final int endedAtMs;
  final double distanceM;
  final int durationS;
  final String source;
  final double maxSpeedKmh;
  final int score;
  final bool isPublic;
  final CloudUploadStatus status;
  final int attempts;
  final String lastError;
  final int updatedAtMs;

  const CloudQueueEntry({
    required this.tripId,
    required this.mode,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.distanceM,
    required this.durationS,
    required this.source,
    required this.maxSpeedKmh,
    required this.score,
    this.isPublic = false,
    required this.status,
    required this.attempts,
    required this.lastError,
    required this.updatedAtMs,
  });

  CloudQueueEntry copyWith({
    CloudUploadStatus? status,
    int? attempts,
    String? lastError,
    int? updatedAtMs,
    bool? isPublic,
  }) =>
      CloudQueueEntry(
        tripId: tripId,
        mode: mode,
        startedAtMs: startedAtMs,
        endedAtMs: endedAtMs,
        distanceM: distanceM,
        durationS: durationS,
        source: source,
        maxSpeedKmh: maxSpeedKmh,
        score: score,
        isPublic: isPublic ?? this.isPublic,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'mode': mode,
        'startedAtMs': startedAtMs,
        'endedAtMs': endedAtMs,
        'distanceM': distanceM,
        'durationS': durationS,
        'source': source,
        'maxSpeedKmh': maxSpeedKmh,
        'score': score,
        'isPublic': isPublic,
        'status': status.name,
        'attempts': attempts,
        'lastError': lastError,
        'updatedAtMs': updatedAtMs,
      };

  static CloudQueueEntry fromJson(Map<String, dynamic> j) =>
      CloudQueueEntry(
        tripId: j['tripId'] as String,
        mode: (j['mode'] as String?) ?? 'car',
        startedAtMs: (j['startedAtMs'] as num?)?.toInt() ?? 0,
        endedAtMs: (j['endedAtMs'] as num?)?.toInt() ?? 0,
        distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
        durationS: (j['durationS'] as num?)?.toInt() ?? 0,
        source: (j['source'] as String?) ?? 'phone',
        maxSpeedKmh: (j['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
        score: (j['score'] as num?)?.toInt() ?? 0,
        isPublic: (j['isPublic'] as bool?) ?? false,
        status:
            CloudUploadStatusLabel.fromKey((j['status'] as String?) ?? ''),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: (j['lastError'] as String?) ?? '',
        updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
      );

  /// trips 表的一行：只存摘要，轨迹点在云存储文件里。
  /// owner 是创建者 user id，RLS 只放行 owner 自己的读写；
  /// is_public = true 的行另有 trips_select_public 公开读策略，
  /// 任何人可读。storage_path 带桶前缀约定（见
  /// [cloudBucketForStoragePath]）：公开行是
  /// `public-files/<user id>/<trip id>.json`，私有行是
  /// `<user id>/<trip id>.json`。
  Map<String, dynamic> toTripRow(String userId, String storagePath) => {
        'owner': userId,
        'mode': mode,
        'started_at': DateTime.fromMillisecondsSinceEpoch(startedAtMs)
            .toUtc()
            .toIso8601String(),
        'ended_at': DateTime.fromMillisecondsSinceEpoch(endedAtMs)
            .toUtc()
            .toIso8601String(),
        'distance_m': distanceM,
        'duration_s': durationS,
        'source': source,
        'max_speed_kmh': maxSpeedKmh,
        'score': score,
        'is_public': isPublic,
        'storage_path': storagePath,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// 云端行程列表的一行（读 trips 表；id 是 bigserial，PostgREST
/// 返回整数，也兼容字符串 _id）。[owner] 是创建者 user id，
/// [isPublic] 是 trips 表的 is_public 列（控制台 SQL 执行前
/// 老行缺该列时按 false 处理）。
class CloudTripRow {
  final String id;
  final String owner;
  final String mode;
  final int startedAtMs;
  final int endedAtMs;
  final double distanceM;
  final int durationS;
  final String source;
  final double maxSpeedKmh;
  final int score;
  final bool isPublic;
  final String storagePath;

  const CloudTripRow({
    required this.id,
    this.owner = '',
    required this.mode,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.distanceM,
    required this.durationS,
    required this.source,
    required this.maxSpeedKmh,
    required this.score,
    this.isPublic = false,
    required this.storagePath,
  });

  static int _parseTime(dynamic v) {
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is num) return v.toInt();
    if (v is String) {
      return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  static CloudTripRow fromJson(Map<String, dynamic> j) => CloudTripRow(
        id: (j['id'] is num)
            ? (j['id'] as num).toString()
            : ((j['id'] as String?) ?? (j['_id'] as String?) ?? ''),
        owner: (j['owner'] as String?) ?? '',
        mode: (j['mode'] as String?) ?? 'car',
        startedAtMs: _parseTime(j['started_at']),
        endedAtMs: _parseTime(j['ended_at']),
        distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0,
        durationS: (j['duration_s'] as num?)?.toInt() ?? 0,
        source: (j['source'] as String?) ?? 'phone',
        maxSpeedKmh: (j['max_speed_kmh'] as num?)?.toDouble() ?? 0,
        score: (j['score'] as num?)?.toInt() ?? 0,
        isPublic: (j['is_public'] as bool?) ?? false,
        storagePath: (j['storage_path'] as String?) ?? '',
      );
}

/// 公开资料（读 profiles 表的一行）。[avatarPath] 是公开桶里的
/// 对象路径（形如 `public-files/<user id>/avatar.jpg`），空 = 未设头像。
/// 注意：profiles 公开读，任何拿到环境 ID 的人都能读到这些字段。
class PublicProfile {
  final String userId;
  final String nickname;
  final String bio;
  final String avatarPath;
  final int updatedAtMs;

  /// v1.5.1 个人资料扩展字段（与 profiles 表新增列对应，见
  /// cloudbase/profiles-v2-fields.sql）：性别（''=未填，'男'/'女'）、
  /// 生日（'yyyy-MM-dd' 或 ''）、行业、座驾品牌、座驾型号。全部
  /// 为公开资料的一部分，随昵称/简介一起同步；缺字段的旧行读回
  /// 时按 '' 处理，不崩。
  final String gender;
  final String birthday;
  final String industry;
  final String vehicleBrand;
  final String vehicleModel;

  const PublicProfile({
    required this.userId,
    this.nickname = '',
    this.bio = '',
    this.avatarPath = '',
    this.updatedAtMs = 0,
    this.gender = '',
    this.birthday = '',
    this.industry = '',
    this.vehicleBrand = '',
    this.vehicleModel = '',
  });

  static int _parseTime(dynamic v) {
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is num) return v.toInt();
    if (v is String) {
      return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  static PublicProfile fromJson(Map<String, dynamic> j) => PublicProfile(
        userId: (j['user_id'] as String?) ?? '',
        nickname: (j['nickname'] as String?) ?? '',
        bio: (j['bio'] as String?) ?? '',
        avatarPath: (j['avatar_path'] as String?) ?? '',
        updatedAtMs: _parseTime(j['updated_at']),
        gender: (j['gender'] as String?) ?? '',
        birthday: (j['birthday'] as String?) ?? '',
        industry: (j['industry'] as String?) ?? '',
        vehicleBrand: (j['vehicle_brand'] as String?) ?? '',
        vehicleModel: (j['vehicle_model'] as String?) ?? '',
      );

  /// profiles 表的一行：user_id 是云端账号 id（auth.uid()），
  /// 不是本机 profile.json 里的 DT-xxxx。
  Map<String, dynamic> toRow() => {
        'user_id': userId,
        'nickname': nickname,
        'bio': bio,
        'avatar_path': avatarPath,
        'updated_at': DateTime.fromMillisecondsSinceEpoch(updatedAtMs)
            .toUtc()
            .toIso8601String(),
        'gender': gender,
        'birthday': birthday,
        'industry': industry,
        'vehicle_brand': vehicleBrand,
        'vehicle_model': vehicleModel,
      };
}

/// 保存公开资料的结果。资料行本身保存失败时 [ok] 为 false；
/// 只有头像上传失败时 [ok] 仍为 true，但 [avatarError] 非空、
/// [message] 会说明头像没同步上（昵称/简介已同步）。
class CloudProfileResult {
  final bool ok;
  final bool notConfigured;
  final String message;
  final String avatarError;
  const CloudProfileResult({
    required this.ok,
    this.notConfigured = false,
    required this.message,
    this.avatarError = '',
  });
}

/// 上传调用结果（调用方只按 ok / notConfigured / message 走，
/// 不猜异常类型）。
class CloudUploadResult {
  final bool ok;
  final bool notConfigured;
  final String message;
  const CloudUploadResult({
    required this.ok,
    this.notConfigured = false,
    required this.message,
  });
}

/// 邮箱注册 / 登录 / 绑定的结果。
///
/// [sessionEstablished]：调用后是否已有可用会话。
/// [needsCode]：需要用户输入邮箱验证码（CloudBase 注册与绑定邮箱
/// 必须先收验证码；验证码 6 位数字、5 分钟有效）。收到 needsCode
/// 后调对应的 verify* 方法完成第二步。
class CloudAuthResult {
  final bool ok;
  final bool notConfigured;
  final bool sessionEstablished;
  final bool needsCode;
  final String message;
  const CloudAuthResult({
    required this.ok,
    this.notConfigured = false,
    this.sessionEstablished = false,
    this.needsCode = false,
    required this.message,
  });
}

/// 邮箱格式（与个人页本地邮箱校验同一正则）。
bool isValidCloudEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

/// 密码长度：CloudBase 用户名密码登录默认最短 6 位。
bool isValidCloudPassword(String password) => password.length >= 6;

/// 把 CloudBase 网关异常翻成中文（调用方直接展示）。
/// 没命中的返回原文，不编造。
String cloudAuthErrorText(Object error) {
  final raw = error is CloudBaseApiException
      ? '${error.code} ${error.message}'
      : error.toString();
  if (raw.contains('Invalid login credentials') ||
      raw.contains('invalid username or password') ||
      raw.contains('用户名或密码')) {
    return '邮箱或密码不对';
  }
  if (raw.contains('verification') &&
      (raw.contains('invalid') ||
          raw.contains('expired') ||
          raw.contains('wrong') ||
          raw.contains('incorrect'))) {
    return '验证码不对或已过期，请重新获取';
  }
  if (raw.contains('User already registered') ||
      raw.contains('already exist') ||
      raw.contains('user already exists')) {
    return '这个邮箱已经注册过，直接登录';
  }
  if (raw.contains('Password should be at least 6 characters')) {
    return '密码至少 6 位';
  }
  if (raw.contains('Unable to validate email address') ||
      raw.contains('invalid email')) {
    return '邮箱格式不对';
  }
  if (raw.contains('rate limit') ||
      raw.contains('too many') ||
      raw.contains('操作太频繁')) {
    return '操作太频繁，稍后再试';
  }
  if (raw.contains('Provider not enabled') ||
      raw.contains('provider is not enabled') ||
      raw.contains('Unsupported provider')) {
    return '这个登录方式还没在控制台启用，请先在控制台开启';
  }
  if (raw.contains('session_expired') ||
      raw.contains('Auth session missing') ||
      raw.contains('No active session')) {
    return '登录已过期，请重新登录';
  }
  if (raw.contains('timeout')) return '请求超时，请检查网络后重试';
  if (raw.contains('network') || raw.contains('SocketException')) {
    return '网络不可用，请检查网络后重试';
  }
  return error is CloudBaseApiException ? error.message : raw;
}

/// CloudBase 后端接口（测试用 fake 替掉，见
/// test/cloud_service_test.dart）。
///
/// 注册与绑定邮箱是两步：先发验证码（signUpWithEmail /
/// linkEmail，返回 needsCode=true），再凭验证码完成
/// （verifySignUpCode / verifyLinkCode）。CloudBase 注册与
/// 改邮箱必须先收验证码，密码登录仍是一步。
/// Google / 微信 OAuth 这期不做（Google OAuth 客户端待 Google
/// 审批，微信要开放平台配置），相关入口只显示“未配置”。
abstract class CloudBackend {
  /// 确保已匿名登录，返回 user id；未登录成功返回 null。
  Future<String?> ensureSignedIn();

  String? get currentUserId;

  /// 上传字节到云存储路径（如 `<user_id>/<trip_id>.json`，
  /// 默认进 trip-files 私有桶）。
  Future<void> uploadBytes(String path, Uint8List bytes);

  /// 上传字节到指定桶的指定对象路径（如公开桶
  /// `public-files` 里的 `<user_id>/<trip_id>.json` 或
  /// `<user_id>/avatar.jpg`）。[contentType] 按文件类型传。
  Future<void> uploadBytesToBucket(
      String bucket, String path, Uint8List bytes, String contentType);

  /// 从指定桶下载对象字节（公开桶任何人可读，私有桶只放行本人）。
  Future<Uint8List> downloadBytes(String bucket, String path);

  /// 删指定桶里的一个对象（行程改回私有后删公开桶旧文件用）。
  Future<void> deleteObject(String bucket, String path);

  /// 往 trips 集合插一条行程文档。
  Future<void> insertTripRow(Map<String, dynamic> row);

  /// 按 storage_path 更新 trips 行（改公开标记 / 搬桶后改
  /// storage_path 用），返回实际改到的行数（0 = 云端没这行）。
  Future<int> updateTripRowByStoragePath(
      String storagePath, Map<String, dynamic> patch);

  /// 读某用户的云端行程（时间倒序）。
  Future<List<Map<String, dynamic>>> listTripRows(String userId);

  /// 读某用户的公开行程（is_public = true，时间倒序）。
  /// 读的是别人的公开行也走这里：RLS 公开读策略放行。
  Future<List<Map<String, dynamic>>> listPublicTripRows(String userId);

  /// 读某用户的公开资料（profiles 表一行），没有返回 null。
  Future<Map<String, dynamic>?> fetchProfileRow(String userId);

  /// 写自己的公开资料（按 user_id upsert：有则更新、无则插入）。
  Future<void> upsertProfileRow(Map<String, dynamic> row);

  /// 当前用户是否匿名（未登录 / 匿名登录都算匿名）。
  bool get isAnonymous;

  /// 当前用户的邮箱（匿名账号为 null）。
  String? get currentUserEmail;

  /// 邮箱注册第一步：发验证码。成功返回 needsCode=true，
  /// 再调 [verifySignUpCode] 完成。
  Future<CloudAuthResult> signUpWithEmail(String email, String password);

  /// 邮箱注册第二步：凭验证码完成注册；邮箱已注册时直接登录。
  Future<CloudAuthResult> verifySignUpCode(String code);

  /// 邮箱密码登录（一步）。
  Future<CloudAuthResult> signInWithEmail(String email, String password);

  /// 匿名账号绑邮箱第一步：发验证码。成功返回 needsCode=true，
  /// 再调 [verifyLinkCode] 完成。CloudBase 的改邮箱接口没有
  /// 密码字段，绑定后账号暂无密码，用邮箱验证码登录（注册页），
  /// 密码以后走邮箱验证码重设流程再设。
  Future<CloudAuthResult> linkEmail(String email);

  /// 匿名账号绑邮箱第二步：凭验证码完成绑定。
  Future<CloudAuthResult> verifyLinkCode(String code);

  /// 退出登录（清本地会话）。
  Future<void> signOut();
}

/// 待完成的邮箱验证码流程（注册 / 绑定共用结构）。
class _PendingVerification {
  final String email;
  final String? password;
  final String verificationId;
  final bool isUser;
  const _PendingVerification({
    required this.email,
    required this.password,
    required this.verificationId,
    required this.isUser,
  });
}

/// 真后端：dart:io 直调 CloudBase HTTP 网关（零第三方依赖）。
class CloudBaseCloudBackend implements CloudBackend {
  CloudBaseCloudBackend({
    required this.envId,
    required this.filesDir,
    String? baseUrlOverride,
  }) : _http = _CloudBaseHttp(envId, filesDir,
            baseUrlOverride: baseUrlOverride) {
    _http.onRefreshSession = _refreshSession;
  }

  final String envId;
  final String filesDir;
  final _CloudBaseHttp _http;

  _CloudSession? _session;
  _PendingVerification? _pendingSignUp;
  _PendingVerification? _pendingLink;
  Future<bool>? _refreshFuture;

  String get _sessionFile => '$filesDir/cloud_session.json';

  static Map<String, dynamic> _dataOf(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return response;
  }

  /// 凭证（access_token / refresh_token / expires_in）+ 用户资料
  /// 合成会话并落盘。
  Future<_CloudSession?> _saveSessionFromCredentials(
      Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null || access.isEmpty) return null;
    var expiresAtMs = _parseExpiresAt(data);
    if (expiresAtMs == null) {
      final expiresIn = (data['expires_in'] as num?)?.toInt();
      if (expiresIn != null) {
        expiresAtMs = DateTime.now().millisecondsSinceEpoch +
            (expiresIn - 30) * 1000;
      }
    }
    _http.session = _CloudSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAtMs: expiresAtMs,
      userId: '',
      userEmail: null,
      isAnonymous: true,
    );
    final user = await _fetchUser();
    if (user == null) return null;
    final session = _CloudSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAtMs: expiresAtMs,
      userId: user.$1,
      userEmail: user.$2,
      isAnonymous: user.$3,
    );
    _session = session;
    _http.session = session;
    await _persistSession(session);
    return session;
  }

  static int? _parseExpiresAt(Map<String, dynamic> data) {
    final v = data['expires_at'];
    if (v is num) {
      // 秒级时间戳与毫秒级时间戳都容：小于 1e12 按秒算。
      final n = v.toInt();
      return n < 1000000000000 ? n * 1000 : n;
    }
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return null;
  }

  /// GET /auth/v1/user/me，返回 (userId, email, isAnonymous)。
  /// user id 取 uid ?? sub ?? id；匿名账号没有邮箱、loginType
  /// 为 anonymous（SDK 的 UserProfile.toUser 同款判定：匿名
  /// 账号的 name 就是 'anonymous'）。
  Future<(String, String?, bool)?> _fetchUser() async {
    try {
      final res = await _http.get('/auth/v1/user/me');
      final data = _dataOf(res);
      final userId = (data['uid'] ?? data['sub'] ?? data['id'])?.toString();
      if (userId == null || userId.isEmpty) return null;
      final email = (data['email'] as String?)?.trim();
      final name = data['name'] as String?;
      final loginType = (data['loginType'] ?? data['login_type']) as String?;
      final isAnonymous = (email == null || email.isEmpty) &&
          (loginType == null ||
              loginType == 'anonymous' ||
              name == 'anonymous' ||
              name == null);
      return (
        userId,
        (email == null || email.isEmpty) ? null : email,
        isAnonymous,
      );
    } catch (_) {
      return null;
    }
  }

  /// 刷新当前会话的用户资料（绑定邮箱后用）。
  Future<void> _refreshUser() async {
    final s = _session;
    if (s == null) return;
    final user = await _fetchUser();
    if (user == null) return;
    final updated = _CloudSession(
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      expiresAtMs: s.expiresAtMs,
      userId: user.$1,
      userEmail: user.$2,
      isAnonymous: user.$3,
    );
    _session = updated;
    _http.session = updated;
    await _persistSession(updated);
  }

  /// 会话落盘：只放本机私有目录（与行程 JSON 同级），不进仓库。
  Future<void> _persistSession(_CloudSession s) async {
    try {
      await File(_sessionFile).writeAsString(jsonEncode(s.toJson()));
    } catch (_) {}
  }

  Future<_CloudSession?> _restoreSession() async {
    try {
      final f = File(_sessionFile);
      if (!await f.exists()) return null;
      final saved =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _CloudSession.fromJson(saved);
    } catch (_) {
      return null;
    }
  }

  /// 用 refresh token 换票（401 重试也走这里；并发只跑一次）。
  Future<bool> _refreshSession() async {
    final ongoing = _refreshFuture;
    if (ongoing != null) return ongoing;
    final fut = _doRefreshSession();
    _refreshFuture = fut;
    try {
      return await fut;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<bool> _doRefreshSession() async {
    final refresh = _session?.refreshToken ?? _http.session?.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _http.post('/auth/v1/token', body: {
        'client_id': envId,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
      });
      final data = _dataOf(res);
      if (data['error'] != null) return false;
      final session = await _saveSessionFromCredentials(data);
      return session != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> ensureSignedIn() async {
    // 先恢复上次的会话：匿名账号跨启动保持同一个 user id，
    // 否则每次启动换账号，云端行程全变“别人的”，自己读不到。
    final saved = await _restoreSession();
    if (saved != null) {
      _session = saved;
      _http.session = saved;
      if (!saved.isExpired) {
        final user = await _fetchUser();
        if (user != null) {
          final updated = _CloudSession(
            accessToken: saved.accessToken,
            refreshToken: saved.refreshToken,
            expiresAtMs: saved.expiresAtMs,
            userId: user.$1,
            userEmail: user.$2,
            isAnonymous: user.$3,
          );
          _session = updated;
          _http.session = updated;
          await _persistSession(updated);
          return user.$1;
        }
      }
      // token 过期或用户拉取失败：换票再试。
      if (await _refreshSession()) return _session?.userId;
    }
    // 没有可用会话：匿名登录。
    try {
      final res = await _http.post('/auth/v1/signin/anonymously', body: {
        'type': 'anonymous',
      });
      final session = await _saveSessionFromCredentials(_dataOf(res));
      return session?.userId;
    } catch (_) {
      return null;
    }
  }

  @override
  String? get currentUserId => _session?.userId ?? _http.session?.userId;

  @override
  bool get isAnonymous =>
      _session?.isAnonymous ?? _http.session?.isAnonymous ?? true;

  @override
  String? get currentUserEmail =>
      _session?.userEmail ?? _http.session?.userEmail;

  @override
  Future<void> uploadBytes(String path, Uint8List bytes) async {
    // 私有行程默认进 trip-files 私有桶（v1.4.1 行为不变）。
    await uploadBytesToBucket(
        cloudTripsBucket, path, bytes, 'application/json');
  }

  @override
  Future<void> uploadBytesToBucket(
      String bucket, String path, Uint8List bytes, String contentType) async {
    // PG 模式：直接 POST 到 Storage API（/v1/storages/object/
    // <bucket>/<path>），raw body + x-upsert；不走传统模式的
    // get-objects-upload-info + COS 预签名直传。
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final encoded =
        clean.split('/').map(Uri.encodeComponent).join('/');
    await _http.postStorageBytes(
      '/v1/storages/object/$bucket/$encoded',
      bytes,
      contentType: contentType,
      upsert: true,
    );
  }

  @override
  Future<Uint8List> downloadBytes(String bucket, String path) async {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final encoded =
        clean.split('/').map(Uri.encodeComponent).join('/');
    return _http.getStorageBytes('/v1/storages/object/$bucket/$encoded');
  }

  @override
  Future<void> deleteObject(String bucket, String path) async {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final encoded =
        clean.split('/').map(Uri.encodeComponent).join('/');
    await _http.deleteStorageObject(
        '/v1/storages/object/$bucket/$encoded');
  }

  String get _tripsPath => '$_postgrestBasePath/$cloudTripsTable';

  String get _profilesPath => '$_postgrestBasePath/$cloudProfilesTable';

  @override
  Future<void> insertTripRow(Map<String, dynamic> row) async {
    // PostgREST：POST 裸 JSON 对象（不是 data 包裹），
    // Prefer: return=representation 让网关回填插入的行。
    await _http.postgrest('POST', _tripsPath,
        body: row,
        extraHeaders: const {'Prefer': 'return=representation'});
  }

  @override
  Future<int> updateTripRowByStoragePath(
      String storagePath, Map<String, dynamic> patch) async {
    // PostgREST：PATCH + storage_path=eq.<路径> 定位行（storage_path
    // 在同一账号下唯一：<user id>/<trip id>.json，公开行带
    // public-files/ 前缀）。RLS update_own 只放行本人改自己的行。
    final res = await _http.postgrest('PATCH', _tripsPath,
        query: {'storage_path': 'eq.$storagePath'},
        body: patch,
        extraHeaders: const {'Prefer': 'return=representation'});
    if (res is List) return res.length;
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> listTripRows(String userId) async {
    // PostgREST：GET + 过滤/排序/分页全在查询参数里；
    // 响应体就是 JSON 数组，不用 EJSON 解码。owner=eq.<uid>
    // 与 RLS 策略（owner = auth.uid()）一致，只读到自己的行。
    final res = await _http.postgrest('GET', _tripsPath, query: {
      'select': '*',
      'owner': 'eq.$userId',
      'order': 'created_at.desc',
      'limit': '50',
    });
    if (res is! List) return [];
    return res
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listPublicTripRows(
      String userId) async {
    // 公开行程：owner=eq.<uid> 且 is_public=eq.true；RLS
    // trips_select_public 放行任何人读公开行。私有行不会返回。
    final res = await _http.postgrest('GET', _tripsPath, query: {
      'select': '*',
      'owner': 'eq.$userId',
      'is_public': 'eq.true',
      'order': 'created_at.desc',
      'limit': '50',
    });
    if (res is! List) return [];
    return res
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileRow(String userId) async {
    // profiles 公开读：任何人可读。没有该用户资料时返回空数组 → null。
    final res = await _http.postgrest('GET', _profilesPath, query: {
      'select': '*',
      'user_id': 'eq.$userId',
      'limit': '1',
    });
    if (res is List && res.isNotEmpty && res.first is Map) {
      return (res.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  @override
  Future<void> upsertProfileRow(Map<String, dynamic> row) async {
    // PostgREST upsert：POST + on_conflict=user_id +
    // Prefer: resolution=merge-duplicates（user_id 是主键，
    // 冲突时按主键合并更新，不插重复行）。
    await _http.postgrest('POST', _profilesPath,
        query: const {'on_conflict': 'user_id'},
        body: row,
        extraHeaders: const {
          'Prefer': 'resolution=merge-duplicates,return=representation',
        });
  }

  @override
  Future<CloudAuthResult> signUpWithEmail(
      String email, String password) async {
    try {
      final res = await _http.post('/auth/v1/verification', body: {
        'email': email,
      });
      final data = _dataOf(res);
      final verificationId = (data['verification_id'] as String?) ?? '';
      if (verificationId.isEmpty) {
        return const CloudAuthResult(
            ok: false, message: '验证码发送失败，请稍后再试');
      }
      _pendingSignUp = _PendingVerification(
        email: email,
        password: password,
        verificationId: verificationId,
        isUser: (data['is_user'] as bool?) ?? false,
      );
      return CloudAuthResult(
        ok: true,
        needsCode: true,
        message: _pendingSignUp!.isUser
            ? '该邮箱已注册，验证码已发送，输入验证码直接登录'
            : '验证码已发送到邮箱，输入 6 位验证码完成注册',
      );
    } on CloudBaseApiException catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    } catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    }
  }

  @override
  Future<CloudAuthResult> verifySignUpCode(String code) async {
    final pending = _pendingSignUp;
    if (pending == null) {
      return const CloudAuthResult(
          ok: false, message: '请重新输入邮箱获取验证码');
    }
    try {
      final verifyRes = await _http.post('/auth/v1/verification/verify',
          body: {
            'verification_id': pending.verificationId,
            'verification_code': code.trim(),
          });
      final verificationToken =
          (_dataOf(verifyRes)['verification_token'] as String?) ?? '';
      if (verificationToken.isEmpty) {
        return const CloudAuthResult(
            ok: false, message: '验证码验证失败，请重新获取');
      }
      if (pending.isUser) {
        // 邮箱已注册：凭验证码直接登录。
        final signRes = await _http.post('/auth/v1/signin', body: {
          'username': pending.email,
          'verification_token': verificationToken,
        });
        final session =
            await _saveSessionFromCredentials(_dataOf(signRes));
        if (session == null) {
          return const CloudAuthResult(
              ok: false, message: '登录失败，请稍后再试');
        }
        _pendingSignUp = null;
        return const CloudAuthResult(
          ok: true,
          sessionEstablished: true,
          message: '登录成功',
        );
      }
      final signUpRes = await _http.post('/auth/v1/signup', body: {
        'email': pending.email,
        'password': pending.password,
        'verification_token': verificationToken,
        'verification_code': code.trim(),
      });
      final session =
          await _saveSessionFromCredentials(_dataOf(signUpRes));
      if (session == null) {
        return const CloudAuthResult(
            ok: false, message: '注册失败，请稍后再试');
      }
      _pendingSignUp = null;
      return const CloudAuthResult(
        ok: true,
        sessionEstablished: true,
        message: '注册成功，已登录',
      );
    } on CloudBaseApiException catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    } catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    }
  }

  @override
  Future<CloudAuthResult> signInWithEmail(
      String email, String password) async {
    try {
      final res = await _http.post('/auth/v1/signin', body: {
        'username': email,
        'password': password,
      });
      final session = await _saveSessionFromCredentials(_dataOf(res));
      if (session == null) {
        return const CloudAuthResult(
            ok: false, message: '登录失败，请稍后再试');
      }
      return const CloudAuthResult(
        ok: true,
        sessionEstablished: true,
        message: '登录成功',
      );
    } on CloudBaseApiException catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    } catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    }
  }

  @override
  Future<CloudAuthResult> linkEmail(String email) async {
    try {
      final res = await _http.post('/auth/v1/verification', body: {
        'email': email,
      });
      final data = _dataOf(res);
      final verificationId = (data['verification_id'] as String?) ?? '';
      if (verificationId.isEmpty) {
        return const CloudAuthResult(
            ok: false, message: '验证码发送失败，请稍后再试');
      }
      _pendingLink = _PendingVerification(
        email: email,
        password: null,
        verificationId: verificationId,
        isUser: false,
      );
      return const CloudAuthResult(
        ok: true,
        needsCode: true,
        message: '验证码已发送到邮箱，输入 6 位验证码完成绑定',
      );
    } on CloudBaseApiException catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    } catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    }
  }

  @override
  Future<CloudAuthResult> verifyLinkCode(String code) async {
    final pending = _pendingLink;
    if (pending == null) {
      return const CloudAuthResult(
          ok: false, message: '请重新输入邮箱获取验证码');
    }
    try {
      await _http.post('/auth/v1/verification/verify', body: {
        'verification_id': pending.verificationId,
        'verification_code': code.trim(),
      });
      await _http.post('/auth/v1/user/basic/edit', body: {
        'email': pending.email,
      });
      await _refreshUser();
      _pendingLink = null;
      return const CloudAuthResult(
        ok: true,
        sessionEstablished: true,
        message: '绑定成功，已升级为邮箱账号；登录时可用邮箱验证码登录',
      );
    } on CloudBaseApiException catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    } catch (e) {
      return CloudAuthResult(ok: false, message: cloudAuthErrorText(e));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _http.post('/auth/v1/revoke', body: {});
    } catch (_) {}
    _session = null;
    _http.session = null;
    _pendingSignUp = null;
    _pendingLink = null;
    try {
      final f = File(_sessionFile);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// GPS 来源 → 云端 source 字段（只认 phone / device）。
/// external 与 mixed 都算 device（至少部分用了外接设备）；
/// phone 与 unknown 算 phone：unknown 是无 provider 信息的
/// 老行程，默认本机记录，不编造 device。
String cloudSourceFor(GpsSource s) => switch (s) {
      GpsSource.external || GpsSource.mixed => 'device',
      _ => 'phone',
    };

/// 云端唯一入口（单例 [CloudService.instance]）。
class CloudService {
  CloudService({CloudBackend? backend, String? filesDir, String? envIdOverride})
      : _backendOverride = backend,
        _filesDirOverride = filesDir,
        _envIdOverride = envIdOverride;

  static final CloudService instance = CloudService();

  final CloudBackend? _backendOverride;
  final String? _filesDirOverride;
  final String? _envIdOverride;

  CloudBackend? _backend;
  String _dir = '';
  CloudStatus _status = CloudStatus.uninitialized;
  String _lastError = '';
  List<CloudQueueEntry> _queue = [];
  final Completer<void> _initialized = Completer<void>();
  bool _initStarted = false;

  /// 账号状态变化计数（登录 / 注册 / 绑定成功时 +1）。
  /// 账号页监听它，状态一变就刷新。
  final ValueNotifier<int> authVersion = ValueNotifier<int>(0);

  void _bumpAuthVersion() {
    authVersion.value++;
  }

  /// 环境 ID 是否已注入。false = 云端未配置，入口只展示、不调接口。
  bool get isConfigured =>
      (_envIdOverride ?? cloudBaseEnvId).isNotEmpty;

  CloudStatus get status => _status;

  String get lastError => _lastError;

  /// init() 完成后再读才准（未完成时为 null）。
  String? get currentUserId => _backend?.currentUserId;

  /// 当前是否匿名账号（未配置 / 未就绪时按匿名算）。
  bool get isAnonymous => _backend?.isAnonymous ?? true;

  /// 当前用户的邮箱（匿名账号为 null）。
  String? get currentUserEmail => _backend?.currentUserEmail;

  /// 匿名 id 截断显示（user id 只露前 8 位）。
  String get displayUserId {
    final id = currentUserId;
    if (id == null || id.isEmpty) return '—';
    return id.length <= 12 ? id : '${id.substring(0, 8)}…';
  }

  /// init() 完成信号（My 页云端卡片等它再刷新一次）。
  Future<void> get initialized => _initialized.future;

  List<CloudQueueEntry> get queue => List.unmodifiable(_queue);

  int get pendingCount => _queue
      .where((e) =>
          e.status == CloudUploadStatus.pending ||
          e.status == CloudUploadStatus.uploading)
      .length;

  int get failedCount =>
      _queue.where((e) => e.status == CloudUploadStatus.failed).length;

  int get doneCount =>
      _queue.where((e) => e.status == CloudUploadStatus.done).length;

  CloudUploadStatus? queueStatusFor(String tripId) {
    for (final e in _queue) {
      if (e.tripId == tripId) return e.status;
    }
    return null;
  }

  String get _queueFile => '$_dir/cloud_upload_queue.json';

  String _stagingFile(String tripId) => '$_dir/cloud_pending/$tripId.json';

  /// 启动时调一次（fire-and-forget，内部全包 try/catch，
  /// 云端挂了不拖住启动）。重复调用返回第一次的 Future。
  Future<void> init() async {
    if (_initStarted) return _initialized.future;
    _initStarted = true;
    try {
      _dir = _filesDirOverride ?? await Native.getFilesDir();
      await _loadQueue();
      if (!isConfigured) {
        _status = CloudStatus.unconfigured;
        return;
      }
      final backend = _backendOverride ??
          CloudBaseCloudBackend(
            envId: _envIdOverride ?? cloudBaseEnvId,
            filesDir: _dir,
          );
      _backend = backend;
      try {
        await backend.ensureSignedIn().timeout(const Duration(seconds: 15));
        _status = CloudStatus.ready;
      } catch (e) {
        _status = CloudStatus.error;
        _lastError = e.toString();
      }
    } catch (e) {
      _status = CloudStatus.error;
      _lastError = e.toString();
    } finally {
      if (!_initialized.isCompleted) _initialized.complete();
    }
  }

  Future<void> _loadQueue() async {
    try {
      final f = File(_queueFile);
      if (!await f.exists()) {
        _queue = [];
        return;
      }
      final list = jsonDecode(await f.readAsString()) as List;
      _queue = list
          .map((e) => CloudQueueEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _queue = [];
    }
  }

  Future<void> _saveQueue() async {
    try {
      await File(_queueFile)
          .writeAsString(jsonEncode(_queue.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void _upsertQueue(CloudQueueEntry entry) {
    final idx = _queue.indexWhere((e) => e.tripId == entry.tripId);
    if (idx >= 0) {
      _queue[idx] = entry;
    } else {
      _queue.insert(0, entry);
    }
  }

  /// 用户在行程详情里点“上传到云端”才调：轨迹序列化为 JSON
  /// 存本地暂存文件，再传云存储，成功后再插 trips 文档。
  /// 未配置时直接返回 notConfigured，不抛错、不写队列。
  Future<CloudUploadResult> enqueueUpload(Trip trip) async {
    await initialized;
    if (!isConfigured) {
      return const CloudUploadResult(
          ok: false, notConfigured: true, message: '云端未配置');
    }
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      return const CloudUploadResult(
          ok: false, message: '云端账号未就绪，请稍后再试');
    }
    final source = cloudSourceFor(classifyGpsSource(
      trip.points.map((p) => p.provider),
    ));
    final bytes = utf8.encode(jsonEncode(trip.toJson()));
    try {
      final staging = File(_stagingFile(trip.id));
      await staging.parent.create(recursive: true);
      await staging.writeAsBytes(bytes);
    } catch (e) {
      return CloudUploadResult(ok: false, message: '暂存轨迹失败：$e');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _upsertQueue(CloudQueueEntry(
      tripId: trip.id,
      mode: trip.mode.name,
      startedAtMs: trip.startMs,
      endedAtMs: trip.endMs,
      distanceM: trip.distanceM,
      durationS: (trip.endMs - trip.startMs) ~/ 1000,
      source: source,
      maxSpeedKmh: trip.maxSpeed * 3.6,
      score: trip.score.round(),
      isPublic: trip.isPublic,
      status: CloudUploadStatus.pending,
      attempts: 0,
      lastError: '',
      updatedAtMs: now,
    ));
    await _saveQueue();
    return _processEntry(trip.id);
  }

  CloudQueueEntry? _entryFor(String tripId) {
    for (final e in _queue) {
      if (e.tripId == tripId) return e;
    }
    return null;
  }

  /// 上传一条队列表项：先传云存储文件，再插 trips 文档。
  /// 公开行程传 public-files 公开桶、行写 is_public = true；
  /// 私有行程传 trip-files 私有桶、is_public = false。
  /// 公开桶尚未在控制台建好时上传失败进 failed + lastError，
  /// 可重试；行程不丢。
  /// 失败留队列（failed + lastError），可重试；不抛错。
  Future<CloudUploadResult> _processEntry(String tripId) async {
    final backend = _backend;
    final userId = currentUserId;
    final entry = _entryFor(tripId);
    if (backend == null || userId == null || entry == null) {
      return const CloudUploadResult(ok: false, message: '云端未就绪');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _upsertQueue(entry.copyWith(
      status: CloudUploadStatus.uploading,
      attempts: entry.attempts + 1,
      updatedAtMs: now,
    ));
    await _saveQueue();
    try {
      final bytes = await File(_stagingFile(tripId)).readAsBytes();
      // storage_path 带桶前缀约定（见 cloudBucketForStoragePath）：
      // 公开行 public-files/<uid>/<trip>.json，私有行 <uid>/<trip>.json。
      final storagePath = entry.isPublic
          ? '$cloudPublicBucket/$userId/$tripId.json'
          : '$userId/$tripId.json';
      final bucket = cloudBucketForStoragePath(storagePath);
      final objectPath = cloudObjectPathForStoragePath(storagePath);
      await backend.uploadBytesToBucket(
          bucket, objectPath, bytes, 'application/json');
      await backend.insertTripRow(entry.toTripRow(userId, storagePath));
      // 写回时用当前队列表项（已含本轮 attempts+1），不要用入队前的旧快照。
      _upsertQueue((_entryFor(tripId) ?? entry).copyWith(
        status: CloudUploadStatus.done,
        lastError: '',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await _saveQueue();
      try {
        await File(_stagingFile(tripId)).delete();
      } catch (_) {}
      return const CloudUploadResult(ok: true, message: '已上传到云端');
    } catch (e) {
      // 写回时用当前队列表项（已含本轮 attempts+1），不要用入队前的旧快照。
      _upsertQueue((_entryFor(tripId) ?? entry).copyWith(
        status: CloudUploadStatus.failed,
        lastError: e.toString(),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await _saveQueue();
      return CloudUploadResult(ok: false, message: '上传失败：$e');
    }
  }

  /// 重试一条失败的队列表项。
  Future<CloudUploadResult> retryEntry(String tripId) async {
    await initialized;
    if (!isConfigured) {
      return const CloudUploadResult(
          ok: false, notConfigured: true, message: '云端未配置');
    }
    final entry = _entryFor(tripId);
    if (entry == null) {
      return const CloudUploadResult(ok: false, message: '队列里没有这条行程');
    }
    if (entry.status != CloudUploadStatus.failed &&
        entry.status != CloudUploadStatus.pending) {
      return const CloudUploadResult(ok: false, message: '这条行程不需要重试');
    }
    return _processEntry(tripId);
  }

  /// 重试全部失败的队列表项（逐条跑，一条失败不堵住后面的）。
  Future<int> retryAllFailed() async {
    await initialized;
    var okCount = 0;
    for (final e in _queue
        .where((e) => e.status == CloudUploadStatus.failed)
        .toList()) {
      final r = await _processEntry(e.tripId);
      if (r.ok) okCount++;
    }
    return okCount;
  }

  /// 读云端行程列表（trips 集合，时间倒序）。未配置 / 未就绪时
  /// 返回空列表，不抛错。
  Future<List<CloudTripRow>> listCloudTrips() async {
    await initialized;
    final backend = _backend;
    final userId = currentUserId;
    if (!isConfigured || backend == null || userId == null) return [];
    try {
      final rows = await backend.listTripRows(userId);
      return rows.map(CloudTripRow.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// 读某用户的公开资料（profiles 表一行）。未配置 / 未就绪 /
  /// 对方没设过资料时返回 null，不抛错。
  Future<PublicProfile?> fetchPublicProfile(String userId) async {
    await initialized;
    final backend = _backend;
    if (!isConfigured || backend == null || userId.isEmpty) return null;
    try {
      final row = await backend.fetchProfileRow(userId);
      if (row == null) return null;
      return PublicProfile.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// 读某用户的公开行程（is_public = true，时间倒序，只含公开行）。
  /// 未配置 / 未就绪 / 对方无公开行程时返回空列表，不抛错。
  Future<List<CloudTripRow>> listPublicTrips(String userId) async {
    await initialized;
    final backend = _backend;
    if (!isConfigured || backend == null || userId.isEmpty) return [];
    try {
      final rows = await backend.listPublicTripRows(userId);
      return rows.map(CloudTripRow.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// 按 storage_path 下文件字节（公开桶 / 私有桶按路径前缀区分）。
  /// 路径为空或下载失败返回 null，不抛错。
  Future<Uint8List?> downloadFileByStoragePath(String storagePath) async {
    await initialized;
    final backend = _backend;
    if (!isConfigured || backend == null || storagePath.isEmpty) {
      return null;
    }
    try {
      return await backend.downloadBytes(
        cloudBucketForStoragePath(storagePath),
        cloudObjectPathForStoragePath(storagePath),
      );
    } catch (_) {
      return null;
    }
  }

  /// 下一条云端行程的轨迹文件字节（行程详情 / 公开行程查看用）。
  /// 公开行的文件在公开桶里，任何人可读；私有行的文件只放行本人。
  /// 下载失败返回 null，不抛错。
  Future<Uint8List?> downloadTripFile(CloudTripRow row) =>
      downloadFileByStoragePath(row.storagePath);

  /// 下公开头像字节（公开资料页用）。头像路径为空或下载失败
  /// 返回 null，不抛错。
  Future<Uint8List?> downloadAvatar(PublicProfile profile) =>
      downloadFileByStoragePath(profile.avatarPath);

  /// 保存自己的公开资料（昵称 / 简介同步到 profiles 表，头像
  /// 传到 public-files 公开桶）。
  ///
  /// 昵称不能为空、昵称最多 32 字、简介最多 200 字，超了直接
  /// 拒绝（本地资料不受影响，调用方先存本机、再调这里同步）。
  /// 头像本地文件不存在 / 没传新头像时沿用云端已有的头像路径，
  /// 不写空覆盖；只有头像上传失败时本次头像不同步（avatarError 非空）。
  /// 头像上传失败不影响资料行保存：昵称/简介照常同步，
  /// 结果里 avatarError 非空、message 说明头像没同步上。
  /// 公开桶尚未在控制台建好时头像上传失败、资料行保存也可能失败
  /// （profiles 表不存在），结果如实返回，不抛错。
  Future<CloudProfileResult> saveProfile({
    required String nickname,
    required String bio,
    String? avatarLocalPath,
    String gender = '',
    String birthday = '',
    String industry = '',
    String vehicleBrand = '',
    String vehicleModel = '',
  }) async {
    await initialized;
    if (!isConfigured) {
      return const CloudProfileResult(
        ok: false,
        notConfigured: true,
        message: '云端未配置，资料只保存在本机',
      );
    }
    final backend = _backend;
    if (backend == null) {
      return const CloudProfileResult(
          ok: false, message: '云端账号未就绪，请稍后再试');
    }
    // v1.5.1 保存失败兜底：之前只读 currentUserId，会话过期或
    // 会话丢失时直接失败（用户反馈点保存弹保存失败）。现先重建
    // 一次会话（恢复已存会话 / 换票 / 匿名登录，与行程上传同款），
    // 仍拿不到 user id 才报错。
    var userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      try {
        userId = await backend
            .ensureSignedIn()
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
    }
    if (userId == null || userId.isEmpty) {
      return const CloudProfileResult(
          ok: false, message: '云端账号未就绪，请稍后再试');
    }
    final name = nickname.trim();
    if (name.isEmpty) {
      return const CloudProfileResult(ok: false, message: '昵称不能为空');
    }
    if (name.length > cloudProfileNicknameMaxLength) {
      return const CloudProfileResult(ok: false, message: '昵称最多 32 个字');
    }
    final intro = bio.trim();
    if (intro.length > cloudProfileBioMaxLength) {
      return const CloudProfileResult(ok: false, message: '简介最多 200 个字');
    }
    var avatarPath = '';
    var avatarError = '';
    final localAvatar = avatarLocalPath;
    if (localAvatar != null && localAvatar.isNotEmpty) {
      try {
        final file = File(localAvatar);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final ext = localAvatar.contains('.')
              ? localAvatar
                  .substring(localAvatar.lastIndexOf('.'))
                  .toLowerCase()
              : '';
          final objectPath = '$userId/avatar$ext';
          await backend.uploadBytesToBucket(cloudPublicBucket, objectPath,
              bytes, cloudAvatarContentType(localAvatar));
          avatarPath = '$cloudPublicBucket/$objectPath';
        }
      } catch (e) {
        // 头像失败不影响资料行：记下来继续保存昵称/简介。
        avatarError = '头像同步失败：$e';
      }
    }
    if (avatarPath.isEmpty) {
      // 本次没传新头像：沿用云端已有的头像路径，不写空覆盖掉它；
      // 读不到旧资料时按未设头像处理。
      try {
        final existing = await backend.fetchProfileRow(userId);
        if (existing != null) {
          avatarPath = (existing['avatar_path'] as String?) ?? '';
        }
      } catch (_) {}
    }
    PublicProfile buildProfile(String uid) => PublicProfile(
          userId: uid,
          nickname: name,
          bio: intro,
          avatarPath: avatarPath,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          gender: gender,
          birthday: birthday,
          industry: industry,
          vehicleBrand: vehicleBrand,
          vehicleModel: vehicleModel,
        );
    try {
      await backend.upsertProfileRow(buildProfile(userId).toRow());
    } on CloudBaseApiException catch (e) {
      // 会话过期导致写失败：postgrest 内已换票重试过一次；这里再
      // 重建一次会话（恢复/换票/匿名登录）后重试一次 upsert，仍
      // 失败才报保存失败。重建后 user id 通常不变（同一匿名账号），
      // 极少数换了新账号时本次头像路径沿用旧值，下次换头像即纠正。
      var retried = false;
      if (e.code == 'session_expired') {
        try {
          final newId = await backend
              .ensureSignedIn()
              .timeout(const Duration(seconds: 15));
          if (newId != null && newId.isNotEmpty) {
            await backend.upsertProfileRow(buildProfile(newId).toRow());
            retried = true;
          }
        } catch (_) {}
      }
      if (!retried) {
        return CloudProfileResult(
            ok: false, message: '公开资料同步失败：$e', avatarError: avatarError);
      }
    } catch (e) {
      return CloudProfileResult(
          ok: false, message: '公开资料同步失败：$e', avatarError: avatarError);
    }
    if (avatarError.isNotEmpty) {
      return CloudProfileResult(
          ok: true,
          message: '昵称、简介已同步到云端；$avatarError',
          avatarError: avatarError);
    }
    return const CloudProfileResult(ok: true, message: '公开资料已同步到云端');
  }

  /// 已上传行程改公开标记后重新发布（个人页 / 详情页切公开时调）。
  ///
  /// 只处理队列里已是 done 的行程：没上传过的行程直接返回提示，
  /// 下次点“上传到云端”时按新标记走对应桶。
  /// 做法：轨迹文件重传到新标记对应的桶，再 PATCH trips 行的
  /// is_public 与 storage_path；改回私有后删掉公开桶里的旧文件
  /// （删失败会在 message 里说明，旧公开文件可能仍可访问）。
  /// 失败不改本地公开标记、不丢队列；成功后更新队列表项的标记。
  Future<CloudUploadResult> republishTrip(Trip trip) async {
    await initialized;
    if (!isConfigured) {
      return const CloudUploadResult(
          ok: false, notConfigured: true, message: '云端未配置');
    }
    final backend = _backend;
    final userId = currentUserId;
    final entry = _entryFor(trip.id);
    if (backend == null || userId == null || entry == null) {
      return const CloudUploadResult(ok: false, message: '云端还没有这条行程，请先上传到云端');
    }
    if (entry.status != CloudUploadStatus.done) {
      return const CloudUploadResult(ok: false, message: '这条行程还没上传成功，公开标记会在下次上传时生效');
    }
    if (entry.isPublic == trip.isPublic) {
      return const CloudUploadResult(ok: true, message: '云端公开状态已是最新');
    }
    final oldStoragePath = entry.isPublic
        ? '$cloudPublicBucket/$userId/${trip.id}.json'
        : '$userId/${trip.id}.json';
    final newStoragePath = trip.isPublic
        ? '$cloudPublicBucket/$userId/${trip.id}.json'
        : '$userId/${trip.id}.json';
    final newBucket = cloudBucketForStoragePath(newStoragePath);
    final bytes = utf8.encode(jsonEncode(trip.toJson()));
    try {
      await backend.uploadBytesToBucket(newBucket,
          cloudObjectPathForStoragePath(newStoragePath), bytes, 'application/json');
    } catch (e) {
      return CloudUploadResult(ok: false, message: '重新发布失败：$e');
    }
    var affected = 0;
    try {
      affected = await backend.updateTripRowByStoragePath(oldStoragePath, {
        'is_public': trip.isPublic,
        'storage_path': newStoragePath,
      });
      if (affected == 0) {
        // 上轮可能已改过 storage_path：按新路径再定位一次。
        affected = await backend.updateTripRowByStoragePath(newStoragePath, {
          'is_public': trip.isPublic,
          'storage_path': newStoragePath,
        });
      }
    } catch (e) {
      return CloudUploadResult(ok: false, message: '云端行程更新失败：$e');
    }
    if (affected == 0) {
      return const CloudUploadResult(
          ok: false, message: '云端找不到这条行程，请重新上传到云端');
    }
    _upsertQueue(entry.copyWith(
      isPublic: trip.isPublic,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    await _saveQueue();
    var deleteNote = '';
    if (oldStoragePath != newStoragePath) {
      try {
        await backend.deleteObject(
          cloudBucketForStoragePath(oldStoragePath),
          cloudObjectPathForStoragePath(oldStoragePath),
        );
      } catch (e) {
        deleteNote = trip.isPublic
            ? ''
            : '；但旧公开文件删除失败，可能仍可访问，请稍后重试';
      }
    }
    return CloudUploadResult(
      ok: true,
      message: trip.isPublic ? '已设为公开，他人打开你的公开资料页可见' : '已改回仅自己可见$deleteNote',
    );
  }

  CloudAuthResult _notConfiguredAuth() => const CloudAuthResult(
        ok: false,
        notConfigured: true,
        message: '云端未配置',
      );

  CloudAuthResult _notReadyAuth() => const CloudAuthResult(
        ok: false,
        message: '云端账号未就绪，请稍后再试',
      );

  /// 邮箱注册第一步：发验证码（成功后调 verifySignUpCode）。
  Future<CloudAuthResult> signUpWithEmail(
      String email, String password) async {
    await initialized;
    if (!isConfigured) return _notConfiguredAuth();
    final backend = _backend;
    if (backend == null) return _notReadyAuth();
    return backend.signUpWithEmail(email.trim(), password);
  }

  /// 邮箱注册第二步：凭验证码完成注册（邮箱已注册时直接登录）。
  Future<CloudAuthResult> verifySignUpCode(String code) async {
    await initialized;
    if (!isConfigured) return _notConfiguredAuth();
    final backend = _backend;
    if (backend == null) return _notReadyAuth();
    final r = await backend.verifySignUpCode(code);
    if (r.ok && r.sessionEstablished) _bumpAuthVersion();
    return r;
  }

  /// 邮箱密码登录（一步）。
  Future<CloudAuthResult> signInWithEmail(
      String email, String password) async {
    await initialized;
    if (!isConfigured) return _notConfiguredAuth();
    final backend = _backend;
    if (backend == null) return _notReadyAuth();
    final r = await backend.signInWithEmail(email.trim(), password);
    if (r.ok && r.sessionEstablished) _bumpAuthVersion();
    return r;
  }

  /// 匿名账号绑邮箱第一步：发验证码（成功后调 verifyLinkCode）。
  /// 绑定后账号暂无密码，登录时用邮箱验证码（注册页）。
  Future<CloudAuthResult> linkEmail(String email) async {
    await initialized;
    if (!isConfigured) return _notConfiguredAuth();
    final backend = _backend;
    if (backend == null) return _notReadyAuth();
    if (currentUserId == null) return _notReadyAuth();
    return backend.linkEmail(email.trim());
  }

  /// 匿名账号绑邮箱第二步：凭验证码完成绑定。
  Future<CloudAuthResult> verifyLinkCode(String code) async {
    await initialized;
    if (!isConfigured) return _notConfiguredAuth();
    final backend = _backend;
    if (backend == null) return _notReadyAuth();
    final r = await backend.verifyLinkCode(code);
    if (r.ok && r.sessionEstablished) _bumpAuthVersion();
    return r;
  }

  /// 退出登录：清本地会话后重新匿名登录，保持“默认匿名”模型。
  /// 邮箱账号下的云端行程仍在原账号下，重新登录可见。
  Future<void> signOut() async {
    await initialized;
    final backend = _backend;
    if (backend == null) return;
    try {
      await backend.signOut();
    } catch (_) {}
    try {
      await backend.ensureSignedIn().timeout(const Duration(seconds: 15));
      _status = CloudStatus.ready;
    } catch (e) {
      _status = CloudStatus.error;
      _lastError = e.toString();
    }
    _bumpAuthVersion();
  }
}
