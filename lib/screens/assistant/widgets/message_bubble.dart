import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/image_data_url.dart';
import '../../../models/chat.dart';
import '../../../services/invite_service.dart';
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

/// 点开查看大图（可双指缩放 / 拖动）。
void _openImagePreview(BuildContext context, String dataUrl) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _ImageViewerScreen(dataUrl: dataUrl),
    ),
  );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.allMessages,
    this.showReasoning = true,
    this.showShareActions = true,
    this.isLatest = false,
    this.onSuggestion,
    this.onRegenerate,
    this.onFeedback,
  });

  final ChatMessage message;
  final List<ChatMessage> allMessages;
  final bool showReasoning;

  /// 是否为会话里最新一条回答：只有它展示「重新生成」和推荐追问（元宝式）。
  final bool isLatest;

  /// 点推荐追问 → 直接发送。为 null 时不展示推荐追问。
  final ValueChanged<String>? onSuggestion;

  /// 重新生成本条回答。为 null 时不展示该按钮。
  final VoidCallback? onRegenerate;

  /// 点赞（1）/ 点踩（-1）。为 null 时不展示反馈按钮。
  final ValueChanged<int>? onFeedback;

  /// 桌面端传 false 隐藏「长图/链接/推广文案」分享类按钮——
  /// share_plus 在 Windows 上能力有限（无系统分享面板），只保留复制。
  final bool showShareActions;

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
    final imageUrls = message.imageDataUrls ?? const <String>[];
    final hasImages = imageUrls.isNotEmpty;

    // AI 气泡用白面：对话区背后是奶油色渐变的背景，米色气泡会糊在底上。
    // 用户气泡保持主色实心，前景色用主题里的 onAccent（白字压墨金 5.4:1）。
    final bg = isUser ? AppColors.amber : AppColors.bgSurface;
    final fg = isUser ? AppColors.onAccent : AppColors.textPrimary;

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
          if (hasImages)
            Padding(
              padding: EdgeInsets.only(top: hasToolCalls ? 6 : 0),
              child: _UserImageStrip(urls: imageUrls),
            ),
          if (hasContent)
            Padding(
              padding:
                  EdgeInsets.only(top: (hasToolCalls || hasImages) ? 6 : 0),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.86,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  // AI 气泡是白面，压在奶油色背景上要靠一条发丝线收边，
                  // 不然边缘会化开。用户气泡是实心主色，不需要线。
                  border: isUser
                      ? null
                      : Border.all(color: AppColors.borderDim, width: 0.5),
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
                showShareActions: showShareActions,
                feedback: message.feedback,
                onRegenerate: isLatest ? onRegenerate : null,
                onFeedback: onFeedback,
                sources: hasToolCalls ? _collectSources() : const [],
                tools: hasToolCalls
                    ? message.toolCalls!.map((c) => c.name).toSet().toList()
                    : const [],
              ),
            ),
          if (!isUser &&
              isLatest &&
              !message.streaming &&
              onSuggestion != null &&
              (message.suggestions?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 2),
              child: _FollowUpList(
                questions: message.suggestions!,
                onTap: onSuggestion!,
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

  /// 从本条回答调用过的工具结果里抽出「来源」：任意层级里带 http(s) url
  /// 的对象（资讯条目等）。按 url 去重，最多 20 条。
  List<_Source> _collectSources() {
    final out = <_Source>[];
    final seen = <String>{};
    void walk(Object? node, int depth) {
      if (depth > 6 || out.length >= 20) return;
      if (node is Map) {
        final url = node['url'] ?? node['link'] ?? node['url_m'] ?? node['url_w'];
        if (url is String && url.startsWith('http') && seen.add(url)) {
          final title = node['title'] ?? node['name'] ?? node['digest'];
          final src = node['source'] ?? node['media'] ?? node['domain'];
          out.add(_Source(
            url: url,
            title: title is String && title.trim().isNotEmpty
                ? title.trim()
                : url,
            source: src is String ? src : null,
          ));
        }
        for (final v in node.values) {
          walk(v, depth + 1);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v, depth + 1);
        }
      }
    }

    for (final c in message.toolCalls ?? const <ToolCall>[]) {
      final r = _findToolResult(c.id);
      if (r == null || r.content.isEmpty) continue;
      try {
        walk(jsonDecode(r.content), 0);
      } catch (_) {
        // 非 JSON 的工具结果没有结构化来源。
      }
    }
    return out;
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

/// 用户消息里的图片：单图按原比例展示，多图按 96 方块平铺；点开看大图。
class _UserImageStrip extends StatelessWidget {
  const _UserImageStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.86;
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openImagePreview(context, urls.first),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 240),
            child: _thumb(decodeImageDataUrl(urls.first),
                fit: BoxFit.contain, placeholderSize: 120),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          for (final url in urls)
            GestureDetector(
              onTap: () => _openImagePreview(context, url),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                child: _thumb(decodeImageDataUrl(url),
                    width: 96, height: 96, fit: BoxFit.cover, placeholderSize: 96),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb(
    Uint8List bytes, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    required double placeholderSize,
  }) {
    if (bytes.isEmpty) {
      return Container(
        width: width,
        height: height ?? placeholderSize,
        color: AppColors.bgRaised,
        child: Icon(Icons.broken_image_outlined,
            size: 18, color: AppColors.textTertiary),
      );
    }
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
    );
  }
}

