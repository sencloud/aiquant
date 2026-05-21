import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 助理顶部统一的「下拉 tag」样式 — PersonaPicker / StrategyPicker 共用。
///
/// 左侧主题色 icon + 文案，右侧 ▼ 指示可点击展开。
class TopTagChip extends StatelessWidget {
  const TopTagChip({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.active = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool active;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final base = active ? accent.withValues(alpha: 0.14) : AppColors.bgRaised;
    final bg = disabled ? base.withValues(alpha: 0.4) : base;
    final borderColor = active ? accent : AppColors.borderDim;
    final fg = active ? accent : AppColors.textPrimary;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: active ? 1.2 : 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
