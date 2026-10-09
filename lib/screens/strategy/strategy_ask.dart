import 'package:flutter/material.dart';

import '../../models/strategy_snapshot.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';

/// 策略页上的「问 AI」：把策略上下文（本期名单、因子、持仓成本）拼进 prompt，
/// 让助理带着这些前提回答，而不是从零问一句"分析一下中国联通"。
///
/// 设计取舍：点一下先弹三个候选问题，而不是直接发问——用户往往不知道该问什么，
/// 给三个角度（为什么选它 / 现在贵不贵 / 我该怎么办）比空聊有用得多。
Future<void> askStrategyAI(
  BuildContext context,
  StrategySnapshot snap, {
  String? code,
  String? name,
  String? role,
  double? cost,
}) async {
  final questions =
      _questions(snap, code: code, name: name, role: role, cost: cost);
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              (name == null || name.isEmpty) ? '让 AI 核对这份策略' : '问 AI：$name',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          for (final q in questions)
            InkWell(
              onTap: () => Navigator.pop(ctx, q),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.north_east,
                        size: 14, color: AppColors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(q,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                              height: 1.45)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => AssistantScreen(
      launch: AssistantLaunch(initialMessage: picked, autoSend: true),
    ),
  ));
}

/// 生成候选问题。带上策略名、目标名单与持仓成本，让回答有前提。
List<String> _questions(
  StrategySnapshot snap, {
  String? code,
  String? name,
  String? role,
  double? cost,
}) {
  final label = (name == null || name.isEmpty) ? (code ?? '') : name;
  final symbol = (code == null || code.isEmpty) ? label : '$label($code)';
  final meta = snap.meta;
  final targetNames =
      snap.action.target.map((t) => t.name.isEmpty ? t.code : t.name).join('、');

  if (label.isEmpty) {
    return [
      '我这套主策略是「${meta.name}」，本期目标名单：$targetNames。'
          '请帮我核对这份名单，有没有基本面硬伤或行业过度集中的问题。',
      '请结合今天的实时行情核对本期调仓清单是否执行得下去：'
          '有没有停牌、涨跌停、流动性不足的标的。',
      '策略本期${snap.action.changed ? '需要调仓' : '无需调仓'}，'
          '请结合最近的宏观数据和行业新闻，说明有没有需要提前调整的理由。',
    ];
  }

  final held = role == '持仓';
  final costHint = (held && cost != null && cost > 0)
      ? '我的持仓成本约 ${cost.toStringAsFixed(2)} 元。'
      : '';
  return [
    '$symbol 被这套主策略选中（${meta.name}），请说明它在估值、现金流质量、'
        '低波动这几类因子上的得分意味着什么，以及主要投资逻辑和风险。',
    '$symbol 现在的估值和基本面怎么样？结合最新财报和同业对比，'
        '说明是偏贵还是偏便宜。$costHint',
    held
        ? '$symbol 最近走势和消息面如何？$costHint'
            '结合策略的月度调仓节奏，我接下来应该重点跟踪哪些指标？'
        : '$symbol 最近的走势和消息面如何？如果我要按策略买入，'
            '现在这个位置合适吗？请给出关键价位参考。',
  ];
}
