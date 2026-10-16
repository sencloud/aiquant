import 'social_models.dart';
import 'social_state.dart';

/// 今天的事从哪来：只有一处 —— **你自己记下的**（[SocialState.myEvents]）。
///
/// 这里不生成任何「别人做了什么」的内容。今天没有事，页面就照实写空。
/// （圈子下线之后，原先「圈自己上报记录」那条来源一起去掉了：现在只有你和
/// 你的记录。）
class TodayFeed {
  const TodayFeed({required this.events});

  final List<SocialEvent> events;

  bool get isEmpty => events.isEmpty;

  /// 这条事下面挂着的话（现在就在那儿的那些）。
  List<SocialPost> postsOn(SocialState state, SocialEvent event) => state.posts
      .where((p) => p.delivered && p.target.id == event.target.id)
      .toList(growable: false);
}

/// 组装「今天」。
TodayFeed buildToday(SocialState state, {DateTime? now}) {
  final today = now ?? DateTime.now();
  bool isToday(DateTime t) =>
      t.year == today.year && t.month == today.month && t.day == today.day;

  final events = state.myEvents.where((e) => isToday(e.at)).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  return TodayFeed(events: events);
}
