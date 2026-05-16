import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../models/chat.dart';
import '../../../theme/app_theme.dart';
import 'reasoning_block.dart';

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
    final hasContent = message.content.trim().isNotEmpty;
    // tool 调用过程对终端用户隐藏 —— 用户只关心最终答复，工具调用卡片不再渲染。

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
          if (message.streaming && !hasReasoning && !hasContent)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _TypingDots(),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, Color fg) {
    if (message.role == 'user') {
      return Text(
        message.content,
        style: TextStyle(color: fg, fontSize: 13, height: 1.4),
      );
    }
    // 流式输出时把内容末尾追加一个零宽 marker，再用一个底部光标动画
    // 配合，模仿元宝的"逐字浮现 + 末尾光标"效果。
    final markdown = MarkdownBody(
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

    if (!message.streaming) return markdown;

    // streaming 时给整个 markdown 加 0.92 → 1.0 的淡入动画 +
    // 文末闪烁的金黄光标，模仿主流 LLM 客户端「逐字浮现」的视觉效果。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          // 用内容长度作为 key，每来一段 delta 就跑一次淡入
          child: KeyedSubtree(
            key: ValueKey(message.content.length ~/ 16),
            child: markdown,
          ),
        ),
        const SizedBox(height: 2),
        const _BlinkingCursor(),
      ],
    );
  }
}

/// 流式输出末尾的闪烁光标 — 用一个 800ms 周期的不透明度脉冲。
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.2, end: 1.0).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.amber,
          borderRadius: BorderRadius.circular(1.5),
        ),
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
