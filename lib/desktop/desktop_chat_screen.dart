import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/require_login.dart';
import '../core/format/credit_fmt.dart';
import '../core/utils/image_data_url.dart';
import '../models/chat.dart';
import '../models/persona.dart';
import '../services/image_attach_service.dart';
import '../state/chat_state.dart';
import '../theme/app_theme.dart';
import '../screens/assistant/widgets/message_bubble.dart';
import '../screens/assistant/widgets/persona_picker.dart';
import 'widgets/desktop_session_list.dart';

/// 桌面端助理对话页。
///
/// 布局（从左到右）：
/// 1. 会话列表（常驻，桌面形态替代移动端抽屉）
/// 2. 消息区：顶部工具条（标题 + persona 切换）+ 居中限宽的消息列 +
///    底部输入区（居中限宽，圆角多行框 + 发送按钮）
///
/// 与移动端 AssistantScreen 共用同一个 ChatState。
class DesktopChatScreen extends StatefulWidget {
  const DesktopChatScreen({super.key});

  @override
  State<DesktopChatScreen> createState() => _DesktopChatScreenState();
}

class _DesktopChatScreenState extends State<DesktopChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 输入框焦点：聚焦时输入框边框变琥珀色（桌面端视觉反馈）。
  final FocusNode _inputFocus = FocusNode();

  /// 已经为哪个会话做过「进入即定位到最新消息」的初始滚动。
  String? _scrolledSessionId;

  /// 待发送的图片（data URL，桌面端走文件选择器，无相机）。
  final ImageAttachService _imageAttach = ImageAttachService();
  final List<String> _pendingImages = [];
  bool _pickingImage = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  /// 进入/切换会话时贴底：markdown 首帧后还会撑高，多跳两次确保到位。
  void _scrollToBottomInitial() {
    void jump() {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      Future.delayed(const Duration(milliseconds: 180), jump);
      Future.delayed(const Duration(milliseconds: 420), jump);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final images = List<String>.from(_pendingImages);
    // 允许「只发图不发文」。
    if (text.isEmpty && images.isEmpty) return;
    // 流式输出中不接受新消息，避免清空输入框和已选图片。
    if (context.read<ChatState>().streaming) return;
    // 发送是需鉴权功能：未登录先弹登录页，放弃则不发送。
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    _input.clear();
    if (images.isNotEmpty) setState(() => _pendingImages.clear());
    await context.read<ChatState>()
        .sendMessage(text, imageDataUrls: images);
    _scrollToBottom();
  }

  /// 桌面端选图：走系统文件选择器（image_picker 的 Windows 实现）。
  Future<void> _pickImages() async {
    if (_pickingImage) return;
    final remaining = ImageAttachService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('最多附带 ${ImageAttachService.maxImages} 张图片'),
        ),
      );
      return;
    }
    setState(() => _pickingImage = true);
    List<String> picked = const [];
    try {
      picked = await _imageAttach.pickFromGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _pendingImages.addAll(picked.take(remaining));
      _pickingImage = false;
    });
  }

  void _showChargeDialog(ChargeIssue issue) {
    final balanceLabel =
        issue.balance != null ? CreditFmt.balance(issue.balance!) : null;
    final content = balanceLabel != null
        ? '当前余额 $balanceLabel 喜点，已经不够本次对话啦。请先在手机端充值。'
        : '喜点不够本次对话啦，请先在手机端充值。';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('喜点不够啦'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;

    if (chat.streaming) _scrollToBottom(animate: false);

    if (session != null &&
        session.messages.isNotEmpty &&
        session.id != _scrolledSessionId) {
      _scrolledSessionId = session.id;
      _scrollToBottomInitial();
    }

    final issue = chat.chargeIssue;
    if (issue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = context.read<ChatState>();
        if (c.chargeIssue == null) return;
        c.consumeChargeIssue();
        _showChargeDialog(issue);
      });
    }

    return Container(
      color: AppColors.bgBase,
      child: Column(
        children: [
          _headerBar(chat, persona, session),
          Container(height: 1, color: AppColors.borderDim),
          Expanded(
            child: Row(
              children: [
                // 左侧：常驻会话列表
                const SizedBox(
                    width: 232, child: DesktopSessionList()),
                Container(width: 1, color: AppColors.borderDim),
                // 右侧：消息区 + 输入区
                Expanded(child: _chatArea(chat, session, persona)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部工具条：页面标题 + persona 切换（替代移动端 AppBar）。
  Widget _headerBar(ChatState chat, Persona persona, ChatSession? session) {
    return Container(
      height: 52,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'AI 助理',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 12),
          if (chat.totalTokens > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.bgRaised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${chat.totalTokens} tok',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10),
              ),
            ),
          const Spacer(),
          PersonaPicker(
            activeId: persona.id,
            disabled: chat.streaming,
            onPick: (id) async {
              final isNewSessionEmpty =
                  (session?.messages.isEmpty ?? true);
              if (isNewSessionEmpty) {
                await chat.setPersona(id);
              } else {
                await chat.newSession(personaId: id);
              }
            },
          ),
          const SizedBox(width: 8),
          _newSessionButton(chat),
        ],
      ),
    );
  }

  Widget _newSessionButton(ChatState chat) {
    return Tooltip(
      message: '新建对话',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: chat.streaming ? null : () => chat.newSession(),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.bgRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDim),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(
                  '新对话',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chatArea(
      ChatState chat, ChatSession? session, Persona persona) {
    return Container(
      color: AppColors.bgBase,
      child: Column(
        children: [
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _welcomePanel(persona)
                : Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 760),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 20),
                        itemCount: session.messages.length,
                        itemBuilder: (context, i) {
                          final msg = session.messages[i];
                          return MessageBubble(
                            message: msg,
                            allMessages: session.messages,
                            // 桌面端隐藏 share_plus 分享按钮
                            showShareActions: false,
                          );
                        },
                      ),
                    ),
                  ),
          ),
          _composer(chat),
        ],
      ),
    );
  }

  /// 空会话欢迎面板：居中大标题 + 快速提问，桌面端不做福利条。
  Widget _welcomePanel(Persona persona) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '嗨，今天想聊点什么？',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '股票、ETF、期货、宏观——问什么都行',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              for (final q in persona.welcomeSuggestions.take(3))
                _suggestion(q),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestion(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Material(
          color: AppColors.bgSurface,
          shape: StadiumBorder(
            side: BorderSide(color: AppColors.borderDim),
          ),
            child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              _input.text = text;
              _send();
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.north_east,
                      color: AppColors.amber, size: 14),
                ],
              ),
            ),
          ),
        ),
      );

  /// 底部输入区：居中限宽，圆角多行框 + 发送按钮（Enter 发送）。
  Widget _composer(ChatState chat) {
    return Container(
      color: AppColors.bgBase,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingImages.isNotEmpty) _pendingImageStrip(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _inputFocus.hasFocus
                                ? AppColors.amber.withValues(alpha: 0.6)
                                : AppColors.borderDim),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _attachButton(),
                          Expanded(
                            child: TextField(
                              controller: _input,
                              focusNode: _inputFocus,
                              minLines: 1,
                              maxLines: 6,
                              style: const TextStyle(fontSize: 13.5),
                              decoration: const InputDecoration(
                                hintText:
                                    '想问点什么？股票、ETF、期货都可以…（Enter 发送）',
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 0),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _sendButton(chat),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 待发送图片缩略图条（右上角可删除）。
  Widget _pendingImageStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _pendingImages.length; i++)
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    decodeImageDataUrl(_pendingImages[i]),
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _pendingImages.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.borderDim),
                      ),
                      child: Icon(Icons.close,
                          size: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 输入框左侧「上传图片」入口。
  Widget _attachButton() {
    final full = _pendingImages.length >= ImageAttachService.maxImages;
    final disabled = full || _pickingImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: '上传图片（最多 ${ImageAttachService.maxImages} 张）',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: disabled ? null : _pickImages,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 20,
              color: disabled ? AppColors.textTertiary : AppColors.amber,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendButton(ChatState chat) {
    if (chat.streaming) {
      return OutlinedButton.icon(
        onPressed: () => chat.abort(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.amber,
          side: const BorderSide(color: AppColors.amber),
          minimumSize: const Size(88, 46),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.stop, size: 16),
        label: const Text('停止'),
      );
    }
    return FilledButton.icon(
      onPressed: _send,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.black,
        minimumSize: const Size(88, 46),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.arrow_upward, size: 16),
      label: const Text('发送'),
    );
  }
}
