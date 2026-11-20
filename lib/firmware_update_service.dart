import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sha256.dart';

/// 固件清单里的单个发布版本。
class FirmwareRelease {
  const FirmwareRelease({
    required this.version,
    required this.build,
    required this.model,
    required this.url,
    required this.sha256,
    required this.size,
    this.notes = '',
  });

  final String version;
  final int build;
  final String model;
  final String url;
  final String sha256;
  final int size;
  final String notes;

  static FirmwareRelease? fromJson(Object? value) {
    if (value is! Map) return null;
    final version = (value['version'] ?? '').toString().trim();
    final url = (value['url'] ?? '').toString().trim();
    final sha = normalizeSha256((value['sha256'] ?? '').toString());
    if (version.isEmpty || url.isEmpty || sha == null) return null;
    return FirmwareRelease(
      version: version,
      build: int.tryParse((value['build'] ?? '0').toString()) ?? 0,
      model: (value['model'] ?? '').toString().trim(),
      url: url,
      sha256: sha,
      size: int.tryParse((value['size'] ?? '0').toString()) ?? 0,
      notes: (value['notes'] ?? '').toString(),
    );
  }
}

/// 固件清单：按型号和通道组织。
class FirmwareManifest {
  const FirmwareManifest({
    required this.channel,
    required this.releases,
    this.updatedAt,
  });

  final String channel;
  final String? updatedAt;
  final List<FirmwareRelease> releases;

  /// 该型号下构建号最高的发布；型号为空时退回任意型号。
  FirmwareRelease? latestFor(String model) {
    final matched = releases
        .where((r) => model.isEmpty || r.model.isEmpty || r.model == model)
        .toList();
    if (matched.isEmpty) return null;
    matched.sort((a, b) {
      final byBuild = b.build.compareTo(a.build);
      if (byBuild != 0) return byBuild;
      return compareFirmwareVersion(b.version, a.version);
    });
    return matched.first;
  }

  static FirmwareManifest fromJson(Map<String, dynamic> json) {
    final raw = json['releases'];
    final list = <FirmwareRelease>[];
    if (raw is List) {
      for (final item in raw) {
        final release = FirmwareRelease.fromJson(item);
        if (release != null) list.add(release);
      }
    }
    return FirmwareManifest(
      channel: (json['channel'] ?? 'stable').toString(),
      updatedAt: json['updatedAt']?.toString(),
      releases: list,
    );
  }
}

/// 设备通过 WiFi 热点返回的自身信息。
class FirmwareDeviceInfo {
  const FirmwareDeviceInfo({
    required this.model,
    required this.version,
    required this.build,
    this.freeHeap,
    this.uptimeMs,
    this.note,
    this.batteryPercent,
    this.charging,
  });

  final String model;
  final String version;
  final int build;
  final int? freeHeap;
  final int? uptimeMs;
  final String? note;

  /// 外接硬件实时电量（0..100）。旧固件不返回该字段时为 null，
  /// 界面显示“—”，不拿 0 冒充。
  final int? batteryPercent;

  /// 是否正在充电；设备不返回时为 null（界面不显示充电状态）。
  final bool? charging;

  static FirmwareDeviceInfo? fromJson(Object? value) {
    if (value is! Map) return null;
    final model = (value['model'] ?? '').toString().trim();
    final version = (value['fw'] ?? value['version'] ?? '').toString().trim();
    if (version.isEmpty) return null;
    return FirmwareDeviceInfo(
      model: model,
      version: version,
      build: int.tryParse((value['build'] ?? '0').toString()) ?? 0,
      freeHeap: int.tryParse((value['freeHeap'] ?? '').toString()),
      uptimeMs: int.tryParse((value['uptimeMs'] ?? '').toString()),
      note: value['note']?.toString(),
      batteryPercent: parseBatteryPercent(value),
      charging: parseBool(value['charging']),
    );
  }
}

/// 从设备 JSON 里读电量（0..100）。只认明确的百分比字段；
/// 电压之类不换算，避免把 4.1V 猜成百分比。
int? parseBatteryPercent(Object? value) {
  if (value is! Map) return null;
  for (final key in const ['battery', 'batteryPct', 'batteryPercent', 'bat']) {
    final raw = value[key];
    if (raw is num) {
      final v = raw.round();
      if (v >= 0 && v <= 100) return v;
    } else if (raw is String) {
      final v = int.tryParse(raw.trim().replaceAll('%', ''));
      if (v != null && v >= 0 && v <= 100) return v;
    }
  }
  return null;
}

