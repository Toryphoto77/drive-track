import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'native.dart';
import 'recorder.dart';

/// 性能测试挑战（v1.0.2，第 7 项）。
///
/// 安全立场（页面顶部第一块就是安全提示，开始按钮须先勾选确认）：
/// 仅在封闭场地 / 合法合规场所测试、遵守限速与法律法规、不要在
/// 公开道路上测试。本页不做任何鼓励超速的文案与排行，不把成绩
/// 包装成“挑战极限”；刹停项表述为制动时间记录，同样只限封闭场地。
///
/// 定位源复用，不另造一套：本页不调用 Native.startLocation，
/// 不开新的定位通道。速度只来自调用方传入的二选一：
/// - [PerformanceChallengePage.recorder]：监听已有 Recorder，
///   读 Recorder.curSpeed（米/秒，手机 GPS 或已切换的外接 GPS
///   都会经 onLocation / onExternalFix 更新它）；
/// - [PerformanceChallengePage.speedSampleStream]：调用方把已有
///   定位流映射成的 SpeedSample 流传进来（可带 hAcc / speedAcc）。
/// 两者都为空时页面显示“未接入定位源”，开始按钮禁用，绝不计时。
/// 主协调接线：首页性能入口与记录页顶部小入口 push 本页时传
/// 入当前 Recorder 即可（见回执的接线钩子）。

/// 页面顶部安全提示文案（必须出现在挑战页顶部第一块）。
const String performanceChallengeSafetyNotice =
    '仅在封闭场地/合法合规场所测试、遵守限速与法律法规、不要在公开道路上测试。';
const String performanceChallengeSafetyDetail =
    '测试前请确认场地空旷、无行人，系好安全带，遵守场地规则与法律法规；'
    '成绩仅供参考，不构成驾驶建议。本页不鼓励、不组织公开道路竞速。';

enum ChallengeType { accel0100, brake1000 }

extension ChallengeTypeLabel on ChallengeType {
  String get label => switch (this) {
        ChallengeType.accel0100 => '0-100 加速',
        ChallengeType.brake1000 => '100-0 刹停',
      };
  String get shortLabel => switch (this) {
        ChallengeType.accel0100 => '0-100',
        ChallengeType.brake1000 => '100-0',
      };
}

/// 一次 GPS 速度样本。时间用调用方给定的毫秒时间戳（Recorder 路径
/// 用收到样本时的本地时间）；精度字段缺失时为 null，缺失不等于
/// 精度好，见 [PerformanceChallengeEngine] 的未验证判定。
class SpeedSample {
  const SpeedSample({
    required this.timeMs,
    required this.speedKmh,
    this.hAccM,
    this.speedAccMps,
  });

  final int timeMs;
  final double speedKmh;

  /// 水平精度（米），null = 本次样本无精度信息。
  final double? hAccM;

  /// 速度精度（米/秒），null = 本次样本无精度信息。
  final double? speedAccMps;

  bool get hasAnyAccuracy => hAccM != null || speedAccMps != null;
}

enum ChallengePhase { idle, armed, running, finished, invalid }

/// 一次已完结的计时结果。valid=false 时 durationMs 为 null，
/// 且调用方（页面）必须不把它写入历史与最好成绩。
class ChallengeOutcome {
  const ChallengeOutcome({
    required this.type,
    required this.phase,
    this.durationMs,
    this.invalidReason,
    this.maxSpeedKmh,
    this.badSampleCount = 0,
  });

  final ChallengeType type;
  final ChallengePhase phase;
  final int? durationMs;
  final String? invalidReason;
  final double? maxSpeedKmh;
  final int badSampleCount;

  bool get valid => phase == ChallengePhase.finished && durationMs != null;

  double? get durationSeconds =>
      durationMs == null ? null : durationMs! / 1000;
}

