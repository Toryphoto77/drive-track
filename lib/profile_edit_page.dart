import 'dart:io';

import 'package:flutter/material.dart';

import 'app_bar_style.dart';
import 'app_notice.dart';
import 'my_page.dart';

/// 个人资料编辑页（v1.5.1，全页跳转，取代卡片内展开编辑器与旧对话框）。
///
/// 样式参考用户给的资料页：头像居中在上、右下角相机钮；下方每行
/// 左标签、右内容（昵称 / 性别 / 生日 / 行业 / 个人签名 /
/// 座驾品牌 / 座驾型号 / 邮箱），右上角“保存”。本页只做校验与回传，
/// 不直接写本机、不直接写云端：点保存后由调用方持久化 + 云端同步。
class ProfileEditPage extends StatefulWidget {
  final String username;
  final String bio;
  final String email;
  final String gender;
  final String birthday;
  final String industry;
  final String vehicleBrand;
  final String vehicleModel;
  final String? avatarPath;

  /// 换头像回调（总协调传 Native.pickFile('image') 一类实现，
  /// 返回本机路径，取消返回 null）。
  final Future<String?> Function()? onPickAvatar;

  /// 保存回调：校验通过后回传结果，调用方持久化 + 同步后本页 pop。
  final ValueChanged<ProfileEditResult>? onSave;

  const ProfileEditPage({
    super.key,
    required this.username,
    required this.bio,
    this.email = '',
    this.gender = '',
    this.birthday = '',
    this.industry = '',
    this.vehicleBrand = '',
    this.vehicleModel = '',
    this.avatarPath,
    this.onPickAvatar,
    this.onSave,
  });

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.username);
  late final TextEditingController _bioCtrl =
      TextEditingController(text: widget.bio);
  late final TextEditingController _industryCtrl =
      TextEditingController(text: widget.industry);
  late final TextEditingController _brandCtrl =
      TextEditingController(text: widget.vehicleBrand);
  late final TextEditingController _modelCtrl =
      TextEditingController(text: widget.vehicleModel);
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.email);
  late String _gender = widget.gender;
  late String _birthday = widget.birthday;
  late String? _avatarPath = widget.avatarPath;
  bool _pickingAvatar = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _industryCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (widget.onPickAvatar == null) {
      if (mounted) showAppNotice(context, '换头像暂不可用。', AppNoticeKind.info);
      return;
    }
    if (_pickingAvatar) return;
    setState(() => _pickingAvatar = true);
    try {
      final path = await widget.onPickAvatar!();
      if (path != null && path.isNotEmpty && mounted) {
        setState(() => _avatarPath = path);
      }
    } catch (e) {
      if (mounted) {
        showAppNotice(context, '换头像失败：$e', AppNoticeKind.error);
      }
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _pickGender() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in const ['男', '女', '不填'])
              ListTile(
                title: Text(g,
                    style: TextStyle(
                        color: _gender == g ||
                                (g == '不填' && _gender.isEmpty)
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white)),
                trailing: (_gender == g || (g == '不填' && _gender.isEmpty))
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, g),
              ),
          ],
        ),
      ),
    );
    if (v != null && mounted) {
      setState(() => _gender = v == '不填' ? '' : v);
    }
  }

  Future<void> _pickBirthday() async {
    final initial = DateTime.tryParse(_birthday) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime.now(),
      helpText: '选择生日',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null && mounted) {
      setState(() => _birthday =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '昵称不能为空，请填写后再保存。');
      return;
    }
    if (name.length > 32) {
      setState(() => _error = '昵称最多 32 个字。');
      return;
    }
    if (_bioCtrl.text.trim().length > 200) {
      setState(() => _error = '个人签名最多 200 个字。');
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = '邮箱格式不对，请检查后再保存（可留空不填）。');
      return;
    }
    setState(() => _error = null);
    widget.onSave?.call(ProfileEditResult(
      username: name,
      bio: _bioCtrl.text.trim(),
      avatarPath: _avatarPath,
      email: email,
      gender: _gender,
      birthday: _birthday,
      industry: _industryCtrl.text.trim(),
      vehicleBrand: _brandCtrl.text.trim(),
      vehicleModel: _modelCtrl.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        title: const Text('编辑资料'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('保存',
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: withAppBarTopInset(
            context, const EdgeInsets.fromLTRB(16, 24, 16, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头像居中在上，右下角相机钮（点按换头像）。
            Center(
              child: GestureDetector(
                onTap: _pickingAvatar ? null : _pickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2),
                      ),
                      child: ClipOval(
                        child: _avatarPath != null &&
                                _avatarPath!.isNotEmpty &&
                                File(_avatarPath!).existsSync()
                            ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                            : Container(
                                color: Colors.black54,
                                child: Icon(Icons.person,
                                    size: 56, color: accent),
                              ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF121212), width: 2),
                        ),
                        child: Icon(
                          _pickingAvatar
                              ? Icons.hourglass_empty
                              : Icons.camera_alt,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _row(
              label: '昵称',
              child: TextField(
                controller: _nameCtrl,
                maxLength: 32,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: '请输入昵称',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            _row(
              label: '性别',
              child: InkWell(
                onTap: _pickGender,
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _gender.isEmpty ? '未填' : _gender,
                      style: TextStyle(
                          color: _gender.isEmpty ? Colors.white38 : Colors.white,
                          fontSize: 15),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: Colors.white38),
                ]),
              ),
            ),
            _row(
              label: '生日',
              child: InkWell(
                onTap: _pickBirthday,
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _birthday.isEmpty ? '未填' : _birthday,
                      style: TextStyle(
                          color:
                              _birthday.isEmpty ? Colors.white38 : Colors.white,
                          fontSize: 15),
                    ),
                  ),
                  if (_birthday.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _birthday = ''),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text('清除',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 13)),
                      ),
                    ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: Colors.white38),
                ]),
              ),
            ),
            _row(
              label: '行业',
              child: TextField(
                controller: _industryCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '如：影视、电视、广播制作',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            _row(
              label: '个人签名',
              child: TextField(
                controller: _bioCtrl,
                minLines: 1,
                maxLines: 3,
                maxLength: 200,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: '介绍一下自己',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            _row(
              label: '座驾品牌',
              child: TextField(
                controller: _brandCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '如：宝马',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            _row(
              label: '座驾型号',
              child: TextField(
                controller: _modelCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '如：M4',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            _row(
              label: '邮箱',
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '仅存本机，用作反馈联系方式',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '昵称、简介与头像保存后会同步到云端公开资料，他人打开你的公开资料页可见；邮箱仅存本机，不会发到服务器。',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  /// 资料行：左标签（96 宽）+ 右内容，底部分隔细线。
  Widget _row({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
