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
  bool _showReasoning = true;

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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
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
            tooltip: (session?.toolsEnabled ?? false)
                ? '已启用工具调用 (Tushare)'
                : '点击启用工具调用',
            icon: Icon(
              (session?.toolsEnabled ?? false)
                  ? Icons.handyman
                  : Icons.handyman_outlined,
              size: 18,
              color: (session?.toolsEnabled ?? false)
                  ? AppColors.amber
                  : AppColors.textSecondary,
            ),
            onPressed: () => chat
                .setToolsEnabled(!(session?.toolsEnabled ?? false)),
          ),
          IconButton(
            tooltip: _showReasoning ? '隐藏推理过程' : '显示推理过程',
            icon: Icon(
                _showReasoning ? Icons.visibility : Icons.visibility_off,
                size: 18),
            onPressed: () =>
                setState(() => _showReasoning = !_showReasoning),
          ),
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

  Widget _welcomePanel(Persona persona) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: persona.color.withValues(alpha: 0.18),
                    border: Border.all(color: persona.color),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(persona.icon, size: 18, color: persona.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(persona.displayName,
                          style: TextStyle(
                              color: persona.color,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0)),
                      const SizedBox(height: 2),
                      Text(persona.title,
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              Text('试试这些提问：',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              for (final q in persona.welcomeSuggestions) _suggestion(q),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestion(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: AppColors.bgRaised,
          child: InkWell(
            onTap: () {
              _input.text = text;
              _focus.requestFocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.east, color: AppColors.amber, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _composer(ChatState chat) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderDim)),
        color: AppColors.bgSurface,
      ),
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
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
                hintText: '问问关于 A 股 / ETF / 期货的任何问题…',
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          if (chat.streaming)
            OutlinedButton(
              onPressed: () => chat.abort(),
              child: const Text('中断'),
            )
          else
            ElevatedButton.icon(
              onPressed: _send,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('发送'),
            ),
        ],
      ),
    );
  }
}