/// 性能挑战计时引擎：纯 Dart，可单元测试，不依赖 Flutter widget
/// 与定位通道，只消费 [SpeedSample]。
///
/// 计时规则（写在代码里，页面脚注同样写明，绝不含糊）：
/// - 0-100：待命后，速度首次 ≥ 3 km/h 视为起步（过滤静止 GPS 漂移，
///   0–3 km/h 段不计入成绩，计时起点为该样本时间）；随后速度首次
///   ≥ 100 km/h 的样本为终点。成绩 = 终点时间 − 起点时间。
/// - 100-0：待命后须先出现 ≥ 100 km/h 的样本（表示已达速），随后
///   速度首次跌破 100 km/h 的样本为起点，首次 ≤ 2 km/h 的样本为
///   终点。成绩 = 终点时间 − 起点时间。未达 100 就减速不算一次。
/// - 计时分辨率受 GPS 采样间隔限制：成绩只能精确到样本间隔，
///   本页不做插值、不补点、不四舍五入成“更漂亮”的数字。
///
/// 无效判定（任一成立即判无效，不记成绩、不进最好成绩与历史）：
/// 1. 计时进行中出现精度超门槛样本：hAcc > 20 m，或 speedAcc > 2.0 m/s。
///    待命期超门槛样本不触发起/停表，只计数并提示（它没参与计时）。
/// 2. 全程没有任何样本带精度信息：完赛时判“精度未验证”，不记成绩。
///    注意：经 Recorder 的外接 GPS 路径目前无精度字段（onExternalFix
///    不更新 curHAcc，Recorder 也未保留 sAcc），该路径的成绩会因此
///    判未验证；要让外接成绩可验证，须后续把 HDOP / 卫星数透传，
///    本次不另造定位源、不编造精度。
/// 3. 计时进行中 GPS 采样中断超过 2 秒（连续样本间隔 > 2000 ms）。
/// 4. 单步速度跳变过大：间隔 < 1000 ms 内速度变化 > 50 km/h，
///    疑似 GPS 跳点；计时进行中出现即判无效，待命期出现只丢弃该样本。
class PerformanceChallengeEngine {
  PerformanceChallengeEngine(this.type);

  static const double startThresholdKmh = 3;
  static const double targetKmh = 100;
  static const double stopThresholdKmh = 2;
  static const double maxHAccM = 20;
  static const double maxSpeedAccMps = 2.0;
  static const int maxGapMs = 2000;
  static const double maxStepKmh = 50;

  final ChallengeType type;
  ChallengePhase phase = ChallengePhase.idle;
  int? startMs;
  int? finishMs;
  String? invalidReason;
  int badSampleCount = 0;
  double? maxSpeedKmh;
  bool _hasReachedTarget = false;
  bool _accuracySeenInRun = false;
  SpeedSample? _last;

  void arm() {
    phase = ChallengePhase.armed;
    startMs = null;
    finishMs = null;
    invalidReason = null;
    badSampleCount = 0;
    maxSpeedKmh = null;
    _hasReachedTarget = false;
    _accuracySeenInRun = false;
    _last = null;
  }

  void cancel() {
    phase = ChallengePhase.idle;
    startMs = null;
    finishMs = null;
    invalidReason = null;
    _last = null;
  }

  void _invalidate(String reason) {
    phase = ChallengePhase.invalid;
    invalidReason = reason;
    finishMs = null;
  }

