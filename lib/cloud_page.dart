import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_auth_page.dart';
import 'cloud_service.dart';
import 'models.dart';

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
  bool _retryingAll = false;

  @override
  void initState() {
    super.initState();
    _tripsFuture = CloudService.instance.listCloudTrips();
  }

  void _refresh() {
    setState(() {
      _tripsFuture = CloudService.instance.listCloudTrips();
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
      appBar: AppBar(title: const Text('云端')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                              '${(r.distanceM / 1000).toStringAsFixed(1)} km · ${(r.durationS ~/ 60)} 分钟 · 评分 ${r.score} · ${r.source == 'device' ? '外接设备' : '手机'}',
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
}
