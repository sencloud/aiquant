import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_state.dart';
import '../../screens/hub/hub_screen.dart' show enterCircle;
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../social_feed.dart';
import '../social_widgets.dart';
import 'record_event_sheet.dart';

/// 一个人的时候：没有朋友的账号，这个 App 也是完整的。
///
/// 这是「不读通讯录」的另一半 —— 不搬关系，就必须让人一个人也有事可做。
class AloneScreen extends StatelessWidget {
  const AloneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = context.watch<TopicState>().current;
    final residents = residentsOf(pack);

    return WkPage(
      title: '一个人的时候',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          const Text('不用把通讯录搬过来。', style: AppType.display),
          const SizedBox(height: AppSpace.sm),
          Text('没有朋友的账号，这里也是完整的：一个人可以先记一件事，'
              '以后它就是别人认识你的由头。',
              style: AppType.read.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpace.xl),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('开一个圈', style: AppType.section),
                const SizedBox(height: AppSpace.sm),
                Text('圈不需要先有人。开圈的时候会住进一位 AI 居民 ——'
                    '他会陪你把它填满，等人来。',
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpace.md),
                WkTagButton(
                  label: '开一个圈',
                  onTap: () => showRecordEventSheet(context, pack),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const Row(
            children: [
              Text('今天可以先聊聊', style: AppType.section),
              Spacer(),
              WkTag('AI 居民', filled: true),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (residents.isEmpty)
            const WkNote(text: '这个圈还没有 AI 居民。')
          else
            WkGroup(
              children: [
                for (final r in residents)
                  WkRow(
                    key: ValueKey('alone-${r.id}'),
                    icon: Icons.smart_toy_outlined,
                    title: '${r.name} · AI 居民',
                    subtitle: r.blurb,
                    onTap: () => enterCircle(context, pack, tab: 0),
                  ),
              ],
            ),
          const SizedBox(height: AppSpace.sm),
          const WkNote(
            text: '他是标明的 AI。他也得守规矩 03：先送东西，才能跟你说话。',
          ),
          const SizedBox(height: AppSpace.xl),
          WkPrimaryButton(
            label: '记一件今天的事',
            icon: Icons.add_rounded,
            onPressed: () => showRecordEventSheet(context, pack),
          ),
        ],
      ),
    );
  }
}
