import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/require_login.dart';
import '../screens/settings/invite_credits_screen.dart';
import '../state/chat_state.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'chat_list_tab.dart';
import 'circles.dart';
import 'wx_kit.dart';

/// 「圈子」页签：一个圈子一行，点一行进去看它的助手。
///
/// 这一页取代了上一版的「通讯录」：微信的通讯录装的是人，这里装的是圈子，
/// 圈子里住的是 AI 助手（研究助理、巴菲特、手冲咖啡师……）。
/// **圈子不是主题**：进圈不换皮，圈色只落在圈徽和头像上。
class WxCirclesTab extends StatefulWidget {
  const WxCirclesTab({super.key});

  @override
  State<WxCirclesTab> createState() => _WxCirclesTabState();
}

class _WxCirclesTabState extends State<WxCirclesTab> {
  final _query = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final circles = q.isEmpty
        ? kCircles
        : kCircles
            .where((c) =>
                c.name.contains(q) ||
                c.blurb.contains(q) ||
                c.personas.any((p) => p.displayName.contains(q)))
            .toList(growable: false);

    return Column(
      children: [
        WxTopBar(
          title: '圈子',
          actions: [
            IconButton(
              key: const ValueKey('circles-invite'),
              tooltip: '邀请好友',
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 24),
              color: AppColors.textPrimary,
              onPressed: () async {
                if (!await requireLogin(context)) return;
                if (!context.mounted) return;
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const InviteCreditsScreen()));
              },
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, 0, AppSpace.md, AppSpace.sm),
          child: WxSearchBar(
            controller: _query,
            hint: '搜索圈子',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.md, 0, AppSpace.md, AppSpace.xxl),
            children: [
              WkGroup(
                children: [
                  WkRow(
                    key: const ValueKey('circles-new-friends'),
                    leading: const WxIconTile(
                      icon: Icons.person_add_alt_1_rounded,
                      color: Color(0xFFFA9D3B),
                    ),
                    title: '新的朋友',
                    subtitle: '邀请好友，填码双方各得 100 喜点',
                    onTap: () async {
                      if (!await requireLogin(context)) return;
                      if (!context.mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const InviteCreditsScreen()));
                    },
                  ),
                ],
              ),
              if (circles.isEmpty)
                const WkNote(text: '没有找到这个圈子。')
              else
                WkGroup(
                  children: [
                    for (final c in circles)
                      WkRow(
                        key: ValueKey('circle-${c.id}'),
                        leading: WxAvatar(
                          text: c.mark,
                          background: c.color,
                          size: 40,
                        ),
                        title: c.name,
                        subtitle: '${c.blurb} · ${c.personaIds.length} 位助手',
                        trailing:
                            c.id == 'money' ? const WkTag('主圈') : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => CircleScreen(circle: c)),
                        ),
                      ),
                  ],
                ),
              const WkNote(
                text: '圈子里的助手都是 AI：人设与提示词在「喜爱」这一侧维护，'
                    '不是真人，也不会读你的通讯录。进圈不换皮 —— 圈色只落在圈徽和头像上。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一个圈子的二级页：这屋里的助手，点谁就用谁开一段新对话。
class CircleScreen extends StatelessWidget {
  const CircleScreen({super.key, required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context) {
    final personas = circle.personas;
    return WkPage(
      title: circle.name,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          Row(
            children: [
              WxAvatar(text: circle.mark, background: circle.color, size: 56),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(circle.name, style: AppType.title.copyWith(fontSize: 20)),
                    const SizedBox(height: AppSpace.xs),
                    Text(circle.blurb,
                        style: AppType.caption
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          WkGroup(
            header: '${personas.length} 位 AI 助手',
            children: [
              for (final p in personas)
                WkRow(
                  key: ValueKey('circle-persona-${p.id}'),
                  leading: WxAvatar(
                    text: p.displayName,
                    icon: p.icon,
                    background: p.color,
                    size: 40,
                  ),
                  title: p.displayName,
                  subtitle: p.title,
                  trailing: const WkTag('AI'),
                  onTap: () => openCircleChat(context, circle, personaId: p.id),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          WkPrimaryButton(
            key: const ValueKey('circle-start'),
            label: '和${circle.defaultPersona.displayName}聊一句',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () => openCircleChat(context, circle),
          ),
          const SizedBox(height: AppSpace.md),
          const WkNote(
            text: '对话按话题走：这个圈里说的话会带着圈的名字，人设 prompt 在服务端，'
                '换个助手就是换一段对话。',
          ),
        ],
      ),
    );
  }
}

/// 进圈说话：用这个圈的默认助手（或指定助手）新开一段对话。
Future<void> openCircleChat(
  BuildContext context,
  Circle circle, {
  String? personaId,
}) async {
  final chat = context.read<ChatState>();
  final session = await chat.newSession(
    topic: circle.id,
    personaId: personaId ?? circle.defaultPersona.id,
    title: circle.name,
  );
  if (!context.mounted) return;
  await openChatScreen(context, sessionId: session.id);
}

