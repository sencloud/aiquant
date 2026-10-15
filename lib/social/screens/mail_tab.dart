import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_state.dart';
import '../social_widgets.dart';
import 'alone_screen.dart';
import 'echo_screen.dart';
import 'gift_screen.dart';
import 'speak_screen.dart';

/// 「信箱」：话挂在东西上，所以这里不按人分组。
///
/// 三区：到你手上的 / 你挂出去的话 / 你送出去的。
/// **没有 1:1 会话列表** —— 这是设计里最容易被要求加回来的一条，先不加。
class MailTab extends StatelessWidget {
  const MailTab({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<TopicState>().current;
    final state = context.watch<SocialState>();
    final mine = state.posts.where((p) => p.delivered).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
      children: [
        const Text('信箱', style: AppType.display),
        const SizedBox(height: AppSpace.sm),
        Text('这里的话都挂着东西。没有「在吗」，也没有已读 —— '
            '需要你回的话会一直放在这儿，不催。',
            style: AppType.read.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpace.xl),
        WkGroup(
          children: [
            WkRow(
              key: const ValueKey('mail-echo'),
              icon: Icons.schedule_rounded,
              title: '回声',
              subtitle: '${state.inFlight.length} 条在路上 · 到他手里之前都能收回',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const EchoScreen())),
            ),
            WkRow(
              key: const ValueKey('mail-alone'),
              icon: Icons.person_outline_rounded,
              title: '一个人的时候',
              subtitle: '不读通讯录，一个人也能用',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AloneScreen())),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            const Text('到你手上的', style: AppType.section),
            const Spacer(),
            Text('0 条', style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const WkNote(
          text: '还没有人给你递话。真人的池子还没开 —— 现在圈里只有你和 AI 居民，'
              '他们的话会出现在对应的那件事下面。',
        ),
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            const Text('你挂出去的话', style: AppType.section),
            const Spacer(),
            Text('${mine.length} 条',
                style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (mine.isEmpty)
          const WkNote(text: '还没有。先去「今天」记一件事，再说第一句。')
        else
          for (final p in mine)
            SocialPostTile(key: ValueKey('mail-${p.id}'), post: p),
        const SizedBox(height: AppSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: WkTagButton(
            label: '去说一句',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SpeakScreen())),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            const Text('你送出去的', style: AppType.section),
            const Spacer(),
            Text('${state.gifts.length} 样',
                style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (state.gifts.isEmpty)
          const WkNote(text: '还没有送出去的东西。想跟谁开始，先送一样。')
        else
          WkGroup(
            children: [
              for (final g in state.gifts)
                WkRow(
                  key: ValueKey('gift-${g.id}'),
                  icon: Icons.card_giftcard_rounded,
                  title: g.title,
                  subtitle: '送给 ${g.toName}${g.note.isEmpty ? '' : ' · ${g.note}'}',
                ),
            ],
          ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerLeft,
          child: WkTagButton(
            label: '送一样东西',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const GiftScreen())),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Center(
          child: WkTagButton(
            label: '这里的规矩',
            onTap: () => showHouseRules(context),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('当前圈：${pack.name}',
            textAlign: TextAlign.center,
            style: AppType.micro.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}
