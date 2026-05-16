import 'dart:convert';

import '../../core/utils/china_market.dart';
import '../../models/instrument.dart';
import '../tushare_service.dart';
import '../ai_tools.dart';

/// 共享 Tushare 服务实例，避免每个工具自建 Dio。
class TushareToolsContext {
  TushareToolsContext({required this.svc});
  final TushareService svc;

  // 内存级缓存——单次会话内复用，避免反复全表拉取
  List<Instrument>? _stocks;
  List<Instrument>? _etfs;
  List<Instrument>? _indexes;
  List<Instrument>? _futures;

  Future<List<Instrument>> stocks() async {
    return _stocks ??= await svc.stockBasic();
  }

  Future<List<Instrument>> etfs() async {
    return _etfs ??= await svc.fundBasic(market: 'E');
  }

  Future<List<Instrument>> indexes() async {
    return _indexes ??= await svc.indexBasic();
  }

  /// 期货 basic 按交易所分散，一次性合并 4 个最常用交易所
  Future<List<Instrument>> futures() async {
    if (_futures != null) return _futures!;
    final out = <Instrument>[];
    for (final ex in const ['CFFEX', 'SHFE', 'DCE', 'CZCE']) {
      try {
        out.addAll(await svc.futBasic(exchange: ex));
      } catch (_) {
        // 某个交易所不通不影响其他
      }
    }
    _futures = out;
    return out;
  }
}

/// 工具 1：在 Tushare 全市场基础列表里关键字搜索（股票 / ETF / 指数 / 期货）
class SearchInstrumentTool extends AiTool {
  SearchInstrumentTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'search_instrument';

  @override
  String get description =>
      '按关键字（中文名 / 代码 / 行业关键字）在 A 股、ETF、指数、期货全集里搜索标的，'
      '返回 ts_code、名称、所属类别、行业。当用户提到"茅台"、"军工 ETF"、"沪深 300"等模糊'
      '描述时使用。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'query': {
            'type': 'string',
            'description': '搜索关键字，可以是中文名、代码片段、或行业关键字（"白酒"、"半导体"等）',
          },
          'asset_class': {
            'type': 'string',
            'enum': ['stock', 'etf', 'index', 'futures', 'all'],
            'description': '限定资产类别（默认 all 全市场搜索）',
          },
          'limit': {
            'type': 'integer',
            'description': '返回前 N 条匹配（默认 8，最大 20）',
          },
        },
        required: ['query'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final q = (args['query'] as String? ?? '').trim();
    if (q.isEmpty) {
      return jsonEncode({'error': '查询关键字不能为空'});
    }
    final assetClass = (args['asset_class'] as String? ?? 'all').toLowerCase();
    final limit = (args['limit'] as num?)?.toInt().clamp(1, 20) ?? 8;

    final pools = <List<Instrument>>[];
    if (assetClass == 'all' || assetClass == 'stock') {
      pools.add(await _ctx.stocks());
    }
    if (assetClass == 'all' || assetClass == 'etf') {
      pools.add(await _ctx.etfs());
    }
    if (assetClass == 'all' || assetClass == 'index') {
      pools.add(await _ctx.indexes());
    }
    if (assetClass == 'all' || assetClass == 'futures') {
      pools.add(await _ctx.futures());
    }

    final qLower = q.toLowerCase();
    final hits = <Map<String, dynamic>>[];
    for (final pool in pools) {
      for (final ins in pool) {
        final fields = [ins.name, ins.tsCode, ins.displaySymbol, ins.industry]
            .map((e) => e.toLowerCase())
            .toList();
        if (fields.any((f) => f.contains(qLower))) {
          hits.add({
            'ts_code': ins.tsCode,
            'name': ins.name,
            'asset': ins.assetClass,
            'industry': ins.industry,
            if (ins.exchange.isNotEmpty) 'exchange': ins.exchange,
          });
          if (hits.length >= limit) break;
        }
      }
      if (hits.length >= limit) break;
    }

    return jsonEncode({
      'query': q,
      'count': hits.length,
      'matches': hits,
    });
  }
}

/// 工具 2：拿单一标的的最近 N 天日线行情（含涨跌幅、成交量）
class GetQuoteTool extends AiTool {
  GetQuoteTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_quote';

