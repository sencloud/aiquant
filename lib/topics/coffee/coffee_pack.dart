import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/topic/topic_log_screen.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_today.dart';
import '../../core/topic/topic_today_screen.dart';
import '../../screens/assistant/assistant_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';

/// 喜爱咖啡 · 给你咖啡相关的一切。
///
/// 页签：今天 / 记录 / 动态圈 / 我的。人设与工具待服务端上线（[aiLive] =
/// false），所以「今天」页里的入口是只读预览，不引导用户去点必然失败的请求。
class CoffeePack extends TopicPack {
  const CoffeePack();

  @override
  String get id => 'coffee';

  @override
  String get name => '喜爱咖啡';

  @override
  String get slogan => '给你咖啡的一切';

  @override
  String get blurb => '豆子匹配 · 冲煮参数 · 赏味期提醒';

  @override
  TopicPalette get palette => TopicPalette.coffee;

  @override
  IconData get icon => Icons.coffee_rounded;

  @override
  String get chatTitle => '喜爱咖啡';

  @override
  TopicToday get today => const TopicToday(
        label: '赏味期',
        verdict: '还没有判断',
        unit: '天',
        why: '记下手上这包豆子的烘焙日，明天这里就会说还有几天最好喝，'
            '以及这一杯该用多少度、多少粉。',
        ticket: '依据：你自己记的豆子与冲煮参数；公开数据用烘焙商建议的养豆期。'
            '没记录就写「还没有判断」。',
        rail: [
          RailCell(0.30),
          RailCell(0.34),
          RailCell(0.42, best: true),
          RailCell(0.38, good: true),
          RailCell(0.22, good: true),
          RailCell(0.16),
          RailCell(0.10),
          RailCell(0.10),
        ],
        nowPercent: 0.06,
        legend: ['今天', '现在', '第 7 天'],
        jobs: [
          TopicJob(
            icon: Icons.local_cafe_outlined,
            title: '风味匹配',
            note: '说你想要的味道，我挑豆子，不挑贵的',
            ask: '我想要果酸明显一点的豆子',
          ),
          TopicJob(
            icon: Icons.tune_rounded,
            title: '冲煮参数',
            note: '按你的豆子与器具算水温、粉水比、时间',
            ask: '手上这支豆子怎么冲？',
          ),
          TopicJob(
            icon: Icons.coffee_maker_outlined,
            title: '设备推荐',
            note: '从你的喝法倒推设备，不推整套',
            ask: '要不要买磨豆机？',
          ),
          TopicJob(
            icon: Icons.inventory_2_outlined,
            title: '豆单管理',
            note: '记下烘焙日，到期前提醒你把它喝掉',
            ask: '我的豆子还剩几天？',
          ),
        ],
      );

  @override
  List<TopicTab> get tabs => [
        TopicTab(
          key: 'today',
          label: '今天',
          icon: Icons.wb_twilight_outlined,
          activeIcon: Icons.wb_twilight_rounded,
          builder: (_) => const TopicTodayScreen(),
        ),
        TopicTab(
          key: 'log',
          label: '记录',
          icon: Icons.edit_note_outlined,
          activeIcon: Icons.edit_note_rounded,
          builder: (_) => const TopicLogScreen(),
        ),
        TopicTab(
          key: 'chat',
          label: '对话',
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_bubble_rounded,
          builder: (_) => const AssistantScreen(),
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
  String? settingsNote(BuildContext context) =>
      '记录与「今天」免费；AI 对话 1 喜点 / 轮（人设上线后开放）。喜点在各圈通用。';
}
