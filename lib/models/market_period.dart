import 'instrument.dart';

/// K 线周期。日内周期直接使用 Tushare 分钟行情，周/月线由日线聚合。
enum MarketPeriod {
  fiveMinutes,
  fifteenMinutes,
  sixtyMinutes,
  oneDay,
  oneWeek,
  oneMonth,
}

extension MarketPeriodX on MarketPeriod {
  String get label {
    switch (this) {
      case MarketPeriod.fiveMinutes:
        return '5分';
      case MarketPeriod.fifteenMinutes:
        return '15分';
      case MarketPeriod.sixtyMinutes:
        return '1小时';
      case MarketPeriod.oneDay:
        return '1天';
      case MarketPeriod.oneWeek:
        return '1周';
      case MarketPeriod.oneMonth:
        return '1月';
    }
  }

  String get longLabel {
    switch (this) {
      case MarketPeriod.fiveMinutes:
        return '5 分钟';
      case MarketPeriod.fifteenMinutes:
        return '15 分钟';
      case MarketPeriod.sixtyMinutes:
        return '1 小时';
      case MarketPeriod.oneDay:
        return '日线';
      case MarketPeriod.oneWeek:
        return '周线';
      case MarketPeriod.oneMonth:
        return '月线';
    }
  }

  String get tushareFrequency {
    switch (this) {
      case MarketPeriod.fiveMinutes:
        return '5min';
      case MarketPeriod.fifteenMinutes:
        return '15min';
      case MarketPeriod.sixtyMinutes:
        return '60min';
      case MarketPeriod.oneDay:
      case MarketPeriod.oneWeek:
      case MarketPeriod.oneMonth:
        return '';
    }
  }

  bool get isIntraday => switch (this) {
        MarketPeriod.fiveMinutes ||
        MarketPeriod.fifteenMinutes ||
        MarketPeriod.sixtyMinutes =>
          true,
        _ => false,
      };

  /// 分钟接口只拉近期窗口，避免单次结果超过 Tushare 的行数上限。
  Duration get historyWindow {
    switch (this) {
      case MarketPeriod.fiveMinutes:
        return const Duration(days: 35);
      case MarketPeriod.fifteenMinutes:
        return const Duration(days: 110);
      case MarketPeriod.sixtyMinutes:
        return const Duration(days: 370);
      case MarketPeriod.oneDay:
        return const Duration(days: 900);
      case MarketPeriod.oneWeek:
        return const Duration(days: 365 * 6);
      case MarketPeriod.oneMonth:
        return const Duration(days: 365 * 14);
    }
  }

  int get preferredVisibleBars {
    switch (this) {
      case MarketPeriod.fiveMinutes:
      case MarketPeriod.fifteenMinutes:
        return 96;
      case MarketPeriod.sixtyMinutes:
        return 88;
      case MarketPeriod.oneDay:
        return 120;
      case MarketPeriod.oneWeek:
        return 104;
      case MarketPeriod.oneMonth:
        return 84;
    }
  }
}

/// 将日线聚合成周线或月线。输入会先按时间升序排列。
class CandleAggregator {
  CandleAggregator._();

  static List<CandlePoint> aggregate(
    List<CandlePoint> candles,
    MarketPeriod period,
  ) {
    if (candles.isEmpty || !_canAggregate(period)) {
      return List<CandlePoint>.unmodifiable(candles);
    }
    final sorted = [...candles]..sort((a, b) => a.date.compareTo(b.date));
    final groups = <String, List<CandlePoint>>{};
    for (final candle in sorted) {
      groups.putIfAbsent(_bucketKey(candle.date, period), () => []).add(candle);
    }

    final out = <CandlePoint>[];
    double? previousClose;
    for (final group in groups.values) {
      final first = group.first;
      final last = group.last;
      var high = last.close;
      var low = last.close;
      var volume = 0.0;
      var hasVolume = false;
      for (final candle in group) {
        high = _max(high, candle.high ?? candle.close);
        low = _min(low, candle.low ?? candle.close);
        final v = candle.vol;
        if (v != null) {
          volume += v;
          hasVolume = true;
        }
      }
      final pct = previousClose != null && previousClose != 0
          ? (last.close - previousClose) / previousClose * 100
          : last.pctChg;
      out.add(
        CandlePoint(
          date: last.date,
          open: first.open ?? first.close,
          high: high,
          low: low,
          close: last.close,
          vol: hasVolume ? volume : null,
          pctChg: pct,
        ),
      );
      previousClose = last.close;
    }
    return List<CandlePoint>.unmodifiable(out);
  }

  static bool _canAggregate(MarketPeriod period) =>
      period == MarketPeriod.oneWeek || period == MarketPeriod.oneMonth;

  static double _max(double a, double b) => a > b ? a : b;

  static double _min(double a, double b) => a < b ? a : b;

  static String _bucketKey(DateTime date, MarketPeriod period) {
    if (period == MarketPeriod.oneMonth) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}';
    }
    final monday = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - DateTime.monday));
    return '${monday.year}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }
}
