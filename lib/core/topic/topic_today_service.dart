import 'topic_log_screen.dart';
import 'topic_pack.dart';
import 'topic_today.dart';

/// 把「静态的今日判断模板」+「本地记录」算成今天真正要显示的那一版。
///
/// 规则只有一条：**算得出才算**。没有起算日记录就返回模板本身（value = null），
/// 页面照实写「还没有判断」；绝不为了首屏好看编一个数。
TopicToday? resolveToday(TopicPack pack) {
  final base = pack.today;
  if (base == null) return null;
  final window = pack.window;
  if (window == null) return base;

  final start = latestStart(pack.id);
  if (start == null) return base;

  final elapsed = DateTime.now().difference(start.at).inHours / 24;
  final total = window.days.toDouble();
  final left = (total - elapsed).clamp(0, total);
  final fraction = left / total;

  return TopicToday(
    label: base.label,
    value: left.floor().toString(),
    unit: base.unit,
    verdict:
        fraction <= window.soonAt ? window.verdictSoon : window.verdictFresh,
    why: base.why,
    ticket: todayTicket(pack)!,
    rail: _rail(fraction),
    nowPercent: (1 - fraction).clamp(0.0, 1.0),
    legend: ['记的那天', '现在', '第 ${window.days} 天'],
    jobs: base.jobs,
  );
}

/// 小票：写清这个数是怎么来的（起算日 + 窗口），可追溯到具体哪条记录。
String? todayTicket(TopicPack pack) {
  final window = pack.window;
  if (window == null) return pack.today?.ticket;
  final start = latestStart(pack.id);
  if (start == null) return pack.today?.ticket;
  return '依据：你 ${_fmtDay(start.at)} 记的「${window.startLabel}」+ '
      '${window.days} 天窗口。删掉那条记录，这里就会回到「还没有判断」。';
}

/// 最近一条起算日记录。
TopicLogEntry? latestStart(String topicId) {
  for (final e in loadTopicLog(topicId)) {
    if (e.start) return e;
  }
  return null;
}

/// 八格轨道：已过的是浅的，还没到的是深的（剩下的窗口就是「还能用」的部分）。
List<RailCell> _rail(double leftFraction) {
  final cells = <RailCell>[];
  for (var i = 0; i < 8; i++) {
    final center = (i + 0.5) / 8;
    final remaining = center > (1 - leftFraction);
    cells.add(RailCell(
      remaining ? 0.9 : 0.34,
      best: remaining && i >= 6,
      good: remaining && i < 6,
    ));
  }
  return cells;
}

String _fmtDay(DateTime at) {
  String two(int v) => v < 10 ? '0$v' : '$v';
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}
