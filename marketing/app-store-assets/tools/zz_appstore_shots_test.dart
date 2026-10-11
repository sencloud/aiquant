// App Store 截图原始画面（不放进 test/ 入库：用时临时拷过去，跑完删掉）。
//   cp marketing/app-store-assets/tools/zz_appstore_shots_test.dart test/
//   git apply marketing/app-store-assets/tools/shot_only_wk_kit.patch
//   SHOT_DEVICE=phone|ipad flutter test --update-goldens test/zz_appstore_shots_test.dart
//   git checkout -- lib/widgets/wk_kit.dart && rm test/zz_appstore_shots_test.dart
// 环境变量：SHOT_FONT_DIR（Noto Sans CJK SC）、SHOT_SERIF_DIR（Noto Serif CJK SC Regular/Medium）、
// SHOT_MONO_DIR（DejaVuSansMono*.ttf）、SHOT_OSM_TILES（可选，钓点地图草稿用的 OSM 瓦片 z_x_y.png）。
// 字体只在这里用 FontLoader 灌进去（Noto Sans/Serif CJK SC），App 本身不带字体。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/core/api/billing_models.dart';
import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/core/topic/topic_picker_screen.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_state.dart';
import 'package:fincept_app/miniapp/miniapp_models.dart';
import 'package:fincept_app/miniapp/miniapp_store.dart';
import 'package:fincept_app/miniapp/screens/miniapp_screen.dart';
import 'package:fincept_app/models/chat.dart';
import 'package:fincept_app/screens/home/home_screen.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/state/chat_state.dart';
import 'package:fincept_app/state/ding_state.dart';
import 'package:fincept_app/state/settings_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:fincept_app/topics/fishing/catches_screen.dart';
import 'package:fincept_app/topics/fishing/fishing_api.dart';
import 'package:fincept_app/topics/fishing/fishing_models.dart';
import 'package:fincept_app/topics/fishing/fishing_pack.dart';
import 'package:fincept_app/topics/fishing/fishing_state.dart';
import 'package:fincept_app/topics/fishing/location/fishing_locator.dart';
import 'package:fincept_app/topics/fishing/map/fishing_map.dart';
import 'package:fincept_app/topics/fishing/map/geo_coord.dart';
import 'package:fincept_app/topics/fishing/map/spots_map_screen.dart';
import 'package:fincept_app/topics/money/money_pack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'miniapp_fakes.dart';

// flutter test 的工作目录是仓库根目录。
const _assets = 'marketing/app-store-assets';
const _data = '$_assets/data';
final _env = Platform.environment;
final _device = _env['SHOT_DEVICE'] ?? 'phone';
final _out = '${Directory.current.path}/$_assets/raw/$_device';
final _fontDir = _env['SHOT_FONT_DIR'] ?? '/workspace/fonts';
final _serifDir = _env['SHOT_SERIF_DIR'] ?? '/workspace/fonts_serif';
final _monoDir = _env['SHOT_MONO_DIR'] ?? '/usr/share/fonts/truetype/dejavu';
final _osmTiles = _env['SHOT_OSM_TILES'] ?? '/workspace/osm_tiles';

