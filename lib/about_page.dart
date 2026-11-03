import 'dart:io';

import 'package:flutter/material.dart';

import 'app_icon_choice.dart';
import 'card_style.dart';
import 'disclaimer_page.dart';
import 'glass_button.dart';
import 'native.dart';
import 'update_service.dart';

/// v1.0.7 关于页链接（公开仓库，点按用系统浏览器打开）。
const String kDriveTrackRepoUrl = 'https://github.com/wangtao969/drive-track';
const String kDriveTrackAuthorUrl = 'https://github.com/wangtao969';
const String kDriveTrackIssuesUrl = 'https://github.com/wangtao969/drive-track/issues';

/// 关于页（v1.0.3：顶部信息合并 + 强调色回主题色 + 图标跟随选择）。
///
/// 结构：顶部一张有边框大卡（图标 + App 名 + 正式版胶囊 + 版本 /
/// 包名 / 图标 / 开发者 / 数据存储，分行显示）→ 下面只留必要独立卡
/// （在线更新、免责声明入口）。v1.0.2 的“每项一张小卡”已合并，
/// 卡片总数由 7 张减为 3 张。
/// - 版本由调用方传 1.0.3（见 main.dart _showAbout；pubspec 版本号
///   本任务同步改 1.0.3+15，本页不改版本号）。
/// - 更新通道如实表述：正式源未配置时写“正式版更新通道待配置”，
///   不伪造“已是最新版”或假下载链接；检查更新逻辑与
///   update_service.dart 一致（已配置时才按检查结果说话）。
/// - 安全 / 免责区已从本页移除，改由独立免责声明页
///   disclaimer_page.dart 承载；侧拉菜单“安全说明”改推该页。
/// - [scrollToSafety] 为旧参数保留（避免旧调用方编译报错），
///   本页已无安全区，该参数现被忽略，不再滚动到任何区域。
class AboutPage extends StatefulWidget {
  final String versionName;
  final int versionCode;
  final String packageName;
  final String channelLabel;
  final String displayFont;
  final UpdateConfig updateConfig;

  /// v1.0.3：当前启动图标选择（'red' 默认 / 'gray'），顶部大卡的
  /// 图标与“图标”行与桌面 alias 同步，不再固定显示旧转速表图。
  final String appIconKey;

  /// 已废弃：关于页已无安全区，传 true 也不再滚动（保留仅为兼容）。
  final bool scrollToSafety;

  /// v1.0.7：数据备份入口回调（调用方推已有数据导出/备份页，
  /// 关于页不另造一套备份逻辑）。
  final VoidCallback? onOpenBackup;

  const AboutPage({
    super.key,
    this.versionName = UpdateService.currentVersionName,
    this.versionCode = UpdateService.currentVersionCode,
    this.packageName = UpdateService.packageName,
    this.channelLabel = '正式版',
    this.displayFont = 'DriveTrackDisplay',
    this.updateConfig = const UpdateConfig.unconfigured(),
    this.appIconKey = AppIconChoice.red,
    this.scrollToSafety = false,
    this.onOpenBackup,
  });

  /// 主协调接线用路由名（本页需带版本等参数，main.dart 仍用
  /// MaterialPageRoute builder 直推，命名路由仅作标识）。
  static const String routeName = '/about';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  UpdateCheckResult? _check;
  bool _checking = false;
  bool _downloading = false;
  String? _downloadError;
  String? _cacheMsg;

  /// v1.0.7：清除缓存（天气缓存、路网缓存、更新下载包等缓存目录
  /// 下的缓存文件）。只删缓存目录，不删行程数据（filesDir 的
  /// trips 等）与设置（profile.json 在 filesDir，不在缓存目录）。
  Future<void> _clearCache() async {
    var count = 0;
    try {
      final dir = await Native.getCacheDir();
      final d = Directory(dir);
      if (await d.exists()) {
        await for (final e in d.list()) {
          final name = e.path.split('/').last;
          if (name.startsWith('weather_cache') ||
              name.startsWith('road_') ||
              name.startsWith('update-')) {
            try {
              await e.delete(recursive: true);
              count++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _cacheMsg = count > 0 ? '已清除 $count 个缓存文件，行程数据与设置未动。' : '暂无可清除的缓存文件，行程数据与设置未动。');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cacheMsg!)));
    }
  }

  Future<void> _onCheckUpdate() async {
    setState(() {
      _checking = true;
      _downloadError = null;
    });
    final r = await UpdateService.check(config: widget.updateConfig);
    if (mounted) {
      setState(() {
        _check = r;
        _checking = false;
      });
    }
  }

  Future<void> _onDownloadAndInstall() async {
    final r = _check;
    if (r == null || r.downloadUrl == null || r.remoteVersionCode == null) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    final ok = await UpdateService.downloadAndInstall(
      url: r.downloadUrl!,
      remoteVersionCode: r.remoteVersionCode!,
    );
    if (mounted) {
      setState(() {
        _downloading = false;
        if (!ok) _downloadError = '下载或调起安装失败，请检查网络后重试（未确认是否有新版时不谎称最新）';
      });
    }
  }

