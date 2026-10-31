import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/market_period.dart';
import 'package:fincept_app/screens/watch/market_theme.dart';
import 'package:fincept_app/screens/watch/watch_screen.dart';
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
