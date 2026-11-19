import 'package:flutter/material.dart';

import 'app_locale.dart';

/// 设备中心共用扫描组件（v1.2.12 抽出，v1.7.x 极简化）。
/// 运动相机页与外接 GPS 页共用一套（两页一致，不许各改各的）。
///
/// v1.7.x 按参考图收敛为极简样式：
/// - 扫描条：左侧小图标 / 波纹 + 一行状态文字 + 右侧「扫描 / 停止」文字按钮，
///   不再有 56px 大红圈、大标题说明和整宽大按钮。
/// - 设备行：左侧红色圆角图标 + 名称 + 一行副信息（信号 / 地址）+ 右侧一个
///   动作按钮（实心「连接」/ 描边「配对」/ 灰色「已连接」）。
/// - 扫描 / 连接逻辑一律不动，各页把自己的状态与回调传进来。

const Color _kRed = Color(0xFFE10600);

/// 扫描动画：转圈 + 三环波纹（扫描中才播放）。
/// 默认 132px；卡片内用 [size] 收小到 36px，保持极简。
class DeviceScanRipple extends StatefulWidget {
  const DeviceScanRipple({super.key, required this.icon, this.size = 132});

  final IconData icon;
  final double size;

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
    final size = widget.size;
    final core = size * 0.42;
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
                            color: _kRed.withValues(alpha: 0.55 * (1 - progress)),
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
            width: core,
            height: core,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kRed.withValues(alpha: 0.15),
              border: Border.all(color: _kRed, width: 2),
            ),
            child: Icon(widget.icon, color: _kRed, size: core * 0.5),
          ),
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: _kRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// 扫描条（极简）：标题 + 一行状态 + 扫描/停止，可选脚注与权限提示。
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

  /// 扫描中：左侧换成波纹动画，按钮变停止态。
  final bool scanning;

  final String scanLabel;
  final String stopLabel;
  final VoidCallback onScanToggle;

  /// 一行状态文字：空态 / 扫描中 / 扫描结果摘要，各页自己算好传进来。
  final String statusLine;

  /// 未扫描时扫描按钮的图标（保留参数以兼容既有调用；极简样式下不再显示）。
  final IconData? scanButtonIcon;

  /// 卡片底部小字脚注，可空。
  final String? footnote;

  /// 权限未授予时的提示（与“去系统设置”按钮一起出现），可空。
  final String? permNotice;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: scanning
                    ? DeviceScanRipple(icon: icon, size: 36)
                    : Container(
                        decoration: BoxDecoration(
                          color: _kRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: _kRed, size: 20),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: onScanToggle,
                style: TextButton.styleFrom(
                  foregroundColor: scanning ? Colors.white70 : _kRed,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(scanning ? stopLabel : scanLabel),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 46, right: 6),
              child: Text(
                footnote!,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
          if (permNotice != null) ...[
            const SizedBox(height: 6),
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
                    child: Text(S.of(context).t('去系统设置', 'System settings')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 搜到的设备行（极简）：左侧红图标 + 名称 + 一行副信息 + 右侧动作按钮。
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
    this.actionIsOutline = false,
    this.icon = Icons.bluetooth,
  });

  final String title;
  final String badgeLabel;

  /// 徽标是否用琥珀警告底（向导连接类）；保留以兼容调用方。
  final bool badgeIsWarning;
  final String detail;
  final String meta;
  final String actionLabel;
  final VoidCallback onTap;
  final bool isConnecting;
  final bool isConnected;

  /// 连接中文案：相机页用“连接中…”，GPS 页沿用旧文案“连接中”。
  final String connectingLabel;

  /// 动作按钮是否描边样式（配对类用描边，连接类用实心）。
  final bool actionIsOutline;

  /// 设备类型图标（默认蓝牙）。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final subtitle = meta.isNotEmpty ? meta : detail;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _kRed, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      badgeLabel.isEmpty
                          ? subtitle
                          : '$badgeLabel · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _action(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(S s) {
    if (isConnecting) {
      return Row(
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
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      );
    }
    if (isConnected) {
      return Text(
        s.t('已连接', 'Connected'),
        style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
      );
    }
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: actionIsOutline ? _kRed : Colors.white,
      backgroundColor: actionIsOutline ? null : _kRed,
      side: actionIsOutline ? const BorderSide(color: _kRed) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
    return TextButton(
      onPressed: onTap,
      style: style,
      child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// 底部提示：找不到设备时的说明（参考图样式），两页共用。
class DeviceScanHint extends StatelessWidget {
  const DeviceScanHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );
  }
}
