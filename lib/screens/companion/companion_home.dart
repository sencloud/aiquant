import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/chat_state.dart';
import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';

/// App 的全部：和喜爱的一段对话。
///
/// 没有页签、没有广场、没有发现 —— 打开就是她。这里只负责两件事：
///   1. 确保「喜爱」这段会话存在（一次安装只有一段，不让人挑）；
///   2. 在她该开口的时候（隔了一阵、不是深夜）让她先说一句。
class CompanionHome extends StatefulWidget {
  const CompanionHome({super.key});

  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // 从后台回来：她可能想先说一句。
      // ignore: unawaited_futures
      context
          .read<CompanionState>()
          .maybeSaySomething(context.read<ChatState>());
    }
  }

  Future<void> _boot() async {
    if (!mounted) return;
    final chat = context.read<ChatState>();
    if (chat.sessions.isEmpty) {
      await chat.bootstrap();
    }
    if (!mounted) return;
    await _ensureSession(chat);
    if (!mounted) return;
    final companion = context.read<CompanionState>();
    if (chat.active?.messages.isEmpty ?? false) {
      await chat.addLocalMessage(
          '我是${companion.name}。\n陪着你，是长情的告白。');
    }
    if (!mounted) return;
    setState(() => _ready = true);
    await companion.maybeSaySomething(chat);
  }

  Future<void> _ensureSession(ChatState chat) async {
    for (final s in chat.sessions) {
      if (s.topic == 'companion') {
        chat.selectSession(s.id);
        return;
      }
    }
    await chat.newSession(
      topic: 'companion',
      personaId: 'xiai',
      title: '喜爱',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(backgroundColor: AppColors.bgBase);
    }
    return const AssistantScreen();
  }
}
