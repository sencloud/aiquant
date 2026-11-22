import 'dart:math' as math;

import '../models/trade_review.dart';

class TradeReviewEngine {
  const TradeReviewEngine();

  TradeReviewReport analyze({
    required List<ParsedTrade> trades,
    String brokerHint = '',
    String currency = 'CNY',
    List<String> parserWarnings = const [],
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now();
    final warnings = <String>[...parserWarnings];
    final sorted = [...trades]..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.sourceIndex.compareTo(b.sourceIndex);
      });
    final valid = <ParsedTrade>[];
    for (final trade in sorted) {
      if (trade.instrumentKey.isEmpty) {
        warnings.add('有一笔成交缺少证券代码和名称，未纳入盈亏计算。');
        continue;
      }
      if (trade.quantity <= 0 || trade.price <= 0) {
        warnings.add(
          '${trade.instrumentLabel} 有一笔成交的数量或价格无效，未纳入计算。',
        );
        continue;
      }
      var fee = trade.fee;
      if (fee < 0) {
        warnings.add('${trade.instrumentLabel} 有一笔成交手续费为负，已按 0 处理。');
        fee = 0;
      }
      valid.add(trade.fee == fee ? trade : trade.copyWith(fee: fee));
    }

    final lots = <String, List<_Lot>>{};
    final closed = <_ClosedTrade>[];
    final feesBySymbol = <String, double>{};
    final turnoverBySymbol = <String, double>{};
    final ordersByDay = <DateTime, int>{};
    final symbolsByDay = <DateTime, Set<String>>{};
    var totalFees = 0.0;
    var turnover = 0.0;

    for (final trade in valid) {
      final key = trade.instrumentKey;
      final day = DateTime(
        trade.occurredAt.year,
        trade.occurredAt.month,
        trade.occurredAt.day,
      );
      ordersByDay[day] = (ordersByDay[day] ?? 0) + 1;
      (symbolsByDay[day] ??= <String>{}).add(key);
      totalFees += trade.fee;
      feesBySymbol[key] = (feesBySymbol[key] ?? 0) + trade.fee;
      turnover += trade.notional;
      turnoverBySymbol[key] = (turnoverBySymbol[key] ?? 0) + trade.notional;

      if (trade.side == TradeSide.buy) {
        final totalCost = trade.notional + trade.fee;
        (lots[key] ??= <_Lot>[]).add(
          _Lot(
            remaining: trade.quantity,
            costPerUnit: totalCost / trade.quantity,
            acquiredAt: trade.occurredAt,
          ),
        );
        continue;
      }

      var remaining = trade.quantity;
      var matchedQuantity = 0.0;
      var matchedCost = 0.0;
      var holdingHoursWeighted = 0.0;
      var matchedSameDay = false;
      final queue = lots[key] ?? <_Lot>[];
      while (remaining > 1e-9 && queue.isNotEmpty) {
        final lot = queue.first;
        final take = math.min(remaining, lot.remaining);
        if (_sameDate(lot.acquiredAt, trade.occurredAt)) {
          matchedSameDay = true;
        }
        final cost = take * lot.costPerUnit;
        final holdingHours =
            trade.occurredAt.difference(lot.acquiredAt).inMinutes / 60.0;
        matchedQuantity += take;
        matchedCost += cost;
        holdingHoursWeighted += math.max(0, holdingHours) * take;
        remaining -= take;
        lot.remaining -= take;
        if (lot.remaining <= 1e-9) queue.removeAt(0);
      }

      if (remaining > 1e-6) {
        warnings.add(
          '${trade.instrumentLabel} ${_dateText(trade.occurredAt)} 的卖出'
          '有 ${_qty(remaining)} 股无法与截图中的买入配对，未计入已实现盈亏。',
        );
      }
      if (matchedQuantity <= 1e-9) continue;

      final matchedProceeds = matchedQuantity * trade.price -
          trade.fee * matchedQuantity / trade.quantity;
      final pnl = matchedProceeds - matchedCost;
      closed.add(
        _ClosedTrade(
          pnl: pnl,
          quantity: matchedQuantity,
          holdingHours: holdingHoursWeighted / matchedQuantity,
          sameDay: matchedSameDay,
        ),
      );
      lots[key] = queue;
    }

