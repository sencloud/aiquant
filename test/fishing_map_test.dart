import 'dart:typed_data';

import 'package:fincept_app/core/config/features.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/topics/fishing/catches_screen.dart';
import 'package:fincept_app/topics/fishing/fishing_api.dart';
import 'package:fincept_app/topics/fishing/fishing_models.dart';
import 'package:fincept_app/topics/fishing/fishing_state.dart';
import 'package:fincept_app/topics/fishing/forecast_screen.dart';
import 'package:fincept_app/topics/fishing/location/fishing_locator.dart';
import 'package:fincept_app/topics/fishing/map/fishing_map.dart';
import 'package:fincept_app/topics/fishing/map/geo_coord.dart';
import 'package:fincept_app/topics/fishing/map/spots_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends FishingApi {
  final forecasts = <Map<String, Object?>>[];
  final saved = <Map<String, dynamic>>[];
  List<FishingSpot> list = const [
    FishingSpot(
        uuid: 's1',
        name: '老河湾',
        lat: 29.62,
        lon: 119.03,
        waterType: '水库',
        species: '翘嘴'),
    FishingSpot(uuid: 's2', name: '远的钓点', lat: 31.2, lon: 121.5),
    FishingSpot(uuid: 's3', name: '没坐标'),
  ];

  @override
  Future<FishingForecast> forecast(
      {String? place,
      double? lat,
      double? lon,
      String? name,
      int days = 3}) async {
    forecasts.add({'place': place, 'lat': lat, 'lon': lon, 'name': name});
    return FishingForecast.fromJson({
      'place': name ?? place ?? '',
      'lat': lat ?? 30,
      'lon': lon ?? 120,
      'days': [
        {
          'date': '2026-10-11',
          'score': 88,
          'level': '很适合',
          'summary': '气压平稳',
          'factors': [],
          'windows': [],
          'warnings': [],
        }
      ],
      'disclaimer': '仅供参考',
    });
  }

  @override
  Future<FishingRegulations> regulations() async =>
      FishingRegulations.fromJson({'regulations': [], 'disclaimer': ''});

  @override
  Future<(List<FishCatch>, CatchStats?)> catches({int? before}) async =>
      (const <FishCatch>[], const CatchStats());

  @override
  Future<List<FishingSpot>> spots() async => list;

  @override
  Future<FishingSpot> saveSpot(Map<String, dynamic> body,
      {String? uuid}) async {
    saved.add(body);
    final s = FishingSpot(
        uuid: uuid ?? 'n${saved.length}',
        name: body['name'] as String,
        lat: (body['lat'] as num?)?.toDouble(),
        lon: (body['lon'] as num?)?.toDouble(),
        species: (body['species'] as String?) ?? '');
    list = [...list, s];
    return s;
  }
}

class _Locator implements FishingLocator {
  _Locator(this.state, {this.afterRequest = LocAccess.granted});
  LocAccess state;
  final LocAccess afterRequest;
  int requests = 0;
  LatLon? pos = const LatLon(29.60512, 119.01987);

  @override
  Future<LocAccess> access() async => state;
  @override
  Future<LocAccess> request() async {
    requests++;
    return state = afterRequest;
  }

  @override
  Future<LatLon?> current() async => pos;
  @override
  Future<bool> openSettings() async => true;
}

class _Authed extends AuthState {
  @override
  bool get isAuthenticated => true;
}

class _QuietBilling extends BillingState {
  @override
  Future<void> refreshBalance() async {}
}

