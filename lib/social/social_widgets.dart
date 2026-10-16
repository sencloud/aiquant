import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'social_models.dart';
import 'social_state.dart';

/// 身份标。AI 在**每一处露出**都带这个标 —— 这是规矩 05，
/// 也是「不必猜」的落点。
class SocialIdentityTag extends StatelessWidget {
  const SocialIdentityTag({super.key, required this.kind});

  final SocialAuthorKind kind;

  @override
  Widget build(BuildContext context) {
    if (kind != SocialAuthorKind.resident) return const SizedBox.shrink();
    return const WkTag('AI 居民', filled: true);
  }
}

/// 事卡（票根）：一件事 = 一个锚点，话挂在它上面。
class SocialEventCard extends StatelessWidget {
  const SocialEventCard({
    super.key,
    required this.event,
    this.posts = const [],
    this.onSpeak,
    this.onWithdraw,
  });

  final SocialEvent event;

  /// 已经挂在这条事上的话。
  final List<SocialPost> posts;
  final VoidCallback? onSpeak;
  final void Function(SocialPost post)? onWithdraw;

  String get _time {
    final h = event.at.hour.toString().padLeft(2, '0');
    final m = event.at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
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
              const Text('我的记录',
                  style: AppType.caption),
              SocialIdentityTag(kind: event.authorKind),
              const Spacer(),
              Text(_time, style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(event.title, style: AppType.title.copyWith(fontSize: 18)),
          if (event.detail.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(event.detail,
                style: AppType.read.copyWith(color: AppColors.textSecondary)),
          ],
          if (event.facts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.xs,
              children: [
                for (final f in event.facts)
                  Text(f,
                      style: AppType.micro.copyWith(
                        color: AppColors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
              ],
            ),
          ],
          if (posts.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            for (final p in posts) SocialPostTile(post: p, onWithdraw: onWithdraw),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              WkTagButton(label: '说一句', primary: true, onTap: onSpeak),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一条话。已经在路上的回声会显示它的条件。
class SocialPostTile extends StatelessWidget {
  const SocialPostTile({super.key, required this.post, this.onWithdraw});

  final SocialPost post;
  final void Function(SocialPost post)? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('挂在：${post.target.title}',
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.sm),
          Text(post.text, style: AppType.read),
          if (post.isEcho) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 13, color: AppColors.textTertiary),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    post.delivered
                        ? '已递出去'
                        : (post.deliveryNote.isEmpty
                            ? '回声：条件到了才递出去'
                            : '回声：${post.deliveryNote}'),
                    style: AppType.micro.copyWith(color: AppColors.textTertiary),
                  ),
                ),
                if (!post.delivered && onWithdraw != null)
                  WkTagButton(
                      label: '撤回', onTap: () => onWithdraw!(post)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 由头卡：说一句之前必须先选它。
class SocialTargetTile extends StatelessWidget {
  const SocialTargetTile({
    super.key,
    required this.target,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final SocialTarget? target;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final title = t?.title ?? '没有由头';
    // 没有由头的那张卡是**禁用并解释**的：这里没有「在吗」。
    final sub = t?.subtitle ??
        (disabled ? '这里没有「在吗」。有话、但不是现在该说的，投一条回声给以后。' : '');
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: disabled ? AppColors.bgRaised : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.amber : AppColors.borderDim,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: disabled
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 16, color: AppColors.amber),
              ],
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(sub,
                  style: AppType.caption
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 水位线：共同记录的轨。一天一格，高度是那天的量。
class WkWaterline extends StatelessWidget {
  const WkWaterline({
    super.key,
    required this.counts,
    this.height = 34,
  });

  final List<int> counts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = counts.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final n in counts) ...[
            Expanded(
              child: Container(
                height: n == 0 ? 3 : 6 + (height - 8) * (n / max),
                decoration: BoxDecoration(
                  color: n == 0
                      ? AppColors.borderDim
                      : (n >= max * 0.75
                          ? AppColors.amber
                          : AppColors.amber.withValues(alpha: 0.36)),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2), bottom: Radius.circular(1)),
                ),
              ),
            ),
            if (n != counts.last) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

/// 小按钮：和 WkRow / WkTag 同一套观感，用于卡片内动作。
class WkTagButton extends StatelessWidget {
  const WkTagButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: primary ? AppColors.amber : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: primary ? AppColors.amber : AppColors.borderDim,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: primary ? AppColors.onAccent : AppColors.textSecondary,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 「这里的规矩」：七条 + 今晚不在。
Future<void> showHouseRules(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgBase,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.92,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, 0, AppSpace.gutter, AppSpace.xxl),
        children: [
          Text('这里的规矩', style: AppType.display.copyWith(fontSize: 22)),
          const SizedBox(height: AppSpace.sm),
          Text('七条。任何新功能跟它们冲突，改功能。',
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.lg),
          const _TonightRow(),
          const SizedBox(height: AppSpace.lg),
          for (var i = 0; i < kSocialRules.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  child: Text((i + 1).toString().padLeft(2, '0'),
                      style: AppType.micro
                          .copyWith(color: AppColors.textTertiary)),
                ),
                Expanded(
                  child: Text(kSocialRules[i], style: AppType.read),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
          ],
          const SizedBox(height: AppSpace.sm),
          const WkNote(
            text: '第 02 与第 03 条是这套规矩里最贵的两条：它们决定了别处的社交产品'
                '抄不走 —— 抄过去就要改自己的消息本体。',
          ),
        ],
      ),
    ),
  );
}

class _TonightRow extends StatelessWidget {
  const _TonightRow();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SocialState>();
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('今晚不在', style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.xs),
                Text('今晚没有人能给你新的话；已经在路上的，明天早上到。',
                    style: AppType.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Switch.adaptive(
            value: state.tonightOff,
            activeTrackColor: AppColors.amber,
            onChanged: state.setTonightOff,
          ),
        ],
      ),
    );
  }
}