    final wins = closed.where((trade) => trade.pnl > 0).toList();
    final losses = closed.where((trade) => trade.pnl < 0).toList();
    final realizedPnl = closed.fold<double>(0, (sum, trade) => sum + trade.pnl);
    final grossProfit = wins.fold<double>(0, (sum, trade) => sum + trade.pnl);
    final grossLoss = losses.fold<double>(0, (sum, trade) => sum + trade.pnl);
    final averageWin = wins.isEmpty ? 0.0 : grossProfit / wins.length;
    final averageLoss = losses.isEmpty ? 0.0 : grossLoss / losses.length;
    final profitLossRatio = averageLoss == 0
        ? (averageWin > 0 ? double.infinity : 0.0)
        : averageWin / averageLoss.abs();
    final weightedHolding = closed.fold<double>(
      0,
      (sum, trade) => sum + trade.holdingHours * trade.quantity,
    );
    final matchedQuantity =
        closed.fold<double>(0, (sum, trade) => sum + trade.quantity);
    final winStreak = _maxStreak(closed, winning: true);
    final lossStreak = _maxStreak(closed, winning: false);
    final tradingDays = ordersByDay.length;
    final maxSymbolsInDay = symbolsByDay.values.isEmpty
        ? 0
        : symbolsByDay.values.map((set) => set.length).reduce(math.max);
    final maxTradesInDay =
        ordersByDay.values.isEmpty ? 0 : ordersByDay.values.reduce(math.max);
    final maxSymbolTurnover = turnoverBySymbol.values.isEmpty
        ? 0.0
        : turnoverBySymbol.values.reduce(math.max);
    final openLotCount = lots.values
        .expand((queue) => queue)
        .where((lot) => lot.remaining > 1e-9)
        .length;
    final winningHold = wins.isEmpty
        ? 0.0
        : wins.fold<double>(0, (sum, trade) => sum + trade.holdingHours) /
            wins.length;
    final losingHold = losses.isEmpty
        ? 0.0
        : losses.fold<double>(0, (sum, trade) => sum + trade.holdingHours) /
            losses.length;

    final metrics = TradeMetrics(
      realizedPnl: realizedPnl,
      grossProfit: grossProfit,
      grossLoss: grossLoss,
      matchedSellCount: closed.length,
      winningSellCount: wins.length,
      losingSellCount: losses.length,
      winRate: closed.isEmpty ? 0 : wins.length / closed.length,
      averageWin: averageWin,
      averageLoss: averageLoss,
      profitLossRatio: profitLossRatio,
      expectancy: closed.isEmpty ? 0 : realizedPnl / closed.length,
      averageHoldingHours:
          matchedQuantity <= 0 ? 0 : weightedHolding / matchedQuantity,
      averageWinningHoldingHours: winningHold,
      averageLosingHoldingHours: losingHold,
      maxWinStreak: winStreak,
      maxLossStreak: lossStreak,
      sameDayRoundTrips: closed.where((trade) => trade.sameDay).length,
      totalFees: totalFees,
      turnover: turnover,
      feeRatio: realizedPnl == 0
          ? (totalFees > 0 ? 1.0 : 0.0)
          : totalFees / realizedPnl.abs(),
      concentrationRatio: turnover <= 0 ? 0 : maxSymbolTurnover / turnover,
      maxSymbolsInDay: maxSymbolsInDay,
      averageSymbolsPerDay: tradingDays == 0
          ? 0
          : symbolsByDay.values.fold<int>(0, (sum, set) => sum + set.length) /
              tradingDays,
      maxTradesInDay: maxTradesInDay,
      averageTradesPerTradingDay:
          tradingDays == 0 ? 0 : valid.length / tradingDays,
      tradingDayCount: tradingDays,
      openLotCount: openLotCount,
      bestTradePnl: closed.isEmpty
          ? 0
          : closed.map((trade) => trade.pnl).reduce(math.max),
      worstTradePnl: closed.isEmpty
          ? 0
          : closed.map((trade) => trade.pnl).reduce(math.min),
    );

    if (valid.isEmpty) {
      warnings.add('没有可分析的成交行，请上传包含日期、方向、数量和价格的成交记录截图。');
    } else if (closed.length < 3) {
      warnings.add('已配对的卖出记录少于 3 笔，胜率和盈亏比只能作为初步观察。');
    }
    if (metrics.openLotCount > 0) {
      warnings.add(
        '截图结束时仍有 ${metrics.openLotCount} 批买入未平仓；'
        '这些持仓的浮动盈亏不在本报告的已实现盈亏中。',
      );
    }
    warnings.add('截图未包含账户总资金与单笔风险预算，因此本报告不判断仓位比例或止损金额。');

