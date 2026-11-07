// 云端二期（腾讯 CloudBase HTTP API）测试。
//
// 全部用 fake 后端，不联网、不读真 key、不碰真 CloudBase 环境；
// 另有一组本地 HttpServer 测试，跑真后端 CloudBaseCloudBackend
// （baseUrlOverride 指到本机），验证端点、请求形态与两步验证码流程。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drive_track/cloud_service.dart';
import 'package:drive_track/gps_source.dart';
import 'package:drive_track/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 CloudBase 后端：只记调用、不联网。
class FakeCloudBackend implements CloudBackend {
  String? userId = 'fake-user-1';
  bool anonymous = true;
  String? email;
  bool failUpload = false;
  bool failInsert = false;
  bool failSignIn = false;
  String? _pendingEmail;
  final List<String> uploadedPaths = [];
  final List<Uint8List> uploadedBytes = [];
  final List<Map<String, dynamic>> insertedRows = [];
  List<Map<String, dynamic>> listedRows = [];

  @override
  Future<String?> ensureSignedIn() async => userId;

  @override
  String? get currentUserId => userId;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get currentUserEmail => email;

  @override
  Future<void> uploadBytes(String path, Uint8List bytes) async {
    if (failUpload) {
      throw const CloudBaseApiException('upload_failed', '模拟上传失败');
    }
    uploadedPaths.add(path);
    uploadedBytes.add(bytes);
  }

  @override
  Future<void> insertTripRow(Map<String, dynamic> row) async {
    if (failInsert) {
      throw const CloudBaseApiException('insert_failed', '模拟写入失败');
    }
    insertedRows.add(row);
  }

  @override
  Future<List<Map<String, dynamic>>> listTripRows(String userId) async =>
      listedRows;

  @override
  Future<CloudAuthResult> signUpWithEmail(
      String email, String password) async {
    _pendingEmail = email;
    return const CloudAuthResult(
      ok: true,
      needsCode: true,
      message: '验证码已发送到邮箱，输入 6 位验证码完成注册',
    );
  }

  @override
  Future<CloudAuthResult> verifySignUpCode(String code) async {
    if (_pendingEmail == null) {
      return const CloudAuthResult(ok: false, message: '请重新输入邮箱获取验证码');
    }
    email = _pendingEmail;
    anonymous = false;
    userId = 'fake-user-2';
    _pendingEmail = null;
    return const CloudAuthResult(
      ok: true,
      sessionEstablished: true,
      message: '注册成功，已登录',
    );
  }

  @override
  Future<CloudAuthResult> signInWithEmail(
      String email, String password) async {
    if (failSignIn) {
      return const CloudAuthResult(ok: false, message: '邮箱或密码不对');
    }
    this.email = email;
    anonymous = false;
    userId = 'fake-user-2';
    return const CloudAuthResult(
      ok: true,
      sessionEstablished: true,
      message: '登录成功',
    );
  }

  @override
  Future<CloudAuthResult> linkEmail(String email) async {
    _pendingEmail = email;
    return const CloudAuthResult(
      ok: true,
      needsCode: true,
      message: '验证码已发送到邮箱，输入 6 位验证码完成绑定',
    );
  }

  @override
  Future<CloudAuthResult> verifyLinkCode(String code) async {
    if (_pendingEmail == null) {
      return const CloudAuthResult(ok: false, message: '请重新输入邮箱获取验证码');
    }
    email = _pendingEmail;
    anonymous = false;
    _pendingEmail = null;
    return const CloudAuthResult(
      ok: true,
      sessionEstablished: true,
      message: '绑定成功，已升级为邮箱账号；登录时可用邮箱验证码登录',
    );
  }

  @override
  Future<void> signOut() async {
    userId = 'fake-user-1';
    anonymous = true;
    email = null;
  }
}

