import 'dart:math' as math;

import '../models/instrument.dart';
import '../models/market_period.dart';
import 'market_levels.dart';

enum MarketAiQuestion {
  entry,
  takeProfit,
  stopLoss,
  assess,
}

extension MarketAiQuestionX on MarketAiQuestion {
  String get label {
    switch (this) {
      case MarketAiQuestion.entry:
        return '现在能不能建仓/补仓？';
      case MarketAiQuestion.takeProfit:
        return '现在要不要止盈？';
      case MarketAiQuestion.stopLoss:
        return '现在要不要止损？';
      case MarketAiQuestion.assess:
        return '评估现在什么情况？';
    }
  }

  String get taskInstruction {
    switch (this) {
      case MarketAiQuestion.entry:
        return '分别回答“空仓是否适合新建仓”和“已有持仓是否适合补仓”。用户在问题中没有提供持仓成本、仓位、资金规模和风险预算，禁止假设这些信息。若位置风险收益比不佳，应明确说“不适合追价”或“等待条件”。';
      case MarketAiQuestion.takeProfit:
        return '用户没有提供持仓成本、仓位和已实现盈亏，不能直接判断个人是否应当止盈。先说明这一限制，再给出可观察的止盈条件：阻力区间反应、放量滞涨、趋势失效或跌破关键均线。';
      case MarketAiQuestion.stopLoss:
        return '用户没有提供持仓成本、仓位和最大可承受亏损，不能直接判断个人是否应当止损。先说明这一限制，再给出技术失效条件与关键区间，避免把固定百分比伪装成个性化建议。';
      case MarketAiQuestion.assess:
        return '用结构化方式评估当前盘面：趋势方向、价格在近期区间中的位置、量价关系、支撑阻力距离，以及最重要的一个风险点。';
    }
  }
}

class MarketAiSnapshot {
  const MarketAiSnapshot({
    required this.name,
    required this.code,
    required this.assetClass,
    required this.period,
    required this.asOf,
    required this.activeIndex,
    required this.totalBars,
    required this.isReplay,
    required this.candles,
    required this.levels,
  });

  final String name;
  final String code;
  final String assetClass;
  final MarketPeriod period;
  final DateTime asOf;
  final int activeIndex;
  final int totalBars;
  final bool isReplay;

  /// 只包含当前屏幕位置及之前的数据，回放时不会把未来 K 线交给模型。
  final List<CandlePoint> candles;
  final SupportResistance levels;
}

class MarketAiPromptBuilder {
  MarketAiPromptBuilder._();

