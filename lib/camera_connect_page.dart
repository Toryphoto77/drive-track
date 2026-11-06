import 'dart:async';

import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'camera_guide.dart';
import 'device_center.dart';
import 'device_scan_card.dart';
import 'gopro_protocol.dart';
import 'native.dart';

/// 运动相机统一扫描页（v1.2.12）：一个入口、一张大卡片、扫描动画。
///
/// 照 RaceChrono 连接 GPS 页的样子：点“扫描相机”一次扫完，
/// 搜到的相机按卡片列出，品牌自动识别、不用先选品牌，点行即连。
///
/// 品牌识别（纯函数，可单测）：
/// - 广播服务含 FEA6 → GoPro；名称含 GoPro → GoPro（名称仅提示，
///   真正连接仍走 FEA6 服务下的 GP-0072/0073 特征查找）。
/// - 名称含 Insta360 / DJI → 对应品牌，卡片明写“向导连接”。
/// - 两者都不是 → 未知品牌，不进相机列表（只计入扫描总数）。
///
/// 连接方式如实区分，绝不假装：
/// - GoPro：BLE 直连 + Get Version 查询
///   （connectBle → 订阅 GP-0073 → 下发 Get Version [0x01, 0x51]，
///   收到响应并解析通过后状态才变“已连接”）。
/// - Insta360 / DJI：现在仍只能走向导（连相机 Wi-Fi 热点、用各自 App），
///   点行即打开对应 CameraGuidePage，卡片上明确写“向导连接”，
///   本页不显示假的已连接状态。
///
/// 同步录像：本 App 现有的同步视频（Native.startVideoRecording）只录
/// 手机后置摄像头，不是外接相机的录像入口；GoPro 快门命令
/// （buildGoProStartRecording）尚未真机验证，不下发。因此连上后
/// 卡片旁的“开始同步录像”目前是明确标注的占位按钮（“开始同步录像
/// （待接入）”），点按只弹顶部提示说明状态，不编一个假的录像启动。
/// Insta360 / DJI 的录像请在品牌 App 内操作。
///
/// 样式：深色 #121212 + 法拉利红 #E10600（走主题 primary，默认
/// #E10600），与 App 一致；全部提示走 app_notice.dart 顶部弹窗，
/// 不用底部 SnackBar。
/// 本页是独立 widget，不引用 main.dart 的类；设备中心只 push 本页。

enum CameraBrand { gopro, insta360, dji, unknown }

/// 品牌自动识别（纯函数）：广播事实优先，名称其次。
CameraBrand identifyCameraBrand(Map<String, dynamic> dev) {
  final uuids = ((dev['serviceUuids'] as List?) ?? [])
      .map((e) => e.toString())
      .toList();
  if (isGoProAdvertisement(uuids)) return CameraBrand.gopro;
  final name = (dev['name'] ?? '').toString().toLowerCase();
  if (name.contains('gopro')) return CameraBrand.gopro;
  if (name.contains('insta360')) return CameraBrand.insta360;
  if (name.contains('dji')) return CameraBrand.dji;
  return CameraBrand.unknown;
}

String cameraBrandLabel(CameraBrand brand) => switch (brand) {
      CameraBrand.gopro => 'GoPro',
      CameraBrand.insta360 => 'Insta360',
      CameraBrand.dji => 'DJI',
      CameraBrand.unknown => '未知品牌',
    };

/// 连接方式徽标文案：GoPro 直连，其余向导，绝不混淆。
String cameraConnectionLabel(CameraBrand brand) => switch (brand) {
      CameraBrand.gopro => 'BLE 直连',
      CameraBrand.insta360 => '向导连接',
      CameraBrand.dji => '向导连接',
      CameraBrand.unknown => '未知品牌',
    };

/// 是否只能走向导（Insta360 / DJI）：本 App 不直连该品牌相机。
bool cameraBrandIsGuideOnly(CameraBrand brand) =>
    brand == CameraBrand.insta360 || brand == CameraBrand.dji;

CameraGuideBrand? cameraGuideBrandFor(CameraBrand brand) => switch (brand) {
      CameraBrand.insta360 => CameraGuideBrand.insta360,
      CameraBrand.dji => CameraGuideBrand.dji,
      _ => null,
    };

/// 扫描到的相机行（纯数据，便于单测与去重逻辑复用）。
class ScannedCamera {
  const ScannedCamera({
    required this.address,
    required this.name,
    required this.brand,
    this.rssi,
  });

