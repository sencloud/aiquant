import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_mark.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_rail.dart';
import '../../core/topic/topic_state.dart';
import '../../core/topic/topic_today_screen.dart';
import '../../core/topic/topic_today_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'hub_state.dart';

/// 兴趣圈首页（App 首屏）：一个圈一行，点一行就进那个圈。
///
/// 三种状态，每种都真实可点：
///   1. **有判断**：大数 + 判定 + 时间轨 + 一句结论 + 小票（依据可追溯）；
///   2. **可问**：还没判断，但 AI 已经上线 —— 点「问一句」带着问题进对话；
///   3. **进圈看**：判断在圈内算（钱看盘后结论、钓鱼看实时出钓指数）。
///
/// 首页用品牌自己的墨金渲染，不属于任何单个圈；进圈之后整屏才换成那个圈的颜色。
class HubHomeTab extends StatelessWidget {
  const HubHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicState>();
    final packs = [...topics.available]..sort((a, b) {
        final av = resolveToday(a)?.hasValue == true ? 0 : 1;
        final bv = resolveToday(b)?.hasValue == true ? 0 : 1;
        return av.compareTo(bv);
      });

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
            Text('${packs.length} 个圈',
                style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        const Text('今天', style: AppType.display),
        const SizedBox(height: AppSpace.sm),
        Text(
          '每个圈今天只交一个判断。点一行就进那个圈 —— 进去之后整屏会换成它的颜色。',
          style: AppType.read.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.xl),
        for (final pack in packs) ...[
          _HubRow(pack: pack, current: pack.id == topics.currentId),
          const SizedBox(height: AppSpace.md),
        ],
        const SizedBox(height: AppSpace.sm),
        const WkNote(
          text: '今天没有判断的圈会照实写「还没有判断」——判断的依据写在圈内那张小票上：'
              '用的是你自己的记录、公开数据，还是模型假设。',
        ),
      ],
    );
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({required this.pack, required this.current});

  final TopicPack pack;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final today = resolveToday(pack);
    final hasValue = today != null && today.hasValue;
    final window = pack.window;

    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('hub-${pack.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => enterCircle(context, pack, tab: hasValue ? 0 : null),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TopicMark(pack.mark),
                  const SizedBox(width: AppSpace.sm),
                  Text(pack.name,
                      style:
                          AppType.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: AppSpace.sm),
                  if (current) const WkTag('当前', filled: true),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.borderMed),
                ],
              ),
              if (hasValue) ...[
                const SizedBox(height: AppSpace.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${today.value}${today.unit}',
                        style: AppType.display.copyWith(
                          fontSize: 34,
                          fontFamilyFallback: AppType.numericFallback,
                          color: AppColors.amber,
                        )),
                    const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(today.verdict,
                          style: AppType.body.copyWith(
                              color: AppColors.amberDim,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (today.rail != null) ...[
                  const SizedBox(height: AppSpace.md),
                  TopicRail(
                    cells: today.rail!,
                    nowPercent: today.nowPercent ?? 0.5,
                    legend: today.legend,
                    maxBar: 20,
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                Text(today.why, style: AppType.read),
                const SizedBox(height: AppSpace.md),
                TicketLine(text: today.ticket),
              ] else ...[
                const SizedBox(height: AppSpace.xs),
                Text(pack.blurb,
                    style: AppType.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    Text('今天还没有判断',
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                    const Spacer(),
                    if (window != null)
                      _ActionChip(
                        label: '记${window.startLabel}',
                        onTap: () => enterCircle(context, pack, tab: 1),
                      )
                    else if (pack.aiLive && (today?.jobs.isNotEmpty ?? false))
                      _ActionChip(
                        label: '问一句',
                        onTap: () => openJobInChat(context, today!.jobs.first),
                      )
                    else
                      Text('进圈看',
                          style: AppType.caption
                              .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 5),
          child: Text(label,
              style: AppType.micro.copyWith(color: AppColors.amberDim)),
        ),
      ),
    );
  }
}

/// 进圈：切到那个圈、记住要落在哪个页签，然后离开首页。
Future<void> enterCircle(BuildContext context, TopicPack pack,
    {int? tab}) async {
  final hub = context.read<HubState>();
  final topics = context.read<TopicState>();
  hub.enter(tab: tab);
  if (pack.id != topics.currentId) await topics.switchTo(pack.id);
}

/// 从圈内回到首页。
class HubEntryAction extends StatelessWidget {
  const HubEntryAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('hub-entry'),
      icon: const Icon(Icons.grid_view_rounded),
      tooltip: '兴趣圈',
      color: AppColors.amber,
      onPressed: () => context.read<HubState>().leave(),
    );
  }
}
