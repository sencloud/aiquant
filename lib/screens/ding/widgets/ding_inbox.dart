import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ding.dart';
import '../../../state/ding_state.dart';
import '../../../theme/app_theme.dart';

/// 收件箱：按"同一任务"自动整合，只展示每个任务最新一条；
/// 同任务的历史消息折叠到二级列表，可以批量删除或单条删除。
class DingInbox extends StatelessWidget {
  const DingInbox({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<DingState>();
    final groups = _groupByTask(st.messages);

    if (groups.isEmpty) {
      return _Empty();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final g = groups[i];
        return _GroupTile(group: g);
      },
    );
  }

  /// 按 `taskId` 分组并保持"组内最新 → 组之间也按最新条时间"的排序。
  ///
  /// taskId 为空的兜底条（来自 server 直接派发、没有挂任务的通知）按消息 id 单独成组，
  /// 避免它们和正常任务的历史混到一起。
  static List<_MsgGroup> _groupByTask(List<DingMessage> all) {
    final map = <String, List<DingMessage>>{};
    final order = <String>[]; // 维持 first-seen 顺序，方便后面统一排序
    for (final m in all) {
      final key = m.taskId.isEmpty ? '__lone__:${m.id}' : m.taskId;
      final bucket = map[key];
      if (bucket == null) {
        map[key] = [m];
        order.add(key);
      } else {
        bucket.add(m);
      }
    }
    final groups = <_MsgGroup>[];
    for (final key in order) {
      final list = map[key]!
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      groups.add(_MsgGroup(taskId: key, items: list));
    }
    groups.sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));
    return groups;
  }
}

/// 一组同任务的消息：[items] 已按 createdAt 倒序，[latest] 是代表条。
class _MsgGroup {
  _MsgGroup({required this.taskId, required this.items});
  final String taskId;
  final List<DingMessage> items;
  DingMessage get latest => items.first;
  List<DingMessage> get history => items.skip(1).toList();
  int get unreadCount => items.where((m) => !m.read).length;
}