  /// 喂入一个样本。已完结（finished / invalid）或未待命时忽略。
  ChallengePhase feed(SpeedSample s) {
    if (phase != ChallengePhase.armed && phase != ChallengePhase.running) {
      return phase;
    }
    final prev = _last;
    if (prev != null) {
      final gap = s.timeMs - prev.timeMs;
      if (gap < 0) {
        // 时间倒流的样本直接丢弃，不参与状态机。
        badSampleCount++;
        return phase;
      }
      if (phase == ChallengePhase.running && gap > maxGapMs) {
        _invalidate('GPS 采样中断超过 2 秒，成绩无效，未记入历史。');
        return phase;
      }
      if (gap > 0 &&
          gap < 1000 &&
          (s.speedKmh - prev.speedKmh).abs() > maxStepKmh) {
        if (phase == ChallengePhase.running) {
          _invalidate('速度单步跳变过大（疑似 GPS 跳点），成绩无效，未记入历史。');
          return phase;
        }
        badSampleCount++;
        _last = s;
        return phase;
      }
    }
    final accuracyBad = (s.hAccM != null && s.hAccM! > maxHAccM) ||
        (s.speedAccMps != null && s.speedAccMps! > maxSpeedAccMps);
    if (accuracyBad) {
      badSampleCount++;
      if (phase == ChallengePhase.running) {
        _invalidate('GPS 精度不足（水平精度 > 20 m 或速度精度 > 2.0 m/s），'
            '成绩无效，未记入历史。');
        return phase;
      }
      // 待命期超门槛样本：不触发起表，只计数；本次样本不更新 _last
      // 以外的状态，避免一个坏点误起表。
      _last = s;
      return phase;
    }
    if (s.hasAnyAccuracy) _accuracySeenInRun = true;
    if (maxSpeedKmh == null || s.speedKmh > maxSpeedKmh!) {
      maxSpeedKmh = s.speedKmh;
    }
    _last = s;

    switch (type) {
      case ChallengeType.accel0100:
        if (phase == ChallengePhase.armed &&
            s.speedKmh >= startThresholdKmh) {
          phase = ChallengePhase.running;
          startMs = s.timeMs;
        } else if (phase == ChallengePhase.running &&
            s.speedKmh >= targetKmh) {
          _finish(s.timeMs);
        }
      case ChallengeType.brake1000:
        if (phase == ChallengePhase.armed && !_hasReachedTarget) {
          if (s.speedKmh >= targetKmh) _hasReachedTarget = true;
        } else if (phase == ChallengePhase.armed && _hasReachedTarget) {
          if (s.speedKmh < targetKmh) {
            phase = ChallengePhase.running;
            startMs = s.timeMs;
          }
        } else if (phase == ChallengePhase.running &&
            s.speedKmh <= stopThresholdKmh) {
          _finish(s.timeMs);
        }
    }
    return phase;
  }

  void _finish(int atMs) {
    if (!_accuracySeenInRun) {
      _invalidate('全程无 GPS 精度信息，成绩未验证，不记入历史与最好成绩。');
      return;
    }
    phase = ChallengePhase.finished;
    finishMs = atMs;
  }

  ChallengeOutcome get outcome => ChallengeOutcome(
        type: type,
        phase: phase,
        durationMs: (phase == ChallengePhase.finished &&
                startMs != null &&
                finishMs != null)
            ? finishMs! - startMs!
            : null,
        invalidReason: invalidReason,
        maxSpeedKmh: maxSpeedKmh,
        badSampleCount: badSampleCount,
      );

  /// 刹停待命期的 UI 提示：是否已见 ≥ 100 km/h。
  bool get hasReachedTarget => _hasReachedTarget;
}

/// 一条已保存的有效成绩。
class ChallengeRunRecord {
  const ChallengeRunRecord({
    required this.type,
    required this.durationMs,
    required this.createdMs,
    this.maxSpeedKmh,
    this.source = 'unknown',
  });

  final ChallengeType type;
  final int durationMs;
  final int createdMs;
  final double? maxSpeedKmh;

  /// 'phone' / 'external' / 'unknown'：调用方传入的来源标注，
  /// 本页不推断（Recorder 路径无法区分时写 unknown，不冒充）。
  final String source;

  double get durationSeconds => durationMs / 1000;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'durationMs': durationMs,
        'createdMs': createdMs,
        if (maxSpeedKmh != null) 'maxSpeedKmh': maxSpeedKmh,
        'source': source,
      };

  static ChallengeRunRecord? fromJson(Map<String, dynamic> json) {
    final typeName = (json['type'] ?? '').toString();
    final type = ChallengeType.values
        .where((t) => t.name == typeName)
        .firstOrNull;
    final durationMs = (json['durationMs'] as num?)?.toInt();
    final createdMs = (json['createdMs'] as num?)?.toInt();
    if (type == null || durationMs == null || createdMs == null) {
      return null;
    }
    return ChallengeRunRecord(
      type: type,
      durationMs: durationMs,
      createdMs: createdMs,
      maxSpeedKmh: (json['maxSpeedKmh'] as num?)?.toDouble(),
      source: (json['source'] ?? 'unknown').toString(),
    );
  }
}

/// 历史成绩本机存储：Native.getFilesDir() 下的 JSON 文件，
/// 与 DeviceCenterStore 同款写法，不走服务器。无效成绩永不写入。
class PerformanceChallengeStore {
  static const String fileName = 'performance_challenge_history.json';

