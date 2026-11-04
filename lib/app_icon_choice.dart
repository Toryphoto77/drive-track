/// v1.1.3 可切换启动图标：红赛车 / RB17 / 女武神（各一套，见 AndroidManifest
/// 的 activity-alias LauncherRed / LauncherRb17 / LauncherValkyrie）。
/// v1.2.2：蓝仪表已删除；新增 'steering'（方向盘）与 'checkered'（方格旗）。
///
/// 来源：红为用户提供的 racing-icons-package_0_w5vc.zip 里原图 PNG
/// （icon-racing-car-red-1024.png）只清右下角白边水印，车辆本身未动；
/// RB17 / 女武神为用户确认的藏青底线条原图；方向盘 / 方格旗为用户
/// 确认的 webp 原图转 PNG。
/// 各套启动 PNG 均由 1024/1600 原图 Lanczos 下采样生成（mdpi 48 / hdpi 72 /
/// xhdpi 96 / xxhdpi 144 / xxxhdpi 192），并套用与红车完全相同的圆角
/// 遮罩（各密度直接复用红车 alpha 遮罩），四角不透明像素逐密度一致。
/// App 内图标图（启动页 / 关于页）用同源 1024px 资源
/// assets/app_icon_red.png / app_icon_rb17.png / app_icon_valkyrie.png /
/// app_icon_steering.png / app_icon_checkered.png，与桌面选择同步。
/// v1.2.2 迁移：旧 'blue' 与历史 'gray' 键加载时一律回落到 'red' 默认，
/// 原生侧收到 'blue' 时同样当 'red' 处理，绝不指向已删除的组件。
/// v1.2.3：Manifest 里恢复的 LauncherBlue 只是启动兼容垫片（图标用红赛车），
/// 不是可选项：isValid('blue') 仍为 false，主题页选项仍只有五项；原生
/// setAppIcon 的禁用清单含该垫片，启动迁移后只剩红赛车启用。
/// 持久化键：profile.json 的 'appIcon'，'red'（默认）、'rb17'、'valkyrie'、
/// 'steering' 或 'checkered'。
class AppIconChoice {
  AppIconChoice._();

  static const String red = 'red';
  static const String rb17 = 'rb17';
  static const String valkyrie = 'valkyrie';
  static const String steering = 'steering';
  static const String checkered = 'checkered';

  static bool isValid(String? key) =>
      key == red ||
      key == rb17 ||
      key == valkyrie ||
      key == steering ||
      key == checkered;

  /// 已删除的蓝仪表键与历史灰仪表键统一回落到红赛车默认。
  static String normalize(String? key) {
    if (key == 'gray' || key == 'blue') return red;
    return isValid(key) ? key! : red;
  }

  /// App 内图标图（启动页 / 关于页用，与桌面选择同步）。
  static String assetFor(String key) {
    switch (normalize(key)) {
      case rb17:
        return 'assets/app_icon_rb17.png';
      case valkyrie:
        return 'assets/app_icon_valkyrie.png';
      case steering:
        return 'assets/app_icon_steering.png';
      case checkered:
        return 'assets/app_icon_checkered.png';
      default:
        return 'assets/app_icon_red.png';
    }
  }

  static String labelFor(String key) {
    switch (normalize(key)) {
      case rb17:
        return 'RB17';
      case valkyrie:
        return '女武神';
      case steering:
        return '方向盘';
      case checkered:
        return '方格旗';
      default:
        return '红赛车';
    }
  }

  static String descriptionFor(String key) {
    switch (normalize(key)) {
      case rb17:
        return 'RB17（藏青底、白外轮廓线条）';
      case valkyrie:
        return '女武神（藏青底、白线条加细节）';
      case steering:
        return '方向盘（法拉利红底、深灰盘圈、白三辐）';
      case checkered:
        return '方格旗（炭灰底、飘动黑白方格旗、红速度线）';
      default:
        return '红赛车（深红底 #C8102E、白 F1 车剪影）';
    }
  }
}