  @override
  String get description =>
      '查询单只 A 股 / ETF / 指数 / 期货最近 N 个交易日的日线行情，'
      '返回收盘价、涨跌幅、成交量序列以及汇总（最新价、区间最高/最低、累计涨跌幅）。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {
            'type': 'string',
            'description':
                '标的代码：可以是 6 位数字（如 600519、159949）或 ts_code 全码（如 600519.SH、IF2412.CFE）',
          },
          'days': {
            'type': 'integer',
            'description': '返回最近多少个交易日（默认 20，最大 120）',
          },
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final raw = (args['symbol'] as String? ?? '').trim();
    if (raw.isEmpty) {
      return jsonEncode({'error': 'symbol 必填'});
    }
    final code = ChinaMarket.normalizeSymbol(raw);
    final days = ((args['days'] as num?)?.toInt() ?? 20).clamp(1, 120);

    final end = DateTime.now();
    // 拉 days*2 天确保留有足够交易日（剔除周末/节假日）
    final start = end.subtract(Duration(days: days * 2 + 30));
    final candles = await _ctx.svc.historyFor(code, start: start, end: end);
    if (candles.isEmpty) {
      return jsonEncode({
        'symbol': code,
        'asset': ChinaMarket.assetClassOf(code),
        'error': '未拉到任何行情（代码可能错误或非交易日）',
      });
    }
    final tail = candles.length > days
        ? candles.sublist(candles.length - days)
        : candles;
    final first = tail.first;
    final last = tail.last;
    final periodPctChg = first.close == 0
        ? 0.0
        : ((last.close - first.close) / first.close) * 100.0;

    final highest = tail.fold<double>(
        double.negativeInfinity, (a, b) => b.high == null ? a : (b.high! > a ? b.high! : a));
    final lowest = tail.fold<double>(
        double.infinity, (a, b) => b.low == null ? a : (b.low! < a ? b.low! : a));

    return jsonEncode({
      'symbol': code,
      'asset': ChinaMarket.assetClassOf(code),
      'exchange': ChinaMarket.exchangeOf(code),
      'days': tail.length,
      'period_start': _ymd(first.date),
      'period_end': _ymd(last.date),
      'last_close': last.close,
      'last_pct_chg': last.pctChg,
      'period_pct_chg': double.parse(periodPctChg.toStringAsFixed(3)),
      'period_high': highest.isFinite ? highest : null,
      'period_low': lowest.isFinite ? lowest : null,
      'series': [
        for (final c in tail)
          {
            'date': _ymd(c.date),
            'close': c.close,
            'pct_chg': c.pctChg,
          },
      ],
    });
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 工具 3：横向比较多个标的最近表现（仅汇总，不返回时间序列以省 token）
class CompareQuotesTool extends AiTool {
  CompareQuotesTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'compare_quotes';

  @override
  String get description =>
      '一次性比较多个标的（最多 6 个）最近 N 天的累计涨跌幅、最新价、区间最高最低，'
      '用于"600519、000858、300750 哪个涨得快""沪深 300 vs 中证 500"等横向对比问题。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbols': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标的代码数组，6 位数字或 ts_code 都可以',
          },
          'days': {
            'type': 'integer',
            'description': '比较窗口（默认 30 个交易日）',
          },
        },
        required: ['symbols'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final symbols = (args['symbols'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    if (symbols.isEmpty) {
      return jsonEncode({'error': 'symbols 不能为空'});
    }
    if (symbols.length > 6) {
      return jsonEncode({'error': '一次最多比较 6 个标的，请拆分多次调用'});
    }
    final days = ((args['days'] as num?)?.toInt() ?? 30).clamp(1, 120);
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days * 2 + 30));

    final out = <Map<String, dynamic>>[];
    for (final raw in symbols) {
      final code = ChinaMarket.normalizeSymbol(raw);
      try {
        final candles =
            await _ctx.svc.historyFor(code, start: start, end: end);
        if (candles.isEmpty) {
          out.add({'symbol': code, 'error': '未拉到行情'});
          continue;
        }
        final tail =
            candles.length > days ? candles.sublist(candles.length - days) : candles;
        final first = tail.first;
        final last = tail.last;
        final pct = first.close == 0
            ? 0.0
            : ((last.close - first.close) / first.close) * 100.0;
        out.add({
          'symbol': code,
          'asset': ChinaMarket.assetClassOf(code),
          'days': tail.length,
          'last_close': last.close,
          'period_pct_chg': double.parse(pct.toStringAsFixed(3)),
          'last_date': GetQuoteTool._ymd(last.date),
        });
      } catch (e) {
        out.add({'symbol': code, 'error': e.toString()});
      }
    }
    out.sort((a, b) {
      final pa = (a['period_pct_chg'] as num?) ?? -1e9;
      final pb = (b['period_pct_chg'] as num?) ?? -1e9;
      return pb.compareTo(pa);
    });
    return jsonEncode({
      'days': days,
      'ranked_by_period_pct_chg': out,
    });
  }
}

/// 工具 4：列出某行业的成分股（基于 stock_basic 的 industry 字段过滤）
class ListIndustryStocksTool extends AiTool {
  ListIndustryStocksTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'list_industry_stocks';

