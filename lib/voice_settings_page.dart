import 'package:flutter/material.dart';
import 'app_notice.dart';
import 'glass_button.dart';
import 'import_style.dart';
import 'native.dart';
import 'voice_service.dart';

/// v0.1.9 语音设置子页：默认仍用系统原生 TTS（本地、无需联网、
/// 无需密钥、无费用，适合驾驶播报）；国内 API 语音只作可选的
/// 自定义服务，不内置 Key、不预填示例 Key、不作默认。
///
/// v1.0.2 “没有语音引擎”根因（查原生 MainActivity.kt 的 whenTtsReady
/// 与 voice_service.dart 的 ensureAvailable 后确认，不是文案问题）：
/// - 原生 TextToSpeech 初始化是异步的：v1.2.1 起按 zh_CN → zh →
///   zh_TW → 系统默认顺序试语言，返回 LANG_AVAILABLE /
///   LANG_COUNTRY_AVAILABLE 才算该语言可用；全部不可用时才判
///   ttsLanguage='none'、ttsReady=false，Dart 侧收到
///   available=false + error='tts_unavailable'。最终语言代码原样
///   回给 Dart（如 zh_CN），中文可用当且仅当代码以 zh 开头。
/// - v1.2.1 另修三处：① 播报静音只看媒体音量，振动/静音模式照常
///   播报，旧的“仅在非静音模式播报”文案已删；② 首选引擎持久化进
///   voice_settings.json，重启恢复，卸载后回退系统默认并明示；
///   ③ 试听等原生 done/error 回调（约 8 秒超时），不再入队即报成功。
///   状态在下方引擎卡里一次给全，系统 TTS 设置与重新探测按钮保留
///   在引擎卡里。
/// - 所以“无引擎”在页面上其实是三种不同情况，旧页只写一句话分不清：
///   ① 系统根本没装 TTS 引擎（无 Google TTS 的国产机 / 精简系统常见，
///     TextToSpeech 构造失败或 init 回调非 SUCCESS）；
///   ② 装了引擎、但中文语音数据没下载（按 zh_CN → zh → zh_TW
///     顺序 setLanguage 均返回 LANG_MISSING_DATA /
///     LANG_NOT_SUPPORTED），此时若默认语言可用会回退默认语言播报、
///     只是不是中文；
///   ③ 引擎列表非空、但所选引擎的中文与默认语言都不可用。
/// - 旧页的另一个缺口：打开时只调 loadEngines() 查引擎列表，
///   不调 ensureAvailable() 探测可用性与语言，ttsAvailable /
///   ttsLanguage 在点“试听”前一直是 null，页面只能写“状态待探测”。
///   本版打开时即 loadEngines + ensureAvailable，状态、当前引擎、
///   中文数据状态三行一次给全；“试听”仍走 speakTest，成功/失败
///   都把原因留在按钮下方，v1.2.1 起试听等原生 done/error 回调才算
///   结果，媒体音量为 0 时仍跑试听但成功结果里明说听不到。
/// - 跳系统设置：新增原生通道 openTtsSettings，走
///   Settings.ACTION_TEXT_TO_SPEECH_SETTINGS（系统“文字转语音输出”页，
///   可选首选引擎、下载中文语音数据）；刻意不用
///   TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA（无处理 Activity 的
///   设备上直接 startActivity 会崩），原生侧另有 try/catch 兜底，
///   无此设置页的 OEM 机型返回 false，页面改显示文字路径引导。
/// - 语速/音调/音量沿用现有语音设置；自定义语音的协议、存储
///   （voice_settings.json）、白名单逻辑一律未动，只换了 UI。