    final logic = _buildLogic(metrics, valid.length, turnoverBySymbol);
    final problems = _buildProblems(metrics, closed.length);
    final improvements = _buildImprovements(metrics, closed.length);

    final uniqueWarnings = <String>[];
    for (final warning in warnings) {
      if (warning.trim().isNotEmpty && !uniqueWarnings.contains(warning)) {
        uniqueWarnings.add(warning);
      }
    }
    final firstDay = valid.isEmpty ? null : _day(valid.first.occurredAt);
    final lastDay = valid.isEmpty ? null : _day(valid.last.occurredAt);
    final range = firstDay == null || lastDay == null
        ? '成交复盘'
        : '${firstDay.month}月${firstDay.day}日'
            '${_sameDate(firstDay, lastDay) ? '' : '－${lastDay.month}月${lastDay.day}日'}'
            ' · ${valid.length} 笔成交';
    return TradeReviewReport(
      id: 'review-${createdAt.microsecondsSinceEpoch}',
      createdAt: createdAt,
      title: range,
      brokerHint: brokerHint,
      currency: currency.isEmpty ? 'CNY' : currency,
      trades: valid,
      metrics: metrics,
      logic: logic,
      problems: problems,
      improvements: improvements,
      warnings: uniqueWarnings,
    );
  }

  List<TradeInsight> _buildLogic(
    TradeMetrics metrics,
    int tradeCount,
    Map<String, double> turnoverBySymbol,
  ) {
    if (tradeCount == 0) return const [];
    final logic = <TradeInsight>[];
    final speed = metrics.averageHoldingHours <= 24
        ? '偏短周期'
        : metrics.averageHoldingHours <= 24 * 5
            ? '以数日持有为主'
            : '持有周期相对较长';
    logic.add(
      TradeInsight(
        kind: TradeInsightKind.logic,
        title: '持仓节奏：$speed',
        body: metrics.matchedSellCount == 0
            ? '现有成交尚未形成可配对的卖出闭环，无法判断持仓时长。'
            : '卖出按先进先出与买入配对后，已平仓交易的平均持有时间'
                '约为 ${_hours(metrics.averageHoldingHours)}。',
        evidence: [
          '${metrics.sameDayRoundTrips} 笔卖出与同日买入形成闭环',
          '共 ${metrics.tradingDayCount} 个交易日、${metrics.matchedSellCount} 笔已配对卖出',
        ],
      ),
    );

    if (metrics.matchedSellCount > 0) {
      final outcome = metrics.realizedPnl >= 0 ? '盈利' : '亏损';
      logic.add(
        TradeInsight(
          kind: TradeInsightKind.logic,
          title: '结果结构：$outcome由胜率和赔率共同决定',
          body: metrics.profitLossRatio == double.infinity
              ? '样本内没有亏损卖出，当前盈亏比无法稳定估计；'
                  '这通常也意味着样本偏少或区间偏短。'
              : '当前胜率为 ${_percent(metrics.winRate)}，'
                  '平均盈利 / 平均亏损为 ${_ratio(metrics.profitLossRatio)}，'
                  '每笔已配对卖出的期望为 ${_num(metrics.expectancy)}。',
          evidence: [
            '盈利 ${metrics.winningSellCount} 笔，亏损 ${metrics.losingSellCount} 笔',
            '最大连续盈利 ${metrics.maxWinStreak} 笔，最大连续亏损 ${metrics.maxLossStreak} 笔',
          ],
        ),
      );
    }

    if (turnoverBySymbol.isNotEmpty) {
      final sorted = turnoverBySymbol.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final leader = sorted.first.key;
      final concentration = metrics.concentrationRatio;
      logic.add(
        TradeInsight(
          kind: TradeInsightKind.logic,
          title: concentration >= 0.5 ? '标的选择：明显集中于单一标的' : '标的选择：成交分散在多个标的',
          body: concentration >= 0.5
              ? '成交金额占比最高的标的是 $leader，'
                  '占全部成交金额的 ${_percent(concentration)}。'
              : '成交金额没有集中在单一标的，最高占比为 ${_percent(concentration)}。',
          evidence: [
            '单日最多涉及 ${metrics.maxSymbolsInDay} 个标的',
            '日均涉及 ${_decimal(metrics.averageSymbolsPerDay)} 个标的',
          ],
        ),
      );
    }

    logic.add(
      TradeInsight(
        kind: TradeInsightKind.logic,
        title: '执行密度：${_densityLabel(metrics.averageTradesPerTradingDay)}',
        body: '按截图中的交易日计算，日均成交 '
            '${_decimal(metrics.averageTradesPerTradingDay)} 笔，'
            '单日最多 ${metrics.maxTradesInDay} 笔。'
            '这是成交频率，不等同于仓位轻重。',
        evidence: [
          '累计成交金额 ${_num(metrics.turnover)}',
          '累计手续费 ${_num(metrics.totalFees)}',
        ],
      ),
    );
    return logic.take(4).toList();
  }

  List<TradeInsight> _buildProblems(TradeMetrics metrics, int closedCount) {
    final problems = <TradeInsight>[];
    if (closedCount < 3) {
      problems.add(
        const TradeInsight(
          kind: TradeInsightKind.problem,
          title: '样本不足，暂不把短期结果当作稳定规律',
          body: '可配对的卖出少于 3 笔。此时胜率、连续亏损和盈亏比都容易受单笔交易影响，'
              '更适合先核对数据是否完整，再扩大复盘区间。',
        ),
      );
    }
    if (metrics.averageWinningHoldingHours > 0 &&
        metrics.averageLosingHoldingHours > 0 &&
        metrics.averageWinningHoldingHours + 0.01 <
            metrics.averageLosingHoldingHours &&
        metrics.winningSellCount >= 2 &&
        metrics.losingSellCount >= 2) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '出现“赢家卖得快、亏损拿得久”的处置效应',
          body: '盈利交易的平均持有时间短于亏损交易。它可能来自过早兑现，'
              '也可能来自亏损后拖延退出；需要结合入场理由复核。',
          evidence: [
            '盈利平均持有 ${_hours(metrics.averageWinningHoldingHours)}',
            '亏损平均持有 ${_hours(metrics.averageLosingHoldingHours)}',
          ],
        ),
      );
    }
    if (metrics.totalFees > 0 &&
        metrics.realizedPnl <= 0 &&
        metrics.matchedSellCount > 0) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '手续费仍在放大已实现亏损',
          body: '样本内已实现结果为亏损，同时产生了手续费。'
              '高频或不必要的换手会让本金在方向判断之外继续损耗。',
          evidence: ['累计手续费 ${_num(metrics.totalFees)}'],
        ),
      );
    } else if (metrics.feeRatio >= 0.2 && metrics.matchedSellCount > 0) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '手续费对净收益的侵蚀偏高',
          body: '手续费占已实现盈亏绝对值的比例较高。'
              '在单笔优势不够明显时，频繁成交更容易把利润磨掉。',
          evidence: ['手续费 / |已实现盈亏| = ${_percent(metrics.feeRatio)}'],
        ),
      );
    }
    if (metrics.maxLossStreak >= 3) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '连续亏损后的执行稳定性需要检查',
          body: '样本内出现过 ${metrics.maxLossStreak} 笔连续亏损。'
              '重点不是把这段亏损解释成行情，而是检查连亏后是否加速加注、'
              '扩大交易频率或取消原有退出条件。',
        ),
      );
    }
    if (metrics.profitLossRatio < 1 &&
        metrics.winningSellCount >= 2 &&
        metrics.losingSellCount >= 2) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '平均盈利不足以覆盖平均亏损',
          body: '即使胜率不低，单笔平均亏损仍大于单笔平均盈利。'
              '需要让盈利目标、退出条件和实际波动重新匹配。',
          evidence: ['盈亏比 ${_ratio(metrics.profitLossRatio)}'],
        ),
      );
    }
    if (metrics.maxSymbolsInDay >= 4 ||
        (metrics.averageSymbolsPerDay >= 3 &&
            metrics.averageTradesPerTradingDay >= 6)) {
      problems.add(
        TradeInsight(
          kind: TradeInsightKind.problem,
          title: '同日多标的切换可能压缩复盘深度',
          body: '成交记录显示同一天频繁切换多个标的。'
              '由于截图没有入场理由，不能直接断言追涨或冲动交易；'
              '但标的切换越快，越容易遗漏原定退出条件。',
          evidence: [
            '单日最多 ${metrics.maxSymbolsInDay} 个标的',
            '日均 ${_decimal(metrics.averageTradesPerTradingDay)} 笔成交',
          ],
        ),
      );
    }
    if (problems.isEmpty) {
      problems.add(
        const TradeInsight(
          kind: TradeInsightKind.problem,
          title: '截图能证明的问题有限',
          body: '从成交行本身没有发现明显的频率、赔率或手续费异常。'
              '这不等于交易逻辑可靠，仍需要对照每笔交易前的入场理由和退出计划。',
        ),
      );
    }
    return problems.take(4).toList();
  }

  List<TradeInsight> _buildImprovements(
    TradeMetrics metrics,
    int closedCount,
  ) {
    final improvements = <TradeInsight>[];
    if (metrics.totalFees > 0) {
      improvements.add(
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '给每笔交易写一句入场理由和退出条件',
          body: '下单前写清“为什么现在买 / 什么情况下退出”，'
              '成交后再用截图核对执行是否偏离。这样下一次复盘能区分判断问题与执行问题。',
        ),
      );
    }
    if (metrics.sameDayRoundTrips > 0 ||
        metrics.averageTradesPerTradingDay >= 6) {
      improvements.add(
        TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '设置“冷静一笔”规则',
          body: '在同一标的卖出后，先记录结果和原因，再决定是否立即寻找下一个标的。'
              '先减少无计划的同日切换，再观察胜率和手续费是否改善。',
          evidence: ['当前有 ${metrics.sameDayRoundTrips} 笔同日闭环交易'],
        ),
      );
    }
    if (metrics.maxLossStreak >= 3) {
      improvements.add(
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '为连续亏损设置暂停与复核条件',
          body: '连续亏损达到预设笔数时暂停新开仓，'
              '逐笔核对入场理由、退出条件和是否临时改变计划。'
              '暂停条件应提前写下，避免亏损发生后临时决定。',
        ),
      );
    }
    if (metrics.profitLossRatio < 1 &&
        metrics.winningSellCount >= 2 &&
        metrics.losingSellCount >= 2) {
      improvements.add(
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '把退出条件放在入场之前',
          body: '复盘亏损单时，不只看亏损金额，还要记录当时依据什么继续持有。'
              '下一批交易先写退出点，再执行，避免把短线交易拖成被动持有。',
        ),
      );
    }
    if (metrics.concentrationRatio >= 0.5) {
      improvements.add(
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '复核单一标的的重复决策',
          body: '高集中度本身不是错误，但需要确认每笔增减仓都有独立理由，'
              '避免把上一笔的盈亏情绪带进下一笔。',
        ),
      );
    }
    if (closedCount < 3) {
      improvements.insert(
        0,
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '先补全一段完整成交区间',
          body: '优先上传覆盖多笔买入和卖出的成交记录，'
              '确保每一笔卖出都能与买入配对，再比较胜率和盈亏比。',
        ),
      );
    }
    if (improvements.length < 2) {
      improvements.add(
        const TradeInsight(
          kind: TradeInsightKind.improvement,
          title: '每周固定复看一次连续亏损段',
          body: '不要只复盘赚钱单。把连续亏损前后的成交频率、标的切换和退出执行放在一起看，'
              '更容易发现行为变化。',
        ),
      );
    }
    return improvements.take(4).toList();
  }
}

