import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

export 'transaction.dart';

const _uuid = Uuid();

/// 投资组合 — 一份命名好的资产清单（持仓 + 交易记录由其他对象承担）。
class Portfolio extends HiveObject {
  String id;
  String name;
  String currency;
  String owner;
  String description;
  DateTime createdAt;
  DateTime updatedAt;

  Portfolio({
    String? id,
    required this.name,
    this.currency = 'CNY',
    this.owner = '本地用户',
    this.description = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}

class PortfolioAdapter extends TypeAdapter<Portfolio> {
  @override
  final int typeId = 1;

  @override
  Portfolio read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return Portfolio(
      id: fields[0] as String,
      name: fields[1] as String,
      currency: fields[2] as String? ?? 'CNY',
      owner: fields[3] as String? ?? '',
      description: fields[4] as String? ?? '',
      createdAt: fields[5] as DateTime? ?? DateTime.now(),
      updatedAt: fields[6] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, Portfolio obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.currency)
      ..writeByte(3)
      ..write(obj.owner)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }
}

/// One row in the positions blotter. Quantities are accumulated from
/// transactions; quote/price fields are filled at refresh time.
class PortfolioAsset {
  final String symbol;
  final String name;
  final String sector;
  final String assetClass; // 股票 / 期货 / ETF / 指数
  final double quantity;
  final double avgBuyPrice;
  /// 合约乘数：股票 / ETF / 指数 = 1；期货 = 每手对应的标的单位数
  /// （SR=10、IF=300、AU=1000…）。市值/成本/盈亏统一通过 multiplier 缩放。
  final double multiplier;

  final double? currentPrice;
  final double? dayChangePercent;

  PortfolioAsset({
    required this.symbol,
    required this.name,
    required this.sector,
    required this.assetClass,
    required this.quantity,
    required this.avgBuyPrice,
    this.multiplier = 1.0,
    this.currentPrice,
    this.dayChangePercent,
  });

  double get costBasis => quantity * avgBuyPrice * multiplier;
  double get marketValue =>
      (currentPrice ?? avgBuyPrice) * quantity * multiplier;
  double get unrealizedPnl => marketValue - costBasis;
  double get unrealizedPnlPercent =>
      costBasis == 0 ? 0 : unrealizedPnl / costBasis * 100.0;

  PortfolioAsset copyWith({
    double? quantity,
    double? avgBuyPrice,
    double? currentPrice,
    double? dayChangePercent,
    double? multiplier,
    String? sector,
    String? name,
    String? assetClass,
  }) {
    return PortfolioAsset(
      symbol: symbol,
      name: name ?? this.name,
      sector: sector ?? this.sector,
      assetClass: assetClass ?? this.assetClass,
      quantity: quantity ?? this.quantity,
      avgBuyPrice: avgBuyPrice ?? this.avgBuyPrice,
      multiplier: multiplier ?? this.multiplier,
      currentPrice: currentPrice ?? this.currentPrice,
      dayChangePercent: dayChangePercent ?? this.dayChangePercent,
    );
  }
}

class PortfolioSummary {
  final Portfolio portfolio;
  final List<PortfolioAsset> holdings;
  final DateTime lastUpdated;

  PortfolioSummary({
    required this.portfolio,
    required this.holdings,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  double get totalMarketValue =>
      holdings.fold(0.0, (s, h) => s + h.marketValue);
  double get totalCostBasis => holdings.fold(0.0, (s, h) => s + h.costBasis);
  double get totalUnrealizedPnl => totalMarketValue - totalCostBasis;
  double get totalUnrealizedPnlPercent =>
      totalCostBasis == 0 ? 0 : totalUnrealizedPnl / totalCostBasis * 100.0;
  double get totalDayChange => holdings.fold(
        0.0,
        (s, h) {
          final pct = h.dayChangePercent;
          if (pct == null || h.currentPrice == null) return s;
          final prev = h.currentPrice! / (1 + pct / 100.0);
          return s + (h.currentPrice! - prev) * h.quantity * h.multiplier;
        },
      );
  double get totalDayChangePercent {
    final prevValue = totalMarketValue - totalDayChange;
    if (prevValue <= 0) return 0;
    return totalDayChange / prevValue * 100.0;
  }

  int get positions => holdings.length;
  int get gainers => holdings.where((h) => h.unrealizedPnl > 0).length;
  int get losers => holdings.where((h) => h.unrealizedPnl < 0).length;

  Map<String, double> get sectorWeights {
    if (totalMarketValue <= 0) return const {};
    final sums = <String, double>{};
    for (final h in holdings) {
      final key = h.sector.isEmpty ? '其它' : h.sector;
      sums[key] = (sums[key] ?? 0) + h.marketValue;
    }
    return {
      for (final e in sums.entries) e.key: e.value / totalMarketValue * 100.0,
    };
  }

  /// 序列化为后端 ChatInput.PortfolioContext。
  ///
  /// 字段命名与 backend/internal/ai/chat/service.go 中的 `PortfolioContext`
  /// 严格对齐，调用方可直接 `jsonEncode` 后塞进 SSE body。
  Map<String, dynamic> toAiContext() {
    final mv = totalMarketValue;
    final cost = totalCostBasis;
    final pnl = mv - cost;
    final pnlPct = cost == 0 ? 0.0 : pnl / cost * 100.0;
    final dayPnl = totalDayChange;
    final dayPnlPct = totalDayChangePercent;
    return {
      'name': portfolio.name,
      'currency': portfolio.currency,
      'as_of_ms': lastUpdated.millisecondsSinceEpoch,
      'total_market_value': _round2(mv),
      'total_cost': _round2(cost),
      'total_pnl': _round2(pnl),
      'total_pnl_pct': _round2(pnlPct),
      'day_pnl': _round2(dayPnl),
      'day_pnl_pct': _round2(dayPnlPct),
      'holdings': [
        for (final h in holdings)
          {
            'ts_code': h.symbol,
            'symbol': h.symbol,
            'name': h.name,
            'industry': h.sector,
            'quantity': _round2(h.quantity),
            'avg_cost': _round2(h.avgBuyPrice),
            'current_price': _round2(h.currentPrice ?? h.avgBuyPrice),
            'market_value': _round2(h.marketValue),
            'pnl': _round2(h.unrealizedPnl),
            'pnl_pct': _round2(h.unrealizedPnlPercent),
            'weight_pct': mv == 0 ? 0.0 : _round2(h.marketValue / mv * 100.0),
            'day_change_pct': _round2(h.dayChangePercent ?? 0),
          },
      ],
    };
  }
}

double _round2(double v) {
  if (v.isNaN || v.isInfinite) return 0;
  return (v * 100).roundToDouble() / 100;
}
