import 'dart:math' as math;

import '../../../models/instrument.dart';

/// K 线图指标序列计算（纯函数，无 IO）。
/// 与 services/indicators.dart 的区别：那边只算"最新一个值"，
/// 这里输出整条序列供画笔逐点绘制。
class ChartIndicators {
  ChartIndicators._();

  /// SMA 序列：第 i 点 = 前 n 个收盘的均值（不足 n 个时为 null）。
  static List<double?> smaSeries(List<CandlePoint> candles, int n) {
    final out = List<double?>.filled(candles.length, null);
    if (n <= 0) return out;
    var sum = 0.0;
    for (var i = 0; i < candles.length; i++) {
      sum += candles[i].close;
      if (i >= n) sum -= candles[i - n].close;
      if (i >= n - 1) out[i] = sum / n;
    }
    return out;
  }

  /// EMA 序列：首值 = 首收盘，之后 ema = close*k + prev*(1-k)。
  static List<double?> emaSeries(List<CandlePoint> candles, int n) {
    if (candles.isEmpty || n <= 0) return const [];
    final k = 2 / (n + 1);
    final out = List<double?>.filled(candles.length, null);
    var prev = candles.first.close;
    out[0] = prev;
    for (var i = 1; i < candles.length; i++) {
      prev = candles[i].close * k + prev * (1 - k);
      out[i] = prev;
    }
    return out;
  }

  /// BOLL(20,2)：中轨 = SMA20，上下轨 = 中轨 ± 2*标准差。
  /// 返回 (mid, upper, lower)。
  static (List<double?>, List<double?>, List<double?>) bollSeries(
      List<CandlePoint> candles,
      {int n = 20,
      int k = 2}) {
    final mid = List<double?>.filled(candles.length, null);
    final upper = List<double?>.filled(candles.length, null);
    final lower = List<double?>.filled(candles.length, null);
    if (n <= 1 || candles.length < n) return (mid, upper, lower);
    for (var i = n - 1; i < candles.length; i++) {
      final m = smaSeries(candles.sublist(0, i + 1), n)[i];
      if (m == null) continue;
      var sumSq = 0.0;
      for (var j = i - n + 1; j <= i; j++) {
        final d = candles[j].close - m;
        sumSq += d * d;
      }
      final std = math.sqrt(sumSq / n);
      mid[i] = m;
      upper[i] = m + k * std;
      lower[i] = m - k * std;
    }
    return (mid, upper, lower);
  }

  /// MACD(12,26,9)：DIF、DEA、MACD 柱（= 2*(DIF-DEA)，国内口径）。
  static (List<double?>, List<double?>, List<double?>) macdSeries(
      List<CandlePoint> candles,
      {int fast = 12,
      int slow = 26,
      int signal = 9}) {
    final dif = List<double?>.filled(candles.length, null);
    final dea = List<double?>.filled(candles.length, null);
    final bar = List<double?>.filled(candles.length, null);
    if (candles.length < slow + signal) return (dif, dea, bar);

    final emaF = emaSeries(candles, fast);
    final emaS = emaSeries(candles, slow);
    // EMA 序列从首点就有值，但前 slow 点不可信，统一从 slow-1 起输出。
    for (var i = slow - 1; i < candles.length; i++) {
      dif[i] = emaF[i]! - emaS[i]!;
    }
    // DEA = DIF 的 EMA(9)：用已有值的段落做一次 EMA。
    final difVals = <double>[];
    final difIdx = <int>[];
    for (var i = 0; i < candles.length; i++) {
      final v = dif[i];
      if (v != null) {
        difVals.add(v);
        difIdx.add(i);
      }
    }
    if (difVals.isEmpty) return (dif, dea, bar);
    final k = 2 / (signal + 1);
    var prev = difVals.first;
    dea[difIdx[0]] = prev;
    for (var i = 1; i < difVals.length; i++) {
      prev = difVals[i] * k + prev * (1 - k);
      dea[difIdx[i]] = prev;
    }
    for (var i = 0; i < candles.length; i++) {
      if (dif[i] != null && dea[i] != null) {
        bar[i] = 2 * (dif[i]! - dea[i]!);
      }
    }
    return (dif, dea, bar);
  }

  /// KDJ(9,3,3)：RSV → K → D → J。
  /// RSV = (C - L9) / (H9 - L9) * 100
  static (List<double?>, List<double?>, List<double?>) kdjSeries(
      List<CandlePoint> candles,
      {int n = 9,
      int k1 = 3,
      int d1 = 3}) {
    final k = List<double?>.filled(candles.length, null);
    final d = List<double?>.filled(candles.length, null);
    final j = List<double?>.filled(candles.length, null);
    if (candles.length < n) return (k, d, j);
    var prevK = 50.0;
    var prevD = 50.0;
    for (var i = n - 1; i < candles.length; i++) {
      var hh = candles[i].high ?? candles[i].close;
      var ll = candles[i].low ?? candles[i].close;
      for (var t = i - n + 1; t <= i; t++) {
        hh = math.max(hh, candles[t].high ?? candles[t].close);
        ll = math.min(ll, candles[t].low ?? candles[t].close);
      }
      final rsv = hh == ll ? 50.0 : (candles[i].close - ll) / (hh - ll) * 100;
      final curK = (2 * prevK + rsv) / k1;
      final curD = (2 * prevD + curK) / d1;
      final curJ = 3 * curK - 2 * curD;
      k[i] = curK;
      d[i] = curD;
      j[i] = curJ;
      prevK = curK;
      prevD = curD;
    }
    return (k, d, j);
  }

  /// RSI(14) 序列：国内软件常用 SMA(X,A,1) 平滑口径。
  /// RSI = SMA(max(close-prev,0), N,1) /
  ///       (SMA(max(close-prev,0),N,1) + SMA(max(prev-close,0),N,1)) * 100
  static List<double?> rsiSeries(List<CandlePoint> candles, {int n = 14}) {
    final out = List<double?>.filled(candles.length, null);
    if (candles.length < n + 1) return out;
    var avgGain = 0.0;
    var avgLoss = 0.0;
    for (var i = 1; i <= n; i++) {
      final diff = candles[i].close - candles[i - 1].close;
      if (diff > 0) {
        avgGain += diff;
      } else {
        avgLoss -= diff;
      }
    }
    avgGain /= n;
    avgLoss /= n;
    void setRsi(int i) {
      if (avgGain + avgLoss == 0) {
        out[i] = 50.0;
      } else {
        out[i] = avgGain / (avgGain + avgLoss) * 100;
      }
    }

    setRsi(n);
    // 之后用 Wilder 平滑（等价 SMA(X,N,1)）。
    for (var i = n + 1; i < candles.length; i++) {
      final diff = candles[i].close - candles[i - 1].close;
      final gain = diff > 0 ? diff : 0.0;
      final loss = diff < 0 ? -diff : 0.0;
      avgGain = (avgGain * (n - 1) + gain) / n;
      avgLoss = (avgLoss * (n - 1) + loss) / n;
      setRsi(i);
    }
    return out;
  }
}
