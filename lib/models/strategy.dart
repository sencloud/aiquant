import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 一个 Strategy = 「策略之王」里可一键运行的量化/配置策略。
///
/// 点击后会以预设 prompt 让 AI 助理调用 Tushare 数据并按统一格式产出
/// 策略报告（持仓建议、动量打分表、风控提示）。
class Strategy {
  const Strategy({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.color,
    required this.highlights,
    required this.prompt,
  });

  /// 内部 id（持久化 / 路由用）
  final String id;

  /// 卡片标题（如「ETF 组合轮动」）
  final String name;

  /// 一句话副标题
  final String tagline;

  /// 卡片图标
  final IconData icon;

  /// 主题色（卡片边框 / icon 背景）
  final Color color;

  /// 卡片正文的特性列表（4 条以内最佳）
  final List<String> highlights;

  /// 一键运行时直接发送给 AI 的中文 prompt。
  ///
  /// prompt 内必须自包含「候选池 / 计算规则 / 输出格式」三段，
  /// 让任何 persona 拿到都能复现，不依赖上下文。
  final String prompt;
}

/// 内置策略库 — 全部为本仓库自研中文 prompt。
class Strategies {
  Strategies._();

  static const String defaultId = 'etf_rotation';

  static const List<Strategy> all = <Strategy>[
    _etfRotation,
    _sellPut,
  ];

  static Strategy byId(String? id) {
    if (id == null) return _etfRotation;
    for (final s in all) {
      if (s.id == id) return s;
    }
    return _etfRotation;
  }

  // ───────────────────────── 内置策略 ─────────────────────────

  static const Strategy _etfRotation = Strategy(
    id: 'etf_rotation',
    name: 'ETF 组合轮动',
    tagline: '双动量打分 · 月度轮动 · 历史 3 年回测 + 当期建议',
    icon: Icons.swap_horiz,
    color: AppColors.amber,
    highlights: [
      '候选池：沪深300 / 中证500 / 创业板 / 科创50 / 红利 / 黄金 / 国债',
      '4 周动量 60% + 12 周动量 40% 综合打分',
      '先回测过去 3 年：总收益 / 年化 / Sharpe / 最大回撤 / 月胜率',
      '再给当期建议持仓 + 进攻 / 防御点评',
    ],
    prompt: '''
请帮我执行一次「ETF 组合轮动」策略，先看历史回测，再给当期建议。
严格按下面三步操作，所有数据走工具，禁止凭空填数。

候选池（除非用户另行指定，默认使用以下 7 只）：
- 510300 沪深300ETF
- 510500 中证500ETF
- 159915 创业板ETF
- 588000 科创50ETF
- 510880 红利ETF
- 518880 黄金ETF
- 511260 十年国债ETF（也作为负动量时的防御标的）

第一步：历史回测
调用 backtest_etf_rotation 工具，参数：
- symbols = 上述候选池
- start_date = 今天前 3 年
- rebalance_days = 20, short_window = 20, long_window = 60
- w_short = 0.6, w_long = 0.4, top_n = 3
- defensive = "511260", benchmark = "510300"
拿到结果后，给出一段「回测业绩」摘要：
- 总收益% / 年化收益% / 年化波动% / Sharpe / 最大回撤% / 月胜率%
- 同期 benchmark (510300) 的总收益% / 年化% / 最大回撤%，并写出 alpha
- 引用 monthly_nav 末 3-4 个点说明近期净值走势

第二步：当期持仓建议
调用 Tushare 拉取候选池近 90 个交易日的日线收盘价，计算：
- R4 = 近 20 个交易日累计收益率
- R12 = 近 60 个交易日累计收益率
- σ = 近 20 个交易日年化波动率
- score = 0.6 × R4 + 0.4 × R12，按 score 降序
仓位生成：score 前 3 等权（各 1/3）；任一入选 score 为负 → 该名额转入 511260；全部为负 → 100% 511260。

第三步：以下面三个块输出，markdown 表格 + 简短结论：
1) 历史回测摘要表 + 一段（≤120 字）评价（说明这套策略在过去 3 年是否跑赢 benchmark、回撤是否可接受）
2) 候选池当期打分表（代码 / 名称 / R4 / R12 / σ / score / 排名）
3) 当期建议持仓表（代码 / 名称 / 权重）+ ≤80 字策略点评（当前是「进攻」还是「防御」基调）

任何接口失败 / 数据缺失 → 直接标「数据缺失」，不要凭空填数。
''',
  );

  static const Strategy _sellPut = Strategy(
    id: 'sell_put',
    name: '卖出认沽（Sell Put）',
    tagline: '现金担保 · 收权利金 · 心仪价格接货',
    icon: Icons.south_west,
    color: Color(0xFF16A34A),
    highlights: [
      '候选池：上证50 / 沪深300 / 中证500 / 创业板 / 科创50 ETF 期权',
      '筛选剩余 7–45 天、虚值 5–12% 的近月合约',
      '按"静态年化权利金 = 权利金 / 现金担保 × 365/剩余天数"排序',
      '输出推荐合约 + 现金担保 + 被指派后的接货成本',
    ],
    prompt: '''
请帮我执行一次「卖出认沽（Cash-Secured Sell Put）」策略，严格按下面的规则操作并以表格 + 简明结论输出。
该策略目的：在愿意持有标的的价格附近卖出虚值认沽，赚取权利金；若被指派，按"行权价 - 权利金"的折扣价接货。

候选标的池（仅 ETF 期权，便于现金担保）：
- 510050 上证50ETF
- 510300 沪深300ETF（上交所期权）
- 159919 沪深300ETF（深交所期权）
- 510500 中证500ETF
- 159915 创业板ETF
- 588000 科创50ETF

执行步骤：
1. 调用 Tushare opt_basic 拉取上述标的当前在交易的 **看跌期权**（opt_type=P）合约清单，仅保留剩余到期日 7–45 个自然日的合约。
2. 调用 fund_daily 拉取每个标的 ETF 的最新收盘价 S。
3. 调用 opt_daily 拉取每个候选合约最新一日的：收盘价（=权利金参考 P）、成交量 V、持仓量 OI。
4. 计算每个合约：
   - 虚值幅度 OTM% = (S - K) / S（K 为行权价；> 0 即虚值认沽）
   - 现金担保 Cash = K × 合约乘数（ETF 期权默认 10000）
   - 静态年化权利金 APY = P × 10000 / Cash × (365 / 剩余自然日)
   - 被指派后接货成本 EffCost = K - P
5. 过滤：
   - 仅保留 5% ≤ OTM% ≤ 12% 的合约（"足够虚值 + 不过分远离"）
   - 当日 V < 100 张 或 OI < 500 张的合约剔除（流动性下限）
6. 排序：按 APY 降序，取前 5。
7. 严格只使用真实数据；任何接口失败 / 数据缺失，直接在对应字段标注「数据缺失」，不要凭空填数；若全候选池都被过滤掉，请直接结论"当前无符合条件合约"。

请按以下格式输出：
1) 候选合约表（合约代码 / 标的 / 到期日 / 剩余天数 / 行权价 / 权利金 / OTM% / APY% / 成交量 / 持仓量）
2) 推荐 1–2 张优选合约 + 建议卖出张数（按用户单笔风险 5 万元上限保守取整，写明所需现金担保）
3) 风险提示（≤120 字）：被指派的接货价、需要准备的现金、若标的跌破 EffCost 的浮亏计算口径
''',
  );
}