/// 全屏看大图（可双指缩放 / 拖动）。
class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeImageDataUrl(dataUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: bytes.isEmpty
            ? const Text('图片无法显示',
                style: TextStyle(color: Colors.white70, fontSize: 13))
            : InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
      ),
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
    this.showShareActions = true,
    this.feedback = 0,
    this.onRegenerate,
    this.onFeedback,
    this.sources = const [],
    this.tools = const [],
  });

  /// 当前反馈：1 赞 / -1 踩 / 0 未评价。
  final int feedback;
  final VoidCallback? onRegenerate;
  final ValueChanged<int>? onFeedback;

  /// 工具结果里抽出的带链接来源。
  final List<_Source> sources;

  /// 本条回答调用过的工具名（去重）。
  final List<String> tools;

  final String text;
  final DateTime timestamp;

  /// 触发这条 assistant 回答的上一条 user 提问；长图 / 分享页里会同时渲染。
  final String? question;

  /// false 时只保留「复制」，隐藏依赖 share_plus 的分享按钮（桌面端用）。
  final bool showShareActions;

  @override
  State<_MessageActionsBar> createState() => _MessageActionsBarState();
}

class _MessageActionsBarState extends State<_MessageActionsBar> {
  bool _sharingLink = false;
  bool _copying = false;

  /// 尽力取当前用户邀请码（未登录/异常返回空，不阻塞分享）。
  Future<String> _fetchInviteCode() async {
    try {
      // 邀请已独立于鹦鹉螺（奖励改为喜点），走 /v1/invite。
      final info = await InviteService().info();
      return info.code;
    } catch (_) {
      return '';
    }
  }

