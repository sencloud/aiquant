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
    // 和输入框上方那排快捷 pill 保持同一套语言：白底、无描边、极轻投影。
    // 选中态只靠主色字 + 主色图标表达 —— 加底色会让它在一排白 pill 里显得
    // 像"另一个控件"，反而乱。
    final base = AppColors.bgSurface;
    final bg = disabled ? base.withValues(alpha: 0.5) : base;
    final fg = disabled
        ? AppColors.textTertiary
        : (active ? AppColors.amberDim : AppColors.textPrimary);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      shadowColor: AppColors.shadow,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, 6, AppSpace.sm, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppType.caption.copyWith(color: fg),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
