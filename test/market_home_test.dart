import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/market_period.dart';
import 'package:fincept_app/screens/watch/market_theme.dart';
import 'package:fincept_app/screens/watch/watch_screen.dart';
import 'package:fincept_app/screens/watch/widgets/trading_candle_chart.dart';
import 'package:fincept_app/services/tushare_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMarketData extends TushareService {
  final requestedPeriods = <MarketPeriod>[];

  @override
  Future<List<CandlePoint>> historyForPeriod(
    String symbol,
    MarketPeriod period, {
    DateTime? end,
  }) async {
    requestedPeriods.add(period);
    final start = DateTime(2026, 1, 1);
    var price = 100.0;
    return List.generate(160, (i) {
      final open = price;
      price += i % 7 < 4 ? 0.35 : -0.22;
      final close = price;
      return CandlePoint(
        date: start.add(Duration(days: i)),
        open: open,
        close: close,
        high: (open > close ? open : close) + 0.4,
        low: (open < close ? open : close) - 0.4,
        vol: 10000 + i * 100,
      );
    });
  }
}

void main() {
  test('行情主题固定为浅色', () {
    final theme = buildMarketTheme();
    expect(theme.brightness, Brightness.light);
    expect(MarketColors.background, Colors.white);
  });

  testWidgets('首页展示六个周期并可切换分钟线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeMarketData();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMarketTheme(),
        home: WatchScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('贵州茅台'), findsOneWidget);
    expect(find.text('5分'), findsOneWidget);
    expect(find.text('15分'), findsOneWidget);
    expect(find.text('1小时'), findsOneWidget);
    expect(find.text('1天'), findsOneWidget);
    expect(find.text('1周'), findsOneWidget);
    expect(find.text('1月'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('5分'));
    await tester.pumpAndSettle();

    expect(service.requestedPeriods.last, MarketPeriod.fiveMinutes);
    expect(find.text('5 分钟 · Tushare'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按十字线后可从当前位置回放', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeMarketData();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMarketTheme(),
        home: WatchScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(TradingCandleChart);
    await tester.longPressAt(tester.getCenter(chart));
    await tester.pump();

    expect(find.text('从此处回放'), findsOneWidget);
    await tester.tap(find.text('从此处回放'));
    await tester.pump(const Duration(milliseconds: 100));

    final replayChart = tester.widget<TradingCandleChart>(chart);
    expect(replayChart.replayIndex, isNotNull);
    expect(find.textContaining('回放 '), findsOneWidget);
    expect(find.byTooltip('退出回放'), findsOneWidget);
    expect(replayChart.levels.supports, isNotEmpty);

    final firstLevels = replayChart.levels;
    final firstIndex = replayChart.replayIndex!;
    await tester.pump(const Duration(milliseconds: 700));
    final advancedChart = tester.widget<TradingCandleChart>(chart);
    expect(advancedChart.replayIndex, firstIndex + 1);
    expect(identical(advancedChart.levels, firstLevels), isFalse);

    await tester.tap(find.byTooltip('退出回放'));
    await tester.pump();
    expect(
      tester.widget<TradingCandleChart>(chart).replayIndex,
      isNull,
    );
  });

  testWidgets('右下角时钟每秒自动更新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMarketTheme(),
        home: WatchScreen(service: _FakeMarketData()),
      ),
    );
    await tester.pumpAndSettle();

    final clock = find.byKey(const Key('market-live-clock'));
    final before = tester.widget<Text>(clock).data;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 1));
    final after = tester.widget<Text>(clock).data;

    expect(before, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(after, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(after, isNot(before));
  });

  testWidgets('桌面宽屏显示品种侧栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeMarketData();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMarketTheme(),
        home: WatchScreen(service: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('喜AI'), findsOneWidget);
    expect(find.text('选择品种'), findsOneWidget);
    expect(find.text('最近查看'), findsOneWidget);
    expect(find.textContaining('–'), findsWidgets);
    expect(find.textContaining('滚轮缩放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
