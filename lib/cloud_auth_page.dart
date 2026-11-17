import 'package:flutter/material.dart';

import 'app_locale.dart';
import 'app_notice.dart';
import 'cloud_phone.dart';
import 'cloud_service.dart';

/// 云端账号页的入口：手机号 / 邮箱登录、注册、匿名账号绑定升级。
enum CloudAuthMode { login, register, link }

/// 极简登录 / 注册门。没有非匿名会话时作为启动后的第一屏。
///
/// v1.7.0 改版：参考主流账号页的极简结构，一屏一个任务。
/// - 首屏只有品牌标识、渐变能力词条、一句理念标题、两个按钮和协议勾选；
/// - 点「手机号登录」进手机号视图，点「邮箱登录」进邮箱视图；
/// - 手机号发码后进 6 位验证码视图，验证完成即登录或注册。
/// 手机号只有一个入口：先按登录发码，号码未注册时自动改走注册发码，
/// 用户不需要先判断自己有没有账号。
///
/// 未配置云端环境 ID（构建时未注入 CLOUDBASE_ENV_ID）时仍可浏览界面，
/// 但点按钮会给出明确提示，不再把按钮静默置灰。
class CloudAuthPage extends StatefulWidget {
  final CloudAuthMode? mode;
  final bool gate;

  const CloudAuthPage({super.key, this.mode, this.gate = false});

  @override
  State<CloudAuthPage> createState() => _CloudAuthPageState();
}

enum _AuthView { landing, phone, code, email }

/// 页面底色与按钮配色（与深色主题一致，不抢主题色）。
const Color _kBg = Color(0xFF0B0B0C);
const Color _kPrimaryBtn = Color(0xFFF1EEE7);
const Color _kFieldBg = Color(0xFF171719);
const Color _kFieldBorder = Color(0xFF2A2A2D);

