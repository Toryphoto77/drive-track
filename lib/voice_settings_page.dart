import 'package:flutter/material.dart';
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
/// - 原生 TextToSpeech 初始化是异步的：先试 Locale.CHINESE，
///   返回 LANG_AVAILABLE / LANG_COUNTRY_AVAILABLE 才算中文可用；
///   中文不可用时回退系统默认语言，默认语言也不可用时才判
///   ttsLanguage='none'、ttsReady=false，Dart 侧收到
///   available=false + error='tts_unavailable'。
/// - 所以“无引擎”在页面上其实是三种不同情况，旧页只写一句话分不清：
///   ① 系统根本没装 TTS 引擎（无 Google TTS 的国产机 / 精简系统常见，
///     TextToSpeech 构造失败或 init 回调非 SUCCESS）；
///   ② 装了引擎、但中文语音数据没下载（setLanguage(CHINESE) 返回
///     LANG_MISSING_DATA / LANG_NOT_SUPPORTED），此时若默认语言可用
///     会回退默认语言播报、只是不是中文；
///   ③ 引擎列表非空、但所选引擎的中文与默认语言都不可用。
/// - 旧页的另一个缺口：打开时只调 loadEngines() 查引擎列表，
///   不调 ensureAvailable() 探测可用性与语言，ttsAvailable /
///   ttsLanguage 在点“试听”前一直是 null，页面只能写“状态待探测”。
///   本版打开时即 loadEngines + ensureAvailable，状态、当前引擎、
///   中文数据状态三行一次给全；“试听”仍走 speakTest，成功/失败
///   都把原因留在按钮下方，设备静音时仍发出并提示“可能听不到”。
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
  String? _customTestResult;
  bool _testing = false;
  bool _customTesting = false;
  bool _refreshing = false;
  bool _ttsSettingsBusy = false;
  late final TextEditingController _endpointCtrl = TextEditingController();
  late final TextEditingController _keyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    VoiceService.instance.load().then((_) async {
      // 打开即探测：引擎列表 + 可用性/语言一次给全，不等用户点试听。
      await VoiceService.instance.loadEngines();
      await VoiceService.instance.ensureAvailable();
      if (!mounted) return;
      final c = VoiceService.instance.customVoice;
      _endpointCtrl.text = c.endpoint;
      _keyCtrl.text = c.apiKey;
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
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openTtsSettings() async {
    setState(() => _ttsSettingsBusy = true);
    final ok = await Native.openTtsSettings();
    if (mounted) {
      setState(() => _ttsSettingsBusy = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '该设备没有系统 TTS 设置页，请手动打开：系统设置 > 系统 > '
              '语言与输入法 > 文字转语音输出，在里面选首选引擎并下载中文语音数据。',
            ),
          ),
        );
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
      _testResult = r.$2;
    });
  }

  Future<void> _saveCustom() async {
    final next = CustomVoiceConfig(
      enabled: VoiceService.instance.customVoice.enabled,
      endpoint: _endpointCtrl.text.trim(),
      apiKey: _keyCtrl.text,
    );
    await VoiceService.instance.updateCustomVoice(next);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('自定义语音服务配置已保存到本机，未上传。')));
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
  String _ttsStatusTitle() {
    final svc = VoiceService.instance;
    if (svc.ttsAvailable == null || svc.ttsLanguage == null) {
      return '语音引擎状态待探测';
    }
    switch (svc.ttsLanguage) {
      case 'zh':
        return '语音可用 · 中文语音已安装';
      case 'default':
        return '语音可用，但中文语音未安装';
      case 'none':
        return svc.ttsEngineList.isEmpty ? '无可用语音引擎（系统未装 TTS 引擎）' : '有引擎，但无可用语言';
      default:
        return '语音引擎状态待探测';
    }
  }

  /// 无引擎时的明确原因：引擎列表空 / 非空、原生错误码分开写。
  String _ttsCauseDetail() {
    final svc = VoiceService.instance;
    final err = svc.lastError;
    final errText = err == null ? '' : '（原生错误码：$err）';
    if (svc.ttsEngineList.isEmpty) {
      return '原因：系统没有返回任何已装 TTS 引擎，常见于未预装 Google '
          '文字转语音的国产机或精简系统——不是 App 没开开关，是系统层 '
          '就没有可用的语音引擎$errText。下一步：先在系统 TTS 设置里 '
          '安装 / 启用一个 TTS 引擎（如 Google 文字转语音），再下载中文语音数据。';
    }
    return '原因：已装引擎 ${svc.ttsEngineList.length} 个，但中文与系统默认语言 '
        '都不可用（语音数据缺失或引擎被禁用）$errText。下一步：在系统 TTS '
        '设置里换一个首选引擎，或为当前引擎下载中文语音数据，再回本页点“重新探测”。';
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
                      subtitle: const Text('默认开启，可一键关闭'),
                      value: _s.enabled,
                      onChanged: (v) => _apply(_s.copyWith(enabled: v)),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(voiceMutedNote, style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(children: [
                        SwitchListTile(title: const Text('事件播报'), subtitle: const Text('急加速、急刹车、过弯完成、压弯超阈值'), value: _s.announceEvents, onChanged: (v) => _apply(_s.copyWith(announceEvents: v))),
                        SwitchListTile(title: const Text('圈速播报'), subtitle: const Text('每圈完成与最快圈'), value: _s.announceLaps, onChanged: (v) => _apply(_s.copyWith(announceLaps: v))),
                        SwitchListTile(title: const Text('结束总结播报'), subtitle: const Text('里程、时长、评分、最快圈'), value: _s.announceSummary, onChanged: (v) => _apply(_s.copyWith(announceSummary: v))),
                      ]),
                    ),
                    _slider('语速', _s.rate, 0.5, 2.0, (v) => _apply(_s.copyWith(rate: v))),
                    _slider('音调', _s.pitch, 0.5, 2.0, (v) => _apply(_s.copyWith(pitch: v))),
                    _slider('音量', _s.volume, 0.0, 1.0, (v) => _apply(_s.copyWith(volume: v))),
                    // 原生 TTS 引擎状态：当前引擎 + 中文数据状态 + 原因 + 下一步。
                    ImportCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('系统 TTS 引擎（原生，默认）',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(_ttsStatusTitle(),
                            style: TextStyle(
                              color: svc.ttsLanguage == 'zh'
                                  ? Colors.greenAccent
                                  : svc.ttsLanguage == 'default'
                                      ? Colors.orange
                                      : svc.ttsLanguage == 'none'
                                          ? Colors.redAccent
                                          : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 4),
                        Text(
                          svc.ttsLanguage == 'zh'
                              ? '当前引擎支持中文，播报走中文语音。'
                              : svc.ttsLanguage == 'default'
                                  ? '中文语音数据未安装，已回退系统默认语言播报：播报能出声，但不一定是中文。按下面步骤装中文数据后可恢复中文播报。'
                                  : svc.ttsLanguage == 'none'
                                      ? _ttsCauseDetail()
                                      : '正在探测系统 TTS 引擎与中文语音数据，点“重新探测”可再查一次。',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ImportInnerCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '当前引擎：${svc.ttsEngineCurrent ?? '系统默认（未指定）'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已装引擎：${svc.ttsEngineList.isEmpty ? '暂无（点“重新探测”后仍为空，即系统未装引擎）' : '${svc.ttsEngineList.length} 个'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '中文语音数据：${svc.ttsLanguage == 'zh' ? '已安装' : svc.ttsLanguage == 'default' ? '未安装（已回退默认语言）' : svc.ttsLanguage == 'none' ? '不可用（无引擎或语言数据缺失）' : '待探测'}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('引擎切换失败，已保持原引擎。')));
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
                          '若系统里根本没有“文字转语音输出”入口，说明该机型未装 TTS 引擎，'
                          '需先从应用商店安装一个 TTS 引擎（如 Google 文字转语音）再按上面步骤配中文数据。',
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
                          message: _testResult!,
                          kind: _testResult!.contains('已播报') || _testResult!.contains('已发出')
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
                          '默认仍走系统原生 TTS。自定义服务（讯飞/阿里/腾讯等）音质更好，'
                          '但需要你自己的 Key、需要联网、可能按量计费，Key 有保管风险，'
                          '因此不内置任何 Key、不预填示例 Key。未填时完全走原生；填了也只在'
                          '你明确开启下方开关后才用，失败时回落原生并记录原因。',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
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
                        const Text(
                          '通用接口约定：POST JSON {"text": "..."}、Authorization: Bearer <Key>，'
                          '期望返回音频流；各厂商协议不同，协议不符时测试会明确报错。',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
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
