import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';

class StoryChatScreen extends StatefulWidget {
  const StoryChatScreen({
    super.key,
    required this.onExit,
  });

  final VoidCallback onExit;

  @override
  State<StoryChatScreen> createState() => _StoryChatScreenState();
}

class _StoryChatScreenState extends State<StoryChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = context.watch<StoryState>();
    final character = story.activeCharacter;
    final night = story.currentNight;
    final beat = story.currentBeat;

    if (character == null || night == null || beat == null) {
      return const Center(
        child: Text('故事没有载入。', style: NightType.caption),
      );
    }

    final messages = story.messages;
    if (messages.length != _lastCount || story.typing) {
      _lastCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Column(
      children: [
        NightBar(
          title: character.name,
          subtitle: '第 ${night.number} 夜 · ${night.title}',
          onBack: widget.onExit,
          actions: const [
            PixelTag('AI · 虚构', color: NightColors.rain),
          ],
        ),
        _SceneHeader(character: character, night: night),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            itemCount: messages.length + (story.typing ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= messages.length) {
                final partial = story.streamingReply;
                if (partial != null && partial.isNotEmpty) {
                  return _MessageRow(
                    message: StoryMessage(
                      role: StoryRole.character,
                      text: partial,
                    ),
                    character: character,
                  );
                }
                return _TypingRow(character: character);
              }
              return _MessageRow(
                message: messages[i],
                character: character,
              );
            },
          ),
        ),
        if (story.safetyPaused)
          _SafetyPanel(
            onContinue: story.acknowledgeSafety,
            onExit: widget.onExit,
          )
        else if (!story.nightComplete && !story.typing)
          _ChoicePanel(
            beat: beat,
            onChoose: story.choose,
          ),
        _Composer(
          controller: _input,
          enabled: !story.typing && !story.nightComplete && !story.safetyPaused,
          onSend: () {
            final text = _input.text;
            if (text.trim().isEmpty) return;
            _input.clear();
            story.send(text);
          },
        ),
      ],
    );
  }
}

class _SceneHeader extends StatelessWidget {
  const _SceneHeader({required this.character, required this.night});

  final StoryCharacter character;
  final StoryNight night;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 122,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        border: Border.all(color: NightColors.border),
        color: NightColors.surface,
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [character.bgA, character.bgB],
                ),
              ),
            ),
            Positioned(
              right: -8,
              top: -26,
              width: 156,
              height: 190,
              child: Opacity(
                opacity: 0.95,
                child: PixelPortrait(
                  character: character,
                  expression: character.expressions.first,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF20E1118), Color(0x000E1118)],
                  stops: [0.38, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${night.time} · ${night.place}',
                      style: NightType.micro.copyWith(letterSpacing: 1)),
                  const SizedBox(height: 5),
                  Text(night.scene,
                      style: NightType.title.copyWith(
                        fontSize: 22,
                        letterSpacing: 3,
                      )),
                  const SizedBox(height: 5),
                  Text('第 ${night.number} 夜 · ${night.title}',
                      style: NightType.caption.copyWith(
                        color: NightColors.amber,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.character});

  final StoryMessage message;
  final StoryCharacter character;

  @override
  Widget build(BuildContext context) {
    if (message.role == StoryRole.system || message.safety) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: NightNote(message.text),
      );
    }

    final mine = message.role == StoryRole.user;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            PixelAvatar(
              character: character,
              size: 30,
              expression: character.expressions.first,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: mine ? NightColors.amber : NightColors.surface,
                border: Border.all(
                  color: mine ? NightColors.amber : NightColors.border,
                ),
              ),
              child: Text(
                message.text,
                style: NightType.body.copyWith(
                  color: mine ? NightColors.ink : NightColors.paper,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow({required this.character});

  final StoryCharacter character;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelAvatar(
            character: character,
            size: 30,
            expression: character.expressions.first,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            decoration: BoxDecoration(
              color: NightColors.surface,
              border: Border.all(color: NightColors.border),
            ),
            child: const TypingIndicator(),
          ),
        ],
      ),
    );
  }
}

class _ChoicePanel extends StatelessWidget {
  const _ChoicePanel({required this.beat, required this.onChoose});

  final StoryBeat beat;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    if (beat.choices.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: NightColors.bg,
        border: Border(top: BorderSide(color: NightColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('这一句，你怎么回？',
                  style: NightType.micro.copyWith(
                    color: NightColors.amber,
                    letterSpacing: 1,
                  )),
              const Spacer(),
              Text('${beat.choices.length} 个选项', style: NightType.micro),
            ],
          ),
          const SizedBox(height: 7),
          for (final c in beat.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: NightColors.surface,
                child: InkWell(
                  onTap: () => onChoose(c.id),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: NightColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(c.label,
                              style: NightType.body.copyWith(fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 15, color: NightColors.amber),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SafetyPanel extends StatelessWidget {
  const _SafetyPanel({required this.onContinue, required this.onExit});

  final VoidCallback onContinue;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: NightColors.surface,
        border: Border(top: BorderSide(color: NightColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('先停一下。',
              style: NightType.title.copyWith(color: NightColors.heart)),
          const SizedBox(height: 6),
          Text(
            '如果你现在很难受，先别一个人扛着。可以退出故事，去找身边的人，'
            '或者联系当地心理援助热线 / 120。',
            style: NightType.caption.copyWith(height: 1.7),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PixelButton(
                  label: '我没事，继续',
                  height: 40,
                  filled: false,
                  onPressed: onContinue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PixelButton(
                  label: '退出故事',
                  height: 40,
                  filled: false,
                  onPressed: onExit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: NightColors.bg,
        border: Border(top: BorderSide(color: NightColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: NightType.body.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: enabled ? '说点什么……也可以只选上面' : '这一夜说完了',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: enabled ? NightColors.amber : NightColors.surfaceRaised,
                child: InkWell(
                  onTap: enabled ? onSend : null,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 19,
                    color: enabled ? NightColors.ink : NightColors.faint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
