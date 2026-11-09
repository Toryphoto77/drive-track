import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 全 App 深色半透磨砂顶栏（v1.4.2，用户定：顶栏由不透明改深色半透）。
///
/// 核实结论（改前）：全部 40 处 AppBar 都是不透明的——全局
/// [DriveTrackTheme.appBarTheme] 背景为 `0xFF121212`（alpha 1.0），
/// 另有 15 处还显式写了不透明 `backgroundColor`（`0xFF121212` /
/// `Colors.black` / `_kBg`）。上一轮修圆圈 bug 时的判断复核无误：
/// [GlassButton.back] 的圆底在不透明 AppBar 上只剩一圈细边框，
/// 因此 back 固定为普通箭头（见 glass_button.dart）。
///
/// 取值（与磨砂导航栏同一视觉语言）：
/// - 不透明度 65%：`0xA6121212`（0xA6 = 166/255 ≈ 0.65），落在任务
///   给的黑色 55%–70% 区间内，与底部磨砂药丸导航
///   （frosted_nav_bar.dart：#2A2A2A 顶部 0.68 / 底部 0.62，约 0.65）
///   的不透明度一致；静止时盖在同为 #121212 的脚手架底色上，与改前
///   不透明观感无缝衔接，滚动时内容从栏下透出；
/// - 模糊 sigma 28，与磨砂导航栏的 BackdropFilter（28）一致；
/// - 底部细线已删（v1.5.1，用户反馈：半透栏下的白 8% 细线在真机上
///   看着像一条白色边框线）；标题与正文的区分靠磨砂模糊本身。
///
/// 实现要点：
/// - [DtAppBar] 是 [AppBar] 的子类：底色透明 + elevation /
///   scrolledUnderElevation 归零 + surfaceTint 透明，磨砂层走
///   flexibleSpace（[BackdropFilter] + 65% 黑），覆盖含状态栏在内
///   的整个顶栏高度——状态栏图标同样落在磨砂层上，保持清晰；
/// - 半透只有在内容真正位于栏后时才可见，因此每个配 [DtAppBar]
///   的 Scaffold 都要同时加 `extendBodyBehindAppBar: true`；
///   注意：`extendBodyBehindAppBar: true` 时 Scaffold 会把 body 的
///   MediaQuery 顶垫去掉（body 从 y=0 开始），滚动视图不会自动
///   获得顶垫——不要以为“无显式 padding 的滚动视图静止时首项仍在
///   栏下”，那是错的（v1.4.2 复核：视频回顾页因此漏了顶垫，首屏
///   控件被栏盖住点不到）。每个配 DtAppBar 的页都必须显式加顶垫，
///   见 [withAppBarTopInset]；
/// - 带显式 padding 的滚动视图不吃 MediaQuery 顶垫，须用
///   [withAppBarTopInset] 在原顶垫上叠加 [appBarTopInset]，否则
///   首项会藏进半透顶栏后；非滚动 body（Column / Padding）同理，
///   在顶部补同样高度；
/// - [GlassButton.back] 不动：仍为普通返回箭头（circular 固定
///   false），不改回圆形。白箭头落在磨砂 + 65% 黑上，模糊已把
///   栏后内容漫射开，可读性不受透出内容影响。
class DtAppBar extends AppBar {
  // 注意：AppBar 本身的构造不是 const（见 SDK app_bar.dart），
  // 故此处也不能标 const；调用处一律写 DtAppBar(...) 即可。
  DtAppBar({
    super.key,
    super.leading,
    super.automaticallyImplyLeading,
    super.title,
    super.actions,
    super.centerTitle,
    super.foregroundColor,
    super.titleTextStyle,
    super.toolbarHeight,
    super.titleSpacing,
    super.leadingWidth,
  }) : super(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: const _AppBarFrost(),
        );
}

/// 顶栏磨砂层：BackdropFilter 模糊 + 65% 黑（无底部细线）。
class _AppBarFrost extends StatelessWidget {
  const _AppBarFrost();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: kAppBarBlurSigma,
          sigmaY: kAppBarBlurSigma,
        ),
        child: Container(
          color: kAppBarBackground,
        ),
      ),
    );
  }
}

/// 顶栏底色：#121212，65% 不透明（0xA6 = 166/255 ≈ 0.65）。
/// 与磨砂导航栏约 0.65 的不透明度一致。
const Color kAppBarBackground = Color(0xA6121212);

/// 顶栏模糊半径，与磨砂导航栏一致（28）。
const double kAppBarBlurSigma = 28;

/// 内容顶缘到屏幕顶的距离，使首项贴在半透顶栏下沿。
///
/// 壳外（首页 / 记录的 State context、被 push 的子页）：
/// `padding.top` 只是状态栏，还要加上工具栏高。
/// 壳内（`extendBodyBehindAppBar` 的 body，设备页 / 我的页）：
/// Scaffold 会把已布局的顶栏高度写回 `padding.top`（大于
/// `viewPadding.top`）。这时再加一截 [kToolbarHeight] 会在栏下
/// 空出一条空白。两种调用点共用这一函数，避免各页各加一次。
double appBarTopInset(BuildContext context) {
  final mq = MediaQuery.of(context);
  if (mq.padding.top > mq.viewPadding.top) return mq.padding.top;
  return mq.viewPadding.top + kToolbarHeight;
}

/// 在原 padding 顶部叠加 [appBarTopInset]（其余三边不动）。
EdgeInsets withAppBarTopInset(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(top: padding.top + appBarTopInset(context));
