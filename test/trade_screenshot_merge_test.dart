import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/services/trade_screenshot_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ParsedTrade trade({
    required int minute,
    String symbol = '600519',
    String name = '贵州茅台',
    TradeSide side = TradeSide.buy,
    double quantity = 100,
    double price = 1500,
    double fee = 5,
  }) {
    return ParsedTrade(
      occurredAt: DateTime(2026, 11, 20, 9, minute),
      symbol: symbol,
      name: name,
      side: side,
      quantity: quantity,
      price: price,
      fee: fee,
    );
  }

  ParsedTradesResult result(
    List<ParsedTrade> trades, {
    String currency = 'CNY',
    List<String> warnings = const [],
  }) {
    return ParsedTradesResult(
      brokerHint: '测试券商',
      currency: currency,
      trades: trades,
      warnings: warnings,
    );
  }

  test('重叠截图按成交指纹合并，并保留截图内真实重复成交', () {
    final first = trade(minute: 1);
    final second = trade(minute: 2, symbol: '000001', name: '平安银行');
    final third = trade(
      minute: 3,
      symbol: '000001',
      name: '平安银行',
      side: TradeSide.sell,
    );

    final merged = mergeParsedTradeResults(
      [
        result([first, second, first]),
        result([first, third, second]),
      ],
      screenshotCount: 2,
      failureWarnings: const ['第 2 张未识别：图片过于模糊。'],
    );

    expect(merged.trades, hasLength(4));
    expect(
      merged.trades.where(
        (item) =>
            item.symbol == '600519' &&
            item.side == TradeSide.buy &&
            item.occurredAt.minute == 1,
      ),
      hasLength(2),
    );
    expect(merged.trades.map((item) => item.occurredAt.minute), [1, 1, 2, 3]);
    expect(merged.screenshotCount, 2);
    expect(merged.successfulScreenshotCount, 2);
    expect(merged.duplicateTradeCount, 2);
    expect(merged.warnings, contains('第 2 张未识别：图片过于模糊。'));
    expect(
      merged.warnings,
      contains('多张截图有 2 笔重叠成交，已自动合并。'),
    );
  });

  test('相邻截图里仅出现一次的重叠成交被移除', () {
    final overlap = trade(minute: 5);
    final next = trade(minute: 6, symbol: '510300', name: '沪深300ETF');

    final merged = mergeParsedTradeResults(
      [
        result([overlap]),
        result([overlap, next]),
      ],
      screenshotCount: 2,
    );

    expect(merged.trades, hasLength(2));
    expect(merged.duplicateTradeCount, 1);
  });

  test('合并结果去除重复警告并提示多币种', () {
    final merged = mergeParsedTradeResults(
      [
        result(
          [trade(minute: 1)],
          currency: 'CNY',
          warnings: const ['请核对手续费'],
        ),
        result(
          [trade(minute: 2)],
          currency: 'USD',
          warnings: const ['请核对手续费'],
        ),
      ],
      screenshotCount: 2,
    );

    expect(merged.currency, 'CNY');
    expect(
      merged.warnings.where((warning) => warning == '请核对手续费'),
      hasLength(1),
    );
    expect(
      merged.warnings,
      contains('截图里出现了多种币种，请逐笔核对币种口径。'),
    );
  });

  test('批量识别限制并发，部分失败时保留成功结果', () async {
    final parser = _FakeTradeParser();
    final progress = <String>[];

    final merged = await parser.parseBatch(
      [
        _screenshot('first'),
        _screenshot('overlap'),
        _screenshot('bad'),
        _screenshot('next'),
      ],
      concurrency: 2,
      onProgress: (completed, total) => progress.add('$completed/$total'),
    );

    expect(parser.maxActive, lessThanOrEqualTo(2));
    expect(progress, ['0/4', '1/4', '2/4', '3/4', '4/4']);
    expect(merged.trades, hasLength(2));
    expect(merged.duplicateTradeCount, 1);
    expect(merged.successfulScreenshotCount, 3);
    expect(merged.warnings, hasLength(2));
    expect(
      merged.warnings,
      contains(contains('第 3 张未识别')),
    );
  });

  test('全部截图失败时返回可展示的批量错误', () async {
    final parser = _FakeTradeParser();

    await expectLater(
      parser.parseBatch([_screenshot('bad'), _screenshot('bad')]),
      throwsA(
        isA<TradeParseException>()
            .having(
              (error) => error.kind,
              'kind',
              TradeParseFailureKind.noTrades,
            )
            .having(
              (error) => error.message,
              'message',
              startsWith('2 张截图都没有识别成功。'),
            ),
      ),
    );
  });
}

PickedTradeScreenshot _screenshot(String key) {
  return PickedTradeScreenshot(
    bytes: Uint8List.fromList([1]),
    mimeType: key,
  );
}

class _FakeTradeParser extends TradeScreenshotParser {
  _FakeTradeParser() : super(dio: Dio());

  int _active = 0;
  int maxActive = 0;

  @override
  Future<ParsedTradesResult> parse({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    _active++;
    if (_active > maxActive) maxActive = _active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (mimeType == 'bad') {
        throw const TradeParseException(
          TradeParseFailureKind.noTrades,
          '没有识别到成交。',
        );
      }
      final isNext = mimeType == 'next';
      return ParsedTradesResult(
        brokerHint: '测试券商',
        currency: 'CNY',
        trades: [
          ParsedTrade(
            occurredAt: DateTime(2026, 11, 20, 9, isNext ? 2 : 1),
            symbol: isNext ? '000001' : '600519',
            name: isNext ? '平安银行' : '贵州茅台',
            side: TradeSide.buy,
            quantity: 100,
            price: 10,
          ),
        ],
        warnings: const [],
      );
    } finally {
      _active--;
    }
  }
}
