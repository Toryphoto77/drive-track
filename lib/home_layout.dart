/// v0.1.10 首页两组三按钮共用的水平布局常量。
///
/// v0.1.9 的问题：两组统一成屏宽减 32、三等分 Expanded，把模式行
/// 和导航栏都拉长拉大了，用户要求改回原来。
///
/// 原始尺寸（v0.1.8 及之前）：模式图标 36px，每项左右 margin 14px，
/// 单项节距 64px，整行宽度 192px，整行在屏幕内居中。
/// v1.5.8：左右 margin 加到 20px，节距 76px、整行 228px，
/// 三个图标之间留出 40px，不再挤在一起。
library;

/// 首页内容区左右边距（大方块行、天气条等其他行仍用 16，不动）。
const double kHomeHorizontalMargin = 16.0;

/// 模式行单项节距：图标 36 + 左右 margin 20 × 2。
/// v1.5.8：左右 margin 由 14 加到 20，三个图标之间留出 40px 空隙。
const double kModeRowItemPitch = 76.0;

/// 模式切换行宽度 = 3 × 76 = 228。
const double kModeRowWidth = 3 * kModeRowItemPitch; // 228.0

/// v1.0.9 方案 A：底部导航栏加宽到 216×56（与模式行解耦，不再同长；
/// v1.0.4 的 176×52 已作废）。
/// 216 宽 / 3 图标 = 每项 72 节距，图标不再挤在一起。
/// v1.5.4：4 项（加设备中心）加宽到 288×56，仍是每项 72 节距。
const double kPillNavWidth = 288.0;

/// 底部导航栏药丸高度 56：图标可点区 48 + 上下 padding 4 × 2。
const double kPillNavHeight = 56.0;

/// 三颗按钮的中心点 x（相对屏幕左边缘），行本身在屏幕内居中。
List<double> tripleCenters(double width) {
  final left = (width - kModeRowWidth) / 2;
  return List<double>.generate(3, (i) => left + (i + 0.5) * kModeRowItemPitch);
}
