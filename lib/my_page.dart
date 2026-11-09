import 'dart:io';

import 'package:flutter/material.dart';
import 'app_bar_style.dart';

import 'app_locale.dart';
import 'card_style.dart';
import 'cloud_page.dart';
import 'empty_hud.dart';
import 'cloud_service.dart';
import 'home_layout.dart';

/// 全新个人页（v0.1.3 分工：个人页 UI 重做）。
///
/// 规则：
/// - 数据全部由构造函数传入，不引用 main.dart 的任何类；
/// - 社交数字只显示传入的真实本机数字：为 0 时显示“暂无”，不编数；
/// - 全部卡片化：统一圆角 16、统一间距 12、按钮统一药丸、横条统一
///   细圆角进度条（高 4）配主题色，不出现参差不齐的裸 Text 行；
/// - 本文件只提供 widget，不做任何存储、网络与删除旧文案的操作；
///   替换旧 _buildMyPage 与删除旧提示文案由总协调负责。
///
/// 主题：黑底 + 法拉利红（默认 #E10600，可由 [accentColor] 覆盖，
/// 与设置页主题色保持一致的传入方式）。

/// 个人页分区：行程 / 动态 / 收藏 / 成就。
enum MyPageSection { trips, posts, favorites, achievements }

extension MyPageSectionLabel on MyPageSection {
  String get label => switch (this) {
        MyPageSection.trips => '行程',
        MyPageSection.posts => '动态',
        MyPageSection.favorites => '收藏',
        MyPageSection.achievements => '成就',
      };
}

/// 一条统计：[progress] 为 0..1 的真实进度（例如里程相对目标），
/// 为 null 时不画进度条，绝不由 widget 自己编造进度。
class MyStat {
  final String label;
  final String value;
  final double? progress;
  const MyStat({required this.label, required this.value, this.progress});
}

/// 行程 / 动态 / 收藏共用的行数据（由调用方传入已过滤的真实列表）。
class MyTripItem {
  final String id;
  final String title;
  final String subtitle;
  final bool isFavorite;
  final bool isPublic;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onTogglePublic;
  const MyTripItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isFavorite = false,
    this.isPublic = false,
    this.onTap,
    this.onToggleFavorite,
    this.onTogglePublic,
  });
}

/// 一条成就：[achieved] 由调用方按本机真实行程条件算出；
/// [progress] 为 0..1 的真实进度，为 null 时只显示达成 / 未达成。
class MyAchievement {
  final String title;
  final bool achieved;
  final double? progress;
  const MyAchievement({required this.title, required this.achieved, this.progress});
}

/// 编辑页回传的结果：用户名 / 简介 / 头像本机路径 / 扩展资料，由
/// 总协调持久化（写回 profile.json 的同名字段）并同步云端公开资料。
/// 邮箱仅存本机，不发服务器。
class ProfileEditResult {
  final String username;
  final String bio;
  final String? avatarPath;
  final String email;
  final String gender;
  final String birthday;
  final String industry;
  final String vehicleBrand;
  final String vehicleModel;
  const ProfileEditResult({
    required this.username,
    required this.bio,
    this.avatarPath,
    this.email = '',
    this.gender = '',
    this.birthday = '',
    this.industry = '',
    this.vehicleBrand = '',
    this.vehicleModel = '',
  });
}

class MyPage extends StatefulWidget {
  /// 头像本机文件路径；为 null 或文件不存在时显示默认头像图标。
  final String? avatarPath;
  final String username;
  final String userId;
  final String bio;
  /// v1.0.7：邮箱（本机存储，见 ProfileEditResult 说明）。
  final String email;

  /// 编辑入口：v1.5.1 起点“编辑”推全页编辑页（ProfileEditPage），
  /// 不再在卡片内展开编辑器、不再弹对话框。
  final VoidCallback? onEditProfile;

  final VoidCallback? onShareInvite;

  /// 空态主操作：去首页开始记录。
  final VoidCallback? onStartRecording;

  /// 打开底栏「记录」（index 2）。个人页的行程区只做公开开关，
  /// 完整行程列表在记录页。
  final VoidCallback? onOpenTripsTab;

  /// 统计卡：调用方传入（行程数 / 总里程 / 总时长 / 平均评分等）。
  final List<MyStat> stats;

  /// v0.1.7 当月汇总统计（可选）：传了才在统计卡下方另起一张
  /// 当月卡，不挤进原有统计行；[monthlyNote] 为当月卡下方的口径说明。
  final List<MyStat> monthlyStats;
  final String monthlyNote;

