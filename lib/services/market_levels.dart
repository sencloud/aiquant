import 'dart:math' as math;

import '../models/instrument.dart';

enum MarketLevelKind { support, resistance }

/// 一个由历史摆动点聚类得到的支撑/阻力价位。
class MarketLevel {
  const MarketLevel({
    required this.price,
    required this.kind,
    required this.score,
    required this.touches,
    required this.lastIndex,
  });

  final double price;
  final MarketLevelKind kind;
  final double score;
  final int touches;
  final int lastIndex;
}

class SupportResistance {
  const SupportResistance({
    this.supports = const [],
    this.resistances = const [],
    this.atr = 0,
  });

  final List<MarketLevel> supports;
  final List<MarketLevel> resistances;
  final double atr;
}

/// 用局部摆动高/低点识别关键价位，再按 ATR 聚类。
///
/// 这不是预测模型：它只把过去被反复验证、且距离现价最近的结构位搬到图上，
/// 方便观察价格在当前区间中的位置。
class MarketLevelAnalyzer {
  MarketLevelAnalyzer._();

  static SupportResistance analyze(
    List<CandlePoint> candles, {
    int maxCandles = 260,
    int swingWindow = 3,
    int maxPerSide = 2,
  }) {
    if (candles.length < 12) return const SupportResistance();
    final sorted = [...candles]..sort((a, b) => a.date.compareTo(b.date));
    final offset = math.max(0, sorted.length - maxCandles);
    final bars = sorted.sublist(offset);
    final close = bars.last.close;
    if (!close.isFinite || close <= 0) return const SupportResistance();

    final atr = _atr(bars, 14);
    final tolerance = math.max(atr * 0.55, close * 0.0035);
    final pivots = <_Pivot>[];
    final w = swingWindow.clamp(1, 6).toInt();

    for (var i = w; i < bars.length - w; i++) {
      final bar = bars[i];
      final high = bar.high ?? bar.close;
      final low = bar.low ?? bar.close;
      var isHigh = true;
      var isLow = true;
      for (var j = i - w; j <= i + w; j++) {
        if (j == i) continue;
        final other = bars[j];
        if ((other.high ?? other.close) >= high) isHigh = false;
        if ((other.low ?? other.close) <= low) isLow = false;
      }
      if (isHigh) {
        pivots.add(
          _Pivot(high, MarketLevelKind.resistance, i, bar.vol ?? 0),
        );
      }
      if (isLow) {
        pivots.add(_Pivot(low, MarketLevelKind.support, i, bar.vol ?? 0));
      }
    }

    if (pivots.isEmpty) {
      return SupportResistance(
        supports: _fallbackSide(bars, close, true, tolerance, maxPerSide),
        resistances: _fallbackSide(bars, close, false, tolerance, maxPerSide),
        atr: atr,
      );
    }

    final clusters = <_Cluster>[];
    for (final pivot in pivots..sort((a, b) => a.price.compareTo(b.price))) {
      _Cluster? closest;
      for (final cluster in clusters) {
        if (cluster.kind != pivot.kind) continue;
        if ((cluster.price - pivot.price).abs() <= tolerance * 1.3) {
          closest = cluster;
          break;
        }
      }
      if (closest == null) {
        clusters.add(
          _Cluster(pivot.price, pivot.kind, [pivot], pivot.index),
        );
      } else {
        closest.add(pivot);
      }
    }

    final scored = <MarketLevel>[];
    final latestVolume = _averageVolume(bars, 20);
    for (final cluster in clusters) {
      final recency = 1 - cluster.lastIndex / math.max(1, bars.length - 1);
      final age = bars.length - 1 - cluster.lastIndex;
      if (age > 55 && cluster.touches < 3) continue;
      final volumeBoost = latestVolume <= 0
          ? 0.0
          : math.min(0.8, cluster.averageVolume / latestVolume * 0.22);
      final score = cluster.touches * 1.35 + recency * 0.9 + volumeBoost;
      scored.add(
        MarketLevel(
          price: cluster.price,
          kind: cluster.kind,
          score: score,
          touches: cluster.touches,
          lastIndex: cluster.lastIndex,
        ),
      );
    }

    var supports = scored
        .where((level) =>
            level.kind == MarketLevelKind.support &&
            level.price < close - tolerance * 0.15)
        .toList()
      ..sort((a, b) {
        final byPrice = b.price.compareTo(a.price);
        return byPrice != 0 ? byPrice : b.score.compareTo(a.score);
      });
    var resistances = scored
        .where((level) =>
            level.kind == MarketLevelKind.resistance &&
            level.price > close + tolerance * 0.15)
        .toList()
      ..sort((a, b) {
        final byPrice = a.price.compareTo(b.price);
        return byPrice != 0 ? byPrice : b.score.compareTo(a.score);
      });

    supports = _dedupeNear(supports, tolerance, maxPerSide);
    resistances = _dedupeNear(resistances, tolerance, maxPerSide);
    if (supports.isEmpty) {
      supports = _fallbackSide(bars, close, true, tolerance, maxPerSide);
    }
    if (resistances.isEmpty) {
      resistances = _fallbackSide(bars, close, false, tolerance, maxPerSide);
    }
    return SupportResistance(
      supports: List.unmodifiable(supports),
      resistances: List.unmodifiable(resistances),
      atr: atr,
    );
  }