  static Future<List<ChallengeRunRecord>> load() async {
    try {
      final dir = await Native.getFilesDir();
      final file = File('$dir/$fileName');
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) =>
              ChallengeRunRecord.fromJson(Map<String, dynamic>.from(e)))
          .whereType<ChallengeRunRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> save(List<ChallengeRunRecord> records) async {
    try {
      final dir = await Native.getFilesDir();
      final file = File('$dir/$fileName');
      await file.writeAsString(
          jsonEncode(records.map((r) => r.toJson()).toList()));
      return true;
    } catch (_) {
      return false;
    }
  }

  static ChallengeRunRecord? bestFor(
      List<ChallengeRunRecord> records, ChallengeType type) {
    final mine = records.where((r) => r.type == type).toList();
    if (mine.isEmpty) return null;
    mine.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    return mine.first;
  }
}

/// 性能测试挑战页（v1.0.2，第 7 项）。
///
/// 构造函数（主协调接线钩子，见回执）：
/// ```dart
/// PerformanceChallengePage(
///   onBack: () => Navigator.of(context).pop(),
///   recorder: rec, // 首页 / 记录页已有的 Recorder，不传则须传 speedSampleStream
/// )
/// ```
/// 不传 recorder 也不传 speedSampleStream 时，页面只展示、不计时。
class PerformanceChallengePage extends StatefulWidget {
  const PerformanceChallengePage({
    super.key,
    this.onBack,
    this.recorder,
    this.speedSampleStream,
  });

  /// 返回上一页的回调；不传则用 Navigator.maybePop。
  final VoidCallback? onBack;

  /// 已有 Recorder（推荐）：监听它读 curSpeed / curHAcc。
  /// 注意 Recorder 未保留速度精度 sAcc，且外接 GPS 路径不更新
  /// curHAcc（999 占位会被本页视为无精度信息），该路径成绩将判
  /// 未验证——这是现有 Recorder 的真实限制，不是本页的 bug 掩盖。
  final Recorder? recorder;

  /// 调用方把已有定位流映射成的速度样本流（可带 hAcc / speedAcc）。
  /// 与 recorder 二选一；两者都传时以 speedSampleStream 为准。
  final Stream<SpeedSample>? speedSampleStream;

  @override
  State<PerformanceChallengePage> createState() =>
      _PerformanceChallengePageState();
}

class _PerformanceChallengePageState extends State<PerformanceChallengePage> {
  ChallengeType _type = ChallengeType.accel0100;
  PerformanceChallengeEngine _engine =
      PerformanceChallengeEngine(ChallengeType.accel0100);
  bool _safetyConfirmed = false;
  List<ChallengeRunRecord> _history = [];
  ChallengeOutcome? _lastOutcome;
  double? _curSpeedKmh;
  double? _curHAccM;
  double? _curSpeedAccMps;
  int _badSamples = 0;
  String? _notice;
  StreamSubscription<SpeedSample>? _streamSub;

  bool get _hasSource =>
      widget.recorder != null || widget.speedSampleStream != null;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    if (widget.speedSampleStream != null) {
      _streamSub =
          widget.speedSampleStream!.listen(_onSample, onError: (_) {});
    } else {
      widget.recorder?.addListener(_onRecorderTick);
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    widget.recorder?.removeListener(_onRecorderTick);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await PerformanceChallengeStore.load();
    if (!mounted) return;
    setState(() => _history = list);
  }

  void _onRecorderTick() {
    final rec = widget.recorder;
    if (rec == null || !mounted) return;
    // curHAcc == 999 是 Recorder 的“未知”占位（手机 GPS 无精度或
    // 外接 GPS 未更新时），必须映射为 null，绝不能把 999 当成 999 米
    // 精度或当成有效精度用。
    final hAcc = rec.curHAcc == 999 ? null : rec.curHAcc;
    _onSample(SpeedSample(
      timeMs: DateTime.now().millisecondsSinceEpoch,
      speedKmh: rec.curSpeed * 3.6,
      hAccM: hAcc,
      // Recorder 未保留 sAcc：此处恒为 null，精度门槛只看 hAcc；
      // 若 hAcc 亦为 null，本次成绩将判未验证（见引擎注释）。
      speedAccMps: null,
    ));
  }

