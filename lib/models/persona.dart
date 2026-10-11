import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 一个 Persona = 一个 AI 角色（投资大师 / 钓鱼老师……）。
///
/// 主题化之后，人设 prompt 统一由**服务端**持有（backend/internal/topic），
/// 客户端只保留 id、展示名、图标、配色和欢迎提问；发消息时只上送 persona id。
/// 钱主题的 11 个 prompt 逐字搬到了服务端，老版本 App 仍会通过 system_hint
/// 上送同一段文字，两条路径拼出的 system prompt 完全一致。
class Persona {
  const Persona({
    required this.id,
    required this.displayName,
    required this.title,
    required this.icon,
    Color? color,
    required this.welcomeSuggestions,
    this.topic = 'money',
  }) : _color = color;

  /// 内部 id（持久化到 ChatSession）
  final String id;

  /// 桌面/会话页显示用的中文名
  final String displayName;

  /// 一句话副标题
  final String title;

  /// 头像图标
  final IconData icon;

  /// 角色色（Picker / 头像背景）。不指定时跟随当前主题的品牌色。
  final Color? _color;
  Color get color => _color ?? AppColors.amber;

  /// 所属主题 id（money / fishing）。
  final String topic;

  /// 欢迎屏推荐提问（每个 Persona 风格不同）
  final List<String> welcomeSuggestions;
}

/// 内置 Persona 库 — 全部为本仓库自研中文 prompt。
class Personas {
  Personas._();

  static const String defaultId = 'default';

  /// 钓鱼主题的默认人设 id。
  static const String fishingDefaultId = 'fishing_buddy';

  /// 某主题的人设列表。
  static List<Persona> forTopic(String topic) =>
      topic == 'fishing' ? fishing : all;

  /// 某主题的默认人设 id。
  static String defaultIdFor(String topic) =>
      topic == 'fishing' ? fishingDefaultId : defaultId;

  /// 喜爱钱的人设（也是 DING 定时任务可选的人设）。
  static final List<Persona> all = <Persona>[
    _default,
    _buffett,
    _graham,
    _lynch,
    _munger,
    _dalio,
    _soros,
    _quant,
    _commodityFutures,
    _finFutures,
    _optionStrategist,
  ];

  /// 按 id 找人设；[topic] 给定时只在该主题里找，找不到回落到该主题默认人设。
  static Persona byId(String? id, {String topic = 'money'}) {
    final list = forTopic(topic);
    final fallback = topic == 'fishing' ? _fishingBuddy : _default;
    if (id == null) return fallback;
    return list.firstWhere(
      (p) => p.id == id,
      orElse: () => fallback,
    );
  }

  /// 喜爱钓鱼的人设（prompt 在服务端 backend/internal/topic/fishing.go）。
  static final List<Persona> fishing = <Persona>[
    _fishingBuddy,
    _taidiaoTeacher,
    _lureCoach,
  ];

  static const Persona _fishingBuddy = Persona(
    id: 'fishing_buddy',
    displayName: '综合钓友',
    title: '台钓 · 传统钓 · 路亚，什么都聊',
    icon: Icons.phishing_rounded,
    topic: 'fishing',
    welcomeSuggestions: [
      '这周末去水库钓鲫鱼，天气合适吗？',
      '秋天钓鲤鱼用什么饵料配方？',
      '新手第一次野钓需要准备什么？',
    ],
  );

  static const Persona _taidiaoTeacher = Persona(
    id: 'taidiao_teacher',
    displayName: '台钓老师',
    title: '调漂 · 线组 · 饵料 · 节奏',
    icon: Icons.straighten_rounded,
    color: Color(0xFF2F5EA8),
    topic: 'fishing',
    welcomeSuggestions: [
      '调四钓二是什么意思？怎么调？',
      '黑坑钓鲤鱼主线子线怎么配？',
      '鲫鱼吃口轻，漂相怎么看？',
    ],
  );

  static const Persona _lureCoach = Persona(
    id: 'lure_coach',
    displayName: '路亚教练',
    title: '鳜鱼 · 翘嘴 · 鲈鱼 · 黑鱼',
    icon: Icons.set_meal_rounded,
    color: Color(0xFF6D4AA8),
    topic: 'fishing',
    welcomeSuggestions: [
      '秋天路亚翘嘴用什么假饵？',
      '新手路亚竿怎么选？',
      '鳜鱼路亚什么时段最好？',
    ],
  );

  // ───────────────────────── 内置 Persona ─────────────────────────

  static const Persona _default = Persona(
    id: 'default',
    displayName: '研究助理',
    title: '中性、客观、结构化',
    icon: Icons.support_agent,
    welcomeSuggestions: [
      '帮我分析一下沪深 300 近期的成交结构',
      '600519、000858、300750 的最新行情和估值对比',
      '最近 5 天涨幅靠前的有色金属个股',
      '波动率低的 ETF 组合应该怎么搭？',
    ],
  );

  static const Persona _buffett = Persona(
    id: 'buffett',
    displayName: '巴菲特',
    title: '价值投资 · 长期持有 · 护城河',
    icon: Icons.account_balance,
    color: Color(0xFFD97706),
    welcomeSuggestions: [
      '帮我用价值投资框架评估贵州茅台',
      '招商银行的护城河怎么样，值得长期持有吗？',
      '最近市场恐慌，巴菲特会怎么看？',
      '估算一下伊利股份的内在价值（DCF 思路）',
    ],
  );

