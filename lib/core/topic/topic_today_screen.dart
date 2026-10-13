import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../../screens/hub/hub_screen.dart';
import 'topic_mark.dart';
import 'topic_pack.dart';
import 'topic_registry.dart';
import 'topic_today.dart';

/// 圈内「今天」：这个圈今天只交一个判断。
///
/// 签名是那条时间轨 —— 把「今天什么时候该去」压成一条不断行的轨道，「现在」
/// 是一根细线，最好的时段是最深的两格。换圈时轨道换色、换尺度（钓鱼按小时、
/// 咖啡与养猫按天）。
class TopicTodayScreen extends StatelessWidget {
  const TopicTodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = topicOf(context, listen: true);
    final today = pack.today;
    if (today == null) {
      return WkPage(
        title: '今天',
        actions: const [_HubAction()],
        child: const WkEmpty(
          icon: Icons.hourglass_empty_rounded,
          title: '这个圈还没有今天的判断',
          hint: '接上数据之后，这里会给出今天该做什么。',
        ),
      );
    }
    return WkPage(
      title: '今天',
      actions: const [_HubAction()],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          _TodayCard(pack: pack, today: today),
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
                    // 服务端还没上这个圈时不给可点的入口：点了必然失败。
                    onTap: pack.aiLive ? () => _ask(context, job) : null,
                  ),
              ],
            ),
            WkNote(
              title: pack.aiLive ? null : '这个圈还在上线中',
              text: pack.aiLive
                  ? '点一条就带着问题进对话，不用自己想怎么问。'
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

  void _ask(BuildContext context, TopicJob job) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.title, style: AppType.title),
            const SizedBox(height: AppSpace.sm),
            Text(job.ask, style: AppType.read.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.lg),
            WkNote(
              text: '把这句话发进「${topicOf(context).name}」的对话里，'
                  'AI 会先读这个圈的记录再回答。',
            ),
          ],
        ),
      ),
    );
  }
}

/// 「今天」页顶栏的兴趣圈入口。
///
/// 新开的四个圈没有「对话」页签（服务端人设还没上线），所以这个入口不能只挂在
/// 对话页上 —— 否则未登录用户进了圈就出不来。
class _HubAction extends StatelessWidget {
  const _HubAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('today-hub'),
      icon: const Icon(Icons.grid_view_rounded),
      tooltip: '兴趣圈',
      color: AppColors.amber,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HubScreen()),
      ),
    );
  }
}

/// 今日判断卡：徽记 + 数 + 判定 + 时间轨 + 一句结论 + 一张小票。
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.pack, required this.today});

  final TopicPack pack;
  final TopicToday today;

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
          Row(
            children: [
              TopicMark(pack.mark),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(pack.name,
                    style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              WkTag(today.label),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                today.value ?? '—',
                style: AppType.display.copyWith(
                  fontSize: 34,
                  fontFamilyFallback: AppType.numericFallback,
                  color: today.hasValue ? AppColors.amber : AppColors.textTertiary,
                ),
              ),
              if (today.unit.isNotEmpty) ...[
                const SizedBox(width: AppSpace.xs),
                Text(today.unit,
                    style: AppType.body.copyWith(color: AppColors.textSecondary)),
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
            _Rail(
              cells: today.rail!,
              nowPercent: today.nowPercent ?? 0.5,
              legend: today.legend,
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(today.why, style: AppType.read),
          const SizedBox(height: AppSpace.md),
          _Ticket(text: today.ticket),
        ],
      ),
    );
  }
}

/// 时间轨：八格 + 「现在」一根细线 + 一行刻度。
class _Rail extends StatelessWidget {
  const _Rail({required this.cells, required this.nowPercent, this.legend});

  final List<RailCell> cells;
  final double nowPercent;
  final List<String>? legend;

  @override
  Widget build(BuildContext context) {
    const maxBar = 28.0;
    final legendStyle = AppType.micro.copyWith(
      color: AppColors.textTertiary,
      fontFamilyFallback: AppType.numericFallback,
      fontWeight: FontWeight.w400,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: maxBar + 6,
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: 6,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < cells.length; i++) ...[
                        Expanded(
                          child: Container(
                            height: 6 + cells[i].height * (maxBar - 6),
                            decoration: BoxDecoration(
                              color: cells[i].best
                                  ? AppColors.amber
                                  : cells[i].good
                                      ? AppColors.amber.withValues(alpha: 0.38)
                                      : AppColors.borderDim,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                  bottom: Radius.circular(2)),
                            ),
                          ),
                        ),
                        if (i != cells.length - 1) const SizedBox(width: 3),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: nowPercent.clamp(0.0, 1.0) * (constraints.maxWidth - 1),
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Container(
                      color: AppColors.textPrimary.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          if (legend != null && legend!.length == 3) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Text(legend![0], style: legendStyle),
                const Spacer(),
                Row(children: [
                  Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: AppColors.amber, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(legend![1],
                      style: legendStyle.copyWith(color: AppColors.textSecondary)),
                ]),
                const Spacer(),
                Text(legend![2], style: legendStyle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 小票行：一条虚线之上写清「凭什么」。
class _Ticket extends StatelessWidget {
  const _Ticket({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(text,
                style: AppType.micro.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}