class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key});
  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
  VoiceSettings _s = VoiceSettings.defaults;
  bool _loaded = false;
  String? _testResult;
  bool _testOk = false;
  String? _customTestResult;
  bool _testing = false;
  bool _customTesting = false;
  bool _refreshing = false;
  bool _ttsSettingsBusy = false;
  late final TextEditingController _endpointCtrl = TextEditingController();
  late final TextEditingController _keyCtrl = TextEditingController();
  String _provider = 'generic';
  String _mimoVoice = '冰糖';

  @override
  void initState() {
    super.initState();
    VoiceService.instance.load().then((_) async {
      // 打开即探测：引擎列表 + 可用性/语言 + 音量/响铃模式一次给全，
      // 不等用户点试听。load() 已先恢复已保存的首选引擎并传给原生。
      await VoiceService.instance.loadEngines();
      await VoiceService.instance.ensureAvailable();
      await VoiceService.instance.refreshAudioStatus();
      if (!mounted) return;
      final c = VoiceService.instance.customVoice;
      _endpointCtrl.text = c.endpoint;
      _keyCtrl.text = c.apiKey;
      _provider = c.provider;
      _mimoVoice = c.mimoVoice;
      setState(() {
        _s = VoiceService.instance.settings;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply(VoiceSettings next) async {
    setState(() => _s = next);
    await VoiceService.instance.updateSettings(next);
  }

  Future<void> _refreshTts() async {
    setState(() => _refreshing = true);
    await VoiceService.instance.loadEngines();
    await VoiceService.instance.ensureAvailable();
    await VoiceService.instance.refreshAudioStatus();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openTtsSettings() async {
    setState(() => _ttsSettingsBusy = true);
    final ok = await Native.openTtsSettings();
    if (mounted) {
      setState(() => _ttsSettingsBusy = false);
      if (!ok) {
        showAppNotice(context, '该设备没有系统 TTS 设置页，请手动打开：系统设置 > 系统 > '
              '语言与输入法 > 文字转语音输出，在里面选首选引擎并下载中文语音数据。', AppNoticeKind.warning);
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final r = await VoiceService.instance.speakTest();
    if (mounted) setState(() {
      _testing = false;
      _testOk = r.$1;
      _testResult = r.$2;
    });
  }

  Future<void> _saveCustom() async {
    final next = CustomVoiceConfig(
      enabled: VoiceService.instance.customVoice.enabled,
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _keyCtrl.text,
      provider: _provider,
      mimoVoice: _mimoVoice,
    );
    await VoiceService.instance.updateCustomVoice(next);
    if (mounted) {
      setState(() {});
      showAppNotice(context, '自定义语音服务配置已保存到本机。', AppNoticeKind.success);
    }
  }

  Future<void> _testCustom() async {
    await _saveCustom();
    setState(() {
      _customTesting = true;
      _customTestResult = null;
    });
    final r = await VoiceService.instance.testCustomVoice();
    if (mounted) setState(() {
      _customTesting = false;
      _customTestResult = r.$2;
    });
  }

  /// 状态标题：中文数据状态与引擎可用性分开说，不混成一句。
  /// v1.2.1：最终语言是原样代码（zh_CN/zh/zh_TW/系统默认代码），
  /// 中文当且仅当代码以 zh 开头；'zh'/'default' 是旧值，不再产生。
  String _ttsStatusTitle() {
    final svc = VoiceService.instance;
    if (svc.ttsAvailable == null || svc.ttsLanguage == null) {
      return '语音引擎状态待探测';
    }
    if (svc.ttsLanguage == 'none') {
      return svc.ttsEngineList.isEmpty ? '无可用语音引擎' : '有引擎，但无可用语言';
    }
    if (svc.ttsChineseAvailable) return '语音可用 · 中文语音已安装';
    return '语音可用，但中文语音未安装';
  }


  /// 无引擎时的明确原因：引擎列表空 / 非空、原生错误码分开写。
  String _ttsCauseDetail() {
    final svc = VoiceService.instance;
    if (svc.ttsEngineList.isEmpty) {
      return '系统未装 TTS 引擎。先在系统 TTS 设置里安装 / 启用一个引擎（如 Google 文字转语音），再下载中文语音数据。';
    }
    return '已装引擎 ${svc.ttsEngineList.length} 个，但中文与默认语言都不可用。在系统 TTS 设置里换一个首选引擎，或为当前引擎下载中文语音数据，再回本页点“重新探测”。';
  }

  @override
  Widget build(BuildContext context) {
    final svc = VoiceService.instance;
    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('语音设置'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: svc,
              builder: (_, __) => ListView(children: [
                    SwitchListTile(
                      title: const Text('语音播报总开关'),
                      subtitle: const Text('关掉后所有语音播报都不出声'),
                      value: _s.enabled,
                      onChanged: (v) => _apply(_s.copyWith(enabled: v)),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(voiceMuteRuleNote, style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(children: [
                        SwitchListTile(title: const Text('事件播报'), subtitle: const Text('急加速、急刹车、过弯完成、压弯超阈值'), value: _s.announceEvents, onChanged: (v) => _apply(_s.copyWith(announceEvents: v))),
                        SwitchListTile(title: const Text('圈速播报'), subtitle: const Text('每圈完成与最快圈'), value: _s.announceLaps, onChanged: (v) => _apply(_s.copyWith(announceLaps: v))),
                        SwitchListTile(title: const Text('结束总结播报'), subtitle: const Text('里程、时长、评分、最快圈'), value: _s.announceSummary, onChanged: (v) => _apply(_s.copyWith(announceSummary: v))),
                        SwitchListTile(title: const Text('开始语音'), subtitle: const Text('开始记录时播报安全注意事项，倒数时报数（3、2、1、开始）'), value: _s.announceStart, onChanged: (v) => _apply(_s.copyWith(announceStart: v))),
                      ]),
                    ),
                    _slider('语速', _s.rate, 0.5, 2.0, (v) => _apply(_s.copyWith(rate: v))),
                    _slider('音调', _s.pitch, 0.5, 2.0, (v) => _apply(_s.copyWith(pitch: v))),
                    _slider('音量', _s.volume, 0.0, 1.0, (v) => _apply(_s.copyWith(volume: v))),
                    // 原生 TTS 引擎状态：当前引擎 + 中文数据状态 + 原因 + 下一步。
                    ImportCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('系统 TTS 引擎',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(_ttsStatusTitle(),
                            style: TextStyle(
                              color: svc.ttsChineseAvailable
                                  ? Colors.greenAccent
                                  : svc.ttsLanguage == 'none'
                                      ? Colors.redAccent
                                      : svc.ttsLanguage != null
                                          ? Colors.orange
                                          : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 4),
                        Text(
                          svc.ttsChineseAvailable
                              ? '当前引擎支持中文，播报走中文语音。'
                              : svc.ttsLanguage == 'none'
                                  ? _ttsCauseDetail()
                                  : svc.ttsLanguage != null
                                      ? '中文语音数据未安装，已回退默认语言播报，不一定是中文。按下面步骤装中文数据。'
                                      : '正在探测系统 TTS 引擎与中文语音数据，点“重新探测”可再查一次。',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ImportInnerCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '当前引擎：${svc.ttsEngineCurrent ?? '系统默认'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已保存的首选引擎：${svc.preferredTtsEngine ?? '系统默认'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已装引擎：${svc.ttsEngineList.isEmpty ? '暂无' : '${svc.ttsEngineList.length} 个'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '中文语音数据：${svc.ttsChineseAvailable ? '已安装' : svc.ttsLanguage == 'none' ? '不可用' : svc.ttsLanguage != null ? '未安装（已回退默认语言）' : '待探测'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            if (svc.preferredEngineMissing) ...[
                              const SizedBox(height: 4),
                              const Text('该引擎已卸载，已回退系统默认',
                                  style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ]),
                        ),
                        const SizedBox(height: 12),
                        if (svc.ttsEngineList.isEmpty)
                          const Text('暂无引擎列表：请先点“重新探测”，或检查系统是否安装 TTS 引擎。',
                              style: TextStyle(color: Colors.white54, fontSize: 12))
                        else
                          DropdownButton<String>(
                            value: svc.ttsEngineList.contains(svc.ttsEngineCurrent)
                                ? svc.ttsEngineCurrent
                                : null,
                            hint: const Text('选择系统已装引擎'),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2A2A2A),
                            items: svc.ttsEngineList
                                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              final ok = await svc.setTtsEngine(v);
                              if (mounted && !ok) {
                                showAppNotice(context, '引擎切换失败，已尝试恢复原引擎。', AppNoticeKind.error);
                              }
                            },
                          ),
                        const SizedBox(height: 8),
                        ImportSecondaryButton(
                          label: '恢复系统默认引擎',
                          onPressed: () async {
                            await svc.clearPreferredEngine();
                            if (mounted) {
                              showAppNotice(context, '已恢复系统默认引擎。', AppNoticeKind.success);
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        ImportPrimaryButton(
                          label: _ttsSettingsBusy ? '正在打开…' : '打开系统 TTS 设置',
                          icon: Icons.settings_voice,
                          onPressed: _ttsSettingsBusy ? null : _openTtsSettings,
                        ),
                        const SizedBox(height: 8),
                        ImportSecondaryButton(
                          label: _refreshing ? '探测中…' : '重新探测',
                          onPressed: _refreshing ? null : _refreshTts,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '在系统设置里这样配中文语音：\n'
                          '1. 点上方按钮进“文字转语音输出”，把“首选引擎”选成你已装的引擎；\n'
                          '2. 点该引擎右侧的设置 / 语音数据，下载“中文（普通话）”语音数据；\n'
                          '3. 回到本页点“重新探测”，状态变“中文语音已安装”后再点“试听一句”。\n'
                          '若没有“文字转语音输出”入口，说明未装 TTS 引擎，先从应用商店装一个（如 Google 文字转语音）再按上面步骤配。',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ImportPrimaryButton(
                        label: _testing ? '试听中…' : '试听一句',
                        icon: Icons.volume_up,
                        onPressed: _testing ? null : _test,
                      ),
                    ),
                    if (_testResult != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ImportNotice(
                          // v1.2.1：按试听实际结果着色，不再按“已播报/
                          // 已发出”字样猜——新文案是“试听完成”才算成功。
                          message: _testResult!,
                          kind: _testOk
                              ? ImportNoticeKind.success
                              : ImportNoticeKind.error,
                        ),
                      ),
                    // 自定义语音服务（可选）：只存用户自己填的地址与 Key，
                    // 协议 / 存储 / 白名单逻辑未动，只按统一导入画风换 UI。
                    ImportCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('自定义语音服务（可选，非默认）',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text(
                          '默认走系统 TTS。自定义服务音质更好，但要用你自己的 Key、需联网、可能按量计费。' '未填时走系统 TTS；填了也要开下方开关才用，失败时回落系统 TTS。',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        DropdownButton<String>(
                          value: _provider,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF2A2A2A),
                          items: const [
                            DropdownMenuItem(value: 'generic', child: Text('通用接口', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'mimo', child: Text('小米 MiMo（mimo-v2.5-tts）', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _provider = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        if (_provider == 'mimo') ...[
                          const Text(
                            '固定接口：https://api.xiaomimimo.com/v1/chat/completions（无需手填）\n'
                            'Key 在小米 MiMo 开放平台自行申请，只存本机；模型 mimo-v2.5-tts，失败时回落系统 TTS。',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          ImportBorderedTextField(
                            controller: _keyCtrl,
                            label: 'MiMo API Key（只存本机，不上传）',
                            obscureText: true,
                          ),
                          const SizedBox(height: 8),
                          DropdownButton<String>(
                            value: mimoTtsVoices.contains(_mimoVoice) ? _mimoVoice : '冰糖',
                            isExpanded: true,
                            dropdownColor: const Color(0xFF2A2A2A),
                            items: mimoTtsVoices
                                .map((v) => DropdownMenuItem(value: v, child: Text('音色：$v', style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _mimoVoice = v);
                            },
                          ),
                        ] else ...[
                          ImportBorderedTextField(
                            controller: _endpointCtrl,
                            label: '接口地址（你自己的服务地址）',
                          ),
                          const SizedBox(height: 8),
                          ImportBorderedTextField(
                            controller: _keyCtrl,
                            label: 'API Key（只存本机，不上传）',
                            obscureText: true,
                          ),
                        ],
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: const Text('启用自定义语音服务'),
                          subtitle: const Text('关闭时完全走原生 TTS'),
                          value: svc.customVoice.enabled,
                          onChanged: (v) async {
                            await svc.updateCustomVoice(CustomVoiceConfig(
                              enabled: v,
                              endpoint: _endpointCtrl.text.trim(),
                              apiKey: _keyCtrl.text,
                              provider: _provider,
                              mimoVoice: _mimoVoice,
                            ));
                            if (mounted) setState(() {});
                          },
                        ),
                        Row(children: [
                          Expanded(
                            child: ImportSecondaryButton(
                              label: '保存到本机',
                              onPressed: _saveCustom,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ImportPrimaryButton(
                              label: _customTesting ? '测试中…' : '测试自定义服务',
                              onPressed: _customTesting ? null : _testCustom,
                            ),
                          ),
                        ]),
                        if (_customTestResult != null) ...[
                          const SizedBox(height: 8),
                          ImportNotice(
                            message: _customTestResult!,
                            kind: ImportNotice.kindFromMessage(_customTestResult!),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _provider == 'mimo'
                              ? 'MiMo 与通用接口不互通，选错提供方会明确报错。'
                              : '通用接口：POST JSON {"text": "..."}、Authorization: Bearer <Key>，期望返回音频流；协议不符时测试会明确报错。',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                  ]),
            ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          SizedBox(width: 48, child: Text(label)),
          Expanded(child: Slider(value: value, min: min, max: max, divisions: 15, onChanged: onChanged)),
          SizedBox(width: 40, child: Text(value.toStringAsFixed(2), textAlign: TextAlign.right)),
        ]),
      ),
    );
  }
}
