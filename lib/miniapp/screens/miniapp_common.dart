import 'package:flutter/material.dart';

import '../../core/api/auth_models.dart';

/// 把接口异常翻成一句给人看的话。
String miniAppErrorText(Object e) {
  if (e is ApiException) {
    if (e.message.isNotEmpty) return e.message;
    return '请求失败（${e.statusCode}）';
  }
  return '网络不太好，稍后再试';
}

void showMiniAppSnack(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text)));
}

/// 每个主题在工坊空白页上给的示例需求。
List<String> miniAppExamples(String topic) => topic == 'fishing'
    ? const [
        '对比我常去的几个水库明天的出钓条件',
        '按水温和季节给我配饵料比例',
        '统计我这个月的渔获',
      ]
    : const [
        '每天早上看棕榈油主力合约的涨跌和持仓',
        '沪深300 ETF 定投计算器',
        '盯豆油和棕榈油的价差',
      ];

/// 工坊阶段 → 文案。
String miniAppStageLabel(String stage) => switch (stage) {
      'validating' => '正在检查结构…',
      'dry_run' => '正在试着取一次数据…',
      'repairing' => '发现问题，正在修正…',
      _ => '正在理解你的需求…',
    };
