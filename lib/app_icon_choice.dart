/// v1.1.1 可切换启动图标：红赛车 / 蓝仪表（各一套，见 AndroidManifest
/// 的 activity-alias LauncherRed / LauncherBlue）。
///
/// 来源：红为用户提供的 racing-icons-package_0_w5vc.zip 里原图 PNG
/// （icon-racing-car-red-1024.png）只清右下角白边水印，车辆本身未动；
/// 蓝为同包仪表盘原图，底色由炭灰改深蓝 #1E40AF，白边水印已清。
/// 两套启动 PNG 均由 1024 原图 Lanczos 下采样生成（mdpi 48 / hdpi 72 /
/// xhdpi 96 / xxhdpi 144 / xxxhdpi 192），不再用之前 512 的低清版本。
/// App 内图标图（启动页 / 关于页）用同源 1024px 资源
/// assets/app_icon_red.png / app_icon_blue.png，与桌面选择同步。
/// v1.1.1：灰仪表档位已改为蓝仪表；已选旧 'gray' 的用户自动承接 'blue'。
/// 持久化键：profile.json 的 'appIcon'，'red'（默认）或 'blue'。
class AppIconChoice {
  AppIconChoice._();

  static const String red = 'red';
  static const String blue = 'blue';

  static bool isValid(String? key) => key == red || key == blue;

  /// 旧灰仪表键已废弃，统一映射到蓝仪表，保证老用户不被打回红色。
  static String normalize(String? key) {
    if (key == 'gray') return blue;
    return isValid(key) ? key! : red;
  }

  /// App 内图标图（启动页 / 关于页用，与桌面选择同步）。
  static String assetFor(String key) =>
      normalize(key) == blue ? 'assets/app_icon_blue.png' : 'assets/app_icon_red.png';

  static String labelFor(String key) =>
      normalize(key) == blue ? '蓝仪表' : '红赛车';

  static String descriptionFor(String key) => normalize(key) == blue
      ? '蓝仪表（深蓝底 #1E40AF、白仪表盘）'
      : '红赛车（深红底 #C8102E、白 F1 车剪影）';
}
