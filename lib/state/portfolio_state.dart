import 'package:flutter/foundation.dart';

import '../models/instrument.dart';
import '../models/portfolio.dart';
import '../services/portfolio_repository.dart';
import '../services/tushare_service.dart';

/// Holds the active portfolio + cached live quotes. The screen layer reads
/// `currentSummary` and rebuilds whenever this notifier fires.
class PortfolioState extends ChangeNotifier {
  PortfolioState({
    PortfolioRepository? repo,
    TushareService? tushare,
  })  : _repo = repo ?? PortfolioRepository(),
        _tushare = tushare ?? TushareService();

  final PortfolioRepository _repo;
  final TushareService _tushare;

  // ── Lifecycle ──────────────────────────────────────────────────────────
  bool _ready = false;
  bool get ready => _ready;

  Future<void> bootstrap() async {
    _portfolios = _repo.allPortfolios();
    if (_portfolios.isNotEmpty && _activeId == null) {
      _activeId = _portfolios.first.id;
    }
    _rebuildSummary();
    _ready = true;
    notifyListeners();
    if (_active != null) {
      // Fire & forget — the user can keep browsing while quotes arrive.
      // ignore: unawaited_futures
      refreshQuotes();
    }
  }

  // ── Selection ──────────────────────────────────────────────────────────
  List<Portfolio> _portfolios = const [];
  String? _activeId;
  PortfolioSummary? _summary;
  String? _quoteError;
  bool _loadingQuotes = false;

  List<Portfolio> get portfolios => List.unmodifiable(_portfolios);
  String? get activeId => _activeId;
  Portfolio? get _active =>
      _activeId == null ? null : portfoliosForId(_activeId!);
  PortfolioSummary? get currentSummary => _summary;
  String? get quoteError => _quoteError;
  bool get loadingQuotes => _loadingQuotes;

  Portfolio? portfoliosForId(String id) {
    for (final p in _portfolios) {
      if (p.id == id) return p;
    }
    return null;
  }

  void selectPortfolio(String id) {
    if (_activeId == id) return;
    _activeId = id;
    _rebuildSummary();
    notifyListeners();
    // ignore: unawaited_futures
    refreshQuotes();
  }

  // ── CRUD ────────────────────────────────────────────────────────────────
  Future<void> createPortfolio({
    required String name,
    String currency = 'CNY',
    String owner = '本地用户',
  }) async {
    final p = await _repo.create(
        name: name, currency: currency, owner: owner);
    _portfolios = _repo.allPortfolios();
    _activeId = p.id;
    _rebuildSummary();
    notifyListeners();
  }

  Future<void> deletePortfolio(String id) async {
    await _repo.delete(id);
    _portfolios = _repo.allPortfolios();
    if (_activeId == id) {
      _activeId = _portfolios.isEmpty ? null : _portfolios.first.id;
    }
    _rebuildSummary();
    notifyListeners();
  }

  // ── Asset operations ────────────────────────────────────────────────────
  Future<void> addAsset({
    required Instrument instrument,
    required double quantity,
    required double price,
  }) async {
    final id = _activeId;
    if (id == null) return;
    await _repo.addAsset(
      portfolioId: id,
      instrument: instrument,
      quantity: quantity,
      price: price,
    );
    _rebuildSummary();
    notifyListeners();
    // ignore: unawaited_futures
    refreshQuotes();
  }

  Future<void> sellAsset({
    required PortfolioAsset asset,
    required double quantity,
    required double price,
  }) async {
    final id = _activeId;
    if (id == null) return;
    await _repo.sellAsset(
      portfolioId: id,
      symbol: asset.symbol,
      quantity: quantity,
      price: price,
      name: asset.name,
      sector: asset.sector,
      assetClass: asset.assetClass,
    );
    _rebuildSummary();
    notifyListeners();
    // ignore: unawaited_futures
    refreshQuotes();
  }

  Future<void> deleteTransaction(String txnId) async {
    await _repo.deleteTransaction(txnId);
    _rebuildSummary();
    notifyListeners();
  }

  List<PortfolioTransaction> currentTransactions() {
    final id = _activeId;
    if (id == null) return const [];
    return _repo.transactionsFor(id);
  }

  // ── Live quotes ─────────────────────────────────────────────────────────
  Future<void> refreshQuotes() async {
    final summary = _summary;
    if (summary == null || summary.holdings.isEmpty) return;
    _loadingQuotes = true;
    _quoteError = null;
    notifyListeners();

    try {
      final updated = <PortfolioAsset>[];
      for (final h in summary.holdings) {
        try {
          final candles = await _tushare.historyFor(
            h.symbol,
            start: DateTime.now().subtract(const Duration(days: 14)),
            end: DateTime.now(),
          );
          if (candles.isEmpty) {
            updated.add(h);
          } else {
            final last = candles.last;
            updated.add(h.copyWith(
              currentPrice: last.close,
              dayChangePercent: last.pctChg,
            ));
          }
        } catch (e) {
          // Per-symbol failure shouldn't kill the whole refresh.
          updated.add(h);
          _quoteError ??= e.toString();
        }
      }
      _summary = PortfolioSummary(
        portfolio: summary.portfolio,
        holdings: updated,
      );
    } catch (e) {
      _quoteError = e.toString();
    } finally {
      _loadingQuotes = false;
      notifyListeners();
    }
  }

  // ── Performance series (active portfolio NAV proxy) ─────────────────────
  Future<List<DateTime>> _datesForRange({int days = 90}) async {
    return [
      for (int i = days; i >= 0; i--)
        DateTime.now().subtract(Duration(days: i)),
    ];
  }

  Future<List<MapEntry<DateTime, double>>> performanceSeries(
      {int days = 90}) async {
    final s = _summary;
    if (s == null || s.holdings.isEmpty) return const [];
    final histories = <String, List<CandlePoint>>{};
    final start = DateTime.now().subtract(Duration(days: days + 14));
    for (final h in s.holdings) {
      try {
        final cs = await _tushare.historyFor(h.symbol,
            start: start, end: DateTime.now());
        histories[h.symbol] = cs;
      } catch (_) {}
    }
    final out = <DateTime, double>{};
    final dates = await _datesForRange(days: days);
    for (final d in dates) {
      double v = 0;
      for (final h in s.holdings) {
        final cs = histories[h.symbol] ?? const [];
        // closest <= d
        double? c;
        for (final p in cs) {
          if (!p.date.isAfter(d)) c = p.close;
          if (p.date.isAfter(d)) break;
        }
        if (c != null) v += c * h.quantity;
      }
      if (v > 0) out[DateTime(d.year, d.month, d.day)] = v;
    }
    final entries = out.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  void _rebuildSummary() {
    final p = _active;
    if (p == null) {
      _summary = null;
      return;
    }
    final holdings = _repo.holdingsFor(p.id);
    // Carry-over previous quotes if symbols still match.
    if (_summary != null) {
      final prev = {for (final h in _summary!.holdings) h.symbol: h};
      final next = [
        for (final h in holdings)
          h.copyWith(
            currentPrice: prev[h.symbol]?.currentPrice,
            dayChangePercent: prev[h.symbol]?.dayChangePercent,
          ),
      ];
      _summary = PortfolioSummary(portfolio: p, holdings: next);
    } else {
      _summary = PortfolioSummary(portfolio: p, holdings: holdings);
    }
  }
}
