import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'cloud_phone.dart';
import 'cloud_service.dart';

/// 云端账号页的入口：邮箱登录、邮箱注册、匿名账号绑定升级。
enum CloudAuthMode { login, register, link }

enum CloudAuthTab {
  phoneLogin,
  phoneRegister,
  emailLogin,
  emailRegister,
  upgrade,
}

CloudAuthTab cloudAuthTabForMode(CloudAuthMode mode) => switch (mode) {
      CloudAuthMode.login => CloudAuthTab.phoneLogin,
      CloudAuthMode.register => CloudAuthTab.phoneRegister,
      CloudAuthMode.link => CloudAuthTab.upgrade,
    };

/// 登录 / 注册门。没有非匿名会话时作为启动后的第一屏，不进入记录界面。
///
/// 主方式是手机号短信，号码按国际格式提交。邮箱登录和邮箱注册保留为备用。
/// 已有匿名会话只能走绑定升级，不能直接进入记录界面。
class CloudAuthPage extends StatefulWidget {
  final CloudAuthMode? mode;
  final bool gate;

  const CloudAuthPage({super.key, this.mode, this.gate = false});

  @override
  State<CloudAuthPage> createState() => _CloudAuthPageState();
}

class _CloudAuthPageState extends State<CloudAuthPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dialCtrl = TextEditingController(text: kDefaultPhoneDialCode);
  final _phonePasswordCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  late CloudAuthTab _tab;
  String _dial = kDefaultPhoneDialCode;
  bool _needsCaptcha = false;
  bool _submitting = false;
  String? _error;
  bool _codeSent = false;
  String _codeMessage = '';
  String _codeKind = 'phone';

  @override
  void initState() {
    super.initState();
    final svc = CloudService.instance;
    _tab = widget.mode != null
        ? cloudAuthTabForMode(widget.mode!)
        : svc.hasAnonymousSession
            ? CloudAuthTab.upgrade
            : CloudAuthTab.phoneLogin;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _dialCtrl.dispose();
    _phonePasswordCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  void _selectTab(CloudAuthTab tab) {
    setState(() {
      _tab = tab;
      _error = null;
      _codeSent = false;
      _codeCtrl.clear();
    });
  }

  Future<void> _finish(CloudAuthResult result) async {
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }
    if (result.needsCaptcha) {
      setState(() {
        _needsCaptcha = true;
        _error = result.message;
      });
      return;
    }
    if (result.needsCode) {
      setState(() {
        _codeSent = true;
        _codeMessage = result.message;
        _error = null;
        _needsCaptcha = false;
      });
      return;
    }
    showAppNotice(context, result.message, AppNoticeKind.success);
    if (!widget.gate && Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _submitEmail() async {
    final s = S.of(context);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!isValidCloudEmail(email)) {
      setState(() => _error = s.t('邮箱格式不对', 'Email format is invalid'));
      return;
    }
    if (_tab != CloudAuthTab.upgrade) {
      if (!isValidCloudPassword(password)) {
        setState(() => _error = s.t('密码至少 6 位', 'Password must be at least 6 characters'));
        return;
      }
      if (_tab == CloudAuthTab.emailRegister && _confirmCtrl.text != password) {
        setState(() => _error = s.t('两次输入的密码不一致', 'The two passwords do not match'));
        return;
      }
    }
    setState(() {
      _error = null;
      _submitting = true;
      _codeKind = 'email';
    });
    final svc = CloudService.instance;
    final CloudAuthResult result;
    switch (_tab) {
      case CloudAuthTab.emailLogin:
        result = await svc.signInWithEmail(email, password);
      case CloudAuthTab.emailRegister:
        result = await svc.signUpWithEmail(email, password);
      case CloudAuthTab.upgrade:
        result = await svc.linkEmail(email);
      case CloudAuthTab.phoneLogin:
      case CloudAuthTab.phoneRegister:
        result = const CloudAuthResult(ok: false, message: '');
    }
    await _finish(result);
  }

  Future<void> _submitPhone() async {
    final s = S.of(context);
    _dial = _dialCtrl.text.trim();
    final phone = formatCloudPhoneNumber(_dial, _phoneCtrl.text);
    if (!isValidCloudPhoneNumber(phone)) {
      setState(() => _error = s.t(
            '请输入有效手机号。号码会按国际格式提交，例如 +86 13800000000、+852 51234567。',
            'Enter a valid phone number. It is sent in international format, for example +86 13800000000 or +852 51234567.',
          ));
      return;
    }
    final captcha = _captchaCtrl.text.trim();
    final CloudAuthResult result;
    if (_tab == CloudAuthTab.upgrade) {
      setState(() {
        _error = null;
        _submitting = true;
        _codeKind = 'phoneLink';
      });
      result = await CloudService.instance.linkPhone(phone);
    } else if (_tab == CloudAuthTab.phoneRegister) {
      final password = _phonePasswordCtrl.text;
      if (password.isNotEmpty && !isValidCloudPassword(password)) {
        setState(() => _error = s.t('密码至少 6 位，或留空', 'Use at least 6 characters, or leave the password empty'));
        return;
      }
      setState(() {
        _error = null;
        _submitting = true;
        _codeKind = 'phoneSignUp';
      });
      result = await CloudService.instance.requestPhoneSignUpCode(
        phone,
        password: password.isEmpty ? null : password,
        captchaToken: captcha.isEmpty ? null : captcha,
      );
    } else {
      setState(() {
        _error = null;
        _submitting = true;
        _codeKind = 'phoneSignIn';
      });
      result = await CloudService.instance.requestPhoneSignInCode(
        phone,
        captchaToken: captcha.isEmpty ? null : captcha,
      );
    }
    await _finish(result);
  }

  Future<void> _submitCode() async {
    final s = S.of(context);
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = s.t('请输入 6 位验证码', 'Enter the 6-digit code'));
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final svc = CloudService.instance;
    final CloudAuthResult result;
    if (_codeKind == 'phoneLink') {
      result = await svc.verifyLinkPhoneCode(code);
    } else if (_codeKind == 'phoneSignUp') {
      result = await svc.verifyPhoneSignUpCode(code);
    } else if (_codeKind == 'phoneSignIn') {
      result = await svc.verifyPhoneSignInCode(code);
    } else if (_tab == CloudAuthTab.upgrade) {
      result = await svc.verifyLinkCode(code);
    } else {
      result = await svc.verifySignUpCode(code);
    }
    await _finish(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final svc = CloudService.instance;
    final upgrade = svc.hasAnonymousSession;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        automaticallyImplyLeading: !widget.gate,
        title: Text(s.t('登录', 'Sign in')),
      ),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(
            context, const EdgeInsets.fromLTRB(16, 16, 16, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.gate) ...[
              const LanguageSwitch(),
              const SizedBox(height: 12),
            ],
            DriveTrackCard(
              child: Text(
                s.t(
                  '使用驰迹前需要登录云端账号。请先用手机号登录；没有账号时用手机号注册。邮箱仍可登录或注册。匿名登录不能进入记录界面。本机已有行程不会被删除。',
                  'A CloudBase account is required before using DriveTrack. Sign in with a phone number, or register a new phone number. Email is still available. Anonymous sign-in cannot open the recording screen. Trips already on this device are not deleted.',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            if (!svc.isConfigured) ...[
              const SizedBox(height: 12),
              DriveTrackCard(
                child: Text(
                  s.t(
                    '云端未配置：构建时未注入环境 ID，无法登录。本地行程文件仍在，配置后重新构建即可登录使用。',
                    'Cloud is not configured: the environment ID was not injected at build time, so sign-in is unavailable. Trip files on this device remain. Rebuild with the environment ID to sign in.',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
            if (upgrade) ...[
              const SizedBox(height: 12),
              DriveTrackCard(
                child: Text(
                  s.t(
                    '本机仍有未升级的匿名云端账号。请绑定邮箱或手机号后继续使用同一个账号，云端行程保留。也可以改用其它邮箱或手机号登录；本机行程仍留在这台设备上。',
                    'This device still has an anonymous cloud account that has not been upgraded. Bind an email or phone number to keep the same account and its cloud trips. You can also sign in with another email or phone number. Trips on this device stay on this device.',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _tabs(s, upgrade),
            const SizedBox(height: 12),
            if (_codeSent) _codeForm(s) else _form(s),
          ],
        ),
      ),
    );
  }

  Widget _tabs(S s, bool upgrade) {
    final tabs = <CloudAuthTab>[
      CloudAuthTab.phoneLogin,
      CloudAuthTab.phoneRegister,
      CloudAuthTab.emailLogin,
      CloudAuthTab.emailRegister,
      if (upgrade) CloudAuthTab.upgrade,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tab in tabs)
          ChoiceChip(
            label: Text(_tabLabel(s, tab)),
            selected: _tab == tab,
            onSelected: _submitting ? null : (_) => _selectTab(tab),
          ),
      ],
    );
  }

  String _tabLabel(S s, CloudAuthTab tab) => switch (tab) {
        CloudAuthTab.phoneLogin => s.t('手机号登录', 'Phone sign-in'),
        CloudAuthTab.phoneRegister => s.t('手机号注册', 'Phone sign-up'),
        CloudAuthTab.emailLogin => s.t('邮箱登录', 'Email sign-in'),
        CloudAuthTab.emailRegister => s.t('邮箱注册', 'Email sign-up'),
        CloudAuthTab.upgrade => s.t('绑定升级', 'Bind and upgrade'),
      };

  Widget _form(S s) {
    if (_tab == CloudAuthTab.phoneLogin) {
      return _phoneForm(s, purpose: 'signIn');
    }
    if (_tab == CloudAuthTab.phoneRegister) {
      return _phoneForm(s, purpose: 'signUp');
    }
    if (_tab == CloudAuthTab.upgrade) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emailForm(s),
          const SizedBox(height: 12),
          _phoneForm(s, purpose: 'link'),
        ],
      );
    }
    return _emailForm(s);
  }

  Widget _emailForm(S s) {
    final configured = CloudService.instance.isConfigured;
    final register = _tab == CloudAuthTab.emailRegister;
    final link = _tab == CloudAuthTab.upgrade;
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            link
                ? s.t(
                    '绑定邮箱分两步：先收取验证码，再输入 6 位验证码完成。绑定后仍是同一个账号。绑定后暂无密码，之后可用邮箱验证码登录。',
                    'Binding an email takes two steps: request a code, then enter the 6-digit code. The account stays the same. There is no password yet; later, sign in with an email code.',
                  )
                : register
                    ? s.t(
                        '邮箱注册分两步：先填写邮箱和密码并收取验证码，再输入 6 位验证码完成注册。邮箱已注册时，输入验证码会直接登录。',
                        'Email sign-up takes two steps: enter the email and password to receive a code, then enter the 6-digit code. If the email is already registered, the code signs you in.',
                      )
                    : s.t(
                        '使用邮箱和密码登录。登录后云端行程归当前账号。',
                        'Sign in with email and password. Cloud trips belong to the signed-in account.',
                      ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.t('邮箱', 'Email'),
              hintText: 'name@example.com',
            ),
          ),
          if (!link) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: s.t('密码', 'Password')),
            ),
          ],
          if (register) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration:
                  InputDecoration(labelText: s.t('确认密码', 'Confirm password')),
            ),
          ],
          if (_tab != CloudAuthTab.upgrade && _error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          if (link && _error != null && _phoneCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (!configured || _submitting) ? null : _submitEmail,
            child: Text(_submitting
                ? s.t('提交中…', 'Submitting…')
                : link
                    ? s.t('发送邮箱验证码', 'Send email code')
                    : register
                        ? s.t('发送验证码', 'Send code')
                        : s.t('登录', 'Sign in')),
          ),
        ],
      ),
    );
  }

  Widget _phoneForm(S s, {required String purpose}) {
    final configured = CloudService.instance.isConfigured;
    final zh = s.zh;
    final known = kPhoneCountryCodes.any((c) => c.dial == _dial);
    final hint = switch (purpose) {
      'signUp' => s.t(
          '注册分两步：先向未注册的号码发短信，再输入 6 位验证码完成注册。密码可留空。号码按国际格式提交，例如 +86 13800000000、+852 51234567。没有国家码时才按 +86 处理。短信需在 CloudBase 控制台开通，并完成腾讯云短信签名与模板审核；中国大陆与国际号码分开配置。',
          'Sign-up takes two steps: send an SMS to a number that is not registered, then enter the 6-digit code. The password can be left empty. Numbers are sent in international format, for example +86 13800000000 or +852 51234567. +86 is added only when no country code is present. SMS must be enabled in the CloudBase console, with mainland and international templates approved separately.',
        ),
      'link' => s.t(
          '绑定手机号分两步：先发短信验证码，再输入 6 位验证码。绑定后仍是同一个账号，云端行程保留。号码按国际格式提交。',
          'Binding a phone number takes two steps: send an SMS code, then enter the 6-digit code. The account stays the same and cloud trips stay with it. The number is sent in international format.',
        ),
      _ => s.t(
          '登录分两步：先向已注册的号码发短信，再输入 6 位验证码登录。还没有账号请用手机号注册。号码按国际格式提交，例如 +852 51234567。没有国家码时才按 +86 处理。',
          'Sign-in takes two steps: send an SMS to a registered number, then enter the 6-digit code. If you do not have an account, use phone sign-up. Numbers are sent in international format, for example +852 51234567. +86 is added only when no country code is present.',
        ),
    };
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          Text(s.t('常用国家或地区', 'Common countries or regions'),
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButton<String>(
            value: known ? _dial : null,
            isExpanded: true,
            hint: Text(s.t('其他区号请在下面填写', 'Enter another code below')),
            dropdownColor: const Color(0xFF1E1E1E),
            items: [
              for (final country in kPhoneCountryCodes)
                DropdownMenuItem(
                  value: country.dial,
                  child: Text(country.label(zh)),
                ),
            ],
            onChanged: _submitting
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _dial = value;
                      _dialCtrl.text = value;
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dialCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: s.t('国际区号', 'Country code'),
              hintText: '+86',
            ),
            onChanged: (value) => setState(() => _dial = value.trim()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: s.t('手机号', 'Phone number'),
              hintText: _dial == '+86' ? '13800000000' : '51234567',
            ),
          ),
          if (purpose == 'signUp') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _phonePasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: s.t('密码（可选）', 'Password (optional)'),
              ),
            ),
          ],
          if (_needsCaptcha) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _captchaCtrl,
              decoration: InputDecoration(
                labelText: s.t('图形验证码令牌', 'Captcha token'),
              ),
            ),
          ],
          if (_error != null &&
              (purpose != 'link' || _phoneCtrl.text.trim().isNotEmpty)) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (!configured || _submitting) ? null : _submitPhone,
            child: Text(_submitting
                ? s.t('提交中…', 'Submitting…')
                : s.t('发送短信验证码', 'Send SMS code')),
          ),
        ],
      ),
    );
  }

  Widget _codeForm(S s) {
    final link = _codeKind == 'phoneLink' || _tab == CloudAuthTab.upgrade;
    final phoneSignIn = _codeKind == 'phoneSignIn';
    return DriveTrackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_codeMessage,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            s.t(
              '验证码为 6 位数字。若超时或收不到，请返回后重新获取。',
              'The code is 6 digits. If it expires or does not arrive, go back and request another.',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.t('验证码', 'Verification code'),
              hintText: s.t('6 位数字', '6 digits'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submitCode,
            child: Text(_submitting
                ? s.t('验证中…', 'Verifying…')
                : link
                    ? s.t('验证并绑定', 'Verify and bind')
                    : phoneSignIn
                        ? s.t('验证并登录', 'Verify and sign in')
                        : s.t('验证并完成注册', 'Verify and finish sign-up')),
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
            child: Text(s.t('重新发送验证码', 'Request a new code')),
          ),
        ],
      ),
    );
  }
}
