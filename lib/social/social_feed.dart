import 'package:flutter/widgets.dart';

import '../core/topic/topic_pack.dart';
import '../models/persona.dart';
import 'social_models.dart';
import 'social_state.dart';

/// 今天的事从哪来。
///
/// 两条来源，都是真的：
///   1. **本机记下的事**（`SocialState.myEvents`）—— 用户在「记一件事」里写下的；
///   2. **圈自己的记录**（`TopicPack.socialEvents`）—— 渔获日志、豆单这些
///      已经在 App 里的东西，由圈自己上报，共享层不写 `if (topic == ...)`。
///
/// 这里**不生成**任何「别人钓到了一条鱼」的内容。今天没有事，页面就照实写空。
class TodayFeed {
  const TodayFeed({required this.events, required this.circle, required this.residents});

  final List<SocialEvent> events;
  final TopicPack circle;
  final List<SocialResident> residents;

  bool get isEmpty => events.isEmpty;

  /// 这条事下面挂着的话（现在就在那儿的那些）。
  List<SocialPost> postsOn(SocialState state, SocialEvent event) =>
      state.posts
          .where((p) => p.delivered && p.target.id == event.target.id)
          .toList(growable: false);
}

/// 组装今天。
TodayFeed buildToday(
  BuildContext context,
  TopicPack pack,
  SocialState state, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  bool isToday(DateTime t) =>
      t.year == today.year && t.month == today.month && t.day == today.day;

  final events = <SocialEvent>[
    ...state.myEvents.where((e) => isToday(e.at)),
    ...pack.socialEvents(context).where((e) => isToday(e.at)),
  ]..sort((a, b) => b.at.compareTo(a.at));

  return TodayFeed(
    events: events,
    circle: pack,
    residents: residentsOf(pack),
  );
}

/// 圈里的 AI 居民 —— 直接复用 App 已有的人设（`lib/models/persona.dart`）：
/// 人设 prompt 在服务端，客户端只管名字与一句话。最多两位。
List<SocialResident> residentsOf(TopicPack pack) {
  final personas = Personas.forTopic(pack.id);
  final preferredId = _residentIdFor(pack.id);
  // 按 id 去重：默认人设同时也是列表里的第一个，不去重会撞 key。
  final ordered = <Persona>[];
  final seen = <String>{};
  for (final p in [
    ...personas.where((p) => p.id == preferredId),
    ...personas,
  ]) {
    if (seen.add(p.id)) ordered.add(p);
    if (ordered.length == 2) break;
  }
  return ordered
      .map((p) => SocialResident(
            id: p.id,
            name: p.displayName,
            blurb: p.title,
            circleId: pack.id,
            circleMark: pack.mark,
          ))
      .toList(growable: false);
}

String _residentIdFor(String topic) {
  switch (topic) {
    case 'fishing':
      return Personas.fishingDefaultId;
    case 'coffee':
      return Personas.coffeeDefaultId;
    case 'cat':
      return Personas.catDefaultId;
    case 'camping':
      return Personas.campingDefaultId;
    case 'hanfu':
      return Personas.hanfuDefaultId;
    default:
      return Personas.defaultId;
  }
}
