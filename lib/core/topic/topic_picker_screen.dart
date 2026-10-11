import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import 'topic_pack.dart';
import 'topic_state.dart';

/// 全新安装首启：选一个喜爱的主题。之后随时可以在「我的 → 切换主题」里换。
class TopicPickerScreen extends StatelessWidget {
  const TopicPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicState>();
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              Text(
                '喜爱',
                textAlign: TextAlign.center,
                style: AppType.display.copyWith(
                  fontFamilyFallback: AppType.readFallback,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                '喜爱什么，就有什么',
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              Text(
                '先选一个你喜爱的',
                style: AppType.section.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpace.md),
              for (final p in topics.available) ...[
                TopicCard(
                  pack: p,
                  onTap: () {
                    Analytics.instance
                        .track('topic_pick', {'topic': p.id});
                    context.read<TopicState>().completePick(p.id);
                  },
                ),
                const SizedBox(height: AppSpace.md),
              ],
              const Spacer(),
              Text(
                '随时可在「我的 → 切换主题」里换，账号和喜点通用',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一个主题的卡片：用该主题自己的主色，不受当前主题配色影响。
class TopicCard extends StatelessWidget {
  const TopicCard({
    super.key,
    required this.pack,
    required this.onTap,
    this.selected = false,
  });

  final TopicPack pack;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final pal = pack.palette;
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: ValueKey('topic-card-${pack.id}'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? pal.brand : AppColors.borderDim,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: pal.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(pack.icon, color: pal.brand, size: 26),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.name,
                          style: AppType.section.copyWith(color: pal.brand),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          pack.slogan,
                          style: AppType.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      pack.blurb,
                      style: AppType.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? pal.brand : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 切换主题面板（「我的 → 切换主题」与长按对话页标题共用）。
Future<void> showTopicSwitcher(BuildContext context) async {
  final topics = context.read<TopicState>();
  if (!topics.canSwitch) return;
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bgBase,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('切换主题',
                textAlign: TextAlign.center,
                style:
                    AppType.section.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpace.xs),
            Text('整个 App 会换成对应主题；账号、喜点通用，对话记录各自保留。',
                textAlign: TextAlign.center,
                style:
                    AppType.caption.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: AppSpace.lg),
            for (final p in topics.available) ...[
              TopicCard(
                pack: p,
                selected: p.id == topics.currentId,
                onTap: () => Navigator.of(ctx).pop(p.id),
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked == topics.currentId) return;
  Analytics.instance.track('topic_switch', {'from': topics.currentId, 'to': picked});
  await topics.switchTo(picked);
}
