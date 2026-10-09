/// 策略目录项：目前只有主策略在跑，其余先占位，客户端据此显示"即将上线"。
class StrategyCatalogEntry {
  const StrategyCatalogEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.live,
  });

  final String id;
  final String name;
  final String subtitle;
  final bool live;

  factory StrategyCatalogEntry.fromJson(Map<String, dynamic> j) =>
      StrategyCatalogEntry(
        id: _str(j['id']),
        name: _str(j['name']),
        subtitle: _str(j['subtitle']),
        live: j['live'] == true,
      );
}

/// 主策略快照（对应后端 GET /v1/strategy/primary 的 snapshot 字段）。
///
/// 这层字段刻意只保留「用户要做决策时需要的」：本期要不要动手、目标名单、
/// 实盘状态、绩效与口径。解析全部走容错路径——外部数据缺字段时降级为空值，
/// 绝不因为一个字段缺失就整张卡片报错。
class StrategySnapshot {
  const StrategySnapshot({
    required this.strategyId,
    required this.meta,
    required this.dataAsOf,
    required this.stale,
    required this.staleDays,
    required this.action,
    required this.metrics,
    this.live,
    this.benchmarks = const [],
    this.yearly = const [],
    this.factors = const [],
    this.universes = const [],
    this.curve = const [],
  });

  final String strategyId;
  final StrategyMeta meta;

  /// 数据实际算到哪一天；[stale] 表示它已经不是最近一个交易日了。
  final String dataAsOf;
  final bool stale;
  final int staleDays;

  final StrategyAction action;
  final StrategyMetrics metrics;
  final StrategyLive? live;
  final List<StrategyBenchmark> benchmarks;
  final List<StrategyYearRet> yearly;
  final List<StrategyFactor> factors;
  final List<StrategyUniverse> universes;
  final List<StrategyCurvePoint> curve;

  factory StrategySnapshot.fromJson(Map<String, dynamic> j) => StrategySnapshot(
        strategyId: _str(j['strategy_id']),
        meta: StrategyMeta.fromJson(_map(j['meta'])),
        dataAsOf: _str(j['data_as_of']),
        stale: j['stale'] == true,
        staleDays: _int(j['stale_days']),
        action: StrategyAction.fromJson(_map(j['action'])),
        metrics: StrategyMetrics.fromJson(_map(j['metrics'])),
        live: j['live'] == null
            ? null
            : StrategyLive.fromJson(_map(j['live'])),
        benchmarks: _list(j['benchmarks'], StrategyBenchmark.fromJson),
        yearly: _list(j['yearly'], StrategyYearRet.fromJson),
        factors: _list(j['factors'], StrategyFactor.fromJson),
        universes: _list(j['universes'], StrategyUniverse.fromJson),
        curve: _list(j['curve'], StrategyCurvePoint.fromJson),
      );
}

class StrategyMeta {
  const StrategyMeta({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.summary,
    required this.disclosure,
    this.universe = '',
    this.topN = 0,
    this.exclude = const [],
    this.rebalance = '',
    this.since = '',
    this.capital = 0,
  });

  final String id;
  final String name;
  final String subtitle;
  final String summary;

  /// 口径与风险声明：跟着成绩一起展示，这是可信度来源。
  final String disclosure;
  final String universe;
  final int topN;
  final List<String> exclude;
  final String rebalance;
  final String since;
  final double capital;

  factory StrategyMeta.fromJson(Map<String, dynamic> j) => StrategyMeta(
        id: _str(j['id']),
        name: _str(j['name']),
        subtitle: _str(j['subtitle']),
        summary: _str(j['summary']),
        disclosure: _str(j['disclosure']),
        universe: _str(j['universe']),
        topN: _int(j['topn']),
        exclude: _strList(j['exclude']),
        rebalance: _str(j['rebalance']),
        since: _str(j['since']),
        capital: _dbl(j['capital']),
      );
}

/// 「要不要动手」卡片的数据。
class StrategyAction {
  const StrategyAction({
    required this.signalDate,
    required this.execDate,
    required this.changed,
    required this.note,
    this.target = const [],
    this.prevTarget = const [],
    this.orders = const [],
    this.targetDetail = const [],
  });

  final String signalDate;
  final String execDate;
  final bool changed;
  final String note;
  final List<StrategyTarget> target;
  final List<StrategyTarget> prevTarget;
  final List<StrategyOrder> orders;
  final List<StrategyTargetDetail> targetDetail;

  /// 本期新增 / 剔除的标的（用于「变动」展示）。
  List<StrategyTarget> get added {
    final prev = prevTarget.map((t) => t.code).toSet();
    return [for (final t in target) if (!prev.contains(t.code)) t];
  }

