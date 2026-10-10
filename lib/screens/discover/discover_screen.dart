import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../services/analytics.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../ding/ding_screen.dart';
import '../live/live_screen.dart';
import '../nautilus/nautilus_screen.dart';
import '../portfolio/portfolio_screen.dart';

/// 发现 —— 第二梯队功能的聚合页，结构照微信的「发现」。
///
/// 一级入口只留少数几个高频动作（对话 / 策略 / 我的），其余按「发现」归档：
/// 想找什么就翻这一页，而不是把所有功能都堆到首屏。这一页不要求登录 ——
/// 内容可浏览，需要账号的动作（定时提醒、下注等）自己弹登录。
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<DingState>().unreadCount;

    return WkPage(
      title: '发现',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: [
          WkGroup(
            header: '提醒与任务',
            footer: '按点让 AI 自己去跑：盯盘、复盘、出日报。',
            children: [
              WkRow(
                icon: Icons.alarm,
                title: '定时提醒',
                subtitle: '按点让 AI 执行任务',
                trailing: unread > 0 ? _Badge(unread) : null,
                onTap: () => _push(context, const DingScreen(),
                    event: 'ding', needsLogin: true),
              ),
            ],
          ),
          WkGroup(
            header: '研究与组合',
            children: [
              WkRow(
                icon: Icons.pie_chart_outline,
                title: '组合管理',
                subtitle: '持仓 · 风险 · 绩效 · 报告',
                onTap: () => _push(context, const PortfolioScreen(),
                    event: 'portfolio'),
              ),
              WkRow(
                icon: Icons.podcasts,
                title: 'AI 直播',
                subtitle: '直播间与长文报告',
                onTap: () =>
                    _push(context, const LiveScreen(), event: 'live'),
              ),
              WkRow(
                icon: Icons.track_changes,
                title: '鹦鹉螺预测',
                subtitle: '天气与金融事件的预测市场',
                onTap: () =>
                    _push(context, const NautilusScreen(), event: 'nautilus'),
              ),
            ],
          ),
          const WkNote(
            text: '这一页只放「想用才去找」的功能。高频动作仍然只有两个：'
                '对话，和策略里的证伪台。',
          ),
        ],
      ),
    );
  }

  Future<void> _push(
    BuildContext context,
    Widget page, {
    required String event,
    bool needsLogin = false,
  }) async {
    Analytics.instance.track(Analytics.evDiscoverOpen, {'entry': event});
    if (needsLogin && !await requireLogin(context)) return;
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
  }
}

/// 未读角标：红底白字的胶囊，和底部页签上的那个同形。
class _Badge extends StatelessWidget {
  const _Badge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}
