import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../theme/app_theme.dart';

/// 主题包（TopicPack）：「喜爱什么，就有什么」。
///
/// 整个 App 随主题切换 —— 页签、助手、内容、配色都由主题包提供，用户一次
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

  /// 一句话，例如「给你量化」。
  String get slogan;

  /// 主题色组：喂给 [AppColors.applyTopic]。
  TopicPalette get palette;

  IconData get icon;

  /// 选择页 / 切换面板上的一行介绍。
  String get blurb => slogan;

  /// 开屏页「喜爱」下面的小字（按上次的主题）。
  String get splashSubtitle => '$name · $slogan';

  /// 开屏页底部的一句话。
  String get splashMotto => blurb;

  /// 对话页顶栏标题。
  String get chatTitle;

  /// 底部页签（固定 4 个，延续微信式结构）。
  List<TopicTab> get tabs;

  /// 主题私有状态：进入主题时才创建，离开主题时整体销毁。
  ///
  /// 放在 `MaterialApp` 之上（见 app.dart），这样从页签 push 出去的页面
  /// 也能读到；外层 `MultiProvider` 以 [id] 作 key，切换即重建。
  List<SingleChildWidget> providers();

  /// 「我的 → 随身工具」里由主题注入的行（钱主题：我的自选）。
  List<Widget> settingsTools(BuildContext context) => const [];

  /// 「我的」随身工具组下方的说明文字（可选）。
  String? settingsNote(BuildContext context) => null;

  /// 对话首页的快捷提问（空会话时展示）；返回空列表则用当前人设的默认提问。
  Future<List<String>> loadHomeSuggestions() async => const [];

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
