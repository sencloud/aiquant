import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/config/features.dart';
import '../../core/topic/topic_pack.dart';
import '../../models/persona.dart';
import '../../screens/assistant/assistant_screen.dart';
import '../../screens/discover/discover_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import 'fishing_discover.dart';
import 'fishing_state.dart';
import 'forecast_screen.dart';
import 'identify_screen.dart';

/// 喜爱钓鱼 · 给你钓鱼相关的一切。
///
/// 页签：对话 / 出钓 / 发现 / 我的。渔获（日记 + 钓点）是「发现」里的内置小应用。
/// 第一版只做淡水钓。
class FishingPack extends TopicPack {
  const FishingPack();

  @override
  String get id => 'fishing';

  @override
  String get name => '喜爱钓鱼';

  @override
  String get slogan => '给你钓鱼的一切';

  @override
  TopicPalette get palette => TopicPalette.fishing;

  @override
  IconData get icon => Icons.phishing_rounded;

  @override
  String get blurb => 'AI 钓友 · 出钓指数 · 渔获日记';

  @override
  String get chatTitle => '喜爱钓鱼';

  @override
  List<TopicTab> get tabs => [
        TopicTab(
          key: 'chat',
          label: '对话',
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_bubble_rounded,
          builder: (_) => const AssistantScreen(),
        ),
        TopicTab(
          key: 'forecast',
          label: '出钓',
          icon: Icons.wb_twilight_outlined,
          activeIcon: Icons.wb_twilight_rounded,
          builder: (_) => const FishingForecastScreen(),
        ),
        TopicTab(
          key: 'discover',
          label: '发现',
          icon: Icons.explore_outlined,
          activeIcon: Icons.explore_rounded,
          builder: (_) => const DiscoverScreen(),
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

  @override
  List<SingleChildWidget> providers() => [
        ChangeNotifierProvider(create: (_) => FishingState()),
      ];

  @override
  List<Widget> discoverBuiltins(BuildContext context) =>
      const [FishingDiscoverBuiltins()];

  @override
  List<Widget> settingsTools(BuildContext context) => [
        if (kEnableFishIdentify)
          ProfileIndexRow(
            key: const Key('settings-identify'),
            icon: Icons.center_focus_strong_outlined,
            title: '拍照识鱼',
            note: '$kIdentifyCredits 喜点 / 次',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const IdentifyScreen())),
          ),
      ];

  @override
  String? settingsNote(BuildContext context) => '出钓指数、钓点地图免费；AI 钓友对话 1 喜点 / 轮'
      '${kEnableFishIdentify ? '，拍照识鱼 $kIdentifyCredits 喜点 / 次' : ''}，'
      '新建小应用 5 喜点、修改 2 喜点（没做出来全额退回）。喜点在各主题通用。';

  @override
  void onAuthChanged(
    BuildContext context, {
    required bool authed,
    required bool switchedAccount,
    required bool loggedOut,
  }) {
    final s = context.read<FishingState>();
    if (!authed || loggedOut || switchedAccount) {
      s.clearJournal();
      s.forgetLocation();
    }
    if (authed) s.refreshJournal();
  }

  @override
  Future<List<String>> loadHomeSuggestions() async =>
      Personas.byId(Personas.fishingDefaultId, topic: 'fishing')
          .welcomeSuggestions;
}