class _GroupTile extends StatefulWidget {
  const _GroupTile({required this.group});
  final _MsgGroup group;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  bool _open = false;
  bool _historyOpen = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final st = context.read<DingState>();
    if (!_open) {
      setState(() => _open = true);
      _ctl.forward(from: 0);
      if (!widget.group.latest.read) {
        await st.markRead(widget.group.latest);
      }
    } else {
      _ctl.reverse();
      setState(() {
        _open = false;
        _historyOpen = false;
      });
    }
  }

  Future<void> _confirmDeleteHistory() async {
    final history = widget.group.history;
    if (history.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: Text('确定要删除「${widget.group.latest.taskTitle}」'
            '折叠起来的 ${history.length} 条旧消息吗？最新这条会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await context.read<DingState>().deleteMessages(history);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n > 0 ? '已清理 $n 条历史消息' : '没有可删除的历史消息'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.group.latest;
    final df = DateFormat('MM-dd HH:mm');
    final unread = !m.read;
    final groupUnread = widget.group.unreadCount;
    final accent = m.hasError ? AppColors.danger : AppColors.amber;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              groupUnread > 0 ? accent.withValues(alpha: 0.7) : AppColors.borderDim,
          width: groupUnread > 0 ? 1.4 : 1,
        ),
        boxShadow: groupUnread > 0
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _toggle,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8), bottom: Radius.zero),
              child: _envelopeHeader(m, df, unread, accent),
            ),
            SizeTransition(
              sizeFactor:
                  CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic),
              axisAlignment: -1,
              child: FadeTransition(
                opacity: _ctl,
                child: _body(m),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _envelopeHeader(
      DingMessage m, DateFormat df, bool unread, Color accent) {
    final history = widget.group.history;
    final groupUnread = widget.group.unreadCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _ctl,
            builder: (_, __) {
              return SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      _open
                          ? Icons.drafts_outlined
                          : (m.hasError
                              ? Icons.report_gmailerrorred
                              : Icons.markunread),
                      size: 22,
                      color: accent,
                    ),
                    if (groupUnread > 0 && !_open)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppColors.bgRaised, width: 1),
                          ),
                          constraints: const BoxConstraints(minWidth: 12),
                          child: Text(
                            groupUnread > 9 ? '9+' : '$groupUnread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight:
                              unread ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(df.format(m.createdAt),
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _previewLine(m.content),
                  maxLines: _open ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.borderDim.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '同任务 ${widget.group.items.length} 条',
                          style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· 折叠 ${history.length} 条历史',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: const Duration(milliseconds: 280),
            child: Icon(Icons.expand_more,
                color: AppColors.textTertiary, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _body(DingMessage m) {
    final history = widget.group.history;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderDim)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _markdown(m.content),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('删除'),
                onPressed: () =>
                    context.read<DingState>().deleteMessage(m),
              ),
              TextButton.icon(
                icon: const Icon(Icons.mark_email_unread_outlined, size: 14),
                label: const Text('标为未读'),
                onPressed: () =>
                    context.read<DingState>().markRead(m, read: false),
              ),
            ],
          ),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderDim),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _historyOpen = !_historyOpen),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      child: Row(
                        children: [
                          Icon(Icons.history,
                              color: AppColors.textTertiary, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '历史 ${history.length} 条',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 0),
                              minimumSize: const Size(0, 28),
                              foregroundColor: AppColors.danger,
                            ),
                            icon: const Icon(Icons.delete_sweep_outlined,
                                size: 14),
                            label: const Text('清空历史'),
                            onPressed: _confirmDeleteHistory,
                          ),
                          AnimatedRotation(
                            turns: _historyOpen ? 0.5 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Icon(Icons.expand_more,
                                color: AppColors.textTertiary, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _historyOpen
                        ? Column(
                            children: [
                              for (final h in history)
                                _HistoryRow(message: h),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _markdown(String md) {
    return MarkdownBody(
      data: md,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
            color: AppColors.textPrimary, fontSize: 13, height: 1.55),
        h1: const TextStyle(
            color: AppColors.amber,
            fontSize: 16,
            fontWeight: FontWeight.w800),
        h2: const TextStyle(
            color: AppColors.amber,
            fontSize: 14,
            fontWeight: FontWeight.w800),
        h3: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800),
        listBullet:
            TextStyle(color: AppColors.textPrimary, fontSize: 13),
        code: TextStyle(
            backgroundColor: AppColors.bgBase,
            color: AppColors.amber,
            fontFamily: 'monospace',
            fontSize: 12),
        codeblockDecoration: BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.borderDim),
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.bgSurface,
          border: const Border(
            left: BorderSide(color: AppColors.amber, width: 3),
          ),
        ),
        tableHead: TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.w800),
      ),
    );
  }

  String _previewLine(String md) {
    final stripped = md
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[`*_>\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty ? '（暂无内容）' : stripped;
  }
}

/// 折叠区里的一条历史消息：标题 + 时间 + 单条删除；点开后展开内容。
class _HistoryRow extends StatefulWidget {
  const _HistoryRow({required this.message});
  final DingMessage message;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final df = DateFormat('MM-dd HH:mm');
    final unread = !m.read;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: AppColors.borderDim, height: 1),
        InkWell(
          onTap: () async {
            setState(() => _open = !_open);
            if (_open && !m.read) {
              await context.read<DingState>().markRead(m);
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: unread
                        ? (m.hasError ? AppColors.danger : AppColors.amber)
                        : AppColors.borderDim,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    df.format(m.createdAt),
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 14),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minHeight: 24, minWidth: 24),
                  onPressed: () =>
                      context.read<DingState>().deleteMessage(m),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(Icons.expand_more,
                      color: AppColors.textTertiary, size: 14),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
                  child: Text(
                    m.content,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.55),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('收件箱还是空的',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '在「任务」里新建一个定时任务，\n或在助理对话内点右上角的闹钟图标，让 AI 按时给你发结果。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
