import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../assistant/assistant_screen.dart';

/// 一条常见问题：问题文案 + 点击后发给 AI 助理的 prompt。
class FaqItem {
  const FaqItem({required this.question, required this.prompt});
  final String question;
  final String prompt;
}

/// 品种详情页的常见问题库。
///
/// 设计思路：普通用户点开一只股票 / 期货，最常见的关注点归为几类——
/// 走势研判 / 基本面 / 资金面 / 估值 / 消息面 / 风险 / 操作建议。
/// 期货品种另外追加持仓 / 保证金 / 交割等品种特有问题。
/// 问题以 prompt 形式带上品种代码，直接发给 AI 助理即可作答。
List<FaqItem> faqFor(String tsCode, String name, String assetClass) {
  final q = '$name($tsCode)';
  final stock = [
    FaqItem(
      question: '$name 现在的走势怎么样？',
      prompt: '请分析 $q 最近的走势：拉取近 60 个交易日日线，'
          '说明当前处于什么趋势（上涨/下跌/震荡）、关键支撑位和压力位在哪，'
          '并给出近期量能变化解读。',
    ),
    FaqItem(
      question: '$name 的基本面怎么样？',
      prompt: '请分析 $q 的基本面：主营业务、最新财报的营收和利润同比变化、'
          '毛利率和 ROE 水平，以及所处行业的景气度。用要点列出，通俗易懂。',
    ),
    FaqItem(
      question: '$name 现在估值贵不贵？',
      prompt: '请评估 $q 当前的估值：给出最新 PE / PB，'
          '跟自身历史分位和同行业可比公司对比，判断目前是偏贵还是偏便宜。',
    ),
    FaqItem(
      question: '$name 最近有什么消息？',
      prompt: '请梳理 $q 近期的重要消息面：公司公告、行业新闻、'
          '市场传闻，分别说明利好还是利空，以及对短期股价可能的影响。',
    ),
    FaqItem(
      question: '$name 有什么风险要注意？',
      prompt: '请提示 $q 当前的主要风险：基本面风险（业绩变脸、行业下行）、'
          '技术面风险（破位、放量滞涨）、消息面风险（减持、监管）等，按重要性排序。',
    ),
    FaqItem(
      question: '$name 现在能买吗？',
      prompt: '请综合判断 $q 现在是否适合买入：结合走势、估值、基本面和消息面，'
          '给出倾向性结论（适合/观望/回避）和理由；如果要买，给出参考的买入区间和止损位。'
          '结尾请附风险提示：仅供参考，不构成投资建议。',
    ),
  ];
  final etf = [
    FaqItem(
      question: '$name 现在的走势怎么样？',
      prompt: '请分析 $q 最近的走势：拉取近 60 个交易日日线，'
          '说明当前趋势、关键支撑压力位和量能变化。',
    ),
    FaqItem(
      question: '$name 跟踪什么指数？',
      prompt: '请介绍 $q 跟踪的指数：指数编制规则、前十大权重股、'
          '当前估值水平（PE 分位），以及近期指数表现。',
    ),
    FaqItem(
      question: '$name 现在适合定投吗？',
      prompt: '请判断 $q 现在是否适合定投：结合指数估值分位、近期走势波动，'
          '给出定投建议（适合/观望）和理由。',
    ),
    FaqItem(
      question: '$name 和同类 ETF 比哪个好？',
      prompt: '请对比 $q 与跟踪同一指数或同类主题的其它主流 ETF：'
          '规模、费率、跟踪误差、流动性，给出选择建议。',
    ),
    FaqItem(
      question: '现在买 $name 是什么观点？',
      prompt: '请综合判断 $q 当前是否适合配置：结合估值、走势和市场环境，'
          '给出倾向性结论和理由，并附风险提示。',
    ),
  ];
  final future = [
    FaqItem(
      question: '$name 现在的走势怎么样？',
      prompt: '请分析 $q 最近的走势：拉取近 60 个交易日日线，'
          '说明当前趋势、关键支撑压力位，并结合持仓量变化解读多空力量。',
    ),
    FaqItem(
      question: '$name 的基本面逻辑是什么？',
      prompt: '请分析 $q 的基本面逻辑：供需两端的情况、库存变化、'
          '季节性规律，以及当前市场的主要矛盾。',
    ),
    FaqItem(
      question: '$name 交易一手要多少钱保证金？',
      prompt: '请计算 $q 交易一手需要的资金：给出合约乘数、'
          '当前价格对应的合约价值，按常见保证金比例估算一手保证金金额。',
    ),
    FaqItem(
      question: '$name 现在适合做多还是做空？',
      prompt: '请综合判断 $q 当前适合做多、做空还是观望：'
          '结合趋势、持仓量、基差和基本面，给出倾向性结论和理由，'
          '并提示关键止损位。结尾附风险提示：仅供参考，不构成投资建议。',
    ),
    FaqItem(
      question: '$name 有什么风险要注意？',
      prompt: '请提示 $q 交易的主要风险：波动风险、保证金追加风险、'
          '交割/移仓风险、政策风险等，按重要性排序并说明应对方式。',
    ),
  ];
  final index = [
    FaqItem(
      question: '$name 现在的走势怎么样？',
      prompt: '请分析 $q 最近的走势：拉取近 60 个交易日日线，'
          '说明当前趋势和关键点位。',
    ),
    FaqItem(
      question: '$name 最近涨跌的主要原因是？',
      prompt: '请分析 $q 近期涨跌的主要驱动因素：权重板块表现、'
          '宏观数据、政策消息面，用要点列出。',
    ),
    FaqItem(
      question: '大盘（$name）现在适合加仓吗？',
      prompt: '请判断当前以 $q 为参照的市场环境适合加仓还是观望：'
          '结合指数走势、成交量和市场情绪，给出倾向性结论和理由，附风险提示。',
    ),
  ];

  switch (assetClass) {
    case 'ETF':
      return etf;
    case '期货':
      return future;
    case '指数':
      return index;
    default:
      return stock;
  }
}

/// 品种详情页底部的"常见问题"区块。
/// 每个分类是一个 ExpansionTile 下拉；点问题 → 跳转 AI 助理自动提问。
class FaqSection extends StatelessWidget {
  const FaqSection({super.key, required this.tsCode, required this.name,
      required this.assetClass});
  final String tsCode;
  final String name;
  final String assetClass;

  @override
  Widget build(BuildContext context) {
    final items = faqFor(tsCode, name, assetClass);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('常见问题',
              style: TextStyle(
                  color: AppColors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0)),
        ),
        // 单个下拉分组：全部问题放一组，简洁直接。
        Theme(
          // 去掉 ExpansionTile 默认的分割线颜色干扰。
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            iconColor: AppColors.amber,
            collapsedIconColor: AppColors.textTertiary,
            title: Text('看看大家都在问什么',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            subtitle: Text('点击问题由 AI 助理解答',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              for (final f in items)
                _FaqTile(question: f.question, prompt: f.prompt),
            ],
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.prompt});
  final String question;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _ask(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.help_outline,
                    size: 15, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.north_east,
                    size: 13, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 跳到 AI 助理并自动发送问题（与组合页 _askAssistant 同套路）。
  void _ask(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AssistantScreen(
        launch: AssistantLaunch(initialMessage: prompt, autoSend: true),
      ),
    ));
  }
}
