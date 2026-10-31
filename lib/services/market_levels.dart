import 'dart:math' as math;

import '../models/instrument.dart';

enum MarketLevelKind { support, resistance }

/// 由历史摆动点聚类形成的支撑/阻力区间。
class MarketPriceZone {
  const MarketPriceZone({
    required this.low,
    required this.high,
    required this.kind,
    required this.score,
    required this.touches,
    required this.lastIndex,
  });

  final double low;
  final double high;
  final MarketLevelKind kind;
  final double score;
  final int touches;
  final int lastIndex;

  double get center => (low + high) / 2;
  double get width => high - low;

  bool contains(double price) => price >= low && price <= high;
}

class SupportResistance {
  const SupportResistance({
    this.supports = const [],
    this.resistances = const [],
    this.atr = 0,
  });

  final List<MarketPriceZone> supports;
  final List<MarketPriceZone> resistances;
  final double atr;
}

/// 用局部摆动高/低点识别关键区间，再按 ATR 聚类。
///
/// 这不是预测模型：它只把过去被反复验证、且距离现价最近的结构带搬到图上，
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
        supports: _fallbackZones(
          bars,
          close,
          true,
          tolerance,
          maxPerSide,
        ),
        resistances: _fallbackZones(
          bars,
          close,
          false,
          tolerance,
          maxPerSide,
        ),
        atr: atr,
      );
    }

    final clusters = <_Cluster>[];
    for (final pivot in pivots..sort((a, b) => a.price.compareTo(b.price))) {
      _Cluster? closest;
      for (final cluster in clusters) {
        if (cluster.kind != pivot.kind) continue;
        if ((cluster.center - pivot.price).abs() <= tolerance * 1.3) {
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

    final scored = <MarketPriceZone>[];
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
        cluster.toZone(
          score: score,
          minimumHalfWidth: tolerance * 0.55,
          maximumHalfWidth: tolerance * 1.55,
        ),
      );
    }

    var supports = scored
        .where(
          (zone) =>
              zone.kind == MarketLevelKind.support &&
              zone.high < close - tolerance * 0.05,
        )
        .toList()
      ..sort((a, b) {
        final byDistance = b.high.compareTo(a.high);
        return byDistance != 0 ? byDistance : b.score.compareTo(a.score);
      });
    var resistances = scored
        .where(
          (zone) =>
              zone.kind == MarketLevelKind.resistance &&
              zone.low > close + tolerance * 0.05,
        )
        .toList()
      ..sort((a, b) {
        final byDistance = a.low.compareTo(b.low);
        return byDistance != 0 ? byDistance : b.score.compareTo(a.score);
      });

    supports = _dedupeZones(supports, tolerance, maxPerSide);
    resistances = _dedupeZones(resistances, tolerance, maxPerSide);
    if (supports.isEmpty) {
      supports = _fallbackZones(bars, close, true, tolerance, maxPerSide);
    }
    if (resistances.isEmpty) {
      resistances = _fallbackZones(
        bars,
        close,
        false,
        tolerance,
        maxPerSide,
      );
    }
    return SupportResistance(
      supports: List.unmodifiable(supports),
      resistances: List.unmodifiable(resistances),
      atr: atr,
    );
  }

  static List<MarketPriceZone> _dedupeZones(
    List<MarketPriceZone> zones,
    double tolerance,
    int limit,
  ) {
    final out = <MarketPriceZone>[];
    for (final zone in zones) {
      final overlaps = out.any(
        (existing) =>
            (existing.center - zone.center).abs() <= tolerance * 1.4 ||
            _overlapRatio(existing, zone) >= 0.35,
      );
      if (!overlaps) out.add(zone);
      if (out.length >= limit) break;
    }
    return out;
  }

  static double _overlapRatio(MarketPriceZone a, MarketPriceZone b) {
    final overlap = math.min(a.high, b.high) - math.max(a.low, b.low);
    if (overlap <= 0) return 0;
    return overlap / math.max(1e-9, math.min(a.width, b.width));
  }

  static List<MarketPriceZone> _fallbackZones(
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
    final out = <MarketPriceZone>[];
    for (final value in candidates) {
      final halfWidth = math.max(tolerance * 0.55, value * 0.001);
      final low = value - halfWidth;
      final high = value + halfWidth;
      final valid = support
          ? high < close - tolerance * 0.05
          : low > close + tolerance * 0.05;
      if (!valid) continue;
      final zone = MarketPriceZone(
        low: low,
        high: high,
        kind: support ? MarketLevelKind.support : MarketLevelKind.resistance,
        score: 0.8,
        touches: 1,
        lastIndex: bars.length - 1,
      );
      if (out.every(
        (existing) => (existing.center - zone.center).abs() > tolerance * 1.4,
      )) {
        out.add(zone);
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
  _Cluster(this.center, this.kind, this.points, this.lastIndex)
      : averageVolume = points.isEmpty ? 0 : points.first.volume;

  double center;
  final MarketLevelKind kind;
  final List<_Pivot> points;
  int lastIndex;
  double averageVolume = 0;

  int get touches => points.length;

  void add(_Pivot pivot) {
    final total = center * points.length + pivot.price;
    points.add(pivot);
    center = total / points.length;
    lastIndex = math.max(lastIndex, pivot.index);
    averageVolume = points.fold<double>(0, (sum, point) => sum + point.volume) /
        points.length;
  }

  MarketPriceZone toZone({
    required double score,
    required double minimumHalfWidth,
    required double maximumHalfWidth,
  }) {
    var low = points.first.price;
    var high = points.first.price;
    for (final point in points.skip(1)) {
      low = math.min(low, point.price);
      high = math.max(high, point.price);
    }
    final halfWidth = ((high - low) / 2).clamp(
      minimumHalfWidth,
      math.max(minimumHalfWidth, maximumHalfWidth),
    );
    return MarketPriceZone(
      low: center - halfWidth,
      high: center + halfWidth,
      kind: kind,
      score: score,
      touches: touches,
      lastIndex: lastIndex,
    );
  }
}
