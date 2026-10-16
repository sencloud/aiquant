import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../services/tushare_service.dart';
import '../state/ding_state.dart';
import '../state/live_state.dart';
import '../state/nautilus_state.dart';
import '../state/portfolio_state.dart';
import '../state/watchlist_state.dart';
import 'config/features.dart';

/// 喜爱 · 应用档案。
///
/// 这个类取代了原来的「主题包」（TopicPack）。2026-10 的微信式重构把多主题
/// 整个拿掉了：App 只有一个身份 —— 喜爱，AI 投研助理。所以这份档案不是用来
/// 「切换」的，它是**唯一**的一份，`appProfile` 是它的常量实例。
///
/// 留下这层的原因很实际：状态装配（哪些 ChangeNotifier 要在启动时挂上、
/// 什么时候预热 Tushare、登录态变化时要 reset 什么）需要一个明确的落点，
/// 否则这些副作用会散在 shell、AuthGate、main 里各写一份。
class AppProfile {
  const AppProfile();

  /// 后端对话接口的 `topic` 参数。老服务端不传即当 money 处理，传了也一致。
  String get id => 'money';

  /// App 名。
  String get name => '喜爱';

  /// 一句话。
  String get slogan => '给你量化';

  /// 徽记字：头像缺省时用它。
  String get mark => '喜';

  IconData get icon => Icons.insights_rounded;

  String get blurb => 'AI 投研助手 · 行情 · 财报 · 盯盘';

  /// AI 助手列表里的第一位：它是「喜爱」自己的会话入口。
  String get chatTitle => '喜爱';

  /// 档案私有的状态。挂在 `MaterialApp` 之上，二级页也读得到。
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

  /// 启动后立即发起一次 Tushare 轻量请求：触发 iOS 中国大陆首启的
  /// "允许使用 Wi-Fi/蜂窝网络" 系统弹窗，并预热 DNS/TLS。
  void onEnter(BuildContext context) {
    // ignore: unawaited_futures
    TushareService().warmup();
  }

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
  void onResume(BuildContext context) {
    context.read<DingState>().resumeFromBackground();
  }

  void onNetworkRestored(BuildContext context) {
    // ignore: unawaited_futures
    TushareService().warmup();
  }

  /// 「我的 → 随身工具」里由档案注入的行（「我的自选」下线时不出现）。
  List<Widget> settingsTools(BuildContext context) => const [];

  /// 「我的」随身工具组下方的说明（可选）。
  String? settingsNote(BuildContext context) => null;

  /// 未读角标用的信号源：定时提醒（DING）未读数。
  int unreadDing(BuildContext context) =>
      context.watch<DingState>().unreadCount;
}

/// 唯一的一份档案。
const AppProfile appProfile = AppProfile();

/// 头像上的品牌字（喜爱 → 喜）。
const String kBrandMark = '喜';