  void _onSample(SpeedSample s) {
    if (!mounted) return;
    final before = _engine.phase;
    final after = _engine.feed(s);
    setState(() {
      _curSpeedKmh = s.speedKmh;
      _curHAccM = s.hAccM;
      _curSpeedAccMps = s.speedAccMps;
      _badSamples = _engine.badSampleCount;
    });
    if (before != after &&
        (after == ChallengePhase.finished ||
            after == ChallengePhase.invalid)) {
      _onFinished();
    }
  }

  Future<void> _onFinished() async {
    final outcome = _engine.outcome;
    if (!mounted) return;
    setState(() => _lastOutcome = outcome);
    if (!outcome.valid || outcome.durationMs == null) {
      setState(() => _notice = outcome.invalidReason ?? '本次成绩无效，未记入历史。');
      return;
    }
    final record = ChallengeRunRecord(
      type: outcome.type,
      durationMs: outcome.durationMs!,
      createdMs: DateTime.now().millisecondsSinceEpoch,
      maxSpeedKmh: outcome.maxSpeedKmh,
      // Recorder 路径无法可靠区分手机 / 外接来源时写 unknown，
      // 不冒充来源；调用方若能确定来源，可在后续版本经参数传入。
      source: 'unknown',
    );
    final next = [record, ..._history];
    final ok = await PerformanceChallengeStore.save(next);
    if (!mounted) return;
    setState(() {
      _history = next;
      _notice = ok ? '有效成绩已保存。' : '成绩有效，但本机保存失败，历史未写入。';
    });
  }

  void _selectType(ChallengeType t) {
    if (_engine.phase == ChallengePhase.running ||
        _engine.phase == ChallengePhase.armed) {
      setState(() => _notice = '计时进行中：请先取消当前计时再切换项目。');
      return;
    }
    setState(() {
      _type = t;
      _engine = PerformanceChallengeEngine(t);
      _lastOutcome = null;
      _badSamples = 0;
    });
  }

  void _arm() {
    if (!_safetyConfirmed) {
      setState(() => _notice = '请先勾选顶部安全确认，再开始计时。');
      return;
    }
    if (!_hasSource) {
      setState(() => _notice = '未接入定位源：本页不自建定位，请由调用方传入 Recorder 或速度样本流。');
      return;
    }
    setState(() {
      _engine.arm();
      _lastOutcome = null;
      _badSamples = 0;
      _notice = _type == ChallengeType.accel0100
          ? '已待命：车辆起步、速度首次 ≥ 3 km/h 时起表，到 100 km/h 停表。'
          : '已待命：请先加速到 100 km/h 以上，速度跌破 100 km/h 时起表，到 ≤ 2 km/h 停表。';
    });
  }

  void _cancel() {
    setState(() {
      _engine.cancel();
      _notice = '已取消当前计时，未记成绩。';
    });
  }

  Future<void> _deleteRecord(ChallengeRunRecord record) async {
    final next = _history.where((r) => r != record).toList();
    final ok = await PerformanceChallengeStore.save(next);
    if (!mounted) return;
    setState(() {
      _history = next;
      _notice = ok ? '已删除该条成绩。' : '删除失败：本机文件写入失败。';
    });
  }

  Future<void> _clearHistory() async {
    final ok = await PerformanceChallengeStore.save(const []);
    if (!mounted) return;
    setState(() {
      _history = const [];
      _notice = ok ? '历史已清空。' : '清空失败：本机文件写入失败。';
    });
  }

