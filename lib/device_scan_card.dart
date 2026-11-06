import 'package:flutter/material.dart';

/// 设备中心共用扫描卡片（v1.2.12）：运动相机页与外接 GPS 页共用一套。
///
/// 样式（两页一致，不许各改各的）：
/// - 深色 #121212 页面底（各页 Scaffold 自带），卡片底 #0B0E13、圆角 16、
///   白 12% 描边；法拉利红 #E10600 点缀（图标圆圈、波纹、进度环）。
/// - 字号层级：卡片标题 18 加粗白、说明 12 白 70 居中、状态行 12 白 54 居中、
///   列表头 15 加粗白、行标题 14 加粗白、行说明 12 白 70、行元信息 11 白 54。
/// - 动画节奏：扫描动画固定 132px、1800ms 一圈、三环波纹（见
///   [DeviceScanRipple]，原相机页 _ScanRipple 原样抽出，不改节奏）。
///
/// 三种状态（卡片 + 行共用同一套呈现）：
/// - 空态：静态红圈图标 + [statusLine]（如“尚未扫描…”），列表区给空态文案，
///   不出现假的已连接 / 假设备。
/// - 扫描中：[DeviceScanRipple]（转圈 + 波纹）+ 扫描中状态行，按钮变“停止…”。
/// - 已连接：行卡片描边变绿、行内文案变“已连接”，连接详情（定位 / 电量）
///   由各页在卡片下方的已连接面板里另行展示，本组件不编造。
///
/// 本文件只管外衣：扫描 / 连接逻辑一律不动，各页把自己的状态与回调传进来。

/// 扫描动画：转圈 + 三环波纹（扫描中才播放）。
/// 原相机页 _ScanRipple 原样抽出：132px、1800ms、三环依次外扩淡出，
/// 中央 56px 红圈图标 + 一圈 CircularProgressIndicator。
class DeviceScanRipple extends StatefulWidget {
  const DeviceScanRipple({super.key, required this.icon});

  final IconData icon;

  @override
  State<DeviceScanRipple> createState() => _DeviceScanRippleState();
}

class _DeviceScanRippleState extends State<DeviceScanRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 132.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Builder(builder: (context) {
                      final progress = (_ctrl.value + i / 3) % 1.0;
                      final ringSize = size * (0.35 + 0.65 * progress);
                      return Container(
                        width: ringSize,
                        height: ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE10600)
                                .withValues(alpha: 0.55 * (1 - progress)),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE10600).withValues(alpha: 0.15),
              border: Border.all(
                color: const Color(0xFFE10600),
                width: 2,
              ),
            ),
            child: Icon(
              widget.icon,
              color: const Color(0xFFE10600),
              size: 28,
            ),
          ),
          const SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFE10600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫描入口大卡片：标题 + 说明 + 扫描按钮 + 状态行（+ 可选脚注 / 权限提示）。
/// 空态与扫描中只换中间图标（静态红圈 ↔ [DeviceScanRipple]），其余不动。
class DeviceScanCard extends StatelessWidget {
  const DeviceScanCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.scanning,
    required this.scanLabel,
    required this.stopLabel,
    required this.onScanToggle,
    required this.statusLine,
    this.scanButtonIcon,
    this.footnote,
    this.permNotice,
    this.onOpenSettings,
  });

  final String title;
  final String description;
  final IconData icon;

  /// 扫描中：中间换波纹动画，按钮变停止态。
  final bool scanning;

  /// 未扫描时按钮文案（如“扫描相机”）；扫描中按钮文案（如“停止扫描”）。
  final String scanLabel;
  final String stopLabel;
  final VoidCallback onScanToggle;

  /// 卡片底部状态行：空态 / 扫描中 / 扫描结果摘要，各页自己算好传进来。
  final String statusLine;

  /// 未扫描时扫描按钮的图标（默认用 [icon]）；扫描中固定为停止图标。
  final IconData? scanButtonIcon;

  /// 卡片底部小字脚注，可空。
  final String? footnote;

  /// 权限未授予时的提示（与“去系统设置”按钮一起出现），可空。
  final String? permNotice;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          if (scanning)
            DeviceScanRipple(icon: icon)
          else
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE10600).withValues(alpha: 0.15),
                border: Border.all(
                  color: const Color(0xFFE10600),
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFE10600),
                size: 28,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScanToggle,
              icon: Icon(
                scanning ? Icons.stop : (scanButtonIcon ?? icon),
                size: 18,
              ),
              label: Text(scanning ? stopLabel : scanLabel),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusLine,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Text(
              footnote!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          if (permNotice != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    permNotice!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (onOpenSettings != null)
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('去系统设置'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 搜到的设备行卡片：相机页与 GPS 页共用同一套行样式。
/// - 标题 14 加粗白 + 右上角徽标（连接方式 / 通道，警告色为琥珀底、
///   其余为主题 primary 20% 底）；说明 12 白 70；元信息 11 白 54。
/// - 连接中：16px 转圈 + [connectingLabel]；已连接：绿字“已连接”、
///   卡片描边变绿；其余：[actionLabel]（如“点行连接”）。
class DeviceScanRow extends StatelessWidget {
  const DeviceScanRow({
    super.key,
    required this.title,
    required this.badgeLabel,
    required this.detail,
    required this.meta,
    required this.actionLabel,
    required this.onTap,
    this.badgeIsWarning = false,
    this.isConnecting = false,
    this.isConnected = false,
    this.connectingLabel = '连接中…',
  });

  final String title;
  final String badgeLabel;

  /// 徽标是否用琥珀警告底（向导连接类）；false 用主题 primary 底。
  final bool badgeIsWarning;
  final String detail;
  final String meta;
  final String actionLabel;
  final VoidCallback onTap;
  final bool isConnecting;
  final bool isConnected;

  /// 连接中文案：相机页用“连接中…”，GPS 页沿用旧文案“连接中”。
  final String connectingLabel;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? Colors.greenAccent : Colors.white12,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeIsWarning
                          ? Colors.amber.withValues(alpha: 0.2)
                          : accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                meta,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (isConnecting)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          connectingLabel,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    )
                  else if (isConnected)
                    const Text(
                      '已连接',
                      style: TextStyle(color: Colors.greenAccent),
                    )
                  else
                    Text(
                      actionLabel,
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
