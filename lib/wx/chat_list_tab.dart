import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/persona.dart';
import '../models/resident.dart';
import '../screens/assistant/assistant_screen.dart';
import '../state/chat_state.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'character_portrait.dart';
import 'wx_kit.dart';

/// 「消息」页签：会话列表。
///
/// 微信的首屏就是这个：一行一个会话，最新的在上，左边方头像，右边时间，
/// 点一行进聊天页。这里没有未读角标 —— 对话是你主动发起的，没有「别人给你
/// 留言」这回事，不摆一个假的数字。
class WxChatListTab extends StatefulWidget {
  const WxChatListTab({super.key});

  @override
  State<WxChatListTab> createState() => _WxChatListTabState();
}

class _WxChatListTabState extends State<WxChatListTab> {
  final _query = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final all = chat.sessions;
    final sessions = _q.isEmpty
        ? all
        : all
            .where((s) =>
                s.title.toLowerCase().contains(_q.toLowerCase()) ||
                _preview(s, chat).toLowerCase().contains(_q.toLowerCase()))
            .toList(growable: false);

    return Column(
      children: [
        WxTopBar(
          title: '消息',
          actions: [
            IconButton(
              key: const ValueKey('chats-new'),
              tooltip: '发起新的对话',
              icon: const Icon(Icons.add_rounded, size: 26),
              color: AppColors.textPrimary,
              onPressed: () async {
                final s = await chat.newSession();
                if (!context.mounted) return;
                await openChatScreen(context, sessionId: s.id);
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
            hint: '搜索',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: Container(
            color: AppColors.bgSurface,
            child: sessions.isEmpty
                ? _empty(all.isEmpty)
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 76,
                      color: AppColors.borderDim,
                    ),
                    itemBuilder: (context, i) => _ChatRow(
                      key: ValueKey('chat-${sessions[i].id}'),
                      session: sessions[i],
                      preview: _preview(sessions[i], chat),
                      onTap: () =>
                          openChatScreen(context, sessionId: sessions[i].id),
                      onLongPress: () => _rowMenu(sessions[i], chat),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _empty(bool noSessions) {
    if (!noSessions) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
          child: Text(
            '搜索「$_q」没有结果。',
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    // 一台新设备上还没有任何对话：不摆一个假的会话，直接给一个入口。
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 34, color: AppColors.textTertiary),
            const SizedBox(height: AppSpace.md),
            Text('还没有对话',
                style: AppType.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.xs),
            Text('问行情、财报、资金流，或者让 AI 把一件事查清楚。',
                textAlign: TextAlign.center,
                style: AppType.caption
                    .copyWith(color: AppColors.textTertiary, height: 1.6)),
            const SizedBox(height: AppSpace.lg),
            WkPrimaryButton(
              label: '开始一段对话',
              icon: Icons.add_rounded,
              onPressed: () async {
                final chat = context.read<ChatState>();
                final s = await chat.newSession();
                if (!mounted) return;
                await openChatScreen(context, sessionId: s.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 列表里那一行灰字：谁在说 + 说了什么。会话是按「话题」分开的，所以
  /// 标题是这次话题，副文写清是跟哪位助手说的。
  String _preview(ChatSession s, ChatState chat) {
    final persona = Personas.byId(s.personaId, topic: s.topic);
    final who = persona.displayName;
    if (s.messages.isEmpty) return '$who：还没有说话';
    final last = s.messages.last;
    final text = last.role == 'assistant' && last.streaming
        ? '正在回答…'
        : last.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final body = text.isEmpty ? '[图片]' : text;
    return last.role == 'user' ? '你：$body' : '$who：$body';
  }

  Future<void> _rowMenu(ChatSession s, ChatState chat) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.sm),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('重命名', style: AppType.body),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: Text('删除这条对话',
                  style: AppType.body.copyWith(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      await chat.deleteSession(s.id);
      return;
    }
    final controller = TextEditingController(text: s.title);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppType.body,
          decoration: const InputDecoration(hintText: '这次聊的是什么'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (next != null && next.isNotEmpty) {
      await chat.renameSession(s.id, next);
    }
  }
}

/// 会话列表里的一行（微信式：方头像 / 主文 + 灰副文 / 右上时间）。
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    super.key,
    required this.session,
    required this.preview,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatSession session;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final persona = Personas.byId(session.personaId, topic: session.topic);
    final title = session.title.trim().isEmpty ? '新的对话' : session.title;
    final resident =
        session.topic == 'social' ? residentOf(session.personaId) : null;
    return Material(
      color: AppColors.bgSurface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, 10, AppSpace.gutter, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (resident != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CharacterPortrait(resident: resident),
                )
              else
                WxAvatar(
                  text: persona.displayName,
                  icon: persona.icon,
                  background: persona.color,
                ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                wxListTime(session.updatedAt),
                style: AppType.micro.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开聊天页。会话列表、通讯录、发现都从这里进。
Future<void> openChatScreen(
  BuildContext context, {
  String? sessionId,
  AssistantLaunch? launch,
}) async {
  final chat = context.read<ChatState>();
  if (sessionId != null) chat.selectSession(sessionId);
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => AssistantScreen(launch: launch),
  ));
}

/// 微信列表里的时间：今天给时刻，昨天给「昨天」，一周内给星期，更早给日期。
String wxListTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  String two(int v) => v.toString().padLeft(2, '0');
  if (diff <= 0) return '${two(t.hour)}:${two(t.minute)}';
  if (diff == 1) return '昨天';
  if (diff < 7) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${names[t.weekday - 1]}';
  }
  return '${t.year % 100}/${t.month}/${t.day}';
}
