/// Lightweight port of `services::markets::ChinaMarket` from the Qt project.
///
/// Centralises symbol normalisation rules (SH/SZ/BJ for stocks, the various
/// futures exchange suffixes used by Tushare) and a tiny seed catalogue used
/// for offline display names. Live data still comes from Tushare.
class ChinaMarket {
  static String normalizeSymbol(String input) {
    final s = input.trim().toUpperCase().replaceAll(' ', '');
    if (s.isEmpty) return '';

    // Already qualified — fix the futures-exchange suffix differences.
    if (s.contains('.')) {
      if (s.endsWith('.CZCE')) return s.substring(0, s.length - 1); // CZCE → CZC
      if (s.endsWith('.SHFE')) return '${s.substring(0, s.length - 5)}.SHF';
      if (s.endsWith('.GFEX')) return '${s.substring(0, s.length - 5)}.GFE';
      if (s.endsWith('.CFFEX')) return '${s.substring(0, s.length - 6)}.CFE';
      return s;
    }

    // Pure 6-digit numeric → infer SSE/SZSE/BSE.
    final sixDigit = RegExp(r'^\d{6}$');
    if (sixDigit.hasMatch(s)) {
      if (s.startsWith('6') || s.startsWith('900')) return '$s.SH';
      if (s.startsWith('0') || s.startsWith('3') || s.startsWith('200')) {
        return '$s.SZ';
      }
      if (s.startsWith('4') || s.startsWith('8') || s.startsWith('920')) {
        return '$s.BJ';
      }
    }

    return s;
  }

  static const _futureSuffixes = {
    '.CZC', '.CZCE',
    '.DCE',
    '.SHF', '.SHFE',
    '.INE',
    '.GFE', '.GFEX',
    '.CFE', '.CFFEX',
  };

  static bool isFuture(String symbol) {
    final s = symbol.toUpperCase();
    return _futureSuffixes.any(s.endsWith);
  }

  static bool isIndex(String symbol) {
    final s = symbol.toUpperCase();
    if (s.startsWith('000') && s.endsWith('.SH')) return true;
    if (s.startsWith('399') && s.endsWith('.SZ')) return true;
    return false;
  }

  static bool isStock(String symbol) {
    final s = symbol.toUpperCase();
    return s.endsWith('.SH') || s.endsWith('.SZ') || s.endsWith('.BJ');
  }

  static String exchangeOf(String symbol) {
    final s = symbol.toUpperCase();
    if (s.endsWith('.SH')) return 'SSE';
    if (s.endsWith('.SZ')) return 'SZSE';
    if (s.endsWith('.BJ')) return 'BSE';
    if (s.endsWith('.CZC') || s.endsWith('.CZCE')) return '郑商所';
    if (s.endsWith('.DCE')) return '大商所';
    if (s.endsWith('.SHF') || s.endsWith('.SHFE')) return '上期所';
    if (s.endsWith('.INE')) return '上海能源';
    if (s.endsWith('.GFE') || s.endsWith('.GFEX')) return '广期所';
    if (s.endsWith('.CFE') || s.endsWith('.CFFEX')) return '中金所';
    return '';
  }

  static String assetClassOf(String symbol) {
    if (isFuture(symbol)) return '期货';
    if (isIndex(symbol)) return '指数';
    if (isStock(symbol)) return '股票';
    return '其它';
  }

  /// 用于 UI 展示的"短代码"——剔除交易所后缀。
  /// 600941.SH → 600941，SR2609.CZC → SR2609。
  static String displaySymbol(String symbol) {
    final i = symbol.indexOf('.');
    return i < 0 ? symbol : symbol.substring(0, i);
  }

  /// 仓位单位：股 / 手 / 份。
  static String quantityUnit(String assetClass, {String? symbol}) {
    if (assetClass == '期货') return '手';
    if (assetClass == 'ETF' || assetClass == 'LOF') return '份';
    if (assetClass == '指数') return '点';
    return '股';
  }

  /// 单笔下单的最小变动数量（手数 → 标的单位）：
  /// - A 股：1 手 = 100 股
  /// - 港股 / B 股不在 scope，沿用 100
  /// - ETF / LOF：1 手 = 100 份
  /// - 期货：1 手 = 1 张合约（实际市值乘 multiplier，由 contractMultiplier 提供）
  static int lotSize(String assetClass) {
    switch (assetClass) {
      case '股票':
      case 'ETF':
      case 'LOF':
        return 100;
      case '期货':
        return 1;
      default:
        return 1;
    }
  }

