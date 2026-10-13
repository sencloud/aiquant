import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/topic/topic_community_screen.dart';
import '../../core/topic/topic_log_screen.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_today.dart';
import '../../core/topic/topic_today_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../theme/app_theme.dart';

/// 喜爱汉服 · 给你汉服相关的一切。
class HanfuPack extends TopicPack {
  const HanfuPack();

  @override
  String get id => 'hanfu';

  @override
  String get name => '喜爱汉服';

  @override
  String get slogan => '给你汉服的一切';

  @override
  String get blurb => '形制匹配 · 穿搭建议 · 妆造教程';

  @override
  TopicPalette get palette => TopicPalette.hanfu;

  @override
  IconData get icon => Icons.checkroom_rounded;

  @override
  String get chatTitle => '喜爱汉服';

  @override
  bool get aiLive => false;

  @override
  TopicToday get today => const TopicToday(
        label: '今日参考',
        verdict: '还没有判断',
        why: '把你的形制与场合记下来（例如「宋制 · 通勤」），之后这里会按温度、'
            '场合与你的衣柜给出今天怎么穿、缺什么。',
        ticket: '依据：你自己记的形制、尺码与场合；形制考据给出处，不用「大概是的」'
            '那种口吻。',
        rail: [
          RailCell(0.20),
          RailCell(0.24),
          RailCell(0.30, good: true),
          RailCell(0.36, good: true),
          RailCell(0.42, best: true),
          RailCell(0.34, good: true),
          RailCell(0.22),
          RailCell(0.16),
        ],
        nowPercent: 0.52,
        legend: ['早', '现在', '晚'],
        jobs: [
          TopicJob(
            icon: Icons.history_edu_outlined,
            title: '形制匹配',
            note: '说清年代与场合，我按形制配对，不混搭',
            ask: '宋制褙子配什么下裙？',
          ),
          TopicJob(
            icon: Icons.thermostat_outlined,
            title: '穿搭建议',
            note: '按当地温度与场合决定穿几层、要不要披',
            ask: '明天 18 度，穿汉服怎么搭？',
          ),
          TopicJob(
            icon: Icons.brush_outlined,
            title: '妆造教程',
            note: '按形制给妆造顺序，不堆产品',
            ask: '明制怎么盘发？',
          ),
          TopicJob(
            icon: Icons.event_outlined,
            title: '场合清单',
            note: '上班、逛街、参加雅集各要注意什么',
            ask: '日常通勤穿汉服会不会太隆重？',
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
