import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/services/market_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('从摆动高低点找出最近支撑与阻力', () {
    final candles = <CandlePoint>[];
    var price = 100.0;
    for (var i = 0; i < 80; i++) {
      final cycle = i % 10;
      final open = price;
      if (i < 79) {
        if (cycle < 5) {
          price += 0.35;
        } else {
          price -= 0.25;
        }
      }
      if (i == 14 || i == 34 || i == 54) price = 104;
      if (i == 24 || i == 44 || i == 64) price = 94;
      final close = price;
      candles.add(
        CandlePoint(
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          open: open,
          close: close,
          high: [open, close].reduce((a, b) => a > b ? a : b) + 0.2,
          low: [open, close].reduce((a, b) => a < b ? a : b) - 0.2,
          vol: 1000 + i * 20,
        ),
      );
    }

    final result = MarketLevelAnalyzer.analyze(candles);

    expect(result.supports, isNotEmpty);
    expect(result.resistances, isNotEmpty);
    expect(result.atr, greaterThan(0));
    expect(result.supports.first.width, greaterThan(0));
    expect(result.resistances.first.width, greaterThan(0));
    expect(
      result.supports.every((zone) => zone.high < candles.last.close),
      isTrue,
    );
    expect(
      result.resistances.every((zone) => zone.low > candles.last.close),
      isTrue,
    );
  });

  test('数据不足时不虚构价位', () {
    final result = MarketLevelAnalyzer.analyze([
      CandlePoint(date: DateTime(2026), close: 10),
      CandlePoint(date: DateTime(2026, 1, 2), close: 11),
    ]);
    expect(result.supports, isEmpty);
    expect(result.resistances, isEmpty);
  });
}