  final String address;
  final String name;
  final CameraBrand brand;
  final int? rssi;

  factory ScannedCamera.fromScan(Map<String, dynamic> dev) {
    final rssi = dev['rssi'];
    return ScannedCamera(
      address: (dev['address'] ?? '').toString(),
      name: (dev['name'] ?? '').toString(),
      brand: identifyCameraBrand(dev),
      rssi: rssi is num ? rssi.toInt() : null,
    );
  }
}

/// 扫描动画与扫描卡片见共用组件 device_scan_card.dart
///（[DeviceScanRipple] / [DeviceScanCard] / [DeviceScanRow]）：
///相机页与外接 GPS 页共用一套，动画节奏、卡片尺寸、字号层级一致。
///本页只保留扫描 / 连接逻辑，样式不再自留一份。
class CameraConnectPage extends StatefulWidget {
  const CameraConnectPage({super.key, this.onBack});

  /// 返回上一页的回调；不传则用 Navigator.maybePop。
  final VoidCallback? onBack;

  @override
  State<CameraConnectPage> createState() => _CameraConnectPageState();
}

class _CameraConnectPageState extends State<CameraConnectPage> {
  final List<Map<String, dynamic>> _scanned = [];
  bool _scanning = false;
  String? _permNotice;
  String _statusLine = '尚未扫描：点下方「扫描相机」开始。';

  DeviceLinkStatus _goproStatus = DeviceLinkStatus.disconnected;
  String? _goproAddress;
  int? _goproBattery; // 仅当原生层回传带地址的电量事件时才有值，否则始终为 null。
  String? _connectingAddress;
  bool _awaitingVersion = false;

  StreamSubscription<Map<String, dynamic>>? _devSub;
  StreamSubscription<Map<String, dynamic>>? _dataSub;

