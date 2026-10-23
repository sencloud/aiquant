import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({
    super.key,
    required this.state,
    required this.onContinue,
    required this.onRestart,
  });

  final StoryState state;
  final VoidCallback onContinue;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final run = state.run;
    final character = state.activeCharacter;
    final slots = <StoryEnding>[
      for (final id in const ['linxia', 'suyu', 'chenye'])
        ...?state.season.routeOf(id)?.endings,
      state.trueEnding,
    ];

    return Column(
      children: [
        const NightBar(
          title: '我',
          subtitle: '临海 · 第 8 天之前',
          actions: [PixelTag('试玩版', color: NightColors.amber)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            children: [
              _profile(run, character),
              const SizedBox(height: 18),
              Text('结局册',
                  style: NightType.title.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.6,
                    color: NightColors.amber,
                  )),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, box) {
                final w = (box.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < state.season.endingSlots; i++)
                      SizedBox(
                        width: w,
                        child: _EndingSlot(
                          ending: i < slots.length ? slots[i] : null,
                          unlocked: i < slots.length &&
                              (slots[i].id == state.trueEnding.id
                                  ? state.trueEndingUnlocked
                                  : state.unlockedEndings
                                      .contains(slots[i].id)),
                          index: i + 1,
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 22),
              Text('设置',
                  style: NightType.title.copyWith(
                    fontSize: 12,
                    letterSpacing: 1.6,
                    color: NightColors.amber,
                  )),
              const SizedBox(height: 8),
              _row('重看开场', Icons.replay_rounded, () => state.replayIntro()),
              _row('清除试玩存档', Icons.delete_outline_rounded,
                  () => _confirmReset(context)),
              _row('关于与 AI 说明', Icons.info_outline_rounded,
                  () => _about(context)),
              const SizedBox(height: 18),
              const NightNote(
                '《喜爱 · 天亮以前》试玩版。故事虚构，角色由 AI 扮演，全部成年人。'
                '你在这里说的话只用于这次故事，不进入投研档案。',
              ),
              const SizedBox(height: 16),
              Center(
                child: Text('喜爱 · 天亮以前 0.1',
                    style: NightType.micro.copyWith(letterSpacing: 1.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profile(StoryRun? run, StoryCharacter? character) {
    if (run == null || character == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NightColors.surface,
          border: Border.all(color: NightColors.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('还没有接通的电话。', style: NightType.title.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Text('通讯录里有三个未接来电。回拨一个，走完七夜。',
                style: NightType.caption.copyWith(height: 1.6)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NightColors.surface,
        border: Border.all(color: NightColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PixelAvatar(character: character, size: 58),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(character.name,
                        style: NightType.title.copyWith(fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(
                      run.finished
                          ? '第 7 夜 · 已走到结局'
                          : '第 ${run.night} 夜 / 7 · ${run.nightComplete ? "夜终" : "通话中"}',
                      style: NightType.caption,
                    ),
                  ],
                ),
              ),
              HeartRow(hearts: run.hearts, size: 13),
            ],
          ),
          const SizedBox(height: 12),
          if (run.finished)
            PixelButton(
              label: '再走一次',
              icon: Icons.refresh_rounded,
              onPressed: onRestart,
            )
          else
            PixelButton(
              label: run.nightComplete ? '收下这一夜' : '继续第 ${run.night} 夜',
              icon: Icons.nightlight_round,
              onPressed: onContinue,
            ),
        ],
      ),
    );
  }

  Widget _row(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: NightColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: NightColors.borderSoft),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: NightColors.muted),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: NightType.body.copyWith(fontSize: 14))),
              const Icon(Icons.chevron_right_rounded,
                  size: 17, color: NightColors.faint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NightColors.surface,
        title: const Text('清除试玩存档？', style: NightType.title),
        content: Text('会清掉当前这一夜、心级和已解锁的结局。主 App 的数据不动。',
            style: NightType.caption.copyWith(height: 1.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想', style: NightType.caption),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清除',
                style: NightType.caption.copyWith(color: NightColors.heart)),
          ),
        ],
      ),
    );
    if (ok == true) await state.resetAll();
  }

  Future<void> _about(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NightColors.surface,
        title: const Text('关于《天亮以前》', style: NightType.title),
        content: Text(
          '这是一个虚构的短篇故事。六位角色由 AI 扮演，全部成年人；'
          '故事里的关系不会延续到现实。\n\n'
          '试玩版只开放林夏线；苏予、陈野的路线在制作中。\n'
          '不卖好感、不卖结局、不抽卡。',
          style: NightType.caption.copyWith(height: 1.8),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: NightType.caption),
          ),
        ],
      ),
    );
  }
}

class _EndingSlot extends StatelessWidget {
  const _EndingSlot({
    required this.ending,
    required this.unlocked,
    required this.index,
  });

  final StoryEnding? ending;
  final bool unlocked;
  final int index;

  @override
  Widget build(BuildContext context) {
    final e = ending;
    return Container(
      height: 104,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: unlocked ? NightColors.surface : NightColors.bg,
        border: Border.all(
          color: unlocked ? NightColors.amberDim : NightColors.borderSoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(index.toString().padLeft(2, '0'),
              style: NightType.micro.copyWith(
                color: unlocked ? NightColors.amber : NightColors.faint,
                letterSpacing: 1.2,
              )),
          const Spacer(),
          Text(
            unlocked && e != null ? e.title : '？？？',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NightType.title.copyWith(
              fontSize: 14,
              color: unlocked ? NightColors.paper : NightColors.faint,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            unlocked && e != null ? e.quote : '还没走到这里。',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NightType.micro.copyWith(
              color: unlocked ? NightColors.muted : NightColors.faint,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
