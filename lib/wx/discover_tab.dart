import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/require_login.dart';
import '../core/config/features.dart';
import '../miniapp/screens/discover_miniapps.dart';
import '../screens/ding/ding_screen.dart';
import '../screens/live/live_screen.dart';
import '../screens/nautilus/nautilus_screen.dart';
import '../screens/portfolio/portfolio_screen.dart';
import '../services/analytics.dart';
import '../social/screens/gift_screen.dart';
import '../social/screens/mail_tab.dart';
import '../social/screens/today_tab.dart';
import '../state/ding_state.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'moments_screen.dart';
import 'wx_kit.dart';

/// 「发现」页签：第二梯队的东西都收在这里（照微信，一级入口只留少数几个）。
///
/// 两组：**广场**（朋友圈）/ **记录**（今天的事 / 信箱 / 见面礼 —— 都是本机的
/// 东西）和**工具**（定时提醒 / 我的小应用）。下线的功能不出现在这里。
class WxDiscoverTab extends StatelessWidget {
  const WxDiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<DingState>().unreadCount;
    return Column(
      children: [
        const WxTopBar(title: '发现'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
            children: [
              WkGroup(
                children: [
                  WkRow(
                    key: const ValueKey('discover-moments'),
                    leading: const WxIconTile(
                      icon: Icons.camera_rounded,
                      color: Color(0xFF9E6322),
                    ),
                    title: '朋友圈',
                    subtitle: '广场上六位居民的近况 · 都是 AI',
                    onTap: () => openFromDiscover(context,
                        const MomentsScreen(),
                        event: 'moments'),
                  ),
                ],
              ),
              WkGroup(
                children: [
                  WkRow(
                    key: const ValueKey('discover-today'),
                    leading: const WxIconTile(
                      icon: Icons.edit_note_rounded,
                      // 主色是墨金：这一格跟着主色走，别处再留微信那种多色图标。
                      color: Color(0xFF9E6322),
                    ),
                    title: '今天的事',
                    subtitle: '记一件今天的事，话才有地方落',
                    onTap: () => openFromDiscover(context, const TodayScreen(),
                        event: 'today'),
                  ),
                  WkRow(
                    key: const ValueKey('discover-mail'),
                    leading: const WxIconTile(
                      icon: Icons.markunread_mailbox_outlined,
                      color: Color(0xFF576B95),
                    ),
                    title: '信箱',
                    subtitle: '话挂在东西上，回声在路上',
                    onTap: () => openFromDiscover(context, const MailScreen(),
                        event: 'mail'),
                  ),
                  WkRow(
                    key: const ValueKey('discover-gift'),
                    leading: const WxIconTile(
                      icon: Icons.card_giftcard_rounded,
                      color: Color(0xFFFA9D3B),
                    ),
                    title: '见面礼',
                    subtitle: '想让谁认识你，先送一样东西',
                    onTap: () => openFromDiscover(context, const GiftScreen(),
                        event: 'gift'),
                  ),
                ],
              ),
              WkGroup(
                children: [
                  WkRow(
                    key: const ValueKey('discover-ding'),
                    leading: const WxIconTile(
                      icon: Icons.alarm_rounded,
                      color: Color(0xFF10AEFF),
                    ),
                    title: '定时提醒',
                    subtitle: '按点让 AI 去跑：盯盘、复盘、出日报',
                    trailing: unread > 0 ? WxBadge(count: unread) : null,
                    onTap: () => openFromDiscover(context, const DingScreen(),
                        event: 'ding', needsLogin: true),
                  ),
                  WkRow(
                    key: const ValueKey('discover-miniapps'),
                    leading: const WxIconTile(
                      icon: Icons.widgets_rounded,
                      color: Color(0xFF8A6DE9),
                    ),
                    title: '我的小应用',
                    subtitle: '把常问的几件事做成一个页面',
                    onTap: () => openFromDiscover(
                        context, const MiniAppsScreen(),
                        event: 'miniapps'),
                  ),
                ],
              ),
              if (kEnablePortfolio || kEnableLive || kEnableNautilus)
                WkGroup(
                  children: [
                    if (kEnablePortfolio)
                      WkRow(
                        leading: const WxIconTile(
                          icon: Icons.pie_chart_rounded,
                          color: Color(0xFF17864E),
                        ),
                        title: '组合管理',
                        subtitle: '持仓 · 风险 · 绩效 · 报告',
                        onTap: () => openFromDiscover(
                            context, const PortfolioScreen(),
                            event: 'portfolio'),
                      ),
                    if (kEnableLive)
                      WkRow(
                        leading: const WxIconTile(
                          icon: Icons.podcasts_rounded,
                          color: Color(0xFFFA5151),
                        ),
                        title: 'AI 直播',
                        subtitle: '直播间与长文报告',
                        onTap: () => openFromDiscover(
                            context, const LiveScreen(),
                            event: 'live'),
                      ),
                    if (kEnableNautilus)
                      WkRow(
                        leading: const WxIconTile(
                          icon: Icons.track_changes_rounded,
                          color: Color(0xFF9E6322),
                        ),
                        title: '鹦鹉螺预测',
                        subtitle: '天气与金融事件的预测市场',
                        onTap: () => openFromDiscover(
                            context, const NautilusScreen(),
                            event: 'nautilus'),
                      ),
                  ],
                ),
              const WkNote(
                text: '最常用的还是「消息」：行情、财报、资金流，直接问就行。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 我的小应用：对话生成的小工具都在这儿（新建、管理、官方模板）。
class MiniAppsScreen extends StatelessWidget {
  const MiniAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WkPage(
      title: '我的小应用',
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        child: DiscoverMiniApps(topic: 'money'),
      ),
    );
  }
}

/// 从发现页打开一个二级页（埋点 + 按需登录）。
Future<void> openFromDiscover(
  BuildContext context,
  Widget page, {
  required String event,
  bool needsLogin = false,
}) async {
  Analytics.instance.track(Analytics.evDiscoverOpen, {'entry': event});
  if (needsLogin && !await requireLogin(context)) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
