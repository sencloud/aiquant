import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/market_period.dart';
import 'package:fincept_app/services/market_realtime_service.dart';
import 'package:fincept_app/services/realtime_candle_merge.dart';
import 'package:flutter_test/flutter_test.dart';

RealtimeQuote quoteAt(
  DateTime time, {
  required double last,
  required int volume,
  String tsCode = '600519.SH',
  double high = 0,
  double low = 0,
}) {
  return RealtimeQuote(
    tsCode: tsCode,
    name: '测试品种',
    assetClass: 'stock',
    last: last,
    pctChg: 1,
    open: last - 1,
    high: high,
    low: low,
    preClose: last - 1,
    preSettle: 0,
    volume: volume,
    delayed: false,
    source: 'test',
    asOf: time,
    quoteTime: time,
  );
}

CandlePoint bar(
  DateTime time, {
  required double open,
  required double close,
  double? high,
  double? low,
  double? volume,
}) {
  return CandlePoint(
    date: time,
    open: open,
    close: close,
    high: high ?? close + 1,
    low: low ?? close - 1,
    vol: volume,
  );
}

void main() {
  test('同一五分钟 K 线更新收盘、极值和成交量增量', () {
    final current = bar(
      DateTime(2026, 11, 3, 9, 40),
      open: 100,
      close: 102,
      high: 103,
      low: 99,
      volume: 20,
    );
    final update = RealtimeCandleMerger.merge(
      candles: [
        bar(DateTime(2026, 11, 3, 9, 35), open: 99, close: 100),
        current,
      ],
      tsCode: '600519.SH',
      period: MarketPeriod.fiveMinutes,
      quote: quoteAt(
        DateTime(2026, 11, 3, 9, 36),
        last: 105,
        high: 120,
        low: 80,
        volume: 1000,
      ),
      previousCumulativeVolume: 900,
    )!;

    expect(update.appended, isFalse);
    expect(update.candles, hasLength(2));
    expect(update.candles.last.close, 105);
    expect(update.candles.last.high, 105);
    expect(update.candles.last.low, 99);
    expect(update.candles.last.vol, 120);
  });

  test('进入新的十五分钟桶时追加 K 线', () {
    final update = RealtimeCandleMerger.merge(
      candles: [
        bar(DateTime(2026, 11, 3, 9, 30), open: 99, close: 100),
      ],
      tsCode: '600519.SH',
      period: MarketPeriod.fifteenMinutes,
      quote: quoteAt(
        DateTime(2026, 11, 3, 9, 31),
        last: 101,
        volume: 500,
      ),
    )!;

    expect(update.appended, isTrue);
    expect(update.candles, hasLength(2));
    expect(update.candles.last.date, DateTime(2026, 11, 3, 9, 45));
    expect(update.candles.last.open, 101);
    expect(update.candles.last.close, 101);
  });

  test('日线同一交易日更新并在下一交易日追加', () {
    final candles = [
      bar(DateTime(2026, 11, 2), open: 99, close: 100, volume: 1000),
      bar(DateTime(2026, 11, 3), open: 100, close: 101, volume: 500),
    ];
    final sameDay = RealtimeCandleMerger.merge(
      candles: candles,
      tsCode: '600519.SH',
      period: MarketPeriod.oneDay,
      quote: quoteAt(
        DateTime(2026, 11, 3, 14),
        last: 102,
        high: 104,
        low: 98,
        volume: 800,
      ),
      previousCumulativeVolume: 500,
    )!;
    expect(sameDay.appended, isFalse);
    expect(sameDay.candles.last.high, 104);
    expect(sameDay.candles.last.low, 98);
    expect(sameDay.candles.last.vol, 800);

    final nextDay = RealtimeCandleMerger.merge(
      candles: sameDay.candles,
      tsCode: '600519.SH',
      period: MarketPeriod.oneDay,
      quote: quoteAt(
        DateTime(2026, 11, 4, 9, 31),
        last: 103,
        volume: 100,
      ),
    )!;
    expect(nextDay.appended, isTrue);
    expect(nextDay.candles.last.date, DateTime(2026, 11, 4));
    expect(nextDay.candles.last.open, 102);
  });

  test('周线同一周更新日期并保留成交量增量', () {
    final update = RealtimeCandleMerger.merge(
      candles: [
        bar(
          DateTime(2026, 11, 3),
          open: 100,
          close: 101,
          volume: 5000,
        ),
      ],
      tsCode: '600519.SH',
      period: MarketPeriod.oneWeek,
      quote: quoteAt(
        DateTime(2026, 11, 4, 10),
        last: 104,
        high: 105,
        low: 98,
        volume: 300,
      ),
      previousCumulativeVolume: 250,
    )!;

    expect(update.appended, isFalse);
    expect(update.candles.last.date, DateTime(2026, 11, 4, 10));
    expect(update.candles.last.high, 105);
    expect(update.candles.last.vol, 5050);
  });

  test('乱序旧报价不会覆盖新 K 线', () {
    final candles = [
      bar(DateTime(2026, 11, 4), open: 110, close: 112, volume: 800),
    ];
    final update = RealtimeCandleMerger.merge(
      candles: candles,
      tsCode: '600519.SH',
      period: MarketPeriod.oneDay,
      quote: quoteAt(
        DateTime(2026, 11, 3, 14),
        last: 90,
        volume: 900,
      ),
    )!;

    expect(update.appended, isFalse);
    expect(update.candles.single.close, 112);
  });

  test('累计成交量重置不会产生负成交量', () {
    final update = RealtimeCandleMerger.merge(
      candles: [
        bar(
          DateTime(2026, 11, 3, 9, 40),
          open: 100,
          close: 101,
          volume: 50,
        ),
      ],
      tsCode: '600519.SH',
      period: MarketPeriod.fiveMinutes,
      quote: quoteAt(
        DateTime(2026, 11, 3, 9, 36),
        last: 102,
        volume: 100,
      ),
      previousCumulativeVolume: 1000,
    )!;

    expect(update.candles.last.vol, 50);
  });
}
