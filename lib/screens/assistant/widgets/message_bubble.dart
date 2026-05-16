import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../models/chat.dart';
import '../../../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showReasoning = true,
  });

  final ChatMessage message;
  final bool showReasoning;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final hasReasoning =
        showReasoning && (message.reasoning?.isNotEmpty ?? false);

    final bg = isUser ? AppColors.amber : AppColors.bgRaised;
    final fg = isUser ? Colors.black : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasReasoning) _reasoningBlock(message.reasoning!),
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
          if (message.streaming)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _TypingDots(),
            ),
        ],
      ),
    );
  }

  Widget _reasoningBlock(String txt) => Container(
        margin: const EdgeInsets.only(bottom: 6, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          border: Border.all(color: AppColors.borderDim),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.psychology_outlined,
                  size: 12, color: AppColors.amber),
              SizedBox(width: 4),
              Text('深度推理',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.amber,
                      letterSpacing: 0.6)),
            ]),
            const SizedBox(height: 4),
            Text(
              txt,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

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
