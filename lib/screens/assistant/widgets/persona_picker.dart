import 'package:flutter/material.dart';

import '../../../models/persona.dart';
import '../../../theme/app_theme.dart';

/// 顶部 Persona 选择条（横向滚动 chip 列表）。
class PersonaPicker extends StatelessWidget {
  const PersonaPicker({
    super.key,
    required this.activeId,
    required this.onPick,
    this.disabled = false,
  });

  final String activeId;
  final ValueChanged<String> onPick;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: Personas.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final p = Personas.all[i];
          final isActive = p.id == activeId;
          return _PersonaChip(
            persona: p,
            active: isActive,
            disabled: disabled,
            onTap: () => onPick(p.id),
          );
        },
      ),
    );
  }
}

class _PersonaChip extends StatelessWidget {
  const _PersonaChip({
    required this.persona,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  final Persona persona;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final base = active ? persona.color : AppColors.bgRaised;
    final bg = disabled ? base.withValues(alpha: 0.4) : base;
    final fg = active ? Colors.white : AppColors.textPrimary;
    final borderColor =
        active ? persona.color : AppColors.borderDim;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(persona.icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                persona.displayName,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
