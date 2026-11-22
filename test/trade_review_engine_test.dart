import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/services/trade_review_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = TradeReviewEngine();

  ParsedTrade trade({
    required String day,
    required TradeSide side,
    required double quantity,
    required double price,
    double fee = 0,
    int sourceIndex = 0,
    String symbol = '600519',
    String name = '贵州茅台',
  }) {
    return ParsedTrade(
      occurredAt: DateTime.parse(day),
      symbol: symbol,
      name: name,
      side: side,
      quantity: quantity,
      price: price,
      fee: fee,
      sourceIndex: sourceIndex,
    );
  }

  test('advanced-first-out matching includes buy and sell fees', () {
    final report = engine.analyze(
      now: DateTime(2026, 11, 22),
      trades: [
        trade(
          day: '2026-11-01',
          side: TradeSide.buy,
          quantity: 100,
          price: 10,
          fee: 5,
        ),
        trade(
          day: '2026-11-03',
          side: TradeSide.buy,
          quantity: 100,
          price: 12,
          fee: 5,
          sourceIndex: 1,
        ),
        trade(
          day: '2026-11-05',
          side: TradeSide.sell,
          quantity: 150,
          price: 15,
          fee: 6,
          sourceIndex: 2,
        ),
      ],
    );

    expect(report.metrics.matchedSellCount, 1);
    expect(report.metrics.winningSellCount, 1);
    expect(report.metrics.openLotCount, 1);
    expect(report.metrics.realizedPnl, closeTo(636.5, 0.001));
    expect(report.metrics.totalFees, closeTo(16, 0.001));
  });

  test('unmatched sell is warned and excluded from realized pnl', () {
    final report = engine.analyze(
      trades: [
        trade(
          day: '2026-11-01',
          side: TradeSide.sell,
          quantity: 100,
          price: 10,
        ),
      ],
    );

    expect(report.metrics.realizedPnl, 0);
    expect(
      report.warnings.any((warning) => warning.contains('无法与截图中的买入配对')),
      isTrue,
    );
  });

  test('multiple symbols remain independent', () {
    final report = engine.analyze(
      trades: [
        trade(
          day: '2026-11-01',
          side: TradeSide.buy,
          quantity: 100,
          price: 10,
          symbol: '000001',
          name: '平安银行',
        ),
        trade(
          day: '2026-11-01',
          side: TradeSide.buy,
          quantity: 100,
          price: 20,
          symbol: '600000',
          name: '浦发银行',
          sourceIndex: 1,
        ),
        trade(
          day: '2026-11-02',
          side: TradeSide.sell,
          quantity: 100,
          price: 11,
          symbol: '000001',
          name: '平安银行',
          sourceIndex: 2,
        ),
      ],
    );

    expect(report.metrics.realizedPnl, closeTo(100, 0.001));
    expect(report.metrics.openLotCount, 1);
  });
}