class _Lot {
  _Lot({
    required this.remaining,
    required this.costPerUnit,
    required this.acquiredAt,
  });

  double remaining;
  final double costPerUnit;
  final DateTime acquiredAt;
}

class _ClosedTrade {
  const _ClosedTrade({
    required this.pnl,
    required this.quantity,
    required this.holdingHours,
    required this.sameDay,
  });

  final double pnl;
  final double quantity;
  final double holdingHours;
  final bool sameDay;
}

int _maxStreak(List<_ClosedTrade> trades, {required bool winning}) {
  var current = 0;
  var best = 0;
  for (final trade in trades) {
    final matches = winning ? trade.pnl > 0 : trade.pnl < 0;
    if (matches) {
      current++;
      best = math.max(best, current);
    } else {
      current = 0;
    }
  }
  return best;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateText(DateTime value) => '${value.month}月${value.day}日';

String _qty(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

String _num(double value) => value.toStringAsFixed(2);

String _decimal(double value) => value.toStringAsFixed(1);

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _ratio(double value) =>
    value.isFinite ? '${value.toStringAsFixed(2)} : 1' : '∞ : 1';

String _hours(double value) {
  if (value <= 0) return '不到 1 小时';
  if (value < 24) return '${value.toStringAsFixed(1)} 小时';
  return '${(value / 24).toStringAsFixed(1)} 天';
}

String _densityLabel(double value) {
  if (value >= 8) return '偏高';
  if (value >= 3) return '中等';
  return '较低';
}
