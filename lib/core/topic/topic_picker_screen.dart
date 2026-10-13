import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import 'topic_pack.dart';
import 'topic_state.dart';

/// 选主题页。两处用的是**同一个页面**：
///
/// * 全新安装首启（[switching] = false）：必须选一个才能往下走，没有返回；
/// * 「我的 → 切换主题」/ 长按对话页标题（[switching] = true，经
///   [showTopicSwitcher] 全屏推入）：当前主题打勾，左上角可关闭。
///
/// 选中后由调用方决定怎么处理：首启直接 [TopicState.completePick]；切换时
/// 把选中的 id 作为路由结果返回。
class TopicPickerScreen extends StatelessWidget {
  const TopicPickerScreen({super.key, this.switching = false});

  /// 是否是从「我的」里进来切换（而不是首启）。
  final bool switching;

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
              // 首启和切换顶部留同样的高度，两种进入方式版式完全一致；
              // 切换时这里放一个关闭按钮。
              SizedBox(
                height: 56,
                child: switching
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          key: const Key('topic-picker-close'),
                          tooltip: '关闭',
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          icon: Icon(Icons.close_rounded,
                              color: AppColors.textSecondary),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      )
                    : null,
              ),
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
                switching ? '换一个你喜爱的' : '先选一个你喜爱的',
                style: AppType.section.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpace.md),
              // 兴趣圈多起来之后这里放不下：卡片区自己滚，页头与脚注固定。
              // 两个主题时看不出区别，六个主题时不会溢出（小屏尤其明显）。
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final p in topics.available) ...[
                      TopicCard(
                        pack: p,
                        selected: switching && p.id == topics.currentId,
                        onTap: () {
                          if (switching) {
                            Navigator.of(context).pop(p.id);
                            return;
                          }
                          Analytics.instance
                              .track('topic_pick', {'topic': p.id});
                          context.read<TopicState>().completePick(p.id);
                        },
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                  ],
                ),
              ),
              Text(
                switching
                    ? '整个 App 随之切换；账号、喜点通用，对话各自保留'
                    : '随时可在「我的 → 切换主题」里换，账号和喜点通用',
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

/// 切换主题（「我的 → 切换主题」与长按对话页标题共用）：全屏推入和首启
/// 同一个 [TopicPickerScreen]，当前主题打勾。
Future<void> showTopicSwitcher(BuildContext context) async {
  final topics = context.read<TopicState>();
  if (!topics.canSwitch) return;
  final picked = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'topic-switcher'),
      builder: (_) => const TopicPickerScreen(switching: true),
    ),
  );
  if (picked == null || picked == topics.currentId) return;
  Analytics.instance
      .track('topic_switch', {'from': topics.currentId, 'to': picked});
  await topics.switchTo(picked);
}
