import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/china_market.dart';
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

  /// 截图导入：把 vision 解析出来的 holdings 列表批量写入当前组合。
  ///
  /// 每条记录走 [addAsset]（落 buy 交易），跟手动一条条添加同结构，
  /// 避免引入新的写入路径影响行情聚合 / 报告 / 优化等下游使用。
  ///
  /// 入参 [rows] 是 UI 层确认对话框最终修正过的明细：
  ///  - code/name/quantity/avgCost 都已校验非空非负；
  ///  - market 用于推断 ts_code 后缀（无后缀时按 ChinaMarket 默认规则）。
  ///
  /// 返回成功导入的行数。
  Future<int> importParsedHoldings(
      List<({
        String code,
        String name,
        String market,
        double quantity,
        double avgCost,
      })> rows) async {
    final id = _activeId;
    if (id == null) return 0;
    var ok = 0;
    for (final r in rows) {
      if (r.quantity <= 0 || r.avgCost <= 0) continue;
      final tsCode = ChinaMarket.normalizeSymbol(r.code);
      if (tsCode.isEmpty) continue;
      final assetClass = ChinaMarket.assetClassOf(tsCode);
      final ins = Instrument(
        tsCode: tsCode,
        displaySymbol: ChinaMarket.displaySymbol(tsCode),
        name: r.name,
        exchange: ChinaMarket.exchangeOf(tsCode),
        assetClass: assetClass,
      );
      await _repo.addAsset(
        portfolioId: id,
        instrument: ins,
        quantity: r.quantity,
        price: r.avgCost,
      );
      ok++;
    }
    _rebuildSummary();
    notifyListeners();
    if (ok > 0) {
      // ignore: unawaited_futures
      refreshQuotes();
    }
    return ok;
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
    _invalidateHistories();
    _rebuildSummary();
    notifyListeners();
  }

  // ── Corporate actions ───────────────────────────────────────────────────

  Future<void> recordDividend({
    required String symbol,
    required double quantity,
    required double dividendPerShare,
    DateTime? date,
    String name = '',
    String sector = '',
    String assetClass = '',
    String notes = '',
  }) async {
    final id = _activeId;
    if (id == null) return;
    await _repo.recordDividend(
      portfolioId: id,
      symbol: symbol,
      quantity: quantity,
      dividendPerShare: dividendPerShare,
      date: date,
      name: name,
      sector: sector,
      assetClass: assetClass,
      notes: notes,
    );
    notifyListeners();
  }

  Future<void> recordSplit({
    required String symbol,
    required double ratio,
    DateTime? date,
    String name = '',
    String sector = '',
    String assetClass = '',
    String notes = '',
  }) async {
    final id = _activeId;
    if (id == null) return;
    await _repo.recordSplit(
      portfolioId: id,
      symbol: symbol,
      ratio: ratio,
      date: date,
      name: name,
      sector: sector,
      assetClass: assetClass,
      notes: notes,
    );
    _invalidateHistories();
    _rebuildSummary();
    notifyListeners();
  }

  // ── CSV import ──────────────────────────────────────────────────────────

  /// 解析并导入交易 CSV。规范字段（首行为表头，大小写不敏感）：
  ///   date,symbol,name,sector,asset_class,type,quantity,price,notes
  /// 其中：
  ///   - date 格式 YYYY-MM-DD 或 YYYY/MM/DD（不强制）
  ///   - type ∈ { buy, sell, dividend, split }
  ///   - split 时 quantity 表示拆分比例（>1 表示 1 拆 N），price 可为 0
  ///   - dividend 时 quantity 表示当时持仓数，price 表示每股分红
  ///
  /// 返回 (importedCount, errors)。
  Future<({int imported, List<String> errors})> importTransactionsCsv(
      String csvContent) async {
    final id = _activeId;
    if (id == null) {
      return (imported: 0, errors: ['当前没有选中的组合']);
    }
    final rows =
        Csv(skipEmptyLines: true, dynamicTyping: false, lineDelimiter: '\n')
            .decode(csvContent.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return (imported: 0, errors: ['CSV 为空']);
    // 自动识别表头
    final headerCandidates = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    final hasHeader = headerCandidates.contains('symbol') ||
        headerCandidates.contains('代码') ||
        headerCandidates.contains('ts_code');
    final List<String> header = hasHeader
        ? headerCandidates
        : ['date', 'symbol', 'name', 'sector', 'asset_class', 'type', 'quantity', 'price', 'notes'];
    final dataRows = hasHeader ? rows.sublist(1) : rows;

    int idx(String key, [String? alt]) {
      final i = header.indexOf(key);
      if (i >= 0) return i;
      if (alt != null) return header.indexOf(alt);
      return -1;
    }

    final iDate = idx('date', '日期');
    final iSym = idx('symbol', '代码');
    final iName = idx('name', '名称');
    final iSec = idx('sector', '行业');
    final iCls = idx('asset_class', '类别');
    final iType = idx('type', '操作');
    final iQty = idx('quantity', '数量');
    final iPrice = idx('price', '价格');
    final iNotes = idx('notes', '备注');

    final errors = <String>[];
    var imported = 0;
    for (var r = 0; r < dataRows.length; r++) {
      final row = dataRows[r];
      String at(int i) => (i >= 0 && i < row.length) ? row[i].toString().trim() : '';
      final symbol = at(iSym);
      final type = at(iType).toLowerCase();
      final qty = double.tryParse(at(iQty));
      final price = double.tryParse(at(iPrice));
      if (symbol.isEmpty) {
        errors.add('行 ${r + 1}：缺少 symbol');
        continue;
      }
      if (qty == null || qty <= 0) {
        errors.add('行 ${r + 1}：quantity 无效');
        continue;
      }
      if (!{'buy', 'sell', 'dividend', 'split'}.contains(type)) {
        errors.add('行 ${r + 1}：不支持的 type=$type');
        continue;
      }
      if ((type == 'buy' || type == 'sell') &&
          (price == null || price <= 0)) {
        errors.add('行 ${r + 1}：price 无效');
        continue;
      }
      DateTime? date;
      final raw = at(iDate);
      if (raw.isNotEmpty) {
        date = DateTime.tryParse(raw.replaceAll('/', '-'));
      }
      final txn = PortfolioTransaction(
        portfolioId: id,
        symbol: symbol,
        name: at(iName),
        sector: at(iSec),
        assetClass: at(iCls),
        type: type,
        quantity: qty,
        price: price ?? 0,
        date: date,
        notes: at(iNotes),
      );
      await _repo.addRawTransaction(txn);
      imported++;
    }
    if (imported > 0) {
      _invalidateHistories();
      _rebuildSummary();
      notifyListeners();
    }
    return (imported: imported, errors: errors);
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

  // ── Histories cache (shared across tabs) ────────────────────────────────
  // 多个 tab 都需要每只持仓的日线序列；这里做一层内存缓存：
  // - key = "<portfolioId>|<days>"，避免不同窗口/不同组合互相覆盖
  // - 只要持仓不变 + 窗口不变就直接返回，跨 tab 复用
  final Map<String, Future<Map<String, List<CandlePoint>>>>
      _histoCache = {};
  String? _histoCacheStamp; // 持仓签名变化时使整个缓存失效

  String _holdingsStamp(PortfolioSummary s) {
    final symbols = s.holdings.map((h) => h.symbol).toList()..sort();
    return symbols.join(',');
  }

  void _invalidateHistories() {
    _histoCache.clear();
    _histoCacheStamp = null;
  }

  /// 拉取每只持仓的日线序列（共享缓存）。
  /// [days] 是窗口大小；不同 tab 用不同窗口都各自缓存。
  Future<Map<String, List<CandlePoint>>> ensureHistories(
      {int days = 252}) async {
    final s = _summary;
    if (s == null || s.holdings.isEmpty) return const {};
    final stamp = _holdingsStamp(s);
    if (_histoCacheStamp != stamp) {
      _invalidateHistories();
      _histoCacheStamp = stamp;
    }
    final id = _activeId ?? '_';
    final key = '$id|$days';
    final cached = _histoCache[key];
    if (cached != null) return cached;

    final fut = () async {
      final out = <String, List<CandlePoint>>{};
      final start = DateTime.now().subtract(Duration(days: days + 14));
      for (final h in s.holdings) {
        try {
          out[h.symbol] = await _tushare.historyFor(
            h.symbol,
            start: start,
            end: DateTime.now(),
          );
        } catch (_) {
          out[h.symbol] = const [];
        }
      }
      return out;
    }();
    _histoCache[key] = fut;
    return fut;
  }

  // ── Performance series (active portfolio NAV proxy) ─────────────────────
  List<DateTime> _datesForRange({int days = 90}) {
    return [
      for (int i = days; i >= 0; i--)
        DateTime.now().subtract(Duration(days: i)),
    ];
  }

  Future<List<MapEntry<DateTime, double>>> performanceSeries(
      {int days = 90}) async {
    final s = _summary;
    if (s == null || s.holdings.isEmpty) return const [];
    final histories = await ensureHistories(days: days);
    final out = <DateTime, double>{};
    final dates = _datesForRange(days: days);
    for (final d in dates) {
      double v = 0;
      for (final h in s.holdings) {
        final cs = histories[h.symbol] ?? const [];
        // 找到 <= d 的最近一根 K 线
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

  /// 拉取一个外部基准（指数/ETF）的日线序列，与 NAV 序列同口径。
  Future<List<CandlePoint>> benchmarkSeries({
    String tsCode = '000300.SH',
    int days = 252,
  }) async {
    try {
      return await _tushare.historyFor(
        tsCode,
        start: DateTime.now().subtract(Duration(days: days + 14)),
        end: DateTime.now(),
      );
    } catch (_) {
      return const [];
    }
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
