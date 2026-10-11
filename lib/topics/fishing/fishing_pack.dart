import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/topic/topic_pack.dart';
import '../../models/persona.dart';
import '../../screens/assistant/assistant_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 喜爱钓鱼 · 给你钓鱼相关的一切。
///
/// 页签：对话 / 出钓 / 渔获 / 我的。第一版只做淡水钓。
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
          builder: (_) => const _ComingSoon(title: '出钓', text: '出钓指数即将上线'),
        ),
        TopicTab(
          key: 'catches',
          label: '渔获',
          icon: Icons.set_meal_outlined,
          activeIcon: Icons.set_meal_rounded,
          builder: (_) => const _ComingSoon(title: '渔获', text: '渔获日记即将上线'),
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
  List<SingleChildWidget> providers() => const [];

  @override
  Future<List<String>> loadHomeSuggestions() async =>
      Personas.byId(Personas.fishingDefaultId, topic: 'fishing')
          .welcomeSuggestions;
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => WkPage(
        title: title,
        child: Center(
          child: Text(text,
              style: AppType.body.copyWith(color: AppColors.textTertiary)),
        ),
      );
}