  /// 中国期货品种合约乘数（每手对应几个标的单位 × 价格 = 合约价值）。
  /// 数据按交易所公开合约规则汇总，覆盖 A 股投资者最常见的品种；
  /// 未列出的品种回退到 1（让总价 = 价格 × 手数，仅作占位）。
  static const Map<String, double> _futureMultiplier = {
    // 上期所 (SHFE / .SHF)
    'CU': 5, // 铜 5 吨/手
    'AL': 5, // 铝
    'ZN': 5, // 锌
    'PB': 5, // 铅
    'SN': 1, // 锡 1 吨
    'NI': 1, // 镍
    'AU': 1000, // 黄金 1000 克/手
    'AG': 15, // 白银 15 千克/手
    'RB': 10, // 螺纹钢 10 吨
    'WR': 10, // 线材
    'HC': 10, // 热卷
    'SS': 5, // 不锈钢
    'BU': 10, // 沥青
    'RU': 10, // 天然橡胶
    'NR': 10, // 20 号胶 (INE)
    'FU': 10, // 燃料油
    'SP': 10, // 纸浆
    'BC': 5, // 国际铜 (INE)
    'SC': 1000, // 原油 1000 桶/手 (INE)
    // 大商所 (DCE / .DCE)
    'A': 10, // 黄大豆 1
    'B': 10, // 黄大豆 2
    'M': 10, // 豆粕
    'Y': 10, // 豆油
    'P': 10, // 棕榈油
    'C': 10, // 玉米
    'CS': 10, // 玉米淀粉
    'JD': 10, // 鸡蛋 10 吨
    'L': 5, // 塑料
    'V': 5, // PVC
    'PP': 5, // 聚丙烯
    'EG': 10, // 乙二醇
    'EB': 5, // 苯乙烯
    'PG': 20, // LPG
    'I': 100, // 铁矿石 100 吨/手
    'J': 100, // 焦炭
    'JM': 60, // 焦煤
    'FB': 10, // 纤维板
    'BB': 500, // 胶合板
    'LH': 16, // 生猪 16 吨/手
    // 郑商所 (CZCE / .CZC)
    'SR': 10, // 白糖 10 吨/手
    'CF': 5, // 棉花
    'CY': 5, // 棉纱
    'TA': 5, // PTA
    'OI': 10, // 菜油
    'RM': 10, // 菜粕
    'RS': 10, // 油菜籽
    'SF': 5, // 硅铁
    'SM': 5, // 锰硅
    'WH': 20, // 强麦 20 吨/手
    'PM': 50, // 普麦
    'JR': 20, // 粳稻
    'LR': 20, // 晚籼稻
    'RI': 20, // 早籼稻
    'AP': 10, // 苹果
    'CJ': 5, // 红枣
    'UR': 20, // 尿素
    'SA': 20, // 纯碱
    'MA': 10, // 甲醇
    'FG': 20, // 玻璃
    'ZC': 100, // 动力煤
    'PF': 5, // 短纤
    'PK': 5, // 花生
    'PX': 5, // 对二甲苯
    'SH': 30, // 烧碱
    // 中金所 (CFFEX / .CFE)
    'IF': 300, // 沪深 300 期指
    'IH': 300, // 上证 50
    'IC': 200, // 中证 500
    'IM': 200, // 中证 1000
    'TF': 10000, // 5 年国债 (面值 100 万 → 元/点 = 10000)
    'T': 10000, // 10 年国债
    'TS': 20000, // 2 年国债 (面值 200 万)
    'TL': 10000, // 30 年国债
    // 广期所 (GFEX / .GFE)
    'SI': 5, // 工业硅 5 吨/手
    'LC': 1, // 碳酸锂 1 吨/手
  };

  /// 期货合约乘数（每手对应的标的单位 × 价格 = 合约价值）。
  /// 输入的 symbol 例如 SR2609.CZC，会先剥离数字部分得到品种代码 SR。
  /// 非期货品种 / 未知品种返回 1。
  static double contractMultiplier(String symbol, String assetClass) {
    if (assetClass != '期货') return 1.0;
    final core = displaySymbol(symbol).toUpperCase();
    // 取代码开头的字母部分（SR2609 → SR；TA509 → TA；T2406 → T）。
    final m = RegExp(r'^[A-Z]+').firstMatch(core);
    if (m == null) return 1.0;
    final code = m.group(0)!;
    return _futureMultiplier[code] ?? 1.0;
  }
}
