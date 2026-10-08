import 'dart:math' as math;

import '../../core/utils/china_market.dart';
import 'backtest_models.dart';
import 'etf_rotation.dart' show BacktestCandle;

/// 「深市 ETF 短线动量」策略回测引擎 — 纯 Dart 本地计算。
///
/// 与 etf_rotation.dart 的差异：那是无摩擦的权重轮动模型（服务端工具的
/// 算法复刻），这个是贴近实盘的持仓模拟，完整实现 A 股交易规则：
///
/// 交易规则（A 股 ETF）：
/// - T+1：每笔买入的份额次日才能卖出，分笔（lot）跟踪可卖份额
/// - 手续费：买卖各万 3（0.0003），按成交金额计；ETF 免印花税
/// - 每笔最小手续费 5 元
/// - 手数：每次买入 100 份整数倍（不足一手的部分不买）
///
/// 策略规则（用户约束）：
/// - 初始本金 5 万；最多同时持有 2 只
/// - 候选池限定深市 ETF（159 开头），引擎按此前缀过滤
/// - 持仓最长 10 个交易日，到期清仓
/// - 动量转负 / 浮亏达止损线 → 清仓
/// - 可补仓：浮亏到阈值且动量仍为正、该仓未补过时补一次
class EtfShortTermEngine {
  /// 初始本金（元）。
  final double initialCapital;

  /// 候选池（引擎只保留 159 开头的深市代码）。
  final List<String> symbols;

  /// 动量观察窗口（交易日）。
  final int momentumWindow;

  /// 触发新开仓的动量阈值（如 0.01 = 1%）。
  final double buyThreshold;

  /// 新开仓目标仓位（占总资产比例）。
  final double firstBuyRatio;

  /// 补仓触发线（浮亏比例，负值，如 -0.04 = -4%）。
  final double addThreshold;

  /// 补仓后单只仓位上限（占总资产比例）。
  final double addMaxRatio;

  /// 止损线（浮亏比例，负值，如 -0.08 = -8%）。
  final double stopLoss;

  /// 最长持仓交易日数（T 日收盘买入，第 T+maxHoldingDays 日到期）。
  final int maxHoldingDays;

  /// 单边手续费率（万 3 = 0.0003）。
  final double feeRate;

  /// 每笔最小手续费（元）。
  final double minFee;

  /// 最多同时持有只数。
  final int maxPositions;

  const EtfShortTermEngine({
    this.initialCapital = 50000,
    this.symbols = const [],
    this.momentumWindow = 5,
    this.buyThreshold = 0.01,
    this.firstBuyRatio = 0.50,
    this.addThreshold = -0.04,
    this.addMaxRatio = 0.70,
    this.stopLoss = -0.08,
    this.maxHoldingDays = 10,
    this.feeRate = 0.0003,
    this.minFee = 5,
    this.maxPositions = 2,
  });

