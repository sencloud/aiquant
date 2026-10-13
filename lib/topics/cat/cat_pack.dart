import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/topic/topic_community_screen.dart';
import '../../core/topic/topic_log_screen.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_today.dart';
import '../../core/topic/topic_today_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';

/// 喜爱养猫 · 给你养猫相关的一切。
///
/// 症状类问题只给排查顺序与就医线，不给诊断 —— 这条写在圈内每一处回答的
/// 小票上，也是「AI 幻觉」这条风险在养宠场景里的唯一正解。
class CatPack extends TopicPack {
  const CatPack();

  @override
  String get id => 'cat';

  @override
  String get name => '喜爱养猫';

  @override
  String get slogan => '给你养猫的一切';

  @override
  String get blurb => '症状排查 · 猫粮成分 · 行为解读';

  @override
  TopicPalette get palette => TopicPalette.cat;

  @override
  IconData get icon => Icons.pets_rounded;

  @override
  String get chatTitle => '喜爱养猫';

  @override
  bool get aiLive => false;

  @override
  TopicToday get today => const TopicToday(
        label: '库存',
        verdict: '还没有判断',
        unit: '天',
        why: '记一次猫粮开封日与体重，明天这里就会说「还剩几天」「体重是涨是平」，'
            '以及这个月该注意什么。',
        ticket: '依据：你自己记的体重、开封日与购买日；症状类问题一律给排查顺序与'
            '就医线，不给诊断。',
        rail: [
          RailCell(0.30),
          RailCell(0.36),
          RailCell(0.42, best: true),
          RailCell(0.34, good: true),
          RailCell(0.24, good: true),
          RailCell(0.16),
          RailCell(0.10),
          RailCell(0.10),
        ],
        nowPercent: 0.06,
        legend: ['今天', '现在', '第 7 天'],
        jobs: [
          TopicJob(
            icon: Icons.medical_information_outlined,
            title: '症状判断',
            note: '说清症状与持续天数，我给可能的方向与就医线',
            ask: '它这周掉毛变多，正常吗？',
          ),
          TopicJob(
            icon: Icons.science_outlined,
            title: '猫粮成分',
            note: '按成分表与你的预算比，不按销量排',
            ask: '这两款猫粮哪个好？',
          ),
          TopicJob(
            icon: Icons.psychology_outlined,
            title: '行为解读',
            note: '半夜跑酷、乱尿、不吃饭，先排除生理原因',
            ask: '它最近老躲床底',
          ),
          TopicJob(
            icon: Icons.shopping_bag_outlined,
            title: '用品清单',
            note: '按体重与年龄算用量，提醒该补什么',
            ask: '我还缺什么？',
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
