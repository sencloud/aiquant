import 'package:flutter/material.dart';

import '../models/persona.dart';

/// 一个圈子 = 一批 AI 助手 + 一个话题。
///
/// 「圈子」是 1.4.0 里取代「通讯录」的那一页：微信的通讯录装的是人，这里
/// 装的是圈子，一个圈子进去是一屋子助手。
///
/// **圈子不是主题**：进圈不换皮 —— 整屏换色那套（TopicPalette）已经删了，
/// 圈色只落在圈徽、头像、标签上。对话本身按服务端的 `topic` 走，
/// 一位助手的人设 prompt 也由服务端按 (topic, persona) 维护。
@immutable
class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.mark,
    required this.blurb,
    required this.color,
    required this.personaIds,
  });

  /// 与后端 `topic` 参数一致：money / fishing / coffee / cat / camping / hanfu。
  final String id;

  /// 圈名，例如「喜爱钓鱼」。
  final String name;

  /// 圈徽记：一个汉字，落在方头像上。
  final String mark;

  /// 一句话说明。
  final String blurb;

  /// 圈色：只用于圈徽与头像，不做整屏换色。
  final Color color;

  /// 这个圈里的助手（人设 id），第一位是默认。
  final List<String> personaIds;

  /// 这个圈的助手列表。
  List<Persona> get personas =>
      [for (final id in personaIds) Personas.byId(id, topic: this.id)];

  /// 默认助手（新开一段对话时用它）。
  Persona get defaultPersona => Personas.byId(personaIds.first, topic: id);
}

/// 六个圈子。顺序就是「圈子」页里的顺序（第一个是主圈）。
const List<Circle> kCircles = [
  Circle(
    id: 'money',
    name: '喜爱钱',
    mark: '钱',
    blurb: '给你量化 · 行情、财报、资金流',
    color: Color(0xFF9E6322),
    personaIds: [
      'default',
      'quant',
      'buffett',
      'graham',
      'lynch',
      'munger',
      'dalio',
      'soros',
      'commodity_futures',
      'fin_futures',
      'option_strategist',
    ],
  ),
  Circle(
    id: 'fishing',
    name: '喜爱钓鱼',
    mark: '钓',
    blurb: '台钓 · 路亚 · 出钓与渔获',
    color: Color(0xFF1F6A7A),
    personaIds: ['fishing_buddy', 'taidiao_teacher', 'lure_coach'],
  ),
  Circle(
    id: 'coffee',
    name: '喜爱咖啡',
    mark: '咖',
    blurb: '手冲 · 意式 · 选豆',
    color: Color(0xFF6F4A2A),
    personaIds: ['coffee_pourover', 'coffee_espresso', 'coffee_bean'],
  ),
  Circle(
    id: 'cat',
    name: '喜爱养猫',
    mark: '猫',
    blurb: '喂养 · 护理 · 行为',
    color: Color(0xFF6E5A8C),
    personaIds: ['cat_buddy', 'cat_nutrition', 'cat_behavior'],
  ),
  Circle(
    id: 'camping',
    name: '喜爱露营',
    mark: '营',
    blurb: '装备 · 天气 · 新手第一次过夜',
    color: Color(0xFF33587A),
    personaIds: ['camp_gear', 'camp_weather', 'camp_beginner'],
  ),
  Circle(
    id: 'hanfu',
    name: '喜爱汉服',
    mark: '服',
    blurb: '形制 · 穿搭 · 入坑',
    color: Color(0xFF8C3A4A),
    personaIds: ['hanfu_history', 'hanfu_styling', 'hanfu_beginner'],
  ),
];

/// 按 id 找圈；找不到给主圈。
Circle circleOf(String? id) {
  for (final c in kCircles) {
    if (c.id == id) return c;
  }
  return kCircles.first;
}

/// 会话列表里用：这个话题属于哪个圈（找不到就给主圈）。
Circle circleOfTopic(String topic) => circleOf(topic);
