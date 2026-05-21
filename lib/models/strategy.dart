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
    tagline: '双动量打分 · 月度轮动 · 国内宽基/红利/避险 ETF',
    icon: Icons.swap_horiz,
    color: AppColors.amber,
    highlights: [
      '候选池：沪深300 / 中证500 / 创业板 / 科创50 / 红利 / 黄金 / 国债',
      '4 周动量 60% + 12 周动量 40% 综合打分',
      '前 3 名等权配置，负动量自动切换到国债 ETF 防御',
      '输出打分表 + 当期建议持仓 + 简明点评',
    ],
    prompt: '''
请帮我执行一次「ETF 组合轮动」策略，严格按下面的规则操作并以表格 + 简明结论输出。

候选池：
- 510300 沪深300ETF
- 510500 中证500ETF
- 159915 创业板ETF
- 588000 科创50ETF
- 510880 红利ETF
- 518880 黄金ETF
- 511260 十年国债ETF

执行步骤：
1. 调用 Tushare 拉取上述 ETF 近 90 个交易日的日线收盘价（按交易日对齐，停牌缺失请标注，不要伪造）。
2. 计算每只 ETF 的：
   - 4 周（约 20 个交易日）累计收益率 R4
   - 12 周（约 60 个交易日）累计收益率 R12
   - 近 20 个交易日年化波动率 σ（按日收益率标准差 × √252）
3. 动量打分：score = 0.6 × R4 + 0.4 × R12，按 score 降序排名。
4. 仓位生成：
   - 选 score 排名前 3 等权配置（各 1/3）；
   - 若入选标的 score 为负，则该名额的权重转入 511260 十年国债ETF 作为防御；
   - 全部前 3 均为负 → 100% 配置 511260。
5. 严格只使用真实数据；任何因接口失败或停牌导致的缺失，直接标注「数据缺失」，不要凭空填数。

请按以下格式输出：
1) 候选池打分表（代码 / 名称 / R4 / R12 / σ / score / 排名）
2) 当期建议持仓表（代码 / 名称 / 权重）
3) 一句话策略点评（≤80 字，包含当前是「进攻」还是「防御」基调）
''',
  );
}