class _CloudAuthPageState extends State<CloudAuthPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();

  late _AuthView _view;

  /// auto = 先登录后自动注册；signUp = 直接注册发码；link = 绑定匿名账号。
  late String _intent;
  String _dial = kDefaultPhoneDialCode;
  bool _emailRegister = false;
  bool _agree = false;
  bool _needsCaptcha = false;
  bool _submitting = false;
  String? _error;
  String _codeMessage = '';
  String _codeKind = 'phoneSignIn';
  String _sentPhone = '';

  @override
  void initState() {
    super.initState();
    final upgrade = CloudService.instance.hasAnonymousSession;
    switch (widget.mode) {
      case CloudAuthMode.register:
        _view = _AuthView.phone;
        _intent = 'signUp';
      case CloudAuthMode.login:
        _view = _AuthView.phone;
        _intent = 'auto';
      case CloudAuthMode.link:
        _view = _AuthView.phone;
        _intent = 'link';
      case null:
        _view = upgrade ? _AuthView.phone : _AuthView.landing;
        _intent = upgrade ? 'link' : 'auto';
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  /// 云端未配置时按钮仍可点，点了给一句明确提示。
  bool _checkConfigured() {
    if (CloudService.instance.isConfigured) return true;
    final s = S.of(context);
    showAppNotice(
      context,
      s.t(
        '当前安装包未注入云端环境 ID，无法登录。请使用带云端配置的安装包。',
        'This build has no cloud environment ID, so sign-in is unavailable.',
      ),
      AppNoticeKind.error,
      const Duration(milliseconds: 3600),
    );
    return false;
  }

  bool _checkAgree() {
    if (_agree) return true;
    final s = S.of(context);
    showAppNotice(
      context,
      s.t('请先阅读并同意用户协议和隐私政策', 'Please accept the terms and privacy policy first'),
      AppNoticeKind.warning,
    );
    return false;
  }

  void _startPhone(String intent) {
    if (!_checkAgree()) return;
    if (!_checkConfigured()) return;
    setState(() {
      _view = _AuthView.phone;
      _intent = intent;
      _error = null;
      _needsCaptcha = false;
      _codeCtrl.clear();
    });
  }

  void _startEmail({bool link = false, bool register = false}) {
    if (!_checkAgree()) return;
    if (!_checkConfigured()) return;
    setState(() {
      _view = _AuthView.email;
      _intent = link ? 'link' : 'auto';
      _emailRegister = register;
      _error = null;
      _needsCaptcha = false;
    });
  }

  void _onBack() {
    if (_view == _AuthView.code) {
      setState(() {
        _view = _AuthView.phone;
        _error = null;
        _codeCtrl.clear();
      });
      return;
    }
    if (_view != _AuthView.landing) {
      setState(() {
        _view = _AuthView.landing;
        _error = null;
      });
      return;
    }
    if (!widget.gate && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  bool _looksUnregistered(CloudAuthResult result) {
    final m = result.message.toLowerCase();
    return m.contains('还没注册') ||
        m.contains('未注册') ||
        m.contains('not registered') ||
        m.contains('not exist');
  }

  String _maskPhone(String phone) {
    final m = RegExp(r'^(\+\d{1,4}) (\d+)$').firstMatch(phone.trim());
    if (m == null) return phone;
    final digits = m.group(2)!;
    if (digits.length < 7) return phone;
    return '${m.group(1)} ${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
  }

  String _dialLabel(S s) {
    final zh = s.zh;
    for (final country in kPhoneCountryCodes) {
      if (country.dial == _dial) return country.label(zh);
    }
    return _dial;
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
        _view = _AuthView.code;
        _codeMessage = result.message;
        _error = null;
        _needsCaptcha = false;
        _codeCtrl.clear();
      });
      return;
    }
    showAppNotice(context, result.message, AppNoticeKind.success);
    if (!widget.gate && Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _sendPhoneCode() async {
    final s = S.of(context);
    if (!_checkAgree() || !_checkConfigured()) return;
    final phone = formatCloudPhoneNumber(_dial, _phoneCtrl.text);
    if (!isValidCloudPhoneNumber(phone)) {
      setState(() => _error = s.t(
            '请输入有效手机号，号码按国际格式提交。',
            'Enter a valid phone number in international format.',
          ));
      return;
    }
    final captcha = _captchaCtrl.text.trim();
    final captchaToken = captcha.isEmpty ? null : captcha;
    setState(() {
      _error = null;
      _submitting = true;
    });
    final svc = CloudService.instance;
    CloudAuthResult result;
    if (_intent == 'link') {
      _codeKind = 'phoneLink';
      result = await svc.linkPhone(phone);
    } else if (_intent == 'signUp') {
      _codeKind = 'phoneSignUp';
      result = await svc.requestPhoneSignUpCode(phone, captchaToken: captchaToken);
    } else {
      _codeKind = 'phoneSignIn';
      result = await svc.requestPhoneSignInCode(phone, captchaToken: captchaToken);
      // 单入口：未注册的号码自动改走注册发码，用户不用先选登录还是注册。
      if (!result.ok && _looksUnregistered(result)) {
        _codeKind = 'phoneSignUp';
        result = await svc.requestPhoneSignUpCode(phone, captchaToken: captchaToken);
      }
    }
    if (!mounted) return;
    _sentPhone = phone;
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
    switch (_codeKind) {
      case 'phoneLink':
        result = await svc.verifyLinkPhoneCode(code);
      case 'phoneSignUp':
        result = await svc.verifyPhoneSignUpCode(code);
      case 'phoneSignIn':
        result = await svc.verifyPhoneSignInCode(code);
      case 'emailLink':
        result = await svc.verifyLinkCode(code);
      default:
        result = await svc.verifySignUpCode(code);
    }
    await _finish(result);
  }

  Future<void> _submitEmail() async {
    final s = S.of(context);
    if (!_checkAgree() || !_checkConfigured()) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final link = _intent == 'link';
    if (!isValidCloudEmail(email)) {
      setState(() => _error = s.t('邮箱格式不对', 'Email format is invalid'));
      return;
    }
    if (!link) {
      if (!isValidCloudPassword(password)) {
        setState(() =>
            _error = s.t('密码至少 6 位', 'Password must be at least 6 characters'));
        return;
      }
      if (_emailRegister && _confirmCtrl.text != password) {
        setState(() =>
            _error = s.t('两次输入的密码不一致', 'The two passwords do not match'));
        return;
      }
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final svc = CloudService.instance;
    final CloudAuthResult result;
    if (link) {
      _codeKind = 'emailLink';
      result = await svc.linkEmail(email);
    } else if (_emailRegister) {
      _codeKind = 'emailSignUp';
      result = await svc.signUpWithEmail(email, password);
    } else {
      result = await svc.signInWithEmail(email, password);
    }
    if (!mounted) return;
    _sentPhone = '';
    await _finish(result);
  }

  Future<void> _pickDial() async {
    final s = S.of(context);
    final zh = s.zh;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                s.t('选择国家或地区', 'Select country or region'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final country in kPhoneCountryCodes)
              ListTile(
                title: Text(
                  country.label(zh),
                  style: const TextStyle(color: Colors.white, fontSize: 14.5),
                ),
                trailing: country.dial == _dial
                    ? const Icon(Icons.check, size: 18, color: Colors.white70)
                    : null,
                onTap: () => Navigator.pop(ctx, country.dial),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _dial = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final upgrade = CloudService.instance.hasAnonymousSession;
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned(
            top: -170,
            right: -120,
            child: IgnorePointer(
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.18),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(s),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      child: KeyedSubtree(
                        key: ValueKey('${_view.name}-$_emailRegister'),
                        child: _body(s, upgrade),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(S s, bool upgrade) => switch (_view) {
        _AuthView.landing => _landing(s, upgrade),
        _AuthView.phone => _phoneView(s),
        _AuthView.code => _codeView(s),
        _AuthView.email => _emailView(s),
      };

  Widget _topBar(S s) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 4),
          if (!widget.gate || _view != _AuthView.landing)
            IconButton(
              onPressed: _onBack,
              icon: const Icon(Icons.arrow_back_ios_new, size: 17),
              color: Colors.white70,
              tooltip: s.t('返回', 'Back'),
            )
          else
            const SizedBox(width: 48),
          const Spacer(),
          if (widget.gate && _view == _AuthView.landing) _langSwitch(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _langSwitch() {
    final lang = LocaleScope.of(context).lang;
    Widget item(String label, AppLang value) {
      final selected = lang == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => LocaleController.instance.setLang(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: Colors.white.withValues(alpha: selected ? 0.9 : 0.32),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item('中文', AppLang.zh),
        Text(' / ', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.18))),
        item('EN', AppLang.en),
      ],
    );
  }

  Widget _brandHeader(S s) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/app_icon_steering.png',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          s.t('驰迹 DriveTrack', 'DRIVETRACK'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  /// 渐变能力词条：越靠中间越亮，中间带一行主题色图标高亮。
  Widget _wordRibbon(S s) {
    final accent = Theme.of(context).colorScheme.primary;
    final rows = <(String, double, IconData?)>[
      (s.t('圈速计时', 'Lap timing'), 0.06, null),
      (s.t('走线复盘', 'Racing line'), 0.10, null),
      (s.t('弯角分析', 'Corner analysis'), 0.16, null),
      (s.t('G 值遥测', 'G-force telemetry'), 0.82, Icons.speed),
      (s.t('OBD 数据', 'OBD data'), 0.14, null),
      (s.t('赛后报告', 'Session report'), 0.07, null),
    ];
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00FFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x33FFFFFF),
        ],
        stops: [0, 0.24, 0.74, 1],
      ).createShader(rect),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  if (row.$3 != null) ...[
                    Icon(row.$3, size: 20, color: accent.withValues(alpha: 0.9)),
                    const SizedBox(width: 9),
                  ],
                  Flexible(
                    child: Text(
                      row.$1,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.44,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: row.$2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _landing(S s, bool upgrade) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandHeader(s),
        const SizedBox(height: 24),
        _wordRibbon(s),
        const SizedBox(height: 14),
        Text(
          s.t('每一圈，\n都算数。', 'Every lap\ncounts.'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            height: 1.32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          s.t(
            '记录走线、圈速与 G 值，赛后逐弯复盘。',
            'Your line, your laps, your G-forces — reviewed corner by corner.',
          ),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        _primaryButton(
          icon: Icons.phone_iphone,
          label: upgrade ? s.t('绑定手机号', 'Bind phone') : s.t('手机号登录', 'Phone sign-in'),
          onTap: () => _startPhone(upgrade ? 'link' : 'auto'),
        ),
        const SizedBox(height: 10),
        _ghostButton(
          icon: Icons.alternate_email,
          label: upgrade ? s.t('绑定邮箱', 'Bind email') : s.t('邮箱登录', 'Email sign-in'),
          onTap: () => _startEmail(link: upgrade),
        ),
        const SizedBox(height: 14),
        Text(
          upgrade
              ? s.t(
                  '本机有未升级的匿名账号，绑定后云端行程保留。',
                  'This device has an anonymous account. Binding keeps its cloud trips.',
                )
              : s.t(
                  '验证码验证后自动登录，未注册的号码会直接创建账号。',
                  'A code signs you in; unregistered numbers get an account.',
                ),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
        if (!CloudService.instance.isConfigured) ...[
          const SizedBox(height: 14),
          _warnBanner(s),
        ],
        const SizedBox(height: 18),
        _agreeRow(s),
        const SizedBox(height: 6),
        Text(
          s.t('本机已有行程不会被删除。', 'Trips already on this device are not deleted.'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.22),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _phoneView(S s) {
    final link = _intent == 'link';
    final signUp = _intent == 'signUp';
    final title = link
        ? s.t('绑定手机号', 'Bind phone')
        : signUp
            ? s.t('手机号注册', 'Phone sign-up')
            : s.t('手机号登录', 'Phone sign-in');
    final subtitle = link
        ? s.t(
            '绑定后仍是同一个账号，云端行程保留。',
            'The account stays the same and keeps its cloud trips.',
          )
        : signUp
            ? s.t(
                '输入未注册的号码，验证后创建账号。',
                'Use a new number; verification creates the account.',
              )
            : s.t(
                '未注册的号码验证后会自动创建账号。',
                'Unregistered numbers get an account after verification.',
              );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            )),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
              height: 1.45,
            )),
        const SizedBox(height: 26),
        _phoneField(s),
        if (_needsCaptcha) ...[
          const SizedBox(height: 16),
          _labeledField(
            label: s.t('图形验证码令牌', 'Captcha token'),
            controller: _captchaCtrl,
          ),
        ],
        if (_error != null) _errorText(_error!),
        const SizedBox(height: 24),
        _primaryButton(
          label: _submitting
              ? s.t('发送中…', 'Sending…')
              : s.t('获取验证码', 'Send code'),
          loading: _submitting,
          onTap: _submitting ? null : _sendPhoneCode,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () => _startEmail(link: link, register: signUp),
            child: Text(
              link
                  ? s.t('改用邮箱绑定', 'Bind an email instead')
                  : signUp
                      ? s.t('改用邮箱注册', 'Sign up with email')
                      : s.t('改用邮箱登录', 'Sign in with email'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _agreeRow(s),
      ],
    );
  }

  Widget _phoneField(S s) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _kFieldBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kFieldBorder),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            onTap: _submitting ? null : _pickDial,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dialLabel(s),
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down,
                      size: 18, color: Colors.white.withValues(alpha: 0.38)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 22, color: Colors.white.withValues(alpha: 0.1)),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              enabled: !_submitting,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: s.t('手机号', 'Phone number'),
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeView(S s) {
    final link = _codeKind == 'phoneLink' || _codeKind == 'emailLink';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.t('输入验证码', 'Enter the code'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _codeMessage.isEmpty ? s.t('验证码已发送。', 'The code has been sent.') : _codeMessage,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
        if (_sentPhone.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            s.t('发送至 ${_maskPhone(_sentPhone)}',
                'Sent to ${_maskPhone(_sentPhone)}'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11.5,
            ),
          ),
        ],
        const SizedBox(height: 26),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          enabled: !_submitting,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 10,
          ),
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: _kFieldBg,
            hintText: '••••••',
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.18),
              letterSpacing: 10,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _kFieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _kFieldBorder),
            ),
          ),
        ),
        if (_error != null) _errorText(_error!),
        const SizedBox(height: 24),
        _primaryButton(
          label: _submitting
              ? s.t('验证中…', 'Verifying…')
              : link
                  ? s.t('验证并绑定', 'Verify and bind')
                  : s.t('验证并继续', 'Verify and continue'),
          loading: _submitting,
          onTap: _submitting ? null : _submitCode,
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _submitting ? null : _onBack,
            child: Text(
              s.t('重新获取验证码', 'Request a new code'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emailView(S s) {
    final link = _intent == 'link';
    final title = link
        ? s.t('绑定邮箱', 'Bind email')
        : _emailRegister
            ? s.t('注册邮箱账号', 'Email sign-up')
            : s.t('邮箱登录', 'Email sign-in');
    final subtitle = link
        ? s.t(
            '邮箱绑定分两步：先收取验证码，再输入 6 位验证码完成。',
            'Two steps: request a code, then enter the 6 digits.',
          )
        : _emailRegister
            ? s.t(
                '填写邮箱和密码，验证码验证后创建账号。',
                'Enter an email and password, then confirm with a code.',
              )
            : s.t('使用邮箱和密码登录。', 'Sign in with email and password.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            )),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 12.5,
              height: 1.45,
            )),
        const SizedBox(height: 26),
        _labeledField(
          label: s.t('邮箱', 'Email'),
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          hint: 'name@example.com',
        ),
        if (!link) ...[
          const SizedBox(height: 16),
          _labeledField(
            label: s.t('密码', 'Password'),
            controller: _passwordCtrl,
            obscure: true,
          ),
        ],
        if (!link && _emailRegister) ...[
          const SizedBox(height: 16),
          _labeledField(
            label: s.t('确认密码', 'Confirm password'),
            controller: _confirmCtrl,
            obscure: true,
          ),
        ],
        if (_error != null) _errorText(_error!),
        const SizedBox(height: 24),
        _primaryButton(
          label: _submitting
              ? s.t('提交中…', 'Submitting…')
              : link
                  ? s.t('发送验证码', 'Send code')
                  : _emailRegister
                      ? s.t('注册', 'Sign up')
                      : s.t('登录', 'Sign in'),
          loading: _submitting,
          onTap: _submitting ? null : _submitEmail,
        ),
        if (!link) ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _emailRegister = !_emailRegister;
                        _error = null;
                      }),
              child: Text(
                _emailRegister
                    ? s.t('已有账号？直接登录', 'Already have an account? Sign in')
                    : s.t('没有账号？注册邮箱账号', 'No account? Sign up with email'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _agreeRow(s),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    final enabled = onTap != null;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: enabled
            ? _kPrimaryBtn
            : _kPrimaryBtn.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (icon != null)
                Positioned(
                  left: 24,
                  child: Icon(icon, size: 20, color: Colors.black87),
                ),
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black87,
                  ),
                )
              else
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ghostButton({
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (icon != null)
                  Positioned(
                    left: 24,
                    child: Icon(icon,
                        size: 20, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    bool obscure = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 11.5,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          enabled: !_submitting,
          autocorrect: false,
          style: const TextStyle(color: Colors.white, fontSize: 15.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _kFieldBg,
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.22)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kFieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kFieldBorder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorText(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, size: 15, color: Colors.redAccent),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warnBanner(S s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 15, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.t(
                '当前安装包未注入云端环境 ID，登录不可用。',
                'This build has no cloud environment ID, so sign-in is unavailable.',
              ),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _agreeRow(S s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _agree = !_agree),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _agree ? _kPrimaryBtn : Colors.transparent,
              border: Border.all(
                color: _agree
                    ? _kPrimaryBtn
                    : Colors.white.withValues(alpha: 0.28),
              ),
            ),
            child: _agree
                ? const Icon(Icons.check, size: 12, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              s.t(
                '我已阅读并同意《用户协议》和《隐私政策》',
                'I accept the Terms of Service and Privacy Policy',
              ),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
