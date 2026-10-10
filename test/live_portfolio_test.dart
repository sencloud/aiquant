import 'dart:io';
import 'dart:math' as math;

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/live_portfolio.dart';
import 'package:fincept_app/screens/portfolio/portfolio_screen.dart';
import 'package:fincept_app/services/live_portfolio_service.dart';
import 'package:fincept_app/services/portfolio_repository.dart';
import 'package:fincept_app/services/tushare_service.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/portfolio_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

/// 与后端 GET /v1/portfolio/live 同形：策略模拟资金（名义本金 100 万，非实盘）。
/// 7/1 按策略结论五等分建仓 → 联通分红 → 建筑送转 → 9/1 剔除 2 只换入 2 只。
Map<String, dynamic> _liveJson() => {
      'id': 'live:sse50_9f_top5',
      'strategy_id': 'sse50_9f_top5',
      'mode': 'simulation',
      'name': '策略模拟：上证50 九因子',
      'description':
          '策略模拟资金 · 非实盘：按「上证50 九因子选股」每期调仓结论，以名义本金 100万元自 2026-07-01 起模拟。',
      'currency': 'CNY',
      'as_of': '2026-10-09',
      'inception': '2026-07-01',
      'stale': false,
      'stale_days': 0,
      'capital': 1000000,
      'cash': 1830.12,
      'market_value': 1032505.0,
      'total': 1034335.12,
      'pnl': 34335.12,
      'pnl_pct': 0.0343,
      'cost_model': '收盘价成交，滑点万5；佣金万2.5（最低5元）、过户费万0.1、卖出印花税万5；100股整数倍',
      'history_note': '上游提供最近 60 笔回测调仓成交，可还原 2025-02-05 起共 19 期调仓结论',
      'rebalances': [
        {'date': '2026-07-01', 'initial': true},
        {'date': '2026-09-01'},
      ],
      'holdings': [
        _h('600050.SH', '中国联通', '通信', 40000, 5.0038, 4.30),
        _h('601318.SH', '中国平安', '保险', 3700, 54.0402, 52.83),
        _h('601668.SH', '中国建筑', '建筑', 46800, 4.2724, 4.35),
        _h('601688.SH', '华泰证券', '证券', 13000, 19.4147, 17.97),
        _h('600028.SH', '中国石化', '石油', 48000, 5.4528, 5.39),
      ],
      'transactions': [
        _t('2026-07-01', 'buy', '600050.SH', '中国联通', 40000, 5.0038),
        _t('2026-07-01', 'buy', '601318.SH', '中国平安', 3700, 54.0402),
        _t('2026-07-01', 'buy', '601668.SH', '中国建筑', 36000, 5.5541),
        _t('2026-07-01', 'buy', '601601.SH', '中国太保', 7000, 28.5326),
        _t('2026-07-01', 'buy', '601211.SH', '国泰君安', 11000, 18.2763),
        {
          'id': 'live:d1',
          'date': '2026-07-15',
          'type': 'dividend',
          'symbol': '600050.SH',
          'name': '中国联通',
          'asset_class': '股票',
          'quantity': 40000,
          'price': 0.1,
          'amount': 4000,
        },
        {
          'id': 'live:s1',
          'date': '2026-08-20',
          'type': 'split',
          'symbol': '601668.SH',
          'name': '中国建筑',
          'asset_class': '股票',
          'quantity': 1.3,
          'price': 0,
          'amount': 0,
        },
        _t('2026-09-01', 'sell', '601211.SH', '国泰君安', 11000, 17.80),
        _t('2026-09-01', 'sell', '601601.SH', '中国太保', 7000, 31.88),
        _t('2026-09-01', 'buy', '601688.SH', '华泰证券', 13000, 19.4147),
        _t('2026-09-01', 'buy', '600028.SH', '中国石化', 48000, 5.4528),
        // 非法类型 / 0 股的行要被丢掉，不能污染账本。
        _t('2026-09-30', 'transfer', '601688.SH', '华泰证券', 1, 1),
        _t('2026-09-30', 'buy', '601688.SH', '华泰证券', 0, 1),
      ],
      'signal_date': '2026-09-30',
      'exec_date': '2026-10-08',
    };

Map<String, dynamic> _h(String symbol, String name, String industry, num shares,
        num avg, num price) =>
    {
      'symbol': symbol,
      'name': name,
      'industry': industry,
      'asset_class': '股票',
      'shares': shares,
      'avg_cost': avg,
      'price': price,
      'weight': 0.2,
      'in_target': true,
    };

