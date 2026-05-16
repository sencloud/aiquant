import 'dart:math' as math;

import '../models/instrument.dart';

/// 量化指标纯计算工具集（无网络 IO，无 Tushare 依赖）。
/// 所有指标基于一段日线收盘序列；调用方负责拉取 [CandlePoint] 序列后传入。
class Indicators {
  Indicators._();

  // ── 基础工具 ────────────────────────────────────────────────────────────

  static List<double> _closes(List<CandlePoint> series) =>
      [for (final c in series) c.close];

  /// 收益率序列（pct_chg / 100），长度 = series.length - 1
  static List<double> dailyReturns(List<CandlePoint> series) {
    final out = <double>[];
    for (var i = 1; i < series.length; i++) {
      final prev = series[i - 1].close;
      if (prev == 0) {
        out.add(0);
      } else {
        out.add((series[i].close - prev) / prev);
      }
    }
    return out;
  }

  static double _mean(List<double> xs) {
    if (xs.isEmpty) return 0;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  static double _variance(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = _mean(xs);
    var sum = 0.0;
    for (final x in xs) {
      final d = x - m;
      sum += d * d;
    }
    return sum / (xs.length - 1);
  }

  static double _stddev(List<double> xs) => math.sqrt(_variance(xs));

  static double _round(double v, [int digits = 4]) =>
      double.parse(v.toStringAsFixed(digits));

  // ── 收益 / 波动 / Sharpe / 最大回撤 ─────────────────────────────────────

  /// 区间累计收益率（最后/首日 - 1）
  static double cumulativeReturn(List<CandlePoint> series) {
    if (series.length < 2) return 0;
    final first = series.first.close;
    if (first == 0) return 0;
    return (series.last.close - first) / first;
  }

  /// 年化收益率（按 252 个交易日折算）
  static double annualizedReturn(List<CandlePoint> series) {
    if (series.length < 2) return 0;
    final r = cumulativeReturn(series);
    final years = (series.length - 1) / 252.0;
    if (years <= 0) return 0;
    return math.pow(1 + r, 1 / years) - 1;
  }

  /// 年化波动率（日收益率标准差 * sqrt(252)）
  static double annualizedVolatility(List<CandlePoint> series) {
    final rs = dailyReturns(series);
    if (rs.length < 2) return 0;
    return _stddev(rs) * math.sqrt(252);
  }

  /// 年化 Sharpe Ratio = (ann_ret - rf) / ann_vol
  static double sharpeRatio(List<CandlePoint> series, {double riskFree = 0.02}) {
    final ar = annualizedReturn(series);
    final av = annualizedVolatility(series);
    if (av == 0) return 0;
    return (ar - riskFree) / av;
  }

  /// 最大回撤：从历史峰值到谷底的最大跌幅，返回正数（如 0.235 表示 -23.5%）
  static MaxDrawdownResult maxDrawdown(List<CandlePoint> series) {
    if (series.length < 2) {
      return const MaxDrawdownResult(
          drawdown: 0, peakDate: null, troughDate: null);
    }
    var peak = series.first.close;
    DateTime peakDate = series.first.date;
    var maxDd = 0.0;
    DateTime? mddPeak;
    DateTime? mddTrough;
    for (final c in series) {
      if (c.close > peak) {
        peak = c.close;
        peakDate = c.date;
      }
      if (peak > 0) {
        final dd = (peak - c.close) / peak;
        if (dd > maxDd) {
          maxDd = dd;
          mddPeak = peakDate;
          mddTrough = c.date;
        }
      }
    }
    return MaxDrawdownResult(
      drawdown: _round(maxDd, 4),
      peakDate: mddPeak,
      troughDate: mddTrough,
    );
  }

  // ── 移动平均 / RSI / MACD ───────────────────────────────────────────────

  /// 简单移动平均 SMA
  static double? sma(List<CandlePoint> series, int n) {
    if (series.length < n || n <= 0) return null;
    final tail = _closes(series).sublist(series.length - n);
    return _round(_mean(tail), 4);
  }

  /// 指数加权移动平均 EMA
  static List<double> emaSeries(List<double> values, int n) {
    if (values.isEmpty || n <= 0) return const [];
    final k = 2 / (n + 1);
    final out = <double>[values.first];
    for (var i = 1; i < values.length; i++) {
      out.add(values[i] * k + out.last * (1 - k));
    }
    return out;
  }

  /// 相对强弱指数 RSI（默认 14 日）
  static double? rsi(List<CandlePoint> series, {int period = 14}) {
    if (series.length <= period) return null;
    var gains = 0.0;
    var losses = 0.0;
    for (var i = series.length - period; i < series.length; i++) {
      final diff = series[i].close - series[i - 1].close;
      if (diff > 0) {
        gains += diff;
      } else {
        losses -= diff;
      }
    }
    if (gains + losses == 0) return 50;
    final avgGain = gains / period;
    final avgLoss = losses / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return _round(100 - 100 / (1 + rs), 2);
  }

  /// MACD：DIF = EMA(fast) - EMA(slow)；DEA = EMA(DIF, signal)；MACD = 2*(DIF-DEA)
  static MacdResult macd(
    List<CandlePoint> series, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    if (series.length < slow + signal) {
      return const MacdResult(dif: null, dea: null, macd: null, cross: null);
    }
    final closes = _closes(series);
    final emaFast = emaSeries(closes, fast);
    final emaSlow = emaSeries(closes, slow);
    final dif = <double>[];
    for (var i = 0; i < closes.length; i++) {
      dif.add(emaFast[i] - emaSlow[i]);
    }
    final dea = emaSeries(dif, signal);
    final last = dif.length - 1;
    final macdVal = 2 * (dif[last] - dea[last]);
    String? cross;
    if (last >= 1) {
      final prevDif = dif[last - 1];
      final prevDea = dea[last - 1];
      if (prevDif <= prevDea && dif[last] > dea[last]) cross = 'golden';
      if (prevDif >= prevDea && dif[last] < dea[last]) cross = 'death';
    }
    return MacdResult(
      dif: _round(dif[last]),
      dea: _round(dea[last]),
      macd: _round(macdVal),
      cross: cross,
    );
  }

  // ── Beta / 相关性 ────────────────────────────────────────────────────────

  /// 收益率序列对齐：按日期裁剪到两边交集
  static (List<double>, List<double>) alignReturns(
      List<CandlePoint> a, List<CandlePoint> b) {
    final mapA = {for (final c in a) c.date: c.close};
    final mapB = {for (final c in b) c.date: c.close};
    final dates = mapA.keys.where(mapB.containsKey).toList()..sort();
    if (dates.length < 2) return (const [], const []);
    final ra = <double>[];
    final rb = <double>[];
    for (var i = 1; i < dates.length; i++) {
      final pa0 = mapA[dates[i - 1]]!;
      final pb0 = mapB[dates[i - 1]]!;
      if (pa0 == 0 || pb0 == 0) continue;
      ra.add((mapA[dates[i]]! - pa0) / pa0);
      rb.add((mapB[dates[i]]! - pb0) / pb0);
    }
    return (ra, rb);
  }

  /// Pearson 相关系数
  static double correlation(List<double> x, List<double> y) {
    if (x.length != y.length || x.length < 2) return 0;
    final mx = _mean(x);
    final my = _mean(y);
    var num = 0.0, dx2 = 0.0, dy2 = 0.0;
    for (var i = 0; i < x.length; i++) {
      final dx = x[i] - mx;
      final dy = y[i] - my;
      num += dx * dy;
      dx2 += dx * dx;
      dy2 += dy * dy;
    }
    final den = math.sqrt(dx2 * dy2);
    if (den == 0) return 0;
    return _round(num / den, 4);
  }

  /// Beta = cov(asset, benchmark) / var(benchmark)
  static BetaResult beta(List<CandlePoint> asset, List<CandlePoint> benchmark,
      {double riskFree = 0.02}) {
    final (ra, rb) = alignReturns(asset, benchmark);
    if (ra.length < 5) {
      return const BetaResult(beta: null, alpha: null, r2: null);
    }
    final ma = _mean(ra);
    final mb = _mean(rb);
    var cov = 0.0, varB = 0.0;
    for (var i = 0; i < ra.length; i++) {
      final dx = ra[i] - ma;
      final dy = rb[i] - mb;
      cov += dx * dy;
      varB += dy * dy;
    }
    cov /= ra.length - 1;
    varB /= ra.length - 1;
    if (varB == 0) {
      return const BetaResult(beta: null, alpha: null, r2: null);
    }
    final betaVal = cov / varB;
    final dailyRf = riskFree / 252;
    final alphaVal = (ma - dailyRf) - betaVal * (mb - dailyRf);
    final corr = correlation(ra, rb);
    return BetaResult(
      beta: _round(betaVal, 4),
      alpha: _round(alphaVal * 252, 4),
      r2: _round(corr * corr, 4),
    );
  }
}

class MaxDrawdownResult {
  const MaxDrawdownResult({
    required this.drawdown,
    required this.peakDate,
    required this.troughDate,
  });
  final double drawdown;
  final DateTime? peakDate;
  final DateTime? troughDate;
}

class MacdResult {
  const MacdResult({
    required this.dif,
    required this.dea,
    required this.macd,
    required this.cross,
  });
  final double? dif;
  final double? dea;
  final double? macd;
  final String? cross;
}

class BetaResult {
  const BetaResult({required this.beta, required this.alpha, required this.r2});
  final double? beta;
  final double? alpha;
  final double? r2;
}
