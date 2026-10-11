// 小应用：发现页（两主题）、工坊（追问 → 生成 → 放到发现页）、模板（未登录可看）。
import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/miniapp/miniapp_store.dart';
import 'package:fincept_app/miniapp/screens/miniapp_screen.dart';
import 'package:fincept_app/miniapp/screens/template_screen.dart';
import 'package:fincept_app/miniapp/screens/workshop_screen.dart';
import 'package:fincept_app/screens/auth/login_screen.dart';
import 'package:fincept_app/screens/discover/discover_screen.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/ding_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/topics/fishing/fishing_pack.dart';
import 'package:fincept_app/topics/fishing/fishing_state.dart';
import 'package:fincept_app/topics/money/money_pack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'miniapp_fakes.dart';

class _Auth extends AuthState {
  _Auth(this.authed);
  final bool authed;
  @override
  bool get isAuthenticated => authed;
  @override
  UserPublic? get currentUser => authed
      ? UserPublic(
          uuid: 'u-1',
          nickname: '测试',
          status: 'active',
          creditBalance: 100,
          hasPhone: true,
          hasApple: false,
          createdAt: DateTime(2026))
      : null;
}

class _QuietBilling extends BillingState {
  int refreshed = 0;
  @override
  Future<void> refreshBalance() async => refreshed++;
}

class _QuietDing extends DingState {
  @override
  int get unreadCount => 0;
}

