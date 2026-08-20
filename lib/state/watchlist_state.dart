import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/hive_setup.dart' show prefsBox;
import '../models/instrument.dart';
import '../services/tushare_service.dart';

/// 一个自选（关注）品种的最小信息。
/// 只保留展示必需字段，持久化到 prefsBox（JSON 字符串）。
class WatchItem {
  const WatchItem({
    required this.tsCode,
    required this.name,
    required this.assetClass,
  });

  /// Tushare 规范代码，如 600519.SH / SR609.CZC
  final String tsCode;
  final String name;

  /// 股票 / ETF / 期货 / 指数
  final String assetClass;

  Map<String, dynamic> toJson() =>
      {'tsCode': tsCode, 'name': name, 'assetClass': assetClass};

  factory WatchItem.fromInstrument(Instrument ins) => WatchItem(
        tsCode: ins.tsCode,
        name: ins.name,
        assetClass: ins.assetClass,
      );

  factory WatchItem.fromJson(Map<String, dynamic> j) => WatchItem(
        tsCode: (j['tsCode'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        assetClass: (j['assetClass'] ?? '').toString(),
      );
}

/// 单只品种的最新行情快照（列表页展示用）。
class WatchQuote {
  const WatchQuote({required this.close, this.pctChg});
  final double close;
  final double? pctChg; // 日涨跌幅（%），无数据时为 null
}

/// 看盘自选列表状态：增删 / Hive 持久化 / 批量刷新最新价。
class WatchlistState extends ChangeNotifier {
  WatchlistState({TushareService? tushare})
      : _tushare = tushare ?? TushareService();

  final TushareService _tushare;
  static const _boxKey = 'watchlist';

  List<WatchItem> _items = const [];
  final Map<String, WatchQuote> _quotes = {};
  bool _loading = false;
  String? _error;

  List<WatchItem> get items => List.unmodifiable(_items);
  WatchQuote? quoteOf(String tsCode) => _quotes[tsCode];
  bool get loading => _loading;
  String? get error => _error;

  bool contains(String tsCode) => _items.any((i) => i.tsCode == tsCode);

  /// 启动时从 prefsBox 恢复自选，并后台静默刷新一次行情。
  Future<void> bootstrap() async {
    _loadFromBox();
    notifyListeners();
    // ignore: unawaited_futures
    refreshQuotes();
  }

  void _loadFromBox() {
    try {
      final raw = prefsBox.get(_boxKey);
      if (raw is! String || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      _items = [
        for (final e in list)
          if (e is Map) WatchItem.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      // 本地缓存损坏时静默丢弃，当作空列表处理。
      _items = const [];
    }
  }

  Future<void> _saveToBox() async {
    await prefsBox.put(
      _boxKey,
      jsonEncode([for (final i in _items) i.toJson()]),
    );
  }

  /// 添加品种（幂等：已在自选则忽略）。
  Future<void> add(Instrument ins) async {
    if (contains(ins.tsCode)) return;
    _items = [..._items, WatchItem.fromInstrument(ins)];
    await _saveToBox();
    notifyListeners();
    // 新品种立刻补拉一次行情，避免列表里显示 '--'。
    // ignore: unawaited_futures
    _refreshOne(ins.tsCode);
  }

  /// 移除品种。
  Future<void> remove(String tsCode) async {
    _items = [for (final i in _items) if (i.tsCode != tsCode) i];
    _quotes.remove(tsCode);
    await _saveToBox();
    notifyListeners();
  }

  /// 刷新全部自选的最新价（并行请求，单只失败不影响其它）。
  Future<void> refreshQuotes() async {
    if (_items.isEmpty) {
      _quotes.clear();
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    await Future.wait(
      [for (final i in _items) _refreshOne(i.tsCode, silent: true)],
    );
    _loading = false;
    notifyListeners();
  }

  /// 拉单只品种最近 14 天日线，取最后一根作为最新行情。
  Future<void> _refreshOne(String tsCode, {bool silent = false}) async {
    try {
      final candles = await _tushare.historyFor(
        tsCode,
        start: DateTime.now().subtract(const Duration(days: 14)),
        end: DateTime.now(),
      );
      if (candles.isEmpty) return;
      final last = candles.last;
      _quotes[tsCode] = WatchQuote(close: last.close, pctChg: last.pctChg);
    } catch (e) {
      // 单只失败只记录首个错误，整体刷新不中断。
      if (!silent) _error ??= e.toString();
    } finally {
      if (!silent) notifyListeners();
    }
  }
}