  /// 执行回测。[series] 键为归一化代码（159xxx.SZ），值升序日线。
  ShortTermResult run({
    required Map<String, List<BacktestCandle>> series,
  }) {
    // 候选池过滤：只保留深市 ETF（159 开头）且有足够行情的代码
    final syms = symbols
        .map(ChinaMarket.normalizeSymbol)
        .toSet()
        .where((s) =>
            s.startsWith('159') &&
            series.containsKey(s) &&
            series[s]!.length > momentumWindow + 2)
        .toList();
    if (syms.isEmpty) {
      throw Exception('候选池没有可用的深市 ETF 行情（需 159 开头且数据充足）');
    }

    // 交易日对齐：所有候选的交集（保证同日动量可比）
    final dates = _intersectDates(series, syms);
    if (dates.length < momentumWindow + 5) {
      throw Exception('对齐后交易日不足（${dates.length}），请扩大时间范围');
    }
    final closes = {
      for (final s in syms) s: _pickCloses(series[s]!, dates),
    };

    // 基准：候选池等权买入持有（同窗口对比，含起点归一）
    final benchCloses = _equalWeightSeries(closes, syms);

    // ── 账户状态 ─────────────────────────────────────────────
    var cash = initialCapital;
    final positions = <String, _Position>{};
    final trades = <TradeRecord>[];
    final navs = <NavPoint>[];
    final benchNavs = <NavPoint>[];
    final dailyReturns = <double>[];
    var prevEquity = initialCapital;

    for (var i = momentumWindow; i < dates.length; i++) {
      // 1) 卖出检查（到期 / 动量转负 / 止损）——信号日收盘执行
      for (final code in positions.keys.toList()) {
        final newCash = _checkSell(code, i, dates, closes, positions,
            trades, cash);
        if (newCash != null) {
          cash = newCash;
          if (positions[code]!.shares <= 0) {
            positions.remove(code);
          }
        }
      }

      // 2) 补仓检查（浮亏到线 + 动量为正 + 未补过仓）
      for (final code in positions.keys.toList()) {
        cash = _checkAdd(
            code, i, dates, closes, positions, trades, cash);
      }

      // 3) 新开仓（动量第一名且超过阈值 + 有空位 + 现金够一手）
      cash = _checkNewBuy(
          i, dates, closes, positions, syms, trades, cash);

      // 4) 日终估值
      final equity = _equity(closes, i, positions, cash);
      dailyReturns
          .add(prevEquity > 0 ? equity / prevEquity - 1 : 0.0);
      prevEquity = equity;
      navs.add(NavPoint(_parseYmd(dates[i]), equity / initialCapital));
      final benchEq = i > 0 ? benchCloses[i] / benchCloses[0] : 1.0;
      benchNavs.add(NavPoint(_parseYmd(dates[i]), benchEq));
    }

    // 期末按最后收盘估值平仓（仅为交易记录完整性）
    final lastIdx = dates.length - 1;
    for (final code in positions.keys.toList()) {
      final p = positions[code]!;
      final sellable = p.sellableSharesAt(lastIdx);
      if (sellable > 0) {
        cash = _doSell(
            code, lastIdx, dates, closes, p, sellable, '期末平仓',
            trades, cash);
      }
    }
    final finalEquity = _equity(closes, lastIdx, positions, cash);

    // ── 统计 ─────────────────────────────────────────────────
    final stratMetrics =
        _stats(dailyReturns, finalEquity / initialCapital);
    final benchDaily = <double>[];
    for (var i = 1; i < benchCloses.length; i++) {
      if (benchCloses[i - 1] > 0) {
        benchDaily.add(benchCloses[i] / benchCloses[i - 1] - 1);
      }
    }
    final benchMetrics = _stats(benchDaily, benchCloses.last / benchCloses[0]);

    return ShortTermResult(
      initialCapital: initialCapital,
      finalEquity: finalEquity,
      metrics: stratMetrics,
      benchMetrics: benchMetrics,
      navSeries: navs,
      benchNavSeries: benchNavs,
      trades: trades,
    );
  }

  // ── 信号 ─────────────────────────────────────────────────────

  /// 动量 = close[i] / close[i - window] - 1（数据不足返回 0）。
  double _momentum(String code, int i, Map<String, List<double>> closes) {
    final cs = closes[code]!;
    final back = i - momentumWindow;
    if (back < 0 || cs[back] <= 0 || cs[i] <= 0) return 0;
    return cs[i] / cs[back] - 1;
  }

  // ── 卖出 ─────────────────────────────────────────────────────

  /// 检查单个持仓的卖出条件，触发则卖出全部「可卖份额」（T+1 约束）。
  /// 返回 null = 未触发；否则返回卖出后的新现金。
  double? _checkSell(
    String code,
    int i,
    List<String> dates,
    Map<String, List<double>> closes,
    Map<String, _Position> positions,
    List<TradeRecord> trades,
    double cash,
  ) {
    final p = positions[code]!;
    final price = closes[code]![i];
    if (price <= 0) return null;
    final ret = price / p.avgCost - 1;
    final heldDays = i - p.firstBuyIdx;
    final mom = _momentum(code, i, closes);

    final expired = heldDays >= maxHoldingDays;
    final momNeg = mom < 0;
    final stopHit = ret <= stopLoss;
    if (!expired && !momNeg && !stopHit) return null;

    final reason =
        expired ? '到期清仓' : (stopHit ? '止损' : '动量转负');
    final sellable = p.sellableSharesAt(i);
    if (sellable <= 0) return null;
    // 触发即全仓退出信号：可卖部分当日卖；当日新买部分次日会再次触发
    return _doSell(code, i, dates, closes, p, sellable, reason, trades,
        cash);
  }

  // ── 补仓 ─────────────────────────────────────────────────────

  /// 检查补仓条件；满足则执行并返回扣除后的现金。
  double _checkAdd(
    String code,
    int i,
    List<String> dates,
    Map<String, List<double>> closes,
    Map<String, _Position> positions,
    List<TradeRecord> trades,
    double cash,
  ) {
    final p = positions[code]!;
    if (p.added) return cash;
    final price = closes[code]![i];
    if (price <= 0) return cash;
    final ret = price / p.avgCost - 1;
    final mom = _momentum(code, i, closes);
    if (ret > addThreshold || mom <= 0) return cash;

    // 目标市值 = 总资产 × addMaxRatio；补差额
    final equity = _equity(closes, i, positions, cash);
    final targetValue = equity * addMaxRatio;
    final curValue = p.shares * price;
    var buyValue = targetValue - curValue;
    if (buyValue > cash) buyValue = cash;
    if (buyValue <= 0) return cash;

    final shares = (buyValue / price).floor() ~/ 100 * 100;
    if (shares < 100) return cash;
    final fee = _buyFee(price * shares);
    if (price * shares + fee > cash) return cash;

    cash -= price * shares + fee;
    p.addLot(shares, i, price: price, fee: fee);
    p.added = true;
    trades.add(TradeRecord(
      date: _parseYmd(dates[i]),
      symbol: code,
      action: '补仓',
      shares: shares,
      price: price,
      fee: fee,
    ));
    return cash;
  }

