import 'dart:math' as math;

import '../core/utils/china_market.dart';
import '../models/instrument.dart';
import '../models/market_period.dart';
import 'market_realtime_service.dart';

class RealtimeCandleUpdate {
  const RealtimeCandleUpdate({
    required this.candles,
    required this.cumulativeVolume,
    required this.appended,
  });

  final List<CandlePoint> candles;
  final int cumulativeVolume;
  final bool appended;
}

/// Merges a snapshot quote into the latest chart bar.
///
/// The backend quote only contains a snapshot, not per-minute OHLC. Therefore
/// the helper updates the current bar and creates the next incomplete bucket
/// when needed. The next history reload replaces synthesized bars with
/// Tushare's authoritative OHLC once that period closes.
class RealtimeCandleMerger {
  RealtimeCandleMerger._();

  static RealtimeCandleUpdate? merge({
    required List<CandlePoint> candles,
    required String tsCode,
    required MarketPeriod period,
    required RealtimeQuote quote,
    int? previousCumulativeVolume,
  }) {
    if (candles.isEmpty ||
        !quote.last.isFinite ||
        quote.last <= 0 ||
        quote.tsCode.isNotEmpty && quote.tsCode != tsCode) {
      return null;
    }

    final bars = [...candles]..sort((a, b) => a.date.compareTo(b.date));
    final last = bars.last;
    final quoteTime = quote.effectiveTime;
    final bucket = _bucketTime(quoteTime, period, tsCode);
    final sameBar = _sameBucket(last.date, bucket, period);
    if (!sameBar && bucket.isBefore(last.date)) {
      // A delayed provider can return an older snapshot after a fresher one.
      return RealtimeCandleUpdate(
        candles: List<CandlePoint>.unmodifiable(bars),
        cumulativeVolume: previousCumulativeVolume ?? quote.volume,
        appended: false,
      );
    }

    final volumeDelta = previousCumulativeVolume == null ||
            quote.volume < previousCumulativeVolume
        ? null
        : quote.volume - previousCumulativeVolume;
    final target = sameBar ? last : null;
    final previousClose = target == null
        ? last.close
        : bars.length > 1
            ? bars[bars.length - 2].close
            : last.open ?? last.close;
    final pctChg = previousClose == 0
        ? quote.pctChg
        : (quote.last - previousClose) / previousClose * 100;
    final barDate = sameBar ? target!.date : bucket;

    if (period == MarketPeriod.oneWeek || period == MarketPeriod.oneMonth) {
      if (quoteTime.isBefore(last.date)) return _unchanged(bars, quote);
    }

    final merged = CandlePoint(
      date: period == MarketPeriod.oneWeek || period == MarketPeriod.oneMonth
          ? quoteTime
          : barDate,
      open: sameBar ? target!.open ?? target.close : _newBarOpen(quote, period),
      close: quote.last,
      high: _high(sameBar ? target : null, quote, period),
      low: _low(sameBar ? target : null, quote, period),
      pctChg: pctChg,
      vol: _mergedVolume(
        existing: sameBar ? target : null,
        quote: quote,
        period: period,
        delta: volumeDelta,
        previousCumulativeVolume: previousCumulativeVolume,
      ),
    );

    if (sameBar) {
      bars[bars.length - 1] = merged;
    } else {
      bars.add(merged);
    }
    return RealtimeCandleUpdate(
      candles: List<CandlePoint>.unmodifiable(bars),
      cumulativeVolume: quote.volume,
      appended: !sameBar,
    );
  }

  static RealtimeCandleUpdate _unchanged(
    List<CandlePoint> bars,
    RealtimeQuote quote,
  ) {
    return RealtimeCandleUpdate(
      candles: List<CandlePoint>.unmodifiable(bars),
      cumulativeVolume: quote.volume,
      appended: false,
    );
  }

  static double _newBarOpen(RealtimeQuote quote, MarketPeriod period) {
    if (period == MarketPeriod.oneDay ||
        period == MarketPeriod.oneWeek ||
        period == MarketPeriod.oneMonth) {
      return quote.open > 0 ? quote.open : quote.last;
    }
    return quote.last;
  }

  static double _high(
    CandlePoint? existing,
    RealtimeQuote quote,
    MarketPeriod period,
  ) {
    var high = math
        .max(existing?.high ?? existing?.close ?? quote.last, quote.last)
        .toDouble();
    if (!period.isIntraday && quote.high > 0) {
      high = math.max(high, quote.high).toDouble();
    }
    return high;
  }

  static double _low(
    CandlePoint? existing,
    RealtimeQuote quote,
    MarketPeriod period,
  ) {
    var low = math
        .min(existing?.low ?? existing?.close ?? quote.last, quote.last)
        .toDouble();
    if (!period.isIntraday && quote.low > 0) {
      low = math.min(low, quote.low).toDouble();
    }
    return low;
  }

