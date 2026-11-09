import 'package:flutter/material.dart';

import 'card_style.dart';

/// 空态 HUD 卡：图标 + 一行状态 + 一个主操作。
class EmptyHud extends StatelessWidget {
  const EmptyHud({
    super.key,
    required this.icon,
    required this.status,
    required this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String status;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final accent = CardStyle.accent(context);
    return DriveTrackCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: accent),
          const SizedBox(height: 8),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
