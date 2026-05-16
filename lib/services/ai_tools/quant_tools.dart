import 'dart:convert';
import 'dart:math' as math;

import '../../core/utils/china_market.dart';
import '../../models/instrument.dart';
import '../indicators.dart';
import '../tushare_service.dart';
import '../ai_tools.dart';
import 'tushare_tools.dart';

/// 时间窗口工具：把"days"参数包装成 (start, end) 时间范围
({DateTime start, DateTime end}) _windowOfDays(int days) {
  final end = DateTime.now();
  final start = end.subtract(Duration(days: days * 2 + 30));
  return (start: start, end: end);
}

String _ymd(DateTime? d) {
  if (d == null) return '';
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Future<List<CandlePoint>> _loadSeries(
    TushareService svc, String code, int days) async {
  final w = _windowOfDays(days);
  final all = await svc.historyFor(code, start: w.start, end: w.end);
  if (all.length <= days) return all;
  return all.sublist(all.length - days);
}

/// 1. 收益率与波动汇总
class CalcReturnsTool extends AiTool {
  CalcReturnsTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_returns';
  @override
  String get description =>
      '计算单一标的最近 N 个交易日的累计收益率、年化收益率、年化波动率。'
      '回答"茅台过去一年涨了多少 / 波动多大"等问题时使用。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string', 'description': '标的代码（6位数字或 ts_code）'},
          'days': {'type': 'integer', 'description': '回看交易日数（默认 252，最大 750）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final days = ((args['days'] as num?)?.toInt() ?? 252).clamp(20, 750);
    final series = await _loadSeries(_ctx.svc, code, days);
    if (series.length < 5) {
      return jsonEncode({'symbol': code, 'error': '行情数据不足以计算（仅 ${series.length} 条）'});
    }
    return jsonEncode({
      'symbol': code,
      'period_start': _ymd(series.first.date),
      'period_end': _ymd(series.last.date),
      'observations': series.length,
      'cumulative_return_pct': double.parse(
          (Indicators.cumulativeReturn(series) * 100).toStringAsFixed(3)),
      'annualized_return_pct': double.parse(
          (Indicators.annualizedReturn(series) * 100).toStringAsFixed(3)),
      'annualized_volatility_pct': double.parse(
          (Indicators.annualizedVolatility(series) * 100).toStringAsFixed(3)),
    });
  }
}

/// 2. Sharpe 比率
class CalcSharpeTool extends AiTool {
  CalcSharpeTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_sharpe';
  @override
  String get description =>
      '计算单一标的的年化 Sharpe Ratio（默认无风险利率 2%）。'
      '用于回答"茅台值不值得买"、"风险调整后的回报"等问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string', 'description': '标的代码'},
          'days': {'type': 'integer', 'description': '回看交易日数（默认 252）'},
          'risk_free_rate': {
            'type': 'number',
            'description': '年化无风险利率（默认 0.02，可传 0.025 等）',
          },
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final days = ((args['days'] as num?)?.toInt() ?? 252).clamp(20, 750);
    final rf = (args['risk_free_rate'] as num?)?.toDouble() ?? 0.02;
    final series = await _loadSeries(_ctx.svc, code, days);
    if (series.length < 20) {
      return jsonEncode({'symbol': code, 'error': '样本不足以计算 Sharpe'});
    }
    final sharpe = Indicators.sharpeRatio(series, riskFree: rf);
    final ar = Indicators.annualizedReturn(series);
    final av = Indicators.annualizedVolatility(series);
    return jsonEncode({
      'symbol': code,
      'observations': series.length,
      'risk_free_rate': rf,
      'annualized_return_pct': double.parse((ar * 100).toStringAsFixed(3)),
      'annualized_volatility_pct': double.parse((av * 100).toStringAsFixed(3)),
      'sharpe_ratio': double.parse(sharpe.toStringAsFixed(3)),
    });
  }
}

