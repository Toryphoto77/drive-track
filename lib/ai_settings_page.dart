import 'package:flutter/material.dart';

import 'ai_analysis_service.dart';
import 'app_bar_style.dart';
import 'app_locale.dart';
import 'app_notice.dart';
import 'card_style.dart';
import 'glass_button.dart';

/// AI 分析设置页（v1.7.0）：OpenAI 兼容接口配置。
///
/// 风格与语音设置页一致（同一套 DtAppBar + 深色卡片 + 分组标题）。
/// Key 只写本机文件，页面明确说明请求何时发起、哪些数据会外发。
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _enabled = false;
  bool _showKey = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AiSettingsStore.load().then((settings) {
      if (!mounted) return;
      setState(() {
        _enabled = settings.enabled;
        _baseCtrl.text = settings.baseUrl;
        _keyCtrl.text = settings.apiKey;
        _modelCtrl.text = settings.model;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    final base = _baseCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (_enabled) {
      final uri = Uri.tryParse(base);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        showAppNotice(
          context,
          s.t('Base URL 需为 http(s):// 地址', 'Base URL must be http(s)'),
          AppNoticeKind.error,
        );
        return;
      }
      if (key.isEmpty) {
        showAppNotice(
          context,
          s.t('API Key 不能为空', 'API Key is required'),
          AppNoticeKind.error,
        );
        return;
      }
      if (model.isEmpty) {
        showAppNotice(
          context,
          s.t('模型名不能为空', 'Model is required'),
          AppNoticeKind.error,
        );
        return;
      }
    }
    setState(() => _saving = true);
    final ok = await AiSettingsStore.save(
      AiSettings(
        enabled: _enabled,
        baseUrl: base.isEmpty ? AiSettings.defaultBaseUrl : base,
        apiKey: key,
        model: model.isEmpty ? AiSettings.defaultModel : model,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    showAppNotice(
      context,
      ok ? s.t('已保存', 'Saved') : s.t('保存失败：本机文件写入失败', 'Save failed'),
      ok ? AppNoticeKind.success : AppNoticeKind.error,
    );
    if (ok) Navigator.of(context).maybePop();
  }

  Future<void> _clear() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(s.t('清除 AI 配置', 'Clear AI settings')),
        content: Text(
          s.t(
            '会删除本机保存的 API Key，之后需重新填写。',
            'The locally stored API key will be deleted.',
          ),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              s.t('清除', 'Clear'),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiSettingsStore.save(AiSettings.defaults);
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _baseCtrl.text = AiSettings.defaultBaseUrl;
      _keyCtrl.clear();
      _modelCtrl.text = AiSettings.defaultModel;
    });
    showAppNotice(context, s.t('已清除', 'Cleared'), AppNoticeKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = CardStyle.accent(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DtAppBar(
        leading: GlassButton.back(onPressed: () => Navigator.maybePop(context)),
        title: Text(s.t('AI 分析', 'AI analysis')),
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
                    Icon(Icons.auto_awesome, size: 20, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.t('启用 AI 赛道分析', 'Enable AI race analysis'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Switch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.t(
                    'OpenAI 兼容接口（chat/completions）。只有你在赛道分析页点“生成分析”时才发起请求，不会后台自动上传。',
                    'OpenAI-compatible chat/completions. Requests are sent only when you tap “Generate analysis”.',
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('接口配置', 'API configuration'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.t('Base URL', 'Base URL'),
                    hintText: AiSettings.defaultBaseUrl,
                    helperText: s.t(
                      '填到 /v1 即可，会自动补 /chat/completions',
                      'End at /v1; /chat/completions is appended',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  obscureText: !_showKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: s.t('API Key', 'API Key'),
                    hintText: 'sk-…',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelCtrl,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: s.t('模型名', 'Model'),
                    hintText: AiSettings.defaultModel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DriveTrackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('数据与隐私', 'Data & privacy'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.t(
                    '发送内容仅限本次选择的赛道实测摘要（圈速、分段、速度/G 极值、弯角、速度差），不含账号、位置轨迹与个人资料。未接入的通道会标注为无数据，AI 不补造数值。',
                    'Only the selected session summary (lap times, sectors, speed/G extremes, corners, speed delta) is sent. No account, route trace or profile data. Missing channels are marked unavailable.',
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.t(
                    'API Key 只保存在本机应用私有目录，不上传服务器、不写日志。',
                    'The API key is stored only in the app private folder.',
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? s.t('保存中…', 'Saving…') : s.t('保存', 'Save')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : _clear,
            child: Text(
              s.t('清除本机 AI 配置', 'Clear local AI settings'),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }
}