  @override
  void initState() {
    super.initState();
    _devSub = Native.bleDeviceStream.listen((e) {
      final addr = (e['address'] ?? '').toString();
      if (addr.isEmpty || !mounted) return;
      setState(() {
        _scanned.removeWhere((d) => d['address'] == addr);
        _scanned.insert(0, e);
        _statusLine = _scanSummary();
      });
    }, onError: (_) {});
    _dataSub = Native.bleDataStream.listen((e) {
      final type = (e['type'] ?? '').toString();
      final addr = (e['address'] ?? '').toString();
      if (!mounted) return;
      if (type == 'connected') {
        // 只认本页发起的 GoPro 连接：页级其它设备连接不翻本页状态。
        if (_connectingAddress != null && _connectingAddress != addr) return;
        if (addr.isNotEmpty) {
          setState(() {
            _goproAddress = addr;
            _goproStatus = DeviceLinkStatus.connecting;
          });
        }
      } else if (type == 'disconnected') {
        if (_goproAddress == null) return;
        setState(() {
          _goproStatus = DeviceLinkStatus.disconnected;
          _goproAddress = null;
          _goproBattery = null;
          _connectingAddress = null;
          _awaitingVersion = false;
        });
        showAppNotice(context, 'GoPro 已断开。', AppNoticeKind.info);
      } else if (type == 'bleNotification') {
        // GoPro 响应特征 GP-0073：收到响应并解析通过才算连上，
        // 之前只算“已下发查询”。
        final cu = (e['characteristicUuid'] ?? '').toString().toLowerCase();
        if (!cu.contains('0073')) return;
        if (_goproAddress == null ||
            (_connectingAddress != null &&
                _connectingAddress != _goproAddress)) {
          return;
        }
        final bytes = (e['bytes'] as List?)
                ?.map((v) => (v as num).toInt())
                .toList() ??
            <int>[];
        final resp = parseGoProCommandResponse(
          bytes,
          expectedCommandId: 0x51,
        );
        if (!mounted) return;
        setState(() {
          if (resp.ok) {
            _goproStatus = DeviceLinkStatus.connected;
            _awaitingVersion = false;
            _connectingAddress = null;
          } else {
            _goproStatus = DeviceLinkStatus.unavailable;
            _awaitingVersion = false;
            _connectingAddress = null;
          }
        });
        showAppNotice(
          context,
          resp.ok
              ? 'GoPro 已响应 Get Version 查询（GP-0073）：Open GoPro 链路通。'
              : 'GoPro 响应解析失败：${resp.error ?? '未知原因'}。',
          resp.ok ? AppNoticeKind.success : AppNoticeKind.error,
        );
      } else if (type == 'battery' && addr.isNotEmpty) {
        // 原生层目前的 battery 事件不带 address（见 MainActivity），
        // 这里只在带 address 且与已连 GoPro 一致时记录；不带 address
        // 时不乱贴到某台设备。
        final v = e['value'];
        if (v is num && addr == _goproAddress) {
          setState(() => _goproBattery = v.toInt());
        }
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _devSub?.cancel();
    _dataSub?.cancel();
    super.dispose();
  }

  List<ScannedCamera> get _cameras => _scanned
      .map(ScannedCamera.fromScan)
      .where((c) => c.address.isNotEmpty && c.brand != CameraBrand.unknown)
      .toList();

  String _scanSummary() {
    final cams = _cameras.length;
    if (_scanned.isEmpty) return '尚未扫描：点下方「扫描相机」开始。';
    if (cams == 0) {
      return '已扫描 ${_scanned.length} 台设备，其中没有可识别的运动相机'
          '（GoPro 按 FEA6 广播识别，Insta360 / DJI 按名称识别）。';
    }
    return '已扫描 ${_scanned.length} 台设备，找到 $cams 台可识别的运动相机。';
  }

  /// 蓝牙 + 定位权限按系统流程申请（分步 requestStep），拒绝时
  /// 给明确提示 + 系统设置入口，不崩溃、不静默失败。
  Future<bool> _ensureBtPermissions() async {
    try {
      final snap = await Native.checkPermissions();
      var btOk = snap['bluetooth'] == true;
      var locOk = snap['location'] == true;
      if (!btOk) {
        final r = await Native.requestStep('extras');
        btOk = r['bluetooth'] == true;
      }
      if (!locOk) {
        final r2 = await Native.requestStep('foreground');
        locOk = r2['location'] == true;
      }
      if (!mounted) return false;
      setState(() => _permNotice = (btOk && locOk)
          ? null
          : '连接运动相机需要蓝牙与定位权限：当前未获授权，扫描与连接不可用。'
              '请在系统设置里为本 App 打开蓝牙与定位权限后重试。');
      return btOk && locOk;
    } catch (_) {
      if (mounted) {
        setState(() => _permNotice = '权限检查失败：请确认蓝牙已打开且权限已授予。');
      }
      return false;
    }
  }

  /// 一次扫完：GoPro 走 FEA6 过滤扫描，Insta360 / DJI 不广播 FEA6，
  /// 走无过滤扫描按名称识别；结果进同一列表，按地址去重。
  /// 原生单 GATT 与扫描说明见 device_center.dart。
  Future<void> _toggleScan() async {
    if (_scanning) {
      try {
        await Native.stopBleScan();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _statusLine = _scanSummary();
      });
      showAppNotice(context, '已停止扫描。', AppNoticeKind.info);
      return;
    }
    if (!await _ensureBtPermissions()) {
      if (mounted && _permNotice != null) {
        showAppNotice(context, _permNotice!, AppNoticeKind.warning);
      }
      return;
    }
    try {
      await Native.scanBleWithServices([goproAdvertisedServiceUuid]);
      final unfilteredOk = await Native.scanBleUnfiltered();
      if (!mounted) return;
      setState(() {
        _scanning = true;
        _statusLine = '正在扫描周围的运动相机…'
            '${unfilteredOk ? '' : '（无过滤扫描启动失败：Insta360 / DJI 可能扫不到，请确认蓝牙已打开且权限已授予。）'}';
      });
    } catch (e) {
      if (!mounted) return;
      showAppNotice(context, '扫描失败：$e', AppNoticeKind.error);
    }
  }

  /// 点行即连：GoPro 走 BLE 直连 + Get Version 查询；
  /// Insta360 / DJI 打开对应连接向导（本 App 不直连）。
  Future<void> _connectCamera(ScannedCamera cam) async {
    if (cameraBrandIsGuideOnly(cam.brand)) {
      final guideBrand = cameraGuideBrandFor(cam.brand);
      if (guideBrand == null) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CameraGuidePage(
            brand: guideBrand,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
      return;
    }
    if (cam.brand == CameraBrand.gopro) {
      await _connectGoPro(cam);
    }
  }

  /// GoPro 连接：先 connectBle，再订阅响应特征 GP-0073，最后下发 Get Version
  /// 只读查询（[0x01, 0x51]），绝不用快门命令作探测；收到响应并
  /// 解析通过后状态才变“已连接”。
  Future<void> _connectGoPro(ScannedCamera cam) async {
    final address = cam.address;
    if (address.isEmpty) return;
    if (_goproAddress == address &&
        _goproStatus == DeviceLinkStatus.connected) {
      return;
    }
    if (!await _ensureBtPermissions()) {
      if (mounted && _permNotice != null) {
        showAppNotice(context, _permNotice!, AppNoticeKind.warning);
      }
      return;
    }
    // 原生单 GATT：一次只能连一台 BLE 设备，连新设备先断开旧的。
    if (_goproAddress != null && _goproAddress != address) {
      try {
        await Native.disconnectBle();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _goproStatus = DeviceLinkStatus.disconnected;
        _goproAddress = null;
        _goproBattery = null;
        _connectingAddress = null;
        _awaitingVersion = false;
      });
    }
    setState(() {
      _goproStatus = DeviceLinkStatus.connecting;
      _connectingAddress = address;
      _goproAddress = address;
    });
    showAppNotice(
      context,
      '正在连接 GoPro（$address）…连接成功后订阅响应特征并下发查询。',
      AppNoticeKind.info,
    );
    try {
      await Native.setBleAutoReconnect(true);
      await Native.connectBle(address);
      final sub = await Native.subscribeBleCharacteristic(
        address,
        goproAdvertisedServiceUuid,
        goproCommandResponseUuid,
      );
      if ((sub['ok'] as bool?) != true) {
        if (!mounted) return;
        setState(() {
          _goproStatus = DeviceLinkStatus.unavailable;
          _connectingAddress = null;
          _awaitingVersion = false;
        });
        showAppNotice(
          context,
          'GoPro 响应特征订阅失败：${sub['error'] ?? 'unknown'}。'
          '常见原因：GATT 服务发现未完成，或该设备不是 Open GoPro 兼容设备。',
          AppNoticeKind.error,
        );
        return;
      }
      final r = await Native.writeBleCharacteristic(
        address,
        goproAdvertisedServiceUuid,
        goproCommandWriteUuid,
        buildGoProGetVersion(),
      );
      if (!mounted) return;
      if ((r['ok'] as bool?) == true) {
        setState(() => _awaitingVersion = true);
        showAppNotice(
          context,
          'Get Version 查询已下发：等待 GoPro 经 GP-0073 响应，'
          '收到响应后状态才变“已连接”；电量仍以响应/电量事件为准，不编造。',
          AppNoticeKind.info,
        );
        Future.delayed(const Duration(seconds: 15), () {
          if (!mounted) return;
          if (_awaitingVersion && _goproAddress == address) {
            showAppNotice(
              context,
              '仍未收到 GoPro 的 Get Version 响应：请确认相机已开机、蓝牙已打开'
              '且未被其它 App 占用；连接本身未断开，可点“断开”后重试。',
              AppNoticeKind.warning,
            );
          }
        });
      } else {
        setState(() {
          _goproStatus = DeviceLinkStatus.unavailable;
          _connectingAddress = null;
          _awaitingVersion = false;
        });
        showAppNotice(
          context,
          'GoPro 查询下发失败：${r['error'] ?? 'unknown'}。',
          AppNoticeKind.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _goproStatus = DeviceLinkStatus.unavailable;
        _connectingAddress = null;
        _awaitingVersion = false;
      });
      showAppNotice(context, 'GoPro 连接失败：$e', AppNoticeKind.error);
    }
  }

  Future<void> _disconnectGoPro() async {
    try {
      await Native.disconnectBle();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _goproStatus = DeviceLinkStatus.disconnected;
      _goproAddress = null;
      _goproBattery = null;
      _connectingAddress = null;
      _awaitingVersion = false;
    });
    showAppNotice(context, '已断开 GoPro。', AppNoticeKind.info);
  }

  /// “开始同步录像”占位：目前没有可复用的外接相机同步录像入口。
  /// 本 App 现有的同步视频只录手机后置摄像头；GoPro 快门命令
  /// 待真机验证，不下发。点按只说明状态，不编一个假的录像启动。
  void _syncRecordingPlaceholder() {
    showAppNotice(
      context,
      '同步录像尚未接入：本 App 的同步视频目前只录手机后置摄像头；'
      'GoPro 快门遥控待真机验证，暂不下发录像命令。'
      'Insta360 / DJI 请在品牌 App 内录像，行程结束后再按向导里的步骤对齐。',
      AppNoticeKind.warning,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameras = _cameras;
    final connected = _goproStatus == DeviceLinkStatus.connected
        ? cameras.where((c) =>
            c.brand == CameraBrand.gopro && c.address == _goproAddress)
        : const Iterable<ScannedCamera>.empty();
    final connectedCam = connected.isEmpty ? null : connected.first;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: const Text('连接运动相机', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 大卡片：扫描入口 + 扫描动画（转圈 + 波纹），共用组件，
          // 与外接 GPS 页同一套样式。
          DeviceScanCard(
            title: '连接运动相机',
            description: '一个入口扫全部品牌：GoPro 走 BLE 直连，Insta360 / DJI 走'
                ' Wi-Fi 热点 + 品牌 App 向导（本 App 不直连）；品牌自动识别，'
                '不用先选品牌，点行即连。',
            icon: Icons.videocam,
            scanning: _scanning,
            scanLabel: '扫描相机',
            stopLabel: '停止扫描',
            onScanToggle: _toggleScan,
            statusLine:
                _scanning ? '正在扫描周围的运动相机…' : _statusLine,
            permNotice: _permNotice,
            onOpenSettings: () => Native.openAppSettings(),
          ),
          const SizedBox(height: 16),
          const Text(
            '搜到的相机',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (cameras.isEmpty)
            const Text(
              '尚未找到相机：点上方「扫描相机」开始；GoPro 须开机并打开蓝牙，'
              'Insta360 / DJI 须开机（名称广播可见即可识别）。',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          for (final cam in cameras)
            _cameraRow(cam, connectedCam),
          if (connectedCam != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '已连接相机',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _disconnectGoPro,
                        child: const Text('断开'),
                      ),
                    ],
                  ),
                  Text(
                    '${connectedCam.name} · ${connectedCam.address}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _goproBattery == null
                        ? '电量：—（未收到电量事件，不显示假数值）'
                        : '电量：$_goproBattery%',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '连接状态：已连接（已收到 Get Version 响应，Open GoPro 链路通）。',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _syncRecordingPlaceholder,
                      icon: const Icon(Icons.fiber_manual_record, size: 18),
                      label: const Text('开始同步录像（待接入）'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '同步录像尚未接入：本 App 的同步视频目前只录手机后置摄像头，'
                    'GoPro 快门遥控待真机验证，暂不下发录像命令。',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            '原生单 GATT：一次只能连一台 BLE 设备，连新设备会断开旧的；'
            'Insta360 / DJI 的连接是否成功以系统 Wi-Fi 实际连接与品牌 App '
            '内显示为准，本 App 不显示假的已连接状态。',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _cameraRow(
    ScannedCamera cam,
    ScannedCamera? connectedCam,
  ) {
    final isGuide = cameraBrandIsGuideOnly(cam.brand);
    final isConnecting =
        cam.brand == CameraBrand.gopro && _connectingAddress == cam.address;
    final isConnected = connectedCam != null &&
        connectedCam.address == cam.address;
    final guide = isGuide
        ? cameraGuides[cameraGuideBrandFor(cam.brand)!]
        : null;
    // 行卡片走共用组件，与外接 GPS 页同一套行样式；文案原样不动。
    return DeviceScanRow(
      title: cam.name.isEmpty ? cameraBrandLabel(cam.brand) : cam.name,
      badgeLabel: cameraConnectionLabel(cam.brand),
      badgeIsWarning: isGuide,
      detail: isGuide
          ? (guide?.connectionSummary ?? '')
          : 'Open GoPro BLE：点行即连，连接后订阅响应特征 GP-0073 并'
              '下发 Get Version 只读查询，收到响应后才算连上。',
      meta: '${cameraBrandLabel(cam.brand)}'
          '${cam.rssi != null ? ' · 信号 ${cam.rssi}' : ''} · ${cam.address}'
          '${isGuide ? ' · 电量：—（请在品牌 App 内查看）' : ''}',
      actionLabel: isGuide ? '点行打开连接向导' : '点行连接',
      isConnecting: isConnecting,
      isConnected: isConnected,
      onTap: () => _connectCamera(cam),
    );
  }
}
