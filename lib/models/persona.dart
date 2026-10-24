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

  /// 兴趣圈（方案五）新开四个主题的默认人设 id。
  static const String catDefaultId = 'cat_buddy';
  static const String coffeeDefaultId = 'coffee_pourover';
  static const String campingDefaultId = 'camp_gear';
  static const String hanfuDefaultId = 'hanfu_history';

  /// 伴侣主线的默认人设（喜爱）。
  static const String companionDefaultId = 'xiai';

  /// 某主题的人设列表。
  static List<Persona> forTopic(String topic) {
    switch (topic) {
      case 'fishing':
        return fishing;
      case 'cat':
        return cat;
      case 'coffee':
        return coffee;
      case 'camping':
        return camping;
      case 'hanfu':
        return hanfu;
      case 'companion':
        return companion;
      default:
        return all;
    }
  }

  /// 某主题的默认人设 id。
  static String defaultIdFor(String topic) {
    switch (topic) {
      case 'fishing':
        return fishingDefaultId;
      case 'cat':
        return catDefaultId;
      case 'coffee':
        return coffeeDefaultId;
      case 'camping':
        return campingDefaultId;
      case 'hanfu':
        return hanfuDefaultId;
      case 'companion':
        return companionDefaultId;
      default:
        return defaultId;
    }
  }

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

  /// 唯一的伴侣：喜爱（prompt 在服务端 topic=companion）。
  static final List<Persona> companion = [
    const Persona(
      id: 'xiai',
      displayName: '喜爱',
      title: 'AI 伴侣',
      icon: Icons.favorite_rounded,
      topic: 'companion',
      welcomeSuggestions: [
        '今天有点累，陪我说会儿话吧',
        '收盘了，想跟你聊聊今天',
        '周末想去钓鱼，你陪我挑个地方？',
      ],
    ),
  ];

  /// 按 id 找人设；[topic] 给定时只在该主题里找，找不到回落到该主题默认人设。
  static Persona byId(String? id, {String topic = 'money'}) {
    final list = forTopic(topic);
    final fallback = list.firstWhere(
      (p) => p.id == defaultIdFor(topic),
      orElse: () => _default,
    );
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

  // ---- 兴趣圈（方案五）：四个新主题的人设 ----
  // prompt 一律在服务端（backend/internal/topic/{cat,coffee,camping,hanfu}.go），
  // 客户端只保留 id、展示名、图标与欢迎提问 —— 与钓鱼主题同一套做法。

  /// 喜爱养猫的人设。
  static const List<Persona> cat = <Persona>[
    _catBuddy,
    _catNutrition,
    _catBehavior,
  ];

  /// 喜爱咖啡的人设。
  static const List<Persona> coffee = <Persona>[
    _coffeePourover,
    _coffeeEspresso,
    _coffeeBean,
  ];

  /// 喜爱露营的人设。
  static const List<Persona> camping = <Persona>[
    _campGear,
    _campWeather,
    _campBeginner,
  ];

  /// 喜爱汉服的人设。
  static const List<Persona> hanfu = <Persona>[
    _hanfuHistory,
    _hanfuStyling,
    _hanfuBeginner,
  ];

  static const Persona _catBuddy = Persona(
    id: 'cat_buddy',
    displayName: '综合猫友',
    title: '喂养 · 护理 · 症状要不要去医院',
    icon: Icons.pets_rounded,
    topic: 'cat',
    welcomeSuggestions: [
      '它这周掉毛变多，正常吗？',
      '这两款猫粮哪个更适合它？',
      '半夜跑酷怎么治？',
    ],
  );

  static const Persona _catNutrition = Persona(
    id: 'cat_nutrition',
    displayName: '营养与喂养',
    title: '成分 · 喂食量 · 换粮节奏',
    icon: Icons.restaurant_rounded,
    topic: 'cat',
    welcomeSuggestions: [
      '猫粮成分表怎么看？',
      '冻干能当主食吗？',
      '换粮软便怎么过渡？',
    ],
  );

  static const Persona _catBehavior = Persona(
    id: 'cat_behavior',
    displayName: '行为解读',
    title: '乱尿 · 抓挠 · 多猫关系',
    icon: Icons.psychology_rounded,
    topic: 'cat',
    welcomeSuggestions: [
      '它总在床上尿，怎么办？',
      '两只猫一直打架怎么处理？',
      '怎么让它不抓沙发？',
    ],
  );

  static const Persona _coffeePourover = Persona(
    id: 'coffee_pourover',
    displayName: '手冲咖啡师',
    title: '研磨 · 水温 · 粉水比 · 注水',
    icon: Icons.coffee_rounded,
    topic: 'coffee',
    welcomeSuggestions: [
      '新买的豆子怎么冲才对味？',
      '手冲总是发苦，问题出在哪？',
      'V60 和蛋糕杯差在哪？',
    ],
  );

  static const Persona _coffeeEspresso = Persona(
    id: 'coffee_espresso',
    displayName: '意式与奶咖',
    title: '萃取 · 粉液比 · 打奶 · 拉花',
    icon: Icons.coffee_maker_rounded,
    topic: 'coffee',
    welcomeSuggestions: [
      '浓缩总是偏酸怎么调？',
      '家用机打奶总是打过头',
      '拉花从哪个图案练起？',
    ],
  );

  static const Persona _coffeeBean = Persona(
    id: 'coffee_bean',
    displayName: '选豆与风味',
    title: '产区 · 处理法 · 养豆期',
    icon: Icons.local_cafe_rounded,
    topic: 'coffee',
    welcomeSuggestions: [
      '想喝果酸明显的豆子怎么挑？',
      '日晒和水洗差在哪？',
      '豆子养几天最好喝？',
    ],
  );

  static const Persona _campGear = Persona(
    id: 'camp_gear',
    displayName: '装备清单官',
    title: '帐篷 · 睡袋温标 · 炉具 · 电源',
    icon: Icons.luggage_rounded,
    topic: 'camping',
    welcomeSuggestions: [
      '两人两天一夜要带什么？',
      '睡袋温标怎么选？',
      '帐篷怎么挑？',
    ],
  );

  static const Persona _campWeather = Persona(
    id: 'camp_weather',
    displayName: '天气与风险',
    title: '风 · 雨 · 露点 · 山洪 · 失温',
    icon: Icons.thunderstorm_rounded,
    topic: 'camping',
    welcomeSuggestions: [
      '这周末适合露营吗？',
      '晚上露水大怎么办？',
      '多大的风不建议搭天幕？',
    ],
  );

  static const Persona _campBeginner = Persona(
    id: 'camp_beginner',
    displayName: '新手向导',
    title: '从一次过夜开始',
    icon: Icons.terrain_rounded,
    topic: 'camping',
    welcomeSuggestions: [
      '新手第一次露营去哪？',
      '公园野餐式露营要买什么？',
      '第一次过夜要注意什么？',
    ],
  );

  static const Persona _hanfuHistory = Persona(
    id: 'hanfu_history',
    displayName: '形制考据',
    title: '形制 · 出土与文献依据',
    icon: Icons.history_edu_rounded,
    topic: 'hanfu',
    welcomeSuggestions: [
      '宋制褙子配什么下裙？',
      '这套是不是形制正确的？',
      '明制有哪些常见形制？',
    ],
  );

  static const Persona _hanfuStyling = Persona(
    id: 'hanfu_styling',
    displayName: '穿搭妆造',
    title: '场合 · 温度 · 发型 · 妆容',
    icon: Icons.checkroom_rounded,
    topic: 'hanfu',
    welcomeSuggestions: [
      '明天 18 度，穿汉服怎么搭？',
      '日常通勤穿汉服会不会太隆重？',
      '明制怎么盘发？',
    ],
  );

  static const Persona _hanfuBeginner = Persona(
    id: 'hanfu_beginner',
    displayName: '入坑向导',
    title: '第一套 · 尺码 · 面料 · 预算',
    icon: Icons.school_rounded,
    topic: 'hanfu',
    welcomeSuggestions: [
      '新手第一套买什么形制？',
      '怎么量尺寸才不踩坑？',
      '租一套和买一套哪个划算？',
    ],
  );

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
