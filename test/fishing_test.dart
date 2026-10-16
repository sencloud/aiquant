import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/topics/fishing/catches_screen.dart';
import 'package:fincept_app/topics/fishing/fishing_api.dart';
import 'package:fincept_app/topics/fishing/fishing_models.dart';
import 'package:fincept_app/topics/fishing/fishing_state.dart';
import 'package:fincept_app/topics/fishing/forecast_screen.dart';
import 'package:fincept_app/topics/fishing/identify_screen.dart';
import 'package:fincept_app/topics/fishing/maps_launcher.dart';
import 'package:fincept_app/topics/fishing/map/geo_coord.dart';
import 'package:fincept_app/topics/fishing/spot_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _factor(String k, String n, int s, int m) => {
      'key': k,
      'name': n,
      'value': '$n 值',
      'score': s,
      'max': m,
      'note': '$n 说明'
    };

Map<String, dynamic> _day(String date, int score, String level) => {
      'date': date,
      'score': score,
      'level': level,
      'summary': '$level：气压平稳，清晨和傍晚是好时段',
      'factors': [
        _factor('pressure', '气压', 30, 30),
        _factor('wind', '风', 20, 20),
        _factor('temp', '气温', 20, 20),
        _factor('precip', '降水', 16, 20),
        _factor('moon', '月相', score - 86, 10),
      ],
      'windows': [
        {'from': '05:30', 'to': '08:00', 'label': '清晨'},
        {'from': '15:38', 'to': '18:08', 'label': '傍晚'},
      ],
      'warnings': score < 90 ? ['阵风 15m/s（7 级以上），注意安全'] : [],
      'moon': {'phase': '新月'},
      'sunrise': '06:00',
      'sunset': '17:38',
      'temp_min': 15,
      'temp_max': 28.7,
      'precip_sum': 0,
      'wind_max': 2.5,
    };

class FakeFishingApi extends FishingApi {
  int identifyCalls = 0;
  String? lastRequestId;
  bool protectedFish = false;
  final created = <Map<String, dynamic>>[];

  @override
  Future<FishingForecast> forecast(
      {String? place,
      double? lat,
      double? lon,
      String? name,
      int days = 3}) async {
    return FishingForecast.fromJson({
      'place': place ?? name ?? '所选位置',
      'lat': 29.6,
      'lon': 119,
      'days': [
        _day('2026-10-11', 96, '很适合'),
        _day('2026-10-12', 88, '很适合'),
        _day('2026-10-13', 94, '很适合'),
      ],
      'formula': '出钓指数 = 气压趋势(30) + 风(20) + 气温(20) + 降水(20) + 月相(10)。',
      'disclaimer': '出钓指数只根据天气打分，仅供参考。',
      'active_bans': ['长江十年禁渔'],
    });
  }

  @override
  Future<FishingRegulations> regulations() async =>
      FishingRegulations.fromJson({
        'date': '2026-10-11',
        'regulations': [
          {
            'id': 'yangtze_10y',
            'name': '长江十年禁渔',
            'period': '自 2021 年 1 月 1 日 0 时起，暂定 10 年常年禁捕',
            'angling': '休闲垂钓由各地规范管理',
            'active': true,
          },
          {'id': 'huai_spring', 'name': '淮河干流禁渔期', 'active': false},
        ],
        'disclaimer': '以当地渔政部门公告为准。',
      });

  @override
  Future<(FishIdentification, int?)> identify(
      {required String requestId, required Uint8List jpeg}) async {
    identifyCalls++;
    lastRequestId = requestId;
    return (
      FishIdentification.fromJson({
        'request_id': requestId,
        'status': 'done',
        'credits': 3,
        'disclaimer': 'AI 识别仅供参考。疑似保护动物请立即放流。',
        'result': {
          'is_fish': true,
          'candidates': [
            {
              'name': protectedFish ? '胭脂鱼' : '鲫鱼',
              'confidence': 0.91,
              'features': '体侧扁，背部隆起',
              'protected': protectedFish,
            },
            {'name': '鲤鱼', 'confidence': 0.06},
          ],
        },
      }),
      7,
    );
  }

  @override
  Future<(List<FishCatch>, CatchStats?)> catches({int? before}) async => (
        [
          FishCatch(
              uuid: 'c1',
              caughtAt: DateTime(2026, 10, 10),
              species: '鲫鱼',
              count: 5,
              weightG: 1500,
              spotName: '老河湾',
              method: '台钓'),
          FishCatch(
              uuid: 'c2',
              caughtAt: DateTime(2026, 10, 3),
              species: '翘嘴',
              released: true),
        ],
        const CatchStats(trips: 2, fish: 6, species: 2, released: 1),
      );

  @override
  Future<List<FishingSpot>> spots() async => const [
        FishingSpot(
            uuid: 's1', name: '老河湾', lat: 30.1, lon: 120.2, waterType: '野河'),
        FishingSpot(uuid: 's2', name: '水库北岸'),
      ];

  @override
  Future<FishCatch> createCatch(Map<String, dynamic> body) async {
    created.add(body);
    return FishCatch(
        uuid: 'new',
        caughtAt: DateTime.now(),
        species: body['species'] as String);
  }
}

class _AuthedState extends AuthState {
  _AuthedState(this.authed);
  final bool authed;
  @override
  bool get isAuthenticated => authed;
}

class _QuietBilling extends BillingState {
  @override
  Future<void> refreshBalance() async {}
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, FishingState s, {bool authed = true}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>(create: (_) => _AuthedState(authed)),
      ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
      ChangeNotifierProvider<FishingState>.value(value: s),
    ],
    child: MaterialApp(
        theme: AppTheme.build(ThemeMode.light), home: child),
  );
}

