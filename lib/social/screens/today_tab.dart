import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_feed.dart';
import '../social_state.dart';
import '../social_widgets.dart';
import 'record_event_sheet.dart';
import 'speak_screen.dart';

/// 「今天的事」：不是信息流，是**今天你自己记下的那几件事**。
///
/// App 不生成内容，也没有别人往里写东西 —— 今天没有事，这里就是空的，
/// 并且给你一个三秒能做完的入口（[showRecordEventSheet]）。
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SocialState>();
    final feed = buildToday(state);
    final n = feed.events.length;

    return WkPage(
      title: '今天的事',
      actions: [
        IconButton(
          key: const ValueKey('today-rules'),
          tooltip: '这里的规矩',
          icon: const Icon(Icons.info_outline_rounded, size: 22),
          onPressed: () => showHouseRules(context),
        ),
        const SizedBox(width: AppSpace.xs),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          Text(n == 0 ? '今天还没有事' : '今天记下了${_cn(n)}件事',
              style: AppType.title.copyWith(fontSize: 20)),
          const SizedBox(height: AppSpace.sm),
          Text('先有事，才有话。点一件事，话就跟着它走。',
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: AppSpace.lg),
          if (n == 0)
            WkEmpty(
              key: const ValueKey('today-empty'),
              icon: Icons.edit_note_rounded,
              title: '还没有可以挂话的事',
              hint: '事可以是：一条记录、一个数、一张照片、今天做过的一件事。'
                  '记下来之后，「说一句」才有地方落。',
              action: WkPrimaryButton(
                label: '记一件今天的事',
                icon: Icons.add_rounded,
                onPressed: () => showRecordEventSheet(context),
              ),
            )
          else
            for (final e in feed.events)
              SocialEventCard(
                key: ValueKey('event-${e.id}'),
                event: e,
                posts: feed.postsOn(state, e),
                onSpeak: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SpeakScreen(initial: e.target))),
                onWithdraw: (p) => state.withdraw(p.id),
              ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: WkPrimaryButton(
                  label: '记一件今天的事',
                  icon: Icons.add_rounded,
                  onPressed: () => showRecordEventSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          WkNote(
            text: n == 0
                ? '这里不生成内容：没有事就是没有事。'
                : '今天只有这几件。没有第四件的时候，这里就是空的 —— 这是故意的。',
          ),
        ],
      ),
    );
  }
}

String _cn(int n) {
  const words = ['零', '一', '两', '三', '四', '五', '六', '七', '八', '九', '十'];
  return words[n.clamp(0, words.length - 1)];
}
