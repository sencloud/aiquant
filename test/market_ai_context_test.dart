import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/market_period.dart';
import 'package:fincept_app/services/market_ai_context.dart';
import 'package:fincept_app/services/market_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 1, 1);
  final candles = List.generate(80, (i) {
    final open = 100 + i * 0.2 + (i % 5);
    final close = open + (i.isEven ? 0.8 : -0.45);
    return CandlePoint(
      date: start.add(Duration(days: i)),
      open: open,
      close: close,
      high: [open, close].reduce((a, b) => a > b ? a : b) + 1,
      low: [open, close].reduce((a, b) => a < b ? a : b) - 1,
      vol: 10000 + i * 70,
    );
  });
  final snapshot = MarketAiSnapshot(
    name: '贵州茅台',
    code: '600519.SH',
    assetClass: '股票',
    period: MarketPeriod.oneDay,
    asOf: candles.last.date,
    activeIndex: candles.length - 1,
    totalBars: 120,
    isReplay: true,
    candles: candles,
    levels: MarketLevelAnalyzer.analyze(candles),
  );

  test('提示词自动写入当前品种、指标、区间与回放边界', () {
    final prompt = MarketAiPromptBuilder.systemPrompt(
      snapshot,
      MarketAiQuestion.entry,
    );

    expect(prompt, contains('贵州茅台（600519.SH，股票）'));
    expect(prompt, contains('回放模式'));
    expect(prompt, contains('MA20'));
    expect(prompt, contains('支撑区间'));
    expect(prompt, contains('阻力区间'));
    expect(prompt, contains('空仓是否适合新建仓'));
    expect(prompt, contains('已有持仓是否适合补仓'));
    expect(prompt, contains('不构成投资建议'));
  });

  test('缺少持仓数据时本地速读不伪造止损建议', () {
    final answer = MarketAiPromptBuilder.localAnswer(
      snapshot,
      MarketAiQuestion.stopLoss,
    );

    expect(answer, contains('缺少持仓成本、仓位和可承受亏损'));
    expect(answer, contains('最近支撑'));
    expect(answer, contains('AI分析仅供盘面参考'));
  });
}
