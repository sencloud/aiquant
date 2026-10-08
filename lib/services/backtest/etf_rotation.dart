import 'dart:math' as math;

import '../../core/utils/china_market.dart';

/// 「双动量 ETF 组合轮动」回测引擎 — 纯 Dart 本地计算。
///
/// 移植自后端 Go 实现 backend/internal/ai/tools/backtest.go 的
/// `backtest_etf_rotation` 工具，算法与默认参数完全一致：
/// - 候选池中按 score = w_short*R_short + w_long*R_long 排名；
/// - 每 rebalance_days 个交易日轮换前 top_n 等权；
/// - 入选标的 score < 0 的名额切换到 defensive ETF 防御；
/// - 与 benchmark 对比输出总收益/年化/波动/Sharpe/最大回撤/月胜率。
///
/// 引擎不做任何 IO（行情由 BacktestDataSource 提供），便于 UI 层
/// 改参数后本地秒级重跑。

/// 回测输入参数（UI 表单直接构造，未填字段走默认值）。
class EtfRotationParams {
  const EtfRotationParams({
    this.symbols = const [],
    this.startDate,
    this.endDate,
    this.rebalanceDays,
    this.shortWindow,
    this.longWindow,
    this.wShort,
    this.wLong,
    this.topN,
    this.defensive,
    this.benchmark,
  });

  /// 候选 ETF 代码列表（6 位或 ts_code，最多 12 只）。
  final List<String> symbols;

  /// 回测起始日（默认今天前 3 年）。
  final DateTime? startDate;

  /// 回测结束日（默认今天）。
  final DateTime? endDate;

  /// 再平衡周期（交易日，5-60，默认 20）。
  final int? rebalanceDays;

  /// 短动量窗口（5-120，默认 20）。
  final int? shortWindow;

  /// 长动量窗口（20-252，默认 60）。
  final int? longWindow;

  /// 短动量权重（默认 0.6）。
  final double? wShort;

  /// 长动量权重（默认 0.4）。
  final double? wLong;

  /// 持仓数（1-5，默认 3）。
  final int? topN;

  /// 防御 ETF（默认 511260 国债 ETF）。
  final String? defensive;

  /// 基准 ETF（默认 510300 沪深 300）。
  final String? benchmark;
}

/// 一条行情：日期（YYYYMMDD 字符串）+ 收盘价。引擎只消费收盘价。
class BacktestCandle {
  const BacktestCandle(this.date, this.close);
  final String date;
  final double close;
}

/// 净值曲线上的一个点。
class NavPoint {
  const NavPoint(this.date, this.nav);
  final DateTime date;
  final double nav;
}

/// 绩效统计块（策略与基准各一份）。
class BacktestMetrics {
  const BacktestMetrics({
    required this.totalReturn,
    required this.annReturn,
    required this.annVol,
    required this.sharpe,
    required this.maxDrawdown,
  });

  final double totalReturn;
  final double annReturn;
  final double annVol;
  final double sharpe;
  final double maxDrawdown;
}

/// 期末持仓行。
class HoldingRow {
  const HoldingRow(this.symbol, this.weight);
  final String symbol;
  final double weight;
}

