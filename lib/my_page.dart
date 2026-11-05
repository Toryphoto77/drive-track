import 'dart:io';

import 'package:flutter/material.dart';
import 'app_notice.dart';

import 'card_style.dart';

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

/// 页内编辑的结果：用户名 / 简介 / 头像本机路径，由总协调持久化
/// （建议写回 profile.json 的 username / bio / avatarPath 三个已有键，
/// 与 AppPrefs.save 保持一致，不要另起一套资料存储）。
class ProfileEditResult {
  final String username;
  final String bio;
  final String? avatarPath;
  /// v1.0.7：邮箱（仅存本机，不验证、不发服务器）。
  final String email;
  const ProfileEditResult({
    required this.username,
    required this.bio,
    this.avatarPath,
    this.email = '',
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
  final VoidCallback? onEditProfile;

  /// v0.1.4：页内编辑的保存回调。传了它，资料卡“编辑”钮就在我的页内
  /// 展开编辑器（改用户名 / 简介 / 换头像），保存后即时回显；
  /// 不传时退回旧行为：点“编辑”调 [onEditProfile]（main 侧对话框）。
  final ValueChanged<ProfileEditResult>? onProfileSaved;

  /// v0.1.4：页内编辑时的换头像回调，总协调传 Native.pickFile('image')
  /// 一类实现（返回本机路径，取消返回 null）。不传时点头像只提示
  /// “待接线”，不伪造头像。
  final Future<String?> Function()? onPickAvatar;
  final VoidCallback? onShareInvite;

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
    this.onProfileSaved,
    this.onPickAvatar,
    this.onShareInvite,
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

  // v0.1.4 页内资料编辑：本地显示值（保存后即时回显，不等父级重建）。
  late String _localUsername = widget.username;
  late String _localBio = widget.bio;
  late String _localEmail = widget.email;
  late String? _localAvatarPath = widget.avatarPath;
  bool _editing = false;
  bool _pickingAvatar = false;
  String? _editError;
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.username);
  late final TextEditingController _bioCtrl =
      TextEditingController(text: widget.bio);
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.email);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v0.1.7 菜单“收藏”跳转必需：已在我的页时，父级 initialSection
    // 变化（如切到收藏分区）同步到内部 _section；否则只改 myTab
    // 不会切换已挂载页面的分区。编辑中不覆盖用户输入的规则不变，
    // 分区同步与编辑互不干扰。
    if (widget.initialSection != oldWidget.initialSection) {
      _section = widget.initialSection;
    }
    // 未在编辑时，父级传入的新值同步到本地显示；编辑中不覆盖用户输入。
    if (!_editing) {
      if (widget.username != oldWidget.username) {
        _localUsername = widget.username;
        _nameCtrl.text = widget.username;
      }
      if (widget.bio != oldWidget.bio) {
        _localBio = widget.bio;
        _bioCtrl.text = widget.bio;
      }
      if (widget.email != oldWidget.email) {
        _localEmail = widget.email;
        _emailCtrl.text = widget.email;
      }
      if (widget.avatarPath != oldWidget.avatarPath) {
        _localAvatarPath = widget.avatarPath;
      }
    }
  }

  void _enterEditing() {
    _nameCtrl.text = _localUsername;
    _bioCtrl.text = _localBio;
    _emailCtrl.text = _localEmail;
    setState(() {
      _editing = true;
      _editError = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _editError = null;
      _nameCtrl.text = _localUsername;
      _bioCtrl.text = _localBio;
      _emailCtrl.text = _localEmail;
    });
  }

  Future<void> _pickAvatar() async {
    if (widget.onPickAvatar == null) {
      if (mounted) showAppNotice(context, '换头像待总协调接线：需传入 Native.pickFile(\'image\') 回调', AppNoticeKind.info);
      return;
    }
    if (_pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final path = await widget.onPickAvatar!();
      // 取消返回 null：不改头像、不报错。
      if (path != null && path.isNotEmpty && mounted) {
        setState(() => _localAvatarPath = path);
      }
    } catch (e) {
      if (mounted) {
        showAppNotice(context, '换头像失败：$e', AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  void _saveEditing() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      // 空用户名不保存、不关闭编辑器，只报错，不崩溃。
      setState(() => _editError = '用户名不能为空，请填写后再保存。');
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _editError = '邮箱格式不对，请检查后再保存（可留空不填）。');
      return;
    }
    final result = ProfileEditResult(
      username: name,
      bio: _bioCtrl.text.trim(),
      avatarPath: _localAvatarPath,
      email: email,
    );
    setState(() {
      _localUsername = result.username;
      _localBio = result.bio;
      _localEmail = result.email;
      _editing = false;
      _editError = null;
    });
    widget.onProfileSaved?.call(result);
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
    final path = _localAvatarPath;
    final file = path != null && path.isNotEmpty ? File(path) : null;
    final hasFile = file != null && file.existsSync();
    return Container(
      width: 60,
      height: 60,
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

  Widget _profileCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // 编辑中点头像换头像；非编辑态头像不可点（不跳转别处）。
          _editing
              ? GestureDetector(
                  onTap: _pickingAvatar ? null : _pickAvatar,
                  child: Stack(
                    children: [
                      _avatar(),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _pickingAvatar ? Icons.hourglass_empty : Icons.camera_alt,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : _avatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_localUsername, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('ID · ${widget.userId}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                _localBio.isEmpty ? '暂无简介，点“编辑”添加' : _localBio,
                style: TextStyle(color: _localBio.isEmpty ? Colors.white38 : Colors.white70, fontSize: 13),
              ),
              if (_localEmail.isNotEmpty)
                Text(
                  _localEmail,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          // v0.1.4：有 onProfileSaved 时在页内编辑；否则退回旧 onEditProfile。
          _pillButton(
            label: _editing ? '取消' : '编辑',
            selected: false,
            onTap: _editing
                ? _cancelEditing
                : (widget.onProfileSaved != null ? _enterEditing : widget.onEditProfile),
          ),
        ]),
        if (_editing) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bioCtrl,
            decoration: const InputDecoration(
              labelText: '简介',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱（仅存本机，用作反馈联系方式）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '邮箱仅存本机，不发验证码、不是账号登录绑定，不会发到任何服务器。',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickingAvatar ? null : _pickAvatar,
            icon: const Icon(Icons.image, size: 16),
            label: Text(_pickingAvatar ? '选择头像中…' : '换头像（图片选择 / 文件导入）'),
          ),
          if (_editError != null)
            Text(_editError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: _pillButton(label: '保存', selected: true, onTap: _saveEditing),
          ),
          const SizedBox(height: 4),
          const Text(
            '保存后立即在本页回显；总协调需把结果写回 profile.json（见 ProfileEditResult 注释），否则重启后会回到旧值。',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
        if (widget.onShareInvite != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _pillButton(label: '通过分享邀请', selected: false, onTap: widget.onShareInvite),
          ),
        ],
      ]),
    );
  }

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
        const Text('本月汇总', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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

  /// 社交行：数字原样传入；为 0 时显示“暂无”，不显示假数字，
  /// 也不在卡片外另贴解释长文。
  Widget _socialCard() {
    String show(int n) => n > 0 ? '$n' : '暂无';
    Widget cell(String label, int n) => Expanded(
          child: Column(children: [
            Text(show(n), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        );
    return _card(
      child: Row(children: [
        cell('关注', widget.following),
        cell('粉丝', widget.followers),
        cell('获赞', widget.likes),
      ]),
    );
  }

  Widget _sectionBar() {
    return Row(children: [
      for (final s in MyPageSection.values) ...[
        if (s != MyPageSection.trips) const SizedBox(width: 8),
        Expanded(child: _pillButton(label: s.label, selected: _section == s, onTap: () => _select(s))),
      ],
    ]);
  }

  Widget _tripRow(MyTripItem item, {bool showPublicToggle = false}) {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: item.onTap,
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
        const SizedBox(width: 8),
        Semantics(
          label: '收藏',
          child: IconButton(
            icon: Icon(item.isFavorite ? Icons.star : Icons.star_border,
                color: item.isFavorite ? widget.accentColor : Colors.white54),
            onPressed: item.onToggleFavorite,
          ),
        ),
        if (showPublicToggle)
          _pillButton(
            label: item.isPublic ? '公开' : '仅自己',
            selected: item.isPublic,
            onTap: item.onTogglePublic,
          )
        else
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
            Text(a.achieved ? '已达成' : '未达成',
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

  Widget _empty(String text) {
    return _card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // v1.0.5：底部 padding 由 48 改回 16，仅作正常内容边距；
      // 不再与主框架叠加留出空黑条，内容在药丸下方划过、透过毛玻璃可见。
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _profileCard(),
        const SizedBox(height: 12),
        _statsCard(),
        if (widget.monthlyStats.isNotEmpty) ...[
          const SizedBox(height: 12),
          _monthlyStatsCard(),
        ],
        const SizedBox(height: 12),
        _socialCard(),
        const SizedBox(height: 12),
        _sectionBar(),
        const SizedBox(height: 12),
        if (_section == MyPageSection.trips) ...[
          if (widget.trips.isEmpty)
            _empty('暂无行程\n去首页开始一次记录')
          else
            for (final t in widget.trips) ...[
              _tripRow(t, showPublicToggle: true),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.posts) ...[
          if (widget.posts.isEmpty)
            _empty('暂无动态\n把行程设为公开后会显示在这里')
          else
            for (final p in widget.posts) ...[
              _tripRow(p),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.favorites) ...[
          if (widget.favorites.isEmpty)
            _empty('暂无收藏\n点行程卡片上的星标即可收藏')
          else
            for (final f in widget.favorites) ...[
              _tripRow(f),
              const SizedBox(height: 8),
            ],
        ],
        if (_section == MyPageSection.achievements) ...[
          if (widget.achievements.isEmpty)
            _empty('暂无成就')
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
