import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../theme/app_theme.dart';
import '../../social/social_models.dart';
import 'topic_today.dart';

/// 主题包（TopicPack）：一个「圈」—— 一个兴趣、一批记录、一位 AI 居民。
///
/// 进圈之后整屏随主题切换 —— 页签、助手、内容、配色都由主题包提供，用户一次
/// 只在一个主题里。共享的只有账号、喜点 / 内购、邀请、对话 UI 骨架与
/// 「我的」骨架；主题之间的差异**只能**通过这个接口注入，不在共享层写
/// `if (topic == ...)`。
///
/// 代码里叫 Topic（不叫 Theme），避免和 Flutter 的 `ThemeData` / `ThemeMode`、
/// 现有的 `AppTheme` 撞名。
abstract class TopicPack {
  const TopicPack();

  /// 内部 id：`money` / `fishing`。与后端 `topic` 参数一致。
  String get id;

  /// 主题名，例如「喜爱钱」。
  String get name;

  /// 圈徽记：一个汉字，用在兴趣圈首页与切换面板上（喜爱钓鱼 → 钓）。
  /// 默认取「喜爱」之后的第一字。
  String get mark {
    final rest =
        name.startsWith('喜爱') && name.length > 2 ? name.substring(2) : name;
    return rest.isEmpty ? '圈' : rest.substring(0, 1);
  }

  /// 一句话，例如「给你量化」。
  String get slogan;

  /// 主题色组：喂给 [AppColors.applyTopic]。
  TopicPalette get palette;

  IconData get icon;

  /// 选择页 / 切换面板上的一行介绍。
  String get blurb => slogan;

  /// 对话页顶栏标题。
  String get chatTitle;

  /// 底部页签（固定 4 个，延续微信式结构）。
  List<TopicTab> get tabs;

  /// 主题私有状态：进入主题时才创建，离开主题时整体销毁。
  ///
  /// 放在 `MaterialApp` 之上（见 app.dart），这样从页签 push 出去的页面
  /// 也能读到；外层 `MultiProvider` 以 [id] 作 key，切换即重建。
  List<SingleChildWidget> providers();

  /// 「发现」页里主题自带的内置入口（钱主题：定时提醒；钓鱼主题：渔获）。
  /// 排在「我的小应用」卡片墙之后、官方模板之前。
  List<Widget> discoverBuiltins(BuildContext context) => const [];

  /// 「发现」页底部的一句说明（可选）。
  String? discoverNote(BuildContext context) => null;

  /// 「我的 → 随身工具」里由主题注入的行（钱主题：我的自选）。
  List<Widget> settingsTools(BuildContext context) => const [];

  /// 「我的」随身工具组下方的说明文字（可选）。
  String? settingsNote(BuildContext context) => null;

  /// 对话首页的快捷提问（空会话时展示）；返回空列表则用当前人设的默认提问。
  Future<List<String>> loadHomeSuggestions() async => const [];

  /// 「今天」的判断：把「今天该做什么」压成一个数加一句话。
  ///
  /// 返回 null 表示这个圈还没有今日判断（页面照实写「今天还没有判断」，
  /// 不编数字）。兴趣圈首页与圈内「今天」页都用它。
  TopicToday? get today => null;

  /// 这个圈的人设与工具是否已在服务端上线。
  ///
  /// 服务端 `topic.Resolve` 对未知 topic 返回 ErrUnknownTopic，所以新圈在
  /// 服务端上线之前，「今天」页里「AI 能替你做的事」只作为只读预览，
  /// 不引导用户去点一个必然会失败的入口。
  bool get aiLive => true;

  // ── 新社交（今天 / 圈 / 信箱）────────────────────────────────
  //
  // 这三支是「圈」向共享层上报自己**真实**数据的地方（共享层不写
  // `if (topic == ...)`）。没实现就是不参与，返回空 —— 空是合法状态。

  /// 这个圈今天发生的事（渔获、豆单、猫的记录……）。
  ///
  /// 只上报真实记录：App 不生成「别人钓到了一条鱼」这类内容，
  /// 今天没有事，「今天」页就照实写空。
  List<SocialEvent> socialEvents(BuildContext context) => const [];

  /// 说话时可以挂靠的「一件东西 / 一个地方」（竿、豆子、常去的钓点）。
  List<SocialTarget> socialTargets(BuildContext context) => const [];

  /// 共有物的水位线：最近 14 天每天记录了几条（0 表示那天没有）。
  List<int> socialWaterline(BuildContext context) => const [];

  /// 「按起算日算天数」的圈在这里声明窗口（咖啡赏味期、猫粮开封）。
  /// 返回 null 表示这个圈的「今天」不能这么算（露营看天气、汉服看温度，
  /// 它们的判断由 AI 在对话里给）。
  TopicWindow? get window => null;

  /// 进入主题时（冷启动 / 切换后首帧）执行一次的副作用，例如钱主题预热 Tushare。
  void onEnter(BuildContext context) {}

  /// 登录态变化时驱动主题私有状态。
  ///
  /// [authed] 当前是否已登录；[switchedAccount] 为 true 表示从另一个账号切过来
  /// （需要先清旧用户缓存）；[loggedOut] 为 true 表示显式登出 / 强制下线。
  void onAuthChanged(
    BuildContext context, {
    required bool authed,
    required bool switchedAccount,
    required bool loggedOut,
  }) {}

  /// App 回到前台。
  void onResume(BuildContext context) {}

  /// iOS 首启授权「无线数据」后网络恢复。
  void onNetworkRestored(BuildContext context) {}
}

/// 一个底部页签。
class TopicTab {
  const TopicTab({
    required this.key,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.builder,
    this.requiresLogin = false,
    this.badge,
  });

  /// 埋点名（例：chat / strategy / discover / me）。
  final String key;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final WidgetBuilder builder;

  /// 进入前需要登录（未登录先弹登录，放弃则停留原页签）。
  final bool requiresLogin;

  /// 页签上的红色数字角标（例：钱主题「发现」的 DING 未读数）。
  /// 在 build 里调用，可以 `context.watch` 主题私有状态。
  final int Function(BuildContext context)? badge;
}