  Future<void> _shareAsImage() async {
    final code = await _fetchInviteCode();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareCardScreen(
        question: widget.question,
        text: widget.text,
        timestamp: widget.timestamp,
        inviteCode: code,
      ),
    ));
  }

  /// 推广文案：选平台 → 生成短链 → 拼平台化文案 → 复制到剪贴板。
  Future<void> _copyPromoText() async {
    if (_copying) return;
    final platform = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('复制推广文案',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
            _promoOption(ctx, '小红书', Icons.tag, 'xhs'),
            _promoOption(ctx, '知乎', Icons.help_outline, 'zhihu'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (platform == null || !mounted) return;

    setState(() => _copying = true);
    try {
      final url = await ShareService().createShare(
        question: widget.question,
        answer: widget.text,
      );
      final caption = _buildPromoCaption(platform, widget.text, url);
      await Clipboard.setData(ClipboardData(text: caption));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${platform == 'xhs' ? '小红书' : '知乎'}文案已复制，去粘贴发布吧'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成文案失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Widget _promoOption(
      BuildContext ctx, String label, IconData icon, String value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.amber, size: 20),
      title: Text(label,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      onTap: () => Navigator.of(ctx).pop(value),
    );
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
        '我用喜爱 AI 助理聊了点投资，分享给你看看：\n$url',
        subject: '来自喜爱 AI 助理',
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

  /// 平台化推广文案：钩子标题 + 正文摘要 + 话题标签 + 短链。
  String _buildPromoCaption(String platform, String text, String url) {
    final excerpt = _excerpt(text, 120);
    if (platform == 'xhs') {
      return '我用喜爱 AI 投研助理问了个问题，回答太顶了📈\n\n'
          '$excerpt\n\n'
          '完整对话👉 $url\n\n'
          '#投资理财 #AI工具 #股票 #理财 #搞钱 #财经 #喜爱';
    }
    // 知乎：偏问答/理性语气。
    return '分享一个我最近在用的 AI 投研助理「喜爱」，问答体验不错。\n\n'
        '$excerpt\n\n'
        '完整回答：$url\n\n'
        '（内容由 AI 生成，仅供参考，不构成投资建议）';
  }

  /// 取正文前 n 字摘要：去掉 Markdown 符号与多余空行。
  String _excerpt(String text, int n) {
    final plain = text
        .replaceAll(RegExp(r'[#>*`_~\-]'), '')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
    if (plain.length <= n) return plain;
    return '${plain.substring(0, n)}…';
  }

  /// 分享入口收进一个底部面板：长图 / 链接 / 推广文案。
  Future<void> _openShareSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _promoOption(ctx, '长图分享', Icons.image_outlined, 'image'),
            _promoOption(ctx, '链接分享', Icons.link, 'link'),
            _promoOption(ctx, '复制推广文案', Icons.campaign_outlined, 'promo'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'image':
        await _shareAsImage();
        break;
      case 'link':
        await _shareAsLink();
        break;
      case 'promo':
        await _copyPromoText();
        break;
    }
  }

  void _openSources() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SourcesSheet(
        sources: widget.sources,
        tools: widget.tools,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sharingLink || _copying;
    return Row(
      children: [
        if (widget.onRegenerate != null)
          _ActionIcon(
            icon: Icons.refresh_rounded,
            tooltip: '重新生成',
            onTap: widget.onRegenerate,
          ),
        _ActionIcon(
          icon: Icons.copy_rounded,
          tooltip: '复制',
          onTap: () => _copyText(context, widget.text),
        ),
        if (widget.onFeedback != null) ...[
          _ActionIcon(
            icon: widget.feedback == 1
                ? Icons.thumb_up_alt_rounded
                : Icons.thumb_up_alt_outlined,
            tooltip: '有帮助',
            active: widget.feedback == 1,
            onTap: () => widget.onFeedback!(1),
          ),
          _ActionIcon(
            icon: widget.feedback == -1
                ? Icons.thumb_down_alt_rounded
                : Icons.thumb_down_alt_outlined,
            tooltip: '没帮助',
            active: widget.feedback == -1,
            onTap: () => widget.onFeedback!(-1),
          ),
        ],
        // 分享类依赖系统分享面板（share_plus），桌面端隐藏。
        if (widget.showShareActions)
          _ActionIcon(
            icon: busy ? Icons.hourglass_top_rounded : Icons.share_outlined,
            tooltip: '分享',
            onTap: busy ? null : _openShareSheet,
          ),
        const Spacer(),
        if (widget.sources.isNotEmpty || widget.tools.isNotEmpty)
          _SourcesChip(
            count: widget.sources.isNotEmpty
                ? widget.sources.length
                : widget.tools.length,
            withLinks: widget.sources.isNotEmpty,
            onTap: _openSources,
          ),
      ],
    );
  }
}

/// 回答下方的图标按钮（元宝那一排：重新生成 / 复制 / 赞 / 踩 / 分享）。
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(
            icon,
            size: 19,
            color: active ? AppColors.amber : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 右侧「来源」小胶囊：有链接显示「N 个来源」，否则显示用到的数据工具数。
class _SourcesChip extends StatelessWidget {
  const _SourcesChip({
    required this.count,
    required this.withLinks,
    required this.onTap,
  });

  final int count;
  final bool withLinks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(withLinks ? Icons.link_rounded : Icons.storage_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                withLinks ? '$count 个来源' : '$count 项数据',
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

/// 工具结果里抽出的一条来源。
class _Source {
  const _Source({required this.url, required this.title, this.source});
  final String url;
  final String title;
  final String? source;
}

/// 「来源」面板：带链接的资讯条目（点开浏览器）+ 本次用到的数据工具。
class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.sources, required this.tools});

  final List<_Source> sources;
  final List<String> tools;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          children: [
            Text('来源',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final s in sources)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.article_outlined,
                    size: 18, color: AppColors.amber),
                title: Text(s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
                subtitle: Text(
                  s.source == null || s.source!.isEmpty
                      ? (Uri.tryParse(s.url)?.host ?? s.url)
                      : s.source!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
                onTap: () {
                  final uri = Uri.tryParse(s.url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            if (tools.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('本次调用的数据工具',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tools)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.bgRaised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 最新回答下方的推荐追问：左对齐的浅底胶囊，宽度跟着文字走，点了直接发送。
class _FollowUpList extends StatelessWidget {
  const _FollowUpList({required this.questions, required this.onTap});

  final List<String> questions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.86;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final q in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Material(
                color: AppColors.bgSurface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTap(q),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    child: Text(
                      q,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            ),
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
