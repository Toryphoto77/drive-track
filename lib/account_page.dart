import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_auth_page.dart';
import 'cloud_service.dart';
import 'dt_page_route.dart';
import 'glass_button.dart';

/// 账号管理页（v1.7.0）：从设置页进入，展示当前云端账号、同步状态，
/// 提供登录 / 绑定升级 / 退出登录。
///
/// 只读 CloudService 的公开状态，不另建账号体系；退出登录复用
/// CloudService.signOut()，不删除本机行程。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _busy = false;

  CloudService get _svc => CloudService.instance;

  @override
  void initState() {
    super.initState();
    _svc.initialized.then((_) {
      if (mounted) setState(() {});
    });
  }

  String _accountSubtitle(S s) {
    final svc = _svc;
    if (!svc.isConfigured) {
      return s.t('云端未配置，无法登录', 'Cloud not configured');
    }
    if (svc.isAnonymous) {
      return s.t('未登录 · 匿名会话', 'Not signed in · anonymous');
    }
    final phone = svc.currentUserPhone;
    if (phone != null && phone.isNotEmpty) return phone;
    final email = svc.currentUserEmail;
    if (email != null && email.isNotEmpty) return email;
    return s.t('已登录', 'Signed in');
  }

  String _kindLabel(S s) => switch (_svc.loginKind) {
    'phone' => s.t('手机号账号', 'Phone account'),
    'email' => s.t('邮箱账号', 'Email account'),
    _ => s.t('匿名会话（未绑定）', 'Anonymous (not linked)'),
  };

  String _statusLabel(S s) => switch (_svc.status) {
    CloudStatus.uninitialized => s.t('同步中…', 'Connecting…'),
    CloudStatus.unconfigured => s.t('未配置', 'Not configured'),
    CloudStatus.error => s.t('云端连接失败', 'Cloud error'),
    CloudStatus.ready => s.t('云端已就绪', 'Cloud ready'),
  };

  Future<void> _openAuth() async {
    await Navigator.of(context)
        .push(DtPageRoute(builder: (_) => const CloudAuthPage(gate: false)));
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.t('退出登录', 'Sign out')),
        content: Text(
          s.t(
            '退出后需要重新登录才能进入记录界面。本机行程不会删除，云端行程留在原账号下。',
            'You will need to sign in again to open the recorder. Trips stay on this device; cloud trips stay with the account.',
          ),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.t('退出', 'Sign out'),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    await _svc.signOut();
    if (!mounted) return;
    setState(() => _busy = false);
    showAppNotice(context, s.t('已退出登录', 'Signed out'), AppNoticeKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final svc = _svc;
    final configured = svc.isConfigured;
    final signedIn = configured && !svc.isAnonymous;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.maybePop(context)),
        title: Text(s.t('账号管理', 'Account')),
      ),
      body: ListView(
        padding: withAppBarTopInset(
          context,
          const EdgeInsets.fromLTRB(16, 16, 16, 28),
        ),
        children: [
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      signedIn ? Icons.verified_user : Icons.person_outline,
                      size: 22,
                      color: CardStyle.accent(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _accountSubtitle(s),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _row(s.t('账号类型', 'Account type'), _kindLabel(s)),
                const SizedBox(height: 8),
                _row(s.t('用户 ID', 'User ID'), svc.displayUserId),
                const SizedBox(height: 8),
                _row(s.t('云端状态', 'Cloud status'), _statusLabel(s)),
                const SizedBox(height: 8),
                _row(
                  s.t('同步队列', 'Sync queue'),
                  s.t(
                    '待上传 ${svc.pendingCount} · 已上传 ${svc.doneCount} · 失败 ${svc.failedCount}',
                    'pending ${svc.pendingCount} · done ${svc.doneCount} · failed ${svc.failedCount}',
                  ),
                ),
                if (!configured) ...[
                  const SizedBox(height: 10),
                  Text(
                    s.t(
                      '构建时未注入云端环境 ID，当前只能使用本机功能。',
                      'No cloud environment ID was injected at build time.',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (configured)
            DriveTrackCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!signedIn)
                    FilledButton(
                      onPressed: _busy ? null : _openAuth,
                      child: Text(
                        s.t('登录 / 注册 / 绑定账号', 'Sign in / register / link'),
                      ),
                    ),
                  if (signedIn)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signOut,
                      icon: const Icon(Icons.logout, size: 18),
                      label: Text(s.t('退出登录', 'Sign out')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    s.t(
                      '账号用于同步公开资料与行程。邮箱、手机号仅用于登录，不上传给第三方。',
                      'The account syncs your public profile and trips. Email and phone are used for sign-in only.',
                    ),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 76,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    ],
  );
}