/// 测试里不走网络：所有瓦片都是 1x1 透明图。
class _BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_png));
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, FishingState s) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthState>(create: (_) => _Authed()),
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
    FishingMap.debugUseNative = false;
    FishingMap.debugTileProvider = _BlankTiles();
  });
  group('坐标换算', () {
    test('WGS-84 → GCJ-02 偏移在几百米量级，反算误差 < 0.5 米', () {
      const w = LatLon(39.9087, 116.3975); // 天安门
      final g = wgsToGcj(w.lat, w.lon);
      final off = distanceMeters(w.lat, w.lon, g.lat, g.lon);
      expect(off, inInclusiveRange(100, 800));
      final back = gcjToWgs(g.lat, g.lon);
      expect(distanceMeters(w.lat, w.lon, back.lat, back.lon), lessThan(0.5));
    });

    test('国外坐标不偏移；降精度到约 1 km；距离格式', () {
      expect(outOfChina(51.5, -0.12), isTrue);
      expect(wgsToGcj(51.5, -0.12), const LatLon(51.5, -0.12));
      expect(outOfChina(30.1, 120.2), isFalse);
      expect(coarse(29.60512), 29.61);
      expect(coarse(119.01487), 119.01);
      expect(formatDistance(850), '850 m');
      expect(formatDistance(1234), '1.2 km');
      expect(formatDistance(23456), '23 km');
    });
  });

  test('附近钓点：按距离排序，过滤没坐标和太远的', () async {
    SharedPreferences.setMockInitialValues({});
    final s = FishingState(api: _Api(), locator: _Locator(LocAccess.granted));
    await s.refreshJournal();
    expect(s.nearbySpots(), isEmpty); // 还没有参考位置
    await s.locate();
    final near = s.nearbySpots(maxKm: 80);
    expect(near.map((e) => e.$1.uuid), ['s1']);
    expect(near.first.$2, lessThan(3000));
    expect(s.nearbySpots(maxKm: 1000).map((e) => e.$1.uuid), ['s1', 's2']);
    s.forgetLocation();
    expect(s.here, isNull);
  });

  testWidgets('出钓页：先说明再请求定位，授权后按约 1 km 精度的位置查指数', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final loc = _Locator(LocAccess.notDetermined);
    final s = FishingState(api: api, locator: loc);
    await tester.pumpWidget(_host(const FishingForecastScreen(), s));
    await tester.pumpAndSettle();
    // 没授权过：不自动弹系统框。
    expect(loc.requests, 0);
    expect(api.forecasts, isEmpty);

    await tester.tap(find.byKey(const Key('forecast-use-here')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loc-explainer')), findsOneWidget);
    expect(find.text('开启定位'), findsOneWidget);
    expect(loc.requests, 0);

    await tester.tap(find.byKey(const Key('loc-allow')));
    await tester.pumpAndSettle();
    expect(loc.requests, 1);
    expect(api.forecasts.single['lat'], 29.61);
    expect(api.forecasts.single['lon'], 119.02);
    expect(s.forecast?.place, FishingState.herePlace);
    expect(find.byKey(const Key('forecast-score')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('fishing.last_is_here'), isTrue);
    expect(prefs.getDouble('fishing.last_lat'), 29.61);
  });

  testWidgets('出钓页：「先不用」不请求权限；拒绝后引导去设置或手动选地点', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final loc =
        _Locator(LocAccess.notDetermined, afterRequest: LocAccess.denied);
    final s = FishingState(api: api, locator: loc);
    await tester.pumpWidget(_host(const FishingForecastScreen(), s));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forecast-use-here')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loc-later')));
    await tester.pumpAndSettle();
    expect(loc.requests, 0);
    expect(find.byKey(const Key('loc-explainer')), findsNothing);

    await tester.tap(find.byKey(const Key('forecast-use-here')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loc-allow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loc-denied')), findsOneWidget);
    expect(find.byKey(const Key('loc-open-settings')), findsOneWidget);
    await tester.tap(find.text('手动选地点'));
    await tester.pumpAndSettle();
    expect(api.forecasts, isEmpty);
    // 手动选地点仍可用。
    await tester.tap(find.text('武汉'));
    await tester.pumpAndSettle();
    expect(s.forecast?.place, '武汉');
  });

  testWidgets('出钓页：已授权且上次用的是当前位置，进来直接按位置查', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({
      'fishing.last_place': FishingState.herePlace,
      'fishing.last_is_here': true
    });
    final api = _Api();
    final loc = _Locator(LocAccess.granted);
    final s = FishingState(api: api, locator: loc);
    await tester.pumpWidget(_host(const FishingForecastScreen(), s));
    await tester.pumpAndSettle();
    expect(loc.requests, 0);
    expect(api.forecasts.single['lat'], 29.61);
    expect(find.byKey(const Key('forecast-score')), findsOneWidget);
  });

  testWidgets('钓点地图：显示图钉；在中心添加带坐标和鱼种保存', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final s =
        FishingState(api: api, locator: _Locator(LocAccess.notDetermined));
    await s.refreshJournal();
    await tester.pumpWidget(_host(SpotsMapScreen(focus: api.list.first), s));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fishing-map')), findsOneWidget);
    expect(find.byKey(const Key('map-pin-s1')), findsOneWidget);
    expect(find.byKey(const Key('map-pin-s3')), findsNothing);
    expect(find.textContaining('只有你能看到'), findsOneWidget);
    expect(find.textContaining('1 个未定位'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map-add-center')));
    await tester.pumpAndSettle();
    final coord = tester.widget<TextField>(find.byKey(const Key('spot-coord')));
    expect(coord.controller!.text, '29.620000, 119.030000');
    await tester.enterText(find.byKey(const Key('spot-name')), '大坝下');
    await tester.enterText(find.byKey(const Key('spot-species')), '鲫鱼');
    await tester.ensureVisible(find.byKey(const Key('spot-save')));
    await tester.tap(find.byKey(const Key('spot-save')));
    await tester.pumpAndSettle();
    final body = api.saved.single;
    expect(body['name'], '大坝下');
    expect(body['species'], '鲫鱼');
    expect(body['lat'], closeTo(29.62, 1e-6));
    expect(body['lon'], closeTo(119.03, 1e-6));
    expect(find.byKey(const Key('map-pin-n1')), findsOneWidget);
  });

  testWidgets('钓点地图：点图钉出卡片，可删除（二次确认）', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final s = FishingState(api: api, locator: _Locator(LocAccess.denied));
    await s.refreshJournal();
    await tester.pumpWidget(_host(SpotsMapScreen(focus: api.list.first), s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map-pin-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spot-card')), findsOneWidget);
    expect(find.text('导航'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spot-card-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spot-delete-confirm')), findsOneWidget);
  });

  testWidgets('拍照识鱼默认下线：渔获页不出现入口，换成钓点地图', (tester) async {
    _phone(tester);
    SharedPreferences.setMockInitialValues({});
    expect(kEnableFishIdentify, isFalse);
    final s = FishingState(api: _Api(), locator: _Locator(LocAccess.denied));
    await tester.pumpWidget(_host(const CatchesScreen(), s));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catches-identify')), findsNothing);
    expect(find.textContaining('识鱼'), findsNothing);
    expect(find.byKey(const Key('catches-map')), findsOneWidget);
  });
}

/// 1x1 透明 PNG。
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];
