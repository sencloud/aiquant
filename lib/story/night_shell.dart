import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'night_kit.dart';
import 'night_theme.dart';
import 'screens/character_sheet.dart';
import 'screens/contacts_screen.dart';
import 'screens/ending_screen.dart';
import 'screens/me_screen.dart';
import 'screens/moments_screen.dart';
import 'screens/night_end_screen.dart';
import 'screens/story_chat_screen.dart';
import 'screens/story_closed_screen.dart';
import 'screens/story_intro_screen.dart';
import 'screens/true_ending_screen.dart';
import 'story_api.dart';
import 'story_models.dart';
import 'story_state.dart';

/// 《天亮以前》的独立外壳。
///
/// 主 App 的 `WxShell` 一行不动；这里从「通讯录」开始，三页签 + 全屏聊天。
/// 入口在「发现 → 天亮以前 · 试用」，或 `--dart-define=STORY_TRIAL_HOME=true`
/// 直接落到这里做走查。
class NightShell extends StatefulWidget {
  const NightShell({super.key, this.state});

  /// 测试 / 走查注入。为空时自己创建并 load。
  final StoryState? state;

  @override
  State<NightShell> createState() => _NightShellState();
}

class _NightShellState extends State<NightShell> {
  late final StoryState _story = widget.state ?? StoryState(api: StoryApi());
  late final bool _owns = widget.state == null;

  @override
  void initState() {
    super.initState();
    if (_owns) _story.load();
  }

  @override
  void dispose() {
    if (_owns) _story.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StoryState>.value(
      value: _story,
      child: Theme(
        data: buildNightTheme(),
        child: const _NightScaffold(),
      ),
    );
  }
}

class _NightScaffold extends StatefulWidget {
  const _NightScaffold();

  @override
  State<_NightScaffold> createState() => _NightScaffoldState();
}

class _NightScaffoldState extends State<_NightScaffold> {
  int _tab = 0;
  bool _chatOpen = false;
  bool _showTrueEnding = false;

  @override
  Widget build(BuildContext context) {
    final story = context.watch<StoryState>();

    if (story.loading) {
      return Scaffold(
        backgroundColor: NightColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('天亮以前',
                  style: NightType.display.copyWith(
                    fontSize: 26,
                    letterSpacing: 4,
                  )),
              const SizedBox(height: 18),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  minHeight: 1,
                  backgroundColor: NightColors.borderSoft,
                  color: NightColors.amber,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!story.config.enabled) {
      return Scaffold(
        backgroundColor: NightColors.bg,
        body: StoryClosedScreen(
          notice: story.config.notice,
          onRetry: story.refreshConfig,
          onExit: _exit,
        ),
      );
    }

    if (!story.introSeen) {
      return Scaffold(
        backgroundColor: NightColors.bg,
        body: StoryIntroScreen(
          onEnter: story.acceptIntro,
          onExit: _exit,
        ),
      );
    }

    if (_showTrueEnding) {
      return Scaffold(
        backgroundColor: NightColors.bg,
        body: TrueEndingScreen(
          onClose: () async {
            await story.archiveRun();
            if (!mounted) return;
            setState(() {
              _showTrueEnding = false;
              _chatOpen = false;
              _tab = 0;
            });
          },
        ),
      );
    }

    if (story.finished) {
      return Scaffold(
        backgroundColor: NightColors.bg,
        body: EndingScreen(
          onRestart: () async {
            await story.restartRoute();
            if (mounted) setState(() => _chatOpen = true);
          },
          onArchive: () async {
            await story.archiveRun();
            if (mounted) {
              setState(() {
                _chatOpen = false;
                _tab = 0;
              });
            }
          },
          onTrueEnding: () => setState(() => _showTrueEnding = true),
        ),
      );
    }

    if (story.nightComplete) {
      return const Scaffold(
        backgroundColor: NightColors.bg,
        body: NightEndScreen(),
      );
    }

    final inChat = _chatOpen && story.run != null;
    return Scaffold(
      backgroundColor: NightColors.bg,
      body: inChat
          ? StoryChatScreen(
              onExit: () => setState(() => _chatOpen = false),
            )
          : IndexedStack(
              index: _tab,
              children: [
                ContactsScreen(
                  state: story,
                  onOpenCharacter: _openCharacter,
                  onContinue: () => setState(() => _chatOpen = true),
                ),
                MomentsScreen(state: story),
                MeScreen(
                  state: story,
                  onContinue: () => setState(() => _chatOpen = true),
                  onRestart: () async {
                    await story.restartRoute();
                    if (mounted) setState(() => _chatOpen = true);
                  },
                ),
              ],
            ),
      bottomNavigationBar: inChat
          ? null
          : NightBottomNav(
              index: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
    );
  }

  void _openCharacter(StoryCharacter character) {
    final story = context.read<StoryState>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<StoryState>.value(
          value: story,
          child: CharacterSheet(
            character: character,
            onStarted: () {
              if (mounted) setState(() => _chatOpen = true);
            },
          ),
        ),
      ),
    );
  }

  void _exit() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
