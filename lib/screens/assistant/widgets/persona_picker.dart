import 'package:flutter/material.dart';

import '../../../models/persona.dart';
import '../../../theme/app_theme.dart';
import '../../../wx/wx_kit.dart';

/// 「换个助手」：底部弹层，列出全部 AI 助手（人设）。
///
/// 微信的聊天页没有「换个人聊」这回事 —— 一个会话就是一个人。我们这边一个
/// 助手是一个人设，所以换人设等于换一位助手：调用方会在会话已经有内容时
/// 新开一段对话，避免人设中途跳变。
Future<String?> showPersonaSheet(
  BuildContext context, {
  required String activeId,
  String topic = 'money',
}) {
  final social = topic == 'social';
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => _PersonaSheet(
      activeId: activeId,
      topic: topic,
      title: social ? '换一个人' : '换个助手',
    ),
  );
}

class _PersonaSheet extends StatelessWidget {
  const _PersonaSheet({
    required this.activeId,
    required this.topic,
    required this.title,
  });

  final String activeId;
  final String topic;
  final String title;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final personas = Personas.forTopic(topic);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: AppType.title)),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Divider(height: 0.5, color: AppColors.borderDim),
            Flexible(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: personas.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 68,
                  color: AppColors.borderDim,
                ),
                itemBuilder: (context, i) {
                  final p = personas[i];
                  return _PersonaTile(
                    persona: p,
                    selected: p.id == activeId,
                    onTap: () => Navigator.of(context).pop(p.id),
                  );
                },
              ),
            ),
          ],
        ),
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
      color: AppColors.bgSurface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: [
              WxAvatar(
                text: persona.displayName,
                icon: persona.icon,
                background: persona.color,
                size: 40,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(persona.displayName, style: AppType.body),
                    const SizedBox(height: 2),
                    Text(persona.title,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded,
                    size: 20, color: AppColors.amber),
            ],
          ),
        ),
      ),
    );
  }
}
