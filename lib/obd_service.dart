import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native.dart';
import 'recorder.dart';

/// OBD（ELM327）第三步：经典蓝牙 SPP + Mode 01 轮询。
///
/// 零新增 pub 插件，全部走手写 Method/EventChannel（见 native.dart）。
/// 解析函数（[parseElmResponse] / [elmErrorKind]）是纯函数，不依赖
/// 平台通道，可单测；平台层抽象为 [ObdPlatform]，测试用 fake，
/// 真实实现 [MethodChannelObdPlatform] 走原生 [ObdManager]。
///
/// 诚实规则：
/// - 未连接时 [ObdStatus] 的全部实时读数均为 null，绝不把旧值当
///   实时值显示（断开即清零，见 [_markDisconnected]）；
/// - GPS 正常时绝不拿 OBD 速度替换实测点里的 GPS 速度：本服务只写
///   Recorder.obdSpeedMs / noteObdSample，Recorder 只在推算时读它；
/// - OBD 采样只存实测（noteObdSample 每秒一条），无采样不画曲线。

/// ELM327 初始化序列（ATZ 复位后回显默认开，ATE0 关回显；
/// 其余关换行/空格/报头、协议自动）。
const List<String> obdInitCommands = [
  'ATZ',
  'ATE0',
  'ATL0',
  'ATS0',
  'ATH0',
  'ATSP0',
];

/// Mode 01 轮询命令：车速 5–10Hz，其余 1Hz。
const String obdCmdSpeed = '010D';
const String obdCmdRpm = '010C';
const String obdCmdThrottle = '0111';
const String obdCmdCoolant = '0105';

/// 一次 ELM327 响应的解析结果。全部读数为 null 且无错误时表示
/// 响应里没有可识别的 Mode 01 帧（如只有 OK / 版本号）。
class ObdReadings {
  final double? speedKmh;
  final double? rpm;
  final double? throttlePct;
  final double? coolantC;

  /// 车辆无响应（点火未开 / 协议未接通）：ELM327 本身还连着，
  /// 不按断线处理，只把对应读数清 null。
  final bool noData;

  /// ELM327 错误：'NO DATA' / 'STOPPED' / 'UNABLE TO CONNECT' /
  /// '?' / 'SEND_FAILED'，无错误为 null。
  final String? errorKind;

  const ObdReadings({
    this.speedKmh,
    this.rpm,
    this.throttlePct,
    this.coolantC,
    this.noData = false,
    this.errorKind,
  });

  bool get hasAny =>
      speedKmh != null ||
      rpm != null ||
      throttlePct != null ||
      coolantC != null;
}

/// ELM327 错误种类（纯函数）：命中任一即返回该种类，否则 null。
/// '?' 只有整行就是问号时才算（未知命令），不按子串判。
String? elmErrorKind(String raw) {
  final upper = raw.toUpperCase();
  if (upper.contains('UNABLE TO CONNECT')) return 'UNABLE TO CONNECT';
  if (upper.contains('NO DATA')) return 'NO DATA';
  if (upper.contains('STOPPED')) return 'STOPPED';
  if (raw.trim() == '?') return '?';
  return null;
}

