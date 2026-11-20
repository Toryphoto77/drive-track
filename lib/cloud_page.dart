import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_auth_page.dart';
import 'cloud_service.dart';
import 'cloud_compare.dart';
import 'store.dart';
import 'models.dart';
import 'public_profile_page.dart';

String _fmtDate(int ms, BuildContext context) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (S.of(context).zh) return '${d.month}月${d.day}日 $hm';
  return '${d.month}/${d.day} $hm';
}

String _modeLabel(S s, TripMode mode) => switch (mode) {
      TripMode.car => s.t('汽车', 'Car'),
      TripMode.moto => s.t('摩托', 'Motorcycle'),
      TripMode.kart => s.t('卡丁车', 'Kart'),
      TripMode.bike => s.t('骑行', 'Bike'),
    };

String _cloudStatusLabel(S s, CloudStatus status) => switch (status) {
      CloudStatus.uninitialized => s.t('同步中…', 'Connecting…'),
      CloudStatus.unconfigured => s.t('云端未配置', 'Cloud not configured'),
      CloudStatus.ready => s.t('已连接', 'Connected'),
      CloudStatus.error => s.t('连接失败', 'Connection failed'),
    };

String _uploadStatusLabel(S s, CloudUploadStatus status) =>
    switch (status) {
      CloudUploadStatus.pending => s.t('待上传', 'Pending'),
      CloudUploadStatus.uploading => s.t('上传中', 'Uploading'),
      CloudUploadStatus.done => s.t('已上传', 'Uploaded'),
      CloudUploadStatus.failed => s.t('上传失败', 'Upload failed'),
    };