TrackPoint _point(int t, double lat, double lon, double speed) => TrackPoint(
      timeMs: t,
      lat: lat,
      lon: lon,
      alt: 10,
      speed: speed,
      bearing: 0,
      hAcc: 5,
      vAcc: 5,
      speedAcc: 1,
      provider: 'gps',
      longG: 0,
      latG: 0,
      vertG: 0,
      pitch: 0,
      roll: 0,
      heading: 0,
      pressureHpa: 1013,
      calibrated: true,
    );

Trip _sampleTrip({String id = 'trip-1'}) => Trip(
      id: id,
      mode: TripMode.car,
      startMs: DateTime.utc(2026, 11, 7, 10).millisecondsSinceEpoch,
      endMs: DateTime.utc(2026, 11, 7, 11).millisecondsSinceEpoch,
      points: [
        _point(0, 31.20, 121.40, 20),
        _point(1000, 31.21, 121.41, 22),
      ],
      events: [],
      score: 88.5,
      subScores: {},
      scoreReasons: [],
    );

Future<Directory> _tempDir() =>
    Directory.systemTemp.createTemp('cloud-test-');

void main() {
  group('CloudBase 配置与版本', () {
    test('pubspec 版本仍是 1.4.1+54，且不含 supabase / cloudbase_flutter', () {
      final content = File('pubspec.yaml').readAsStringSync();
      expect(content, contains('version: 1.4.1+54'));
      expect(content.toLowerCase(), isNot(contains('supabase')));
      // HTTP API 路由：零新增 pub 依赖，SDK 不进 pubspec。
      expect(content, isNot(contains('cloudbase_flutter')));
    });

    test('两个构建脚本都读 .cloudbase-env 注入 CLOUDBASE_ENV_ID', () {
      for (final name in ['build-apk.sh', 'build-apk-release.sh']) {
        final content = File(name).readAsStringSync();
        expect(content, contains('.cloudbase-env'));
        expect(content, contains('CLOUDBASE_ENV_ID'));
        expect(content, isNot(contains('SUPABASE_ANON_KEY')));
        expect(content, isNot(contains('.supabase-key')));
      }
    });

    test('.gitignore 含 .cloudbase-env；若本地存在，内容须是合法 env ID', () {
      final gitignore = File('.gitignore').readAsStringSync();
      expect(gitignore, contains('.cloudbase-env'));
      final envFile = File('.cloudbase-env');
      if (envFile.existsSync()) {
        final envId = envFile.readAsStringSync();
        expect(envId, matches(RegExp(r'^[a-z0-9][a-z0-9-]*$')));
      }
    });

    test('lib / android 关键文件无 Supabase 残留', () {
      for (final path in [
        'lib/cloud_service.dart',
        'lib/cloud_page.dart',
        'lib/cloud_auth_page.dart',
        'lib/main.dart',
        'lib/native.dart',
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/main/kotlin/com/chixi/drive_track/MainActivity.kt',
        'pubspec.yaml',
      ]) {
        expect(File(path).readAsStringSync().toLowerCase(), isNot(contains('supabase')),
            reason: path);
      }
    });

    test('trips-rls.sql：建表 + RLS + 仅本人读写（含 anon），文档库规则已删', () {
      final sql = File('cloudbase/trips-rls.sql').readAsStringSync();
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.trips'));
      expect(sql, contains('ENABLE ROW LEVEL SECURITY'));
      expect(sql, contains('auth.uid()'));
      expect(sql, contains('TO anon, authenticated'));
      expect(sql, contains('FOR SELECT'));
      expect(sql, contains('FOR INSERT'));
      expect(sql, contains('FOR UPDATE'));
      expect(sql, contains('FOR DELETE'));
      expect(sql, contains('storage.objects'));
      expect(sql, contains("bucket_id = 'trip-files'"));
      expect(sql, contains('storage.foldername(name)'));
      expect(File('cloudbase/security-rules.json').existsSync(), isFalse);
    });

    test('cloudbase/README.md 讲清 trips 表、RLS、桶与匿名/邮箱登录', () {
      final content = File('cloudbase/README.md').readAsStringSync();
      expect(content, contains('trips'));
      expect(content, contains('PG'));
      expect(content, contains('trips-rls.sql'));
      expect(content, contains('trip-files'));
      expect(content, contains('匿名登录'));
      expect(content, contains('邮箱'));
    });
  });

  group('CloudService + FakeCloudBackend', () {
    late Directory dir;
    late FakeCloudBackend fake;

    setUp(() async {
      dir = await _tempDir();
      fake = FakeCloudBackend();
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    CloudService _service({String envId = 'test-env'}) => CloudService(
          backend: fake,
          filesDir: dir.path,
          envIdOverride: envId,
        );

    test('未配置时 init 为 unconfigured，上传直接返回 notConfigured', () async {
      final svc = _service(envId: '');
      await svc.init();
      expect(svc.status, CloudStatus.unconfigured);
      expect(svc.isConfigured, isFalse);
      final r = await svc.enqueueUpload(_sampleTrip());
      expect(r.notConfigured, isTrue);
      expect(r.ok, isFalse);
      expect(svc.queue, isEmpty);
      expect(await svc.listCloudTrips(), isEmpty);
    });

    test('匿名就绪后上传成功：队列 done、路径与文档字段正确、暂存已删', () async {
      final svc = _service();
      await svc.init();
      expect(svc.status, CloudStatus.ready);
      final r = await svc.enqueueUpload(_sampleTrip());
      expect(r.ok, isTrue);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.done);
      expect(fake.uploadedPaths, ['fake-user-1/trip-1.json']);
      final row = fake.insertedRows.single;
      expect(row['owner'], 'fake-user-1');
      expect(row['storage_path'], 'fake-user-1/trip-1.json');
      expect(row['mode'], 'car');
      expect(row['source'], 'phone');
      expect(row['score'], 89);
      expect(
          jsonDecode(utf8.decode(fake.uploadedBytes.single))['id'], 'trip-1');
      expect(
          File('${dir.path}/cloud_pending/trip-1.json').existsSync(), isFalse);
    });

    test('上传失败进 failed，retryEntry 成功，attempts 累加', () async {
      final svc = _service();
      await svc.init();
      fake.failUpload = true;
      final r = await svc.enqueueUpload(_sampleTrip());
      expect(r.ok, isFalse);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.failed);
      final entry = svc.queue.single;
      expect(entry.attempts, 1);
      expect(entry.lastError, isNotEmpty);
      fake.failUpload = false;
      final r2 = await svc.retryEntry('trip-1');
      expect(r2.ok, isTrue);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.done);
      expect(svc.queue.single.attempts, 2);
    });

    test('retryAllFailed 只重试失败项', () async {
      final svc = _service();
      await svc.init();
      fake.failUpload = true;
      await svc.enqueueUpload(_sampleTrip(id: 'trip-1'));
      await svc.enqueueUpload(_sampleTrip(id: 'trip-2'));
      expect(svc.failedCount, 2);
      fake.failUpload = false;
      expect(await svc.retryAllFailed(), 2);
      expect(svc.failedCount, 0);
      expect(svc.doneCount, 2);
    });

    test('注册两步：发码 needsCode，验码后会话建立、authVersion +1', () async {
      final svc = _service();
      await svc.init();
      final before = svc.authVersion.value;
      final step1 = await svc.signUpWithEmail('a@b.com', '123456');
      expect(step1.ok, isTrue);
      expect(step1.needsCode, isTrue);
      final step2 = await svc.verifySignUpCode('123456');
      expect(step2.ok, isTrue);
      expect(step2.sessionEstablished, isTrue);
      expect(svc.authVersion.value, before + 1);
      expect(svc.isAnonymous, isFalse);
      expect(svc.currentUserEmail, 'a@b.com');
    });

    test('邮箱密码登录成功与失败', () async {
      final svc = _service();
      await svc.init();
      final ok = await svc.signInWithEmail('a@b.com', '123456');
      expect(ok.ok, isTrue);
      expect(ok.sessionEstablished, isTrue);
      expect(svc.currentUserEmail, 'a@b.com');
      fake.failSignIn = true;
      final bad = await svc.signInWithEmail('a@b.com', 'wrong');
      expect(bad.ok, isFalse);
      expect(bad.message, '邮箱或密码不对');
    });

    test('匿名绑邮箱两步：发码 needsCode，验码后邮箱已设', () async {
      final svc = _service();
      await svc.init();
      expect(svc.isAnonymous, isTrue);
      final step1 = await svc.linkEmail('a@b.com');
      expect(step1.ok, isTrue);
      expect(step1.needsCode, isTrue);
      final step2 = await svc.verifyLinkCode('123456');
      expect(step2.ok, isTrue);
      expect(step2.sessionEstablished, isTrue);
      expect(svc.currentUserEmail, 'a@b.com');
      expect(svc.isAnonymous, isFalse);
    });

    test('退出登录后回到匿名账号', () async {
      final svc = _service();
      await svc.init();
      await svc.signInWithEmail('a@b.com', '123456');
      expect(svc.isAnonymous, isFalse);
      await svc.signOut();
      expect(svc.isAnonymous, isTrue);
      expect(svc.currentUserEmail, isNull);
      expect(svc.currentUserId, 'fake-user-1');
    });

    test('listCloudTrips 映射 int id 与字段', () async {
      final svc = _service();
      await svc.init();
      fake.listedRows = [
        {
          'id': 7,
          'owner': 'fake-user-1',
          'mode': 'moto',
          'started_at': '2026-11-07T10:00:00.000Z',
          'ended_at': '2026-11-07T11:00:00.000Z',
          'distance_m': 1234.5,
          'duration_s': 3600,
          'source': 'device',
          'max_speed_kmh': 80.0,
          'score': 90,
          'storage_path': 'fake-user-1/trip-1.json',
        },
      ];
      final rows = await svc.listCloudTrips();
      expect(rows, hasLength(1));
      expect(rows.single.id, '7');
      expect(rows.single.mode, 'moto');
      expect(rows.single.distanceM, 1234.5);
      expect(rows.single.source, 'device');
      expect(rows.single.storagePath, 'fake-user-1/trip-1.json');
    });

    test('邮箱与密码校验', () {
      expect(isValidCloudEmail('a@b.com'), isTrue);
      expect(isValidCloudEmail('not-an-email'), isFalse);
      expect(isValidCloudEmail('a@b'), isFalse);
      expect(isValidCloudPassword('123456'), isTrue);
      expect(isValidCloudPassword('12345'), isFalse);
    });

    test('cloudAuthErrorText 映射常见错误', () {
      expect(
          cloudAuthErrorText(const CloudBaseApiException(
              'x', 'Invalid login credentials')),
          '邮箱或密码不对');
      expect(
          cloudAuthErrorText(const CloudBaseApiException(
              'x', 'Provider not enabled')),
          '这个登录方式还没在控制台启用，请先在控制台开启');
      expect(
          cloudAuthErrorText(const CloudBaseApiException(
              'x', 'verification code invalid')),
          '验证码不对或已过期，请重新获取');
    });

    test('cloudSourceFor：外接/混合算 device，其余算 phone', () {
      expect(cloudSourceFor(GpsSource.external), 'device');
      expect(cloudSourceFor(GpsSource.mixed), 'device');
      expect(cloudSourceFor(GpsSource.phone), 'phone');
      expect(cloudSourceFor(GpsSource.unknown), 'phone');
    });

    test('toTripRow 字段齐全：owner、时间 ISO、storage_path', () {
      final entry = CloudQueueEntry(
        tripId: 'trip-1',
        mode: 'car',
        startedAtMs: DateTime.utc(2026, 11, 7, 10).millisecondsSinceEpoch,
        endedAtMs: DateTime.utc(2026, 11, 7, 11).millisecondsSinceEpoch,
        distanceM: 1000,
        durationS: 3600,
        source: 'phone',
        maxSpeedKmh: 72,
        score: 88,
        status: CloudUploadStatus.pending,
        attempts: 0,
        lastError: '',
        updatedAtMs: 0,
      );
      final doc = entry.toTripRow('user-1', 'user-1/trip-1.json');
      expect(doc['owner'], 'user-1');
      expect(doc['mode'], 'car');
      expect(doc['storage_path'], 'user-1/trip-1.json');
      expect(doc['started_at'], '2026-11-07T10:00:00.000Z');
      expect(doc['distance_m'], 1000);
      expect(doc['created_at'], isA<String>());
    });

    test('CloudTripRow.fromJson：缺字段有默认值，id 兼容 int 与 _id', () {
      final row = CloudTripRow.fromJson({'_id': 'doc-9'});
      expect(row.id, 'doc-9');
      expect(row.mode, 'car');
      expect(row.distanceM, 0);
      expect(row.source, 'phone');
      expect(row.storagePath, '');
      expect(CloudTripRow.fromJson({'id': 42}).id, '42');
      expect(CloudTripRow.fromJson({'id': 'abc-1'}).id, 'abc-1');
    });
  });

  group('真后端 CloudBaseCloudBackend（本地 HttpServer）', () {
    late HttpServer server;
    late Directory tmp;
    late CloudBaseCloudBackend backend;
    late Map<String, dynamic> currentUser;
    String lastUploadBody = '';
    String lastUploadPath = '';
    String lastUploadAuth = '';
    String lastUploadUpsert = '';
    String lastUploadContentType = '';
    String lastUploadClientId = '';
    String lastInsertBody = '';
    String lastInsertPrefer = '';
    String lastInsertClientId = '';
    String lastPostgrestAuth = '';
    String lastListOwner = '';
    String lastListOrder = '';
    String lastListSelect = '';
    String lastListLimit = '';
    String lastListClientId = '';
    String lastClientId = '';
    String lastDeviceId = '';

    final anonUser = {
      'uid': 'anon-uid-1',
      'email': '',
      'name': 'anonymous',
      'loginType': 'anonymous',
    };
    final emailUser = {
      'uid': 'user-1',
      'email': 'a@b.com',
      'name': 'a@b.com',
      'loginType': 'email',
    };

    setUp(() async {
      tmp = await _tempDir();
      currentUser = anonUser;
      lastUploadBody = '';
      lastUploadPath = '';
      lastUploadAuth = '';
      lastUploadUpsert = '';
      lastUploadContentType = '';
      lastUploadClientId = '';
      lastInsertBody = '';
      lastInsertPrefer = '';
      lastInsertClientId = '';
      lastPostgrestAuth = '';
      lastListOwner = '';
      lastListOrder = '';
      lastListSelect = '';
      lastListLimit = '';
      lastListClientId = '';
      lastClientId = '';
      lastDeviceId = '';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        final body = await utf8.decoder.bind(req).join();
        lastClientId = req.uri.queryParameters['client_id'] ?? '';
        lastDeviceId = req.headers.value('x-device-id') ?? '';
        void reply(int code, Object m) {
          req.response.statusCode = code;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(m));
          req.response.close();
        }

        if (req.method == 'POST' &&
            path == '/auth/v1/signin/anonymously') {
          reply(200, {
            'access_token': 'tok-anon',
            'refresh_token': 'ref-anon',
            'expires_in': 3600,
          });
        } else if (req.method == 'GET' && path == '/auth/v1/user/me') {
          reply(200, currentUser);
        } else if (req.method == 'POST' &&
            path.startsWith('/v1/storages/object/trip-files/')) {
          lastUploadPath = path;
          lastUploadBody = body;
          lastUploadAuth = req.headers.value('authorization') ?? '';
          lastUploadUpsert = req.headers.value('x-upsert') ?? '';
          lastUploadContentType = req.headers.value('content-type') ?? '';
          lastUploadClientId = req.uri.queryParameters['client_id'] ?? '';
          reply(200, {'Id': 'obj-1', 'Key': 'anon-uid-1/trip-1.json'});
        } else if (req.method == 'POST' && path == '/v1/rdb/rest/trips') {
          lastInsertBody = body;
          lastInsertPrefer = req.headers.value('prefer') ?? '';
          lastInsertClientId = req.uri.queryParameters['client_id'] ?? '';
          lastPostgrestAuth = req.headers.value('authorization') ?? '';
          reply(201, [
            {'id': 7, 'owner': 'anon-uid-1', 'mode': 'car'},
          ]);
        } else if (req.method == 'GET' && path == '/v1/rdb/rest/trips') {
          lastListOwner = req.uri.queryParameters['owner'] ?? '';
          lastListOrder = req.uri.queryParameters['order'] ?? '';
          lastListSelect = req.uri.queryParameters['select'] ?? '';
          lastListLimit = req.uri.queryParameters['limit'] ?? '';
          lastListClientId = req.uri.queryParameters['client_id'] ?? '';
          lastPostgrestAuth = req.headers.value('authorization') ?? '';
          reply(200, [
            {
              'id': 7,
              'owner': 'anon-uid-1',
              'mode': 'car',
              'started_at': '2026-11-07T10:00:00.000Z',
              'ended_at': '2026-11-07T11:00:00.000Z',
              'distance_m': 1234.5,
              'duration_s': 3600,
              'source': 'phone',
              'max_speed_kmh': 80.0,
              'score': 90,
              'storage_path': 'anon-uid-1/trip-1.json',
            },
          ]);
        } else if (req.method == 'POST' && path == '/auth/v1/verification') {
          reply(200, {'verification_id': 'vid-1', 'is_user': false});
        } else if (req.method == 'POST' &&
            path == '/auth/v1/verification/verify') {
          reply(200, {'verification_token': 'vtok-1'});
        } else if (req.method == 'POST' && path == '/auth/v1/signup') {
          currentUser = emailUser;
          reply(200, {
            'access_token': 'tok-mail',
            'refresh_token': 'ref-mail',
            'expires_in': 3600,
          });
        } else if (req.method == 'POST' && path == '/auth/v1/signin') {
          final parsed = jsonDecode(body) as Map<String, dynamic>;
          if (parsed['password'] == 'wrong') {
            reply(400, {
              'error': {
                'code': 'AUTH_INVALID',
                'message': 'Invalid login credentials',
              },
            });
            return;
          }
          currentUser = emailUser;
          reply(200, {
            'access_token': 'tok-mail',
            'refresh_token': 'ref-mail',
            'expires_in': 3600,
          });
        } else if (req.method == 'POST' &&
            path == '/auth/v1/user/basic/edit') {
          currentUser = emailUser;
          reply(200, {});
        } else if (req.method == 'POST' && path == '/auth/v1/revoke') {
          reply(200, {});
        } else {
          req.response.statusCode = 404;
          req.response.close();
        }
      });
      backend = CloudBaseCloudBackend(
        envId: 'test-env',
        filesDir: tmp.path,
        baseUrlOverride: 'http://127.0.0.1:${server.port}',
      );
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('匿名登录：拿到 uid，请求带 client_id 与 x-device-id', () async {
      final uid = await backend.ensureSignedIn();
      expect(uid, 'anon-uid-1');
      expect(backend.currentUserId, 'anon-uid-1');
      expect(backend.isAnonymous, isTrue);
      expect(lastClientId, 'test-env');
      expect(lastDeviceId, isNotEmpty);
      // 会话已落盘：同一目录重建后端，恢复后不再匿名登录。
      final again = CloudBaseCloudBackend(
        envId: 'test-env',
        filesDir: tmp.path,
        baseUrlOverride: 'http://127.0.0.1:${server.port}',
      );
      expect(await again.ensureSignedIn(), 'anon-uid-1');
    });

    test('上传与插行：Storage API 直传 + PostgREST 裸对象，不带 client_id', () async {
      await backend.ensureSignedIn();
      await backend.uploadBytes(
          'anon-uid-1/trip-1.json', Uint8List.fromList([1, 2, 3]));
      expect(lastUploadPath,
          '/v1/storages/object/trip-files/anon-uid-1/trip-1.json');
      expect(lastUploadBody, isNotEmpty);
      expect(lastUploadAuth, 'Bearer tok-anon');
      expect(lastUploadUpsert, 'true');
      expect(lastUploadContentType, contains('application/json'));
      expect(lastUploadClientId, isEmpty);
      await backend.insertTripRow({'owner': 'anon-uid-1', 'mode': 'car'});
      final inserted = jsonDecode(lastInsertBody) as Map<String, dynamic>;
      expect(inserted['owner'], 'anon-uid-1');
      expect(inserted.containsKey('data'), isFalse);
      expect(lastInsertPrefer, contains('return=representation'));
      expect(lastInsertClientId, isEmpty);
      expect(lastPostgrestAuth, 'Bearer tok-anon');
    });

    test('listTripRows：PostgREST 查询带 owner=eq.、排序与分页，解析出 int id', () async {
      await backend.ensureSignedIn();
      final rows = await backend.listTripRows('anon-uid-1');
      expect(lastListOwner, 'eq.anon-uid-1');
      expect(lastListOrder, 'created_at.desc');
      expect(lastListSelect, '*');
      expect(lastListLimit, '50');
      expect(lastListClientId, isEmpty);
      expect(rows, hasLength(1));
      expect(rows.single['id'], 7);
      expect(rows.single['distance_m'], 1234.5);
    });

    test('注册两步走通：发码 → 验码 → signup → 会话建立', () async {
      final step1 = await backend.signUpWithEmail('a@b.com', '123456');
      expect(step1.ok, isTrue);
      expect(step1.needsCode, isTrue);
      final step2 = await backend.verifySignUpCode('123456');
      expect(step2.ok, isTrue);
      expect(step2.sessionEstablished, isTrue);
      expect(backend.currentUserId, 'user-1');
      expect(backend.currentUserEmail, 'a@b.com');
      expect(backend.isAnonymous, isFalse);
    });

    test('邮箱密码登录走通；错密码翻成“邮箱或密码不对”', () async {
      final ok = await backend.signInWithEmail('a@b.com', '123456');
      expect(ok.ok, isTrue);
      expect(ok.sessionEstablished, isTrue);
      expect(backend.currentUserEmail, 'a@b.com');
      final bad = await backend.signInWithEmail('a@b.com', 'wrong');
      expect(bad.ok, isFalse);
      expect(bad.message, '邮箱或密码不对');
    });

    test('绑邮箱两步走通：发码 → 验码 → 改邮箱 → 刷新出邮箱', () async {
      await backend.ensureSignedIn();
      expect(backend.isAnonymous, isTrue);
      final step1 = await backend.linkEmail('a@b.com');
      expect(step1.ok, isTrue);
      expect(step1.needsCode, isTrue);
      final step2 = await backend.verifyLinkCode('123456');
      expect(step2.ok, isTrue);
      expect(step2.sessionEstablished, isTrue);
      expect(backend.currentUserEmail, 'a@b.com');
      expect(backend.isAnonymous, isFalse);
    });

    test('退出登录清会话', () async {
      await backend.ensureSignedIn();
      await backend.signOut();
      expect(backend.currentUserId, isNull);
      expect(File('${tmp.path}/cloud_session.json').existsSync(), isFalse);
    });
  });
}
