import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/chat.dart';
import '../../../services/share_service.dart';
import '../../../state/chat_state.dart';
import '../../../theme/app_theme.dart';
import 'reasoning_block.dart';
import 'share_card_screen.dart';
import 'tool_call_card.dart';

/// 复制文本到剪贴板并轻提示。聊天区"长按复制"与操作栏"复制"共用。
Future<void> _copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('已复制到剪贴板'),
      duration: Duration(seconds: 1),
    ),
  );
}

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
              child: _MessageActionsBar(
                text: message.content,
                question: _previousUserText(),
                timestamp: message.timestamp,
              ),
            ),
          if (isUser && hasContent)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: _UserActionsBar(text: message.content),
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

  /// 找当前 assistant 消息之前最近的一条 user 消息正文（供长图分享用）。
  ///
  /// 若找不到（例如对话首条就是 assistant），返回 null，
  /// 长图渲染时则只显示「回答」段。
  String? _previousUserText() {
    final idx = allMessages.indexOf(message);
    if (idx <= 0) return null;
    for (var i = idx - 1; i >= 0; i--) {
      final m = allMessages[i];
      if (m.role == 'user' && m.content.trim().isNotEmpty) {
        return m.content.trim();
      }
    }
    return null;
  }

  Widget _content(BuildContext context, Color fg) {
    if (message.role == 'user') {
      // 用户气泡用纯 Text（非 selectable），长按整段复制。
      return GestureDetector(
        onLongPress: () => _copyText(context, message.content),
        child: Text(
          message.content,
          style: TextStyle(color: fg, fontSize: 13, height: 1.4),
        ),
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

/// 助理消息底部的轻量操作栏：复制 / 生成长图分享。
///
/// 「长图分享」先 push 到 [ShareCardScreen] 让用户预览，再调系统分享面板
/// （iOS 装了微信会出现「微信 / 朋友圈」入口）。比直接 text 分享更"成图友好"，
/// 接收方在微信里看是一张完整的品牌长图。
class _MessageActionsBar extends StatefulWidget {
  const _MessageActionsBar({
    required this.text,
    required this.timestamp,
    this.question,
  });

  final String text;
  final DateTime timestamp;

  /// 触发这条 assistant 回答的上一条 user 提问；长图 / 分享页里会同时渲染。
  final String? question;

  @override
  State<_MessageActionsBar> createState() => _MessageActionsBarState();
}

class _MessageActionsBarState extends State<_MessageActionsBar> {
  bool _sharingLink = false;

  void _shareAsImage() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareCardScreen(
        question: widget.question,
        text: widget.text,
        timestamp: widget.timestamp,
      ),
    ));
  }

  /// 生成可分享的网页链接：先把问答存到服务端换回短链，再走系统分享面板
  /// 发送 URL（微信里点开是一张品牌网页）。
  Future<void> _shareAsLink() async {
    if (_sharingLink) return;
    setState(() => _sharingLink = true);
    try {
      final url = await ShareService().createShare(
        question: widget.question,
        answer: widget.text,
      );
      if (!mounted) return;
      Rect? origin;
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        origin = box.localToGlobal(Offset.zero) & box.size;
      }
      await Share.share(
        '我用喜宽 AI 助理聊了点投资，分享给你看看：\n$url',
        subject: '来自喜宽 AI 助理',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成分享链接失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _sharingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionChip(
          icon: Icons.copy_outlined,
          label: '复制',
          onTap: () => _copyText(context, widget.text),
        ),
        const SizedBox(width: 6),
        _ActionChip(
          icon: Icons.ios_share,
          label: '长图分享',
          onTap: _shareAsImage,
        ),
        const SizedBox(width: 6),
        _ActionChip(
          icon: _sharingLink ? Icons.hourglass_top : Icons.link,
          label: _sharingLink ? '生成中…' : '链接分享',
          onTap: _sharingLink ? null : _shareAsLink,
        ),
      ],
    );
  }
}

/// 用户消息底部操作栏：复制 / 重发。
///
/// - 复制：拷贝该条用户输入到剪贴板。
/// - 重发：把同样的文字再发一次（追加一轮新问答），方便重试或换个回答。
class _UserActionsBar extends StatelessWidget {
  const _UserActionsBar({required this.text});

  final String text;

  Future<void> _resend(BuildContext context) async {
    final chat = context.read<ChatState>();
    if (chat.streaming) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请等当前回复完成后再重发'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    await chat.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionChip(
          icon: Icons.copy_outlined,
          label: '复制',
          onTap: () => _copyText(context, text),
        ),
        const SizedBox(width: 6),
        _ActionChip(
          icon: Icons.refresh,
          label: '重发',
          onTap: () => _resend(context),
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
  final VoidCallback? onTap;

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
