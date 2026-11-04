/// 赛道模式纯 Dart 计时逻辑（新文件，不改动已有文件）。
///
/// 设计原则：
/// - 本文件零 Flutter 依赖、零项目内 import，可直接单测：调用方把 1Hz 轨迹点
///   喂给 [LapTimer.addPoint] 即可，事后也可用同一类对已存轨迹做离线重算。
/// - 本文件不引用 models.dart 的 TrackPoint：调用方把 lat/lon/speed/timeMs
///   抄成 [TimedPoint] 再喂入，避免计时逻辑与行程模型互相耦合。
/// - 赛道模式下不套用街道驾驶评分：本文件只输出圈速与圈速稳定性指标
///   （[LapStability]：圈速标准差 / 极差 / 平均圈速），评分字段由接线方
///   在赛道模式下留空或标注“赛道模式不评分”，不得把街道评分混进来。
/// - 起终点基准：以赛道起终点经纬度，或用户在赛道页点的起终点为准，
///   由调用方在构造 [LapTimer] 时传入。本文件不猜、不内置任何赛道坐标
///   （目录文件 track_catalog.dart 也故意不含坐标，见其文件头注释）。

import 'dart:math' as math;

/// 计时用的最小轨迹点：时间（ms）、经纬度、速度（m/s）。
class TimedPoint {
  final int timeMs;
  final double lat;
  final double lon;
  final double speed;
  const TimedPoint({
    required this.timeMs,
    required this.lat,
    required this.lon,
    required this.speed,
  });
}

/// 一个经纬度点（起终点 / 分段点）。
class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint(this.lat, this.lon);
}

/// 一圈的计时结果。
class Lap {
  /// 圈号，从 1 开始。发车圈（第一次穿越起终点之前）不计圈，不产生 Lap。
  final int number;
  final int startMs;
  final int endMs;

  /// 圈速（ms，已扣除暂停时长，见 [pausedMs]）。
  final int durationMs;

  /// 本圈内因停车暂停而扣除的时长（ms）。
  final int pausedMs;

  /// 本圈内是否发生过停车超阈值停留。若为 true，本圈标注“停留不计圈”，
  /// 不进入最快圈、圈速榜与圈速稳定性统计（但仍保留在 [LapTimer.laps] 里备查）。
  final bool dwellNotCounted;

  /// 分段用时（ms）：
  /// - 若构造时给了 2 个分段点：[S1, S2, S3]，共 3 段；
  /// - 若无分段点：按圈时长中点切成 2 段 [前半圈, 后半圈]（见文件头与
  ///   [LapTimer] 注释：这是无分段点时的退化分段，不是真实 S1/S2 边界，
  ///   界面须标注“无分段点，前后半圈示意”）；
  /// - 若给了分段点但某段因 GPS 丢点未触发：缺失段不补数，sectors 长度
  ///   小于应有段数，调用方按实际长度显示，不得脑补。
  final List<int> sectorsMs;

  const Lap({
    required this.number,
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    required this.pausedMs,
    required this.dwellNotCounted,
    required this.sectorsMs,
  });

  /// 是否计入成绩（未停留的圈才计入）。
  bool get counted => !dwellNotCounted;

  Map<String, dynamic> toJson() => {
        'n': number,
        's': startMs,
        'e': endMs,
        'd': durationMs,
        'paused': pausedMs,
        'dwell': dwellNotCounted,
        'sec': sectorsMs,
      };

