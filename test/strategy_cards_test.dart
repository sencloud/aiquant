import 'package:fincept_app/models/strategy_snapshot.dart';
import 'package:fincept_app/screens/strategy/widgets/strategy_cards.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('格式化', () {
    test('金额带千分位与符号', () {
      expect(money(50457.94), '¥50,457.94');
      expect(money(-289), '-¥289.00');
      expect(money(50000, digits: 0), '¥50,000');
      expect(money(1234567.5), '¥1,234,567.50');
    });

    test('百分比带正负号', () {
      expect(pct(0.0092), '+0.92%');
      expect(pct(-0.0058), '-0.58%');
    });

    test('盈亏配色遵循国内惯例（红涨绿跌）', () {
      expect(pnlColor(1), AppColors.positive);
      expect(pnlColor(-1), AppColors.negative);
      expect(pnlColor(0), AppColors.textSecondary);
    });
  });

  testWidgets('ActionCard：本期无需调仓 + 目标名单 + 变动', (tester) async {
    const action = StrategyAction(
      signalDate: '2026-09-30',
      execDate: '2026-10-08',
      changed: false,
      note: '目标名单与上期相同，下次调仓无需操作',
      target: [
        StrategyTarget(code: '600050.SH', name: '中国联通'),
        StrategyTarget(code: '601688.SH', name: '华泰证券'),
      ],
      prevTarget: [
        StrategyTarget(code: '600050.SH', name: '中国联通'),
        StrategyTarget(code: '601688.SH', name: '华泰证券'),
      ],
    );
    await tester.pumpWidget(wrap(const ActionCard(action: action)));

    expect(find.text('本期无需调仓'), findsOneWidget);
    expect(find.textContaining('2026-10-08'), findsOneWidget);
    expect(find.text('中国联通'), findsOneWidget);
    expect(find.text('华泰证券'), findsOneWidget);
    expect(find.textContaining('无需操作'), findsOneWidget);
  });

  testWidgets('ActionCard：有变动时展示新进/剔除与调仓清单', (tester) async {
    const action = StrategyAction(
      signalDate: '2026-10-30',
      execDate: '2026-11-02',
      changed: true,
      note: '目标名单有变化，需按调仓指令买卖',
      target: [StrategyTarget(code: '600519.SH', name: '贵州茅台')],
      prevTarget: [StrategyTarget(code: '600050.SH', name: '中国联通')],
      orders: [
        StrategyOrder(
          side: 'sell',
          code: '600050.SH',
          name: '中国联通',
          shares: 3000,
          price: 4.24,
          amount: 12720,
        ),
        StrategyOrder(
          side: 'buy',
          code: '600519.SH',
          name: '贵州茅台',
          shares: 100,
          price: 1500,
          amount: 150000,
        ),
      ],
    );
    await tester.pumpWidget(wrap(const ActionCard(action: action)));

    expect(find.text('需要调仓'), findsOneWidget);
    // 「新进 / 剔除」用 RichText 拼标签+名单，需开 findRichText 才匹配得到。
    expect(find.textContaining('新进', findRichText: true), findsOneWidget);
    expect(find.textContaining('剔除', findRichText: true), findsOneWidget);
    expect(find.textContaining('贵州茅台', findRichText: true), findsWidgets);
    expect(find.text('卖'), findsOneWidget);
    expect(find.text('买'), findsOneWidget);
    expect(find.text('3000 股 @ 4.24'), findsOneWidget);
  });

  testWidgets('LiveCard：总值、盈亏、持仓与"人工调过仓"提示', (tester) async {
    const live = StrategyLive(
      asOf: '2026-09-30',
      inception: '2026-09-21',
      capital: 50000,
      cash: 41557.94,
      marketValue: 8900,
      total: 50457.94,
      pnl: 457.94,
      pnlPct: 0.0092,
      realized: 536.03,
      fees: 71.06,
      dividends: 252,
      divergence: true,
      positions: [
        StrategyPosition(
          code: '601688.SH',
          name: '华泰证券',
          shares: 500,
          avgCost: 18.36,
          price: 17.8,
          marketValue: 8900,
          pnl: -280,
          pnlPct: -0.0305,
          weight: 0.176,
          inTarget: true,
        ),
      ],
    );
    await tester.pumpWidget(wrap(const LiveCard(live: live)));

    expect(find.text('¥50,457.94'), findsOneWidget);
    expect(find.text('华泰证券'), findsOneWidget);
    expect(find.textContaining('人工调过仓'), findsOneWidget);
    expect(find.textContaining('累计费用 ¥71.06'), findsOneWidget);
    expect(find.textContaining('分红 ¥252.00'), findsOneWidget);
  });

  testWidgets('StaleBanner 明确提示落后交易日数', (tester) async {
    await tester.pumpWidget(wrap(
      const StaleBanner(dataAsOf: '2026-09-30', staleDays: 2),
    ));
    expect(find.textContaining('数据截至 2026-09-30'), findsOneWidget);
    expect(find.textContaining('落后 2 个交易日'), findsOneWidget);
  });
}