/// 3. 最大回撤
class CalcMaxDrawdownTool extends AiTool {
  CalcMaxDrawdownTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_max_drawdown';
  @override
  String get description =>
      '计算单一标的回看期内的最大回撤（峰值到谷底的最大跌幅）和对应的峰值/谷底日期。'
      '用于评估"如果在最高点买入，最坏会亏多少"。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'days': {'type': 'integer', 'description': '回看交易日数（默认 252）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final days = ((args['days'] as num?)?.toInt() ?? 252).clamp(20, 1500);
    final series = await _loadSeries(_ctx.svc, code, days);
    if (series.length < 5) {
      return jsonEncode({'symbol': code, 'error': '样本不足'});
    }
    final r = Indicators.maxDrawdown(series);
    return jsonEncode({
      'symbol': code,
      'observations': series.length,
      'max_drawdown_pct':
          double.parse((r.drawdown * 100).toStringAsFixed(3)),
      'peak_date': _ymd(r.peakDate),
      'trough_date': _ymd(r.troughDate),
    });
  }
}

/// 4. 多标的相关性矩阵
class CalcCorrelationTool extends AiTool {
  CalcCorrelationTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_correlation';
  @override
  String get description =>
      '计算多个标的（最多 6 个）日收益率两两之间的 Pearson 相关系数，'
      '回答"沪深 300 和茅台相关性""哪些行业是分散化好搭档"等问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbols': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '2~6 个标的代码',
          },
          'days': {'type': 'integer', 'description': '回看交易日数（默认 120）'},
        },
        required: ['symbols'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final symbols = (args['symbols'] as List?)
            ?.map((e) => ChinaMarket.normalizeSymbol(e.toString().trim()))
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    if (symbols.length < 2) {
      return jsonEncode({'error': '至少 2 个标的'});
    }
    if (symbols.length > 6) {
      return jsonEncode({'error': '最多 6 个标的'});
    }
    final days = ((args['days'] as num?)?.toInt() ?? 120).clamp(20, 500);

    final allSeries = <String, List<CandlePoint>>{};
    for (final s in symbols) {
      try {
        allSeries[s] = await _loadSeries(_ctx.svc, s, days);
      } catch (_) {
        allSeries[s] = const [];
      }
    }
    final matrix = <String, Map<String, double>>{};
    for (final a in symbols) {
      matrix[a] = {};
      for (final b in symbols) {
        if (a == b) {
          matrix[a]![b] = 1;
          continue;
        }
        if (allSeries[a]!.isEmpty || allSeries[b]!.isEmpty) {
          matrix[a]![b] = 0;
          continue;
        }
        final (ra, rb) =
            Indicators.alignReturns(allSeries[a]!, allSeries[b]!);
        matrix[a]![b] = Indicators.correlation(ra, rb);
      }
    }
    return jsonEncode({
      'days': days,
      'symbols': symbols,
      'matrix': matrix,
    });
  }
}

/// 5. Beta / Alpha vs 沪深 300
class CalcBetaTool extends AiTool {
  CalcBetaTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_beta';
  @override
  String get description =>
      '计算单一 A 股标的相对沪深 300（默认基准）的 Beta、年化 Alpha 和 R²。'
      '用于"这只票随大盘的程度多大""能跑赢大盘多少"等问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'benchmark': {
            'type': 'string',
            'description': '基准代码（默认 000300.SH = 沪深300）',
          },
          'days': {'type': 'integer', 'description': '回看交易日数（默认 252）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final benchmark = ChinaMarket.normalizeSymbol(
        (args['benchmark'] as String? ?? '000300.SH').trim());
    final days = ((args['days'] as num?)?.toInt() ?? 252).clamp(20, 1000);
    final w = _windowOfDays(days);
    final asset =
        await _ctx.svc.historyFor(code, start: w.start, end: w.end);
    final bm =
        await _ctx.svc.historyFor(benchmark, start: w.start, end: w.end);
    if (asset.length < 20 || bm.length < 20) {
      return jsonEncode({'error': '样本不足以估算 Beta'});
    }
    final r = Indicators.beta(asset, bm);
    return jsonEncode({
      'symbol': code,
      'benchmark': benchmark,
      'observations': math.min(asset.length, bm.length),
      'beta': r.beta,
      'annualized_alpha_pct':
          r.alpha == null ? null : double.parse((r.alpha! * 100).toStringAsFixed(3)),
      'r_squared': r.r2,
    });
  }
}