  /// 有边框信息卡：标题 + 内容（v1.0.3 仅在线更新区用，顶部信息
  /// 已合并进一张大卡，不再每项一张卡）。
  Widget _infoCard({required String title, required Widget child}) {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, color: Colors.white54, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final accent = CardStyle.accent(context);
    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('关于'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          // ---- 顶部一张有边框大卡：图标 + App 名 + 正式版胶囊 +
          // ---- 版本 / 包名 / 图标 / 开发者 / 数据存储（分行显示） ----
          DriveTrackCard(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(AppIconChoice.assetFor(widget.appIconKey),
                      width: 72, height: 72),
                ),
                const SizedBox(height: 12),
                Text(
                  'DriveTrack',
                  style: TextStyle(
                    fontFamily: widget.displayFont,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent),
                  ),
                  child: Text(
                    widget.channelLabel,
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                // v1.0.7：顶部大卡只留图标、App 名、正式版胶囊、版本号；
                // 包名、图标说明、开发者、数据存储等分行说明全部删掉。
                Text(
                  '版本 ${widget.versionName} ${widget.channelLabel}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- 在线更新区（正式版预留，通道状态如实写） ----
          _infoCard(
            title: '在线更新',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本：${widget.versionName}',
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  '更新通道状态：${check?.message ?? (widget.updateConfig.isConfigured ? '已配置正式源，尚未检查' : '正式版更新通道待配置')}',
                  style: TextStyle(
                    fontSize: 14,
                    color: check?.status == UpdateCheckStatus.error
                        ? Colors.orange
                        : widget.updateConfig.isConfigured
                            ? Colors.white70
                            : Colors.orange,
                  ),
                ),
                if (check?.notes != null && check!.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('新版说明：${check.notes}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
                if (_downloadError != null) ...[
                  const SizedBox(height: 4),
                  Text(_downloadError!,
                      style: const TextStyle(color: Colors.orange, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _checking ? null : _onCheckUpdate,
                      child: Text(_checking ? '检查中…' : '检查更新'),
                    ),
                  ),
                  if (check?.status == UpdateCheckStatus.available) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _downloading ? null : _onDownloadAndInstall,
                        child: Text(_downloading ? '下载中…' : '下载并安装'),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // v1.0.7：库链接 / 源码 / 作者 ID（点按用系统浏览器打开）。
          _linkCard(
            icon: Icons.code,
            title: '库链接',
            subtitle: kDriveTrackRepoUrl,
            onTap: () => Native.openUrl(kDriveTrackRepoUrl),
          ),
          const SizedBox(height: 12),
          _linkCard(
            icon: Icons.source,
            title: '源码',
            subtitle: kDriveTrackRepoUrl,
            onTap: () => Native.openUrl(kDriveTrackRepoUrl),
          ),
          const SizedBox(height: 12),
          _linkCard(
            icon: Icons.person,
            title: '作者 ID',
            subtitle: 'wangtao969',
            onTap: () => Native.openUrl(kDriveTrackAuthorUrl),
          ),
          const SizedBox(height: 12),
          // 免责声明入口：关于页本身不再放免责正文，只留入口。
          DriveTrackCard(
            onTap: () => Navigator.pushNamed(context, DisclaimerPage.routeName),
            child: const Row(children: [
              Icon(Icons.description_outlined, color: Colors.white70),
              SizedBox(width: 8),
              Expanded(
                child: Text('免责声明',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
          const SizedBox(height: 12),
          // v1.0.7：意见反馈（无服务端，打开 GitHub Issues 页，不假装提交成功）。
          _linkCard(
            icon: Icons.feedback_outlined,
            title: '意见反馈',
            subtitle: '打开 GitHub Issues 页提交',
            onTap: () => Native.openUrl(kDriveTrackIssuesUrl),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            onTap: _clearCache,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.cleaning_services_outlined, color: Colors.white70),
                SizedBox(width: 8),
                Expanded(
                  child: Text('清除缓存',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                Icon(Icons.chevron_right, color: Colors.white38),
              ]),
              const SizedBox(height: 4),
              const Text('清天气缓存、路网缓存等缓存文件，不删行程数据、不删设置。',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              if (_cacheMsg != null) ...[
                const SizedBox(height: 4),
                Text(_cacheMsg!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          // v1.0.7：数据备份（复用已有数据导出/备份页，不另造备份逻辑）。
          _linkCard(
            icon: Icons.backup_outlined,
            title: '数据备份',
            subtitle: '导出 / 恢复本机行程与设置备份',
            onTap: widget.onOpenBackup,
          ),
          const SizedBox(height: 16),
          // v1.0.7：打赏支持（打赏码待作者提供，不编造二维码或收款账号）。
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.volunteer_activism),
              label: const Text('打赏支持'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DonationPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 关于页链接行卡（库链接 / 源码 / 作者 / 反馈 / 备份共用）。
  Widget _linkCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return DriveTrackCard(
      onTap: onTap,
      child: Row(children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: Colors.white38),
      ]),
    );
  }
}

/// v1.0.7 打赏页：workspace/user/files 里未找到用户给的收款码图，
/// 因此只写“感谢支持，打赏码由作者后续添加”，绝不编造二维码或收款账号。
class DonationPage extends StatelessWidget {
  const DonationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('打赏支持'),
      ),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('感谢支持', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text('打赏码由作者后续添加。', style: TextStyle(color: Colors.white70, fontSize: 15)),
          SizedBox(height: 8),
          Text('本页不展示任何二维码或收款账号，以免误导。',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ]),
      ),
    );
  }
}