  String get _phaseLabel => switch (_engine.phase) {
        ChallengePhase.idle => '未开始',
        ChallengePhase.armed => _type == ChallengeType.brake1000 &&
                _engine.hasReachedTarget
            ? '待命：已达 100 km/h，刹车跌破 100 即起表'
            : '待命：等待触发',
        ChallengePhase.running => '计时中…',
        ChallengePhase.finished => '已完成',
        ChallengePhase.invalid => '无效',
      };

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bestAccel =
        PerformanceChallengeStore.bestFor(_history, ChallengeType.accel0100);
    final bestBrake =
        PerformanceChallengeStore.bestFor(_history, ChallengeType.brake1000);
    final busy = _engine.phase == ChallengePhase.armed ||
        _engine.phase == ChallengePhase.running;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        title: const Text('性能测试', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部第一块：安全提示（第 7 项硬性要求）。
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.warning_amber, color: Colors.orangeAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('安全提示',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(performanceChallengeSafetyNotice,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(performanceChallengeSafetyDetail,
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                CheckboxListTile(
                  value: _safetyConfirmed,
                  onChanged: (v) =>
                      setState(() => _safetyConfirmed = v ?? false),
                  title: const Text('我已阅读并确认仅在封闭场地测试',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_hasSource)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '未接入定位源：本页不自建定位、不启动定位通道。调用方须传入已有 '
                'Recorder 或速度样本流（主协调接线），否则无法计时。',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          if (_notice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_notice!,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          // 项目选择。
          Row(children: [
            for (final t in ChallengeType.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton(
                    onPressed: () => _selectType(t),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _type == t ? accent : Colors.white12,
                    ),
                    child: Text(t.label),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          // 实时速度与状态。
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0E13),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                Text(
                  _curSpeedKmh == null
                      ? '— km/h'
                      : '${_curSpeedKmh!.toStringAsFixed(1)} km/h',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text('状态：$_phaseLabel',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  'GPS 精度：${_curHAccM == null ? '无 hAcc 信息' : 'hAcc ${_curHAccM!.toStringAsFixed(1)} m'}'
                  ' · ${_curSpeedAccMps == null ? '无速度精度信息' : '速度精度 ${_curSpeedAccMps!.toStringAsFixed(2)} m/s'}'
                  '${_badSamples > 0 ? ' · 超门槛样本 $_badSamples 条' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy || !_safetyConfirmed || !_hasSource
                          ? null
                          : _arm,
                      child: Text(_type == ChallengeType.accel0100
                          ? '开始待命：0-100'
                          : '开始待命：100-0'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? _cancel : null,
                      child: const Text('取消计时'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_lastOutcome != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('上次结果：${_lastOutcome!.type.label}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _lastOutcome!.valid
                        ? '成绩：${_lastOutcome!.durationSeconds!.toStringAsFixed(2)} 秒'
                            '（最高 ${_lastOutcome!.maxSpeedKmh?.toStringAsFixed(1) ?? '—'} km/h，已保存）'
                        : '无效：${_lastOutcome!.invalidReason ?? '未知原因'}（未记入历史与最好成绩）',
                    style: TextStyle(
                        color: _lastOutcome!.valid
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text('最好成绩（仅有效成绩）',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _bestRow('0-100 加速', bestAccel),
          _bestRow('100-0 刹停', bestBrake),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(
              child: Text('历史列表（仅有效成绩）',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
            if (_history.isNotEmpty)
              TextButton(onPressed: _clearHistory, child: const Text('清空')),
          ]),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Text('暂无有效成绩：无效成绩不会出现在这里。',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          for (final r in _history)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E13),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.type.label} · ${r.durationSeconds.toStringAsFixed(2)} 秒',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${_formatDate(r.createdMs)} · 来源 ${r.source}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                    onPressed: () => _deleteRecord(r),
                    child: const Text('删除')),
              ]),
            ),
          const SizedBox(height: 12),
          const Text(
            '计时规则：0-100 从速度首次 ≥ 3 km/h 起表（0–3 km/h 段不计入，'
            '过滤静止漂移），到首次 ≥ 100 km/h 停表；100-0 须先达 100 km/h，'
            '随后首次跌破 100 km/h 起表，到首次 ≤ 2 km/h 停表。计时分辨率受 '
            'GPS 采样间隔限制，不做插值。无效判定：计时中精度超门槛（hAcc > 20 m '
            '或速度精度 > 2.0 m/s）、采样中断超 2 秒、单步跳变 > 50 km/h、'
            '全程无精度信息，一律不记成绩。经 Recorder 的外接 GPS 路径目前无'
            '精度字段，其成绩将判未验证，须后续透传精度信息后才可验证。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _bestRow(String label, ChallengeRunRecord? best) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white)),
        ),
        Text(
          best == null
              ? '—'
              : '${best.durationSeconds.toStringAsFixed(2)} 秒',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ]),
    );
  }
}