/// 6. 移动平均（多周期）+ 多/空头排列判断
class CalcMovingAverageTool extends AiTool {
  CalcMovingAverageTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_moving_average';
  @override
  String get description =>
      '计算单一标的的最新 MA5 / MA10 / MA20 / MA60 / MA120 数值，'
      '并判断当前是否处于多头排列（短期 MA 在上）或空头排列（短期 MA 在下）。'
      '用于回答技术面问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'periods': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': '自定义周期数组（默认 [5,10,20,60,120]）',
          },
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final periods = (args['periods'] as List?)
            ?.map((e) => (e as num).toInt())
            .where((n) => n > 0 && n <= 250)
            .toList() ??
        const [5, 10, 20, 60, 120];
    final maxN = periods.reduce(math.max);
    final series = await _loadSeries(_ctx.svc, code, maxN + 30);
    if (series.length < maxN) {
      return jsonEncode({
        'symbol': code,
        'error': '行情样本不足以计算 MA$maxN（仅 ${series.length} 条）',
      });
    }
    final mas = <int, double?>{
      for (final n in periods) n: Indicators.sma(series, n),
    };
    final sortedPeriods = [...periods]..sort();
    final values = [for (final p in sortedPeriods) mas[p]];
    final allValid = values.every((v) => v != null);
    String? alignment;
    if (allValid) {
      var bullish = true;
      var bearish = true;
      for (var i = 0; i + 1 < values.length; i++) {
        if (!(values[i]! > values[i + 1]!)) bullish = false;
        if (!(values[i]! < values[i + 1]!)) bearish = false;
      }
      alignment = bullish ? 'bullish' : (bearish ? 'bearish' : 'mixed');
    }
    return jsonEncode({
      'symbol': code,
      'last_date': _ymd(series.last.date),
      'last_close': series.last.close,
      'ma': {for (final e in mas.entries) 'MA${e.key}': e.value},
      'alignment': alignment,
    });
  }
}

/// 7. RSI
class CalcRsiTool extends AiTool {
  CalcRsiTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_rsi';
  @override
  String get description =>
      '计算单一标的的 RSI（相对强弱指数）。RSI > 70 一般视为超买，< 30 视为超卖。'
      '回答"现在还能追吗 / 是不是超卖"等问题时使用。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'period': {'type': 'integer', 'description': '周期（默认 14）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final period = ((args['period'] as num?)?.toInt() ?? 14).clamp(2, 60);
    final series = await _loadSeries(_ctx.svc, code, period * 4 + 20);
    final rsi = Indicators.rsi(series, period: period);
    String? signal;
    if (rsi != null) {
      if (rsi > 70) {
        signal = 'overbought';
      } else if (rsi < 30) {
        signal = 'oversold';
      } else {
        signal = 'neutral';
      }
    }
    return jsonEncode({
      'symbol': code,
      'period': period,
      'last_date': series.isEmpty ? null : _ymd(series.last.date),
      'rsi': rsi,
      'signal': signal,
    });
  }
}

/// 8. MACD
class CalcMacdTool extends AiTool {
  CalcMacdTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'calc_macd';
  @override
  String get description =>
      '计算单一标的最近一日的 MACD（DIF/DEA/MACD 三值），并标注是否为金叉/死叉。'
      '回答"出现金叉了没 / 趋势是否在反转"等问题时使用。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'fast': {'type': 'integer', 'description': '快线（默认 12）'},
          'slow': {'type': 'integer', 'description': '慢线（默认 26）'},
          'signal': {'type': 'integer', 'description': '信号线（默认 9）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    final fast = ((args['fast'] as num?)?.toInt() ?? 12).clamp(3, 60);
    final slow = ((args['slow'] as num?)?.toInt() ?? 26).clamp(5, 100);
    final signal = ((args['signal'] as num?)?.toInt() ?? 9).clamp(2, 30);
    final series = await _loadSeries(_ctx.svc, code, slow * 4 + signal + 30);
    final r = Indicators.macd(series, fast: fast, slow: slow, signal: signal);
    return jsonEncode({
      'symbol': code,
      'last_date': series.isEmpty ? null : _ymd(series.last.date),
      'fast': fast,
      'slow': slow,
      'signal': signal,
      'dif': r.dif,
      'dea': r.dea,
      'macd_bar': r.macd,
      'cross': r.cross,
    });
  }
}

/// 工厂：把 8 个量化工具批量塞给 ToolRegistry 的构造列表
List<AiTool> buildQuantTools(TushareToolsContext ctx) => [
      CalcReturnsTool(ctx),
      CalcSharpeTool(ctx),
      CalcMaxDrawdownTool(ctx),
      CalcCorrelationTool(ctx),
      CalcBetaTool(ctx),
      CalcMovingAverageTool(ctx),
      CalcRsiTool(ctx),
      CalcMacdTool(ctx),
    ];
