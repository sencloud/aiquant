import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';

class CharacterSheet extends StatelessWidget {
  const CharacterSheet({
    super.key,
    required this.character,
    required this.onStarted,
  });

  final StoryCharacter character;
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context) {
    final story = context.watch<StoryState>();
    final active = story.run != null &&
            story.run!.characterId == character.id &&
            !story.run!.finished
        ? story.run
        : null;
    final completed =
        story.unlockedEndings.any((id) => id.startsWith(character.id));
    final enabled = story.isCharacterEnabled(character.id);

    return Theme(
      data: buildNightTheme(),
      child: Scaffold(
        backgroundColor: NightColors.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: NightBackdrop(stars: false)),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  NightBar(
                    title: character.name,
                    subtitle: '${character.city} · ${character.job}',
                    onBack: () => Navigator.of(context).pop(),
                    actions: const [
                      PixelTag('AI · 虚构', color: NightColors.rain),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      children: [
                        _portrait(enabled),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Flexible(
                              child: Text(character.nameWithAge,
                                  style:
                                      NightType.display.copyWith(fontSize: 24)),
                            ),
                            const SizedBox(width: 8),
                            const PixelTag('AI', color: NightColors.rain),
                            const Spacer(),
                            if (completed)
                              const PixelTag('已看完', color: NightColors.good),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                            '${character.city} · ${character.job} · ${character.nightWindow}',
                            style: NightType.caption),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in character.tags)
                              PixelTag(t, color: character.accent),
                          ],
                        ),
                        const SizedBox(height: 16),
                        NightNote('「${character.quote}」'),
                        const SizedBox(height: 18),
                        _section('TA 的夜晚'),
                        const SizedBox(height: 8),
                        _infoRow('出没', character.nightWindow),
                        _infoRow('状态', character.status),
                        _infoRow(
                            '路线',
                            enabled
                                ? '第一季 · 7 夜'
                                : (character.routeOpen ? '暂未开放' : '第二季')),
                        const SizedBox(height: 20),
                        if (active != null) ...[
                          PixelButton(
                            label: '继续第 ${active.night} 夜',
                            icon: Icons.nightlight_round,
                            onPressed: () {
                              onStarted();
                              Navigator.of(context).pop();
                            },
                          ),
                          const SizedBox(height: 8),
                          const Center(
                            child: Text('今晚已经接通，接着上次的往下说。',
                                style: NightType.micro),
                          ),
                        ] else if (enabled)
                          PixelButton(
                            label: completed ? '再走一次' : '回拨这个号码',
                            icon: Icons.phone_in_talk_rounded,
                            onPressed: () => _start(context, story),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PixelButton(
                                label: character.routeOpen
                                    ? '暂未开放'
                                    : '第 1 夜 · 制作中',
                                icon: Icons.schedule_rounded,
                                onPressed: null,
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                    character.routeOpen
                                        ? '这一条被运营暂时关上了。'
                                        : '立绘、档案、动态已经好了；路线在下一刀补。',
                                    textAlign: TextAlign.center,
                                    style: NightType.micro),
                              ),
                            ],
                          ),
                        const SizedBox(height: 14),
                        const NightNote(
                          'TA 是 AI 扮演的虚构角色，所有角色均为成年人。'
                          '故事里的关系不会延续到现实；不转账、不见面、不越界。',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, StoryState story) async {
    await story.startRoute(character.id);
    if (!context.mounted) return;
    onStarted();
    Navigator.of(context).pop();
  }

  Widget _portrait(bool enabled) {
    return Container(
      height: 340,
      width: double.infinity,
      decoration: BoxDecoration(
        color: NightColors.surface,
        border: Border.all(color: NightColors.border),
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 64,
                height: 88,
                child: PixelPortrait(character: character),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC0E1118)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  PixelTag(
                      enabled ? '未接来电' : (character.routeOpen ? '暂未开放' : '第二季'),
                      color: character.accent),
                  const Spacer(),
                  Text('立绘 · 试作',
                      style: NightType.micro.copyWith(letterSpacing: 2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String text) {
    return Text(text,
        style: NightType.title.copyWith(
          fontSize: 12,
          letterSpacing: 1.4,
          color: NightColors.amber,
        ));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(label, style: NightType.micro.copyWith(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: NightType.caption.copyWith(
                  color: NightColors.paper,
                  height: 1.6,
                )),
          ),
        ],
      ),
    );
  }
}