bool? parseBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return null;
}

int? _intField(Map value, List<String> keys) {
  for (final key in keys) {
    final raw = value[key];
    if (raw is num) return raw.round();
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      if (v != null) return v;
    }
  }
  return null;
}

/// 单圈结果：设备侧只保证圈序与用时（毫秒）。
class DeviceLap {
  const DeviceLap({
    required this.index,
    required this.timeMs,
    this.valid = true,
  });

  final int index;
  final int timeMs;
  final bool valid;

  /// 宽松解析：接受 {i|index|laps, timeMs|ms|lapMs|durationMs}，
  /// 也接受 "1:23.456" / "83.456" 形式的字符串。
  static DeviceLap? fromJson(Object? value, {int fallbackIndex = 0}) {
    if (value is num) {
      final ms = value.round();
      if (ms <= 0) return null;
      return DeviceLap(index: fallbackIndex, timeMs: ms);
    }
    if (value is! Map) return null;
    final index =
        _intField(value, const ['i', 'index', 'lap', 'n']) ?? fallbackIndex;
    var ms = _intField(value, const [
      'timeMs',
      'ms',
      'lapMs',
      'durationMs',
      'time_ms',
    ]);
    ms ??= parseLapTimeText(value['time'] ?? value['dur'] ?? value['t']);
    if (ms == null || ms <= 0) return null;
    return DeviceLap(index: index, timeMs: ms);
  }

  /// "1:23.456" → 83456 ms；"83.456" → 83456 ms；"83456" → 83456 ms。
  static int? parseLapTimeText(Object? value) {
    if (value is num) {
      final v = value.toDouble();
      // 小于 3600 的数字按秒，否则按毫秒（单圈不可能超过 1 小时）。
      return v < 3600 ? (v * 1000).round() : v.round();
    }
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    try {
      if (parts.length == 1) {
        final sec = double.parse(parts[0]);
        return sec < 3600 ? (sec * 1000).round() : sec.round();
      }
      if (parts.length == 2) {
        final min = int.parse(parts[0]);
        final sec = double.parse(parts[1]);
        return ((min * 60 + sec) * 1000).round();
      }
      if (parts.length == 3) {
        final hour = int.parse(parts[0]);
        final min = int.parse(parts[1]);
        final sec = double.parse(parts[2]);
        return ((hour * 3600 + min * 60 + sec) * 1000).round();
      }
    } catch (_) {}
    return null;
  }
}

/// `GET /api/status` 的实时状态。字段缺省一律为 null，界面显示“—”，
/// 绝不把缺省值当成 0 或“未录制”。
class DeviceRuntimeStatus {
  const DeviceRuntimeStatus({
    this.batteryPercent,
    this.charging,
    this.recording,
    this.hasFix,
    this.satellites,
    this.lapCount,
    this.currentLapMs,
    this.lastLapMs,
    this.bestLapMs,
    this.uptimeMs,
    this.freeHeap,
    this.sdPresent,
    this.sdState,
    this.sdTotalKb,
    this.sdFreeKb,
    this.supportsShutdown = false,
    this.supportsLaps = false,
  });

  final int? batteryPercent;
  final bool? charging;
  final bool? recording;
  final bool? hasFix;
  final int? satellites;
  final int? lapCount;
  final int? currentLapMs;
  final int? lastLapMs;
  final int? bestLapMs;
  final int? uptimeMs;
  final int? freeHeap;

  /// microSD 状态（固件 0.4.0+ 才上报，旧固件为 null → 界面不显示这一行）。
  final bool? sdPresent;
  final String? sdState; // ok / no_card / mount_fail
  final int? sdTotalKb;
  final int? sdFreeKb;

  bool get sdMounted => sdPresent == true && (sdTotalKb ?? 0) > 0;

  /// 固件能力：旧固件不报 caps，对应按钮置灰并提示升级固件。
  final bool supportsShutdown;
  final bool supportsLaps;

