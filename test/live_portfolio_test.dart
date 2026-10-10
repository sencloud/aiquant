import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/models/instrument.dart';
import 'package:fincept_app/models/live_portfolio.dart';
import 'package:fincept_app/models/portfolio.dart';
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

/// 与后端 GET /v1/portfolio/live 同形（取自线上 2026-10-09 的实盘账户）。
Map<String, dynamic> _liveJson() => {
      'id': 'live:sse50_9f_top5',
      'strategy_id': 'sse50_9f_top5',
      'name': '实盘：上证50 九因子',
      'description': '系统托管 · 跟随「上证50 九因子选股」实盘账户自动同步，只读。',
      'currency': 'CNY',
      'as_of': '2026-10-09',
      'inception': '2026-09-21',
      'stale': false,
      'stale_days': 0,
      'capital': 50000,
      'cash': 41557.94,
      'market_value': 8985,
      'total': 50542.94,
      'pnl': 542.94,
      'pnl_pct': 0.010859,
      'divergence': true,
      'reconciled': true,
      'holdings': [
        {
          'symbol': '601688.SH',
          'name': '华泰证券',
          'industry': '证券',
          'asset_class': '股票',
          'shares': 500,
          'avg_cost': 18.4602,
          'price': 17.97,
          'weight': 0.1778,
          'in_target': true,
        }
      ],
      'transactions': [
        _t('2026-09-21', 'buy', '601318.SH', '中国平安', 100, 53.3505),
        _t('2026-09-21', 'buy', '600050.SH', '中国联通', 3000, 4.2217),
        _t('2026-09-21', 'buy', '601688.SH', '华泰证券', 500, 18.4602),
        _t('2026-09-30', 'sell', '600050.SH', '中国联通', 3000, 4.2363),
        _t('2026-09-30', 'sell', '601318.SH', '中国平安', 100, 53.2777),
        {
          'id': 'live:d1',
          'date': '2026-09-30',
          'type': 'dividend',
          'symbol': '600050.SH',
          'name': '中国联通',
          'asset_class': '股票',
          'quantity': 3000,
          'price': 0.05,
          'amount': 150,
        },
        // 非法类型 / 0 股的行要被丢掉，不能污染账本。
        _t('2026-09-30', 'transfer', '601688.SH', '华泰证券', 1, 1),
        _t('2026-09-30', 'buy', '601688.SH', '华泰证券', 0, 1),
      ],
      'signal_date': '2026-09-30',
      'exec_date': '2026-10-08',
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
      'industry': symbol == '601688.SH' ? '证券' : '',
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
    final base = symbol == '601688.SH' ? 17.5 : 10.0;
    final now = DateTime(2026, 10, 9);
    return [
      for (var i = 120; i >= 0; i--)
        CandlePoint(
          date: now.subtract(Duration(days: i)),
          close: base + (i % 9) * 0.12 - i * 0.004,
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

  test('fromJson + toTransactions：丢弃非法行，保留买卖与分红', () {
    final lp = LivePortfolio.fromJson(_liveJson());
    expect(lp.id, 'live:sse50_9f_top5');
    expect(lp.holdings.single.symbol, '601688.SH');
    expect(lp.closePrices, {'601688.SH': 17.97});
    final txns = lp.toTransactions();
    expect(txns.length, 6);
    expect(txns.every((t) => t.portfolioId == lp.id), isTrue);
    final div = txns.firstWhere((t) => t.type == 'dividend');
    expect(div.totalValue, 150);
    expect(txns.first.date, DateTime(2026, 9, 21));
  });

  test('同步实盘组合：置顶、只读、按回放得到真实持仓；登出后隐藏', () async {
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
    final h = ps.currentSummary!.holdings;
    expect(h.length, 1);
    expect(h.single.symbol, '601688.SH');
    expect(h.single.quantity, 500);
    expect(h.single.avgBuyPrice, closeTo(18.4602, 1e-4));
    expect(h.single.sector, '证券');
    expect(ps.currentTransactions().length, 6);

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
    expect(ps.currentTransactions().length, 6);
    expect(ps.portfoliosForId('live:sse50_9f_top5'), isNotNull);

    // 30 分钟内不重复拉；force 才拉。再同步一次是整体替换，不会重复累加。
    await ps.syncLivePortfolio();
    expect(svc.calls, 1);
    await ps.syncLivePortfolio(force: true);
    expect(svc.calls, 2);
    expect(ps.currentTransactions().length, 6);
    expect(ps.currentSummary!.holdings.single.quantity, 500);

    // 登出：实盘组合不可见，自动切回用户自己的组合；用户组合不受影响。
    await ps.onAuthChanged(false);
    expect(ps.portfolios.map((p) => p.name), ['我的组合']);
    expect(ps.activeIsManaged, isFalse);
    expect(ps.liveMeta, isNull);
  });

  testWidgets('组合页：实盘条 + 只读命令栏；未登录时显示登录引导', (tester) async {
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
    expect(find.text('实盘'), findsOneWidget);
    expect(find.textContaining('数据截至 2026-10-09'), findsOneWidget);
    expect(find.text('策略详情 ›'), findsOneWidget);
    expect(find.textContaining('实盘：上证50 九因子'), findsWidgets);
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
          matchesGoldenFile('goldens/portfolio_live.png'));
    }

    // 未登录：显示登录引导，实盘组合被隐藏。
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