  static String systemPrompt(
    MarketAiSnapshot snapshot,
    MarketAiQuestion question,
  ) {
    final active = snapshot.candles.last;
    final previous = snapshot.candles.length > 1
        ? snapshot.candles[snapshot.candles.length - 2]
        : null;
    final change = previous == null || previous.close == 0
        ? null
        : (active.close - previous.close) / previous.close * 100;
    final recent = snapshot.candles
        .skip(math.max(0, snapshot.candles.length - 30))
        .toList(growable: false);
    final recentLow = recent.map((e) => e.low ?? e.close).reduce(math.min);
    final recentHigh = recent.map((e) => e.high ?? e.close).reduce(math.max);
    final position = recentHigh == recentLow
        ? 0.5
        : ((active.close - recentLow) / (recentHigh - recentLow))
            .clamp(0.0, 1.0);
    final volumeAvg = _volumeAverage(recent);
    final volumeRatio =
        volumeAvg > 0 && active.vol != null ? active.vol! / volumeAvg : null;
    final ma5 = _sma(snapshot.candles, 5);
    final ma10 = _sma(snapshot.candles, 10);
    final ma20 = _sma(snapshot.candles, 20);
    final recentCloses = snapshot.candles
        .skip(math.max(0, snapshot.candles.length - 10))
        .map((e) => _price(e.close))
        .join(' → ');
    final supports = _zones(snapshot.levels.supports, 'S');
    final resistances = _zones(snapshot.levels.resistances, 'R');
    final replayNote = snapshot.isReplay
        ? '当前处于回放模式，分析截止到回放游标；不得引用游标之后的价格。'
        : '分析截止到当前屏幕最新一根 K 线。';

    return '''
你是“喜AI盘面分析助手”，服务于专业股票/期货 K 线终端。

【当前标的】
${snapshot.name}（${snapshot.code}，${snapshot.assetClass}）
周期：${snapshot.period.longLabel}
屏幕时间：${_dateTime(snapshot.asOf)}
数据位置：第 ${snapshot.activeIndex + 1} / ${snapshot.totalBars} 根
$replayNote

【当前 K 线】
开 ${_priceMaybe(active.open)}，高 ${_priceMaybe(active.high)}，低 ${_priceMaybe(active.low)}，收 ${_price(active.close)}
上一根收盘：${previous == null ? '无' : _price(previous.close)}
本根涨跌：${change == null ? '无法计算' : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%'}
成交量：${active.vol == null ? '缺失' : _number(active.vol!)}
近 30 根平均量：${volumeAvg <= 0 ? '缺失' : _number(volumeAvg)}
量比：${volumeRatio == null ? '无法计算' : volumeRatio.toStringAsFixed(2)}
近 30 根低点/高点：${_price(recentLow)} / ${_price(recentHigh)}
现价在近 30 根区间的位置：${(position * 100).round()}%
最近 10 根收盘：$recentCloses

【指标】
MA5：${ma5 == null ? '不足' : _price(ma5)}
MA10：${ma10 == null ? '不足' : _price(ma10)}
MA20：${ma20 == null ? '不足' : _price(ma20)}
ATR(14)：${snapshot.levels.atr <= 0 ? '不足' : _price(snapshot.levels.atr)}

【支撑区间】
${supports.isEmpty ? '当前历史窗口未形成稳定支撑区间' : supports.join('\n')}

【阻力区间】
${resistances.isEmpty ? '当前历史窗口未形成稳定阻力区间' : resistances.join('\n')}

【本轮问题】
${question.label}

【回答要求】
1. ${question.taskInstruction}
2. 先给一句明确倾向，再给盘面证据；只能使用上述数据，不得虚构新闻、基本面、资金流、持仓成本或未来价格。
3. 用“观察 → 触发条件 → 失效条件”描述，不使用“必涨、必跌、保证收益”等表达。
4. 支撑阻力优先使用给出的区间上下界，不要把区间偷换成单一价格。
5. 输出 Markdown，控制在 350 字以内，依次使用小标题：结论、盘面依据、执行条件、风险。
6. 结尾固定写：AI分析仅供盘面参考，不构成投资建议。
''';
  }

  static String userMessage(
          MarketAiSnapshot snapshot, MarketAiQuestion question) =>
      '${snapshot.name} ${snapshot.code}，${snapshot.period.longLabel}。${question.label}';

  static String formatPrice(double value) => _price(value);