/// 解析一次 ELM327 原始响应（纯函数）。
///
/// 容忍：命令回显（如 '010D'）、'ELM327 v1.5' 版本行、'SEARCHING...'
/// 提示、'>' 提示符、'\r' / '\n' 分隔、多帧连发（如
/// '41 0D 3C 41 0D 3D'，后帧覆盖前帧）。只认 '41' 开头的 Mode 01
/// 应答帧；其余内容忽略，不抛错。
/// - 车速 0x0D：单字节 km/h；
/// - 转速 0x0C：(A*256+B)/4 rpm；
/// - 油门 0x11：A*100/255 %；
/// - 水温 0x05：A-40 ℃。
ObdReadings parseElmResponse(String raw) {
  final error = elmErrorKind(raw);
  if (error == 'NO DATA') {
    return const ObdReadings(noData: true, errorKind: 'NO DATA');
  }
  if (error != null) return ObdReadings(errorKind: error);
  // 按空白 / \r / \n / '>' / ',' 切 token，逐 token 扫 '41' 帧头。
  final tokens = raw
      .toUpperCase()
      .split(RegExp(r'[\s\r\n>,]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  double? speedKmh;
  double? rpm;
  double? throttlePct;
  double? coolantC;
  var i = 0;
  while (i < tokens.length) {
    if (tokens[i] == '41' && i + 1 < tokens.length) {
      int? byteAt(int off) {
        final idx = i + 2 + off;
        if (idx >= tokens.length) return null;
        return int.tryParse(tokens[idx], radix: 16);
      }

      switch (tokens[i + 1]) {
        case '0D':
          final a = byteAt(0);
          if (a != null) speedKmh = a.toDouble();
          i += 3;
          continue;
        case '0C':
          final a = byteAt(0);
          final b = byteAt(1);
          if (a != null && b != null) rpm = (a * 256 + b) / 4;
          i += 4;
          continue;
        case '11':
          final a = byteAt(0);
          if (a != null) throttlePct = a * 100 / 255;
          i += 3;
          continue;
        case '05':
          final a = byteAt(0);
          if (a != null) coolantC = (a - 40).toDouble();
          i += 3;
          continue;
      }
    }
    i++;
  }
  return ObdReadings(
    speedKmh: speedKmh,
    rpm: rpm,
    throttlePct: throttlePct,
    coolantC: coolantC,
  );
}

/// OBD 实时连接状态（设备中心写入、录制页 / 复盘页只读）。
/// 未连接（[disconnected]）时读数全部为 null。
class ObdStatus {
  final bool connected;
  final bool connecting;
  final String deviceName;
  final double? speedKmh;
  final double? rpm;
  final double? throttlePct;
  final double? coolantC;

  /// 最近一次失败的简短原因（'' = 无），供设备中心显示，不持久化。
  final String error;

  const ObdStatus({
    this.connected = false,
    this.connecting = false,
    this.deviceName = '',
    this.speedKmh,
    this.rpm,
    this.throttlePct,
    this.coolantC,
    this.error = '',
  });

  static const disconnected = ObdStatus();

  // 读数参数用哨兵区分“不改”与“显式置 null”：NO DATA 时必须把
  // 对应读数清 null，绝不能把旧值继续当实时值显示。
  static const _unset = Object();

  ObdStatus copyWith({
    bool? connected,
    bool? connecting,
    String? deviceName,
    Object? speedKmh = _unset,
    Object? rpm = _unset,
    Object? throttlePct = _unset,
    Object? coolantC = _unset,
    String? error,
    bool clearReadings = false,
  }) =>
      ObdStatus(
        connected: connected ?? this.connected,
        connecting: connecting ?? this.connecting,
        deviceName: deviceName ?? this.deviceName,
        speedKmh: clearReadings
            ? null
            : (speedKmh == _unset ? this.speedKmh : speedKmh as double?),
        rpm: clearReadings
            ? null
            : (rpm == _unset ? this.rpm : rpm as double?),
        throttlePct: clearReadings
            ? null
            : (throttlePct == _unset
                ? this.throttlePct
                : throttlePct as double?),
        coolantC: clearReadings
            ? null
            : (coolantC == _unset ? this.coolantC : coolantC as double?),
        error: error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is ObdStatus &&
      other.connected == connected &&
      other.connecting == connecting &&
      other.deviceName == deviceName &&
      other.speedKmh == speedKmh &&
      other.rpm == rpm &&
      other.throttlePct == throttlePct &&
      other.coolantC == coolantC &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
        connected,
        connecting,
        deviceName,
        speedKmh,
        rpm,
        throttlePct,
        coolantC,
        error,
      );
}

/// OBD 状态文案（纯函数，供设备中心 / 录制页共用）。
String obdStatusLabel(ObdStatus s) {
  if (s.connecting) return '正在连接 OBD…';
  if (!s.connected) return '未连接 OBD';
  final name = s.deviceName.trim();
  return name.isEmpty ? 'OBD · 已连接' : 'OBD · $name';
}

/// OBD 平台层抽象（可注入）：真实实现走 Method/EventChannel，
/// 测试用 fake，不依赖真蓝牙。
abstract class ObdPlatform {
  /// 已配对经典蓝牙设备（[{address, name, type}]），
  /// ELM327 须先在系统蓝牙里配对才会出现在这里。
  Future<List<Map<String, dynamic>>> listPaired();

  /// 发起 SPP 连接（后台线程连，成功后 [connected] 发事件）。
  Future<void> connect(String address);

  /// 断开 SPP。
  Future<void> disconnect();

  /// 发一条 ELM327 命令（不带 '\r'，原生侧补）；响应行走 [responses]。
  Future<void> sendCommand(String command);

  /// ELM327 原始响应行（已按 \r / \n 切行，含 '>' 提示行）。
  Stream<String> get responses;

  /// SPP socket 已连通。
  Stream<void> get connected;

  /// SPP socket 已断开，值为原因（'eof' / 'io_error' / 'permission' …）。
  Stream<String> get disconnected;
}

/// 真实平台实现：MethodChannel 发命令 + EventChannel 收响应行。
class MethodChannelObdPlatform implements ObdPlatform {
  final _lineController = StreamController<String>.broadcast();
  final _connectedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<String>.broadcast();

  MethodChannelObdPlatform() {
    Native.obdStream.listen((e) {
      switch ((e['type'] ?? '').toString()) {
        case 'obdLine':
          _lineController.add((e['line'] ?? '').toString());
          break;
        case 'obdConnected':
          _connectedController.add(null);
          break;
        case 'obdDisconnected':
          _disconnectedController
              .add((e['reason'] ?? '').toString());
          break;
      }
    }, onError: (_) {});
  }

  @override
  Future<List<Map<String, dynamic>>> listPaired() =>
      Native.listBondedObdDevices();

  @override
  Future<void> connect(String address) => Native.connectObd(address);

  @override
  Future<void> disconnect() => Native.disconnectObd();

  @override
  Future<void> sendCommand(String command) =>
      Native.sendObdCommand(command);

  @override
  Stream<String> get responses => _lineController.stream;

  @override
  Stream<void> get connected => _connectedController.stream;

  @override
  Stream<String> get disconnected => _disconnectedController.stream;
}

/// OBD 服务：初始化 → 轮询 → 断线重连一次 → 报断开。
///
/// - 车速 010D 约 5–10Hz（默认 150ms），转速 / 油门 / 水温 1Hz；
/// - 实时车速写 Recorder.obdSpeedMs（只供隧道推算用），每秒调一次
///   Recorder.noteObdSample 存实测采样；断开时调 clearObdSpeed()；
/// - 断线（超时 / socket 断开）自动重连一次，仍失败即报断开，
///   读数清 null，不崩、不静默挂起。
class ObdService {
  final ObdPlatform platform;

  /// 录制器（main.dart 在 _init 里 attach；测试可直接传）。
  Recorder? recorder;

  /// 轮询间隔（可注入，测试用长间隔关掉后台轮询、手动单步）。
  final Duration speedPollInterval;
  final Duration slowPollInterval;

  final ValueNotifier<ObdStatus> statusNotifier =
      ValueNotifier<ObdStatus>(ObdStatus.disconnected);

  ObdStatus get status => statusNotifier.value;

  StreamSubscription<String>? _responsesSub;
  StreamSubscription<void>? _connectedSub;
  StreamSubscription<String>? _disconnectedSub;

  Completer<String>? _inFlight;
  final List<String> _responseBuffer = [];
  Completer<void>? _connectCompleter;

  String? _address;
  String _deviceName = '';
  // 本次用户发起的连接里是否已试过重连：只在 connect() 里复位，
  // 成功重连不复位——抖动连接（连上又断）不会无限重连下去，
  // 第二次断线即报断开，由用户手动重连。
  bool _reconnectTried = false;
  bool _dropHandling = false;
  bool _disposed = false;

  Timer? _speedTimer;
  Timer? _slowTimer;

  ObdService({
    required this.platform,
    this.recorder,
    this.speedPollInterval = const Duration(milliseconds: 150),
    this.slowPollInterval = const Duration(seconds: 1),
  }) {
    _responsesSub = platform.responses.listen(_onResponseLine);
    _connectedSub = platform.connected.listen((_) {
      final c = _connectCompleter;
      if (c != null && !c.isCompleted) c.complete();
    });
    _disconnectedSub = platform.disconnected.listen((_) {
      _onSocketDisconnected();
    });
  }

  void attachRecorder(Recorder r) {
    recorder = r;
  }

  void dispose() {
    _disposed = true;
    _stopPolling();
    _responsesSub?.cancel();
    _connectedSub?.cancel();
    _disconnectedSub?.cancel();
    statusNotifier.dispose();
  }

  void _setStatus(ObdStatus s) {
    if (_disposed) return;
    if (statusNotifier.value != s) statusNotifier.value = s;
  }

  /// 连接一台已配对 ELM327。返回 true = 初始化通过、已开始轮询。
  Future<bool> connect(String address, {String deviceName = ''}) async {
    if (status.connected && _address == address) return true;
    _reconnectTried = false;
    return _connectInternal(address, deviceName: deviceName);
  }

  Future<bool> _connectInternal(String address,
      {String deviceName = ''}) async {
    if (_disposed) return false;
    _address = address;
    _deviceName = deviceName;
    _setStatus(ObdStatus(connecting: true, deviceName: deviceName));
    try {
      _connectCompleter = Completer<void>();
      await platform.connect(address);
      await _connectCompleter!.future
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      _fail('连接超时：请确认 ELM327 已开机、在系统蓝牙里已配对，'
          '且未被其它 App 占用。');
      return false;
    }
    // 初始化序列：只有 ATZ 超时才算失败（山寨 ELM327 其余命令
    // 偶有慢响应，解析层已容忍回显，失败也继续轮询、不假装断线）。
    final atz = await _sendCommand('ATZ',
        timeout: const Duration(seconds: 3));
    if (atz == null || atz.timedOut || _disposed) {
      _fail('ELM327 无响应：请确认设备已开机且未被其它 App 占用。');
      return false;
    }
    for (final cmd in obdInitCommands.skip(1)) {
      await _sendCommand(cmd);
      if (_disposed) return false;
    }
    if (_disposed) return false;
    _setStatus(ObdStatus(
        connected: true, deviceName: _deviceName, error: ''));
    _startPolling();
    return true;
  }

  /// 用户主动断开：停轮询、清 OBD 速度、状态回未连接，不重连。
  Future<void> disconnect() async {
    final addr = _address;
    _address = null;
    _reconnectTried = false;
    _stopPolling();
    _inFlight = null;
    try {
      await platform.disconnect();
    } catch (_) {}
    recorder?.clearObdSpeed();
    _setStatus(ObdStatus.disconnected);
    if (addr != null) {
      // 已断开，无需再等 socket 的 disconnected 事件（_onSocketDisconnected
      // 见到未连接态会直接忽略，不会误触发重连）。
    }
  }

  void _fail(String error) {
    _stopPolling();
    _inFlight = null;
    _address = null;
    recorder?.clearObdSpeed();
    _setStatus(ObdStatus(error: error));
  }

  /// 断线后最终报断开（重连一次仍失败时走这里）。
  void _markDisconnected([String error = '']) {
    _stopPolling();
    _inFlight = null;
    _address = null;
    recorder?.clearObdSpeed();
    _setStatus(ObdStatus(
        error: error.isEmpty ? 'OBD 已断开' : error));
  }

  void _onSocketDisconnected() {
    if (!status.connected && !status.connecting) return;
    if (_disposed) return;
    _handleDrop();
  }

  /// 断线处理：重连一次，仍失败即报断开。并发触发只处理一次。
  void _handleDrop() {
    if (_dropHandling || _disposed) return;
    if (!status.connected && !status.connecting) return;
    _dropHandling = true;
    unawaited(_handleDropAsync());
  }

  Future<void> _handleDropAsync() async {
    _stopPolling();
    _inFlight = null;
    final addr = _address;
    final name = _deviceName;
    if (!_reconnectTried && addr != null) {
      _reconnectTried = true;
      try {
        await platform.disconnect();
      } catch (_) {}
      final ok = await _connectInternal(addr, deviceName: name);
      _dropHandling = false;
      if (ok) return;
      // _connectInternal 内部失败已 _fail（状态为未连接 + 原因）。
      return;
    }
    _dropHandling = false;
    _markDisconnected('OBD 已断开（重连失败）');
  }

  void _startPolling() {
    _stopPolling();
    _speedTimer = Timer.periodic(speedPollInterval, (_) => _pollSpeed());
    _slowTimer = Timer.periodic(slowPollInterval, (_) async {
      await _pollSlow();
      _sampleNow();
    });
  }

  void _stopPolling() {
    _speedTimer?.cancel();
    _speedTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
  }

  void _onResponseLine(String line) {
    final pending = _inFlight;
    if (pending == null) return;
    _responseBuffer.add(line);
    if (line.contains('>')) {
      _inFlight = null;
      if (!pending.isCompleted) {
        pending.complete(_responseBuffer.join('\n'));
      }
    }
  }

  /// 发一条命令，等 '>' 提示行或超时。返回 null = 上一条命令
  /// 还在等响应（本 tick 跳过，不堆命令）。
  Future<({ObdReadings readings, bool timedOut})?> _sendCommand(
    String command, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (_inFlight != null) return null;
    final completer = Completer<String>();
    _inFlight = completer;
    _responseBuffer.clear();
    bool sendOk = true;
    try {
      await platform.sendCommand(command);
    } catch (_) {
      sendOk = false;
    }
    if (!sendOk) {
      _inFlight = null;
      return (readings: const ObdReadings(errorKind: 'SEND_FAILED'),
          timedOut: false);
    }
    String raw;
    var timedOut = false;
    try {
      raw = await completer.future.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      raw = _responseBuffer.join('\n');
      _inFlight = null;
    }
    return (readings: parseElmResponse(raw), timedOut: timedOut);
  }

  /// 车速单步轮询（测试入口；生产走 [_speedTimer]）。
  @visibleForTesting
  Future<void> pollSpeedOnce() => _pollSpeed();

  /// 转速 / 油门 / 水温单步轮询（测试入口；生产走 [_slowTimer]）。
  @visibleForTesting
  Future<void> pollSlowOnce() => _pollSlow();

  /// 按当前最新读数存一条实测采样（测试入口；生产走 1 秒定时器）。
  @visibleForTesting
  void sampleNow() => _sampleNow();

  Future<void> _pollSpeed() async {
    if (!status.connected || _disposed) return;
    final res = await _sendCommand(obdCmdSpeed);
    if (res == null || _disposed) return;
    if (res.timedOut ||
        res.readings.errorKind == 'STOPPED' ||
        res.readings.errorKind == 'UNABLE TO CONNECT' ||
        res.readings.errorKind == 'SEND_FAILED') {
      _handleDrop();
      return;
    }
    final v = res.readings.speedKmh;
    if (v == null) {
      // NO DATA / 空响应：ELM 还连着，只把车速清 null，不显示旧值。
      if (res.readings.noData) {
        _setStatus(status.copyWith(speedKmh: null, clearReadings: false));
        recorder?.obdSpeedMs = null;
      }
      return;
    }
    _setStatus(status.copyWith(speedKmh: v));
    recorder?.obdSpeedMs = v / 3.6;
  }

  Future<void> _pollSlow() async {
    if (!status.connected || _disposed) return;
    for (final cmd in [obdCmdRpm, obdCmdThrottle, obdCmdCoolant]) {
      if (!status.connected || _disposed) return;
      final res = await _sendCommand(cmd);
      if (res == null) continue;
      if (res.timedOut ||
          res.readings.errorKind == 'STOPPED' ||
          res.readings.errorKind == 'UNABLE TO CONNECT' ||
          res.readings.errorKind == 'SEND_FAILED') {
        _handleDrop();
        return;
      }
      final r = res.readings;
      if (r.noData) {
        // 该 PID 无数据：对应读数清 null，不断线。
        if (cmd == obdCmdRpm) {
          _setStatus(status.copyWith(rpm: null));
        } else if (cmd == obdCmdThrottle) {
          _setStatus(status.copyWith(throttlePct: null));
        } else {
          _setStatus(status.copyWith(coolantC: null));
        }
        continue;
      }
      if (cmd == obdCmdRpm && r.rpm != null) {
        _setStatus(status.copyWith(rpm: r.rpm));
      } else if (cmd == obdCmdThrottle && r.throttlePct != null) {
        _setStatus(status.copyWith(throttlePct: r.throttlePct));
      } else if (cmd == obdCmdCoolant && r.coolantC != null) {
        _setStatus(status.copyWith(coolantC: r.coolantC));
      }
    }
  }

  void _sampleNow() {
    final s = status;
    final rec = recorder;
    if (rec == null || !s.connected) return;
    final v = s.speedKmh;
    if (v == null) return;
    rec.noteObdSample(
      speedKmh: v,
      rpm: s.rpm,
      throttlePct: s.throttlePct,
      coolantC: s.coolantC,
    );
  }
}

/// 全局 OBD 服务（MethodChannel 真实实现；main.dart 在 _init 里
/// attachRecorder）。设备中心默认用它，测试可另建 ObdService。
final ObdService obdService =
    ObdService(platform: MethodChannelObdPlatform());

/// OBD 连接状态的唯一共享源（录制页药丸 / 复盘页只读）。
final ValueNotifier<ObdStatus> obdStatus = obdService.statusNotifier;