  static const Persona _graham = Persona(
    id: 'graham',
    displayName: '格雷厄姆',
    title: '深度价值 · 安全边际 · 净流动资产',
    icon: Icons.shield,
    color: Color(0xFF1E40AF),
    welcomeSuggestions: [
      '用格雷厄姆 7 项指标筛选沪深 300 里的防御型标的',
      '当前 A 股有没有真正的"网-网"股？',
      '宝钢股份 PB 不到 1，符合深度价值标准吗？',
      'PE 15 倍以下、连续 5 年分红的银行股有哪些？',
    ],
  );

  static const Persona _lynch = Persona(
    id: 'lynch',
    displayName: '林奇',
    title: '成长投资 · 行业研究 · PEG',
    icon: Icons.trending_up,
    color: Color(0xFF059669),
    welcomeSuggestions: [
      '用 PEG 评估比亚迪、宁德时代的估值',
      '帮我从 6 类股票框架分类一下美的集团',
      '当下中国市场可能的"十倍股"特征是什么？',
      '海底捞算是什么类型，PEG 怎么算？',
    ],
  );

  static const Persona _munger = Persona(
    id: 'munger',
    displayName: '芒格',
    title: '多元思维 · 反向 · 第一性原理',
    icon: Icons.psychology,
    color: Color(0xFF7C3AED),
    welcomeSuggestions: [
      '用反向思考分析一下白酒板块的风险',
      '为什么大多数散户在 A 股长期亏钱？（认知偏误角度）',
      '从激励机制看央企改革会不会真的提估值？',
      '帮我审视一下我对新能源车行业的判断有没有偏误',
    ],
  );

  static const Persona _dalio = Persona(
    id: 'dalio',
    displayName: '达里奥',
    title: '宏观周期 · 全天候 · 风险平价',
    icon: Icons.public,
    color: Color(0xFF0891B2),
    welcomeSuggestions: [
      '当前中国经济处在达里奥周期的哪个位置？',
      '股、债、黄金、商品的全天候组合应该怎么配？',
      '分析中美利差对人民币和 A 股的影响',
      '从大国兴衰看未来 5 年的资产配置思路',
    ],
  );

  static const Persona _soros = Persona(
    id: 'soros',
    displayName: '索罗斯',
    title: '反身性 · 宏观对冲 · 趋势捕捉',
    icon: Icons.bolt,
    color: Color(0xFFE11D48),
    welcomeSuggestions: [
      '用反身性分析一下 AI 概念的资金流叙事',
      '人民币汇率背后有没有反身性闭环？',
      '历史上的 A 股大牛市哪些是反身性驱动的？',
      '如果做空一个板块，止损条件应该怎么设？',
    ],
  );

  static const Persona _quant = Persona(
    id: 'quant',
    displayName: '量化研究',
    title: '因子 · 技术分析 · 数据驱动',
    icon: Icons.analytics,
    color: Color(0xFF2563EB),
    welcomeSuggestions: [
      '用 6 大因子打分沪深 300 里的银行股',
      '600519 近 60 日的动量、波动率、Sharpe 怎么样？',
      '科创 50 当前的技术形态（MA / MACD / 布林）',
      '设计一个低波动 + 高股息的因子组合',
    ],
  );

  // ─────────────── 期货 / 期权 专家 Personas ───────────────

  static const Persona _commodityFutures = Persona(
    id: 'commodity_futures',
    displayName: '商品期货研究员',
    title: '产业链 · 库存周期 · 基差 · 跨期套利',
    icon: Icons.local_shipping,
    color: Color(0xFFB45309),
    welcomeSuggestions: [
      '螺纹钢主力合约现在多少？基差怎么样',
      '焦煤 + 焦炭 + 铁矿的产业链价差分析',
      '原油主力合约近期持仓结构变化',
      '从库存周期看豆粕未来 1 个月怎么走',
    ],
  );

  static const Persona _finFutures = Persona(
    id: 'fin_futures',
    displayName: '股指国债专家',
    title: 'IF/IC/IH/IM/T · 期现套利 · Beta 对冲',
    icon: Icons.candlestick_chart,
    color: Color(0xFF0F766E),
    welcomeSuggestions: [
      'IF 主力当前贴水多少？年化折算',
      'IM / IH 套利 spread 历史分位',
      '10 年期国债期货主力合约 + CTD 分析',
      '帮我对冲 100 万沪深 300 多头，需要几手 IF？',
    ],
  );

  static const Persona _optionStrategist = Persona(
    id: 'option_strategist',
    displayName: '期权策略师',
    title: '希腊字母 · IV · 价差 · 卖方思维',
    icon: Icons.scatter_plot,
    color: Color(0xFFBE185D),
    welcomeSuggestions: [
      '50ETF 期权当前主力月份 IV 是多少？',
      '帮我设计一个沪深300 ETF 的 Iron Condor',
      '当前 sell put 哪几张 APY 最高？',
      'IO 沽-购 25Delta 偏度怎么样，反映了什么',
    ],
  );
}
