import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ding.dart';
import '../../../state/ding_state.dart';
import '../../../theme/app_theme.dart';

/// 收件箱：信封样式列表，点击展开有"邮件打开"动画 + 已读状态。
class DingInbox extends StatelessWidget {
  const DingInbox({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<DingState>();
    final list = st.messages;

    if (list.isEmpty) {
      return _Empty();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = list[i];
        return _EnvelopeTile(message: m);
      },
    );
  }
}

class _EnvelopeTile extends StatefulWidget {
  const _EnvelopeTile({required this.message});
  final DingMessage message;

  @override
  State<_EnvelopeTile> createState() => _EnvelopeTileState();
}

class _EnvelopeTileState extends State<_EnvelopeTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  bool _open = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final st = context.read<DingState>();
    if (!_open) {
      // 打开：信封翻盖动画 + 标记已读
      setState(() => _open = true);
      _ctl.forward(from: 0);
      if (!widget.message.read) {
        await st.markRead(widget.message);
      }
    } else {
      _ctl.reverse();
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final df = DateFormat('MM-dd HH:mm');
    final unread = !m.read;

    final accent = m.hasError ? AppColors.danger : AppColors.amber;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: unread ? accent.withValues(alpha: 0.7) : AppColors.borderDim,
          width: unread ? 1.4 : 1,
        ),
        boxShadow: unread
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
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _envelopeHeader(m, df, unread, accent),
              SizeTransition(
                sizeFactor: CurvedAnimation(
                    parent: _ctl, curve: Curves.easeOutCubic),
                axisAlignment: -1,
                child: FadeTransition(
                  opacity: _ctl,
                  child: _body(m),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _envelopeHeader(
      DingMessage m, DateFormat df, bool unread, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 信封图标 + 翻盖动画
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
                    if (unread && !_open)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.bgRaised, width: 1),
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
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderDim)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: m.content,
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
          ),
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
        ],
      ),
    );
  }

  String _previewLine(String md) {
    final stripped = md
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[`*_>\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped.isEmpty ? '（无内容）' : stripped;
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
            Text('暂无 DING 消息',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '到「任务」标签页新建一个定时任务，\n或在助理对话内点 +DING，把消息会议化推送过来。',
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