void _phone(WidgetTester tester, {double h = 844}) {
  tester.view.physicalSize = Size(390, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, {required TopicPack pack, bool authed = true}) {
  AppColors.applyTopic(pack.palette);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>(create: (_) => _Auth(authed)),
      ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
      Provider<TopicPack>.value(value: pack),
      if (pack.id == 'money')
        ChangeNotifierProvider<DingState>(create: (_) => _QuietDing()),
      if (pack.id == 'fishing')
        ChangeNotifierProvider<FishingState>(create: (_) => FishingState()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(ThemeMode.light, palette: pack.palette),
      home: child,
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    await loadGoldenFonts();
  });
  setUp(MiniAppStore.resetAll);
  tearDown(() => AppColors.applyTopic(TopicPalette.money));

  test('页签：喜爱钓鱼 对话 / 出钓 / 发现 / 我的；喜爱钱 对话 / 发现 / 我的', () {
    expect(const FishingPack().tabs.map((t) => t.key).toList(),
        ['chat', 'forecast', 'discover', 'me']);
    expect(const MoneyPack().tabs.map((t) => t.key).toList(),
        ['chat', 'discover', 'me']);
  });

  testWidgets('发现（喜爱钱）：小应用卡片墙 + 新建 + 定时提醒 + 官方模板', (tester) async {
    _phone(tester, h: 1200);
    MiniAppStore.api = FakeMiniAppApi(apps: [
      fakeApp('money.spread_monitor', position: 0),
      fakeApp('money.etf_dca', position: 1),
      fakeApp('money.palm_morning', mounted: false),
    ]);
    await tester.pumpWidget(_host(const DiscoverScreen(), pack: const MoneyPack()));
    await _settle(tester);
    expect(find.byKey(const Key('miniapp-card-app-money-spread_monitor')), findsOneWidget);
    expect(find.byKey(const Key('miniapp-card-app-money-etf_dca')), findsOneWidget);
    expect(find.byKey(const Key('miniapp-new')), findsOneWidget);
    expect(find.byKey(const Key('miniapp-drafts')), findsOneWidget);
    expect(find.text('定时提醒'), findsOneWidget);
    expect(find.text('官方模板'), findsOneWidget);
    expect(find.text('棕榈油早报'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/miniapp_discover_money.png'));
  });

  testWidgets('发现（喜爱钓鱼）：渔获作为内置入口；未登录也能看官方模板', (tester) async {
    _phone(tester, h: 1000);
    MiniAppStore.api = FakeMiniAppApi();
    await tester.pumpWidget(
        _host(const DiscoverScreen(), pack: const FishingPack(), authed: false));
    await _settle(tester);
    expect(find.byKey(const Key('discover-catches')), findsOneWidget);
    expect(find.text('官方模板'), findsOneWidget);
    expect(find.text('饵料配比计算器'), findsOneWidget);
    expect(find.byKey(const Key('miniapp-manage')), findsNothing);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/miniapp_discover_fishing.png'));

    // 未登录点「新建」先弹登录。
    await tester.tap(find.byKey(const Key('miniapp-new')));
    await _settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('模板：未登录可预览并调参；「用这个模板」要求登录', (tester) async {
    _phone(tester, h: 1100);
    final api = FakeMiniAppApi();
    MiniAppStore.api = api;
    await tester.pumpWidget(_host(
        TemplateScreen(topic: 'money', template: templateById('money.etf_dca')),
        pack: const MoneyPack(),
        authed: false));
    await _settle(tester);
    expect(find.text('每月投入'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('miniapp-use-template')));
    await tester.tap(find.byKey(const Key('miniapp-use-template')));
    await _settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(api.fromTemplateCalls, 0);
  });

  testWidgets('模板：登录后一键添加并打开', (tester) async {
    _phone(tester, h: 1100);
    final api = FakeMiniAppApi();
    MiniAppStore.api = api;
    await tester.pumpWidget(_host(
        TemplateScreen(topic: 'money', template: templateById('money.etf_dca')),
        pack: const MoneyPack()));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('miniapp-use-template')));
    await tester.tap(find.byKey(const Key('miniapp-use-template')));
    await _settle(tester);
    expect(api.fromTemplateCalls, 1);
    expect(find.byType(MiniAppScreen), findsOneWidget);
    expect(find.byKey(const Key('miniapp-edit')), findsOneWidget);
  });

  testWidgets('工坊：追问 → 回答 → 生成 → 放到发现页；价格提示与退款提示', (tester) async {
    _phone(tester, h: 1200);
    final made = fakeApp('money.etf_dca',
        uuid: 'gen-app-1', mounted: false, title: '沪深300 ETF 定投');
    final api = FakeMiniAppApi(apps: [made], genScript: [
      fakeGen(status: 'pending'),
      fakeGen(status: 'done', outcome: 'ask', refunded: true, result: {
        'message': '先确认两件事：',
        'questions': [
          {'q': '每月投多少', 'options': ['500 元', '1000 元', '2000 元']},
          {'q': '看几年', 'options': ['5 年', '10 年']},
        ]
      }),
      fakeGen(
          requestId: 'req-2',
          status: 'pending',
          stage: 'dry_run',
          message: '每月投多少：1000 元'),
      fakeGen(
          requestId: 'req-2',
          status: 'done',
          outcome: 'spec',
          message: '每月投多少：1000 元',
          result: {
        'app_uuid': 'gen-app-1',
        'version': 1,
        'summary': '按月定投，估算到期金额',
      }),
    ]);
    MiniAppStore.api = api;
    await tester.pumpWidget(_host(
        const WorkshopScreen(
            topic: 'money', pollInterval: Duration(milliseconds: 100)),
        pack: const MoneyPack()));
    await _settle(tester);
    expect(find.text('新建 5 喜点 · 未做出来全额退回'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('workshop-input')), '沪深300 ETF 定投计算器');
    await tester.tap(find.byKey(const Key('workshop-send')));
    await tester.pump();
    expect(find.byKey(const Key('workshop-stage')), findsOneWidget);
    await _settle(tester);
    expect(find.text('每月投多少'), findsOneWidget);
    expect(find.text('已退回 5 喜点'), findsOneWidget);

    await tester.tap(find.text('1000 元'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('workshop-answer')));
    await tester.pump();
    expect(api.sent.last, '每月投多少：1000 元');
    await _settle(tester);
    await _settle(tester);
    expect(find.byKey(const Key('workshop-preview')), findsOneWidget);
    expect(find.text('修改 2 喜点 · 没改成全额退回'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/miniapp_workshop_done.png'));

    await tester.tap(find.byKey(const Key('workshop-mount')));
    await _settle(tester);
    expect(api.apps.single.mounted, isTrue);
    expect(find.byKey(const Key('workshop-mount')), findsNothing);
  });

  testWidgets('小应用页：数据 + 改一改入口 + 免责提示', (tester) async {
    _phone(tester, h: 1300);
    MiniAppStore.api = FakeMiniAppApi(apps: [fakeApp('money.spread_monitor')]);
    await tester.pumpWidget(_host(
        const MiniAppScreen(topic: 'money', appId: 'app-money-spread_monitor'),
        pack: const MoneyPack()));
    await _settle(tester);
    expect(find.text('价差走势'), findsOneWidget);
    expect(find.byKey(const Key('miniapp-edit')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/miniapp_screen_money.png'));
  });

  testWidgets('小应用页（钓鱼）：水库对比', (tester) async {
    _phone(tester, h: 1100);
    MiniAppStore.api =
        FakeMiniAppApi(apps: [fakeApp('fishing.reservoir_compare')]);
    await tester.pumpWidget(_host(
        const MiniAppScreen(topic: 'fishing', appId: 'app-fishing-reservoir_compare'),
        pack: const FishingPack()));
    await _settle(tester);
    expect(find.text('千岛湖'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/miniapp_screen_fishing.png'));
  });
}