/// 云端入口页（个人页 → 云端）。
///
/// 未配置时只展示“云端未配置”、不调任何接口、不崩；已配置时
/// 展示账号状态、同步状态、云端行程列表与上传队列（含重试）。
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  late Future<List<CloudTripRow>> _tripsFuture;
  late Future<PublicProfile?> _ownProfileFuture;
  final TextEditingController _otherUserIdCtrl = TextEditingController();
  bool _retryingAll = false;
  bool _comparing = false;
  CloudLocalCompare? _lastCompare;

  @override
  void initState() {
    super.initState();
    _tripsFuture = CloudService.instance.listCloudTrips();
    _ownProfileFuture = _loadOwnProfile();
    CloudService.instance.authVersion.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (mounted) _refresh();
  }

  Future<PublicProfile?> _loadOwnProfile() async {
    await CloudService.instance.initialized;
    final id = CloudService.instance.currentUserId;
    if (id == null || id.isEmpty) return null;
    return CloudService.instance.fetchPublicProfile(id);
  }

  @override
  void dispose() {
    CloudService.instance.authVersion.removeListener(_onAuthChanged);
    _otherUserIdCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _tripsFuture = CloudService.instance.listCloudTrips();
      _ownProfileFuture = _loadOwnProfile();
    });
  }

  Future<void> _retryEntry(String tripId) async {
    final r = await CloudService.instance.retryEntry(tripId);
    if (!mounted) return;
    showAppNotice(context, r.message,
        r.ok ? AppNoticeKind.success : AppNoticeKind.error);
    _refresh();
  }

  Future<void> _retryAll() async {
    if (_retryingAll) return;
    setState(() => _retryingAll = true);
    final okCount = await CloudService.instance.retryAllFailed();
    if (!mounted) return;
    setState(() => _retryingAll = false);
    final s = S.of(context);
    showAppNotice(
        context,
        s.t('重试完成，成功 $okCount 条', 'Retry finished, $okCount succeeded'),
        AppNoticeKind.success);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final svc = CloudService.instance;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(s.t('云端', 'Cloud'))),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!svc.isConfigured) ...[
              DriveTrackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('云端未配置', 'Cloud not configured'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      s.t(
                        '构建时未注入 CLOUDBASE_ENV_ID，云端上传与云端行程不可用。本地记录不受影响；带环境 ID 重新构建后即可使用。',
                        'CLOUDBASE_ENV_ID was not set at build time, so cloud upload and cloud trips are unavailable. Local records are unaffected; rebuild with an environment ID to enable them.',
                      ),
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ] else
              FutureBuilder<void>(
                future: svc.initialized,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return DriveTrackCard(
                      child: Row(children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(s.t('正在连接云端…', 'Connecting to cloud…')),
                      ]),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _accountCard(svc, s),
                      const SizedBox(height: 12),
                      _syncCard(svc, s),
                      const SizedBox(height: 12),
                      _queueCard(svc, s),
                      const SizedBox(height: 12),
                      _cloudTripsCard(s),
                      const SizedBox(height: 12),
                      _publicProfileCard(svc, s),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _accountLine(CloudService svc, bool isAnon, String? email, S s) {
    if (isAnon) return s.t('匿名账号 · ${svc.displayUserId}', 'Anonymous · ${svc.displayUserId}');
    final phone = svc.currentUserPhone;
    return switch (svc.loginKind) {
      'phone' => s.t('手机号账号 · ${phone ?? svc.displayUserId}',
          'Phone account · ${phone ?? svc.displayUserId}'),
      _ => s.t('邮箱账号 · ${email ?? phone ?? svc.displayUserId}',
          'Email account · ${email ?? phone ?? svc.displayUserId}'),
    };
  }

  Widget _accountCard(CloudService svc, S s) {
    final isAnon = svc.isAnonymous;
    final email = svc.currentUserEmail;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('账号', 'Account'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _accountLine(svc, isAnon, email, s),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
              s.t(
                '状态：${_cloudStatusLabel(s, svc.status)}'
                '${svc.status == CloudStatus.error && svc.lastError.isNotEmpty ? '（${svc.lastError}）' : ''}',
                'Status: ${_cloudStatusLabel(s, svc.status)}'
                '${svc.status == CloudStatus.error && svc.lastError.isNotEmpty ? ' (${svc.lastError})' : ''}',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            isAnon
                ? s.t(
                    '这是尚未升级的匿名账号，不能用来进入记录界面。绑定邮箱或手机号后仍是同一个账号，云端行程保留。本机行程不会被删除。',
                    'This anonymous account cannot open the recorder. Linking an email or phone keeps the same account and its cloud trips. Trips on this device are not deleted.',
                  )
                : s.t(
                    '退出后需要重新登录才能继续使用。本机行程保留，不会删除。云端行程留在原账号下，再次登录可见。',
                    'You will need to sign in again to continue. Trips on this device are kept. Cloud trips stay with the account and reappear after signing in.',
                  ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            s.t(
              '个人页的用户名、简介、头像会同步到云端公开资料，他人打开你的公开资料页可见；邮箱只存本机，不会同步。',
              'Your username, bio and avatar are synced to your public cloud profile and visible to anyone opening it. Your email stays on this device and is never synced.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isAnon) ...[
                FilledButton(
                  onPressed: () => _openAuth(CloudAuthMode.login),
                  child: Text(s.t('登录', 'Sign in')),
                ),
                OutlinedButton(
                  onPressed: () => _openAuth(CloudAuthMode.register),
                  child: Text(s.t('注册', 'Sign up')),
                ),
                OutlinedButton(
                  onPressed: () => _openAuth(CloudAuthMode.link),
                  child: Text(s.t('绑定账号升级', 'Link account')),
                ),
              ] else
                OutlinedButton(
                  onPressed: _signOut,
                  child: Text(s.t('退出登录', 'Sign out')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openAuth(CloudAuthMode mode) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CloudAuthPage(mode: mode)),
    );
    if (mounted) _refresh();
  }

  Future<void> _signOut() async {
    await CloudService.instance.signOut();
    if (!mounted) return;
    final s = S.of(context);
    showAppNotice(
        context,
        s.t('已退出登录。本机行程仍保留，重新登录后可继续使用。',
            'Signed out. Trips on this device are kept; sign in again to continue.'),
        AppNoticeKind.success);
    _refresh();
  }

  Future<void> _compareLocalCloud() async {
    if (_comparing) return;
    setState(() => _comparing = true);
    try {
      final store = Store();
      await store.init();
      final local = await store.loadIndex();
      final cmp = await CloudService.instance
          .compareLocalAndCloud(local.map((m) => m.id));
      if (!mounted) return;
      setState(() {
        _lastCompare = cmp;
        _comparing = false;
      });
      showAppNotice(context, cmp.summary, AppNoticeKind.info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _comparing = false);
      showAppNotice(context, 'Compare failed: $e', AppNoticeKind.error);
    }
  }

  Widget _syncCard(CloudService svc, S s) {
    final cmp = _lastCompare;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('同步状态', 'Sync status'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
              s.t(
                '待上传 ${svc.pendingCount} 条 · 已上传 ${svc.doneCount} 条 · 失败 ${svc.failedCount} 条',
                'Pending ${svc.pendingCount} · Uploaded ${svc.doneCount} · Failed ${svc.failedCount}',
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
              s.t(
                '只传你点过“上传到云端”的行程，不自动传。',
                'Only trips you explicitly uploaded are synced; nothing is uploaded automatically.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          const Text(
            'Compare is read-only: no upload, overwrite, or delete. Conflict resolution stays a manual choice.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (cmp != null) ...[
            const SizedBox(height: 8),
            Text(cmp.summary,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _comparing ? null : _compareLocalCloud,
                child: Text(_comparing ? 'Comparing…' : 'Compare local vs cloud'),
              ),
              if (svc.failedCount > 0)
                FilledButton(
                  onPressed: _retryingAll ? null : _retryAll,
                  child: Text(_retryingAll
                      ? s.t('重试中…', 'Retrying…')
                      : s.t('重试全部失败', 'Retry all failed')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _queueCard(CloudService svc, S s) {
    final q = svc.queue;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('上传队列', 'Upload queue'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (q.isEmpty)
            Text(s.t('队列为空', 'Queue is empty'),
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          for (final e in q) ...[
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_modeLabel(s, TripModeLabel.fromKey(e.mode))}${s.t('行程', ' trip')} · ${_fmtDate(e.startedAtMs, context)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      s.t(
                        '${_uploadStatusLabel(s, e.status)}'
                        '${e.status == CloudUploadStatus.failed && e.lastError.isNotEmpty ? '：${e.lastError}' : ''}',
                        '${_uploadStatusLabel(s, e.status)}'
                        '${e.status == CloudUploadStatus.failed && e.lastError.isNotEmpty ? ': ${e.lastError}' : ''}',
                      ),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (e.status == CloudUploadStatus.failed)
                TextButton(
                  onPressed: () => _retryEntry(e.tripId),
                  child: Text(s.t('重试', 'Retry')),
                ),
            ]),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _cloudTripsCard(S s) {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(s.t('云端行程', 'Cloud trips'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _refresh,
              tooltip: s.t('刷新', 'Refresh'),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              s.t(
                '设为公开并上传的行程，他人打开你的公开资料页可见；仅自己可见的行程只有你能看到。',
                'Trips marked public and uploaded are visible on your public profile; private trips are visible only to you.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          FutureBuilder<List<CloudTripRow>>(
            future: _tripsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return Text(
                    s.t('云端暂无行程\n在行程详情里点“上传到云端”即可上传',
                        'No cloud trips yet\nUse "Upload to cloud" in a trip\'s details'),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13));
              }
              return Column(
                children: [
                  for (final r in rows) ...[
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_modeLabel(s, TripModeLabel.fromKey(r.mode))}${s.t('行程', ' trip')} · ${_fmtDate(r.startedAtMs, context)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              s.t(
                                '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${(r.durationS ~/ 60)} 分钟 · 评分 ${r.score} · ${r.source == 'device' ? '外接设备' : '手机'}${r.isPublic ? ' · 公开' : ''}',
                                '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${(r.durationS ~/ 60)} min · Score ${r.score} · ${r.source == 'device' ? 'Device' : 'Phone'}${r.isPublic ? ' · Public' : ''}',
                              ),
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 公开资料区：自己的公开资料自查 + 按云端用户 ID 打开他人公开资料。
  /// 没有用户发现/搜索入口：想看谁的资料，就让对方把云端页里的
  /// “复制我的云端用户 ID”发过来，粘贴到下面打开。
  Widget _publicProfileCard(CloudService svc, S s) {
    final myId = svc.currentUserId ?? '';
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('公开资料', 'Public profile'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<PublicProfile?>(
            future: _ownProfileFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Text(s.t('正在加载…', 'Loading…'),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13));
              }
              final p = snap.data;
              if (p == null) {
                return Text(
                    s.t(
                      '还没同步过公开资料：去个人页编辑昵称、简介后保存即可同步。',
                      'No public profile synced yet: edit your nickname and bio on the profile page and save to sync.',
                    ),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13));
              }
              return Text(
                s.t(
                  '我的公开资料：${p.nickname.isEmpty ? '未设置昵称' : p.nickname}'
                  '${p.bio.isEmpty ? '' : ' · ${p.bio}'}',
                  'My public profile: ${p.nickname.isEmpty ? 'No nickname' : p.nickname}'
                  '${p.bio.isEmpty ? '' : ' · ${p.bio}'}',
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
              s.t(
                '昵称、简介、头像与公开行程所有人可见；想收回就把行程改回仅自己可见。',
                'Nickname, bio, avatar and public trips are visible to everyone. To revoke, set the trip back to private.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: myId.isEmpty
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfilePage(userId: myId),
                          ),
                        );
                      },
                child: Text(s.t('查看我的公开资料页', 'View my public profile')),
              ),
              OutlinedButton(
                onPressed: myId.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: myId));
                        if (context.mounted) {
                          showAppNotice(
                              context,
                              s.t('云端用户 ID 已复制', 'Cloud user ID copied'),
                              AppNoticeKind.success);
                        }
                      },
                child: Text(s.t('复制我的云端用户 ID', 'Copy my cloud user ID')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otherUserIdCtrl,
            decoration: InputDecoration(
              labelText: s.t('对方云端用户 ID', 'Their cloud user ID'),
              hintText:
                  s.t('粘贴对方发来的云端用户 ID', 'Paste the cloud user ID you received'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final id = _otherUserIdCtrl.text.trim();
                if (id.isEmpty) {
                  showAppNotice(
                      context,
                      s.t('请先输入对方云端用户 ID',
                          'Enter their cloud user ID first'),
                      AppNoticeKind.warning);
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublicProfilePage(userId: id),
                  ),
                );
              },
              child: Text(s.t('打开他人公开资料', 'Open their public profile')),
            ),
          ),
        ],
      ),
    );
  }
}
