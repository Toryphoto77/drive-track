/// 国内优先更新通道测试（UpdateConfig.domestic）。
///
/// 覆盖：
/// - 配置值：jsDelivr 清单地址、回落 GitHub 地址均指向
///   Toryphoto77/drive-track（旧账号链接已清掉）；
/// - 仓库根 update-manifest.json：当前版 1.5.4+59、apkUrl 指向
///   Toryphoto77 Release 附件；
/// - 本地 HttpServer 编排：清单成功时不走回落；清单失败时回落
///   GitHub 接口；两路都失败时返回 error、绝不谎称最新。
/// 不发真实网络请求（jsDelivr 可达性由沙箱 curl 另行核对）。

import 'dart:convert';
import 'dart:io';

import 'package:drive_track/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _server(
    Future<void> Function(HttpRequest req) handler) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((req) async {
    try {
      await handler(req);
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  });
  return server;
}

void main() {
  group('domestic config', () {
    test('manifest first is jsDelivr, fallback is corrected GitHub repo',
        () {
      const c = UpdateConfig.domestic();
      expect(c.manifestUrl,
          'https://cdn.jsdelivr.net/gh/Toryphoto77/drive-track@main/update-manifest.json');
      expect(c.fallbackGithubUrl,
          'https://api.github.com/repos/Toryphoto77/drive-track/releases/latest');
      expect(c.githubReleases, isFalse);
      expect(c.isConfigured, isTrue);
      expect(c.manifestUrl, isNot(contains('wangtao969')));
      expect(c.fallbackGithubUrl, isNot(contains('wangtao969')));
    });

    test('githubReleases config points at corrected repo', () {
      const c = UpdateConfig.githubReleases();
      expect(c.manifestUrl,
          'https://api.github.com/repos/Toryphoto77/drive-track/releases/latest');
      expect(c.manifestUrl, isNot(contains('wangtao969')));
    });

    test('repo-root update-manifest.json lists current release', () {
      final file = File('update-manifest.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['versionName'], '1.5.4');
      expect(json['versionCode'], 59);
      expect(json['apkUrl'],
          'https://github.com/Toryphoto77/drive-track/releases/download/v1.5.4/DriveTrack-v1.5.4-release-arm64-v8a.apk');
      expect(json['notes'], isA<String>());
    });
  });

  group('check with local server', () {
    test('manifest success returns available and never hits fallback',
        () async {
      var githubHits = 0;
      final server = await _server((req) async {
        if (req.uri.path == '/manifest.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'versionName': '1.5.5',
            'versionCode': 60,
            'apkUrl': 'https://example.invalid/app.apk',
            'notes': 'test',
          }));
        } else {
          githubHits++;
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final r = await UpdateService.check(
          config: UpdateConfig(
            manifestUrl: '$base/manifest.json',
            fallbackGithubUrl: '$base/releases/latest',
          ),
        );
        expect(r.status, UpdateCheckStatus.available);
        expect(r.remoteVersionName, '1.5.5');
        expect(r.remoteVersionCode, 60);
        expect(r.downloadUrl, 'https://example.invalid/app.apk');
        expect(githubHits, 0);
      } finally {
        await server.close(force: true);
      }
    });

    test('manifest up to date returns upToDate without fallback', () async {
      var githubHits = 0;
      final server = await _server((req) async {
        if (req.uri.path == '/manifest.json') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'versionName': '1.5.4',
            'versionCode': 59,
            'apkUrl': 'https://example.invalid/app.apk',
          }));
        } else {
          githubHits++;
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final r = await UpdateService.check(
          config: UpdateConfig(
            manifestUrl: '$base/manifest.json',
            fallbackGithubUrl: '$base/releases/latest',
          ),
        );
        expect(r.status, UpdateCheckStatus.upToDate);
        expect(githubHits, 0);
      } finally {
        await server.close(force: true);
      }
    });

    test('manifest failure falls back to GitHub releases', () async {
      final server = await _server((req) async {
        if (req.uri.path == '/manifest.json') {
          req.response.statusCode = 500;
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'tag_name': 'v1.5.5',
            'body': 'fallback notes',
            'assets': [
              {
                'name': 'DriveTrack-v1.5.5-release-arm64-v8a.apk',
                'browser_download_url': 'https://example.invalid/v155.apk',
              },
            ],
          }));
        }
        await req.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final r = await UpdateService.check(
          config: UpdateConfig(
            manifestUrl: '$base/manifest.json',
            fallbackGithubUrl: '$base/releases/latest',
          ),
        );
        expect(r.status, UpdateCheckStatus.available);
        expect(r.remoteVersionName, '1.5.5');
        expect(r.downloadUrl, 'https://example.invalid/v155.apk');
      } finally {
        await server.close(force: true);
      }
    });

    test('both channels failing returns error, never upToDate', () async {
      final server = await _server((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final r = await UpdateService.check(
          config: UpdateConfig(
            manifestUrl: '$base/manifest.json',
            fallbackGithubUrl: '$base/releases/latest',
          ),
        );
        expect(r.status, UpdateCheckStatus.error);
      } finally {
        await server.close(force: true);
      }
    });
  });
}
