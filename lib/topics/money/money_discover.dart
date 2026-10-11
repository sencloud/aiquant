import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/features.dart';
import '../../screens/discover/discover_screen.dart';
import '../../screens/ding/ding_screen.dart';
import '../../screens/live/live_screen.dart';
import '../../screens/nautilus/nautilus_screen.dart';
import '../../screens/portfolio/portfolio_screen.dart';
import '../../state/ding_state.dart';
import '../../widgets/wk_kit.dart';

/// 喜爱钱「发现」里的内置入口：定时提醒；以及默认下线的组合管理 / AI 直播 /
/// 鹦鹉螺（编译开关，全部关掉时整组不出现）。
class MoneyDiscoverBuiltins extends StatelessWidget {
  const MoneyDiscoverBuiltins({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<DingState>().unreadCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WkGroup(
          header: '提醒与任务',
          footer: '按点让 AI 自己去跑：盯盘、复盘、出日报。',
          children: [
            WkRow(
              icon: Icons.alarm_rounded,
              title: '定时提醒',
              subtitle: '按点让 AI 执行任务',
              trailing: unread > 0 ? DiscoverBadge(unread) : null,
              onTap: () => openFromDiscover(context, const DingScreen(),
                  event: 'ding', needsLogin: true),
            ),
          ],
        ),
        if (kEnablePortfolio || kEnableLive || kEnableNautilus)
          WkGroup(
            header: '研究与组合',
            footer: '邀请好友在「我的」里：填码双方各得 100 喜点。',
            children: [
              if (kEnablePortfolio)
                WkRow(
                  icon: Icons.pie_chart_rounded,
                  title: '组合管理',
                  subtitle: '策略模拟组合 · 持仓 · 风险 · 绩效 · 报告',
                  onTap: () => openFromDiscover(context, const PortfolioScreen(),
                      event: 'portfolio'),
                ),
              if (kEnableLive)
                WkRow(
                  icon: Icons.podcasts_rounded,
                  title: 'AI 直播',
                  subtitle: '直播间与长文报告',
                  onTap: () =>
                      openFromDiscover(context, const LiveScreen(), event: 'live'),
                ),
              if (kEnableNautilus)
                WkRow(
                  icon: Icons.track_changes_rounded,
                  title: '鹦鹉螺预测',
                  subtitle: '天气与金融事件的预测市场',
                  onTap: () => openFromDiscover(context, const NautilusScreen(),
                      event: 'nautilus'),
                ),
            ],
          ),
      ],
    );
  }
}
