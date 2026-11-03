/// v1.0.3 可切换启动图标：红赛车 / 灰仪表（各一套，见 AndroidManifest
/// 的 activity-alias LauncherRed / LauncherGray）。
///
/// 来源：用户提供的 racing-icons-package_2_l9gm.zip，SVG 本身无水印；
/// 两套启动 PNG 均由 SVG 生成（mdpi 48 / hdpi 72 / xhdpi 96 /
/// xxhdpi 144 / xxxhdpi 192），未直接使用 PNG 原图（右下角有
/// Qoder AI 水印）。App 内图标图（启动页 / 关于页）用同源 512px
/// 资源 assets/app_icon_red.png / app_icon_gray.png，与桌面选择同步。
/// v1.0.4：旧转速表图不再被任何启动路径引用——application 图标与
/// 系统启动图标均已改为红赛车，assets/app_icon.png 已换成红赛车图
/// （并从 pubspec 资源清单移除），mipmap 旧转速表文件仅作未引用
/// 回落保留，不在切换列表里。
/// 持久化键：profile.json 的 'appIcon'，'red'（默认）或 'gray'。
class AppIconChoice {
  AppIconChoice._();

  static const String red = 'red';
  static const String gray = 'gray';

  static bool isValid(String? key) => key == red || key == gray;

  static String normalize(String? key) => isValid(key) ? key! : red;

  /// App 内图标图（启动页 / 关于页用，与桌面选择同步）。
  static String assetFor(String key) =>
      normalize(key) == gray ? 'assets/app_icon_gray.png' : 'assets/app_icon_red.png';

  static String labelFor(String key) =>
      normalize(key) == gray ? '灰仪表' : '红赛车';

  static String descriptionFor(String key) => normalize(key) == gray
      ? '灰仪表（深灰底 #2D2D2D、白仪表盘）'
      : '红赛车（深红底 #C8102E、白 F1 车剪影）';
}
