import 'package:flutter/material.dart';

import '../../core/auth/require_login.dart';
import '../../core/topic/topic_registry.dart';
import '../../miniapp/screens/discover_miniapps.dart';
import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 发现 —— 结构照微信的「发现」，两个主题共用。
///
/// 自上而下：「我的小应用」卡片墙（对话生成的小工具 + ＋新建）、主题内置入口
/// （[TopicPack.discoverBuiltins]：钱主题的定时提醒、钓鱼主题的渔获）、官方模板。
/// 这一页不要求登录 —— 官方模板可浏览，需要账号的动作（新建、定时提醒）自己弹登录。
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pack = topicOf(context, listen: true);
    final note = pack.discoverNote(context);
    return WkPage(
      title: '发现',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: [
          DiscoverMiniApps(
            key: ValueKey('miniapps-${pack.id}'),
            topic: pack.id,
            builtins: pack.discoverBuiltins(context),
          ),
          if (note != null) WkNote(text: note),
        ],
      ),
    );
  }
}

/// 从发现页打开一个内置页面（埋点 + 按需登录）。
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

/// 未读角标：红底白字的胶囊，和底部页签上的那个同形。
class DiscoverBadge extends StatelessWidget {
  const DiscoverBadge(this.count, {super.key});
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
