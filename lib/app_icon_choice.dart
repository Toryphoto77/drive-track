/// APP 图标选择：只剩 'steering'（方向盘）与 'checkered'（方格旗）两项。
///
/// 删减历史：'red'（大红赛车）/'rb17'/'valkyrie' 已从可选项里移除，
/// 默认回落改为 'steering'。旧 'blue'/'gray' 同样回落到 'steering'。
/// 被删键（'red'/'rb17'/'valkyrie'/'blue'/'gray'）与任何非法键加载时
/// 一律由 normalize 折到 'steering'，运行时不会再出现被删图标。
///
/// 桌面启动图标已是方向盘（AndroidManifest 的 application 图标与
/// LauncherRed / LauncherBlue 垫片都用 @mipmap/ic_launcher_steering）。
/// 废弃的 Flutter assets（app_icon.png / red / rb17 / valkyrie）已删除；
/// activity-alias（含 rb17/valkyrie 组件名）保留——组件启用状态跨升级
/// 粘性，删 alias 会导致 App 无法启动（v1.2.2 教训），对应 mipmap 仍留。
/// App 内图标图（启动页 / 关于页）只走：
/// assets/app_icon_steering.png / assets/app_icon_checkered.png。
/// 持久化键：profile.json 的 'appIcon'，'steering'（默认）或 'checkered'。
class AppIconChoice {
  AppIconChoice._();

  static const String steering = 'steering';
  static const String checkered = 'checkered';

  /// 当前全部可选项（主题页只渲染这两项）。
  static const List<String> options = [steering, checkered];

  static bool isValid(String? key) => key == steering || key == checkered;

  /// 已删除键（'red'/'rb17'/'valkyrie'/'blue'/'gray'）与任何非法键
  /// 一律回落到方向盘默认，绝不留空、不崩溃。
  static String normalize(String? key) {
    return isValid(key) ? key! : steering;
  }

  /// App 内图标图（启动页 / 关于页用，与桌面选择同步）。
  static String assetFor(String key) {
    switch (normalize(key)) {
      case checkered:
        return 'assets/app_icon_checkered.png';
      case steering:
      default:
        return 'assets/app_icon_steering.png';
    }
  }

  static String labelFor(String key) {
    switch (normalize(key)) {
      case checkered:
        return '方格旗';
      case steering:
      default:
        return '方向盘';
    }
  }

  static String descriptionFor(String key) {
    switch (normalize(key)) {
      case checkered:
        return '方格旗（炭灰底、飘动黑白方格旗、红速度线）';
      case steering:
      default:
        return '方向盘（法拉利红底、深灰盘圈、白三辐）';
    }
  }
}