Future<void> _family(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final sans = [
    '$_fontDir/NotoSansCJKsc-Regular.otf',
    '$_fontDir/NotoSansCJKsc-Bold.otf',
  ];
  final serif = [
    '$_serifDir/NotoSerifCJKsc-Regular.otf',
    '$_serifDir/NotoSerifCJKsc-Medium.otf',
  ];
  // iOS 上 numericFallback 实际落到 Menlo；DejaVu Sans Mono 与 Menlo 同源。
  final mono = [
    '$_monoDir/DejaVuSansMono.ttf',
    '$_monoDir/DejaVuSansMono-Bold.ttf',
  ];
  for (final f in ['Roboto', 'FlutterTest', 'ShotSans', ...AppType.sansFallback]) {
    await _family(f, sans);
  }
  for (final f in AppType.readFallback) {
    await _family(f, serif);
  }
  for (final f in AppType.numericFallback) {
    await _family(f, mono);
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await _family('MaterialIcons', [icons.path]);
}

/// 测试字体会让按钮/标签退回 FlutterTest 族，这里统一指到 ShotSans（= Noto Sans CJK）。
ThemeData _shotTheme(ThemeData t) => t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'ShotSans'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'ShotSans'),
    textButtonTheme: t.textButtonTheme.style == null
        ? null
        : TextButtonThemeData(
            style: t.textButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(TextStyle(
                    fontFamily: 'ShotSans',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.2)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _fam(t.outlinedButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _fam(t.elevatedButtonTheme.style)),
    filledButtonTheme: FilledButtonThemeData(style: _fam(t.filledButtonTheme.style)),
    chipTheme: t.chipTheme.labelStyle == null
        ? null
        : t.chipTheme.copyWith(
            labelStyle: t.chipTheme.labelStyle!.copyWith(fontFamily: 'ShotSans')));

ButtonStyle _fam(ButtonStyle? s) {
  final base = s ?? const ButtonStyle();
  return base.copyWith(
      textStyle: WidgetStateProperty.resolveWith((st) =>
          (base.textStyle?.resolve(st) ?? const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
              .copyWith(fontFamily: 'ShotSans')));
}

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_data/$name').readAsStringSync()) as Map<String, dynamic>;

// ── 假状态 ──────────────────────────────────────────────────────────────

class _Auth extends AuthState {
  _Auth(this.authed);
  final bool authed;
  @override
  bool get isAuthenticated => authed;
  @override
  UserPublic? get currentUser => authed
      ? UserPublic(
          uuid: 'u-demo',
          nickname: '钓友',
          status: 'active',
          creditBalance: 560,
          hasPhone: false,
          hasApple: true,
          createdAt: DateTime(2026, 9))
      : null;
}

class _QuietBilling extends BillingState {
  @override
  List<CreditSku> get skus => [
        for (final e in (_json('skus.json')['items'] as List))
          CreditSku.fromJson((e as Map).cast<String, dynamic>())
      ];
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<void> refreshAll() async {}
}

class _QuietDing extends DingState {
  @override
  int get unreadCount => 0;
}

/// 小应用：数据用线上官方模板的真实运行结果（marketing/app-store-assets/data/run_*.json）。
class _RealRunApi extends FakeMiniAppApi {
  _RealRunApi({super.apps});
  MiniAppRun _real(String tpl) {
    final f = File('$_data/run_$tpl.json');
    if (!f.existsSync()) {
      return MiniAppRun(inputs: const {}, data: fakeData(tpl), errors: const {}, fetchedAt: 0);
    }
    return MiniAppRun.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }

  @override
  Future<MiniAppRun> runTemplate(String id, {Map<String, dynamic>? inputs}) async => _real(id);
  @override
  Future<MiniAppRun> run(String id, {Map<String, dynamic>? inputs}) async =>
      _real(apps.firstWhere((a) => a.uuid == id).templateId!);
}

class _FishApi extends FishingApi {
  @override
  Future<FishingForecast> forecast(
          {String? place, double? lat, double? lon, String? name, int days = 3}) async =>
      FishingForecast.fromJson(_json('qdh.json'));
  @override
  Future<FishingRegulations> regulations() async =>
      FishingRegulations.fromJson({'regulations': [], 'disclaimer': ''});
  @override
  Future<(List<FishCatch>, CatchStats?)> catches({int? before}) async {
    int ms(int d, int h, int m) => DateTime(2026, 10, d, h, m).millisecondsSinceEpoch;
    final items = [
      {'uuid': 'c1', 'caught_at': ms(10, 6, 40), 'species': '翘嘴', 'count': 3, 'weight_g': 2100, 'length_cm': 46, 'spot_name': '东南湾', 'method': '路亚', 'bait': '米诺', 'weather': '晴 · 微风', 'note': '早口集中在六点半到七点半，岸边浅滩追小鱼', 'released': true},
      {'uuid': 'c2', 'caught_at': ms(10, 16, 20), 'species': '鲫鱼', 'count': 12, 'weight_g': 3600, 'spot_name': '大坝下', 'method': '台钓', 'bait': '蚯蚓 + 商品饵', 'weather': '晴', 'note': '傍晚窝子起鱼'},
      {'uuid': 'c3', 'caught_at': ms(4, 7, 5), 'species': '鳜鱼', 'count': 1, 'weight_g': 900, 'length_cm': 35, 'spot_name': '老河湾', 'method': '路亚', 'bait': '软虫', 'weather': '多云', 'released': true},
      {'uuid': 'c4', 'caught_at': ms(3, 15, 50), 'species': '鲢鳙', 'count': 2, 'weight_g': 11500, 'spot_name': '东南湾', 'method': '浮钓', 'bait': '酸臭饵', 'weather': '阴', 'note': '第二条上了 7 斤'},
      {'uuid': 'c5', 'caught_at': DateTime(2026, 9, 27, 6, 15).millisecondsSinceEpoch, 'species': '鲤鱼', 'count': 1, 'weight_g': 2600, 'length_cm': 52, 'spot_name': '大坝下', 'method': '台钓', 'bait': '玉米', 'weather': '晴'},
      {'uuid': 'c6', 'caught_at': DateTime(2026, 9, 20, 17, 0).millisecondsSinceEpoch, 'species': '鲫鱼', 'count': 8, 'weight_g': 2200, 'spot_name': '西岛', 'method': '台钓', 'bait': '红虫', 'weather': '多云'},
      {'uuid': 'c7', 'caught_at': DateTime(2026, 9, 13, 7, 30).millisecondsSinceEpoch, 'species': '翘嘴', 'count': 2, 'weight_g': 1500, 'length_cm': 41, 'spot_name': '老河湾', 'method': '路亚', 'bait': '亮片', 'weather': '晴', 'released': true},
    ];
    return (
      [for (final i in items) FishCatch.fromJson(i)],
      CatchStats.fromJson({'trips': 7, 'fish': 29, 'species': 5, 'released': 6}),
    );
  }

  @override
  Future<List<FishingSpot>> spots() async => const [
        FishingSpot(uuid: 's1', name: '老河湾', lat: 29.589, lon: 119.005, waterType: '水库', species: '翘嘴'),
        FishingSpot(uuid: 's2', name: '大坝下', lat: 29.547, lon: 118.967, waterType: '水库', species: '鲫鱼'),
        FishingSpot(uuid: 's3', name: '东南湾', lat: 29.547, lon: 119.049, species: '鲢鳙'),
        FishingSpot(uuid: 's4', name: '西岛', lat: 29.598, lon: 118.922),
      ];
}

class _Locator implements FishingLocator {
  @override
  Future<LocAccess> access() async => LocAccess.granted;
  @override
  Future<LocAccess> request() async => LocAccess.granted;
  @override
  Future<LatLon?> current() async => const LatLon(29.571, 118.988);
  @override
  Future<bool> openSettings() async => true;
}

// ── 对话内容（数据来自线上 2026-10-09 收盘 / 2026-10-11 出钓指数）────────

const _moneyAnswer = '''截至 10 月 9 日收盘（大商所主力）：

- **豆油 Y2701**：9014 元/吨
- **棕榈油 P2701**：9643 元/吨
- **价差（豆油 − 棕榈油）**：**−629 元/吨**

### 放到近 60 个交易日看
- 均值 −1096，标准差约 184
- 当前比均值高 467，约 **2.5 个标准差**
- 区间 −1340 ～ −603，目前贴近区间上沿

### 最近 6 个交易日
−844 → −762 → −690 → −609 → −603 → −629
价差先快速收窄，最近一天小幅回落。

以上是对历史数据的统计描述，不代表后续走势，不构成投资建议。''';

ChatSession _moneySession() => ChatSession(id: 'm1', title: '豆棕价差')
  ..messages.addAll([
    ChatMessage(role: 'user', content: '豆油和棕榈油主力的价差，现在处在什么位置？'),
    ChatMessage(
      role: 'assistant',
      content: _moneyAnswer,
      toolCalls: [
        ToolCall(id: 'c1', name: 'get_dominant_contract', argumentsJson: '{"product":"Y"}'),
        ToolCall(id: 'c2', name: 'get_dominant_contract', argumentsJson: '{"product":"P"}'),
        ToolCall(id: 'c3', name: 'get_quote', argumentsJson: '{"days":60}'),
      ],
      suggestions: const [
        '把这个价差做成小应用，放到发现页',
        '马来西亚柔佛产区最近天气怎么样？',
      ],
    ),
    ChatMessage(role: 'tool', toolCallId: 'c1', name: 'get_dominant_contract', content: '{"ts_code":"Y2701.DCE"}'),
    ChatMessage(role: 'tool', toolCallId: 'c2', name: 'get_dominant_contract', content: '{"ts_code":"P2701.DCE"}'),
    ChatMessage(role: 'tool', toolCallId: 'c3', name: 'get_quote', content: '{}'),
  ]);

const _fishAnswer = '''两天都是「很适合」，**13 号（周二）略好一点**：

| | 12 日 | 13 日 |
|---|---|---|
| 出钓指数 | 90 | **96** |
| 气压 | 1018 hPa，平稳 | 1018 hPa，平稳 |
| 风 | 0.7 m/s，几乎无风 | 1.4 m/s，微风 |
| 气温 | 15–29 ℃ | 16–30 ℃ |
| 降水 | 0 mm | 0 mm |

12 号几乎无风，水面如镜，鱼会更警惕；13 号有点微风起浪，水里溶氧好，翘嘴这类上层鱼更愿意追饵。

**好时段**：清晨 05:31–08:01，傍晚 15:36–18:06。中午气温接近 30 ℃，可以歇一歇。

出发前留意当地的禁渔和垂钓管理规定，注意安全。''';

ChatSession _fishSession() => ChatSession(id: 'f1', title: '千岛湖哪天去')
  ..messages.addAll([
    ChatMessage(role: 'user', content: '明后天想去千岛湖打翘嘴，哪天更合适？'),
    ChatMessage(
      role: 'assistant',
      content: _fishAnswer,
      toolCalls: [
        ToolCall(id: 'f1', name: 'get_fishing_forecast', argumentsJson: '{"place":"千岛湖"}'),
      ],
      suggestions: const ['翘嘴用什么饵比较好？', '帮我记一笔渔获'],
    ),
    ChatMessage(role: 'tool', toolCallId: 'f1', name: 'get_fishing_forecast', content: '{}'),
  ]);

// ── 宿主 ────────────────────────────────────────────────────────────────

Widget _host(TopicPack pack, Widget home,
    {bool authed = true, ChatState? chat, FishingState? fishing, TopicState? topics}) {
  AppColors.applyTopic(pack.palette);
  topics ??= TopicState(packs: builtInTopicPacks(fishing: true));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsState()),
      ChangeNotifierProvider<AuthState>(create: (_) => _Auth(authed)),
      ChangeNotifierProvider<BillingState>(create: (_) => _QuietBilling()),
      ChangeNotifierProvider.value(value: topics),
      ChangeNotifierProvider<ChatState>.value(value: chat ?? ChatState()),
    ],
    child: MultiProvider(
      providers: [
        Provider<TopicPack>.value(value: pack),
        ...pack.providers(),
        if (pack.id == 'money') ChangeNotifierProvider<DingState>(create: (_) => _QuietDing()),
        if (fishing != null) ChangeNotifierProvider<FishingState>.value(value: fishing),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _shotTheme(AppTheme.build(ThemeMode.light, palette: pack.palette)),
        home: home,
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _toTop(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.dragFrom(tester.getCenter(find.byType(MaterialApp)), const Offset(0, 900));
    await _settle(tester, n: 3);
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('$_out/$name.png'));
}

final _tiles = <String, Uint8List>{};

class _DiskTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) =>
      MemoryImage(_tiles['${c.z}_${c.x}_${c.y}'] ?? _tiles.values.first);
}