  static List<MarketLevel> _dedupeNear(
    List<MarketLevel> levels,
    double tolerance,
    int limit,
  ) {
    final out = <MarketLevel>[];
    for (final level in levels) {
      if (out.every((v) => (v.price - level.price).abs() > tolerance * 1.2)) {
        out.add(level);
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  static List<MarketLevel> _fallbackSide(
    List<CandlePoint> bars,
    double close,
    bool support,
    double tolerance,
    int limit,
  ) {
    final values = [
      for (final bar in bars)
        support ? (bar.low ?? bar.close) : (bar.high ?? bar.close),
    ];
    values.sort();
    final candidates = support ? values.reversed : values;
    final out = <MarketLevel>[];
    for (final value in candidates) {
      final valid = support
          ? value < close - tolerance * 0.15
          : value > close + tolerance * 0.15;
      if (!valid) continue;
      if (out.every((v) => (v.price - value).abs() > tolerance * 1.2)) {
        out.add(
          MarketLevel(
            price: value,
            kind:
                support ? MarketLevelKind.support : MarketLevelKind.resistance,
            score: 0.8,
            touches: 1,
            lastIndex: bars.length - 1,
          ),
        );
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  static double _atr(List<CandlePoint> bars, int n) {
    final count = math.min(n, math.max(1, bars.length - 1));
    var sum = 0.0;
    for (var i = bars.length - count; i < bars.length; i++) {
      final bar = bars[i];
      final previous = bars[math.max(0, i - 1)].close;
      final high = bar.high ?? bar.close;
      final low = bar.low ?? bar.close;
      final tr = math.max(
        high - low,
        math.max((high - previous).abs(), (low - previous).abs()),
      );
      sum += tr;
    }
    return count == 0 ? 0 : sum / count;
  }

  static double _averageVolume(List<CandlePoint> bars, int n) {
    var sum = 0.0;
    var count = 0;
    for (final bar in bars.skip(math.max(0, bars.length - n))) {
      final vol = bar.vol;
      if (vol != null && vol > 0) {
        sum += vol;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}

class _Pivot {
  const _Pivot(this.price, this.kind, this.index, this.volume);
  final double price;
  final MarketLevelKind kind;
  final int index;
  final double volume;
}

class _Cluster {
  _Cluster(this.price, this.kind, this.points, this.lastIndex)
      : averageVolume = points.isEmpty ? 0 : points.first.volume;

  double price;
  final MarketLevelKind kind;
  final List<_Pivot> points;
  int lastIndex;
  double averageVolume = 0;

  int get touches => points.length;

  void add(_Pivot pivot) {
    final total = price * points.length + pivot.price;
    points.add(pivot);
    price = total / points.length;
    lastIndex = math.max(lastIndex, pivot.index);
    averageVolume = points.fold<double>(0, (sum, point) => sum + point.volume) /
        points.length;
  }
}