  static double? _mergedVolume({
    required CandlePoint? existing,
    required RealtimeQuote quote,
    required MarketPeriod period,
    required int? delta,
    required int? previousCumulativeVolume,
  }) {
    if (quote.volume <= 0) return existing?.vol;
    if (period == MarketPeriod.oneDay) return quote.volume.toDouble();
    if (period == MarketPeriod.oneWeek || period == MarketPeriod.oneMonth) {
      if (existing?.vol != null && delta != null) {
        return existing!.vol! + math.max(0, delta);
      }
      return existing?.vol ?? quote.volume.toDouble();
    }
    if (existing?.vol != null) {
      if (previousCumulativeVolume != null && delta != null) {
        return existing!.vol! + math.max(0, delta);
      }
      return existing!.vol;
    }
    if (delta != null && delta >= 0) return delta.toDouble();
    return 0;
  }

  static bool _sameBucket(
    DateTime candle,
    DateTime bucket,
    MarketPeriod period,
  ) {
    switch (period) {
      case MarketPeriod.fiveMinutes:
      case MarketPeriod.fifteenMinutes:
      case MarketPeriod.sixtyMinutes:
        return candle.year == bucket.year &&
            candle.month == bucket.month &&
            candle.day == bucket.day &&
            candle.hour == bucket.hour &&
            candle.minute == bucket.minute;
      case MarketPeriod.oneDay:
        return _sameDate(candle, bucket);
      case MarketPeriod.oneWeek:
        return _weekKey(candle) == _weekKey(bucket);
      case MarketPeriod.oneMonth:
        return candle.year == bucket.year && candle.month == bucket.month;
    }
  }

  static DateTime _bucketTime(
    DateTime source,
    MarketPeriod period,
    String tsCode,
  ) {
    switch (period) {
      case MarketPeriod.oneDay:
        return DateTime(source.year, source.month, source.day);
      case MarketPeriod.oneWeek:
      case MarketPeriod.oneMonth:
        return DateTime(source.year, source.month, source.day);
      case MarketPeriod.fiveMinutes:
        return _intradayBucket(source, 5, ChinaMarket.isFuture(tsCode), tsCode);
      case MarketPeriod.fifteenMinutes:
        return _intradayBucket(
            source, 15, ChinaMarket.isFuture(tsCode), tsCode);
      case MarketPeriod.sixtyMinutes:
        return _intradayBucket(
            source, 60, ChinaMarket.isFuture(tsCode), tsCode);
    }
  }

  static DateTime _intradayBucket(
    DateTime source,
    int minutes,
    bool future,
    String tsCode,
  ) {
    final sessions = _sessionsFor(source, future, tsCode);
    for (final session in sessions) {
      if (!source.isBefore(session.start) && !source.isAfter(session.end)) {
        return _roundUpInSession(source, session, minutes);
      }
    }

    _Session? latest;
    for (final session in sessions) {
      if (!session.end.isAfter(source) &&
          (latest == null || session.end.isAfter(latest.end))) {
        latest = session;
      }
    }
    return latest?.end ?? source;
  }

  static DateTime _roundUpInSession(
    DateTime source,
    _Session session,
    int minutes,
  ) {
    final elapsed = source.difference(session.start);
    final step = Duration(minutes: minutes);
    if (elapsed <= Duration.zero) return session.start;
    final multiplier = (elapsed.inSeconds / step.inSeconds).ceil();
    final bucket = session.start.add(step * multiplier);
    return bucket.isAfter(session.end) ? session.end : bucket;
  }

  static List<_Session> _sessionsFor(
    DateTime day,
    bool future,
    String tsCode,
  ) {
    final out = <_Session>[];
    DateTime at(int dayOffset, int hour, int minute) =>
        DateTime(day.year, day.month, day.day + dayOffset, hour, minute);

    if (!future || _isFinancialFuture(tsCode)) {
      out.add(_Session(at(0, 9, 30), at(0, 11, 30)));
      out.add(_Session(at(0, 13, 0), at(0, 15, 0)));
    } else {
      out.add(_Session(at(0, 9, 0), at(0, 10, 15)));
      out.add(_Session(at(0, 10, 30), at(0, 11, 30)));
      out.add(_Session(at(0, 13, 30), at(0, 15, 0)));
    }
    if (future) {
      // CFFEX treasury futures close at 15:15; include it as a final bucket.
      if (_isTreasuryFuture(tsCode)) {
        out.add(_Session(at(0, 15, 0), at(0, 15, 15)));
      }
      // Most night sessions end at 23:00, 01:00 or 02:30. The actual quote
      // timestamp determines the bar, so using the widest session does not
      // create bars after a product stops ticking.
      out.add(_Session(at(0, 21, 0), at(1, 3, 0)));
    }
    return out;
  }

  static bool _isFinancialFuture(String tsCode) {
    final code = ChinaMarket.displaySymbol(tsCode).toUpperCase();
    return RegExp(r'^(IF|IH|IC|IM|T|TF|TS|TL)').hasMatch(code);
  }

  static bool _isTreasuryFuture(String tsCode) {
    final code = ChinaMarket.displaySymbol(tsCode).toUpperCase();
    return RegExp(r'^(T|TF|TS|TL)').hasMatch(code);
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekKey(DateTime date) {
    final monday = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - DateTime.monday));
    return '${monday.year}-${monday.month}-${monday.day}';
  }
}

class _Session {
  const _Session(this.start, this.end);

  final DateTime start;
  final DateTime end;
}
