import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/chat.dart';
import '../../../state/chat_state.dart';
import '../../../theme/app_theme.dart';

class SessionDrawer extends StatelessWidget {
  const SessionDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    return Drawer(
      backgroundColor: AppColors.bgSurface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('对话记录',
                        style: TextStyle(
                            color: AppColors.amber,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.8)),
                  ),
                  IconButton(
                    tooltip: '新建对话',
                    icon: const Icon(Icons.add, color: AppColors.amber),
                    onPressed: () {
                      chat.newSession();
                      Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderDim),
            Expanded(
              child: ListView.separated(
                itemCount: chat.sessions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.borderDim),
                itemBuilder: (context, i) {
                  final s = chat.sessions[i];
                  final selected = s.id == chat.activeId;
                  return _SessionTile(session: s, selected: selected);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.selected});

  final ChatSession session;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatState>();
    final fmt = DateFormat('MM-dd HH:mm');
    return Material(
      color: selected ? AppColors.bgRaised : Colors.transparent,
      child: InkWell(
        onTap: () {
          chat.selectSession(session.id);
          Navigator.of(context).maybePop();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title.isEmpty ? '未命名' : session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppColors.amber
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz,
                        size: 16, color: AppColors.textTertiary),
                    color: AppColors.bgRaised,
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final controller =
                            TextEditingController(text: session.title);
                        final next = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('重命名对话'),
                            content: TextField(controller: controller),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, controller.text.trim()),
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        );
                        if (next != null && next.isNotEmpty) {
                          await chat.renameSession(session.id, next);
                        }
                      } else if (v == 'delete') {
                        await chat.deleteSession(session.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${session.messages.length} 条 · ${fmt.format(session.updatedAt)}',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
