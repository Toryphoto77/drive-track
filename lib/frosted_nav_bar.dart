/// v1.0.9 方案 A 深色炭灰玻璃底部导航栏（v1.0.8 白色玻璃的问题：
/// 白药丸在 #121212 深色底上像一张贴纸，白边 0.40 过硬，透过的
/// 内容还会跟深色图标打架；176 宽塞 3 图标也显挤）。
///
/// 规格：
/// - 独立悬浮药丸：高度 56、全圆角（圆角 = 高 / 2）；
///   v1.7.3 起宽度跟随屏幕（左右各 16 留白，最小 288、最大 560），
///   与首页内容卡两侧对齐；4 项（首页 / 设备 / 记录 / 我的）等分；
/// - v1.7.3 液态玻璃：32px 高斯模糊 + 低透明度灰玻璃染色（透出下方
///   内容）、左上斜向液面反光、上亮下暗的 1px 渐变描边、悬浮投影；
///   选中态为主题色径向渐变小玻璃 + 柔光晕；
/// - 图标随玻璃改色：未选中白色 70%，选中主题色，
///   选中圆底为主题色径向渐变（40% → 14%）+ 柔光晕；
/// - 静态玻璃：无滚动放大、无切换拉伸、无选中放大；
/// - 图标只留图标无文字；悬浮位置由调用方 Positioned 直接定
///   （底部 12px + 系统底部 inset），本组件内不再用 SafeArea，
///   不在药丸下方垫出空底色区；
/// - 内容不再为药丸留空：内容从药丸下方划过、透过毛玻璃模糊可见，
///   药丸周边不再是空黑条；
/// - 记录中由调用方隐藏本组件。
/// - 无任何放大动画：不跟随滚动放大、不做切换拉伸回弹、
///   选中图标不放大；选中态只用主题色药丸高光
///   （主题色 22% 底 + 主题色光晕，图标变主题色）。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_haptics.dart';
import 'app_locale.dart';
import 'home_layout.dart';

/// 选中圆左边缘，使圆心落在第 [index] 个等分槽的中心。
///
/// [AnimatedAlign] 的 Alignment 把子组件中心映射到
/// `(parentSize - childSize)` 的剩余空间里，不是父级全宽。
/// `alignX = -1 + (2i+1)/n` 因此会把 48px 选中圆往中间拽：
/// 288 宽、4 项时两端差约 18px、中间两项差约 6px，图标和
/// 圆点看起来错开。槽宽中心与图标、点击区用同一套除法。
double navSelectionLeft({
  required double barWidth,
  required int index,
  required int count,
  double indicatorSize = 48,
}) {
  if (count <= 0 || barWidth <= 0) return 0;
  final slot = barWidth / count;
  final i = index.clamp(0, count - 1);
  return i * slot + (slot - indicatorSize) / 2;
}

class FrostedGlassNavBar extends StatefulWidget {
  const FrostedGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    this.dragProgress,
    this.onDragProgress,
    this.onDragEnd,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  /// 直接拖动底栏时的连续页码与松手吸附回调。
  /// 调用方可借此让 PageView 与药丸一起跟手，而不是松手后才跳页。
  final ValueChanged<double>? onDragProgress;
  final ValueChanged<int>? onDragEnd;

  /// 左右拖拽切页时的连续页码（0.0～3.0）。
  ///
  /// 非 null 时选中药丸直接跟随页码移动、不做隐式动画（跟手）；
  /// 松手后回到 null，改用 320ms easeOutBack 收到 [selectedIndex]。
  final ValueListenable<double?>? dragProgress;

  static const _tabs = [
    (Icons.home, '首页'),
    // 第 2 项：设备中心（与首页/记录/我的同为底栏页，选中态与切换动画一致）。
    // v1.7.1：图标由 Icons.devices 换成 Icons.sensors，和“外接传感器 / GPS”
    // 的语义更贴切，也不会和首页的设备类图标撞脸。
    (Icons.sensors, '设备'),
    (Icons.list_alt, '记录'),
    (Icons.person, '我的'),
  ];

  @override
  State<FrostedGlassNavBar> createState() => _FrostedGlassNavBarState();
}

class _FrostedGlassNavBarState extends State<FrostedGlassNavBar> {
  /// 液态玻璃折射 shader；仅 Impeller 可用，加载失败/不支持时为 null，
  /// 回退到纯高斯模糊（视觉不变，只是没有边缘折射）。
  ui.FragmentShader? _shader;

