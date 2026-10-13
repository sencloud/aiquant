import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/topic/topic_community_screen.dart';
import '../../core/topic/topic_log_screen.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_today.dart';
import '../../core/topic/topic_today_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';

/// 喜爱露营 · 给你露营相关的一切。
class CampingPack extends TopicPack {
  const CampingPack();

  @override
  String get id => 'camping';

  @override
  String get name => '喜爱露营';

  @override
  String get slogan => '给你露营的一切';

  @override
  String get blurb => '出发条件 · 装备清单 · 营地选择';

  @override
  TopicPalette get palette => TopicPalette.camping;

  @override
  IconData get icon => Icons.cabin_rounded;

  @override
  String get chatTitle => '喜爱露营';

  @override
  bool get aiLive => false;

  @override
  TopicToday get today => const TopicToday(
        label: '出发条件',
        verdict: '还没有判断',
        why: '记一次营地与装备，之后这里会按天气、海拔与你的装备清单给出'
            '「这周末值不值得出发」。',
        ticket: '依据：你自己记的营地与装备；公开数据用 Open-Meteo 的风、温、'
            '降水与露点。恶劣天气只写不建议，不给折中方案。',
        rail: [
          RailCell(0.18),
          RailCell(0.22),
          RailCell(0.32, good: true),
          RailCell(0.42, best: true),
          RailCell(0.38, good: true),
          RailCell(0.26, good: true),
          RailCell(0.24, good: true),
          RailCell(0.14),
        ],
        nowPercent: 0.38,
        legend: ['周五', '现在', '周一'],
        jobs: [
          TopicJob(
            icon: Icons.checklist_rounded,
            title: '装备清单',
            note: '按营地条件与人数生成清单，标出你已经有的',
            ask: '两人两天一夜要带什么？',
          ),
          TopicJob(
            icon: Icons.thunderstorm_outlined,
            title: '天气风险',
            note: '风、雨、露点、温差，直接说该不该去',
            ask: '这周末适合露营吗？',
          ),
          TopicJob(
            icon: Icons.place_outlined,
            title: '营地推荐',
            note: '按距离、水源、收费与手机信号挑',
            ask: '附近哪个营地适合新手？',
          ),
          TopicJob(
            icon: Icons.route_outlined,
            title: '新手路线',
            note: '从一次过夜开始，推下一步学什么',
            ask: '第一次露营该从哪开始？',
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
          key: 'community',
          label: '动态圈',
          icon: Icons.forum_outlined,
          activeIcon: Icons.forum_rounded,
          builder: (_) => const TopicCommunityScreen(),
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
