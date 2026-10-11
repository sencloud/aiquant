import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/config/features.dart';
import '../../core/topic/topic_pack.dart';
import '../../screens/assistant/assistant_screen.dart';
import '../../screens/discover/discover_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/strategy/strategy_screen.dart';
import '../../screens/watch/watch_screen.dart';
import '../../services/tushare_service.dart';
import '../../state/ding_state.dart';
import '../../state/live_state.dart';
import '../../state/nautilus_state.dart';
import '../../state/portfolio_state.dart';
import '../../state/watchlist_state.dart';
import '../../theme/app_theme.dart';
import 'money_discover.dart';

/// 喜爱钱 · 给你量化。
///
/// 主题化之前 App 的功能归到这里：对话 / 发现 / 我的。「策略」页签（证伪
/// 档案）、「发现 → 组合管理」、「我的 → 我的自选」已下线（代码保留，见
/// `core/config/features.dart` 的开关）。
class MoneyPack extends TopicPack {
  const MoneyPack();

  @override
  String get id => 'money';

  @override
  String get name => '喜爱钱';

  @override
  String get slogan => '给你量化';

  @override
  TopicPalette get palette => TopicPalette.money;

  @override
  IconData get icon => Icons.insights_rounded;

  @override
  String get blurb => 'AI 投研助手 · 行情 · 财报 · 盯盘';

  @override
  String get chatTitle => '喜爱';

  /// 「发现」内容可浏览，需要账号的动作自己会弹登录；只有「我的」需要登录。
  /// 「策略」页签（证伪台）默认下线，[kEnableStrategyTab] 打开才出现。
  @override
  List<TopicTab> get tabs => [
        TopicTab(
          key: 'chat',
          label: '对话',
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_bubble_rounded,
          builder: (_) => const AssistantScreen(),
        ),
        if (kEnableStrategyTab)
          TopicTab(
            key: 'strategy',
            label: '策略',
            icon: Icons.insights_rounded,
            activeIcon: Icons.insights_rounded,
            builder: (_) => const StrategyScreen(),
          ),
        TopicTab(
          key: 'discover',
          label: '发现',
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore_rounded,
          builder: (_) => const DiscoverScreen(),
          badge: (context) => context.watch<DingState>().unreadCount,
        ),
        TopicTab(
          key: 'me',
          label: '我的',
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          builder: (_) => const SettingsScreen(),
          requiresLogin: true,
        ),
      ];

  /// 量化私有状态：只在喜爱钱里创建，离开主题即销毁（不再请求 Tushare）。
  @override
  List<SingleChildWidget> providers() => [
        // 组合管理下线时不启动（不拉行情）；Provider 仍在，对话里的组合附带
        // 逻辑读得到它，只是永远是空的。
        ChangeNotifierProvider(create: (_) {
          final s = PortfolioState();
          if (kEnablePortfolio) s.bootstrap();
          return s;
        }),
        // DingState 的 bootstrap() 由登录态切换驱动（见 [onAuthChanged]）。
        ChangeNotifierProvider(create: (_) => DingState()),
        ChangeNotifierProvider(create: (_) => LiveState()),
        ChangeNotifierProvider(create: (_) => NautilusState()),
        // 看盘自选列表（本地持久化，无需登录）。「我的自选」下线时不启动。
        ChangeNotifierProvider(create: (_) {
          final s = WatchlistState();
          if (kEnableWatchlist) s.bootstrap();
          return s;
        }),
      ];

  @override
  List<Widget> discoverBuiltins(BuildContext context) =>
      const [MoneyDiscoverBuiltins()];

  @override
  String? discoverNote(BuildContext context) =>
      '最常用的还是「对话」：行情、财报、资金流，直接问就行。';

  @override
  List<Widget> settingsTools(BuildContext context) => [
        if (kEnableWatchlist)
          ProfileIndexRow(
            icon: Icons.star_outline_rounded,
            title: '我的自选',
            note: '股票 / ETF / 期货',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WatchScreen()),
            ),
          ),
      ];

  @override
  String? settingsNote(BuildContext context) =>
      kEnableNautilus ? null : '鹦鹉螺预测已下线：螺壳余额保留，暂停赚取与使用。';

  /// 启动后立即发起一次 Tushare 轻量请求：触发 iOS 中国大陆首启的
  /// "允许使用 Wi-Fi/蜂窝网络" 系统弹窗，并预热 DNS/TLS。
  @override
  void onEnter(BuildContext context) {
    // ignore: unawaited_futures
    TushareService().warmup();
  }

  @override
  void onAuthChanged(
    BuildContext context, {
    required bool authed,
    required bool switchedAccount,
    required bool loggedOut,
  }) {
    if (authed) {
      if (switchedAccount) {
        context.read<DingState>().reset();
        if (kEnableNautilus) context.read<NautilusState>().clearUserData();
      }
      context.read<DingState>().bootstrap();
      // 螺壳已冻结、鹦鹉螺隐藏：不再拉螺壳钱包。
      if (kEnableNautilus) context.read<NautilusState>().refreshWallet();
    } else if (loggedOut) {
      context.read<DingState>().reset();
      if (kEnableNautilus) context.read<NautilusState>().clearUserData();
    }
  }

  /// 回到前台时让 DING 调度器追赶一次（移动端无真后台 cron）。
  @override
  void onResume(BuildContext context) {
    context.read<DingState>().resumeFromBackground();
  }

  @override
  void onNetworkRestored(BuildContext context) {
    // ignore: unawaited_futures
    TushareService().warmup();
  }
}
