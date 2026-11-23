import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/services/trade_screenshot_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ParsedTrade trade({
    required int minute,
    DateTime? at,
    String symbol = '600519',
    String name = '贵州茅台',
    TradeSide side = TradeSide.buy,
    double quantity = 100,
    double price = 1500,
    double fee = 5,
  }) {
    return ParsedTrade(
      occurredAt: at ?? DateTime(2026, 11, 20, 9, minute),
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

  test('两张滑动截图识别 4+7 笔后保留 9 笔并合并 2 笔页间重叠', () {
    final trades = [
      trade(
        at: DateTime(2026, 11, 20, 10, 30, 36),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 2400,
        price: 4.171,
        fee: 2.50,
      ),
      trade(
        at: DateTime(2026, 11, 17, 9, 30, 4),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 2400,
        price: 4.217,
        fee: 2.53,
      ),
      trade(
        at: DateTime(2026, 10, 30, 11, 26, 7),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 1200,
        price: 4.274,
        fee: 1.28,
      ),
      trade(
        at: DateTime(2026, 10, 30, 9, 55, 7),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 1200,
        price: 4.244,
        fee: 1.27,
      ),
      trade(
        at: DateTime(2026, 10, 23, 14, 39, 4),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        side: TradeSide.sell,
        quantity: 2300,
        price: 4.364,
        fee: 2.51,
      ),
      trade(
        at: DateTime(2026, 10, 23, 9, 32, 42),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 2300,
        price: 4.240,
        fee: 2.44,
      ),
      trade(
        at: DateTime(2026, 10, 22, 13, 59, 13),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 2400,
        price: 4.306,
        fee: 2.58,
      ),
      trade(
        at: DateTime(2026, 9, 17, 10, 11, 3),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 1000,
        price: 4.730,
        fee: 1.18,
      ),
      trade(
        at: DateTime(2026, 8, 21, 13, 27, 46),
        minute: 0,
        symbol: '159919',
        name: '沪深300ETF嘉实',
        quantity: 1000,
        price: 4.885,
        fee: 1.22,
      ),
    ];

    final merged = mergeParsedTradeResults(
      [
        result(trades.sublist(0, 4)),
        result(trades.sublist(2)),
      ],
      screenshotCount: 2,
    );

    expect(merged.trades, hasLength(9));
    expect(
      merged.trades.where((item) => item.side == TradeSide.buy),
      hasLength(8),
    );
    expect(
      merged.trades.where((item) => item.side == TradeSide.sell),
      hasLength(1),
    );
    expect(merged.successfulScreenshotCount, 2);
    expect(merged.duplicateTradeCount, 2);
  });

  test('重叠成交容忍 OCR 的秒级时间差、名称空格和价格误差', () {
    final first = trade(
      at: DateTime(2026, 11, 20, 9, 30, 4),
      minute: 0,
      symbol: '',
      name: '沪深 300 ETF 嘉实',
      quantity: 2400,
      price: 4.171,
      fee: 2.50,
    );
    final second = trade(
      at: DateTime(2026, 11, 20, 9, 30, 49),
      minute: 0,
      symbol: '159919',
      name: '沪深300ETF嘉实股份有限公司',
      quantity: 2400,
      price: 4.1713,
      fee: 2.53,
    );

    final merged = mergeParsedTradeResults(
      [
        result([first]),
        result([second]),
      ],
      screenshotCount: 2,
    );

    expect(merged.trades, hasLength(1));
    expect(merged.duplicateTradeCount, 1);
  });

  test('容差链 A≈B、B≈C 不会误把 A 与 C 合并', () {
    final a = trade(
      at: DateTime(2026, 11, 20, 9, 30, 0),
      minute: 0,
    );
    final b = trade(
      at: DateTime(2026, 11, 20, 9, 31, 0),
      minute: 1,
    );
    final c = trade(
      at: DateTime(2026, 11, 20, 9, 32, 0),
      minute: 2,
    );

    final merged = mergeParsedTradeResults(
      [
        result([a]),
        result([b]),
        result([c]),
      ],
      screenshotCount: 3,
    );

    expect(merged.trades, hasLength(2));
    expect(merged.duplicateTradeCount, 1);
  });

  test('同一成交在不相邻截图中再次出现时不会误删', () {
    final repeated = trade(minute: 5);
    final middle = trade(minute: 6, symbol: '510300', name: '沪深300ETF');

    final merged = mergeParsedTradeResults(
      [
        result([repeated]),
        result([middle]),
        result([repeated]),
      ],
      screenshotCount: 3,
    );

    expect(merged.trades, hasLength(3));
    expect(merged.duplicateTradeCount, 0);
  });

  test('中间截图识别失败时，不跨未知页面合并相同成交', () {
    final repeated = trade(minute: 5);

    final merged = mergeParsedTradeResults(
      [
        result([repeated]),
        result([repeated]),
      ],
      screenshotCount: 3,
      sourceScreenshotIndices: const [0, 2],
    );

    expect(merged.trades, hasLength(2));
    expect(merged.duplicateTradeCount, 0);
  });

  test('批量识别遇到网络错误时自动重试并保留成功结果', () async {
    final parser = _RetryingTradeParser();

    final merged = await parser.parseBatch(
      [_screenshot('retry'), _screenshot('ok')],
    );

    expect(parser.attempts['retry'], 2);
    expect(merged.successfulScreenshotCount, 2);
    expect(merged.trades, hasLength(2));
  });

  test('可重试错误最终失败时在提示里说明重试次数', () async {
    final parser = _AlwaysNetworkFailTradeParser();

    await expectLater(
      parser.parseBatch([_screenshot('network')]),
      throwsA(
        isA<TradeParseException>().having(
          (error) => error.message,
          'message',
          contains('已自动重试 2 次'),
        ),
      ),
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

class _RetryingTradeParser extends TradeScreenshotParser {
  _RetryingTradeParser() : super(dio: Dio(), retryDelay: Duration.zero);

  final attempts = <String, int>{};

  @override
  Future<ParsedTradesResult> parse({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    final attempt = (attempts[mimeType] ?? 0) + 1;
    attempts[mimeType] = attempt;
    if (mimeType == 'retry' && attempt == 1) {
      throw const TradeParseException(
        TradeParseFailureKind.network,
        '网络连接失败。',
      );
    }
    return ParsedTradesResult(
      brokerHint: '测试券商',
      currency: 'CNY',
      trades: [
        ParsedTrade(
          occurredAt: DateTime(2026, 11, 20, 9, mimeType == 'retry' ? 30 : 31),
          symbol: mimeType == 'retry' ? '159919' : '000001',
          name: mimeType == 'retry' ? '沪深300ETF嘉实' : '平安银行',
          side: TradeSide.buy,
          quantity: 100,
          price: 10,
        ),
      ],
      warnings: const [],
    );
  }
}

class _AlwaysNetworkFailTradeParser extends TradeScreenshotParser {
  _AlwaysNetworkFailTradeParser()
      : super(dio: Dio(), retryDelay: Duration.zero);

  @override
  Future<ParsedTradesResult> parse({
    required List<int> imageBytes,
    required String mimeType,
  }) async {
    throw const TradeParseException(
      TradeParseFailureKind.network,
      '网络连接失败。',
    );
  }
}
