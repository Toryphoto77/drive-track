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
  bool failBucketUpload = false;
  String? _pendingEmail;
  final List<String> uploadedPaths = [];
  final List<Uint8List> uploadedBytes = [];
  final List<Map<String, dynamic>> insertedRows = [];
  List<Map<String, dynamic>> listedRows = [];
  // 公开资料与公开行程：按桶+对象路径记文件，按 user_id 记资料行。
  final Map<String, Uint8List> bucketObjects = {};
  final Map<String, Map<String, dynamic>> profiles = {};
  List<Map<String, dynamic>> publicTripRows = [];

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
    await uploadBytesToBucket(
        cloudTripsBucket, path, bytes, 'application/json');
  }

  @override
  Future<void> uploadBytesToBucket(
      String bucket, String path, Uint8List bytes, String contentType) async {
    if (failUpload) {
      throw const CloudBaseApiException('upload_failed', '模拟上传失败');
    }
    if (bucket == cloudPublicBucket && failBucketUpload) {
      throw const CloudBaseApiException(
          'bucket_missing', '模拟公开桶不存在');
    }
    bucketObjects['$bucket/$path'] = bytes;
    uploadedPaths.add(path);
    uploadedBytes.add(bytes);
  }

  @override
  Future<Uint8List> downloadBytes(String bucket, String path) async {
    final bytes = bucketObjects['$bucket/$path'];
    if (bytes == null) {
      throw const CloudBaseApiException('download_failed', '模拟文件不存在');
    }
    return bytes;
  }

  @override
  Future<void> deleteObject(String bucket, String path) async {
    bucketObjects.remove('$bucket/$path');
  }

  @override
  Future<void> insertTripRow(Map<String, dynamic> row) async {
    if (failInsert) {
      throw const CloudBaseApiException('insert_failed', '模拟写入失败');
    }
    insertedRows.add(row);
  }

  @override
  Future<int> updateTripRowByStoragePath(
      String storagePath, Map<String, dynamic> patch) async {
    var count = 0;
    for (final row in insertedRows) {
      if (row['storage_path'] == storagePath) {
        row.addAll(patch);
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<Map<String, dynamic>>> listTripRows(String userId) async =>
      listedRows;

  @override
  Future<List<Map<String, dynamic>>> listPublicTripRows(
      String userId) async {
    return publicTripRows
        .where((r) =>
            r['owner'] == userId && (r['is_public'] as bool? ?? false))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileRow(String userId) async =>
      profiles[userId];

  @override
  Future<void> upsertProfileRow(Map<String, dynamic> row) async {
    profiles[(row['user_id'] as String?) ?? ''] =
        Map<String, dynamic>.from(row);
  }

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

Trip _sampleTrip({String id = 'trip-1', bool isPublic = false}) => Trip(
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
      isPublic: isPublic,
    );

Future<Directory> _tempDir() =>
    Directory.systemTemp.createTemp('cloud-test-');

void main() {
  group('CloudBase 配置与版本', () {
    test('pubspec 版本仍是 1.5.1+56，且不含 supabase / cloudbase_flutter', () {
      final content = File('pubspec.yaml').readAsStringSync();
      expect(content, contains('version: 1.5.1+56'));
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

  group('公开资料与公开行程', () {
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

    test('profiles-public.sql：建表 + RLS + is_public 列 + 公开桶策略', () {
      final sql = File('cloudbase/profiles-public.sql').readAsStringSync();
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.profiles'));
      expect(sql, contains('user_id varchar(64) PRIMARY KEY'));
      expect(sql, contains('nickname varchar(32)'));
      expect(sql, contains('bio varchar(200)'));
      expect(sql, contains('avatar_path text'));
      expect(sql, contains('updated_at timestamptz'));
      expect(sql, contains('profiles_select_public'));
      expect(sql, contains('profiles_insert_own'));
      expect(sql, contains('profiles_update_own'));
      expect(sql, contains('profiles_delete_own'));
      expect(sql, contains('ADD COLUMN IF NOT EXISTS is_public'));
      expect(sql, contains('trips_select_public'));
      expect(sql, contains('USING (is_public = true)'));
      expect(sql, contains("bucket_id = 'public-files'"));
      expect(sql, contains('public_files_select_public'));
      expect(sql, contains('public_files_insert_own'));
      expect(sql, contains('TO anon, authenticated'));
      expect(File('cloudbase/profiles-public-steps.md').existsSync(),
          isTrue);
      final steps =
          File('cloudbase/profiles-public-steps.md').readAsStringSync();
      expect(steps, contains('public-files'));
      expect(steps, contains('profiles-public.sql'));
      expect(steps, contains('is_public'));
      final readme = File('cloudbase/README.md').readAsStringSync();
      expect(readme, contains('public-files'));
      expect(readme, contains('profiles-public-steps.md'));
    });

    test('storage_path 桶前缀约定与头像 Content-Type', () {
      expect(cloudBucketForStoragePath('public-files/u1/t1.json'),
          cloudPublicBucket);
      expect(cloudBucketForStoragePath('u1/t1.json'), cloudTripsBucket);
      expect(cloudObjectPathForStoragePath('public-files/u1/t1.json'),
          'u1/t1.json');
      expect(cloudObjectPathForStoragePath('u1/t1.json'), 'u1/t1.json');
      expect(cloudAvatarContentType('a.jpg'), 'image/jpeg');
      expect(cloudAvatarContentType('a.PNG'), 'image/png');
      expect(cloudAvatarContentType('a.webp'), 'image/webp');
      expect(cloudAvatarContentType('a.bin'), 'application/octet-stream');
    });

    test('PublicProfile fromJson 缺字段有默认值，toRow 字段齐全', () {
      final p = PublicProfile.fromJson({'user_id': 'u1'});
      expect(p.userId, 'u1');
      expect(p.nickname, '');
      expect(p.bio, '');
      expect(p.avatarPath, '');
      final row = PublicProfile(
        userId: 'u1',
        nickname: '柴西',
        bio: 'hello',
        avatarPath: 'public-files/u1/avatar.jpg',
        updatedAtMs:
            DateTime.utc(2026, 11, 7, 10).millisecondsSinceEpoch,
      ).toRow();
      expect(row['user_id'], 'u1');
      expect(row['nickname'], '柴西');
      expect(row['avatar_path'], 'public-files/u1/avatar.jpg');
      expect(row['updated_at'], '2026-11-07T10:00:00.000Z');
    });

    test('CloudTripRow fromJson：owner 与 is_public 有默认值', () {
      final row = CloudTripRow.fromJson({'id': 7});
      expect(row.id, '7');
      expect(row.owner, '');
      expect(row.isPublic, isFalse);
      final pub = CloudTripRow.fromJson({
        'id': 8,
        'owner': 'u2',
        'is_public': true,
        'storage_path': 'public-files/u2/trip-9.json',
      });
      expect(pub.owner, 'u2');
      expect(pub.isPublic, isTrue);
      expect(pub.storagePath, 'public-files/u2/trip-9.json');
    });

    test('CloudQueueEntry isPublic 落盘往返，toTripRow 带 is_public', () {
      final entry = CloudQueueEntry(
        tripId: 'trip-1',
        mode: 'car',
        startedAtMs: 0,
        endedAtMs: 3600000,
        distanceM: 1000,
        durationS: 3600,
        source: 'phone',
        maxSpeedKmh: 72,
        score: 88,
        isPublic: true,
        status: CloudUploadStatus.pending,
        attempts: 0,
        lastError: '',
        updatedAtMs: 0,
      );
      expect(
          CloudQueueEntry.fromJson(entry.toJson()).isPublic, isTrue);
      expect(
          CloudQueueEntry.fromJson({'tripId': 't'}).isPublic, isFalse);
      final row = entry.toTripRow('user-1', 'public-files/user-1/trip-1.json');
      expect(row['is_public'], isTrue);
      expect(row['storage_path'], 'public-files/user-1/trip-1.json');
    });

    test('saveProfile 成功：昵称/简介写 profiles 表，无头像时 avatar_path 为空', () async {
      final svc = _service();
      await svc.init();
      final r = await svc.saveProfile(nickname: '柴西', bio: 'hello');
      expect(r.ok, isTrue);
      expect(r.avatarError, isEmpty);
      final saved = fake.profiles['fake-user-1']!;
      expect(saved['nickname'], '柴西');
      expect(saved['bio'], 'hello');
      expect(saved['avatar_path'], '');
      expect(saved['updated_at'], isA<String>());
      expect(await svc.fetchPublicProfile('fake-user-1'), isNotNull);
      expect(
          (await svc.fetchPublicProfile('fake-user-1'))!.nickname, '柴西');
      expect(await svc.fetchPublicProfile('nobody'), isNull);
    });

    test('saveProfile 校验：空昵称 / 超长昵称 / 超长简介直接拒绝', () async {
      final svc = _service();
      await svc.init();
      expect((await svc.saveProfile(nickname: '  ', bio: '')).ok, isFalse);
      expect(
          (await svc.saveProfile(
                  nickname: '昵' * 33, bio: '')).ok,
          isFalse);
      expect(
          (await svc.saveProfile(
                  nickname: '柴西', bio: '简' * 201)).ok,
          isFalse);
      expect(fake.profiles, isEmpty);
    });

    test('saveProfile 带头像：头像进公开桶，资料行记带前缀的头像路径', () async {
      final svc = _service();
      await svc.init();
      final avatar = File('${dir.path}/avatar.jpg');
      await avatar.writeAsBytes([1, 2, 3]);
      final r = await svc.saveProfile(
          nickname: '柴西', bio: '', avatarLocalPath: avatar.path);
      expect(r.ok, isTrue);
      expect(fake.bucketObjects['public-files/fake-user-1/avatar.jpg'],
          [1, 2, 3]);
      expect(fake.profiles['fake-user-1']!['avatar_path'],
          'public-files/fake-user-1/avatar.jpg');
    });

    test('saveProfile 头像失败不影响资料行：ok 仍为 true，avatarError 非空', () async {
      final svc = _service();
      await svc.init();
      final avatar = File('${dir.path}/avatar.jpg');
      await avatar.writeAsBytes([1, 2, 3]);
      fake.failBucketUpload = true;
      final r = await svc.saveProfile(
          nickname: '柴西', bio: 'hello', avatarLocalPath: avatar.path);
      expect(r.ok, isTrue);
      expect(r.avatarError, isNotEmpty);
      expect(r.message, contains('头像'));
      expect(fake.profiles['fake-user-1']!['nickname'], '柴西');
      expect(fake.profiles['fake-user-1']!['avatar_path'], '');
    });

    test('saveProfile 没传新头像时沿用云端已有头像路径', () async {
      final svc = _service();
      await svc.init();
      final avatar = File('${dir.path}/avatar.jpg');
      await avatar.writeAsBytes([1, 2, 3]);
      await svc.saveProfile(
          nickname: '柴西', bio: '', avatarLocalPath: avatar.path);
      final r = await svc.saveProfile(nickname: '柴西二', bio: 'new');
      expect(r.ok, isTrue);
      expect(fake.profiles['fake-user-1']!['avatar_path'],
          'public-files/fake-user-1/avatar.jpg');
    });

    test('saveProfile 扩展字段：性别/生日/行业/座驾品牌型号写 profiles 表', () async {
      final svc = _service();
      await svc.init();
      final r = await svc.saveProfile(
        nickname: '柴西',
        bio: 'hello',
        gender: '男',
        birthday: '1996-09-29',
        industry: '影视、电视、广播制作',
        vehicleBrand: '宝马',
        vehicleModel: 'M4',
      );
      expect(r.ok, isTrue);
      final saved = fake.profiles['fake-user-1']!;
      expect(saved['gender'], '男');
      expect(saved['birthday'], '1996-09-29');
      expect(saved['industry'], '影视、电视、广播制作');
      expect(saved['vehicle_brand'], '宝马');
      expect(saved['vehicle_model'], 'M4');
      // 读回时新字段同样解析。
      expect((await svc.fetchPublicProfile('fake-user-1'))!.gender, '男');
      expect((await svc.fetchPublicProfile('fake-user-1'))!.vehicleModel,
          'M4');
    });

    test('公开行程上传：文件进公开桶，行写 is_public 与带前缀 storage_path', () async {
      final svc = _service();
      await svc.init();
      final r = await svc.enqueueUpload(_sampleTrip(isPublic: true));
      expect(r.ok, isTrue);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.done);
      expect(fake.bucketObjects['public-files/fake-user-1/trip-1.json'],
          isNotNull);
      expect(fake.bucketObjects['trip-files/fake-user-1/trip-1.json'],
          isNull);
      final row = fake.insertedRows.single;
      expect(row['is_public'], isTrue);
      expect(row['storage_path'], 'public-files/fake-user-1/trip-1.json');
      expect(svc.queue.single.isPublic, isTrue);
    });

    test('私有行程上传不变：文件进私有桶，is_public 为 false', () async {
      final svc = _service();
      await svc.init();
      final r = await svc.enqueueUpload(_sampleTrip());
      expect(r.ok, isTrue);
      expect(fake.bucketObjects['trip-files/fake-user-1/trip-1.json'],
          isNotNull);
      expect(fake.insertedRows.single['is_public'], isFalse);
      expect(fake.insertedRows.single['storage_path'],
          'fake-user-1/trip-1.json');
    });

    test('公开桶不存在时公开上传失败进 failed，可重试', () async {
      final svc = _service();
      await svc.init();
      fake.failBucketUpload = true;
      final r = await svc.enqueueUpload(_sampleTrip(isPublic: true));
      expect(r.ok, isFalse);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.failed);
      fake.failBucketUpload = false;
      expect((await svc.retryEntry('trip-1')).ok, isTrue);
      expect(svc.queueStatusFor('trip-1'), CloudUploadStatus.done);
    });

    test('republishTrip：私有→公开搬桶改行删旧文件，再改回私有', () async {
      final svc = _service();
      await svc.init();
      expect((await svc.enqueueUpload(_sampleTrip())).ok, isTrue);
      // 改公开。
      final toPublic =
          await svc.republishTrip(_sampleTrip(isPublic: true));
      expect(toPublic.ok, isTrue);
      expect(fake.insertedRows.single['is_public'], isTrue);
      expect(fake.insertedRows.single['storage_path'],
          'public-files/fake-user-1/trip-1.json');
      expect(fake.bucketObjects['public-files/fake-user-1/trip-1.json'],
          isNotNull);
      expect(fake.bucketObjects['trip-files/fake-user-1/trip-1.json'],
          isNull);
      expect(svc.queue.single.isPublic, isTrue);
      // 改回私有。
      final toPrivate = await svc.republishTrip(_sampleTrip());
      expect(toPrivate.ok, isTrue);
      expect(fake.insertedRows.single['is_public'], isFalse);
      expect(fake.insertedRows.single['storage_path'],
          'fake-user-1/trip-1.json');
      expect(fake.bucketObjects['trip-files/fake-user-1/trip-1.json'],
          isNotNull);
      expect(fake.bucketObjects['public-files/fake-user-1/trip-1.json'],
          isNull);
    });

    test('republishTrip：没上传过的行程直接提示，不写队列', () async {
      final svc = _service();
      await svc.init();
      final r = await svc.republishTrip(_sampleTrip(isPublic: true));
      expect(r.ok, isFalse);
      expect(svc.queue, isEmpty);
    });

    test('listPublicTrips 只返回公开行，带 owner 与 isPublic', () async {
      final svc = _service();
      await svc.init();
      fake.publicTripRows = [
        {
          'id': 7,
          'owner': 'fake-user-1',
          'mode': 'car',
          'started_at': '2026-11-07T10:00:00.000Z',
          'ended_at': '2026-11-07T11:00:00.000Z',
          'distance_m': 1000,
          'duration_s': 3600,
          'source': 'phone',
          'max_speed_kmh': 72,
          'score': 88,
          'is_public': true,
          'storage_path': 'public-files/fake-user-1/trip-1.json',
        },
        {
          'id': 8,
          'owner': 'fake-user-1',
          'mode': 'car',
          'started_at': '2026-11-07T10:00:00.000Z',
          'ended_at': '2026-11-07T11:00:00.000Z',
          'distance_m': 2000,
          'duration_s': 3600,
          'source': 'phone',
          'max_speed_kmh': 72,
          'score': 90,
          'is_public': false,
          'storage_path': 'fake-user-1/trip-2.json',
        },
      ];
      final rows = await svc.listPublicTrips('fake-user-1');
      expect(rows, hasLength(1));
      expect(rows.single.id, '7');
      expect(rows.single.owner, 'fake-user-1');
      expect(rows.single.isPublic, isTrue);
    });

    test('downloadTripFile：按 storage_path 前缀分桶，读不到返回 null', () async {
      final svc = _service();
      await svc.init();
      fake.bucketObjects['public-files/u1/trip-1.json'] =
          Uint8List.fromList([9, 9]);
      final okRow = CloudTripRow.fromJson({
        'id': 7,
        'mode': 'car',
        'started_at': '2026-11-07T10:00:00.000Z',
        'ended_at': '2026-11-07T11:00:00.000Z',
        'storage_path': 'public-files/u1/trip-1.json',
      });
      expect(await svc.downloadTripFile(okRow), [9, 9]);
      final missingRow = CloudTripRow.fromJson({
        'id': 8,
        'mode': 'car',
        'started_at': '2026-11-07T10:00:00.000Z',
        'ended_at': '2026-11-07T11:00:00.000Z',
        'storage_path': 'public-files/u1/trip-9.json',
      });
      expect(await svc.downloadTripFile(missingRow), isNull);
      expect(
          await svc.downloadFileByStoragePath(''), isNull);
    });

    test('未配置时资料与公开行程接口返回空，不抛错', () async {
      final svc = _service(envId: '');
      await svc.init();
      expect(await svc.fetchPublicProfile('u1'), isNull);
      expect(await svc.listPublicTrips('u1'), isEmpty);
      final r = await svc.saveProfile(nickname: '柴西', bio: '');
      expect(r.ok, isFalse);
      expect(r.notConfigured, isTrue);
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
