import 'package:flutter/material.dart';

/// 兴趣圈的「今天」：一个数 + 一句话 + 一条时间轨 + 一张小票。
///
/// [value] 为 null 表示这个圈今天还没有判断 —— 这是**合法状态**，页面照实
/// 写「还没有判断」。编一个数出来比空着更糟：这条产品线全部的价值都建立在
/// 「数字可追溯」上（见 PRODUCT.md 的产品原则）。
@immutable
class TopicToday {
  const TopicToday({
    required this.label,
    this.value,
    this.unit = '',
    required this.verdict,
    required this.why,
    required this.ticket,
    this.rail,
    this.nowPercent,
    this.legend,
    this.jobs = const [],
  });

  /// 这个数是什么，例如「出钓指数」「猫粮余量」「赏味期」。
  final String label;

  /// 数的值（字符串，原样展示）；null = 今天还没有判断。
  final String? value;

  /// 单位，例如「天」。
  final String unit;

  /// 判定词，例如「适合出钓」「该补猫砂」。
  final String verdict;

  /// 一句结论：点开之前就能读完，不铺开讲。
  final String why;

  /// 依据（小票）：你的记录 → 公开数据 → 模型假设，三层分开写。
  final String ticket;

  /// 时间轨：八格。null = 这个圈不画轨道。
  final List<RailCell>? rail;

  /// 「现在」在轨道上的位置（0..1）。
  final double? nowPercent;

  /// 轨道下的三个刻度，例如 `['06:00', '现在 15:20', '22:00']`。
  final List<String>? legend;

  /// AI 能替你做的事。
  final List<TopicJob> jobs;

  bool get hasValue => value != null;
}

/// 时间轨上的一格：高度 0..1；[best] 是最深的时段，[good] 次之。
@immutable
class RailCell {
  const RailCell(this.height, {this.best = false, this.good = false});

  final double height;
  final bool best;
  final bool good;
}

/// 「按一条起算日记录算天数」的圈：咖啡的烘焙日、猫粮的开封日。
///
/// 只有起算日是**有类型**的数据，其余记录是自由文本 —— 判断不从随意写的字里
/// 猜。所以这类圈的「今天」只认用户显式标了起算日的那条记录。
@immutable
class TopicWindow {
  const TopicWindow({
    required this.days,
    required this.startLabel,
    required this.verdictFresh,
    required this.verdictSoon,
    this.soonAt = 0.4,
  });

  /// 窗口长度（天）：烘焙日 + 14 天、开封日 + 30 天。
  final int days;

  /// 起算日在记录里的叫法，例如「烘焙日」「开封日」。
  final String startLabel;

  /// 剩余比例还宽松时的判定词，例如「在最香的时候」。
  final String verdictFresh;

  /// 剩余比例小于 [soonAt] 时的判定词，例如「这几天得喝完」。
  final String verdictSoon;

  /// 进入「该动手了」的阈值（剩余 / 总长）。
  final double soonAt;
}

/// 「AI 能替你做的事」里的一条：点它带着一句问题进对话。
@immutable
class TopicJob {
  const TopicJob({
    required this.icon,
    required this.title,
    required this.note,
    required this.ask,
  });

  final IconData icon;
  final String title;
  final String note;

  /// 进对话时预填的问题。
  final String ask;
}
