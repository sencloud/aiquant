import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

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
    final hasToolCalls = (message.toolCalls?.isNotEmpty ?? false);
    final hasContent = message.content.trim().isNotEmpty;

    final bg = isUser ? AppColors.amber : AppColors.bgRaised;
    final fg = isUser ? Colors.black : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        // 时间顺序：推理 → 工具调用 → 正文。AI 通常先「调用工具拿数据」，再
        // 「基于数据写正文」，UI 顺序按真实时序展示更直观。
        children: [
          if (hasReasoning)
            ReasoningBlock(
              text: message.reasoning!,
              streaming: message.streaming && !hasContent,
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
          if (hasContent)
            Padding(
              padding: EdgeInsets.only(top: hasToolCalls ? 6 : 0),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.86,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isUser && message.portfolioAttached)
                      _PortfolioBadge(name: message.portfolioName),
                    _content(context, fg),
                  ],
                ),
              ),
            ),
          if (!isUser && hasContent && !message.streaming)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: _MessageActionsBar(text: message.content),
            ),
          if (message.streaming &&
              !hasReasoning &&
              !hasContent &&
              !hasToolCalls)
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

    // streaming 时不再对整段 markdown 做淡入（会让旧内容反复重绘 → 闪动）。
    // 直接渲染最新内容，并在末尾放一个金黄闪烁光标作为"还在打字"的视觉提示。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        markdown,
        const SizedBox(height: 2),
        const _BlinkingCursor(),
      ],
    );
  }
}

/// 助理消息底部的轻量操作栏：复制 / 分享到微信。
///
/// 分享走 iOS 系统分享面板（UIActivityViewController）—— 装了微信后会自动
/// 出现「微信」「朋友圈」入口，无需额外引入微信 SDK 或原生配置。
class _MessageActionsBar extends StatelessWidget {
  const _MessageActionsBar({required this.text});

  final String text;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _shareToWeChat(BuildContext context) async {
    // iPad 上系统要求提供 popover 锚点，否则可能崩溃；这里取按钮自身位置。
    Rect? origin;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      origin = topLeft & box.size;
    }
    await Share.share(
      text,
      subject: '来自喜宽 AI 助理',
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionChip(
          icon: Icons.copy_outlined,
          label: '复制',
          onTap: () => _copy(context),
        ),
        const SizedBox(width: 6),
        Builder(
          builder: (btnCtx) => _ActionChip(
            icon: Icons.ios_share,
            label: '分享到微信',
            onTap: () => _shareToWeChat(btnCtx),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 用户消息上方的"已附带组合"标识；仅在该消息发送时携带 portfolio_context
/// 时显示，便于事后回看历史时知道当时的回答基于哪个组合。
class _PortfolioBadge extends StatelessWidget {
  const _PortfolioBadge({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final label = name == null || name!.isEmpty ? '已附带组合' : '已附带组合：$name';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet,
                size: 11, color: Colors.black87),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
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
