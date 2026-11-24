import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/trade_review.dart';
import 'package:fincept_app/screens/shell/xiai_shell.dart';
import 'package:fincept_app/services/trade_review_repository.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    tempDir = await Directory.systemTemp.createTemp('xiai-shell-test-');
    Hive.init(tempDir.path);
    await Hive.openBox(kBoxPrefs);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await TradeReviewStore.instance.clear();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    WidgetBuilder? watchPageBuilder,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>(create: (_) => AuthState()),
            ChangeNotifierProvider<BillingState>(create: (_) => BillingState()),
          ],
          child: XiaiShell(
            chatPageBuilder: (_) => const Scaffold(
              body: Center(child: Text('对话测试页')),
            ),
            watchPageBuilder: watchPageBuilder ??
                (_) => const Scaffold(
                      body: Center(child: Text('看盘测试页')),
                    ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('保留嘻，AI、对话与我的三个页签', (tester) async {
    await pumpShell(tester);

    expect(find.text('嘻，AI'), findsWidgets);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('搭子'), findsNothing);
    expect(find.text('云搭子'), findsNothing);
    expect(find.text('我的搭子'), findsNothing);
    expect(find.text('选择成交截图（可多选）'), findsOneWidget);

    await tester.tap(find.text('对话'));
    await tester.pump();
    expect(find.text('对话测试页'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.text('喜爱用户'), findsOneWidget);
    expect(find.text('最近复盘'), findsOneWidget);
    expect(find.text('交易记录'), findsOneWidget);
    expect(find.text('看盘'), findsOneWidget);
    expect(find.text('付费会员'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('电脑连接'), findsNothing);
    expect(find.text('数据与隐私'), findsNothing);
    expect(find.text('用户协议'), findsNothing);
    expect(find.text('隐私政策'), findsNothing);
    expect(find.text('关于喜爱'), findsNothing);
    expect(find.textContaining('从成交本身复盘'), findsNothing);
    expect(find.text('我的搭子'), findsNothing);

    final top = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('my-top-white')),
    );
    expect(top.color, AppColors.bgSurface);
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('my-page-surface')),
    );
    // 页面灰底 + 白色分组：最后一个分组下方露出灰色作为分割。
    expect(surface.color, AppColors.bgBase);
    expect(
      tester.getCenter(find.text('行情终端')).dx,
      greaterThan(tester.getCenter(find.text('看盘')).dx),
    );
    expect(
      tester
          .getCenter(
            find.descendant(
              of: find.byKey(const ValueKey('my-recent-review')),
              matching: find.text('暂无'),
            ),
          )
          .dx,
      greaterThan(tester.getCenter(find.text('最近复盘')).dx),
    );
  });

  testWidgets('首页保留下拉白底并展示最近三笔真实成交', (tester) async {
    await tester.runAsync(
      () => TradeReviewStore.instance.save(_reportFixture()),
    );
    await pumpShell(tester);

    final top = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('trade-review-top-white')),
    );
    expect(top.color, AppColors.bgSurface);
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('trade-review-page-surface')),
    );
    expect(surface.color, AppColors.bgSurface);

    expect(find.text('成交切片'), findsOneWidget);
    expect(find.text('旧标的 · 000001'), findsNothing);
    expect(find.text('中际旭创 · 300308'), findsOneWidget);
    expect(find.text('贵州茅台 · 600519'), findsOneWidget);
    expect(find.text('东方财富 · 300059'), findsOneWidget);
    expect(find.text('另有 2 笔成交，完整报告里按时间列出'), findsOneWidget);
    expect(find.text('卖出过早，缺少可验证的退出条件。'), findsOneWidget);
    expect(find.text('样本里有 2 次同日换股。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置收纳隐私、协议与产品信息', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('数据与隐私'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('关于喜爱'), findsOneWidget);
  });

  testWidgets('付费会员入口沿用登录与充值流程', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('付费会员'));
    await tester.pumpAndSettle();

    expect(find.text('请输入邮箱地址'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('未登录时可从首页进入邮箱验证码登录', (tester) async {
    await pumpShell(tester);

    expect(find.byKey(const ValueKey('trade-review-login')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trade-review-login')));
    await tester.pumpAndSettle();

    expect(find.text('请输入邮箱地址'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('我的页可以进入看盘与交易记录', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('看盘'));
    await tester.pumpAndSettle();
    expect(find.text('看盘测试页'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('看盘测试页')),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('交易记录'));
    await tester.pumpAndSettle();
    expect(find.text('还没有保存过交易复盘'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

TradeReviewReport _reportFixture() {
  const insight = TradeInsight(
    kind: TradeInsightKind.logic,
    title: '先小仓试探，确认强势后加仓',
    body: '你把更有延续性的持仓留在账户里，但卖出时机仍然依赖盘中情绪。',
    evidence: ['样本里有 2 次同日换股。'],
  );
  return TradeReviewReport(
    id: 'visual-latest-trades',
    createdAt: DateTime(2026, 11, 22, 19, 30),
    title: '强势股加仓有效，但盈利单退出偏早',
    brokerHint: '东方财富',
    currency: 'CNY',
    trades: [
      ParsedTrade(
        occurredAt: DateTime(2026, 11, 18, 9, 31),
        symbol: '000001',
        name: '旧标的',
        side: TradeSide.buy,
        quantity: 100,
        price: 10,
      ),
      ParsedTrade(
        occurredAt: DateTime(2026, 11, 18, 10, 6),
        symbol: '000001',
        name: '旧标的',
        side: TradeSide.sell,
        quantity: 100,
        price: 10.2,
      ),
      ParsedTrade(
        occurredAt: DateTime(2026, 11, 21, 9, 48),
        symbol: '300308',
        name: '中际旭创',
        side: TradeSide.buy,
        quantity: 200,
        price: 158.6,
      ),
      ParsedTrade(
        occurredAt: DateTime(2026, 11, 21, 13, 42),
        symbol: '600519',
        name: '贵州茅台',
        side: TradeSide.buy,
        quantity: 100,
        price: 1468,
      ),
      ParsedTrade(
        occurredAt: DateTime(2026, 11, 22, 14, 17),
        symbol: '300059',
        name: '东方财富',
        side: TradeSide.sell,
        quantity: 500,
        price: 24.36,
      ),
    ],
    metrics: const TradeMetrics(
      realizedPnl: 1286.4,
      grossProfit: 2350,
      grossLoss: -1063.6,
      matchedSellCount: 2,
      winningSellCount: 1,
      losingSellCount: 1,
      winRate: 0.5,
      averageWin: 2350,
      averageLoss: -1063.6,
      profitLossRatio: 2.21,
      expectancy: 643.2,
      averageHoldingHours: 20.5,
      averageWinningHoldingHours: 18,
      averageLosingHoldingHours: 23,
      maxWinStreak: 1,
      maxLossStreak: 1,
      sameDayRoundTrips: 2,
      totalFees: 21.4,
      turnover: 48260,
      feeRatio: 0.0004,
      concentrationRatio: 0.58,
      maxSymbolsInDay: 2,
      averageSymbolsPerDay: 1.5,
      maxTradesInDay: 3,
      averageTradesPerTradingDay: 2.5,
      tradingDayCount: 2,
      openLotCount: 1,
      bestTradePnl: 2350,
      worstTradePnl: -1063.6,
    ),
    logic: const [insight],
    problems: const [
      TradeInsight(
        kind: TradeInsightKind.problem,
        title: '盈利单退出过早',
        body: '卖出过早，缺少可验证的退出条件。',
        evidence: ['样本里有 2 次同日换股。'],
      ),
    ],
    improvements: const [
      TradeInsight(
        kind: TradeInsightKind.improvement,
        title: '先写下退出条件',
        body: '下单前写下止盈、止损和再次加仓各自的触发条件。',
      ),
    ],
    warnings: const [],
  );
}
