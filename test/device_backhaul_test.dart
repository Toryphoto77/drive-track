/// 设备 SD 会话文件回传：列表与下载。
import 'dart:convert';
import 'dart:io';

import 'package:drive_track/firmware_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  HttpOverrides.global = _RealHttpOverrides();
  late HttpServer server;
  late FirmwareUpdateService service;
  late Directory dir;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = FirmwareUpdateService(host: '127.0.0.1:${server.port}');
    dir = await Directory.systemTemp.createTemp('backhaul_');
  });

  tearDown(() async {
    service.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test('列出设备 SD 上的会话文件', () async {
    server.listen((req) async {
      expect(req.uri.path, '/api/files');
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"ok":true,"files":['
          '{"name":"session_0001.ndjson","size":1234},'
          '{"name":"session_0002.ndjson","size":5678}]}');
      await req.response.close();
    });

    final files = await service.listRecordings();
    expect(files, hasLength(2));
    expect(files.first.name, 'session_0001.ndjson');
    expect(files.first.size, 1234);
    expect(files.last.name, 'session_0002.ndjson');
  });

  test('下载会话文件到本地并保留原始字节', () async {
    server.listen((req) async {
      expect(req.uri.path, '/api/files/download');
      expect(req.uri.queryParameters['name'], 'session_0001.ndjson');
      req.response.add(utf8.encode('{"t":"sess"}\n'));
      await req.response.close();
    });

    final file = await service.downloadRecording(
      'session_0001.ndjson',
      directory: dir,
    );
    expect(await file.readAsString(), '{"t":"sess"}\n');
    expect(file.path, endsWith('session_0001.ndjson'));
  });

  test('拒绝路径穿越等非法文件名，不发请求', () async {
    var requested = false;
    server.listen((req) async {
      requested = true;
      await req.response.close();
    });

    await expectLater(
      service.downloadRecording('../../etc/passwd', directory: dir),
      throwsA(isA<ArgumentError>()),
    );
    expect(requested, isFalse);
  });

  test('设备不支持回传时给出明确错误', () async {
    server.listen((req) async {
      req.response.statusCode = 409;
      req.response.write('{"ok":false,"error":"sd_not_ready"}');
      await req.response.close();
    });

    await expectLater(
      service.listRecordings(),
      throwsA(isA<FirmwareUpdateException>()),
    );
  });
}
