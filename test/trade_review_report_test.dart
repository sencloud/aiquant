import 'dart:convert';

import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/screens/trade_review/trade_review_widgets.dart';
import 'package:fincept_app/services/trade_review_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report survives local JSON round trip', () {
    final report = const TradeReviewEngine().analyze(
      now: DateTime(2026, 11, 22, 10, 30),
      brokerHint: '测试券商',
      trades: [
        ParsedTrade(
          occurredAt: DateTime(2026, 11, 1, 9, 35),
          symbol: '600519',
          name: '贵州茅台',
          side: TradeSide.buy,
          quantity: 100,
          price: 1500,
          fee: 5,
        ),
        ParsedTrade(
          occurredAt: DateTime(2026, 11, 2, 14, 10),
          symbol: '600519',
          name: '贵州茅台',
          side: TradeSide.sell,
          quantity: 100,
          price: 1510,
          fee: 5,
          sourceIndex: 1,
        ),
      ],
    );

    final decoded = TradeReviewReport.fromJson(
      jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.id, report.id);
    expect(decoded.trades.length, 2);
    expect(decoded.trades.first.occurredAt.hour, 9);
    expect(decoded.metrics.realizedPnl, closeTo(990, 0.001));
    expect(decoded.logic, isNotEmpty);
    expect(decoded.problems, isNotEmpty);
    expect(decoded.improvements, isNotEmpty);
  });

  test('money formatting keeps the loss sign', () {
    expect(formatTradeMoney(-1234.5), '-¥1,234.50');
    expect(formatTradeMoney(1234.5), '+¥1,234.50');
    expect(formatTradeMoney(-0.5, currency: 'USD'), '-\$0.50');
  });
}