  // ── 新开仓 ───────────────────────────────────────────────────

  /// 动量第一名超过阈值且有空位时买入；返回扣除后的现金。
  double _checkNewBuy(
    int i,
    List<String> dates,
    Map<String, List<double>> closes,
    Map<String, _Position> positions,
    List<String> candidates,
    List<TradeRecord> trades,
    double cash,
  ) {
    if (positions.length >= maxPositions) return cash;

    final ranked = <(String, double)>[];
    for (final c in candidates) {
      if (positions.containsKey(c)) continue;
      final m = _momentum(c, i, closes);
      if (m > 0) ranked.add((c, m));
    }
    ranked.sort((a, b) => b.$2.compareTo(a.$2));
    if (ranked.isEmpty) return cash;

    // 用满仓上限检查：若空位不止一个且现金充裕，按动量序逐一开仓
    var remaining = maxPositions - positions.length;
    for (final (code, mom) in ranked) {
      if (remaining <= 0) break;
      if (mom < buyThreshold) break;
      final price = closes[code]![i];
      if (price <= 0) continue;
      final equity = _equity(closes, i, positions, cash);
      final buyValue = equity * firstBuyRatio;
      final capped = buyValue > cash ? cash : buyValue;
      final shares = (capped / price).floor() ~/ 100 * 100;
      if (shares < 100) continue;
      final fee = _buyFee(price * shares);
      if (price * shares + fee > cash) continue;

      cash -= price * shares + fee;
      final p = _Position();
      p.addLot(shares, i, price: price, fee: fee);
      positions[code] = p;
      trades.add(TradeRecord(
        date: _parseYmd(dates[i]),
        symbol: code,
        action: '买入',
        shares: shares,
        price: price,
        fee: fee,
      ));
      remaining--;
    }
    return cash;
  }

  // ── 成交执行 ─────────────────────────────────────────────────

  /// 执行卖出：加现金、扣 lot、写记录。返回新现金。
  double _doSell(
    String code,
    int i,
    List<String> dates,
    Map<String, List<double>> closes,
    _Position p,
    int shares,
    String reason,
    List<TradeRecord> trades,
    double cash,
  ) {
    final price = closes[code]![i];
    final amount = price * shares;
    final fee = _sellFee(amount);
    cash += amount - fee;
    p.removeLot(shares, i);
    trades.add(TradeRecord(
      date: _parseYmd(dates[i]),
      symbol: code,
      action: reason,
      shares: shares,
      price: price,
      fee: fee,
    ));
    return cash;
  }

  /// 买入手续费：万 3，最低 5 元。
  double _buyFee(double amount) => math.max(amount * feeRate, minFee);

  /// 卖出手续费：万 3，最低 5 元（ETF 免印花税）。
  double _sellFee(double amount) => math.max(amount * feeRate, minFee);

  // ── 估值 ─────────────────────────────────────────────────────

  /// 总资产 = 现金 + Σ(持仓 × 当日收盘)。
  double _equity(Map<String, List<double>> closes, int i,
      Map<String, _Position> positions, double cash) {
    var total = cash;
    positions.forEach((code, p) {
      final price = closes[code]![i];
      total += p.shares * price;
    });
    return total;
  }

  // ── 基准与统计 ───────────────────────────────────────────────

  /// 候选池等权价格序列（起点归一为 1）。
  List<double> _equalWeightSeries(
      Map<String, List<double>> closes, List<String> syms) {
    final n = closes[syms.first]!.length;
    final out = List<double>.filled(n, 0.0);
    for (final s in syms) {
      final cs = closes[s]!;
      for (var i = 0; i < n; i++) {
        out[i] += i < cs.length ? cs[i] : cs.last;
      }
    }
    final base = out[0] / syms.length;
    return [for (final v in out) v / syms.length / base];
  }