  @override
  String get description =>
      '按行业关键字列出 A 股个股（如"白酒"、"半导体"、"光伏"、"军工"等）。'
      '返回该行业内的股票代码与名称，便于后续逐个调用 get_quote 或 compare_quotes 进行行情比较。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'industry_keyword': {
            'type': 'string',
            'description': '行业关键字，会模糊匹配 Tushare 的 industry 字段',
          },
          'limit': {
            'type': 'integer',
            'description': '返回前 N 只（默认 20，最大 60）',
          },
        },
        required: ['industry_keyword'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final kw = (args['industry_keyword'] as String? ?? '').trim();
    if (kw.isEmpty) {
      return jsonEncode({'error': 'industry_keyword 必填'});
    }
    final limit = (args['limit'] as num?)?.toInt().clamp(1, 60) ?? 20;
    final stocks = await _ctx.stocks();
    final hits = <Map<String, dynamic>>[];
    final kwLower = kw.toLowerCase();
    for (final s in stocks) {
      if (s.industry.toLowerCase().contains(kwLower)) {
        hits.add({
          'ts_code': s.tsCode,
          'name': s.name,
          'industry': s.industry,
          if (s.area.isNotEmpty) 'area': s.area,
        });
        if (hits.length >= limit) break;
      }
    }
    return jsonEncode({
      'industry_keyword': kw,
      'count': hits.length,
      'stocks': hits,
    });
  }
}

/// 工具 5：拉主要 A 股市场指数当前快照（沪深 300、上证 50、中证 500、科创 50、创业板）
class GetMarketSnapshotTool extends AiTool {
  GetMarketSnapshotTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_market_snapshot';

  @override
  String get description =>
      '获取 A 股主要指数（沪深 300、上证 50、中证 500、科创 50、创业板指）的最新行情快照，'
      '用于回答"今天大盘怎么样""科创 50 涨了多少"等市场总览问题。';

  @override
  ToolParameterSchema get parameters =>
      const ToolParameterSchema(properties: {}, required: []);

  static const _indexes = <Map<String, String>>[
    {'code': '000300.SH', 'name': '沪深300'},
    {'code': '000016.SH', 'name': '上证50'},
    {'code': '000905.SH', 'name': '中证500'},
    {'code': '000688.SH', 'name': '科创50'},
    {'code': '399006.SZ', 'name': '创业板指'},
  ];

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 30));
    final results = <Map<String, dynamic>>[];
    for (final ix in _indexes) {
      try {
        final candles =
            await _ctx.svc.indexDaily(tsCode: ix['code']!, startDate: _fmt(start), endDate: _fmt(end));
        if (candles.isEmpty) {
          results.add({'name': ix['name'], 'error': '无行情'});
          continue;
        }
        final last = candles.last;
        results.add({
          'name': ix['name'],
          'code': ix['code'],
          'last_date': GetQuoteTool._ymd(last.date),
          'last_close': last.close,
          'last_pct_chg': last.pctChg,
        });
      } catch (e) {
        results.add({'name': ix['name'], 'error': e.toString()});
      }
    }
    return jsonEncode({'indexes': results});
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 工具 6：在 ETF 全集里按主题/规模筛选（基金类型 + 名称关键字）
class ListEtfsByThemeTool extends AiTool {
  ListEtfsByThemeTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'list_etfs_by_theme';

  @override
  String get description =>
      '按主题/类型关键字筛选场内 ETF（如"科创"、"医疗"、"红利"、"债券"等）。'
      '返回 ETF 代码、名称、基金类型、管理人，可后续调用 get_quote 看其表现。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'theme_keyword': {
            'type': 'string',
            'description': '主题/类型关键字，匹配 ETF 名称或基金类型',
          },
          'limit': {
            'type': 'integer',
            'description': '返回前 N 只（默认 15，最大 40）',
          },
        },
        required: ['theme_keyword'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final kw = (args['theme_keyword'] as String? ?? '').trim();
    if (kw.isEmpty) {
      return jsonEncode({'error': 'theme_keyword 必填'});
    }
    final limit = (args['limit'] as num?)?.toInt().clamp(1, 40) ?? 15;
    final etfs = await _ctx.etfs();
    final kwLower = kw.toLowerCase();
    final hits = <Map<String, dynamic>>[];
    for (final f in etfs) {
      if (f.name.toLowerCase().contains(kwLower) ||
          f.industry.toLowerCase().contains(kwLower) ||
          f.area.toLowerCase().contains(kwLower)) {
        hits.add({
          'ts_code': f.tsCode,
          'name': f.name,
          if (f.industry.isNotEmpty) 'fund_type': f.industry,
          if (f.area.isNotEmpty) 'manager': f.area,
        });
        if (hits.length >= limit) break;
      }
    }
    return jsonEncode({
      'theme_keyword': kw,
      'count': hits.length,
      'etfs': hits,
    });
  }
}

/// 构建一组 Tushare 基础工具（搜索 / 行情 / 对比 / 行业 / 大盘 / ETF）
List<AiTool> buildBaseTushareTools(TushareToolsContext ctx) => [
      SearchInstrumentTool(ctx),
      GetQuoteTool(ctx),
      CompareQuotesTool(ctx),
      ListIndustryStocksTool(ctx),
      GetMarketSnapshotTool(ctx),
      ListEtfsByThemeTool(ctx),
    ];