  static Lap fromJson(Map<String, dynamic> j) => Lap(
        number: (j['n'] as num).toInt(),
        startMs: (j['s'] as num).toInt(),
        endMs: (j['e'] as num).toInt(),
        durationMs: (j['d'] as num).toInt(),
        pausedMs: (j['paused'] as num?)?.toInt() ?? 0,
        dwellNotCounted: (j['dwell'] as bool?) ?? false,
        sectorsMs:
            ((j['sec'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
      );
}

/// 圈速稳定性指标：只统计计入成绩的圈（停留不计圈的圈排除在外）。
/// 圈数不足 2 圈时无意义，[LapTimer.stability] 返回 null。
class LapStability {
  /// 计入统计的圈数。
  final int count;

  /// 平均圈速（ms）。
  final double meanMs;

  /// 圈速标准差（ms，总体标准差）。
  final double stdDevMs;

  /// 极差（ms）= 最慢计入圈 - 最快计入圈。
  final double rangeMs;

  const LapStability({
    required this.count,
    required this.meanMs,
    required this.stdDevMs,
    required this.rangeMs,
  });
}

/// 圈速计时器：逐点喂入轨迹，实时输出当前圈 / 上一圈 / 最快圈 / Delta。
///
/// 判定阈值（全部可在构造时覆盖，下面的默认值就是接线默认值）：
/// - [crossingRadiusM] = 30 m：起终点穿越判定半径。1Hz 采样下高速通过
///   起终点时两点之间可能跨过 30 m 半径，因此判定不用“单点落入圆内”，
///   而用“上一轨迹点到当前轨迹点的线段到起终点的最短距离 < 半径”，
///   同一判定也用于分段点。
/// - [minLapMs] = 30_000 ms：最短圈间隔。穿越后 30 秒内的再次穿越视为
///   同一圈内的 GPS 抖动 / 掉头，不计圈；同时穿越后必须先离开起终点
///   2 倍半径（60 m）之外才重新获得穿越资格（防原地抖动连触发）。
/// - [dwellSpeedMs] = 0.5 m/s、[dwellThresholdMs] = 30_000 ms：速度持续
///   低于 0.5 m/s 满 30 秒即判定停车：计时自动暂停（暂停时长不计入圈速），
///   且本圈标注“停留不计圈”；速度回升到 0.5 m/s 及以上时自动恢复计时。
/// - 分段：构造时传 2 个分段点（S1 终点、S2 终点）得 S1/S2/S3；不传则
///   退化为按圈时长中点切两段，界面须标注“无分段点，前后半圈示意”。
class LapTimer {
  /// 起终点经纬度（调用方传入：赛道起终点或用户点选的起终点）。
  final GeoPoint startFinish;

  /// 起终点穿越判定半径（m），默认 30。
  final double crossingRadiusM;

  /// 最短圈间隔（ms），默认 30 秒。
  final int minLapMs;

  /// 停车判定速度阈值（m/s），默认 0.5。
  final double dwellSpeedMs;

  /// 停车判定持续时长（ms），默认 30 秒。
  final int dwellThresholdMs;

  /// 分段点：空 = 无分段点（退化两段）；1 个 = S1/S2 两段；
  /// 2 个 = S1/S2/S3 三段。多于 2 个只取前 2 个。
  final List<GeoPoint> sectorPoints;

  LapTimer({
    required this.startFinish,
    this.crossingRadiusM = 30,
    this.minLapMs = 30000,
    this.dwellSpeedMs = 0.5,
    this.dwellThresholdMs = 30000,
    List<GeoPoint> sectorPoints = const [],
  }) : sectorPoints = sectorPoints.take(2).toList();

  final List<Lap> _laps = [];
  final List<int> _pointLapNumbers = [];
  final List<bool> _sectorCrossed = [];

  TimedPoint? _prev;
  TimedPoint? _last;
  int? _lapStartMs;
  int _currentLapNumber = 0; // 0 = 发车圈（第一次穿越前），未开始计时
  bool _canCross = true;
  bool _paused = false;
  int? _pauseStartMs;
  int _pausedMsCurrentLap = 0;
  bool _dwellInCurrentLap = false;
  int? _lowSpeedSinceMs;
  final List<int> _sectorSplitElapsed = [];

  /// 已完成的所有圈（含停留不计圈的圈，调用方按 [Lap.counted] 过滤显示）。
  List<Lap> get laps => List.unmodifiable(_laps);

  /// 上一圈（最近完成的一圈，含停留不计圈的圈；成绩榜用 [leaderboard]）。
  Lap? get lastLap => _laps.isEmpty ? null : _laps.last;

  /// 最快圈：只在计入成绩的圈里取最快；无计入圈时为 null。
  Lap? get bestLap {
    final counted = _laps.where((l) => l.counted).toList();
    if (counted.isEmpty) return null;
    counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    return counted.first;
  }

  /// 圈速榜：计入成绩的圈按圈速从快到慢排（停留不计圈的圈不进榜）。
  List<Lap> get leaderboard {
    final counted = _laps.where((l) => l.counted).toList();
    counted.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    return counted;
  }

  /// 当前圈号：0 表示还在发车圈（未第一次穿越起终点），否则为进行中的圈号。
  int get currentLapNumber => _currentLapNumber;

  /// 是否因停车处于自动暂停中。
  bool get isPaused => _paused;

  /// 当前圈已用时长（ms，已扣除暂停时长）；未开始计时时为 null。
  int? get currentLapMs {
    final start = _lapStartMs;
    final last = _last;
    if (start == null || last == null) return null;
    return last.timeMs - start - _effectivePausedMs(last.timeMs);
  }

  /// 与最快圈的 Delta（ms）= 当前圈已用时长 - 最快圈圈速。
  /// 负值表示当前圈比最快圈更快；无最快圈或未开始计时时为 null。
  int? get currentDeltaMs {
    final cur = currentLapMs;
    final best = bestLap;
    if (cur == null || best == null) return null;
    return cur - best.durationMs;
  }

  /// 进行中圈已完成分段的各段用时（ms，已扣除暂停时长）：
  /// 由本圈已触发的分段点时刻差算出（第 i 段 = 第 i 个分段点时刻
  /// 减上一分段点时刻，首段减圈起点）；未开始计时、或尚未触发
  /// 任何分段点时为空列表。只读快照，不改动任何计时状态。
  /// 注意：无分段点（sectorPoints 为空）时进行中圈没有已完成
  /// 分段，本 getter 恒为空——前后半圈切分只在完圈时
  /// （[_buildSectors]）才能确定，不得在进行中把半圈当成
  /// 已完成分段去算 delta。
  List<int> get currentCompletedSectorsMs {
    if (_lapStartMs == null) return const [];
    final sectors = <int>[];
    var prevSplit = 0;
    for (final split in _sectorSplitElapsed) {
      sectors.add(split - prevSplit);
      prevSplit = split;
    }
    return sectors;
  }

  /// 进行中圈当前分段已用耗时（ms，已扣除暂停时长）：
  /// = 当前圈已用时长 - 已完成分段用时之和；未开始计时时为 null。
  /// 只读，不改动计时状态。
  int? get currentSectorElapsedMs {
    final cur = currentLapMs;
    if (cur == null) return null;
    var done = 0;
    for (final s in currentCompletedSectorsMs) {
      done += s;
    }
    return cur - done;
  }

  /// 进行中圈已完成分段相对本节最佳圈的 delta（ms）：
  /// 第 i 项 = 本圈第 i 段实测 - 最佳圈第 i 段；负 = 更快，正 = 更慢。
  /// 长度 = 已完成分段数；对应位置无参照数据时（无最佳圈，或
  /// 最佳圈没有该段——分段口径不一致时）该项为 null，不得拿
  /// 错位的段相减。只读，参照圈固定为 [bestLap]，调用方不得
  /// 在此改参照口径。
  List<int?> get currentSectorDeltasVsBest {
    final completed = currentCompletedSectorsMs;
    final best = bestLap;
    return List<int?>.generate(completed.length, (i) {
      if (best == null || i >= best.sectorsMs.length) return null;
      return completed[i] - best.sectorsMs[i];
    });
  }

  /// 预测圈（ms，参照圈默认本节最佳圈）：
  /// = 已完成分段实测之和 + 参照圈从当前分段起的各段用时。
  /// 等价于参照圈总圈速 + 已完成分段 delta 之和：当前分段按
  /// 参照圈 pace 投影，当前分段已用耗时不另加——若在
  /// [currentLapMs] 之外再加参照圈剩余段，会把当前分段算两次；
  /// 若只加当前分段之后的参照段，则等于默认当前分段立即结束，
  /// 会系统性低估。两种错误算法本 getter 一律不用。
  /// 返回 null 的情形（不编数）：未开始计时；无最佳圈；参照圈
  /// 无分段数据；参照圈分段数 <= 已完成分段数（无剩余分段可
  /// 投影，或分段口径不一致）。
  int? get predictedLapMsVsBest {
    if (currentLapMs == null) return null;
    final best = bestLap;
    if (best == null || best.sectorsMs.isEmpty) return null;
    final completed = currentCompletedSectorsMs;
    final k = completed.length;
    if (best.sectorsMs.length <= k) return null;
    var sum = 0;
    for (final s in completed) {
      sum += s;
    }
    for (var i = k; i < best.sectorsMs.length; i++) {
      sum += best.sectorsMs[i];
    }
    return sum;
  }

  /// 圈速稳定性（只统计计入圈）；计入圈不足 2 圈时为 null。
  LapStability? get stability {
    final ds =
        _laps.where((l) => l.counted).map((l) => l.durationMs.toDouble()).toList();
    if (ds.length < 2) return null;
    final mean = ds.reduce((a, b) => a + b) / ds.length;
    var sumSq = 0.0;
    for (final d in ds) {
      sumSq += (d - mean) * (d - mean);
    }
    final std = math.sqrt(sumSq / ds.length);
    final range = ds.reduce(math.max) - ds.reduce(math.min);
    return LapStability(
        count: ds.length, meanMs: mean, stdDevMs: std, rangeMs: range);
  }

  /// 逐点对应的圈号（与喂入点数一一对应）：
  /// 0 = 发车圈（第一次穿越前），N >= 1 = 第 N 圈。
  /// 供行程详情页按圈分段显示轨迹时分组用（见接线规格）。
  /// 穿越点本身归属新开始的一圈。
  List<int> get pointLapNumbers => List.unmodifiable(_pointLapNumbers);

  /// 喂入一个轨迹点（调用方按时间顺序喂，1Hz 即可）。
  void addPoint(TimedPoint p) {
    final prev = _prev;

    // 1) 停车 / 恢复判定（用当前点速度与时间戳；暂停时长在取值时统一扣除）。
    _updateDwell(p);

    // 2) 起终点穿越判定（线段距离法，防高速跨点漏判）。
    var crossed = false;
    if (prev != null) {
      crossed = _segmentDistanceM(prev, p, startFinish) < crossingRadiusM;
    } else {
      crossed = _distanceM(p, startFinish) < crossingRadiusM;
    }
    // 离开起终点 2 倍半径之外后，才重新获得穿越资格。
    if (_distanceM(p, startFinish) > crossingRadiusM * 2) {
      _canCross = true;
    }

    if (crossed && _canCross) {
      if (_lapStartMs == null) {
        // 第一次穿越：发车圈结束，开始第 1 圈计时。
        _startLap(p.timeMs, 1);
        _canCross = false;
      } else if (p.timeMs - _lapStartMs! >= minLapMs) {
        // 完成一圈，立即开始下一圈（穿越点归属新圈）。
        _closeLap(p.timeMs);
        _startLap(p.timeMs, _currentLapNumber + 1);
        _canCross = false;
      }
      // 30 秒内的再次穿越：忽略（GPS 抖动），不关闭、不重启。
    }

    // 3) 分段点穿越判定（同样线段距离法；每圈每段只记一次）。
    if (_lapStartMs != null && sectorPoints.isNotEmpty) {
      for (var i = 0; i < sectorPoints.length; i++) {
        if (_sectorCrossed[i]) continue;
        final hit = prev == null
            ? _distanceM(p, sectorPoints[i]) < crossingRadiusM
            : _segmentDistanceM(prev, p, sectorPoints[i]) < crossingRadiusM;
        if (hit) {
          _sectorCrossed[i] = true;
          _sectorSplitElapsed.add(
              p.timeMs - _lapStartMs! - _effectivePausedMs(p.timeMs));
        }
      }
    }

    // 4) 记录本点归属圈号与最新点。
    _pointLapNumbers.add(_currentLapNumber);
    _prev = p;
    _last = p;
  }

  void _startLap(int timeMs, int number) {
    _lapStartMs = timeMs;
    _currentLapNumber = number;
    _paused = false;
    _pauseStartMs = null;
    _pausedMsCurrentLap = 0;
    _dwellInCurrentLap = false;
    _lowSpeedSinceMs = null;
    _sectorSplitElapsed.clear();
    _sectorCrossed.clear();
    _sectorCrossed.addAll(List.filled(sectorPoints.length, false));
  }

  void _closeLap(int endMs) {
    final start = _lapStartMs;
    if (start == null) return;
    final paused = _effectivePausedMs(endMs);
    final duration = endMs - start - paused;
    final sectors = _buildSectors(duration);
    _laps.add(Lap(
      number: _currentLapNumber,
      startMs: start,
      endMs: endMs,
      durationMs: duration,
      pausedMs: paused,
      dwellNotCounted: _dwellInCurrentLap,
      sectorsMs: sectors,
    ));
  }

  List<int> _buildSectors(int duration) {
    if (sectorPoints.isEmpty) {
      // 无分段点退化分段：按圈时长中点切两段（前半圈 / 后半圈示意）。
      final half = duration ~/ 2;
      return [half, duration - half];
    }
    // 有分段点：分段用时 = 各分段点时刻 - 上一分段点时刻，末段补到圈终点。
    final sectors = <int>[];
    var prevSplit = 0;
    for (final split in _sectorSplitElapsed) {
      sectors.add(split - prevSplit);
      prevSplit = split;
    }
    sectors.add(duration - prevSplit);
    return sectors;
  }

  void _updateDwell(TimedPoint p) {
    if (_lapStartMs == null) {
      // 发车圈不做停车判定（发车格等待不应污染第一圈）。
      _lowSpeedSinceMs = null;
      return;
    }
    if (p.speed < dwellSpeedMs) {
      _lowSpeedSinceMs ??= p.timeMs;
      if (!_paused &&
          p.timeMs - _lowSpeedSinceMs! >= dwellThresholdMs) {
        // 停车超阈值：自动暂停计时，本圈标注停留不计圈。
        _paused = true;
        _pauseStartMs = p.timeMs;
        _dwellInCurrentLap = true;
      }
    } else {
      // 速度恢复：结束暂停，暂停时长计入扣除。
      if (_paused && _pauseStartMs != null) {
        _pausedMsCurrentLap += p.timeMs - _pauseStartMs!;
      }
      _paused = false;
      _pauseStartMs = null;
      _lowSpeedSinceMs = null;
    }
  }

  int _effectivePausedMs(int atMs) {
    var paused = _pausedMsCurrentLap;
    if (_paused && _pauseStartMs != null) {
      paused += atMs - _pauseStartMs!;
    }
    return paused;
  }

  /// 圈速格式化：m:ss.mmm；null 显示占位。
  static String formatLapTime(int? ms) {
    if (ms == null || ms < 0) return '--:--.---';
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// Delta 格式化：带正负号，负为更快，如 -0:01.234 / +0:02.500。
  static String formatDelta(int? ms) {
    if (ms == null) return '--';
    final sign = ms < 0 ? '-' : '+';
    return sign + formatLapTime(ms.abs());
  }
}

double _rad(double d) => d * math.pi / 180;

double _distanceM(TimedPoint p, GeoPoint g) {
  const r = 6371000.0;
  final dLat = _rad(g.lat - p.lat);
  final dLon = _rad(g.lon - p.lon);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(p.lat)) * math.cos(_rad(g.lat)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// 线段（上一轨迹点 -> 当前轨迹点）到目标点的最短距离（m）。
/// 用等距圆柱投影近似（赛道尺度下误差可忽略），避免高速跨点漏判。
double _segmentDistanceM(TimedPoint a, TimedPoint b, GeoPoint g) {
  final meanLat = _rad((a.lat + b.lat) / 2);
  final ax = 0.0;
  final ay = 0.0;
  final bx = (b.lon - a.lon) * math.cos(meanLat) * 111320;
  final by = (b.lat - a.lat) * 110540;
  final gx = (g.lon - a.lon) * math.cos(meanLat) * 111320;
  final gy = (g.lat - a.lat) * 110540;
  final dx = bx - ax;
  final dy = by - ay;
  final lenSq = dx * dx + dy * dy;
  double t = 0;
  if (lenSq > 0) {
    t = ((gx - ax) * dx + (gy - ay) * dy) / lenSq;
    t = t.clamp(0, 1);
  }
  final px = ax + t * dx;
  final py = ay + t * dy;
  return math.sqrt((gx - px) * (gx - px) + (gy - py) * (gy - py));
}