  BacktestMetrics _stats(List<double> dailyReturns, double finalNav) {
    final n = dailyReturns.length;
    if (n < 2) {
      return const BacktestMetrics(
          totalReturn: 0, annReturn: 0, annVol: 0, sharpe: 0, maxDrawdown: 0);
    }
    final totalReturn = finalNav - 1;
    final years = n / 252.0;
    var annReturn = 0.0;
    if (years > 0 && 1 + totalReturn > 0) {
      annReturn = math.pow(1 + totalReturn, 1 / years) - 1;
    }
    var mean = 0.0;
    for (final r in dailyReturns) {
      mean += r;
    }
    mean /= n;
    var varSum = 0.0;
    for (final r in dailyReturns) {
      final d = r - mean;
      varSum += d * d;
    }
    final std = math.sqrt(varSum / (n - 1));
    final annVol = std * math.sqrt(252);
    final sharpe = annVol > 0 ? (annReturn - 0.02) / annVol : 0.0;

    var nav = 1.0;
    var peak = 1.0;
    var maxDd = 0.0;
    for (final r in dailyReturns) {
      nav *= 1 + r;
      if (nav > peak) peak = nav;
      final dd = (peak - nav) / peak;
      if (dd > maxDd) maxDd = dd;
    }
    return BacktestMetrics(
      totalReturn: totalReturn,
      annReturn: annReturn,
      annVol: annVol,
      sharpe: sharpe,
      maxDrawdown: maxDd,
    );
  }
}

// ── 持仓与交易记录 ─────────────────────────────────────────────

/// 单只持仓：分笔（lot）跟踪买入日以满足 T+1 可卖约束。
class _Position {
  final List<({int shares, int buyIdx})> _lots = [];

  /// 是否已补过仓（每仓限一次）。
  bool added = false;

  /// 加权平均成本（含手续费）。
  double avgCost = 0;

  /// 首笔买入的交易日下标（用于计算最长持仓天数）。
  int firstBuyIdx = -1;

  int get shares => _lots.fold(0, (a, l) => a + l.shares);

  void addLot(int lotShares, int idx, {double price = 0, double fee = 0}) {
    if (lotShares <= 0) return;
    // 加权平均成本（含手续费）：新成本 = (旧份额×旧成本 + 新金额+费) / 总份额
    if (price > 0) {
      final totalShares = shares + lotShares;
      final totalCost = avgCost * shares + price * lotShares + fee;
      avgCost = totalShares > 0 ? totalCost / totalShares : 0;
    }
    _lots.add((shares: lotShares, buyIdx: idx));
    if (firstBuyIdx < 0) firstBuyIdx = idx;
  }

  /// T+1：当日（idx）可卖份额 = 所有买入日早于 idx 的 lot 合计。
  int sellableSharesAt(int idx) => _lots
      .where((l) => l.buyIdx < idx)
      .fold(0, (a, l) => a + l.shares);

  /// 卖出按 FIFO 扣减 lot。
  void removeLot(int sellShares, int idx) {
    var remaining = sellShares;
    final done = <({int shares, int buyIdx})>[];
    for (final l in _lots) {
      if (remaining <= 0) {
        done.add(l);
        continue;
      }
      final take = l.shares < remaining ? l.shares : remaining;
      remaining -= take;
      if (l.shares - take > 0) {
        done.add((shares: l.shares - take, buyIdx: l.buyIdx));
      }
    }
    _lots
      ..clear()
      ..addAll(done);
  }
}

/// 一笔成交记录（UI 交易明细表用）。
class TradeRecord {
  TradeRecord({
    required this.date,
    required this.symbol,
    required this.action,
    required this.shares,
    required this.price,
    required this.fee,
  });

  final DateTime date;
  final String symbol;
  final String action;
  final int shares;
  final double price;
  final double fee;
}

/// 短线策略回测结果。
class ShortTermResult {
  const ShortTermResult({
    required this.initialCapital,
    required this.finalEquity,
    required this.metrics,
    required this.benchMetrics,
    required this.navSeries,
    required this.benchNavSeries,
    required this.trades,
  });

  final double initialCapital;
  final double finalEquity;
  final BacktestMetrics metrics;
  final BacktestMetrics benchMetrics;
  final List<NavPoint> navSeries;
  final List<NavPoint> benchNavSeries;
  final List<TradeRecord> trades;
}

// ── 内部小工具 ─────────────────────────────────────────────────

List<String> _intersectDates(
    Map<String, List<BacktestCandle>> series, List<String> codes) {
  final count = <String, int>{};
  for (final code in codes) {
    final candles = series[code];
    if (candles == null) continue;
    final seen = <String>{};
    for (final c in candles) {
      if (seen.add(c.date)) count[c.date] = (count[c.date] ?? 0) + 1;
    }
  }
  final out = count.entries
      .where((e) => e.value == codes.length)
      .map((e) => e.key)
      .toList()
    ..sort();
  return out;
}

List<double> _pickCloses(List<BacktestCandle> s, List<String> dates) {
  final m = {for (final c in s) c.date: c.close};
  return [for (final d in dates) m[d] ?? 0.0];
}

DateTime _parseYmd(String s) => DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
