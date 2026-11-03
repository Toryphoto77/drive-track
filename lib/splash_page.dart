import 'package:flutter/material.dart';

import 'app_icon_choice.dart';

/// v1.0.2 启动页：App 冷启动第一帧只能是本页。
///
/// 开屏前闪不完整页面的根因（v1.0.2 核查，见 main.dart 注释）：
/// 旧写法是 `home: SplashPage(child: PermissionGate(child: HomePage()))`，
/// 存在两处“首页提前进场”：
/// ① HomePage widget 对象在 MaterialApp 首帧构建时就作为实参被
///   构造出来（虽然 State 尚未挂载，但首页骨架已随启动参数进场）；
/// ② 动画跑完 pushReplacement 到 PermissionGate 后，该页 build 是
///   Stack[引导页, AnimatedOpacity(child: HomePage, opacity: 0)]——
///   首页在 opacity 0 下照常 build/布局并启动 _init（定位/天气/
///   行程加载），随后 350ms 淡入，用户看到的就是一张先黑后闪现
///   的不完整首页骨架，而不是干净的启动页 → 首页切换。
/// 修法（本文件 + main.dart 路由）：
/// - SplashPage 不再接收 child：它不持有、不构造任何首页 widget；
/// - 启动第一帧的 Widget 树只有 MaterialApp → SplashPage（纯黑
///   Scaffold + 图标淡入），首页在动画完成前不构建、不渲染；
/// - v1.0.4：启动页底色由纯黑改为深炭灰 #121212（与主框架同步）；
///   首帧图标默认红赛车：appIconKey 默认即 red，AppPrefs 加载完成
///   前绝不读旧 app_icon.png，加载完成后再按用户选择刷新。
/// - 动画跑完才经路由进首页：默认 pushReplacementNamed('/home')，
///   '/home' 的 builder 里才首次构造 PermissionGate(child: HomePage())；
///   传了 [onFinished] 时改调该回调（供主协调在不走命名路由时接线）。
/// - 原生侧不动：launch_background（drawable 与 drawable-v21 两份）
///   与 LaunchTheme/NormalTheme 在 v1.0.0 已是纯黑父主题，Flutter
///   首帧背景亦为纯黑（本页 Scaffold + 全局黑色主题），不改回白。
/// - 图标：当前选择的启动图标（assets/app_icon_red/gray.png，
///   与桌面 alias 同源 SVG 生成），不再固定用旧转速表图；
/// - 文字“驰迹 DriveTrack”淡入，slogan“记录每一次出发”随后淡入；
/// - 总时长约 1.2 秒，缓动 easeOut；动画跑完才切首页，启动页不留
///   在返回栈里（pushReplacement）。
class SplashPage extends StatefulWidget {
  /// 动画完成后的回调；不传时默认走命名路由 '/home'（main.dart 已注册）。
  final VoidCallback? onFinished;

  /// v1.0.3：启动图标选择（'red' 默认 / 'gray'），与桌面 alias 同步；
  /// 由 DriveTrackApp 在 build 时传当前 appPrefs.appIcon，load 完成
  /// 后 AnimatedBuilder 重建会同步刷新（动画 1.2 秒内通常已加载完）。
  final String appIconKey;

  const SplashPage({super.key, this.onFinished, this.appIconKey = AppIconChoice.red});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  bool _navigated = false;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted && !_navigated) {
        _navigated = true;
        if (widget.onFinished != null) {
          widget.onFinished!();
        } else {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    });

  late final Animation<double> _iconOpacity = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );
  late final Animation<double> _iconScale = Tween<double>(begin: 0.92, end: 1.0)
      .animate(CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
  ));
  late final Animation<double> _titleOpacity = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.25, 0.75, curve: Curves.easeOut),
  );
  late final Animation<double> _sloganOpacity = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Opacity(
                opacity: _iconOpacity.value,
                child: Transform.scale(scale: _iconScale.value, child: child),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(AppIconChoice.assetFor(widget.appIconKey), width: 112, height: 112),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _titleOpacity,
              child: const Text(
                '驰迹 DriveTrack',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _sloganOpacity,
              child: const Text(
                '记录每一次出发',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
