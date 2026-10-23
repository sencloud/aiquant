import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({
    super.key,
    required this.state,
    required this.onOpenCharacter,
    required this.onContinue,
  });

  final StoryState state;
  final ValueChanged<StoryCharacter> onOpenCharacter;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final run = state.run;
    final characters = [...state.season.characters]
      ..sort((a, b) => a.order.compareTo(b.order));

    return Column(
      children: [
        const NightBar(
          title: '通讯录',
          subtitle: '00:47 · 临海 · 雨',
          actions: [PixelTag('AI · 虚构', color: NightColors.rain)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              Text('你只在这里\n待七天。',
                  style:
                      NightType.display.copyWith(fontSize: 27, height: 1.25)),
              const SizedBox(height: 10),
              Text('第八天清晨，第一班车。\n夜里睡不着，通讯录里六个名字。',
                  style: NightType.read.copyWith(height: 1.85)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text('未接来电', style: NightType.title.copyWith(fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(
                      '${state.season.characters.where((c) => state.isCharacterEnabled(c.id)).length}',
                      style: NightType.mono.copyWith(color: NightColors.heart)),
                  const Spacer(),
                  Text('六位 · 都标了 AI',
                      style: NightType.micro.copyWith(letterSpacing: 0.6)),
                ],
              ),
              const SizedBox(height: 10),
              for (final c in characters) ...[
                _ContactTile(
                  character: c,
                  state: state,
                  onTap: () {
                    final enabled = state.isCharacterEnabled(c.id);
                    if (!enabled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: NightColors.surfaceRaised,
                          content: Text(
                            state.config.notice.trim().isNotEmpty
                                ? state.config.notice
                                : '${c.name}这一条暂时没开。',
                            style: NightType.caption.copyWith(
                              color: NightColors.paper,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    if (run != null &&
                        run.characterId == c.id &&
                        !run.finished) {
                      onContinue();
                    } else {
                      onOpenCharacter(c);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
              const NightNote(
                '六位都是 AI 扮演的虚构角色，全部成年人。名字旁的 AI 标说明身份；'
                '故事里的关系不会延续到现实。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.character,
    required this.state,
    required this.onTap,
  });

  final StoryCharacter character;
  final StoryState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final run = state.run;
    final active =
        run != null && run.characterId == character.id && !run.finished
            ? run
            : null;
    final mine = active != null;
    final enabled = state.isCharacterEnabled(character.id);
    final completed =
        state.unlockedEndings.any((id) => id.startsWith(character.id));

    final subtitle = active != null
        ? '第 ${active.night} 夜 · 继续'
        : !enabled
            ? (character.routeOpen ? '暂未开放' : character.routeNote)
            : completed
                ? '已看完 · 可以再走一次'
                : '未接来电 · 第 1 夜';

    return Opacity(
      opacity: enabled ? 1 : 0.58,
      child: Material(
        color: mine ? NightColors.surfaceRaised : NightColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: mine ? NightColors.amber : Colors.transparent,
                  width: 2,
                ),
                top: const BorderSide(color: NightColors.borderSoft),
                right: const BorderSide(color: NightColors.borderSoft),
                bottom: const BorderSide(color: NightColors.borderSoft),
              ),
            ),
            child: Row(
              children: [
                PixelAvatar(character: character, size: 62),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(character.nameWithAge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NightType.title.copyWith(fontSize: 16)),
                          ),
                          const SizedBox(width: 7),
                          const PixelTag('AI', color: NightColors.rain),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(character.status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NightType.caption.copyWith(
                            color: NightColors.muted,
                          )),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(subtitle,
                              style: NightType.micro.copyWith(
                                color: mine
                                    ? NightColors.amber
                                    : NightColors.faint,
                                letterSpacing: 0.5,
                              )),
                          const Spacer(),
                          if (active != null)
                            HeartRow(hearts: active.hearts, size: 12),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  enabled
                      ? Icons.chevron_right_rounded
                      : Icons.phone_missed_rounded,
                  size: 18,
                  color: enabled ? NightColors.muted : NightColors.faint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
