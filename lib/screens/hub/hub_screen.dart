import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_mark.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 兴趣圈首页：一个圈一行，点一行就进那个圈。
///
/// 方案五的入口页 —— 用「喜爱」做入口，用 AI 做引擎。它刻意不铺内容流：
/// 每行只写这个圈今天的一个判断（没有判断就照实写没有），点进去才是干活的地方。
///
/// 作为 push 出来的页面，它是**在当前圈的配色下**渲染的（AppColors 是全 App
/// 唯一的运行时色组）；「首页属于品牌本身的墨金」这件事要等导航改成
/// 「首页 / 圈子 / 我的」三页签时一起做（见 design/xiai/design-plan.md）。
class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicState>();
    return WkPage(
      title: '兴趣圈',
      leading: IconButton(
        key: const ValueKey('hub-back'),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: '返回',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
        children: [
          const SizedBox(height: AppSpace.sm),
          const Text('今天', style: AppType.display),
          const SizedBox(height: AppSpace.sm),
          Text(
            '每个圈今天只交一个判断。点一行就进那个圈 —— 进去之后整屏会换成它的颜色。',
            style: AppType.read.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.xl),
          for (final pack in topics.available) ...[
            _CircleEntry(
              pack: pack,
              current: pack.id == topics.currentId,
              onTap: () => _enter(context, topics, pack),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          const SizedBox(height: AppSpace.sm),
          const WkNote(
            text: '今天还没有判断的圈会照实写「还没有判断」。判断的依据写在圈内那张'
                '小票上：用的是你自己的记录、公开数据，还是模型假设。',
          ),
        ],
      ),
    );
  }

  void _enter(BuildContext context, TopicState topics, TopicPack pack) {
    Navigator.of(context).maybePop();
    if (pack.id != topics.currentId) topics.switchTo(pack.id);
  }
}

class _CircleEntry extends StatelessWidget {
  const _CircleEntry({
    required this.pack,
    required this.current,
    required this.onTap,
  });

  final TopicPack pack;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = pack.today;
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('hub-${pack.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
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
                      style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: AppSpace.sm),
                  if (current) const WkTag('当前', filled: true),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.borderMed),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(pack.blurb,
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  if (today == null)
                    Text('进圈看今天的判断',
                        style: AppType.caption
                            .copyWith(color: AppColors.textSecondary))
                  else ...[
                    Text(today.label,
                        style: AppType.micro
                            .copyWith(color: AppColors.textTertiary)),
                    const SizedBox(width: AppSpace.sm),
                    if (today.hasValue) ...[
                      Text('${today.value}${today.unit}',
                          style: AppType.body.copyWith(
                            color: AppColors.amber,
                            fontWeight: FontWeight.w600,
                            fontFamilyFallback: AppType.numericFallback,
                          )),
                      const SizedBox(width: AppSpace.sm),
                      Text(today.verdict,
                          style: AppType.caption.copyWith(
                              color: AppColors.amberDim,
                              fontWeight: FontWeight.w600)),
                    ] else
                      Text(today.verdict,
                          style: AppType.caption
                              .copyWith(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
