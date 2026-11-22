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
  });

  final String brokerHint;
  final String currency;
  final List<ParsedTrade> trades;
  final List<String> warnings;
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
