import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../models/chat.dart';
import '../../../theme/app_theme.dart';
import 'reasoning_block.dart';
import 'tool_call_card.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.allMessages,
    this.showReasoning = true,
  });

  final ChatMessage message;
  final List<ChatMessage> allMessages;
  final bool showReasoning;

  @override
  Widget build(BuildContext context) {
    // role=tool 不渲染独立气泡——结果会在所属 assistant 气泡里展示
    if (message.role == 'tool') {
      return const SizedBox.shrink();
    }

    final isUser = message.role == 'user';
    final hasReasoning =
        showReasoning && (message.reasoning?.isNotEmpty ?? false);
    final hasToolCalls =
        (message.toolCalls?.isNotEmpty ?? false);
    final hasContent = message.content.trim().isNotEmpty;

    final bg = isUser ? AppColors.amber : AppColors.bgRaised;
    final fg = isUser ? Colors.black : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasReasoning)
            ReasoningBlock(
              text: message.reasoning!,
              streaming: message.streaming && !hasContent,
            ),
          if (hasContent)
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.86,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: _content(context, fg),
            ),
          if (hasToolCalls)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.92,
              ),
              child: ToolCallList(
                calls: message.toolCalls!,
                findResult: _findToolResult,
              ),
            ),
          if (message.streaming && !hasReasoning && !hasContent && !hasToolCalls)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _TypingDots(),
            ),
        ],
      ),
    );
  }

  ChatMessage? _findToolResult(String toolCallId) {
    for (final m in allMessages) {
      if (m.role == 'tool' && m.toolCallId == toolCallId) return m;
    }
    return null;
  }

  Widget _content(BuildContext context, Color fg) {
    if (message.role == 'user') {
      return Text(
        message.content,
        style: TextStyle(color: fg, fontSize: 13, height: 1.4),
      );
    }
    return MarkdownBody(
      data: message.content.isEmpty ? '…' : message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: fg, fontSize: 13, height: 1.5),
        strong: TextStyle(color: fg, fontWeight: FontWeight.w800),
        listBullet: TextStyle(color: fg, fontSize: 13),
        h1: TextStyle(
            color: fg, fontWeight: FontWeight.w800, fontSize: 18),
        h2: TextStyle(
            color: fg, fontWeight: FontWeight.w800, fontSize: 16),
        h3: TextStyle(
            color: fg, fontWeight: FontWeight.w800, fontSize: 14),
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
        tableHead: TextStyle(color: fg, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final n = ((_c.value * 4).floor() % 4);
        return Text(
          '正在思考${'·' * n}',
          style: TextStyle(
              fontSize: 11, color: AppColors.textTertiary),
        );
      },
    );
  }
}
