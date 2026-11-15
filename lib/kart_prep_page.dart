import 'package:flutter/material.dart';

import 'gps_source.dart';

/// v1.5.7 卡丁车准备页。
///
/// 卡丁车固定走赛道模式且必须先连硬件（门槛在入口处已校验，这里只做
/// 上车前的最后一次确认）。页面不提供开录，只负责：确认硬件、说明手机
/// 放置、选赛道；开录仍回记录页完成，避免出现第二套录制流程。
class KartPrepPage extends StatelessWidget {
  /// 选赛道：由记录页拉起赛道选择弹层（复用现有赛道包选择逻辑）。
  final VoidCallback onPickTrack;

  /// 去连接设备：跳设备中心。
  final VoidCallback onConnectDevice;

  const KartPrepPage({
    super.key,
    required this.onPickTrack,
    required this.onConnectDevice,
  });

  static const _bg = Color(0xFF121212);
  static const _card = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2A2A2A);
  static const _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 20),
                ),
                const Text('卡丁车准备',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            _hardwareCard(context),
            const SizedBox(height: 12),
            _placementCard(),
            const SizedBox(height: 12),
            _trackCard(),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _red),
                onPressed: onPickTrack,
                icon: const Icon(Icons.flag, size: 18),
                label: const Text('选择赛道',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hardwareCard(BuildContext context) {
    return ValueListenableBuilder<ExternalGpsStatus>(
      valueListenable: externalGpsStatus,
      builder: (context, st, _) {
        final ready = st.hardwareReady;
        final fixText = !st.connected
            ? '未连接'
            : st.binaryOnly
                ? '二进制协议，暂不能用于计时'
                : st.lastFixAtMs <= 0
                    ? '已连接，等待定位'
                    : '定位正常';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ready ? _red : _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(ready ? Icons.check_circle : Icons.error_outline,
                      color: ready ? const Color(0xFF22C55E) : _red, size: 18),
                  const SizedBox(width: 8),
                  const Text('定位硬件',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(ready ? '已就绪' : '未就绪',
                      style: TextStyle(
                          color: ready ? const Color(0xFF22C55E) : _red,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              _kv('设备', st.deviceName.isEmpty ? '—' : st.deviceName),
              _kv('状态', fixText),
              _kv(
                '采样率',
                st.sampleRateHz <= 0
                    ? '—'
                    : '${st.sampleRateHz.toStringAsFixed(0)} Hz',
              ),
              if (!ready) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: _red),
                    ),
                    onPressed: onConnectDevice,
                    child: const Text('去连接设备'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _placementCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('手机放哪',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _bullet('手机只做显示与记录，可以放在身上或场边，不必固定在车上。'),
          _bullet('与硬件保持在 10 米以内，避免金属和人体大面积遮挡。'),
          _bullet('不要夹在方向盘或车架附近，震动会损伤接口且遮挡视线。'),
          const SizedBox(height: 6),
          const Text('计时和圈速均来自外接硬件定位，手机是否随身不影响精度。',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  Widget _trackCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('赛道',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('选择卡丁场赛道包后，撞线点与分段就绪，回到记录页即可开始计时。',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('短赛道分段不足时，Delta 会显示 --，以圈速为准。',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(k,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: SizedBox(
              width: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: _red, shape: BoxShape.circle),
              ),
            ),
          ),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
