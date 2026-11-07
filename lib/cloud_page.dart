import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_auth_page.dart';
import 'cloud_service.dart';
import 'models.dart';
import 'public_profile_page.dart';

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

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

  @override
  void initState() {
    super.initState();
    _tripsFuture = CloudService.instance.listCloudTrips();
    _ownProfileFuture = _loadOwnProfile();
  }

  Future<PublicProfile?> _loadOwnProfile() async {
    await CloudService.instance.initialized;
    final id = CloudService.instance.currentUserId;
    if (id == null || id.isEmpty) return null;
    return CloudService.instance.fetchPublicProfile(id);
  }

  @override
  void dispose() {
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
    showAppNotice(context, '重试完成，成功 $okCount 条',
        AppNoticeKind.success);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final svc = CloudService.instance;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: const Text('云端')),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!svc.isConfigured) ...[
              DriveTrackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('云端未配置',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      '构建时未注入 CLOUDBASE_ENV_ID，云端上传与云端行程不可用。本地记录不受影响；带环境 ID 重新构建后即可使用。',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ] else
              FutureBuilder<void>(
                future: svc.initialized,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const DriveTrackCard(
                      child: Row(children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('正在连接云端…'),
                      ]),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _accountCard(svc),
                      const SizedBox(height: 12),
                      _syncCard(svc),
                      const SizedBox(height: 12),
                      _queueCard(svc),
                      const SizedBox(height: 12),
                      _cloudTripsCard(),
                      const SizedBox(height: 12),
                      _publicProfileCard(svc),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(CloudService svc) {
    final isAnon = svc.isAnonymous;
    final email = svc.currentUserEmail;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('账号',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            isAnon
                ? '匿名账号 · ${svc.displayUserId}'
                : '邮箱账号 · ${email ?? svc.displayUserId}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text('状态：${svc.status.label}'
              '${svc.status == CloudStatus.error && svc.lastError.isNotEmpty ? '（${svc.lastError}）' : ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            isAnon
                ? '匿名登录无密码；账号只存在本机与云端，不收集手机号与邮箱。绑定邮箱后可升级为正式账号，行程不丢。'
                : '退出后回到匿名账号；邮箱账号下的云端行程仍在，重新登录可见。',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            '个人页的用户名、简介、头像会同步到云端公开资料，他人打开你的公开资料页可见；邮箱只存本机，不会同步。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isAnon) ...[
                FilledButton(
                  onPressed: () => _openAuth(CloudAuthMode.login),
                  child: const Text('登录'),
                ),
                OutlinedButton(
                  onPressed: () => _openAuth(CloudAuthMode.register),
                  child: const Text('注册'),
                ),
                OutlinedButton(
                  onPressed: () => _openAuth(CloudAuthMode.link),
                  child: const Text('绑定账号升级'),
                ),
              ] else
                OutlinedButton(
                  onPressed: _signOut,
                  child: const Text('退出登录'),
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
    showAppNotice(context, '已退出登录，回到匿名账号', AppNoticeKind.success);
    _refresh();
  }

  Widget _syncCard(CloudService svc) {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('同步状态',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
              '待上传 ${svc.pendingCount} 条 · 已上传 ${svc.doneCount} 条 · 失败 ${svc.failedCount} 条',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('只传你点过“上传到云端”的行程，不自动传。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (svc.failedCount > 0) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _retryingAll ? null : _retryAll,
              child: Text(_retryingAll ? '重试中…' : '重试全部失败'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _queueCard(CloudService svc) {
    final q = svc.queue;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('上传队列',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (q.isEmpty)
            const Text('队列为空',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          for (final e in q) ...[
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${TripModeLabel.fromKey(e.mode).label}行程 · ${_fmtDate(e.startedAtMs)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      '${e.status.label}'
                      '${e.status == CloudUploadStatus.failed && e.lastError.isNotEmpty ? '：${e.lastError}' : ''}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (e.status == CloudUploadStatus.failed)
                TextButton(
                  onPressed: () => _retryEntry(e.tripId),
                  child: const Text('重试'),
                ),
            ]),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _cloudTripsCard() {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('云端行程',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _refresh,
              tooltip: '刷新',
            ),
          ]),
          const SizedBox(height: 4),
          const Text('设为公开并上传的行程，他人打开你的公开资料页可见；仅自己可见的行程只有你能看到。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                return const Text('云端暂无行程\n在行程详情里点“上传到云端”即可上传',
                    style: TextStyle(color: Colors.white54, fontSize: 13));
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
                              '${TripModeLabel.fromKey(r.mode).label}行程 · ${_fmtDate(r.startedAtMs)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${(r.durationS ~/ 60)} 分钟 · 评分 ${r.score} · ${r.source == 'device' ? '外接设备' : '手机'}${r.isPublic ? ' · 公开' : ''}',
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
  Widget _publicProfileCard(CloudService svc) {
    final myId = svc.currentUserId ?? '';
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('公开资料',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<PublicProfile?>(
            future: _ownProfileFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Text('正在加载…',
                    style: TextStyle(color: Colors.white54, fontSize: 13));
              }
              final p = snap.data;
              if (p == null) {
                return const Text('还没同步过公开资料：去个人页编辑昵称、简介后保存即可同步。',
                    style: TextStyle(color: Colors.white54, fontSize: 13));
              }
              return Text(
                '我的公开资料：${p.nickname.isEmpty ? '未设置昵称' : p.nickname}'
                '${p.bio.isEmpty ? '' : ' · ${p.bio}'}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              );
            },
          ),
          const SizedBox(height: 4),
          const Text('昵称、简介、头像与公开行程所有人可见；想收回就把行程改回仅自己可见。',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                child: const Text('查看我的公开资料页'),
              ),
              OutlinedButton(
                onPressed: myId.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: myId));
                        if (context.mounted) {
                          showAppNotice(context, '云端用户 ID 已复制',
                              AppNoticeKind.success);
                        }
                      },
                child: const Text('复制我的云端用户 ID'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otherUserIdCtrl,
            decoration: const InputDecoration(
              labelText: '对方云端用户 ID',
              hintText: '粘贴对方发来的云端用户 ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final id = _otherUserIdCtrl.text.trim();
                if (id.isEmpty) {
                  showAppNotice(context, '请先输入对方云端用户 ID',
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
              child: const Text('打开他人公开资料'),
            ),
          ),
        ],
      ),
    );
  }
}
