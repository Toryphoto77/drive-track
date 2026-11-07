import 'package:flutter/material.dart';

/// v1.0.0 两颗药丸同长常量：直连卫星与同步视频记录共用同一
/// [CompactTogglePill]，外层与内层同宽，不再随文字长度伸缩。
///
/// 定宽实测（字 14、横向 padding 12×2、图标 16 + 间隙 6、
/// 文字与拨杆间隙 10、拨杆 36）：
/// - “同步视频记录”（6 字）约 176；
/// - “直连卫星 · 123 颗”（3 位颗数）实测需 255（widget 测试
///   中 252 会溢出 3px，故不能按 252 定）；
/// 280 留了约 25 余量，3 位颗数内不截断；极端超长时 Text
/// 在 Expanded 内用省略号兜底，不溢出。
const double kTogglePillWidth = 280.0;

/// v0.1.9 通用紧凑药丸开关：直连卫星与同步视频记录共用同一组件，
/// 尺寸与交互完全一致（不要再给视频开关另做一套样式）。
///
/// 定好的尺寸方案（v0.1.5 起，不要再把字体放大去配大按钮，也不要
/// 把可点区缩到字体那么小）：
/// - 视觉 pill：高 32，字体 14，左侧小图标 + 文字；
/// - 整行可点区域：高 44（透明 padding 补足），点整行即可开关；
/// - 右侧是与文字视觉匹配的小开关（36×20 自定义拨杆，不是
///   默认 48 高的 Switch，避免开关本身把 pill 撑大；点整行与点
///   拨杆是同一回调，不会出现一次点按触发两次切换）。
class CompactTogglePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accentColor;

  const CompactTogglePill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final enabled = onChanged != null;
    // M2：窄屏上药丸宽取屏宽 - 32（320dp 屏上 288→仍取 280）；MediaQuery
    // 宽度不可用（≤32，如测试里被覆盖的 MediaQuery）时回落到 280，不崩溃。
    final screenW = MediaQuery.of(context).size.width;
    final pillW = (screenW <= 32 || screenW - 32 >= kTogglePillWidth)
        ? kTogglePillWidth
        : screenW - 32;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SizedBox(
        width: pillW,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? () => onChanged!(!value) : null,
            child: Container(
              width: pillW,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              // v1.0.0：文字放 Expanded 内，省略号才真正生效（此前
              // 文字在 mainAxisSize.min 的内 Row 里不受约束，超长会
              // 直接溢出而非省略）；拨杆始终贴右沿；两颗药丸视觉
              // 完全一致，框线/阴影只画在各自药丸容器内，不会挤在一起。
              child: Row(
                children: [
                  Icon(icon, size: 16, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 小拨杆：36×20，圆点 16，200ms easeOutCubic，与菜单动画同曲线。
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 36,
                    height: 20,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: value ? accent : Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 直连卫星紧凑 pill 开关（v0.1.5：开始前快速开关与定位子页同款）。
/// v0.1.9 起委托给 [CompactTogglePill]，与同步视频记录同一组件。
///
/// - 卫星数 [satelliteCount] 为实时值：null = 暂无快照，显示
///   “直连卫星 · —”；非 null 时显示真实颗数（含 0 颗），不编数。
/// - [onChanged] 为 null 时整行置灰且不可点（子页切换进行中用）。
class CompactSatellitePill extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final int? satelliteCount;
  final Color? accentColor;

  const CompactSatellitePill({
    super.key,
    required this.value,
    required this.onChanged,
    required this.satelliteCount,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final countText = satelliteCount == null ? '—' : '$satelliteCount 颗';
    return CompactTogglePill(
      icon: Icons.satellite_alt,
      label: '直连卫星 · $countText',
      value: value,
      onChanged: onChanged,
      accentColor: accentColor,
    );
  }
}
