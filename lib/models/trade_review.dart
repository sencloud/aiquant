import 'dart:math' as math;

enum TradeSide { buy, sell }

extension TradeSideLabel on TradeSide {
  String get apiValue => this == TradeSide.buy ? 'buy' : 'sell';

  String get label => this == TradeSide.buy ? '买入' : '卖出';

  static TradeSide? fromApi(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'buy' || '买入' => TradeSide.buy,
      'sell' || '卖出' => TradeSide.sell,
      _ => null,
    };
  }
}

class ParsedTrade {
  const ParsedTrade({
    required this.occurredAt,
    required this.symbol,
    required this.name,
    required this.side,
    required this.quantity,
    required this.price,
    this.fee = 0,
    this.sourceIndex = 0,
  });

  factory ParsedTrade.fromJson(Map<String, dynamic> json) {
    final dateText = (json['trade_date'] ?? '').toString().trim();
    final timeText = (json['trade_time'] ?? '').toString().trim();
    final parsedDate = DateTime.tryParse(
      timeText.isEmpty ? dateText : '${dateText}T$timeText',
    );
    final side = TradeSideLabel.fromApi(json['side']?.toString());
    if (parsedDate == null || side == null) {
      throw const FormatException('成交日期或买卖方向无效');
    }
    return ParsedTrade(
      occurredAt: parsedDate,
      symbol: (json['symbol'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString().trim(),
      side: side,
      quantity: _number(json['quantity']),
      price: _number(json['price']),
      fee: _number(json['fee']),
      sourceIndex: _integer(json['source_index']),
    );
  }

  final DateTime occurredAt;
  final String symbol;
  final String name;
  final TradeSide side;
  final double quantity;
  final double price;
  final double fee;
  final int sourceIndex;

  String get instrumentLabel {
    if (name.isNotEmpty && symbol.isNotEmpty && name != symbol) {
      return '$name · $symbol';
    }
    if (name.isNotEmpty) return name;
    if (symbol.isNotEmpty) return symbol;
    return '未命名标的';
  }

  String get instrumentKey {
    final value = symbol.isNotEmpty ? symbol : name;
    return value.trim().toUpperCase();
  }

  double get notional => quantity * price;

  ParsedTrade copyWith({
    DateTime? occurredAt,
    String? symbol,
    String? name,
    TradeSide? side,
    double? quantity,
    double? price,
    double? fee,
    int? sourceIndex,
  }) {
    return ParsedTrade(
      occurredAt: occurredAt ?? this.occurredAt,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      side: side ?? this.side,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      fee: fee ?? this.fee,
      sourceIndex: sourceIndex ?? this.sourceIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'trade_date': _dateOnly(occurredAt),
        if (_hasTime(occurredAt))
          'trade_time':
              '${_two(occurredAt.hour)}:${_two(occurredAt.minute)}:${_two(occurredAt.second)}',
        'symbol': symbol,
        'name': name,
        'side': side.apiValue,
        'quantity': quantity,
        'price': price,
        'fee': fee,
        'source_index': sourceIndex,
      };
}

class ParsedTradesResult {
  const ParsedTradesResult({
    required this.brokerHint,
    required this.currency,
    required this.trades,
    required this.warnings,
    this.screenshotCount = 1,
    this.successfulScreenshotCount = 1,
    this.duplicateTradeCount = 0,
  });

  final String brokerHint;
  final String currency;
  final List<ParsedTrade> trades;
  final List<String> warnings;
  final int screenshotCount;
  final int successfulScreenshotCount;
  final int duplicateTradeCount;
}

/// 合并一组截图的识别结果。
///
/// 相邻两页截图经常包含同一笔成交。这里以“每张截图内出现的最大次数”合并，
/// 而不是简单按指纹去重：同一张截图里两笔字段完全相同的真实成交仍会保留，
/// 重叠页带来的重复则会消失。
ParsedTradesResult mergeParsedTradeResults(
  List<ParsedTradesResult> results, {
  required int screenshotCount,
  List<String> failureWarnings = const [],
  List<int>? sourceScreenshotIndices,
}) {
  if (results.isEmpty) {
    throw ArgumentError.value(results, 'results', '至少需要一张成功识别的截图');
  }
  final screenshotIndices = sourceScreenshotIndices ??
      [for (var index = 0; index < results.length; index++) index];
  if (screenshotIndices.length != results.length) {
    throw ArgumentError.value(
      sourceScreenshotIndices,
      'sourceScreenshotIndices',
      '截图索引数量必须与识别结果数量一致',
    );
  }

  final warnings = <String>[];
  final brokers = <String>[];
  final currencies = <String>[];
  var inputTradeCount = 0;

  void addUnique(List<String> target, String value) {
    if (value.isEmpty || target.contains(value)) return;
    target.add(value);
  }

  final screenshotTrades = <List<ParsedTrade>>[];
  for (final result in results) {
    addUnique(brokers, result.brokerHint.trim());
    addUnique(currencies, result.currency.trim());
    for (final warning in result.warnings) {
      addUnique(warnings, warning.trim());
    }
    screenshotTrades.add(result.trades);
    inputTradeCount += result.trades.length;
  }

  // 相邻截图可能来自滑动列表的同一页片段。只允许和上一张截图中的记录
  // 相连，且必须与已有簇内每一条都匹配，避免 A≈B、B≈C 链式误合并，
  // 也避免同一成交在不相邻页面重复出现时被删掉。
  final clusters = _ClusterTrades(
    screenshotTrades,
    sourceScreenshotIndices: screenshotIndices,
  );
  final trades = <ParsedTrade>[];
  for (final cluster in clusters.clusters) {
    var bestGroup = cluster.groups.first;
    for (final group in cluster.groups.skip(1)) {
      if (group.trades.length > bestGroup.trades.length) {
        bestGroup = group;
      }
    }
    trades.addAll(bestGroup.trades);
  }
  trades.sort((a, b) {
    final byTime = a.occurredAt.compareTo(b.occurredAt);
    if (byTime != 0) return byTime;
    final byInstrument = a.instrumentKey.compareTo(b.instrumentKey);
    if (byInstrument != 0) return byInstrument;
    return a.sourceIndex.compareTo(b.sourceIndex);
  });
  final duplicateCount = inputTradeCount - trades.length;

  for (final warning in failureWarnings) {
    addUnique(warnings, warning.trim());
  }
  if (duplicateCount > 0) {
    addUnique(warnings, '多张截图有 $duplicateCount 笔重叠成交，已自动合并。');
  }
  if (currencies.length > 1) {
    addUnique(warnings, '截图里出现了多种币种，请逐笔核对币种口径。');
  }

  return ParsedTradesResult(
    brokerHint: brokers.join('、'),
    currency: currencies.isEmpty ? 'CNY' : currencies.first,
    trades: trades,
    warnings: warnings,
    screenshotCount: screenshotCount,
    successfulScreenshotCount: results.length,
    duplicateTradeCount: duplicateCount,
  );
}

bool _isSameOverlappingTrade(ParsedTrade a, ParsedTrade b) {
  if (a.side != b.side) return false;
  final aDay =
      DateTime(a.occurredAt.year, a.occurredAt.month, a.occurredAt.day);
  final bDay =
      DateTime(b.occurredAt.year, b.occurredAt.month, b.occurredAt.day);
  if (aDay != bDay) return false;
  if (!_instrumentIdentitiesMatch(a, b)) return false;
  if ((a.quantity - b.quantity).abs() > 0.01) return false;

  final priceTolerance = math.max(
    0.0011,
    math.min(0.01, a.price.abs() * 0.00001),
  );
  if ((a.price - b.price).abs() > priceTolerance) return false;

  final aHasClock = _hasTime(a.occurredAt);
  final bHasClock = _hasTime(b.occurredAt);
  if (aHasClock && bHasClock) {
    return a.occurredAt.difference(b.occurredAt).inSeconds.abs() <= 90;
  }
  // 只有一侧识别出时间时，同一天的相同成交仍视为疑似重叠页。
  return true;
}

bool _instrumentIdentitiesMatch(ParsedTrade a, ParsedTrade b) {
  final aSymbol = a.symbol.trim().toUpperCase();
  final bSymbol = b.symbol.trim().toUpperCase();
  if (aSymbol.isNotEmpty && bSymbol.isNotEmpty) {
    return aSymbol == bSymbol;
  }
  final aName = _normalizedInstrumentName(a.name);
  final bName = _normalizedInstrumentName(b.name);
  if (aName.isNotEmpty && bName.isNotEmpty) {
    return aName == bName;
  }
  return a.instrumentKey == b.instrumentKey;
}

String _normalizedInstrumentName(String value) {
  return value
      .replaceAll(RegExp(r'[\s·•・\-—]'), '')
      .replaceAll('股份有限公司', '')
      .trim()
      .toUpperCase();
}

class _ClusterTrades {
  _ClusterTrades(
    List<List<ParsedTrade>> screenshots, {
    required List<int> sourceScreenshotIndices,
  }) {
    final localGroups = <_TradeGroup>[];
    for (var screenshotIndex = 0;
        screenshotIndex < screenshots.length;
        screenshotIndex++) {
      localGroups.addAll(_groupScreenshotTrades(
        screenshots[screenshotIndex],
        sourceScreenshotIndices[screenshotIndex],
      ));
    }

    for (final group in localGroups) {
      _TradeCluster? best;
      var bestScore = double.infinity;
      for (final cluster in clusters) {
        if (cluster.hasScreenshot(group.screenshotIndex) ||
            !cluster.hasScreenshot(group.screenshotIndex - 1) ||
            !cluster.groups.every((prior) => _groupsOverlap(prior, group))) {
          continue;
        }
        final score = cluster.groups
            .map((prior) => _groupOverlapScore(prior, group))
            .reduce(math.min);
        if (score < bestScore) {
          best = cluster;
          bestScore = score;
        }
      }
      if (best == null) {
        clusters.add(_TradeCluster([group]));
      } else {
        best.groups.add(group);
      }
    }
  }

  final List<_TradeCluster> clusters = [];
}

List<_TradeGroup> _groupScreenshotTrades(
  List<ParsedTrade> trades,
  int screenshotIndex,
) {
  final groups = <_TradeGroup>[];
  for (final trade in trades) {
    _TradeGroup? target;
    for (final group in groups) {
      if (group.trades.every(
        (existing) => _isSameFillWithinScreenshot(existing, trade),
      )) {
        target = group;
        break;
      }
    }
    if (target == null) {
      groups.add(_TradeGroup(screenshotIndex, [trade]));
    } else {
      target.trades.add(trade);
    }
  }
  return groups;
}

bool _isSameFillWithinScreenshot(ParsedTrade a, ParsedTrade b) {
  if (!_isSameOverlappingTrade(a, b)) return false;
  if (!_hasTime(a.occurredAt) || !_hasTime(b.occurredAt)) return true;
  return a.occurredAt.difference(b.occurredAt).inSeconds.abs() <= 5;
}

bool _groupsOverlap(_TradeGroup a, _TradeGroup b) {
  for (final left in a.trades) {
    for (final right in b.trades) {
      if (!_isSameOverlappingTrade(left, right)) return false;
    }
  }
  return true;
}

double _groupOverlapScore(_TradeGroup a, _TradeGroup b) {
  var score = 0.0;
  for (final left in a.trades) {
    for (final right in b.trades) {
      score = math.max(score, _overlapScore(left, right));
    }
  }
  return score;
}

class _TradeGroup {
  _TradeGroup(
    this.screenshotIndex,
    this.trades,
  );

  final int screenshotIndex;
  final List<ParsedTrade> trades;
}

class _TradeCluster {
  _TradeCluster(this.groups);

  final List<_TradeGroup> groups;

  bool hasScreenshot(int screenshotIndex) {
    return groups.any((group) => group.screenshotIndex == screenshotIndex);
  }
}

double _overlapScore(ParsedTrade a, ParsedTrade b) {
  final seconds = _hasTime(a.occurredAt) && _hasTime(b.occurredAt)
      ? a.occurredAt.difference(b.occurredAt).inSeconds.abs().toDouble()
      : 0;
  return seconds +
      (a.price - b.price).abs() * 100000 +
      (a.quantity - b.quantity).abs() * 1000;
}

String tradeFingerprint(ParsedTrade trade) {
  final time = trade.occurredAt;
  String two(int value) => value.toString().padLeft(2, '0');
  String amount(double value) => (value * 10000).round().toString();
  final instrument = trade.instrumentKey;
  return [
    '${time.year}-${two(time.month)}-${two(time.day)}',
    '${two(time.hour)}:${two(time.minute)}',
    instrument,
    trade.side.apiValue,
    amount(trade.quantity),
    amount(trade.price),
    (trade.fee * 100).round().toString(),
  ].join('|');
}

class TradeMetrics {
  const TradeMetrics({
    required this.realizedPnl,
    required this.grossProfit,
    required this.grossLoss,
    required this.matchedSellCount,
    required this.winningSellCount,
    required this.losingSellCount,
    required this.winRate,
    required this.averageWin,
    required this.averageLoss,
    required this.profitLossRatio,
    required this.expectancy,
    required this.averageHoldingHours,
    required this.averageWinningHoldingHours,
    required this.averageLosingHoldingHours,
    required this.maxWinStreak,
    required this.maxLossStreak,
    required this.sameDayRoundTrips,
    required this.totalFees,
    required this.turnover,
    required this.feeRatio,
    required this.concentrationRatio,
    required this.maxSymbolsInDay,
    required this.averageSymbolsPerDay,
    required this.maxTradesInDay,
    required this.averageTradesPerTradingDay,
    required this.tradingDayCount,
    required this.openLotCount,
    required this.bestTradePnl,
    required this.worstTradePnl,
  });

  factory TradeMetrics.fromJson(Map<String, dynamic> json) {
    return TradeMetrics(
      realizedPnl: _number(json['realized_pnl']),
      grossProfit: _number(json['gross_profit']),
      grossLoss: _number(json['gross_loss']),
      matchedSellCount: _integer(json['matched_sell_count']),
      winningSellCount: _integer(json['winning_sell_count']),
      losingSellCount: _integer(json['losing_sell_count']),
      winRate: _number(json['win_rate']),
      averageWin: _number(json['average_win']),
      averageLoss: _number(json['average_loss']),
      profitLossRatio: _number(json['profit_loss_ratio']) < 0
          ? double.infinity
          : _number(json['profit_loss_ratio']),
      expectancy: _number(json['expectancy']),
      averageHoldingHours: _number(json['average_holding_hours']),
      averageWinningHoldingHours:
          _number(json['average_winning_holding_hours']),
      averageLosingHoldingHours: _number(json['average_losing_holding_hours']),
      maxWinStreak: _integer(json['max_win_streak']),
      maxLossStreak: _integer(json['max_loss_streak']),
      sameDayRoundTrips: _integer(json['same_day_round_trips']),
      totalFees: _number(json['total_fees']),
      turnover: _number(json['turnover']),
      feeRatio: _number(json['fee_ratio']),
      concentrationRatio: _number(json['concentration_ratio']),
      maxSymbolsInDay: _integer(json['max_symbols_in_day']),
      averageSymbolsPerDay: _number(json['average_symbols_per_day']),
      maxTradesInDay: _integer(json['max_trades_in_day']),
      averageTradesPerTradingDay:
          _number(json['average_trades_per_trading_day']),
      tradingDayCount: _integer(json['trading_day_count']),
      openLotCount: _integer(json['open_lot_count']),
      bestTradePnl: _number(json['best_trade_pnl']),
      worstTradePnl: _number(json['worst_trade_pnl']),
    );
  }

  final double realizedPnl;
  final double grossProfit;
  final double grossLoss;
  final int matchedSellCount;
  final int winningSellCount;
  final int losingSellCount;
  final double winRate;
  final double averageWin;
  final double averageLoss;
  final double profitLossRatio;
  final double expectancy;
  final double averageHoldingHours;
  final double averageWinningHoldingHours;
  final double averageLosingHoldingHours;
  final int maxWinStreak;
  final int maxLossStreak;
  final int sameDayRoundTrips;
  final double totalFees;
  final double turnover;
  final double feeRatio;
  final double concentrationRatio;
  final int maxSymbolsInDay;
  final double averageSymbolsPerDay;
  final int maxTradesInDay;
  final double averageTradesPerTradingDay;
  final int tradingDayCount;
  final int openLotCount;
  final double bestTradePnl;
  final double worstTradePnl;

  Map<String, dynamic> toJson() => {
        'realized_pnl': realizedPnl,
        'gross_profit': grossProfit,
        'gross_loss': grossLoss,
        'matched_sell_count': matchedSellCount,
        'winning_sell_count': winningSellCount,
        'losing_sell_count': losingSellCount,
        'win_rate': winRate,
        'average_win': averageWin,
        'average_loss': averageLoss,
        'profit_loss_ratio': profitLossRatio.isFinite ? profitLossRatio : -1,
        'expectancy': expectancy,
        'average_holding_hours': averageHoldingHours,
        'average_winning_holding_hours': averageWinningHoldingHours,
        'average_losing_holding_hours': averageLosingHoldingHours,
        'max_win_streak': maxWinStreak,
        'max_loss_streak': maxLossStreak,
        'same_day_round_trips': sameDayRoundTrips,
        'total_fees': totalFees,
        'turnover': turnover,
        'fee_ratio': feeRatio,
        'concentration_ratio': concentrationRatio,
        'max_symbols_in_day': maxSymbolsInDay,
        'average_symbols_per_day': averageSymbolsPerDay,
        'max_trades_in_day': maxTradesInDay,
        'average_trades_per_trading_day': averageTradesPerTradingDay,
        'trading_day_count': tradingDayCount,
        'open_lot_count': openLotCount,
        'best_trade_pnl': bestTradePnl,
        'worst_trade_pnl': worstTradePnl,
      };
}

enum TradeInsightKind { logic, problem, improvement }

class TradeInsight {
  const TradeInsight({
    required this.kind,
    required this.title,
    required this.body,
    this.evidence = const [],
  });

  factory TradeInsight.fromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']?.toString()) {
      'logic' => TradeInsightKind.logic,
      'improvement' => TradeInsightKind.improvement,
      _ => TradeInsightKind.problem,
    };
    return TradeInsight(
      kind: kind,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      evidence: [
        for (final row in (json['evidence'] as List? ?? const []))
          if (row != null) row.toString(),
      ],
    );
  }

  final TradeInsightKind kind;
  final String title;
  final String body;
  final List<String> evidence;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'body': body,
        'evidence': evidence,
      };
}

