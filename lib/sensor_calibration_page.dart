import 'dart:async';

import 'package:flutter/material.dart';

import 'glass_button.dart';
import 'native.dart';
import 'recorder.dart';

/// v0.1.9 传感器校准页（设置页新增入口）。
///
/// 结论：有必要加，但不另造一套标定——理由：G 值、压弯、朝向都
/// 依赖手机固定姿态与 IMU 零偏，现有开始前标定只做了一次车头
/// 方向；长期漂移、换手机/换支架后需要重校。本页复用现有标定
/// 逻辑与存储（Recorder 本身的 calibrated / calibratedAtMs /
/// calibrationNote，以及本页新增的零偏记录字段，见 recorder.dart），
/// 不在设置页发明第二套 G 值计算；G 值计算仍只在 recorder.dart
/// 的 onSensor 里。
///
/// 三步向导：
/// ① 水平静置校零：手机水平静置 2 秒，取传感器流 ax/ay/az 均值
///    记为零偏（recordZeroBias），2 秒内无数据则明确报错、不编零；
/// ② 车头方向标定：复用现有 beginCalibration（直线行驶至 18 km/h
///    以上自动锁定），完成状态直接读 rec.calibrated，与记录页
///    大方块同一状态源，天然同步；
/// ③ 罗盘 8 字校准提示：只做提示与完成勾选（状态位
///    compassHintDone），不编造罗盘校准结果——系统罗盘校准
///    本身由系统完成，App 无法也不应伪造一个结果。
class SensorCalibrationPage extends StatefulWidget {
  final Recorder recorder;

  /// 车头标定启动回调（总协调传入：权限复查 + beginCalibration +
  /// startLocation + startSensors，与旧标定底部表同一流程）。
  final VoidCallback onStartHeadingCalibration;

  const SensorCalibrationPage({
    super.key,
    required this.recorder,
    required this.onStartHeadingCalibration,
  });

  @override
  State<SensorCalibrationPage> createState() => _SensorCalibrationPageState();
}

class _SensorCalibrationPageState extends State<SensorCalibrationPage> {
  int _step = 0;
  bool _zeroRunning = false;
  String? _zeroError;
  bool _compassDone = false;

  Recorder get _rec => widget.recorder;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_tick);
  }

  @override
  void dispose() {
    _rec.removeListener(_tick);
    super.dispose();
  }

  void _tick() => mounted ? setState(() {}) : null;

  /// ① 水平静置校零：先启动传感器，静置采样 2 秒取均值。
  Future<void> _runZero() async {
    setState(() {
      _zeroRunning = true;
      _zeroError = null;
    });
    try {
      await Native.startSensors();
    } catch (_) {
      // 传感器启动失败不直接判死刑：继续等 2 秒看流里有无数据。
    }
    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    StreamSubscription<Map<String, dynamic>>? sub;
    try {
      sub = Native.sensorStream.listen((e) {
        xs.add((e['ax'] as num?)?.toDouble() ?? 0);
        ys.add((e['ay'] as num?)?.toDouble() ?? 0);
        zs.add((e['az'] as num?)?.toDouble() ?? 0);
      }, onError: (_) {});
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      // 流订阅失败：下面按无数据处理，不编零偏。
    } finally {
      await sub?.cancel();
    }
    if (!mounted) return;
    if (xs.isEmpty) {
      setState(() {
        _zeroRunning = false;
        _zeroError = '未收到传感器数据：请确认手机传感器可用，重新静置后再试。';
      });
      return;
    }
    final mean = (List<double> v) => v.reduce((a, b) => a + b) / v.length;
    _rec.recordZeroBias(mean(xs), mean(ys), mean(zs));
    setState(() => _zeroRunning = false);
  }

  Widget _stepper() {
    const labels = ['水平静置校零', '车头方向标定', '罗盘 8 字提示'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const Expanded(child: Divider(color: Colors.white24)),
          Column(children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: i == _step
                  ? Theme.of(context).colorScheme.primary
                  : (i < _step ? Colors.green : Colors.white24),
              child: Text('${i + 1}',
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
            ),
            const SizedBox(height: 4),
            Text(labels[i], style: const TextStyle(fontSize: 11)),
          ]),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = _rec;
    return Scaffold(
      appBar: AppBar(
        leading: GlassButton.back(onPressed: () => Navigator.pop(context)),
        title: const Text('传感器校准'),
      ),
      body: AnimatedBuilder(
        animation: rec,
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _stepper(),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              const Text('第 1 步 · 水平静置校零',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '把手机水平放在支架或桌面上、保持静止，点“开始校零”后静置 2 秒。' '长期漂移或换手机 / 换支架后请重校。',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (rec.zeroBiasAtMs != null)
                Text(
                  '已校零：ax ${rec.zeroBiasAx!.toStringAsFixed(3)} · '
                  'ay ${rec.zeroBiasAy!.toStringAsFixed(3)} · '
                  'az ${rec.zeroBiasAz!.toStringAsFixed(3)} m/s²',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
              if (_zeroError != null) ...[
                const SizedBox(height: 8),
                Text(_zeroError!, style: const TextStyle(color: Colors.orange, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _zeroRunning ? null : _runZero,
                child: Text(_zeroRunning ? '采样中…请保持静止' : '开始校零（静置 2 秒）'),
              ),
            ],
            if (_step == 1) ...[
              const Text('第 2 步 · 车头方向标定',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '把手机固定在支架上，点“开始标定”后直线行驶至 18 km/h 以上，App 自动锁定车头方向。',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(rec.calibrationNote,
                  style: TextStyle(
                      color: rec.calibrated ? Colors.greenAccent : Colors.white,
                      fontSize: 13)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: rec.waitingCalibration ? null : widget.onStartHeadingCalibration,
                child: Text(rec.waitingCalibration ? '标定中…请直线行驶' : '开始标定'),
              ),
              if (rec.calibrated) ...[
                const SizedBox(height: 8),
                const Text('车头方向已锁定，可以继续下一步。',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
              ],
            ],
            if (_step == 2) ...[
              const Text('第 3 步 · 罗盘 8 字校准提示',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '拿起手机，在空中画“8”字摆动几次，帮助系统罗盘消除磁干扰。完成后勾选即可。',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _compassDone || rec.compassHintDone,
                title: const Text('我已完成 8 字摆动'),
                onChanged: (v) {
                  if (v == true) rec.markCompassHintDone();
                  setState(() => _compassDone = v ?? false);
                },
              ),
              if (rec.compassHintDone)
                const Text('8 字提示已完成。',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
            const SizedBox(height: 24),
            Row(children: [
              if (_step > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    child: const Text('上一步'),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (_step < 2) {
                      setState(() => _step++);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(_step < 2 ? '下一步' : '完成并返回'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