  List<StrategyTarget> get removed {
    final now = target.map((t) => t.code).toSet();
    return [for (final t in prevTarget) if (!now.contains(t.code)) t];
  }

  factory StrategyAction.fromJson(Map<String, dynamic> j) => StrategyAction(
        signalDate: _str(j['signal_date']),
        execDate: _str(j['exec_date']),
        changed: j['changed'] == true,
        note: _str(j['note']),
        target: _list(j['target'], StrategyTarget.fromJson),
        prevTarget: _list(j['prev_target'], StrategyTarget.fromJson),
        orders: _list(j['orders'], StrategyOrder.fromJson),
        targetDetail: _list(j['target_detail'], StrategyTargetDetail.fromJson),
      );
}

class StrategyTarget {
  const StrategyTarget({required this.code, required this.name});
  final String code;
  final String name;

  factory StrategyTarget.fromJson(Map<String, dynamic> j) =>
      StrategyTarget(code: _str(j['code']), name: _str(j['name']));
}

/// 目标标的的因子细节（外部只对当前持仓给出，其余为仅代码/名称）。
class StrategyTargetDetail {
  const StrategyTargetDetail({
    required this.code,
    required this.name,
    this.industry = '',
    this.price = 0,
    this.score = 0,
    this.z = const {},
  });

  final String code;
  final String name;
  final String industry;
  final double price;
  final double score;
  final Map<String, double> z;

  factory StrategyTargetDetail.fromJson(Map<String, dynamic> j) {
    final zRaw = j['z'];
    final z = <String, double>{};
    if (zRaw is Map) {
      zRaw.forEach((k, v) => z['$k'] = _dbl(v));
    }
    return StrategyTargetDetail(
      code: _str(j['code']),
      name: _str(j['name']),
      industry: _str(j['industry']),
      price: _dbl(j['price']),
      score: _dbl(j['score']),
      z: z,
    );
  }
}

class StrategyOrder {
  const StrategyOrder({
    required this.side,
    required this.code,
    required this.name,
    required this.shares,
    required this.price,
    required this.amount,
    this.note = '',
  });

  final String side; // buy / sell
  final String code;
  final String name;
  final int shares;
  final double price;
  final double amount;
  final String note;

  bool get isBuy => side == 'buy';

  factory StrategyOrder.fromJson(Map<String, dynamic> j) => StrategyOrder(
        side: _str(j['side']),
        code: _str(j['code']),
        name: _str(j['name']),
        shares: _int(j['shares']),
        price: _dbl(j['price']),
        amount: _dbl(j['amount']),
        note: _str(j['note']),
      );
}

/// 实盘账户状态。
class StrategyLive {
  const StrategyLive({
    required this.asOf,
    required this.capital,
    required this.cash,
    required this.marketValue,
    required this.total,
    required this.pnl,
    required this.pnlPct,
    required this.realized,
    required this.fees,
    required this.dividends,
    this.inception = '',
    this.positions = const [],
    this.divergence = false,
  });

  final String asOf;
  final String inception;
  final double capital;
  final double cash;
  final double marketValue;
  final double total;
  final double pnl;
  final double pnlPct;
  final double realized;
  final double fees;
  final double dividends;
  final List<StrategyPosition> positions;

  /// 持仓与策略目标名单不一致（人工调过仓）时为 true。
  final bool divergence;

  double get positionPct => total > 0 ? marketValue / total : 0;

  factory StrategyLive.fromJson(Map<String, dynamic> j) => StrategyLive(
        asOf: _str(j['as_of']),
        inception: _str(j['inception']),
        capital: _dbl(j['capital']),
        cash: _dbl(j['cash']),
        marketValue: _dbl(j['market_value']),
        total: _dbl(j['total']),
        pnl: _dbl(j['pnl']),
        pnlPct: _dbl(j['pnl_pct']),
        realized: _dbl(j['realized']),
        fees: _dbl(j['fees']),
        dividends: _dbl(j['dividends']),
        positions: _list(j['positions'], StrategyPosition.fromJson),
        divergence: j['divergence'] == true,
      );
}

class StrategyPosition {
  const StrategyPosition({
    required this.code,
    required this.name,
    required this.shares,
    required this.avgCost,
    required this.price,
    required this.marketValue,
    required this.pnl,
    required this.pnlPct,
    this.weight = 0,
    this.inTarget = false,
  });

  final String code;
  final String name;
  final int shares;
  final double avgCost;
  final double price;
  final double marketValue;
  final double pnl;
  final double pnlPct;
  final double weight;
  final bool inTarget;

