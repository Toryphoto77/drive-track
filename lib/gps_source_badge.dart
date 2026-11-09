import 'package:flutter/material.dart';

/// 记录页 GPS 来源徽标（v1.2.16 A 路）。
///
/// 只做来源展示：不改接管/回落逻辑，不改计时判定与圈速口径，
/// 不改设备中心；G 值与姿态仍是手机传感器，不因外接改口径。
///
/// 两种态（调用方每帧按实时状态传参，徽标本身不缓存状态）：
/// - 外接接通：绿色边框 + 绿点，`外接 GPS · [设备名 · ]25Hz · N 颗星`
///   （设备名没有时省略，绝不编一个名字；频率/星数无数据时该段省略，
///   不拿 0 冒充）；
/// - 手机 GPS（含已回落）：灰色边框 + 灰点，`手机 GPS · 1Hz`。
/// 回落瞬间调用方须把 [externalActive] 置 false（见 main.dart
/// `_buildRecording`：`_blediyActive && !shouldFallbackToPhoneGps()`），
/// 徽标绿变灰，不得在已回落时仍显示外接。
/// 点按弹 [showDialog] 详情，不用底部 SnackBar。
const Color _kFerrariRed = Color(0xFFE10600);

class GpsSourceBadge extends StatelessWidget {
  const GpsSourceBadge({
    super.key,
    required this.externalActive,
    this.deviceName,
    this.hz,
    this.satelliteCount,
    this.accuracyM,
    this.fallingBack = false,
  });

  /// 生效中的外接 GPS（已排除回落态）。
  final bool externalActive;

  /// 已连外接设备名；状态里没有现成的名字映射时传 null，徽标省略该段。
  final String? deviceName;

  /// 外接输出频率（Hz，近 1 秒定位周期数）；手机态不使用。
  final double? hz;

  /// 卫星数：外接态为 GGA 卫星数（GSA 参与解算数兜底），
  /// 手机态为手机 GNSS 可见星数；无数据时 null。
  final int? satelliteCount;

  /// 定位精度（米）；无数据时 null（调用方把 rec.curHAcc >= 999 转 null）。
  final double? accuracyM;

  /// 是否正在回落手机 GPS（曾接外接、现已超时/断线）。
  final bool fallingBack;

  /// 徽标文案（纯函数，便于测试与详情复用同一口径）。
  String get label {
    final acc = (accuracyM != null && accuracyM! > 0 && accuracyM! < 999)
        ? '${accuracyM!.toStringAsFixed(0)} m'
        : null;
    if (!externalActive) {
      final parts = <String>['手机 GPS', '1Hz'];
      if (acc != null) parts.add(acc);
      return parts.join(' · ');
    }
    final parts = <String>['外接 GPS'];
    final name = deviceName?.trim();
    if (name != null && name.isNotEmpty) parts.add(name);
    if (hz != null && hz! > 0) parts.add('${hz!.toStringAsFixed(0)}Hz');
    if (satelliteCount != null) parts.add('$satelliteCount 颗星');
    if (acc != null) parts.add(acc);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        externalActive ? Colors.greenAccent : Colors.white.withValues(alpha: 0.24);
    final dotColor = externalActive ? Colors.greenAccent : Colors.white54;
    // 触摸目标 44px：外层 SizedBox 高 44，视觉药丸高 32 居中。
    return SizedBox(
      height: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => showGpsSourceDetails(context, badge: this),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.satellite_alt,
                      size: 16, color: _kFerrariRed),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: dotColor),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹出 GPS 来源详情对话框（showDialog，不用 SnackBar）。
Future<void> showGpsSourceDetails(BuildContext context,
    {required GpsSourceBadge badge}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF141414),
      title: const Text('GPS 来源', style: TextStyle(color: Colors.white)),
      content: GpsSourceDetails(badge: badge),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭', style: TextStyle(color: _kFerrariRed)),
        ),
      ],
    ),
  );
}

/// 详情内容：设备名、频率、卫星数、定位精度、是否正在回落手机 GPS。
/// 无数据项一律显示“—”，绝不编数。
class GpsSourceDetails extends StatelessWidget {
  const GpsSourceDetails({super.key, required this.badge});

  final GpsSourceBadge badge;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 13);
    const valueStyle = TextStyle(color: Colors.white, fontSize: 13);
    final name = badge.deviceName?.trim();
    final rows = <(String, String)>[
      ('来源', badge.externalActive ? '外接 GPS' : '手机 GPS'),
      ('设备', (name != null && name.isNotEmpty) ? name : '—'),
      (
        '频率',
        badge.externalActive
            ? (badge.hz != null && badge.hz! > 0
                ? '${badge.hz!.toStringAsFixed(0)}Hz'
                : '—')
            : '1Hz',
      ),
      (
        '卫星数',
        badge.satelliteCount != null ? '${badge.satelliteCount} 颗' : '—',
      ),
      (
        '定位精度',
        badge.accuracyM != null
            ? '${badge.accuracyM!.toStringAsFixed(0)} m'
            : '—',
      ),
      ('正在回落手机 GPS', badge.fallingBack ? '是' : '否'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(value,
                      style: valueStyle, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
