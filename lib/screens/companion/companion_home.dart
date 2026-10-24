import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/chat_state.dart';
import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';
import '../../models/companion_mood.dart';
import 'live_avatar.dart';

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
  bool _arrival = true;

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
    return Stack(
      children: [
        if (_ready)
          const AssistantScreen()
        else
          const ColoredBox(color: Color(0xFFF4EEE4)),
        if (_arrival)
          Positioned.fill(
            child: _Arrival(
              onDone: () {
                if (mounted) setState(() => _arrival = false);
              },
            ),
          ),
      ],
    );
  }
}

/// 「去她家」的开场：二次元欢迎。
///
/// 她的写真放大淡入，冒出一句「你来啦。」，几片花瓣飘过；1.8 秒后自动
/// 让位给对话，点一下也能立刻跳过。
class _Arrival extends StatefulWidget {
  const _Arrival({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<_Arrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _timer = Timer(const Duration(milliseconds: 2000), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = context.watch<CompanionState>().look;
    return GestureDetector(
      onTap: widget.onDone,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_c.value);
          final fadeOut = _c.value > 0.85
              ? (1 - (_c.value - 0.85) / 0.15).clamp(0.0, 1.0)
              : 1.0;
          return Stack(
            fit: StackFit.expand,
              children: [
                Image.asset('assets/portraits/room.jpg', fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.30),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.45),
                      ],
                    ),
                  ),
                ),
                for (var i = 0; i < 7; i++)
                  Positioned(
                    left: 30.0 + (i * 47) % 330,
                    top: 90 + ((i * 83 + _c.value * 520) % 700),
                    child: Opacity(
                      opacity: 0.55 * fadeOut,
                      child: Transform.rotate(
                        angle: _c.value * (i.isEven ? 1.2 : -1.0),
                        child: const Icon(Icons.local_florist_rounded,
                            size: 14, color: Color(0xFFC9A67A)),
                      ),
                    ),
                  ),
                Center(
                  child: Opacity(
                    opacity: fadeOut,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.88 + 0.12 * t,
                          child: LiveAvatar(
                            look: look,
                            mood: AvatarMood.happy,
                            width: 168,
                            height: 208,
                            radius: 28,
                          ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg, vertical: AppSpace.md),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '你来啦。',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              fontFamilyFallback: AppType.sansFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
          );
        },
      ),
    );
  }
}