void main() {
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
  });
  // 多主题下线后，钓鱼的入口全部撤掉；功能代码保留，测试继续钉住它本身的
  // 行为（出钓指数、渔获、识鱼），随时可以重新接上入口。

  testWidgets('出钓页：恢复上次地点，展示总分、分项、时段、禁渔提示', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({'fishing.last_place': '千岛湖'});
    final s = FishingState(api: FakeFishingApi());
    await tester.pumpWidget(_host(const FishingForecastScreen(), s));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forecast-score')), findsOneWidget);
    expect(find.text('96'), findsWidgets);
    expect(find.text('千岛湖'), findsWidgets);
    for (final n in ['气压', '风', '气温', '降水', '月相']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('30/30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('forecast-day-1')));
    await tester.pumpAndSettle();
    expect(s.selectedDay, 1);
    expect(find.textContaining('阵风 15m/s'), findsOneWidget);

    // 正文字号抬到 16 之后，时段那一组落到首屏之外（列表不建不可见的行）——
    // 滚到它再断言。
    await tester.scrollUntilVisible(find.textContaining('清晨  05:30'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('清晨  05:30'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('forecast-all-regs')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('长江十年禁渔'), findsOneWidget);
    expect(find.textContaining('以当地公告为准'), findsWidgets);
    await tester.tap(find.byKey(const Key('forecast-all-regs')));
    await tester.pumpAndSettle();
    expect(find.text('淮河干流禁渔期'), findsOneWidget);
    expect(find.text('今日生效'), findsOneWidget);
  });

  testWidgets('出钓页：没有历史地点时给快捷地点，点一下就查', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final s = FishingState(api: FakeFishingApi());
    await tester.pumpWidget(_host(const FishingForecastScreen(), s));
    await tester.pumpAndSettle();
    expect(find.text('去哪儿钓？'), findsOneWidget);
    await tester.tap(find.text('武汉'));
    await tester.pumpAndSettle();
    expect(s.forecast?.place, '武汉');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fishing.last_place'), '武汉');
  });

  testWidgets('渔获页：未登录给登录引导', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final s = FishingState(api: FakeFishingApi());
    await tester.pumpWidget(_host(const CatchesScreen(), s, authed: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catches-login')), findsOneWidget);
    expect(s.journalLoaded, isFalse);
  });

  testWidgets('渔获页：汇总、列表、私人钓点', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final s = FishingState(api: FakeFishingApi());
    await tester.pumpWidget(_host(const CatchesScreen(), s));
    await tester.pumpAndSettle();
    expect(find.text('鲫鱼 ×5'), findsOneWidget);
    expect(find.text('翘嘴 ×1'), findsOneWidget);
    expect(find.text('放流'), findsWidgets);
    expect(find.textContaining('3.0斤'), findsOneWidget);
    await tester.tap(find.text('私人钓点'));
    await tester.pumpAndSettle();
    expect(find.text('老河湾'), findsOneWidget);
    expect(find.textContaining('未填坐标'), findsOneWidget);
    expect(find.byKey(const Key('spot-add')), findsOneWidget);
  });

  testWidgets('拍照识鱼：展示「AI 识别仅供参考」和候选；保护鱼种提示放流', (tester) async {
    _phone(tester);
    final api = FakeFishingApi()..protectedFish = true;
    final s = FishingState(api: api);
    await tester.pumpWidget(
        _host(IdentifyScreen(initialImage: Uint8List.fromList(_png)), s));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 喜点'), findsWidgets);
    await tester.tap(find.byKey(const Key('identify-go')));
    await tester.pumpAndSettle();
    expect(api.identifyCalls, 1);
    expect(api.lastRequestId, startsWith('fi-'));
    expect(find.byKey(const Key('identify-disclaimer')), findsOneWidget);
    expect(find.textContaining('AI 识别仅供参考'), findsOneWidget);
    expect(find.text('胭脂鱼'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.textContaining('请立即放流'), findsWidgets);
    expect(find.text('记入渔获（标记放流）'), findsOneWidget);
  });

  test('系统地图链接与坐标解析', () {
    const sp = FishingSpot(uuid: 'x', name: '老河湾', lat: 30.1, lon: 120.2);
    // Apple 地图在国内用 GCJ-02：存 WGS-84，交给 Apple 地图前要换算。
    final apple = mapsUriFor(sp, platform: TargetPlatform.iOS);
    expect(apple.host, 'maps.apple.com');
    final ll =
        apple.queryParameters['ll']!.split(',').map(double.parse).toList();
    final gcj = wgsToGcj(30.1, 120.2);
    expect(ll[0], closeTo(gcj.lat, 1e-5));
    expect(ll[1], closeTo(gcj.lon, 1e-5));
    expect((ll[0] - 30.1).abs() + (ll[1] - 120.2).abs(), greaterThan(1e-3));
    expect(
        mapsUriFor(sp, platform: TargetPlatform.windows)
            .queryParameters['coordinate'],
        'wgs84');
    expect(mapsUriFor(sp, platform: TargetPlatform.android).scheme, 'geo');
    expect(
        mapsUriFor(sp, platform: TargetPlatform.windows).host, 'uri.amap.com');
    const noCoord = FishingSpot(uuid: 'y', name: '水库北岸');
    expect(
        mapsUriFor(noCoord, platform: TargetPlatform.iOS).queryParameters['q'],
        '水库北岸');
    expect(parseLatLon('30.27, 120.15'), (30.27, 120.15));
    expect(parseLatLon('30.27，120.15'), (30.27, 120.15));
    expect(parseLatLon('abc'), isNull);
    expect(parseLatLon('95, 10'), isNull);
  });
}

/// 1x1 透明 PNG。
const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
