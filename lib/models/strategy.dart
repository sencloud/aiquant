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
请帮我执行一次「卖出认沽（Cash-Secured Sell Put）」策略，严格按下面规则操作。
该策略目的：在愿意持有标的的价格附近卖出虚值认沽，赚取权利金；若被指派，按"行权价 - 权利金"的折扣价接货。

第一步：一站式筛选
调用 screen_sell_put 工具，参数如下（除非用户另行指定，使用默认值）：
- underlyings = ["510050.SH","510300.SH","159919.SZ","510500.SH","159915.SZ","588000.SH"]
- min_dte = 7, max_dte = 45     // 剩余 7-45 个自然日
- min_otm = 0.05, max_otm = 0.12 // 虚值幅度 5%-12%
- min_volume = 100, min_oi = 500 // 流动性下限
- top_n = 5

工具会自动：
- 拉每只 ETF 最新收盘价 spot
- 拉对应交易所的 PUT 合约清单（opt_basic）
- 拉当日全市场 PUT 行情（opt_daily）
- 计算 OTM% / 现金担保 cash_required / 静态年化 apy_pct
  / 被指派接货价 effective_buy_price
- 按 apy_pct 降序返回 top_n

第二步：检查结果
- 若 count = 0：直接输出"当前无符合条件合约"，附上 underlyings 里每个标的的 spot / put_contracts 数，并提示"可适当放宽 max_otm 或 min_oi 后重试"。
- 否则：把 contracts 渲染成 markdown 表格（顺序：合约代码 / 标的 / 到期日 / 剩余天数 dte / 行权价 strike / 现价 spot / 权利金 premium / OTM% / APY% / 成交量 vol / 持仓量 oi / 现金担保 cash_required / 接货价 effective_buy_price）。

第三步：在表格下方给出
1) 推荐 1–2 张优选合约（apy_pct 最高且流动性最优），按用户单笔风险 5 万元上限给出"可卖出张数 = floor(50000 / cash_required)"。
2) 风险提示（≤120 字）：被指派后的实际接货价、需要准备的现金担保、若到期日时标的跌破 effective_buy_price 的浮亏计算口径、提前平仓的滑点风险。

严格只使用工具返回的真实数据；任何字段缺失直接标注「数据缺失」，禁止凭空填数。
工具失败 / 返回 error 字段时，直接把错误原样告诉用户，不要重试或编造。
''',
  );
}