/// 回测结果。
class BacktestResult {
  const BacktestResult({
    required this.periodStart,
    required this.periodEnd,
    required this.observations,
    required this.rebalances,
    required this.strategyMetrics,
    required this.benchmarkMetrics,
    required this.alpha,
    required this.monthlyWinRate,
    required this.navSeries,
    required this.benchmarkNavSeries,
    required this.finalHoldings,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final int observations;
  final int rebalances;
  final BacktestMetrics strategyMetrics;
  final BacktestMetrics benchmarkMetrics;

  /// 年化超额收益（策略 - 基准）。
  final double alpha;

  /// 月胜率（0-100）。
  final double monthlyWinRate;

  /// 策略月度净值曲线（与 benchmarkNavSeries 对齐，同长度）。
  final List<NavPoint> navSeries;
  final List<NavPoint> benchmarkNavSeries;

  /// 期末持仓（权重降序）。
  final List<HoldingRow> finalHoldings;
}

/// 回测失败（数据不足 / 参数窗口过短等业务性错误）。
class BacktestException implements Exception {
  BacktestException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 解析并钳制后的内部参数（对应 Go 的 resolvedBacktest）。
class _Resolved {
  _Resolved({
    required this.symbols,
    required this.start,
    required this.end,
    required this.rebalanceDays,
    required this.shortWindow,
    required this.longWindow,
    required this.wShort,
    required this.wLong,
    required this.topN,
    required this.defensive,
    required this.benchmark,
  });

  final List<String> symbols;
  final DateTime start;
  final DateTime end;
  final int rebalanceDays;
  final int shortWindow;
  final int longWindow;
  final double wShort;
  final double wLong;
  final int topN;
  final String defensive;
  final String benchmark;
}

// _Resolved 仅引擎内部使用；对外预览用 ResolvedBacktestConfig。

// ── 参数解析（对应 Go resolveBacktestInput） ─────────────────────────

const _defaultSymbols = [
  '510300', '510500', '159915', '588000', '510880', '518880', '511260',
];

/// 供 UI 预览解析后的参数（默认值 / 钳制后的实际生效值）。
/// 返回值字段与 _Resolved 一致，但只读用于展示与暖机窗口计算。
ResolvedBacktestConfig previewResolved(EtfRotationParams in_) {
  final r = _resolve(in_);
  return ResolvedBacktestConfig(
    symbols: r.symbols,
    start: r.start,
    end: r.end,
    rebalanceDays: r.rebalanceDays,
    shortWindow: r.shortWindow,
    longWindow: r.longWindow,
    wShort: r.wShort,
    wLong: r.wLong,
    topN: r.topN,
    defensive: r.defensive,
    benchmark: r.benchmark,
  );
}

class ResolvedBacktestConfig {
  const ResolvedBacktestConfig({
    required this.symbols,
    required this.start,
    required this.end,
    required this.rebalanceDays,
    required this.shortWindow,
    required this.longWindow,
    required this.wShort,
    required this.wLong,
    required this.topN,
    required this.defensive,
    required this.benchmark,
  });

  final List<String> symbols;
  final DateTime start;
  final DateTime end;
  final int rebalanceDays;
  final int shortWindow;
  final int longWindow;
  final double wShort;
  final double wLong;
  final int topN;
  final String defensive;
  final String benchmark;
}

_Resolved _resolve(EtfRotationParams in_) {
  final now = DateTime.now();

  final syms = in_.symbols
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final symbols = syms.isEmpty ? _defaultSymbols : syms.take(12).toList();

  var start = in_.startDate ?? now.subtract(const Duration(days: 365 * 3));
  var end = in_.endDate ?? now;
  if (!end.isAfter(start)) {
    start = end.subtract(const Duration(days: 365));
  }

  var defensive = (in_.defensive ?? '').trim();
  if (defensive.isEmpty) defensive = '511260';
  var benchmark = (in_.benchmark ?? '').trim();
  if (benchmark.isEmpty) benchmark = '510300';

  var wShort = in_.wShort ?? 0;
  var wLong = in_.wLong ?? 0;
  if (wShort <= 0 && wLong <= 0) {
    wShort = 0.6;
    wLong = 0.4;
  }
  if (wShort < 0) wShort = 0;
  if (wLong < 0) wLong = 0;
  if (wShort + wLong == 0) {
    wShort = 0.6;
    wLong = 0.4;
  }

  return _Resolved(
    symbols: symbols,
    start: start,
    end: end,
    rebalanceDays: _clampInt(in_.rebalanceDays, 5, 60, 20),
    shortWindow: _clampInt(in_.shortWindow, 5, 120, 20),
    longWindow: _clampInt(in_.longWindow, 20, 252, 60),
    wShort: wShort,
    wLong: wLong,
    topN: _clampInt(in_.topN, 1, 5, 3),
    defensive: defensive,
    benchmark: benchmark,
  );
}

int _clampInt(int? v, int min, int max, int dflt) {
  if (v == null) return dflt;
  return v.clamp(min, max);
}

// ── 主流程 ────────────────────────────────────────────────────────────

/// 执行回测。[series] 为每个归一化代码的日线（调用方负责拉取与暖机窗口）。
BacktestResult runEtfRotationBacktest({
  required EtfRotationParams params,
  required Map<String, List<BacktestCandle>> series,
}) {
  final cfg = _resolve(params);

  // 2) 对齐 trade_date：取所有候选 symbols 的交集（benchmark 不强制）。
  final symCodes =
      cfg.symbols.map(ChinaMarket.normalizeSymbol).toList();
  final dates = _intersectDates(series, symCodes);
  if (dates.length < cfg.longWindow + cfg.rebalanceDays) {
    throw BacktestException(
      '候选池交集后仅 ${dates.length} 个交易日，不足以回测'
      '（至少需要 ${cfg.longWindow + cfg.rebalanceDays}）',
    );
  }

  // 3) 构建每个 code 在每个对齐交易日的收盘价。
  final closes = <String, List<double>>{};
  for (final code in symCodes) {
    closes[code] = _pickCloses(series[code]!, dates);
  }
  // benchmark / defensive 用自己的交易日，缺失日前向填充。
  final benchCloses = _pickClosesAllowFill(
      series[ChinaMarket.normalizeSymbol(cfg.benchmark)]!, dates);
  final defCloses = _pickClosesAllowFill(
      series[ChinaMarket.normalizeSymbol(cfg.defensive)]!, dates);

  // 4) 策略实际起始 index：≥ long_window 且 ≥ 用户 start_date 中较晚者。
  var startIdx = cfg.longWindow;
  final userStartStr = _formatYmd(cfg.start);
  for (var i = 0; i < dates.length; i++) {
    if (dates[i].compareTo(userStartStr) >= 0) {
      if (i > startIdx) startIdx = i;
      break;
    }
  }
  if (startIdx >= dates.length - cfg.rebalanceDays) {
    throw BacktestException('回测窗口过短，请扩大时间范围');
  }

  // 5) 模拟：NAV[startIdx] = 1，每 rebalance_days 触发一次再平衡。
  var nav = 1.0;
  final benchStartClose = benchCloses[startIdx];
  var benchNav = 1.0;
  var navSeries = <NavPoint>[NavPoint(_parseYmd(dates[startIdx]), 1.0)];
  var benchSeries = <NavPoint>[NavPoint(_parseYmd(dates[startIdx]), 1.0)];

  var weights = _rebalance(closes, startIdx, cfg, defCloses);
  var rebCount = 1;
  var finalWeights = weights;

  final dailyReturns = <double>[];
  var monthlyWins = 0;
  var monthlyTotal = 0;
  var monthStartNav = 1.0;
  var monthStartBench = 1.0;
  var monthStartDate = dates[startIdx].substring(0, 6);

  for (var i = startIdx + 1; i < dates.length; i++) {
    var dayRet = 0.0;
    weights.forEach((code, w) {
      final prev = _lookupClose(closes, defCloses, code, i - 1);
      final cur = _lookupClose(closes, defCloses, code, i);
      if (prev <= 0 || cur <= 0) return;
      dayRet += w * (cur / prev - 1);
    });
    nav *= 1 + dayRet;
    dailyReturns.add(dayRet);

    if (benchCloses[i] > 0 && benchStartClose > 0) {
      benchNav = benchCloses[i] / benchStartClose;
    }

    // 月末（YYYYMM 变化）记录月度点 + 计胜率
    final curMonth = dates[i].substring(0, 6);
    if (curMonth != monthStartDate) {
      navSeries.add(NavPoint(_parseYmd(dates[i - 1]), _round(nav, 6)));
      benchSeries
          .add(NavPoint(_parseYmd(dates[i - 1]), _round(benchNav, 6)));
      monthlyTotal++;
      final stratRet = nav / monthStartNav - 1;
      final benchRet = benchNav / monthStartBench - 1;
      if (stratRet > benchRet) monthlyWins++;
      monthStartNav = nav;
      monthStartBench = benchNav;
      monthStartDate = curMonth;
    }

    // 距上次再平衡 rebalance_days 个交易日 → 触发
    if ((i - startIdx) % cfg.rebalanceDays == 0) {
      weights = _rebalance(closes, i, cfg, defCloses);
      finalWeights = weights;
      rebCount++;
    }
  }
  // 收尾：补上最后一个月度点
  if (navSeries.isEmpty ||
      navSeries.last.date != _parseYmd(dates[dates.length - 1])) {
    navSeries
        .add(NavPoint(_parseYmd(dates[dates.length - 1]), _round(nav, 6)));
    benchSeries.add(
        NavPoint(_parseYmd(dates[dates.length - 1]), _round(benchNav, 6)));
  }

  // 6) 指标统计
  final stratStats = _stats(dailyReturns, nav);
  final benchDaily = _benchDailyReturns(benchCloses, startIdx);
  final benchStats = _stats(benchDaily, benchNav);

  var winRate = 0.0;
  if (monthlyTotal > 0) {
    winRate = monthlyWins / monthlyTotal * 100;
  }

  final defCode = ChinaMarket.normalizeSymbol(cfg.defensive);
  final holdings = finalWeights.entries
      .where((e) => e.value > 0)
      .map((e) => e.key == defCode
          ? HoldingRow('${e.key}（防御）', e.value)
          : HoldingRow(e.key, e.value))
      .toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));

  return BacktestResult(
    periodStart: _parseYmd(dates[startIdx]),
    periodEnd: _parseYmd(dates[dates.length - 1]),
    observations: dailyReturns.length + 1,
    rebalances: rebCount,
    strategyMetrics: stratStats,
    benchmarkMetrics: benchStats,
    alpha: stratStats.annReturn - benchStats.annReturn,
    monthlyWinRate: winRate,
    navSeries: navSeries,
    benchmarkNavSeries: benchSeries,
    finalHoldings: holdings,
  );
}

// ── 数据准备（对应 Go intersectDates / pickCloses / pickClosesAllowFill）──

/// 取所有 codes 在 series 里都出现的 trade_date 并按升序返回。
List<String> _intersectDates(
    Map<String, List<BacktestCandle>> series, List<String> codes) {
  if (codes.isEmpty) return const [];
  final count = <String, int>{};
  for (final code in codes) {
    final candles = series[code];
    if (candles == null) continue;
    final seen = <String>{};
    for (final c in candles) {
      if (seen.add(c.date)) count[c.date] = (count[c.date] ?? 0) + 1;
    }
  }
  final out = count.entries
      .where((e) => e.value == codes.length)
      .map((e) => e.key)
      .toList()
    ..sort();
  return out;
}

/// 取 series 在指定日期列表上的收盘价（要求全部命中）。
List<double> _pickCloses(List<BacktestCandle> s, List<String> dates) {
  final m = {for (final c in s) c.date: c.close};
  return [for (final d in dates) m[d] ?? 0.0];
}

/// 同 _pickCloses 但缺失日用前一日补（benchmark / defensive 用）。
List<double> _pickClosesAllowFill(List<BacktestCandle> s, List<String> dates) {
  final m = {for (final c in s) c.date: c.close};
  final out = List<double>.filled(dates.length, 0.0);
  var last = 0.0;
  for (var i = 0; i < dates.length; i++) {
    final v = m[dates[i]];
    if (v != null && v > 0) last = v;
    out[i] = last;
  }
  return out;
}

double _lookupClose(Map<String, List<double>> closes, List<double> defCloses,
    String code, int idx) {
  final v = closes[code];
  if (v != null && idx < v.length) return v[idx];
  if (idx < defCloses.length) return defCloses[idx];
  return 0;
}

// ── 再平衡（对应 Go rebalance） ───────────────────────────────────────

/// 在 idx 这一天用过去 short/long 窗口计算动量打分，选 top_n 等权；
/// 负动量的名额转给 defensive。
Map<String, double> _rebalance(Map<String, List<double>> closes, int idx,
    _Resolved cfg, List<double> defCloses) {
  final scores = <(String, double)>[];
  for (final raw in cfg.symbols) {
    final code = ChinaMarket.normalizeSymbol(raw);
    final cs = closes[code];
    if (cs == null || idx >= cs.length) continue;
    final curPrice = cs[idx];
    if (curPrice <= 0) continue;
    final shortBack = idx - cfg.shortWindow;
    final longBack = idx - cfg.longWindow;
    if (shortBack < 0 || longBack < 0) continue;
    final prevShort = cs[shortBack];
    final prevLong = cs[longBack];
    if (prevShort <= 0 || prevLong <= 0) continue;
    final rs = curPrice / prevShort - 1;
    final rl = curPrice / prevLong - 1;
    scores.add((code, cfg.wShort * rs + cfg.wLong * rl));
  }
  scores.sort((a, b) => b.$2.compareTo(a.$2));

  final w = <String, double>{};
  final defCode = ChinaMarket.normalizeSymbol(cfg.defensive);
  var slots = cfg.topN;
  if (slots > scores.length) slots = scores.length;
  final per = 1.0 / cfg.topN;
  var defenseTotal = 0.0;
  for (var i = 0; i < slots; i++) {
    if (scores[i].$2 <= 0) {
      defenseTotal += per;
      continue;
    }
    w[scores[i].$1] = (w[scores[i].$1] ?? 0) + per;
  }
  // 候选数不足 top_n 时，剩余名额也给防御
  if (slots < cfg.topN) {
    defenseTotal += per * (cfg.topN - slots);
  }
  if (defenseTotal > 0) {
    w[defCode] = (w[defCode] ?? 0) + defenseTotal;
  }
  return w;
}

// ── 指标统计（对应 Go backtestStats / benchDailyReturns） ─────────────

BacktestMetrics _stats(List<double> dailyReturns, double finalNav) {
  final n = dailyReturns.length;
  if (n < 2) {
    return const BacktestMetrics(
        totalReturn: 0, annReturn: 0, annVol: 0, sharpe: 0, maxDrawdown: 0);
  }
  final totalReturn = finalNav - 1;
  final years = n / 252.0;
  var annReturn = 0.0;
  if (years > 0) {
    annReturn = math.pow(1 + totalReturn, 1 / years) - 1;
  }
  var mean = 0.0;
  for (final r in dailyReturns) {
    mean += r;
  }
  mean /= n;
  var varSum = 0.0;
  for (final r in dailyReturns) {
    final d = r - mean;
    varSum += d * d;
  }
  final std = math.sqrt(varSum / (n - 1));
  final annVol = std * math.sqrt(252);
  var sharpe = 0.0;
  if (annVol > 0) {
    // 与 Go 版一致：无风险利率取 2%
    sharpe = (annReturn - 0.02) / annVol;
  }

  // 最大回撤：从日收益还原 NAV 序列
  var nav = 1.0;
  var peak = 1.0;
  var maxDd = 0.0;
  for (final r in dailyReturns) {
    nav *= 1 + r;
    if (nav > peak) peak = nav;
    final dd = (peak - nav) / peak;
    if (dd > maxDd) maxDd = dd;
  }
  return BacktestMetrics(
    totalReturn: totalReturn,
    annReturn: annReturn,
    annVol: annVol,
    sharpe: sharpe,
    maxDrawdown: maxDd,
  );
}

List<double> _benchDailyReturns(List<double> benchCloses, int startIdx) {
  final out = <double>[];
  for (var i = startIdx + 1; i < benchCloses.length; i++) {
    final prev = benchCloses[i - 1];
    if (prev <= 0) {
      out.add(0);
      continue;
    }
    out.add(benchCloses[i] / prev - 1);
  }
  return out;
}

// ── 小工具 ────────────────────────────────────────────────────────────

String _formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _parseYmd(String s) => DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );

double _round(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).roundToDouble() / p;
}