int _seq = 0;
Map<String, dynamic> _t(String date, String type, String symbol, String name,
        num qty, num price) =>
    {
      'id': 'live:t${_seq++}',
      'date': date,
      'type': type,
      'symbol': symbol,
      'name': name,
      'industry': const {
            '601688.SH': '证券',
            '600050.SH': '通信',
            '601318.SH': '保险',
            '601668.SH': '建筑',
            '600028.SH': '石油',
          }[symbol] ??
          '',
      'asset_class': '股票',
      'quantity': qty,
      'price': price,
      'amount': qty * price,
    };

class _FakeLiveService extends LivePortfolioService {
  _FakeLiveService(this.next);
  LivePortfolio? next;
  int calls = 0;
  @override
  Future<LivePortfolio?> fetch() async {
    calls++;
    return next;
  }
}

class _FakeTushare extends TushareService {
  @override
  Future<List<CandlePoint>> historyFor(String symbol,
      {DateTime? start, DateTime? end}) async {
    const base = {
      '600050.SH': 4.3,
      '601318.SH': 52.83,
      '601668.SH': 4.35,
      '601688.SH': 17.97,
      '600028.SH': 5.39,
      '601601.SH': 31.88,
      '601211.SH': 17.8,
    };
    final b = base[symbol] ?? 10.0;
    final now = DateTime(2026, 10, 9);
    final seed = symbol.codeUnits.fold<int>(0, (a, c) => a + c);
    return [
      for (var i = 160; i >= 0; i--)
        CandlePoint(
          date: now.subtract(Duration(days: i)),
          close: b *
              (1 +
                  0.04 * math.sin((i + seed) / 11) -
                  0.0004 * i +
                  0.01 * math.cos(i / 3)),
          pctChg: 0.4,
        ),
    ];
  }
}

class _FakeAuth extends AuthState {
  _FakeAuth(this.authed);
  final bool authed;
  @override
  bool get isAuthenticated => authed;
}

Future<void> _clearBoxes() async {
  await portfoliosBox.clear();
  await transactionsBox.clear();
}