  /// 社交数字：调用方传入的真实本机数字（关注 / 粉丝 / 获赞）。
  final int following;
  final int followers;
  final int likes;

  final List<MyTripItem> trips;
  final List<MyTripItem> posts;
  final List<MyTripItem> favorites;
  final List<MyAchievement> achievements;

  final MyPageSection initialSection;
  final ValueChanged<MyPageSection>? onSectionChanged;
  final Color accentColor;

  const MyPage({
    super.key,
    this.avatarPath,
    required this.username,
    required this.userId,
    required this.bio,
    this.email = '',
    this.onEditProfile,
    this.onShareInvite,
    this.onStartRecording,
    this.onOpenTripsTab,
    required this.stats,
    this.monthlyStats = const [],
    this.monthlyNote = '',
    required this.following,
    required this.followers,
    required this.likes,
    required this.trips,
    required this.posts,
    required this.favorites,
    required this.achievements,
    this.initialSection = MyPageSection.trips,
    this.onSectionChanged,
    this.accentColor = const Color(0xFFE10600),
  });

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late MyPageSection _section = widget.initialSection;

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v0.1.7 菜单“收藏”跳转必需：已在我的页时，父级 initialSection
    // 变化（如切到收藏分区）同步到内部 _section；否则只改 myTab
    // 不会切换已挂载页面的分区。
    if (widget.initialSection != oldWidget.initialSection) {
      _section = widget.initialSection;
    }
  }

  // v1.0.2 卡片统一：大卡 #1E1E1E、圆角 26、细亮边框（见 card_style.dart）。

  void _select(MyPageSection section) {
    setState(() => _section = section);
    widget.onSectionChanged?.call(section);
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return DriveTrackCard(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }

  /// 细圆角进度条：高 4，底色白 12%，前景主题色，进度 clamp 到 0..1。
  Widget _thinBar(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 4,
        color: Colors.white12,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: p,
            child: Container(color: widget.accentColor),
          ),
        ),
      ),
    );
  }

  /// 药丸按钮：选中态红底黑字，未选中态黑底白字 + 白 12% 边框。
  /// 注意：本方法不包 Expanded（避免放进 SizedBox 等非 Flex 父级时
  /// 报错）；需要均分宽度的场景由调用方在外层包 Expanded。
  Widget _pillButton({required String label, required bool selected, required VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
            decoration: BoxDecoration(
              // v1.0.3：选中态用当前主题色（默认法拉利红），不再写死截图蓝；
              // 未选中边框用统一细亮边框。
              color: selected ? CardStyle.accent(context) : Colors.black54,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? CardStyle.accent(context) : CardStyle.borderColor),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
    );
  }

  Widget _avatar() {
    final path = widget.avatarPath;
    final file = path != null && path.isNotEmpty ? File(path) : null;
    final hasFile = file != null && file.existsSync();
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: widget.accentColor, width: 2),
      ),
      child: ClipOval(
        child: hasFile
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: Colors.black54,
                child: Icon(Icons.person, size: 32, color: widget.accentColor),
              ),
      ),
    );
  }

  /// 个人主页式资料卡（v1.5.2）：头行只放头像 + 名字/ID（头像 64，
  /// 名字块只有两行，Row 居中后头像中心与名字块中心齐平）；简介与
  /// 邮箱移到头行下方通栏，不再挤进名字列把头像顶偏。分享钮改小、
  /// 放旁边：36 圆角图标钮，与“编辑”并排在头行右侧。
  Widget _profileCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('ID · ${widget.userId}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          if (widget.onShareInvite != null) ...[
            _iconButton(icon: Icons.share, onTap: widget.onShareInvite, tooltip: '分享'),
            const SizedBox(width: 8),
          ],
          // v1.5.1：点“编辑”推全页编辑页，不再在卡片内展开编辑器。
          _pillButton(
            label: S.of(context).t('编辑', 'Edit'),
            selected: false,
            onTap: widget.onEditProfile,
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          widget.bio.isEmpty ? S.of(context).t('暂无简介，点“编辑”添加', 'No bio yet. Tap Edit.') : widget.bio,
          style: TextStyle(color: widget.bio.isEmpty ? Colors.white38 : Colors.white70, fontSize: 13),
        ),
        if (widget.email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            widget.email,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
        // v1.5.1：关注/粉丝/获赞并进资料卡（原独立社交卡已删）；
        // 数字为调用方传入的真实本机数字，为 0 时显示“暂无”，不编数。
        const SizedBox(height: 14),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _socialCell(S.of(context).t('关注', 'Following'), widget.following),
          _socialCell(S.of(context).t('粉丝', 'Followers'), widget.followers),
          _socialCell(S.of(context).t('获赞', 'Likes'), widget.likes),
        ]),
      ]),
    );
  }

  /// 小圆形图标钮（分享等）：36 高、黑底 + 细亮边框，与药丸按钮同风格。
  Widget _iconButton(
      {required IconData icon, required VoidCallback? onTap, String? tooltip}) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: CardStyle.borderColor),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip, child: btn);
  }

  /// 资料卡内的社交数字格：数字在上、标签在下，居中。
  Widget _socialCell(String label, int n) => Expanded(
        child: Column(children: [
          Text(n > 0 ? '$n' : S.of(context).t('暂无', 'None'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );

  Widget _statsCard() {
    if (widget.stats.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                // v0.1.9 总里程不换行：数字与单位同一行——maxLines 1 +
                // softWrap false 禁止在空格处折行，FittedBox scaleDown
                // 在栏宽内自适应缩小字号，不截断、不把单位挤到下一行。
                // 千分位分组由调用方 formatDistanceKm 负责（如 123,456.7 km）。
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.stats[i].value,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 2),
                Text(widget.stats[i].label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (widget.stats[i].progress != null) ...[
                  const SizedBox(height: 8),
                  _thinBar(widget.stats[i].progress!),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  /// v0.1.7 当月汇总卡：复用统计行的布局，标题写明“本月”，
  /// 下方口径说明由调用方传入（总里程含全部模式、油耗/花费
  /// 仅汽车/摩托、未填写时显示“未填写”）。
  Widget _monthlyStatsCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(S.of(context).t('本月汇总', 'This month'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.monthlyStats.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Column(children: [
                  // v0.1.9：与统计卡同一不换行处理（见 _statsCard 注释）。
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(widget.monthlyStats[i].value,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(widget.monthlyStats[i].label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
            ],
          ],
        ),
        if (widget.monthlyNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(widget.monthlyNote, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ]),
    );
  }

  // 云端一期：个人页云端入口（账号状态 + 同步状态，点进云端页）。
  // 本卡只读 CloudService 的同步状态、不发任何网络请求；
  // 未配置时只显示“云端未配置”，点进去看说明。
  Widget _cloudCard() {
    final svc = CloudService.instance;
    return FutureBuilder<void>(
      future: svc.initialized,
      builder: (context, snap) {
        final subtitle = !svc.isConfigured
            ? '云端未配置'
            : svc.status == CloudStatus.uninitialized
                ? '同步中…'
                : svc.isAnonymous
                    ? '匿名账号 · 待上传 ${svc.pendingCount} 条 · 已上传 ${svc.doneCount} 条 · 失败 ${svc.failedCount} 条'
                    : '已登录 · 待上传 ${svc.pendingCount} 条 · 已上传 ${svc.doneCount} 条 · 失败 ${svc.failedCount} 条';
        return _card(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CloudPage()),
              );
            },
            child: Row(children: [
              const Icon(Icons.cloud_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('云端',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 2),
                    const Text('昵称、简介、头像会同步到云端公开资料，他人打开你的公开资料页可见；邮箱只存本机。',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: Colors.white54),
            ]),
          ),
        );
      },
    );
  }

  /// 分区分段控件（v1.5.1 重做，替代旧的四个独立药丸）：
  /// - 旧药丸的文字错位：标签与数字拼在同一个 Text 里（'行程 12'），
  ///   中文与数字混排时基线不一致、看起来错位；现标签与数字分开
  ///   两个 Text、同一行居中，窄屏下 FittedBox 等比缩小不断行；
  /// - 每段 Expanded 均分、内容用 alignment.center + textAlign.center
  ///   双重居中。
  Widget _sectionBar() {
    final s = S.of(context);
    final achieved =
        widget.achievements.where((a) => a.achieved).length;
    (String, String) parts(MyPageSection section) => switch (section) {
          MyPageSection.trips => (s.t('行程', 'Trips'), '${widget.trips.length}'),
          MyPageSection.posts => (s.t('动态', 'Feed'), '${widget.posts.length}'),
          MyPageSection.favorites => (s.t('收藏', 'Saved'), '${widget.favorites.length}'),
          MyPageSection.achievements =>
            (s.t('成就', 'Badges'), '$achieved/${widget.achievements.length}'),
        };
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: CardStyle.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Row(children: [
          for (final section in MyPageSection.values)
            Expanded(
              child: _sectionSegment(
                label: parts(section).$1,
                count: parts(section).$2,
                selected: _section == section,
                onTap: () => _select(section),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _sectionSegment({
    required String label,
    required String count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? CardStyle.accent(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  count,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tripRow(MyTripItem item, {bool showPublicToggle = false}) {
    final s = S.of(context);
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(
          child: InkWell(
            // 公开管理列表不是第二套行程浏览器，行本身不进详情。
            onTap: showPublicToggle ? null : item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(item.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          ),
        ),
        if (!showPublicToggle) ...[
          const SizedBox(width: 8),
          Semantics(
            label: s.t('收藏', 'Save'),
            child: IconButton(
              icon: Icon(item.isFavorite ? Icons.star : Icons.star_border,
                  color: item.isFavorite ? widget.accentColor : Colors.white54),
              onPressed: item.onToggleFavorite,
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ] else
          _pillButton(
            label: item.isPublic ? s.t('公开', 'Public') : s.t('仅自己', 'Private'),
            selected: item.isPublic,
            onTap: item.onTogglePublic,
          ),
      ]),
    );
  }

  Widget _openTripsCard() {
    final s = S.of(context);
    return DriveTrackCard(
      onTap: widget.onOpenTripsTab,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Icon(Icons.list_alt, color: CardStyle.accent(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('打开行程记录', 'Open trips'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(s.t('完整行程在「记录」页', 'Full list is on the Trips tab'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        const Icon(Icons.chevron_right, color: Colors.white38),
      ]),
    );
  }

  Widget _achievementRow(MyAchievement a) {
    return _card(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(a.achieved ? Icons.emoji_events : Icons.emoji_events_outlined,
            color: a.achieved ? widget.accentColor : Colors.white24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(a.achieved ? S.of(context).t('已达成', 'Done') : S.of(context).t('未达成', 'Not yet'),
                style: TextStyle(color: a.achieved ? widget.accentColor : Colors.white38, fontSize: 12)),
            if (a.progress != null) ...[
              const SizedBox(height: 8),
              _thinBar(a.progress!),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _emptyHud({
    required IconData icon,
    required String status,
  }) {
    final s = S.of(context);
    return EmptyHud(
      icon: icon,
      status: status,
      actionLabel: s.t('开始记录', 'Start recording'),
      onAction: widget.onStartRecording,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // 底栏药丸盖住滚动末尾：留出药丸高 + 距底 12 + 系统底 inset + 间隙。
    final bottomPad = kPillNavHeight + 12 + MediaQuery.paddingOf(context).bottom + 16;
    return SingleChildScrollView(
      // v1.4.2：顶栏改半透 + 主框架 extendBodyBehindAppBar，顶部再加
      // 顶栏高度，首张卡片静止时才不会藏进顶栏后。
      padding: withAppBarTopInset(context, EdgeInsets.fromLTRB(16, 16, 16, bottomPad)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _profileCard(),
        const SizedBox(height: 12),
        _statsCard(),
        if (widget.monthlyStats.isNotEmpty) ...[
          const SizedBox(height: 12),
          _monthlyStatsCard(),
        ],
        const SizedBox(height: 12),
        _cloudCard(),
        const SizedBox(height: 12),
        _sectionBar(),
        const SizedBox(height: 12),
        if (_section == MyPageSection.trips) ...[
          _openTripsCard(),
          const SizedBox(height: 8),
          Text(s.t('公开范围', 'Visibility'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(
            s.t('只切换是否公开。完整行程在「记录」页。',
                'Publish toggles only. Full trips are on the Trips tab.'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (widget.trips.isEmpty)
            _emptyHud(icon: Icons.route, status: s.t('暂无行程', 'No trips yet'))
          else
            for (final t in widget.trips) ...[
              _tripRow(t, showPublicToggle: true),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.posts) ...[
          if (widget.posts.isEmpty)
            _emptyHud(icon: Icons.dynamic_feed, status: s.t('暂无动态', 'No posts yet'))
          else
            for (final p in widget.posts) ...[
              _tripRow(p),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.favorites) ...[
          if (widget.favorites.isEmpty)
            _emptyHud(icon: Icons.star_border, status: s.t('暂无收藏', 'No saved trips'))
          else
            for (final f in widget.favorites) ...[
              _tripRow(f),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.achievements) ...[
          if (widget.achievements.isEmpty)
            _emptyHud(icon: Icons.emoji_events_outlined, status: s.t('暂无成就', 'No badges yet'))
          else
            for (final a in widget.achievements) ...[
              _achievementRow(a),
              const SizedBox(height: 8),
            ],
        ],
      ]),
    );
  }
}
