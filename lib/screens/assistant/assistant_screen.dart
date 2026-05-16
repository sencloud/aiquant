import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/persona.dart';
import '../../state/chat_state.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart';
import 'widgets/message_bubble.dart';
import 'widgets/persona_picker.dart';
import 'widgets/session_drawer.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  // 推理过程默认始终展示；不再提供顶部隐藏开关。
  static const bool _showReasoning = true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 240,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? override]) async {
    final raw = override ?? _input.text;
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    // 发送即收起键盘 + 失焦，让聊天区视野最大化
    _focus.unfocus();
    await context.read<ChatState>().sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatState>();
    final session = chat.active;
    final persona = chat.currentPersona;

    if (chat.streaming) _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI 助理'),
            const SizedBox(width: 8),
            if (chat.totalTokens > 0)
              Text(
                '${chat.totalTokens} tok',
                style: TextStyle(
                    fontSize: 10, color: AppColors.textTertiary),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '新对话',
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            onPressed: () => chat.newSession(),
          ),
          IconButton(
            tooltip: '我的',
            icon: const Icon(Icons.person_outline, size: 18),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      drawer: const SessionDrawer(),
      body: Column(
        children: [
          PersonaPicker(
            activeId: persona.id,
            disabled: chat.streaming,
            onPick: (id) async {
              final isNewSessionEmpty =
                  (session?.messages.isEmpty ?? true);
              if (isNewSessionEmpty) {
                await chat.setPersona(id);
              } else {
                // 已有对话不切 persona，直接开新会话避免 prompt 跳变
                await chat.newSession(personaId: id);
              }
            },
          ),
          Container(height: 1, color: AppColors.borderDim),
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _welcomePanel(persona)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    itemCount: session.messages.length,
                    itemBuilder: (context, i) {
                      final msg = session.messages[i];
                      return MessageBubble(
                        message: msg,
                        allMessages: session.messages,
                        showReasoning: _showReasoning,
                      );
                    },
                  ),
          ),
          _composer(chat),
        ],
      ),
    );
  }

  /// 空会话时的欢迎面板：参考"元宝"截图布局——上半部分留白让视线聚焦，
  /// 下半部分依次为大标题、福利中心广告条、3 条快速提问 pill。
  Widget _welcomePanel(Persona persona) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'Hi，今天从哪里开始？',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _CreditAdBanner(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 14),
          for (final q in persona.welcomeSuggestions.take(3)) _suggestion(q),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 椭圆 pill 样式的快速提问（替代原 raised 背景的方框样式），
  /// 视觉风格更靠近"元宝"截图，但配色仍走金黄主调。
  Widget _suggestion(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: AppColors.bgRaised,
          shape: StadiumBorder(
            side: BorderSide(color: AppColors.borderDim),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _send(text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  /// 输入框做成圆角胶囊形，主按钮内嵌右侧——参考截图样式，
  /// 但保持深色暗调 + 金黄主色，不照搬截图浅色配色。
  Widget _composer(ChatState chat) {
    return Container(
      color: AppColors.bgSurface,
      padding: EdgeInsets.fromLTRB(
          14, 8, 14, 10 + MediaQuery.of(context).padding.bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgRaised,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.borderDim),
              ),
              padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 6,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '发消息或问点 A 股 / ETF / 期货…',
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _sendButton(chat),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendButton(ChatState chat) {
    if (chat.streaming) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: AppColors.bgSurface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.amber, width: 1.2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => chat.abort(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.stop, color: AppColors.amber, size: 18),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: AppColors.amber,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _send,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.arrow_upward, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

/// 福利中心广告条 — 引导用户进入"我的"页面充值喜点。
/// 视觉参考"元宝"截图的紫色福利条；这里改用金黄渐变与现有主题统一。
class _CreditAdBanner extends StatelessWidget {
  const _CreditAdBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.amber.withValues(alpha: 0.20),
                AppColors.amber.withValues(alpha: 0.06),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '喜宽福利中心',
                      style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '做任务、买喜点、解锁深度 AI 与高级行情',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text(
                      '福利中心',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
