import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../topics/fishing/fishing_pack.dart';
import '../../topics/money/money_pack.dart';
import '../../topics/camping/camping_pack.dart';
import '../../topics/cat/cat_pack.dart';
import '../../topics/coffee/coffee_pack.dart';
import '../../topics/hanfu/hanfu_pack.dart';
import 'topic_flags.dart';
import 'topic_pack.dart';
import 'topic_state.dart';

/// 内置主题包。顺序即首启选择页 / 切换面板的顺序；第一个是默认主题。
List<TopicPack> builtInTopicPacks({bool? fishing, bool? circles}) => [
      const MoneyPack(),
      if (fishing ?? kEnableTopicFishing) const FishingPack(),
      if (circles ?? kEnableTopicCircles) ...[
        const CatPack(),
        const CoffeePack(),
        const CampingPack(),
        const HanfuPack(),
      ],
    ];

/// 当前主题包（由 app.dart 在 `MaterialApp` 之上注入）。
///
/// 测试 / 截图里单独挂一个页面、没有注入时，回落到喜爱钱 —— 与主题化之前
/// 的行为一致。
TopicPack topicOf(BuildContext context, {bool listen = false}) {
  try {
    final p = listen
        ? Provider.of<TopicPack?>(context)
        : Provider.of<TopicPack?>(context, listen: false);
    if (p != null) return p;
  } on ProviderNotFoundException {
    // fallthrough
  }
  return const MoneyPack();
}

/// 当前树上的 [TopicState]（没有注入时返回 null，例如单页面测试）。
TopicState? maybeTopicState(BuildContext context) {
  try {
    return Provider.of<TopicState?>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}