class TradeContextEvent {
  const TradeContextEvent({
    required this.date,
    required this.scope,
    required this.category,
    required this.title,
    this.time = '',
    this.summary = '',
    this.source = '',
    this.url = '',
    this.importance = 0,
    this.timing = '',
    this.relatedTradeDates = const [],
  });

  factory TradeContextEvent.fromJson(Map<String, dynamic> json) {
    return TradeContextEvent(
      date: (json['date'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      scope: (json['scope'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      importance: _integer(json['importance']),
      timing: (json['timing'] ?? '').toString(),
      relatedTradeDates: [
        for (final row in (json['related_trade_dates'] as List? ?? const []))
          if (row != null) row.toString(),
      ],
    );
  }

  final String date;
  final String time;
  final String scope;
  final String category;
  final String title;
  final String summary;
  final String source;
  final String url;
  final int importance;
  final String timing;
  final List<String> relatedTradeDates;

  Map<String, dynamic> toJson() => {
        'date': date,
        if (time.isNotEmpty) 'time': time,
        'scope': scope,
        'category': category,
        'title': title,
        if (summary.isNotEmpty) 'summary': summary,
        if (source.isNotEmpty) 'source': source,
        if (url.isNotEmpty) 'url': url,
        if (importance > 0) 'importance': importance,
        if (timing.isNotEmpty) 'timing': timing,
        if (relatedTradeDates.isNotEmpty)
          'related_trade_dates': relatedTradeDates,
      };
}

class TradeContextCoverage {
  const TradeContextCoverage({
    required this.source,
    required this.status,
    required this.count,
    this.detail = '',
  });

  factory TradeContextCoverage.fromJson(Map<String, dynamic> json) {
    return TradeContextCoverage(
      source: (json['source'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      count: _integer(json['count']),
      detail: (json['detail'] ?? '').toString(),
    );
  }

  final String source;
  final String status;
  final int count;
  final String detail;

  Map<String, dynamic> toJson() => {
        'source': source,
        'status': status,
        'count': count,
        if (detail.isNotEmpty) 'detail': detail,
      };
}

class TradeMarketContext {
  const TradeMarketContext({
    this.events = const [],
    this.coverage = const [],
    this.gaps = const [],
  });

  factory TradeMarketContext.fromJson(Map<String, dynamic> json) {
    return TradeMarketContext(
      events: [
        for (final row in (json['events'] as List? ?? const []))
          if (row is Map)
            TradeContextEvent.fromJson(Map<String, dynamic>.from(row)),
      ],
      coverage: [
        for (final row in (json['coverage'] as List? ?? const []))
          if (row is Map)
            TradeContextCoverage.fromJson(Map<String, dynamic>.from(row)),
      ],
      gaps: [
        for (final row in (json['gaps'] as List? ?? const []))
          if (row != null) row.toString(),
      ],
    );
  }

  final List<TradeContextEvent> events;
  final List<TradeContextCoverage> coverage;
  final List<String> gaps;

  bool get isEmpty => events.isEmpty && coverage.isEmpty && gaps.isEmpty;

  Map<String, dynamic> toJson() => {
        'events': events.map((event) => event.toJson()).toList(),
        'coverage': coverage.map((item) => item.toJson()).toList(),
        'gaps': gaps,
      };
}

class TradePerspective {
  const TradePerspective({
    required this.dimension,
    required this.title,
    required this.body,
    required this.basis,
    this.evidence = const [],
    this.confidence = '',
  });

  factory TradePerspective.fromJson(Map<String, dynamic> json) {
    return TradePerspective(
      dimension: (json['dimension'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      basis: (json['basis'] ?? '').toString(),
      evidence: [
        for (final row in (json['evidence'] as List? ?? const []))
          if (row != null) row.toString(),
      ],
      confidence: (json['confidence'] ?? '').toString(),
    );
  }

  final String dimension;
  final String title;
  final String body;
  final String basis;
  final List<String> evidence;
  final String confidence;

  Map<String, dynamic> toJson() => {
        'dimension': dimension,
        'title': title,
        'body': body,
        'basis': basis,
        'evidence': evidence,
        'confidence': confidence,
      };
}

class TradeReviewReport {
  const TradeReviewReport({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.brokerHint,
    required this.currency,
    required this.trades,
    required this.metrics,
    required this.logic,
    required this.problems,
    required this.improvements,
    required this.warnings,
    this.marketContext = const TradeMarketContext(),
    this.perspectives = const [],
  });

  factory TradeReviewReport.fromJson(Map<String, dynamic> json) {
    List<TradeInsight> insights(String key) => [
          for (final row in (json[key] as List? ?? const []))
            if (row is Map)
              TradeInsight.fromJson(Map<String, dynamic>.from(row)),
        ];
    return TradeReviewReport(
      id: (json['id'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      title: (json['title'] ?? '交易复盘').toString(),
      brokerHint: (json['broker_hint'] ?? '').toString(),
      currency: (json['currency'] ?? 'CNY').toString(),
      trades: [
        for (final row in (json['trades'] as List? ?? const []))
          if (row is Map) ParsedTrade.fromJson(Map<String, dynamic>.from(row)),
      ],
      metrics: TradeMetrics.fromJson(
        Map<String, dynamic>.from(
          json['metrics'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      logic: insights('logic'),
      problems: insights('problems'),
      improvements: insights('improvements'),
      marketContext: TradeMarketContext.fromJson(
        Map<String, dynamic>.from(
          json['market_context'] as Map? ?? const <String, dynamic>{},
        ),
      ),
      perspectives: [
        for (final row in (json['perspectives'] as List? ?? const []))
          if (row is Map)
            TradePerspective.fromJson(Map<String, dynamic>.from(row)),
      ],
      warnings: [
        for (final row in (json['warnings'] as List? ?? const []))
          if (row != null) row.toString(),
      ],
    );
  }

  final String id;
  final DateTime createdAt;
  final String title;
  final String brokerHint;
  final String currency;
  final List<ParsedTrade> trades;
  final TradeMetrics metrics;
  final List<TradeInsight> logic;
  final List<TradeInsight> problems;
  final List<TradeInsight> improvements;
  final List<String> warnings;
  final TradeMarketContext marketContext;
  final List<TradePerspective> perspectives;

  int get buyCount => trades.where((t) => t.side == TradeSide.buy).length;
  int get sellCount => trades.where((t) => t.side == TradeSide.sell).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'title': title,
        'broker_hint': brokerHint,
        'currency': currency,
        'trades': trades.map((trade) => trade.toJson()).toList(),
        'metrics': metrics.toJson(),
        'logic': logic.map((item) => item.toJson()).toList(),
        'problems': problems.map((item) => item.toJson()).toList(),
        'improvements': improvements.map((item) => item.toJson()).toList(),
        'market_context': marketContext.toJson(),
        'perspectives': perspectives.map((item) => item.toJson()).toList(),
        'warnings': warnings,
      };
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}

int _integer(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${_two(value.month)}-${_two(value.day)}';

bool _hasTime(DateTime value) =>
    value.hour != 0 ||
    value.minute != 0 ||
    value.second != 0 ||
    value.millisecond != 0 ||
    value.microsecond != 0;
