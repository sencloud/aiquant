import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/market_period.dart';
import 'package:fincept_app/core/utils/china_market.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Tushare 期货原生后缀保持一致', () {
    expect(ChinaMarket.normalizeSymbol('IF2612.CFFEX'), 'IF2612.CFX');
    expect(ChinaMarket.normalizeSymbol('SR2611.CZC'), 'SR2611.ZCE');
    expect(ChinaMarket.normalizeSymbol('RB2610.SHFE'), 'RB2610.SHF');
    expect(ChinaMarket.isFuture('IF2612.CFX'), isTrue);
    expect(ChinaMarket.isFuture('SR2611.ZCE'), isTrue);
  });

  CandlePoint candle(
    DateTime date, {
    required double open,
    required double close,
    required double high,
    required double low,
    required double volume,
  }) {
    return CandlePoint(
      date: date,
      open: open,
      close: close,
      high: high,
      low: low,
      vol: volume,
    );
  }

  test('周线按自然周聚合 OHLC 与成交量', () {
    final rows = [
      candle(
        DateTime(2026, 10, 26),
        open: 10,
        close: 11,
        high: 12,
        low: 9,
        volume: 100,
      ),
      candle(
        DateTime(2026, 10, 27),
        open: 11,
        close: 10.5,
        high: 11.8,
        low: 10,
        volume: 200,
      ),
      candle(
        DateTime(2026, 10, 30),
        open: 10.5,
        close: 12,
        high: 12.5,
        low: 10.2,
        volume: 300,
      ),
      candle(
        DateTime(2026, 11, 2),
        open: 12,
        close: 11.5,
        high: 12.2,
        low: 11,
        volume: 400,
      ),
    ];

    final weekly = CandleAggregator.aggregate(rows, MarketPeriod.oneWeek);

    expect(weekly, hasLength(2));
    expect(weekly.first.open, 10);
    expect(weekly.first.close, 12);
    expect(weekly.first.high, 12.5);
    expect(weekly.first.low, 9);
    expect(weekly.first.vol, 600);
    expect(weekly.last.pctChg, closeTo(-4.166, 0.001));
  });

  test('月线跨月切分且按时间升序', () {
    final rows = [
      candle(
        DateTime(2026, 9, 30),
        open: 8,
        close: 9,
        high: 9.5,
        low: 7.8,
        volume: 10,
      ),
      candle(
        DateTime(2026, 10, 9),
        open: 9,
        close: 10,
        high: 10.5,
        low: 8.9,
        volume: 20,
      ),
      candle(
        DateTime(2026, 10, 30),
        open: 10,
        close: 11,
        high: 11.2,
        low: 9.8,
        volume: 30,
      ),
    ];

    final monthly = CandleAggregator.aggregate(rows, MarketPeriod.oneMonth);

    expect(monthly, hasLength(2));
    expect(monthly.first.date.month, 9);
    expect(monthly.last.date.month, 10);
    expect(monthly.last.open, 9);
    expect(monthly.last.close, 11);
    expect(monthly.last.vol, 50);
  });
}