void main() {
  late Directory tmp;
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost');
    tmp = await Directory.systemTemp.createTemp('live_portfolio_test');
    Hive.init(tmp.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });
  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('fromJson + toTransactions：模拟口径字段，丢弃非法行，保留买卖/分红/送转', () {
    final lp = LivePortfolio.fromJson(_liveJson());
    expect(lp.id, 'live:sse50_9f_top5');
    expect(lp.mode, 'simulation');
    expect(lp.capital, 1000000);
    expect(lp.rebalanceCount, 2);
    expect(lp.costModel, contains('印花税'));
    expect(lp.holdings.length, 5);
    expect(lp.closePrices['601688.SH'], 17.97);
    final txns = lp.toTransactions();
    expect(txns.length, 11);
    expect(txns.every((t) => t.portfolioId == lp.id), isTrue);
    final div = txns.firstWhere((t) => t.type == 'dividend');
    expect(div.totalValue, 4000);
    final split = txns.firstWhere((t) => t.type == 'split');
    expect(split.quantity, 1.3);
    expect(split.totalValue, 0);
    expect(txns.first.date, DateTime(2026, 7, 1));
  });

  test('同步策略模拟组合：置顶、只读、按回放得到模拟持仓；登出后隐藏', () async {
    await _clearBoxes();
    final repo = PortfolioRepository();
    await repo.create(name: '我的组合');
    final svc = _FakeLiveService(LivePortfolio.fromJson(_liveJson()));
    final ps = PortfolioState(repo: repo, tushare: _FakeTushare(), live: svc);
    await ps.bootstrap();
    expect(ps.portfolios.map((p) => p.name), ['我的组合']);

    await ps.onAuthChanged(true);
    expect(svc.calls, 1);
    expect(ps.portfolios.first.id, 'live:sse50_9f_top5');
    expect(ps.portfolios.first.isManaged, isTrue);
    expect(ps.portfolios.length, 2);

    ps.selectPortfolio('live:sse50_9f_top5');
    expect(ps.activeIsManaged, isTrue);
    expect(ps.portfolios.first.name, '策略模拟：上证50 九因子');
    final h = ps.currentSummary!.holdings;
    expect(h.length, 5);
    final ht = h.firstWhere((x) => x.symbol == '601688.SH');
    expect(ht.quantity, 13000);
    expect(ht.avgBuyPrice, closeTo(19.4147, 1e-4));
    expect(ht.sector, '证券');
    final jz = h.firstWhere((x) => x.symbol == '601668.SH');
    expect(jz.quantity, closeTo(46800, 1e-6)); // 10 送 3
    expect(jz.avgBuyPrice, closeTo(5.5541 / 1.3, 1e-4));
    expect(h.any((x) => x.symbol == '601211.SH'), isFalse);
    expect(ps.currentTransactions().length, 11);

    // 只读：增删改都无效。
    await ps.addAsset(
      instrument: Instrument(
          tsCode: '600000.SH',
          displaySymbol: '600000',
          name: '浦发银行',
          exchange: 'SSE',
          assetClass: '股票'),
      quantity: 100,
      price: 10,
    );
    await ps.deleteTransaction(ps.currentTransactions().first.id);
    await ps.deletePortfolio('live:sse50_9f_top5');
    final csv = await ps.importTransactionsCsv(
        'date,symbol,type,quantity,price\n2026-10-01,600000.SH,buy,100,10');
    expect(csv.imported, 0);
    expect(ps.currentTransactions().length, 11);
    expect(ps.portfoliosForId('live:sse50_9f_top5'), isNotNull);

    // 30 分钟内不重复拉；force 才拉。再同步一次是整体替换，不会重复累加。
    await ps.syncLivePortfolio();
    expect(svc.calls, 1);
    await ps.syncLivePortfolio(force: true);
    expect(svc.calls, 2);
    expect(ps.currentTransactions().length, 11);
    expect(ps.currentSummary!.holdings.length, 5);

    // 登出：策略模拟组合不可见，自动切回用户自己的组合；用户组合不受影响。
    await ps.onAuthChanged(false);
    expect(ps.portfolios.map((p) => p.name), ['我的组合']);
    expect(ps.activeIsManaged, isFalse);
    expect(ps.liveMeta, isNull);
  });

  testWidgets('组合页：策略模拟条 + 只读命令栏；未登录时显示登录引导', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final svc = _FakeLiveService(LivePortfolio.fromJson(_liveJson()));
    late PortfolioState ps;
    await tester.runAsync(() async {
      await _clearBoxes();
      ps = PortfolioState(
          repo: PortfolioRepository(), tushare: _FakeTushare(), live: svc);
      await ps.bootstrap();
      await ps.onAuthChanged(true);
    });

    var theme = AppTheme.build(ThemeMode.light);
    if (_fontsLoaded) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'ScreenshotSans'),
        primaryTextTheme:
            theme.primaryTextTheme.apply(fontFamily: 'ScreenshotSans'),
      );
    }
    Widget app(bool authed) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>(create: (_) => _FakeAuth(authed)),
            ChangeNotifierProvider<PortfolioState>.value(value: ps),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const PortfolioScreen(),
          ),
        );

    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('live-portfolio-banner')), findsOneWidget);
    expect(find.text('模拟'), findsOneWidget);
    expect(find.textContaining('模拟资金 · 非实盘 · 截至 2026-10-09'), findsOneWidget);
    expect(find.textContaining('名义本金 100万 · 2026-07-01 起'), findsOneWidget);
    expect(find.text('策略详情 ›'), findsOneWidget);
    expect(find.textContaining('策略模拟：上证50 九因子'), findsWidgets);
    expect(find.textContaining('实盘：'), findsNothing);
    // 只读：添加品种 / 删除组合按钮禁用。
    final add = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.playlist_add));
    expect(add.onPressed, isNull);
    final del = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline));
    expect(del.onPressed, isNull);

    if (Platform.environment.containsKey('PORTFOLIO_SCREENSHOT')) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/portfolio_sim.png'));
    }

    // 未登录：显示登录引导，策略模拟组合被隐藏。
    await tester.pumpWidget(Container());
    await tester.runAsync(() => ps.onAuthChanged(false));
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(find.text('登录查看'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-portfolio-banner')), findsNothing);
  });
}

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  final dir = Platform.environment['STRATEGY_FONT_DIR'];
  if (dir == null || _fontsLoaded) return;
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.otf') || f.path.endsWith('.ttf'))
      .toList();
  if (files.isEmpty) return;
  for (final family in [
    'ScreenshotSans',
    'Roboto',
    ...AppType.sansFallback,
    ...AppType.readFallback,
    ...AppType.numericFallback,
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
  _fontsLoaded = true;
}
