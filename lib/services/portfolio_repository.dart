import '../core/storage/hive_setup.dart';
import '../core/utils/china_market.dart';
import '../models/instrument.dart';
import '../models/portfolio.dart';

/// Hive-backed portfolio repository. Mirrors the responsibilities of
/// `services::PortfolioService` from the Qt project: portfolio CRUD,
/// transaction logging, and asset aggregation from the transaction ledger.
class PortfolioRepository {
  List<Portfolio> allPortfolios() => portfoliosBox.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<Portfolio> create({
    required String name,
    String currency = 'CNY',
    String owner = '本地用户',
    String description = '',
  }) async {
    final p = Portfolio(
      name: name,
      currency: currency,
      owner: owner,
      description: description,
    );
    await portfoliosBox.put(p.id, p);
    return p;
  }

  Future<void> delete(String id) async {
    await portfoliosBox.delete(id);
    final txKeys = transactionsBox.values
        .where((t) => t.portfolioId == id)
        .map((t) => t.key)
        .toList();
    await transactionsBox.deleteAll(txKeys);
  }

  // ── Asset operations ────────────────────────────────────────────────────

  Future<PortfolioTransaction> addAsset({
    required String portfolioId,
    required Instrument instrument,
    required double quantity,
    required double price,
    DateTime? date,
    String notes = '',
  }) async {
    final txn = PortfolioTransaction(
      portfolioId: portfolioId,
      symbol: ChinaMarket.normalizeSymbol(instrument.tsCode),
      name: instrument.name,
      sector: instrument.industry,
      assetClass: instrument.assetClass,
      type: 'buy',
      quantity: quantity,
      price: price,
      date: date,
      notes: notes,
    );
    await transactionsBox.add(txn);
    final p = portfoliosBox.get(portfolioId);
    if (p != null) {
      p.updatedAt = DateTime.now();
      await p.save();
    }
    return txn;
  }

  Future<PortfolioTransaction> sellAsset({
    required String portfolioId,
    required String symbol,
    required double quantity,
    required double price,
    DateTime? date,
    String notes = '',
    String name = '',
    String sector = '',
    String assetClass = '',
  }) async {
    final txn = PortfolioTransaction(
      portfolioId: portfolioId,
      symbol: symbol,
      name: name,
      sector: sector,
      assetClass: assetClass,
      type: 'sell',
      quantity: quantity,
      price: price,
      date: date,
      notes: notes,
    );
    await transactionsBox.add(txn);
    return txn;
  }

  Future<void> deleteTransaction(String txnId) async {
    final entry = transactionsBox.values.firstWhere(
      (t) => t.id == txnId,
      orElse: () => throw StateError('transaction not found'),
    );
    await entry.delete();
  }

  // ── Aggregation ─────────────────────────────────────────────────────────

  List<PortfolioTransaction> transactionsFor(String portfolioId) {
    return transactionsBox.values
        .where((t) => t.portfolioId == portfolioId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Aggregates buys / sells into the current holdings list. Average price
  /// uses the running buy-cost basis (no FIFO/LIFO sophistication; we just
  /// add the buy lots and reduce the cost proportionally on sells).
  List<PortfolioAsset> holdingsFor(String portfolioId) {
    final txns = transactionsBox.values
        .where((t) => t.portfolioId == portfolioId)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final agg = <String, _Holding>{};
    for (final t in txns) {
      final h = agg.putIfAbsent(
        t.symbol,
        () => _Holding(
          symbol: t.symbol,
          name: t.name,
          sector: t.sector,
          assetClass: t.assetClass,
        ),
      );
      h.touch(t);
    }
    return agg.values
        .where((h) => h.qty > 1e-9)
        .map((h) => PortfolioAsset(
              symbol: h.symbol,
              name: h.name,
              sector: h.sector,
              assetClass: h.assetClass,
              quantity: h.qty,
              avgBuyPrice: h.qty == 0 ? 0 : h.cost / h.qty,
            ))
        .toList();
  }
}

class _Holding {
  _Holding({
    required this.symbol,
    required this.name,
    required this.sector,
    required this.assetClass,
  });
  final String symbol;
  String name;
  String sector;
  String assetClass;
  double qty = 0;
  double cost = 0;

  void touch(PortfolioTransaction t) {
    if (name.isEmpty && t.name.isNotEmpty) name = t.name;
    if (sector.isEmpty && t.sector.isNotEmpty) sector = t.sector;
    if (assetClass.isEmpty && t.assetClass.isNotEmpty) {
      assetClass = t.assetClass;
    }
    if (t.type == 'buy') {
      cost += t.quantity * t.price;
      qty += t.quantity;
    } else if (t.type == 'sell') {
      final avg = qty == 0 ? 0 : cost / qty;
      final reduce = t.quantity.clamp(0, qty).toDouble();
      cost -= reduce * avg;
      qty -= reduce;
      if (qty < 1e-9) {
        qty = 0;
        cost = 0;
      }
    }
  }
}
