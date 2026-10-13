import 'package:flutter/material.dart';

import '../../screens/assistant/assistant_screen.dart';
import '../../screens/hub/hub_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'topic_mark.dart';
import 'topic_pack.dart';
import 'topic_rail.dart';
import 'topic_registry.dart';
import 'topic_today.dart';
import 'topic_today_service.dart';

/// 圈内「今天」：这个圈今天只交一个判断。
///
/// 判断来自 [resolveToday]（静态模板 + 本地记录算出来的天数），算不出就照实写
/// 「还没有判断」。签名是那条时间轨，与首页共用 [TopicRail]。
class TopicTodayScreen extends StatelessWidget {
  const TopicTodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = topicOf(context, listen: true);
    final today = resolveToday(pack);
    if (today == null) {
      return const WkPage(
        title: '今天',
        child: WkEmpty(
          icon: Icons.hourglass_empty_rounded,
          title: '这个圈还没有今天的判断',
          hint: '接上数据之后，这里会给出今天该做什么。',
        ),
      );
    }
    return WkPage(
      title: '今天',
      actions: const [HubEntryAction()],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          TodayCard(pack: pack, today: today),
          const SizedBox(height: AppSpace.xl),
          if (today.jobs.isNotEmpty) ...[
            WkGroup(
              header: 'AI 能替你做的事',
              children: [
                for (final job in today.jobs)
                  WkRow(
                    key: ValueKey('job-${job.title}'),
                    icon: job.icon,
                    title: job.title,
                    subtitle: job.note,
                    trailing: pack.aiLive
                        ? null
                        : WkTag('即将开放', tone: AppColors.textTertiary),
                    onTap:
                        pack.aiLive ? () => openJobInChat(context, job) : null,
                  ),
              ],
            ),
            WkNote(
              title: pack.aiLive ? null : '这个圈还在上线中',
              text: pack.aiLive
                  ? '点一条就把问题填进对话，你可以改完再发；它会先读你在这个圈的记录再回答。'
                  : '这个圈的 AI 还在上线中，现在这几条是只读预览；'
                      '上线后点一条就带着问题进对话，它会先读你在这个圈的记录。',
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          const WkNote(
            text: '每个圈今天只交一个判断。没有数据的圈会照实写「还没有判断」，不编数字；'
                '每次判断都带一张小票，写清依据来自你自己的记录、公开数据，还是模型假设。',
          ),
        ],
      ),
    );
  }
}

/// 带着问题进对话，但不自动发送：一轮对话 1 喜点，发不发由用户决定。
void openJobInChat(BuildContext context, TopicJob job) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AssistantScreen(
        launch: AssistantLaunch(initialMessage: job.ask),
      ),
    ),
  );
}

/// 今日判断卡：徽记 + 数 + 判定 + 时间轨 + 一句结论 + 一张小票。
///
/// 首页与圈内「今天」页共用同一张卡 —— 同一枚签名在两处必须长得一样。
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.pack,
    required this.today,
    this.showHeader = true,
    this.onTicketTap,
  });

  final TopicPack pack;
  final TopicToday today;
  final bool showHeader;
  final VoidCallback? onTicketTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                TopicMark(pack.mark),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(pack.name,
                      style:
                          AppType.body.copyWith(fontWeight: FontWeight.w600)),
                ),
                WkTag(today.label),
              ],
            ),
            const SizedBox(height: AppSpace.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                today.value ?? '—',
                style: AppType.display.copyWith(
                  fontSize: 34,
                  fontFamilyFallback: AppType.numericFallback,
                  color:
                      today.hasValue ? AppColors.amber : AppColors.textTertiary,
                ),
              ),
              if (today.unit.isNotEmpty) ...[
                const SizedBox(width: AppSpace.xs),
                Text(today.unit,
                    style:
                        AppType.body.copyWith(color: AppColors.textSecondary)),
              ],
              const SizedBox(width: AppSpace.sm),
              Flexible(
                child: Text(
                  today.verdict,
                  style: AppType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: today.hasValue
                        ? AppColors.amberDim
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (today.rail != null) ...[
            const SizedBox(height: AppSpace.md),
            TopicRail(
              cells: today.rail!,
              nowPercent: today.nowPercent ?? 0.5,
              legend: today.legend,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(today.why, style: AppType.read),
          const SizedBox(height: AppSpace.md),
          TicketLine(text: today.ticket, onTap: onTicketTap),
        ],
      ),
    );
  }
}

/// 小票行：一条发丝线之上写清「凭什么」。
class TicketLine extends StatelessWidget {
  const TicketLine({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        decoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 14, color: AppColors.textTertiary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(text,
                  style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }
}
