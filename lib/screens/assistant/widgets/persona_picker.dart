import 'package:flutter/material.dart';

import '../../../models/persona.dart';
import '../../../theme/app_theme.dart';
import 'top_tag_chip.dart';

/// 顶部「角色」入口：紧凑下拉 tag，显示当前选中的 persona。
///
/// 点击后弹底部表，列出全部 persona 卡片，用户选中后回调切换。
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

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PersonaSheet(activeId: activeId),
    );
    if (picked != null && picked != activeId) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = Personas.byId(activeId);
    return TopTagChip(
      icon: active.icon,
      label: active.displayName,
      accent: active.color,
      active: true,
      disabled: disabled,
      onTap: () => _openSheet(context),
    );
  }
}

class _PersonaSheet extends StatelessWidget {
  const _PersonaSheet({required this.activeId});

  final String activeId;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.78),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(
            icon: Icons.person_outline,
            title: '选择 AI 角色',
            subtitle: '切换会基于当前会话状态自动新建对话，避免人设跳变。',
          ),
          Divider(height: 1, color: AppColors.borderDim),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              itemCount: Personas.all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = Personas.all[i];
                final selected = p.id == activeId;
                return _PersonaTile(
                  persona: p,
                  selected: selected,
                  onTap: () => Navigator.of(context).pop(p.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({
    required this.persona,
    required this.selected,
    required this.onTap,
  });

  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? persona.color.withValues(alpha: 0.12)
          : AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? persona.color : AppColors.borderDim,
          width: selected ? 1.2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
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
                  color: persona.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(persona.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.displayName,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      persona.title,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: persona.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// BottomSheet 通用头部（图标 + 标题 + 一行小字）。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close, size: 18, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
