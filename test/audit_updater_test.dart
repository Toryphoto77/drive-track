/// 审计修复回归测试（在线更新部分）：按设备架构选包、超时、SHA-256 校验。
/// 本文件不初始化 TestWidgetsFlutterBinding——那会把 HttpClient 换成
/// 一律返回 400 的假实现，本机 HttpServer 用例就测不到真实下载路径。
import 'dart:convert';
import 'dart:io';

import 'package:drive_track/sha256.dart';
import 'package:drive_track/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('audit_upd_'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('architecture-aware updater', () {
    const legacy = {
      'versionName': '9.9.9', 'versionCode': 999,
      'apkUrl': 'https://example.invalid/DriveTrack-v9.9.9-release-arm64-v8a.apk',
    };
    test('legacy manifest is never offered to non-arm64 devices', () {
      expect(selectManifestApk(legacy, ['armeabi-v7a', 'armeabi']), isNull);
      expect(selectManifestApk(legacy, ['x86_64']), isNull);
      expect(selectManifestApk(legacy, ['arm64-v8a', 'armeabi-v7a'])!.abi, 'arm64-v8a');
    });

    test('apks map picks the first supported ABI and normalizes digest', () {
      final m = {
        ...legacy,
        'apks': {
          'arm64-v8a': {'url': 'u64', 'sha256': 'A' * 64},
          'armeabi-v7a': {'url': 'u32', 'sha256': 'sha256:${'b' * 64}'},
        },
      };
      final c = selectManifestApk(m, ['armeabi-v7a', 'armeabi'])!;
      expect(c.url, 'u32');
      expect(c.sha256, 'b' * 64);
      expect(selectManifestApk(m, ['arm64-v8a'])!.sha256, 'a' * 64);
    });

    test('GitHub assets: picks by ABI and uses digest when present', () {
      final assets = [
        {'name': 'DriveTrack-v1.6.0-release-arm64-v8a.apk', 'browser_download_url': 'a64', 'digest': 'sha256:${'c' * 64}'},
        {'name': 'DriveTrack-v1.6.0-release-armeabi-v7a.apk', 'browser_download_url': 'a32'},
        {'name': 'DriveTrack-v1.6.0-release-x86_64.apk', 'browser_download_url': 'x64'},
      ];
      expect(selectGithubApk(assets, ['x86_64'])!.url, 'x64');
      expect(selectGithubApk(assets, ['armeabi-v7a'])!.sha256, isNull);
      expect(selectGithubApk(assets, ['arm64-v8a'])!.sha256, 'c' * 64);
    });

    test('check() returns error (not a wrong-ABI package) for 32-bit device on legacy manifest', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        req.response.write(jsonEncode(legacy));
        await req.response.close();
      });
      final r = await UpdateService.check(
          config: UpdateConfig(manifestUrl: 'http://127.0.0.1:${server.port}/m.json'),
          abis: const ['armeabi-v7a']);
      await server.close(force: true);
      expect(r.status, UpdateCheckStatus.error);
      expect(r.downloadUrl, isNull);
    });

    Future<(HttpServer, List<int>)> apkServer() async {
      final body = List<int>.generate(200000, (i) => (i * 31) & 0xff);
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        req.response.contentLength = body.length;
        req.response.add(body);
        await req.response.close();
      });
      return (server, body);
    }

    Future<UpdateInstallResult> run(HttpServer s, String? sha, List<String> installed) =>
        UpdateService.downloadAndInstallChecked(
          url: 'http://127.0.0.1:${s.port}/app.apk',
          remoteVersionCode: 99,
          expectedSha256: sha,
          httpClient: HttpClient(),
          cacheDir: () async => tmp.path,
          install: (p) async {
            installed.add(p);
            return true;
          },
        );

    test('matching checksum installs and reports verified', () async {
      final (s, body) = await apkServer();
      final installed = <String>[];
      final r = await run(s, Sha256.hexOf(body), installed);
      await s.close(force: true);
      expect(r.ok, isTrue);
      expect(r.verified, isTrue);
      expect(installed, hasLength(1));
      expect(File(installed.single).lengthSync(), body.length);
    });

    test('checksum mismatch refuses install and deletes the download', () async {
      final (s, _) = await apkServer();
      final installed = <String>[];
      final r = await run(s, '0' * 64, installed);
      await s.close(force: true);
      expect(r.ok, isFalse);
      expect(installed, isEmpty);
      expect(tmp.listSync().where((e) => e.path.contains('update-99')), isEmpty);
    });

    test('no checksum: installs but explicitly unverified', () async {
      final (s, _) = await apkServer();
      final installed = <String>[];
      final r = await run(s, null, installed);
      await s.close(force: true);
      expect(r.ok, isTrue);
      expect(r.verified, isFalse);
      expect(r.message, contains('NOT verified'));
    });

    test('truncated download is never installed', () async {
      // 原始 socket：声明 200000 字节，只发 1000 字节就断开。
      final ss = await ServerSocket.bind('127.0.0.1', 0);
      ss.listen((sock) async {
        await sock.first;
        sock.add(utf8.encode('HTTP/1.1 200 OK\r\nContent-Length: 200000\r\nConnection: close\r\n\r\n'));
        sock.add(List.filled(1000, 7));
        await sock.flush();
        await sock.close();
      });
      final installed = <String>[];
      final r = await UpdateService.downloadAndInstallChecked(
        url: 'http://127.0.0.1:${ss.port}/app.apk',
        remoteVersionCode: 98,
        httpClient: HttpClient(),
        cacheDir: () async => tmp.path,
        install: (p) async {
          installed.add(p);
          return true;
        },
      );
      await ss.close();
      expect(r.ok, isFalse);
      expect(installed, isEmpty);
      expect(tmp.listSync().where((e) => e.path.contains('update-98')), isEmpty);
    });

    test('malformed checksum in manifest refuses to start', () async {
      final r = await UpdateService.downloadAndInstallChecked(
          url: 'http://127.0.0.1:1/x', remoteVersionCode: 1, expectedSha256: 'not-a-hash');
      expect(r.ok, isFalse);
    });

    test('sha256 matches FIPS test vectors incl. block boundaries', () {
      expect(Sha256.hexOf(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(Sha256.hexOf(const []), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(Sha256.hexOf(List.filled(64, 0x61)),
          'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb');
    });

    test('repo update-manifest.json keeps legacy apkUrl and lists all ABIs', () {
      final m = jsonDecode(File('update-manifest.json').readAsStringSync()) as Map<String, dynamic>;
      expect(m['apkUrl'], contains('arm64-v8a'));
      expect((m['apks'] as Map).keys, containsAll(kPublishedAbis));
    });
  });

}
