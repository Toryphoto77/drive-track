import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_service.dart';

/// 云端账号页的三种模式：邮箱登录、邮箱注册、匿名绑邮箱升级。
/// Apple / Google / 微信这期不做（Google OAuth 客户端待 Google
/// 审批，微信要开放平台配置），入口只显示“未配置”；手机号登录
/// 是二期。邮箱注册与绑定邮箱都是两步：先收验证码，再凭验证码
/// 完成；邮箱密码登录是一步。
enum CloudAuthMode { login, register, link }

extension CloudAuthModeLabel on CloudAuthMode {
  String get title => switch (this) {
        CloudAuthMode.login => '登录',
        CloudAuthMode.register => '注册',
        CloudAuthMode.link => '绑定账号升级',
      };

  String get submitLabel => switch (this) {
        CloudAuthMode.login => '登录',
        CloudAuthMode.register => '发送验证码',
        CloudAuthMode.link => '发送验证码',
      };

  String get hint => switch (this) {
        CloudAuthMode.login =>
          '邮箱密码登录。匿名仍是首次启动默认方式，登录后云端行程归当前账号。',
        CloudAuthMode.register =>
          '邮箱注册分两步：先输邮箱和密码收验证码，再输 6 位验证码完成注册（验证码 5 分钟有效）。邮箱已注册时，输验证码会直接登录。',
        CloudAuthMode.link =>
          '给当前匿名账号绑一个邮箱，绑定后仍用同一个账号，云端行程不丢。分两步：先收验证码，再输验证码完成绑定。绑定后账号暂无密码，登录时用邮箱验证码（注册页）。',
      };
}

/// 邮箱登录 / 注册 / 匿名绑邮箱升级。
///
/// 注册与绑定邮箱走 CloudBase 邮箱验证码流程（先发码、再凭码完成）；
/// Apple 与 Google 这期未配置，只展示提示，不跳转、不崩。
class CloudAuthPage extends StatefulWidget {
  final CloudAuthMode mode;
  const CloudAuthPage({super.key, required this.mode});

  @override
  State<CloudAuthPage> createState() => _CloudAuthPageState();
}

class _CloudAuthPageState extends State<CloudAuthPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _codeSent = false;
  String _codeMessage = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 第一步提交：登录（一步完成）或注册/绑定（发验证码）。
  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!isValidCloudEmail(email)) {
      setState(() => _error = '邮箱格式不对');
      return;
    }
    if (widget.mode != CloudAuthMode.link) {
      if (!isValidCloudPassword(password)) {
        setState(() => _error = '密码至少 6 位');
        return;
      }
      if (widget.mode == CloudAuthMode.register &&
          _confirmCtrl.text != password) {
        setState(() => _error = '两次输入的密码不一致');
        return;
      }
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final svc = CloudService.instance;
    final CloudAuthResult r;
    switch (widget.mode) {
      case CloudAuthMode.login:
        r = await svc.signInWithEmail(email, password);
      case CloudAuthMode.register:
        r = await svc.signUpWithEmail(email, password);
      case CloudAuthMode.link:
        r = await svc.linkEmail(email);
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    if (r.needsCode) {
      setState(() {
        _codeSent = true;
        _codeMessage = r.message;
      });
      return;
    }
    showAppNotice(context, r.message, AppNoticeKind.success);
    Navigator.pop(context, true);
  }

  /// 第二步提交：凭验证码完成注册 / 绑定。
  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final svc = CloudService.instance;
    final r = widget.mode == CloudAuthMode.link
        ? await svc.verifyLinkCode(code)
        : await svc.verifySignUpCode(code);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    showAppNotice(context, r.message, AppNoticeKind.success);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(title: Text(mode.title)),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DriveTrackCard(
              child: Text(mode.hint,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            const SizedBox(height: 12),
            if (_codeSent) _codeForm(mode) else _emailForm(mode),
            const SizedBox(height: 12),
            const DriveTrackCard(
              child: Text(
                'Apple / Google 登录未配置：本期不做（Google OAuth 客户端待 Google 审批，微信需开放平台配置）。手机号登录是二期。',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emailForm(CloudAuthMode mode) {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: '邮箱',
              hintText: 'name@example.com',
            ),
          ),
          if (mode != CloudAuthMode.link) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
          if (mode == CloudAuthMode.register) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认密码'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submitEmail,
            child: Text(_submitting ? '提交中…' : mode.submitLabel),
          ),
        ],
      ),
    );
  }

  Widget _codeForm(CloudAuthMode mode) {
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_codeMessage,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '验证码',
              hintText: '6 位数字',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submitCode,
            child: Text(_submitting
                ? '验证中…'
                : mode == CloudAuthMode.link
                    ? '验证并绑定'
                    : '验证并完成注册'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _codeSent = false;
                      _codeCtrl.clear();
                      _error = null;
                    }),
            child: const Text('重新发送验证码'),
          ),
        ],
      ),
    );
  }
}