  // 底栏自身的长按/横拖手势。位置以连续页码表示，拖动期间不经过
  // AnimatedPositioned 的缓动，保证药丸和调用方 PageView 都能逐帧跟手。
  double? _directDragPos;
  double _directDragOrigin = 0;
  double _directDragStartDx = 0;

  void _beginDirectDrag(double dx, bool haptic) {
    final n = FrostedGlassNavBar._tabs.length;
    final origin = widget.selectedIndex.clamp(0, n - 1).toDouble();
    _directDragOrigin = origin;
    _directDragStartDx = dx;
    setState(() => _directDragPos = origin);
    if (haptic) AppHaptics.tap();
    widget.onDragProgress?.call(origin);
  }

  void _updateDirectDrag(double dx, double slotWidth) {
    final current = _directDragPos;
    if (current == null || slotWidth <= 0) return;
    final n = FrostedGlassNavBar._tabs.length;
    final next = (_directDragOrigin + (dx - _directDragStartDx) / slotWidth)
        .clamp(0.0, n - 1.0)
        .toDouble();
    if ((next - current).abs() < 0.0001) return;
    setState(() => _directDragPos = next);
    widget.onDragProgress?.call(next);
  }

  void _endDirectDrag() {
    final current = _directDragPos;
    if (current == null) return;
    final n = FrostedGlassNavBar._tabs.length;
    final target = current.round().clamp(0, n - 1);
    setState(() => _directDragPos = null);
    if (target != widget.selectedIndex) AppHaptics.tap();
    final onDragEnd = widget.onDragEnd;
    if (onDragEnd != null) {
      onDragEnd(target);
    } else {
      widget.onTap(target);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      final shader = program.fragmentShader()
        ..setFloat(2, 24.0) // u_strength：边缘折射位移（px）
        ..setFloat(3, 14.0) // u_blur：模糊半径（shader 内 9 抽样）
        ..setFloat(4, 2.4) // u_chroma：边缘色散（px）
        ..setFloat(5, 34.0); // u_edge：折射生效带宽（px）
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (_) {
      // 测试环境或非 Impeller 后端：静默回退纯模糊。
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  /// 背景滤镜：模糊与折射都在 shader 内完成；不可用时回退纯高斯模糊。
  ui.ImageFilter _backdropFilter() {
    final shader = _shader;
    if (shader == null) {
      return ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32);
    }
    try {
      return ui.ImageFilter.shader(shader);
    } catch (_) {
      return ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final labels = [
      s.t('首页', 'Home'),
      s.t('设备', 'Devices'),
      s.t('记录', 'Trips'),
      s.t('我的', 'Me'),
    ];
    final n = FrostedGlassNavBar._tabs.length;
    final index = widget.selectedIndex.clamp(0, n - 1);
    // v1.7.3：药丸宽度跟随页面左右各 16 的留白，两侧与首页的
    // “标定 / 开始记录”卡片对齐；窄于原 288 时保底，平板最宽 560。
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = (screenWidth - 32).clamp(kPillNavWidth, 560.0);
    // v1.0.5：删掉 SafeArea，底部位置由调用方 Positioned 直接算，
    // 本组件只输出药丸本身，不带任何背景容器。
    return Center(
      child: SizedBox(
        width: barWidth,
        height: kPillNavHeight,
        // 悬浮投影放在裁剪之外，让药丸像“浮”在内容上。
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kPillNavHeight / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kPillNavHeight / 2),
            child: Stack(
              children: [
                // 1) 底色：大半径高斯模糊 + 液态玻璃折射 shader
                //    （仅 Impeller）+ 低透明度灰玻璃染色；不支持 shader
                //    时自动回退纯模糊。
                BackdropFilter(
                  filter: _backdropFilter(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF4A4A50).withValues(alpha: 0.52),
                          const Color(0xFF26262B).withValues(alpha: 0.48),
                        ],
                      ),
                    ),
                  ),
                ),
                // 2) 液面反光：左上斜向白色高光 + 右下微反光，
                //    模拟玻璃受光后的连续质感。
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 0.38, 0.72, 1.0],
                          colors: [
                            Color(0x2EFFFFFF),
                            Color(0x0AFFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x14FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 3) 渐变描边：上沿亮、下沿暗，比单色 1px 边框更像玻璃边缘。
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GlassRimPainter()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox.expand(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slotWidth = constraints.maxWidth / n;
                        final pillWidth = (slotWidth - 12).clamp(40.0, 132.0);
                        // 参考视频的选中态：偏亮的深灰玻璃药丸（不带主题色），
                        // 主题色只用在图标和文字上；只做水平滑动。
                        final pillBase = const Color(0xFF313138);
                        final pillTop = const Color(0xFF3B3B44);
                        // 页面滑动和底栏直接拖动共用连续页码；松手回到
                        // selectedIndex，用 320ms easeOutBack 收尾（Q 弹）。
                        final drag = widget.dragProgress;
                        final directDrag = _directDragPos;
                        Widget indicator(double? dragPos) {
                          final pos = (dragPos ?? index.toDouble())
                              .clamp(0.0, n - 1.0)
                              .toDouble();
                          final dragging = dragPos != null;
                          return AnimatedPositioned(
                            key: const Key('nav-selection-indicator'),
                            duration: dragPos != null
                                ? Duration.zero
                                : const Duration(milliseconds: 320),
                            // Q 弹滑动：easeOutBack 先冲过头再回弹，接近
                            // 参考视频里液态玻璃被“推”过去的手感。
                            curve: Curves.easeOutBack,
                            left: pos * slotWidth + (slotWidth - pillWidth) / 2,
                            top: 0,
                            bottom: 0,
                            width: pillWidth,
                            child: IgnorePointer(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutBack,
                                transformAlignment: Alignment.center,
                                // 拖动时轻微横向拉伸、纵向压扁；松手后弹性恢复，
                                // 位置本身不做插值，避免“跟手”变成“追赶手指”。
                                transform: Matrix4.diagonal3Values(
                                  dragging ? 1.06 : 1.0,
                                  dragging ? 0.96 : 1.0,
                                  1.0,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(26),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [pillTop, pillBase],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.30,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return GestureDetector(
                          key: const Key('nav-drag-gesture'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (d) =>
                              _beginDirectDrag(d.localPosition.dx, false),
                          onHorizontalDragUpdate: (d) =>
                              _updateDirectDrag(d.localPosition.dx, slotWidth),
                          onHorizontalDragEnd: (_) => _endDirectDrag(),
                          onHorizontalDragCancel: _endDirectDrag,
                          onLongPressStart: (d) =>
                              _beginDirectDrag(d.localPosition.dx, true),
                          onLongPressMoveUpdate: (d) =>
                              _updateDirectDrag(d.localPosition.dx, slotWidth),
                          onLongPressEnd: (_) => _endDirectDrag(),
                          onLongPressCancel: _endDirectDrag,
                          child: Stack(
                            children: [
                              if (directDrag != null)
                                indicator(directDrag)
                              else if (drag == null)
                                indicator(null)
                              else
                                ValueListenableBuilder<double?>(
                                  valueListenable: drag,
                                  builder: (context, value, _) =>
                                      indicator(value),
                                ),
                              Row(
                                children: [
                                  for (
                                    var i = 0;
                                    i < FrostedGlassNavBar._tabs.length;
                                    i++
                                  )
                                    Expanded(
                                      // 整槽可点，图标 + 文字在槽中心。
                                      child: Semantics(
                                        label: labels[i],
                                        button: true,
                                        // 药丸是自绘半透明玻璃，不在 Material 上：
                                        // InkWell 的水波/按压高光会画到外层页面的
                                        // Material 上，透出来就是一圈灰白底框。
                                        // 这里用透明 Material 包住并关掉所有高光色。
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              AppHaptics.tap();
                                              widget.onTap(i);
                                            },
                                            splashColor: Colors.transparent,
                                            highlightColor: Colors.transparent,
                                            hoverColor: Colors.transparent,
                                            focusColor: Colors.transparent,
                                            child: Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    FrostedGlassNavBar
                                                        ._tabs[i]
                                                        .$1,
                                                    size: 21,
                                                    color: index == i
                                                        ? accent
                                                        : Colors.white
                                                              .withValues(
                                                                alpha: 0.72,
                                                              ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    labels[i],
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      height: 1.15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: index == i
                                                          ? accent
                                                          : Colors.white
                                                                .withValues(
                                                                  alpha: 0.72,
                                                                ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃边缘描边：上沿亮白、右侧过渡、下沿偏暗，1px 渐变圆角框。
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(kPillNavHeight / 2),
    );
    final shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, size.height),
      const [Color(0x73FFFFFF), Color(0x1AFFFFFF), Color(0x4DFFFFFF)],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) => false;
}
