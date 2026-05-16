import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/chat_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import '../../ui/theme_toggle_button.dart';
import '../settings/settings_screen.dart';
import 'widgets/message_bubble.dart';
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
    final settings = context.watch<SettingsState>();
    final session = chat.active;

    if (chat.streaming) _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AI 助理'),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: settings.deepMode
                      ? AppColors.amber
                      : AppColors.borderMed,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                settings.deepMode
                    ? '深度模式 · DeepSeek-R'
                    : settings.deepseekModel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: settings.deepMode
                      ? AppColors.amber
                      : AppColors.textSecondary,
                ),
              ),
            ),
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
            tooltip: _showReasoning ? '隐藏推理过程' : '显示推理过程',
            icon: Icon(_showReasoning ? Icons.visibility : Icons.visibility_off,
                size: 18),
            onPressed: () => setState(() => _showReasoning = !_showReasoning),
          ),
          IconButton(
            tooltip: '新对话',
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            onPressed: () => chat.newSession(),
          ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined, size: 18),
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
          if (!settings.hasDeepseekKey) _missingKeyBanner(),
          Expanded(
            child: session == null || session.messages.isEmpty
                ? _welcomePanel(context)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    itemCount: session.messages.length,
                    itemBuilder: (context, i) {
                      final msg = session.messages[i];
                      return MessageBubble(
                        message: msg,
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

  Widget _missingKeyBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: AppColors.bgRaised,
        child: Row(
          children: [
            const Icon(Icons.key_off, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '尚未配置 DeepSeek API Key — 前往“设置”填写后即可对话。',
                style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('打开设置'),
            ),
          ],
        ),
      );

  Widget _welcomePanel(BuildContext context) {
    final settings = context.read<SettingsState>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('欢迎使用 Fincept AI 助理',
                  style: TextStyle(
                      color: AppColors.amber,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0)),
              const SizedBox(height: 8),
              Text(
                settings.deepMode
                    ? '当前默认模型：deepseek-reasoner（深度模式 / 推理）。'
                    : '当前模型：${settings.deepseekModel}。可在“设置”切换。',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Text('试试这些提问：',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              _suggestion('帮我分析一下沪深300近期的成交结构'),
              _suggestion('我持有 600519、000858、300750，请给出风险提示'),
              _suggestion('列出最近 5 天涨幅靠前的有色金属板块个股'),
              _suggestion('如何用波动率构建一个稳健的 ETF 组合？'),
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
