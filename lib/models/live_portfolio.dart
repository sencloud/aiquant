import 'portfolio.dart';

/// 「组合管理」里系统托管的实盘组合（对应后端 GET /v1/portfolio/live）。
///
/// 后端每天把主策略（上证50 九因子）的实盘账户物化成：持仓 + 可回放的交易流水
/// + 现金/盈亏。客户端把它落成一个只读组合，十个 tab 都按真实持仓计算。
class LivePortfolio {
  const LivePortfolio({
    required this.id,
    required this.name,
    required this.description,
    required this.currency,
    required this.asOf,
    required this.inception,
    required this.stale,
    required this.staleDays,
    required this.capital,
    required this.cash,
    required this.marketValue,
    required this.total,
    required this.pnl,
    required this.pnlPct,
    required this.divergence,
    required this.reconciled,
    required this.holdings,
    required this.transactions,
    required this.signalDate,
    required this.execDate,
  });

  /// 管理来源标记，写在 [Portfolio.managedBy] 里。
  static const String managedBy = 'live_strategy';

  final String id;
  final String name;
  final String description;
  final String currency;
  final String asOf;
  final String inception;
  final bool stale;
  final int staleDays;
  final double capital;
  final double cash;
  final double marketValue;
  final double total;
  final double pnl;

  /// 小数（0.0108 = 1.08%）。
  final double pnlPct;
  final bool divergence;
  final bool reconciled;
  final List<LiveHolding> holdings;
  final List<LiveTxn> transactions;
  final String signalDate;
  final String execDate;

  factory LivePortfolio.fromJson(Map<String, dynamic> j) => LivePortfolio(
        id: _str(j['id']),
        name: _str(j['name']),
        description: _str(j['description']),
        currency: _str(j['currency']).isEmpty ? 'CNY' : _str(j['currency']),
        asOf: _str(j['as_of']),
        inception: _str(j['inception']),
        stale: j['stale'] == true,
        staleDays: _num(j['stale_days']).toInt(),
        capital: _num(j['capital']),
        cash: _num(j['cash']),
        marketValue: _num(j['market_value']),
        total: _num(j['total']),
        pnl: _num(j['pnl']),
        pnlPct: _num(j['pnl_pct']),
        divergence: j['divergence'] == true,
        reconciled: j['reconciled'] != false,
        holdings: [
          for (final h in (j['holdings'] as List? ?? const []))
            if (h is Map) LiveHolding.fromJson(h.cast<String, dynamic>()),
        ],
        transactions: [
          for (final t in (j['transactions'] as List? ?? const []))
            if (t is Map) LiveTxn.fromJson(t.cast<String, dynamic>()),
        ],
        signalDate: _str(j['signal_date']),
        execDate: _str(j['exec_date']),
      );

  /// 翻成本地账本：组合 id 固定（[id]），每次同步整体替换。
  List<PortfolioTransaction> toTransactions() => [
        for (final t in transactions)
          if (t.quantity > 0 &&
              t.symbol.isNotEmpty &&
              const {'buy', 'sell', 'dividend'}.contains(t.type))
            PortfolioTransaction(
              id: t.id.isEmpty ? null : t.id,
              portfolioId: id,
              symbol: t.symbol,
              name: t.name,
              sector: t.industry,
              assetClass: t.assetClass.isEmpty ? '股票' : t.assetClass,
              type: t.type,
              quantity: t.quantity,
              price: t.price,
              totalValue: t.type == 'dividend' && t.amount > 0
                  ? t.amount
                  : t.quantity * t.price,
              date: DateTime.tryParse(t.date) ?? DateTime.now(),
              notes: t.note,
            ),
      ];

  /// 后端给的「截至日收盘价」，在 tushare 行情回来之前先顶上。
  Map<String, double> get closePrices => {
        for (final h in holdings)
          if (h.price > 0) h.symbol: h.price,
      };
}

class LiveHolding {
  const LiveHolding({
    required this.symbol,
    required this.name,
    required this.industry,
    required this.shares,
    required this.avgCost,
    required this.price,
    required this.weight,
    required this.inTarget,
  });

  final String symbol;
  final String name;
  final String industry;
  final double shares;
  final double avgCost;
  final double price;
  final double weight;
  final bool inTarget;

  factory LiveHolding.fromJson(Map<String, dynamic> j) => LiveHolding(
        symbol: _str(j['symbol']),
        name: _str(j['name']),
        industry: _str(j['industry']),
        shares: _num(j['shares']),
        avgCost: _num(j['avg_cost']),
        price: _num(j['price']),
        weight: _num(j['weight']),
        inTarget: j['in_target'] == true,
      );
}

class LiveTxn {
  const LiveTxn({
    required this.id,
    required this.date,
    required this.type,
    required this.symbol,
    required this.name,
    required this.industry,
    required this.assetClass,
    required this.quantity,
    required this.price,
    required this.amount,
    required this.note,
  });

  final String id;
  final String date;
  final String type;
  final String symbol;
  final String name;
  final String industry;
  final String assetClass;
  final double quantity;
  final double price;
  final double amount;
  final String note;

  factory LiveTxn.fromJson(Map<String, dynamic> j) => LiveTxn(
        id: _str(j['id']),
        date: _str(j['date']),
        type: _str(j['type']),
        symbol: _str(j['symbol']),
        name: _str(j['name']),
        industry: _str(j['industry']),
        assetClass: _str(j['asset_class']),
        quantity: _num(j['quantity']),
        price: _num(j['price']),
        amount: _num(j['amount']),
        note: _str(j['note']),
      );
}

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

double _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