  static String localAnswer(
    MarketAiSnapshot snapshot,
    MarketAiQuestion question,
  ) {
    final active = snapshot.candles.last;
    final ma5 = _sma(snapshot.candles, 5);
    final ma10 = _sma(snapshot.candles, 10);
    final ma20 = _sma(snapshot.candles, 20);
    final support = snapshot.levels.supports.isEmpty
        ? null
        : snapshot.levels.supports.first;
    final resistance = snapshot.levels.resistances.isEmpty
        ? null
        : snapshot.levels.resistances.first;
    final aboveMa20 = ma20 != null && active.close >= ma20;
    final bullish = aboveMa20 && ma5 != null && ma10 != null && ma5 >= ma10;
    final bias = bullish
        ? '结构偏强'
        : aboveMa20
            ? '结构中性偏强'
            : '结构偏弱';
    final supportText = support == null
        ? '暂未形成稳定支撑区间'
        : '${_price(support.low)}–${_price(support.high)}';
    final resistanceText = resistance == null
        ? '暂未形成稳定阻力区间'
        : '${_price(resistance.low)}–${_price(resistance.high)}';
    final commonEvidence =
        '现价 ${_price(active.close)}，${aboveMa20 ? '位于 MA20 上方' : '位于 MA20 下方'}；最近支撑 $supportText，最近阻力 $resistanceText。';

    final conclusion = switch (question) {
      MarketAiQuestion.entry =>
        '$bias，但不适合无条件追价。空仓应等待支撑区企稳或有效突破；已有持仓补仓也必须先确认原逻辑未失效。',
      MarketAiQuestion.takeProfit =>
        '缺少持仓成本、仓位和盈亏，无法判断你个人是否应该止盈；技术上应在阻力区放量滞涨或趋势转弱时考虑分批处理。',
      MarketAiQuestion.stopLoss =>
        '缺少持仓成本、仓位和可承受亏损，无法给出个性化止损线；技术观察重点是支撑区失守后是否继续放量。',
      MarketAiQuestion.assess =>
        '$bias。$commonEvidence 当前更值得关注的是价格能否守住最近支撑，以及在阻力区附近的量价反应。',
    };

    final action = switch (question) {
      MarketAiQuestion.entry =>
        '- 空仓：等待回踩 $supportText 不破并重新转强，或突破 $resistanceText 后回踩确认。\n- 补仓：仅在原持仓逻辑仍有效、价格靠近支撑时考虑分批，不在阻力区追补。',
      MarketAiQuestion.takeProfit =>
        '- 接近 $resistanceText 时观察是否放量滞涨。\n- 若跌破 MA10 ${ma10 == null ? '（数据不足）' : _price(ma10)} 或最近支撑，分批保护利润。',
      MarketAiQuestion.stopLoss =>
        '- 第一观察位：${support == null ? '最近结构低点' : _price(support.low)}。\n- 若支撑区间整体失守且成交量放大，说明当前盘面结构被破坏。',
      MarketAiQuestion.assess =>
        '- 向上：有效站上 $resistanceText。\n- 向下：有效跌破 $supportText。\n- 指标：MA5 ${_priceMaybe(ma5)}，MA10 ${_priceMaybe(ma10)}，MA20 ${_priceMaybe(ma20)}。',
    };

    return '''
**结论**
$conclusion

**盘面依据**
- $commonEvidence
- MA5 ${_priceMaybe(ma5)} / MA10 ${_priceMaybe(ma10)} / MA20 ${_priceMaybe(ma20)}。

**执行条件**
$action

**风险**
未提供持仓成本、仓位和风险预算，以上为技术条件，不是个性化交易指令。

AI分析仅供盘面参考，不构成投资建议。
''';
  }

  static List<String> _zones(List<MarketPriceZone> zones, String prefix) {
    return [
      for (var i = 0; i < zones.length; i++)
        '$prefix${i + 1}：${_price(zones[i].low)}–${_price(zones[i].high)}'
            '（中心 ${_price(zones[i].center)}，触碰 ${zones[i].touches} 次）',
    ];
  }

  static double? _sma(List<CandlePoint> candles, int n) {
    if (candles.length < n || n <= 0) return null;
    var sum = 0.0;
    for (final candle in candles.skip(candles.length - n)) {
      sum += candle.close;
    }
    return sum / n;
  }

  static double _volumeAverage(List<CandlePoint> candles) {
    var sum = 0.0;
    var count = 0;
    for (final candle in candles) {
      final volume = candle.vol;
      if (volume != null && volume > 0) {
        sum += volume;
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  static String _price(double value) {
    final abs = value.abs();
    if (abs >= 100000) return value.toStringAsFixed(0);
    if (abs >= 1000) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  static String _priceMaybe(double? value) =>
      value == null ? '不足' : _price(value);

  static String _number(double value) {
    if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(2)}亿';
    if (value >= 10000) return '${(value / 10000).toStringAsFixed(2)}万';
    return value.toStringAsFixed(0);
  }

  static String _dateTime(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