  static DeviceRuntimeStatus fromJson(Map<String, dynamic> json) {
    final caps =
        (json['caps'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toSet() ??
        const <String>{};
    bool supports(String name, String flagKey) {
      final flag = parseBool(json[flagKey]);
      if (flag != null) return flag;
      return caps.contains(name);
    }

    final recording = parseBool(json['recording'] ?? json['rec']);
    final fix = parseBool(json['fix'] ?? json['hasFix'] ?? json['gnss']);
    return DeviceRuntimeStatus(
      batteryPercent: parseBatteryPercent(json),
      charging: parseBool(json['charging']),
      recording: recording,
      hasFix: fix,
      satellites: _intField(json, const ['sats', 'satellites', 'sat']),
      lapCount: _intField(json, const ['laps', 'lapCount', 'lap_count']),
      currentLapMs: _intField(json, const [
        'currentLapMs',
        'curLapMs',
        'lapMs',
        'current_ms',
      ]),
      lastLapMs: _intField(json, const ['lastLapMs', 'last_ms', 'lastLap']),
      bestLapMs: _intField(json, const ['bestLapMs', 'best_ms', 'bestLap']),
      uptimeMs: _intField(json, const ['uptimeMs', 'uptime_ms']),
      freeHeap: _intField(json, const ['freeHeap', 'free_heap']),
      sdPresent: parseBool(json['sd'] ?? json['sdPresent'] ?? json['sdOk']),
      sdState: json['sdState']?.toString() ?? json['sd_state']?.toString(),
      sdTotalKb: _intField(json, const ['sdTotalKb', 'sd_total_kb']),
      sdFreeKb: _intField(json, const ['sdFreeKb', 'sd_free_kb']),
      supportsShutdown: supports('shutdown', 'shutdown'),
      supportsLaps: supports('laps', 'lapsApi'),
    );
  }
}

class FirmwareProgress {
  const FirmwareProgress(this.received, this.total);

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

/// 比较点分版本号；a 大于 b 返回正数。
int compareFirmwareVersion(String a, String b) {
  List<int> parts(String v) => v
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

/// 自研硬件的固件在线升级：清单拉取、下载校验、WiFi 直连上传。
///
/// 设备侧协议（与固件保持一致）：
/// - `GET  /api/info` 返回 `{model, fw, build, freeHeap, uptimeMs}`
/// - `POST /api/ota` 请求体为固件二进制，头 `X-Firmware-Sha256` 为摘要，
///   设备校验通过后写入备用分区并重启。
class FirmwareUpdateService {
  FirmwareUpdateService({this.host = defaultHost, HttpClient? client})
    : _client = client ?? HttpClient();

  /// 设备热点默认分配的网关地址。
  static const String defaultHost = '192.168.4.1';

  /// 设备热点名称前缀，App 内用于提示用户连接。
  static const String accessPointPrefix = 'DriveTrack';

  /// 设备热点默认密码（固件 dt_config.h 的 DT_AP_PASSWORD）。
  static const String accessPointPassword = 'drivetrack123';

  static const String domesticManifestUrl =
      'https://cdn.jsdelivr.net/gh/Toryphoto77/drive-track@main/firmware/manifest.json';

  static const String fallbackManifestUrl =
      'https://raw.githubusercontent.com/Toryphoto77/drive-track/main/firmware/manifest.json';

  final String host;
  final HttpClient _client;

  /// 拉取固件清单：优先国内 CDN，失败后回退原始地址。
  Future<FirmwareManifest> fetchManifest({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    for (final url in const [domesticManifestUrl, fallbackManifestUrl]) {
      try {
        final body = await _getString(url, timeout: timeout);
        final decoded = jsonDecode(body);
        if (decoded is! Map) throw const FormatException('清单格式不正确');
        final manifest = FirmwareManifest.fromJson(
          decoded.cast<String, dynamic>(),
        );
        if (manifest.releases.isEmpty) throw const FormatException('清单里没有可用固件');
        return manifest;
      } catch (e) {
        lastError = e;
      }
    }
    throw FirmwareUpdateException('固件清单获取失败：$lastError');
  }

  /// 探测当前连接的设备；未连接设备热点时返回 null。
  Future<FirmwareDeviceInfo?> probeDevice({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final body = await _getString('http://$host/api/info', timeout: timeout);
      return FirmwareDeviceInfo.fromJson(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  /// 读取实时状态（电量 / 定位 / 当前圈 / 光线圈数）。
  /// 设备不可达或旧固件没有该接口时返回 null，供轮询使用，不抛异常。
  Future<DeviceRuntimeStatus?> readStatus({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final body = await _getString(
        'http://$host/api/status',
        timeout: timeout,
      );
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return DeviceRuntimeStatus.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// 读取设备端已记录圈速。接口缺失 / 格式异常时返回空列表（不抛异常）。
  Future<List<DeviceLap>> readLaps({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final body = await _getString('http://$host/api/laps', timeout: timeout);
      final decoded = jsonDecode(body);
      final raw = decoded is List
          ? decoded
          : (decoded is Map ? decoded['laps'] : null);
      if (raw is! List) return const [];
      final laps = <DeviceLap>[];
      for (var i = 0; i < raw.length; i++) {
        final lap = DeviceLap.fromJson(raw[i], fallbackIndex: i + 1);
        if (lap != null) laps.add(lap);
      }
      return laps;
    } catch (_) {
      return const [];
    }
  }

  /// App 内关机：POST /api/shutdown。
  ///
  /// 初版硬件按键是单脉冲，只能开机不能在机上关机，因此关机只从 App
  /// 发起。设备关机后热点会立即消失，若请求发出后连接被断开，按
  /// “设备可能已关机”提示调用方，不擅自报成功。
  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) async {
    final request = await _client
        .postUrl(Uri.parse('http://$host/api/shutdown'))
        .timeout(timeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write('{}');
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirmwareUpdateException('设备拒绝关机：HTTP ${response.statusCode} $body');
    }
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['ok'] == false) {
          throw FirmwareUpdateException('设备拒绝关机：${decoded['error'] ?? '未知原因'}');
        }
      } catch (e) {
        if (e is FirmwareUpdateException) rethrow;
      }
    }
  }

  /// 下载固件到 [directory]，边写边算摘要并校验。
  Future<File> download(
    FirmwareRelease release, {
    required Directory directory,
    void Function(FirmwareProgress)? onProgress,
  }) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final target = File('${directory.path}/firmware-${release.version}.bin');
    final partial = File('${target.path}.part');
    final request = await _client.getUrl(Uri.parse(release.url));
    request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw FirmwareUpdateException('固件下载失败：HTTP ${response.statusCode}');
    }
    final total = response.contentLength > 0
        ? response.contentLength
        : release.size;
    final sink = partial.openWrite();
    final digest = Sha256();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        digest.add(chunk);
        received += chunk.length;
        onProgress?.call(FirmwareProgress(received, total));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final actual = digest.hexDigest();
    if (actual != release.sha256) {
      try {
        await partial.delete();
      } catch (_) {}
      throw FirmwareUpdateException('固件校验失败：摘要不匹配');
    }
    if (await target.exists()) {
      await target.delete();
    }
    await partial.rename(target.path);
    return target;
  }

  /// 把固件通过设备 WiFi 热点上传；设备校验摘要后写入备用分区。
  Future<void> upload(
    File file, {
    required String sha256,
    void Function(FirmwareProgress)? onProgress,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final length = await file.length();
    final request = await _client
        .postUrl(Uri.parse('http://$host/api/ota'))
        .timeout(timeout);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/octet-stream',
    );
    request.headers.set('X-Firmware-Sha256', sha256);
    request.contentLength = length;

    var sent = 0;
    final responseFuture = request.close();
    await for (final chunk in file.openRead()) {
      request.add(chunk);
      sent += chunk.length;
      onProgress?.call(FirmwareProgress(sent, length));
    }
    final response = await responseFuture.timeout(timeout);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw FirmwareUpdateException('设备拒绝升级：HTTP ${response.statusCode} $body');
    }
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['ok'] == false) {
          throw FirmwareUpdateException('设备校验失败：${decoded['error'] ?? '未知原因'}');
        }
      } catch (e) {
        if (e is FirmwareUpdateException) rethrow;
      }
    }
  }

  /// 升级后轮询设备，等待其以新版本重新上线。
  Future<FirmwareDeviceInfo?> waitForFirmware(
    String expectedVersion, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final info = await probeDevice();
      if (info != null && info.version == expectedVersion) return info;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<String> _getString(String url, {required Duration timeout}) async {
    final request = await _client.getUrl(Uri.parse(url)).timeout(timeout);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw FirmwareUpdateException('HTTP ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join().timeout(timeout);
  }

  void close() => _client.close(force: true);
}

class FirmwareUpdateException implements Exception {
  FirmwareUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