  factory StrategyPosition.fromJson(Map<String, dynamic> j) => StrategyPosition(
        code: _str(j['code']),
        name: _str(j['name']),
        shares: _int(j['shares']),
        avgCost: _dbl(j['avg_cost']),
        price: _dbl(j['price']),
        marketValue: _dbl(j['market_value']),
        pnl: _dbl(j['pnl']),
        pnlPct: _dbl(j['pnl_pct']),
        weight: _dbl(j['weight']),
        inTarget: j['in_target'] == true,
      );
}

class StrategyMetrics {
  const StrategyMetrics({
    required this.capital,
    required this.equity,
    required this.pnl,
    required this.pnlPct,
    required this.cagr,
    required this.sharpe,
    required this.maxDrawdown,
    required this.monthWin,
    required this.trades,
    required this.fees,
  });

  final double capital;
  final double equity;
  final double pnl;
  final double pnlPct;
  final double cagr;
  final double sharpe;
  final double maxDrawdown;
  final double monthWin;
  final int trades;
  final double fees;

  factory StrategyMetrics.fromJson(Map<String, dynamic> j) => StrategyMetrics(
        capital: _dbl(j['capital']),
        equity: _dbl(j['equity']),
        pnl: _dbl(j['pnl']),
        pnlPct: _dbl(j['pnl_pct']),
        cagr: _dbl(j['cagr']),
        sharpe: _dbl(j['sharpe']),
        maxDrawdown: _dbl(j['max_drawdown']),
        monthWin: _dbl(j['month_win']),
        trades: _int(j['trades']),
        fees: _dbl(j['fees']),
      );
}

class StrategyBenchmark {
  const StrategyBenchmark({
    required this.name,
    required this.totalReturn,
    required this.cagr,
    this.comment = '',
  });

  final String name;
  final double totalReturn;
  final double cagr;
  final String comment;

  factory StrategyBenchmark.fromJson(Map<String, dynamic> j) =>
      StrategyBenchmark(
        name: _str(j['name']),
        totalReturn: _dbl(j['total_return']),
        cagr: _dbl(j['cagr']),
        comment: _str(j['comment']),
      );
}

class StrategyYearRet {
  const StrategyYearRet({required this.year, required this.ret});
  final int year;
  final double ret;

  factory StrategyYearRet.fromJson(Map<String, dynamic> j) =>
      StrategyYearRet(year: _int(j['year']), ret: _dbl(j['ret']));
}

class StrategyFactor {
  const StrategyFactor({
    required this.factor,
    required this.name,
    required this.ic,
    required this.t,
    required this.oos,
    required this.win,
    this.group = '',
    this.desc = '',
  });

  /// 因子 key（ep / dv / …）
  final String factor;

  /// 中文名与分类：由后端从外部数据源的 factor_meta 带出，客户端不维护字典。
  final String name;
  final String group;
  final String desc;
  final double ic;
  final double t;
  final double oos;
  final double win;

  factory StrategyFactor.fromJson(Map<String, dynamic> j) => StrategyFactor(
        factor: _str(j['factor']),
        name: _str(j['name']).isEmpty ? _str(j['factor']) : _str(j['name']),
        group: _str(j['group']),
        desc: _str(j['desc']),
        ic: _dbl(j['ic']),
        t: _dbl(j['t']),
        oos: _dbl(j['oos']),
        win: _dbl(j['win']),
      );
}

class StrategyUniverse {
  const StrategyUniverse({
    required this.name,
    required this.cagr,
    required this.sharpe,
    required this.dd,
  });

  final String name;
  final double cagr;
  final double sharpe;
  final double dd;

  factory StrategyUniverse.fromJson(Map<String, dynamic> j) => StrategyUniverse(
        name: _str(j['name']),
        cagr: _dbl(j['cagr']),
        sharpe: _dbl(j['sharpe']),
        dd: _dbl(j['dd']),
      );
}

class StrategyCurvePoint {
  const StrategyCurvePoint({
    required this.date,
    required this.equity,
    required this.bench,
  });

  final String date;
  final double equity;
  final double bench;

  factory StrategyCurvePoint.fromJson(Map<String, dynamic> j) =>
      StrategyCurvePoint(
        date: _str(j['date']),
        equity: _dbl(j['equity']),
        bench: _dbl(j['bench']),
      );
}

// ── 容错解析工具 ────────────────────────────────────────────────────────

String _str(dynamic v) => v == null ? '' : '$v';

double _dbl(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

List<String> _strList(dynamic v) =>
    v is List ? [for (final e in v) '$e'] : const [];

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) out.add(f(e.cast<String, dynamic>()));
  }
  return out;
}
