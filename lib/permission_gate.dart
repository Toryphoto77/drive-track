import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';
import 'native.dart';

/// 首屏权限引导门。
///
/// 深色引导页（字体不写 fontFamily，由主协调统一设主题字体）。
/// 主流程没有任何“点按钮才请求权限”的实体按钮：首帧后自动按顺序拉系统框
/// check → foreground → extras → background；foreground 通过后，extras /
/// background 即使被拒绝也不阻塞主流程，随后以 AnimatedOpacity 350ms 淡入 child。
///
/// 唯一例外：foreground 被永久拒绝，或非永久拒绝时自动重拉（首次请求外
/// 最多再重拉 2 次，即最多 3 次系统框）仍拒绝，才出现一个去系统设置的次要
/// 入口；从设置页重回前台（AppLifecycleState.resumed）时自动重新 check。
class PermissionGate extends StatefulWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _showSettings = false;
  bool _running = false;
  String _status = '正在自动申请权限…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后才拉系统框：不要在 build 里直接调，避免 build 期间弹框 / 重复触发。
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页（或别处）重回前台时自动重新 check，不依赖用户再点什么。
    if (state == AppLifecycleState.resumed && !_ready && !_running) {
      _recheckOnResume();
    }
  }

  static bool _foregroundGranted(Map<String, dynamic> status) =>
      status['foreground'] == true || status['location'] == true;

  /// 永久拒绝判定：只在刚发起过 foreground 请求、复查仍拒绝时采信。
  /// 首次 check 时从未申请过的权限 rationale 同样为 false，不能直接当永久拒绝。
  static bool _foregroundPermanentlyDenied(Map<String, dynamic> status) {
    final raw = status['permanentlyDenied'];
    if (raw is! List) return false;
    return raw.any((e) =>
        e == 'android.permission.ACCESS_FINE_LOCATION' ||
        e == 'android.permission.ACCESS_COARSE_LOCATION');
  }

  /// extras / background 被拒绝或出错都不阻塞主流程。
  Future<void> _runExtrasAndBackground() async {
    for (final step in const ['extras', 'background']) {
      if (!mounted) return;
      try {
        await Native.requestStep(step);
      } on PlatformException {
        // 忽略：通知 / 蓝牙 / 后台定位缺失时主流程仍可用前台定位记录。
      } catch (_) {
        // 同上：任何 extras/background 异常都不应把用户卡在引导页。
      }
    }
  }

  void _markReady() {
    if (!mounted) return;
    setState(() {
      _ready = true;
      _showSettings = false;
    });
  }

  void _markSettings() {
    if (!mounted) return;
    setState(() {
      _showSettings = true;
      _status = '定位权限被拒绝，驰迹无法记录轨迹。';
    });
  }

  Future<void> _runGate() async {
    if (_running || _ready || !mounted) return;
    _running = true;
    try {
      var status = await Native.checkPermissions();
      if (!mounted) return;
      if (_foregroundGranted(status)) {
        await _runExtrasAndBackground();
        _markReady();
        return;
      }
      // 非永久拒绝自动重拉：首次请求 + 最多 2 次重拉（最多 3 次系统框）。
      var retries = 0;
      while (mounted) {
        await Native.requestStep('foreground');
        if (!mounted) return;
        status = await Native.checkPermissions();
        if (!mounted) return;
        if (_foregroundGranted(status)) {
          await _runExtrasAndBackground();
          _markReady();
          return;
        }
        if (_foregroundPermanentlyDenied(status)) {
          _markSettings();
          return;
        }
        if (retries < 2) {
          retries++;
          continue;
        }
        _markSettings();
        return;
      }
    } catch (_) {
      // check / foreground 异常时不静默放行，也不自动反复弹框：
      // 保持引导页；用户重回前台时会触发 resumed 重新 check。
      if (mounted) {
        setState(() => _status = '权限检查失败，返回前台后自动重试。');
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _recheckOnResume() async {
    if (_running || _ready || !mounted) return;
    // 已在设置入口状态时只做 check，不自动再弹系统框，避免回前台即循环弹框。
    if (_showSettings) {
      _running = true;
      try {
        final status = await Native.checkPermissions();
        if (!mounted) return;
        if (_foregroundGranted(status)) {
          await _runExtrasAndBackground();
          _markReady();
        }
        // 仍拒绝则继续停留在设置入口，不自动弹框。
      } catch (_) {
        // 保持设置入口，下次 resumed 再 check。
      } finally {
        _running = false;
      }
      return;
    }
    // 未进过设置入口的重回前台：走完整自动流程（check → 分步请求）。
    await _runGate();
  }

  String _localizedStatus(S s) => switch (_status) {
        '正在自动申请权限…' => s.t('正在自动申请权限…', 'Requesting permissions…'),
        '定位权限被拒绝，驰迹无法记录轨迹。' => s.t(
            '定位权限被拒绝，驰迹无法记录轨迹。',
            'Location permission denied. DriveTrack cannot record a track.'),
        '权限检查失败，返回前台后自动重试。' => s.t(
            '权限检查失败，返回前台后自动重试。',
            'Permission check failed. It retries when you come back.'),
        _ => _status,
      };

  Widget _buildGuide() {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E13),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  s.t('权限', 'Permissions'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.t('记录轨迹需要以下权限，正在自动申请：', 'Recording needs these permissions. Requesting them now:'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 24),
                Text(
                  s.t(
                    '· 前台定位：记录轨迹与车速\n'
                    '· 后台定位：切后台后继续记录\n'
                    '· 通知：后台记录时显示常驻通知\n'
                    '· 蓝牙：连接骑行功率计 / 踏频 / 心率带',
                    '· Foreground location: track and speed\n'
                    '· Background location: keep recording\n'
                    '· Notifications: ongoing recording notice\n'
                    '· Bluetooth: power, cadence, heart rate',
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.8),
                ),
                const SizedBox(height: 32),
                // 唯一按钮：仅在 foreground 永久拒绝（或自动重拉耗尽仍拒绝）
                // 时出现，且为去系统设置的次要入口，不是“点按钮才请求权限”。
                if (_showSettings) ...[
                  Text(
                    _localizedStatus(s),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: Native.openAppSettings,
                    child: Text(s.t('去系统设置开启定位权限', 'Open system settings for location')),
                  ),
                ] else ...[
                  const CircularProgressIndicator(color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(
                    _localizedStatus(s),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildGuide(),
        IgnorePointer(
          ignoring: !_ready,
          child: AnimatedOpacity(
            opacity: _ready ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 350),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
