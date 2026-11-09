import 'dart:convert';
import 'dart:io';

import 'package:drive_track/sha256.dart';
import 'package:drive_track/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const github =
      'https://github.com/Toryphoto77/drive-track/releases/download/v1.5.5/a.apk';

  test('cdn and mirrors come before GitHub, proxies last', () {
    final sources = buildDownloadSources(
      url: github,
      cdnUrl: 'https://cdn.example/a.apk',
      mirrors: const ['https://mirror.example/a.apk'],
    );
    expect(sources.map((s) => s.url).toList(), [
      'https://cdn.example/a.apk',
      'https://mirror.example/a.apk',
      github,
      'https://ghfast.top/$github',
      'https://gh-proxy.com/$github',
      'https://mirror.ghproxy.com/$github',
    ]);
    expect(sources.first.kind, DownloadSourceKind.cdn);
    expect(sources[2].kind, DownloadSourceKind.github);
    expect(sources[3].kind, DownloadSourceKind.githubProxy);
  });

  test('githubProxyFallback false and non-github urls skip proxies', () {
    expect(
      buildDownloadSources(url: github, githubProxyFallback: false).map((s) => s.url),
      [github],
    );
    expect(
      buildDownloadSources(
        url: github,
        githubProxies: const ['https://custom.example/'],
      ).map((s) => s.url).toList(),
      [github, 'https://custom.example/$github'],
    );
    expect(
      buildDownloadSources(url: 'https://cos.example/a.apk').map((s) => s.kind),
      [DownloadSourceKind.cdn],
    );
  });

  test('per-apk cdn wins; top-level cdn does not apply to another ABI', () {
    final json = {
      'apkUrl': 'https://github.com/o/r/releases/download/v1/arm64.apk',
      'cdnUrl': 'https://cdn.example/arm64.apk',
      'mirrors': ['https://mirror.example/arm64.apk'],
      'apks': {
        'arm64-v8a': {
          'url': 'https://github.com/o/r/releases/download/v1/arm64.apk',
          'cdnUrl': 'https://cdn.example/arm64-fast.apk',
        },
        'armeabi-v7a': {
          'url': 'https://github.com/o/r/releases/download/v1/v7a.apk',
        },
      },
    };
    final arm64 = selectManifestApk(json, const ['arm64-v8a'])!;
    expect(arm64.url, contains('arm64.apk'));
    expect(arm64.cdnUrl, 'https://cdn.example/arm64-fast.apk');
    expect(arm64.mirrors, contains('https://mirror.example/arm64.apk'));
    final v7 = selectManifestApk(json, const ['armeabi-v7a'])!;
    expect(v7.url, contains('v7a.apk'));
    expect(v7.cdnUrl, isNull);
    expect(v7.mirrors, isEmpty);
    final legacy = selectManifestApk({
      'apkUrl': 'https://example.invalid/app.apk',
      'cdnUrl': 'https://cdn.example/app.apk',
    }, const ['arm64-v8a'])!;
    expect(legacy.url, 'https://example.invalid/app.apk');
    expect(legacy.cdnUrl, 'https://cdn.example/app.apk');
  });

  test('committed manifest does not invent a CDN url', () {
    final json = jsonDecodeFile();
    expect(json.containsKey('cdnUrl'), isFalse);
    final apks = json['apks'] as Map;
    for (final entry in apks.values) {
      expect((entry as Map).containsKey('cdnUrl'), isFalse);
      expect(entry.containsKey('mirrors'), isFalse);
    }
  });

  test('failed CDN falls through and the next body still verifies', () async {
    final body = List<int>.generate(4000, (i) => i & 0xff);
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/cdn') {
        req.response.statusCode = 500;
        await req.response.close();
        return;
      }
      req.response.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });
    final tmp = await Directory.systemTemp.createTemp('upd_mirror_');
    final installed = <String>[];
    final seen = <int>[];
    try {
      final base = 'http://127.0.0.1:${server.port}';
      final result = await UpdateService.downloadAndInstallChecked(
        url: '$base/github',
        sources: [
          DownloadSource('$base/cdn', DownloadSourceKind.cdn),
          DownloadSource('$base/github', DownloadSourceKind.github),
        ],
        remoteVersionCode: 77,
        expectedSha256: Sha256.hexOf(body),
        httpClient: HttpClient(),
        cacheDir: () async => tmp.path,
        install: (p) async {
          installed.add(p);
          return true;
        },
        onProgress: (received, _) => seen.add(received),
      );
      expect(result.ok, isTrue);
      expect(result.verified, isTrue);
      expect(installed, hasLength(1));
      expect(seen, contains(0));
      expect(seen.last, body.length);
    } finally {
      await server.close(force: true);
      await tmp.delete(recursive: true);
    }
  });
}

Map<String, dynamic> jsonDecodeFile() {
  final raw = File('update-manifest.json').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}
