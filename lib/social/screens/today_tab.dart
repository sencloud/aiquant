import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_state.dart';
import '../../screens/hub/hub_screen.dart' show enterCircle;
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_feed.dart';
import '../social_state.dart';
import '../social_widgets.dart';
import 'record_event_sheet.dart';
import 'speak_screen.dart';

/// 「今天」页签：不是信息流，是**今天发生过的三件事**。
///
/// 事从哪来：你自己的记录（渔获日志、本机记下的事）。App 不生成
/// 「别人钓到了一条鱼」——所以没有事的时候，这里就是空的，并且给你一个
/// 三秒能做完的入口（[RecordEventSheet]）。
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<TopicState>().current;
    final state = context.watch<SocialState>();
    final feed = buildToday(context, pack, state);
    final waterline = pack.socialWaterline(context);
    final n = feed.events.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.amber),
            const SizedBox(width: AppSpace.sm),
            Text('喜爱',
                style: AppType.title.copyWith(letterSpacing: 1, fontSize: 18)),
            const Spacer(),
            IconButton(
              key: const ValueKey('today-rules'),
              tooltip: '这里的规矩',
              icon: const Icon(Icons.info_outline_rounded),
              color: AppColors.textSecondary,
              onPressed: () => showHouseRules(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(n == 0 ? '今天还没有事' : '今天，圈里有${_cn(n)}件事',
            style: AppType.display),
        const SizedBox(height: AppSpace.sm),
        Text('先有事，才有话。点一件事，话就跟着它走。',
            style: AppType.read.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpace.xl),
        if (n == 0)
          _EmptyToday(pack: pack)
        else
          for (final e in feed.events)
            SocialEventCard(
              key: ValueKey('event-${e.id}'),
              event: e,
              posts: feed.postsOn(state, e),
              onSpeak: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SpeakScreen(initial: e.target))),
              onOpenCircle: () => enterCircle(context, pack),
              onWithdraw: (p) => state.withdraw(p.id),
            ),
        if (waterline.isNotEmpty) _SharedThing(pack: pack, counts: waterline),
        if (feed.residents.isNotEmpty) _ResidentRow(feed: feed),
        const SizedBox(height: AppSpace.lg),
        WkNote(
          text: n == 0
              ? '这里不生成内容：没有事就是没有事。记下第一件事，它就成了别人认识你的由头。'
              : '今天只有这几件。没有第四件的时候，这里就是空的 —— 这是故意的。',
        ),
      ],
    );
  }
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday({required this.pack});

  final TopicPack pack;

  @override
  Widget build(BuildContext context) {
    return WkEmpty(
      key: const ValueKey('today-empty'),
      icon: Icons.edit_note_rounded,
      title: '还没有可以挂话的事',
      hint: '事可以是：一条渔获、一支新豆子、猫的体重、一张照片。'
          '记下来之后，「说一句」才有地方落。',
      action: WkPrimaryButton(
        label: '记一件今天的事',
        icon: Icons.add_rounded,
        onPressed: () => showRecordEventSheet(context, pack),
      ),
    );
  }
}

/// 共有物：这个圈里你们一起留下的东西。
class _SharedThing extends StatelessWidget {
  const _SharedThing({required this.pack, required this.counts});

  final TopicPack pack;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold<int>(0, (a, b) => a + b);
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('你们一起留下的记录', style: AppType.section),
              const Spacer(),
              Text('近 14 天', style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          WkWaterline(counts: counts),
          const SizedBox(height: AppSpace.sm),
          Text('一共 $total 条记录',
              style: AppType.micro.copyWith(
                color: AppColors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: AppSpace.sm),
          Text('这个东西不属于谁 —— 你们只是都往这里放东西。',
              style: AppType.caption.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 圈里的 AI 居民。他们也要守规矩 03：先送东西，才能跟你说话。
class _ResidentRow extends StatelessWidget {
  const _ResidentRow({required this.feed});

  final TodayFeed feed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.xl),
        const Row(
          children: [
            Text('这个圈里的 AI 居民', style: AppType.section),
            Spacer(),
            WkTag('AI 居民', filled: true),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        WkGroup(
          children: [
            for (final r in feed.residents)
              WkRow(
                key: ValueKey('resident-${r.id}'),
                icon: Icons.smart_toy_outlined,
                title: '${r.name} · AI 居民',
                subtitle: r.blurb,
                onTap: () => enterCircle(context, feed.circle, tab: 0),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const WkNote(
          text: '他是标明的 AI：名字后面带着标，资料页写明谁在维护。'
              '他也得先送东西才能跟你说话 —— 规矩不只为真人立。',
        ),
      ],
    );
  }
}

String _cn(int n) {
  const words = ['零', '一', '两', '三', '四', '五', '六', '七', '八', '九', '十'];
  return words[n.clamp(0, words.length - 1)];
}