void main() {
  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: '喜爱', packageName: 'com.aiquant.app', version: '1.1.0', buildNumber: '201', buildSignature: '');
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    final dir = await Directory.systemTemp.createTemp('hive_shots');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
    FishingMap.debugUseNative = false;
    FishingMap.debugTileProvider = _DiskTiles();
    if (Directory(_osmTiles).existsSync()) {
      for (final f in Directory(_osmTiles).listSync().whereType<File>()) {
        _tiles[f.uri.pathSegments.last.replaceAll('.png', '')] = f.readAsBytesSync();
      }
    }
    await _loadFonts();
  });

  Future<void> device(WidgetTester tester) async {
    if (_device == 'ipad') {
      tester.view.physicalSize = const Size(2064, 2752); // 13" iPad 1032×1376 pt @2x
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 40);
    } else {
      tester.view.physicalSize = const Size(1320, 2868); // 6.9" 440×956 pt @3x
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 186, bottom: 102);
    }
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    MiniAppStore.resetAll();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await _settle(tester);
  }

  testWidgets('01 picker', (tester) async {
    await device(tester);
    final topics = TopicState(packs: builtInTopicPacks(fishing: true));
    await tester.pumpWidget(_host(const MoneyPack(), const TopicPickerScreen(), topics: topics, authed: false));
    await _settle(tester);
    await _shot(tester, '01_picker');
  });

  testWidgets('02 money chat', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi();
    final chat = ChatState()..debugSeed([_moneySession()], activeId: 'm1');
    await tester.pumpWidget(_host(const MoneyPack(), const HomeScreen(), chat: chat));
    await _settle(tester);
    await _toTop(tester);
    await _shot(tester, '02_money_chat');
  });

  testWidgets('03 money discover', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi(apps: [
      fakeApp('money.palm_morning', position: 0),
      fakeApp('money.spread_monitor', position: 1),
      fakeApp('money.etf_dca', position: 2),
    ]);
    await tester.pumpWidget(_host(const MoneyPack(), const HomeScreen()));
    await _settle(tester);
    await tapTab(tester, '发现');
    await _settle(tester);
    await _shot(tester, '03_money_discover');
  });

  testWidgets('04 miniapp', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi(apps: [fakeApp('money.palm_morning')]);
    await tester.pumpWidget(_host(const MoneyPack(),
        const MiniAppScreen(topic: 'money', appId: 'app-money-palm_morning')));
    await _settle(tester);
    await _shot(tester, '04_miniapp_palm');
  });

  testWidgets('04b miniapp spread', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi(apps: [fakeApp('money.spread_monitor')]);
    await tester.pumpWidget(_host(const MoneyPack(),
        const MiniAppScreen(topic: 'money', appId: 'app-money-spread_monitor')));
    await _settle(tester);
    await _shot(tester, '04b_miniapp_spread');
  });

  testWidgets('05 forecast', (tester) async {
    await device(tester);
    SharedPreferences.setMockInitialValues({'fishing.last_place': '千岛湖'});
    MiniAppStore.api = _RealRunApi();
    final fs = FishingState(api: _FishApi(), locator: _Locator());
    await tester.pumpWidget(_host(const FishingPack(), const HomeScreen(), fishing: fs));
    await _settle(tester);
    await tapTab(tester, '出钓');
    await _settle(tester, n: 12);
    await _shot(tester, '05_forecast');
  });

  testWidgets('06 map (OSM draft only)', (tester) async {
    if (_tiles.isEmpty) return; // 没给 SHOT_OSM_TILES 就不出地图草稿
    await device(tester);
    final fs = FishingState(api: _FishApi(), locator: _Locator());
    await tester.runAsync(() async {
      await fs.refreshJournal();
      await fs.locate();
    });
    await tester.pumpWidget(_host(const FishingPack(), const SpotsMapScreen(), fishing: fs));
    await _settle(tester, n: 12);
    await _shot(tester, '06_map_osm_draft');
  });

  testWidgets('07 fishing chat', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi();
    final fs = FishingState(api: _FishApi(), locator: _Locator());
    final chat = ChatState()..debugSeed([_fishSession()], activeId: 'f1');
    await tester.pumpWidget(_host(const FishingPack(), const HomeScreen(), chat: chat, fishing: fs));
    await _settle(tester);
    await _toTop(tester);
    await _shot(tester, '07_fishing_chat');
  });

  testWidgets('08 catches', (tester) async {
    await device(tester);
    final fs = FishingState(api: _FishApi(), locator: _Locator());
    await tester.runAsync(() => fs.refreshJournal());
    await tester.pumpWidget(_host(const FishingPack(), const CatchesScreen(), fishing: fs));
    await _settle(tester);
    await _shot(tester, '08_catches');
  });

  testWidgets('09 iap sheet', (tester) async {
    await device(tester);
    MiniAppStore.api = _RealRunApi();
    await tester.pumpWidget(_host(const MoneyPack(), const SettingsScreen()));
    await _settle(tester);
    showRechargeSheet(tester.element(find.byType(SettingsScreen)));
    await _settle(tester);
    await _shot(tester, '09_iap_sheet');
  });
}
