import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/chat.dart';
import '../../state/chat_state.dart';
import '../../theme/app_theme.dart';

/// 桌面端常驻会话列表（替代移动端 SessionDrawer 抽屉）。
///
/// 视觉与桌面 Shell 统一：选中项琥珀左边条 + 柔和底色（同侧边栏导航），
/// 列表为空时给出轻量空态提示。
class DesktopSessionList extends StatelessWidget {
  const DesktopSessionList({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    return Container(
      color: AppColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('对话记录',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          letterSpacing: 0.8)),
                ),
                IconButton(
                  tooltip: '新建对话',
                  icon: const Icon(Icons.add,
                      size: 16, color: AppColors.amber),
                  onPressed: chat.streaming
                      ? null
                      : () => chat.newSession(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.borderDim),
          Expanded(
            child: chat.sessions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 30, color: AppColors.textTertiary),
                        const SizedBox(height: 10),
                        Text(
                          '暂无对话\n点右上 + 开新对话',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              height: 1.6),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: chat.sessions.length,
                    itemBuilder: (context, i) {
                      final s = chat.sessions[i];
                      final selected = s.id == chat.activeId;
                      return _DesktopSessionTile(
                          session: s, selected: selected);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSessionTile extends StatefulWidget {
  const _DesktopSessionTile({required this.session, required this.selected});

  final ChatSession session;
  final bool selected;

  @override
  State<_DesktopSessionTile> createState() => _DesktopSessionTileState();
}

class _DesktopSessionTileState extends State<_DesktopSessionTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatState>();
    final fmt = DateFormat('MM-dd HH:mm');
    final s = widget.session;
    final selected = widget.selected;

    final bg = selected
        ? AppColors.amber.withValues(alpha: 0.10)
        : _hovering
            ? AppColors.bgHover
            : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => chat.selectSession(s.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(
                    color: AppColors.amber.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 选中指示条（与侧边栏导航一致）
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 2.5,
                height: selected ? 28 : 0,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title.isEmpty ? '未命名' : s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.messages.length} 条 · ${fmt.format(s.updatedAt)}',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz,
                    size: 15,
                    color: _hovering || selected
                        ? AppColors.textSecondary
                        : AppColors.textTertiary),
                color: AppColors.bgRaised,
                onSelected: (v) async {
                  if (v == 'rename') {
                    final controller =
                        TextEditingController(text: s.title);
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
                      await chat.renameSession(s.id, next);
                    }
                  } else if (v == 'delete') {
                    await chat.deleteSession(s.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
