// 小应用测试用的假接口与宿主（组件金图、发现页、工坊共用）。
import 'dart:convert';
import 'dart:io';

import 'package:fincept_app/core/api/auth_models.dart';
import 'package:fincept_app/miniapp/miniapp_api.dart';
import 'package:fincept_app/miniapp/miniapp_models.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/services.dart';

/// 金图字体：STRATEGY_FONT_DIR 下的全部字体灌进常用字族；没有就用测试字体。
Future<void> loadGoldenFonts() async {
  final dir = Platform.environment['STRATEGY_FONT_DIR'];
  final files = dir == null
      ? const <File>[]
      : Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.otf') || f.path.endsWith('.ttf'))
          .toList();
  for (final family in [
    'Roboto',
    ...AppType.sansFallback,
    ...AppType.readFallback,
    ...AppType.numericFallback,
  ]) {
    if (files.isEmpty) break;
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
}

/// 后端内置的官方模板（与服务端同一份 JSON）。
List<MiniAppTemplate> officialTemplates(String topic) {
  final dir = Directory('backend/internal/miniapp/templates');
  final out = <(int, MiniAppTemplate)>[];
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final spec = (j['spec'] as Map).cast<String, dynamic>();
    if (spec['topic'] != topic) continue;
    final meta = (spec['meta'] as Map).cast<String, dynamic>();
    out.add((
      (j['order'] as num?)?.toInt() ?? 0,
      MiniAppTemplate.fromJson({
        'id': j['id'],
        'topic': topic,
        'title': meta['title'],
        'summary': meta['summary'],
        'icon': meta['icon'],
        'spec': spec,
        'private_data': j['private_data'] == true || '$spec'.contains('fishing.catch'),
      })
    ));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in out) e.$2];
}

MiniAppTemplate templateById(String id) {
  final topic = id.split('.').first;
  return officialTemplates(topic).firstWhere((t) => t.id == id);
}

/// 固定的示例数据（与服务端数据源的输出形态一致）。
Map<String, dynamic> fakeData(String templateId) {
  List<Map<String, dynamic>> bars(double base, double drift) => [
        for (var i = 0; i < 40; i++)
          () {
            final o = base + drift * i + (i % 5 - 2) * 12.0;
            final c = o + ((i * 7) % 11 - 5) * 6.0;
            return {
              'date': '2026-08-${(i % 28 + 1).toString().padLeft(2, '0')}',
              'open': o,
              'high': (o > c ? o : c) + 18.0,
              'low': (o < c ? o : c) - 15.0,
              'close': c,
              'vol': 10000.0 + i * 50,
            };
          }(),
      ];
  switch (templateId) {
    case 'money.spread_monitor':
      return {
        'ma': {'ts_code': 'Y2601.DCE', 'close': 8120.0},
        'mb': {'ts_code': 'P2601.DCE', 'close': 8890.0},
        'ba': {'items': bars(7900, 6)},
        'bb': {'items': bars(8600, 8)},
      };
    case 'money.palm_morning':
      return {
        'main': {'ts_code': 'P2601.DCE', 'close': 8890.0},
        'q': {'last': 8932.0, 'pct_chg': 0.86},
        'bars': {'items': bars(8600, 8)},
        'wx': {
          'place': '马来西亚·柔佛',
          'forecast': [
            for (var i = 0; i < 3; i++)
              {'date': '2026-10-1${i + 1}', 'precip_mm': 6.5 + i * 3, 'temp_max': 31.0}
          ]
        },
        'news': {
          'items': [
            {'title': '马棕 9 月出口环比增 6%', 'source': '新华财经', 'time': '08:12'},
            {'title': '印尼生柴政策维持 B40', 'source': '新华财经', 'time': '07:40'},
          ]
        },
      };
    case 'fishing.reservoir_compare':
      Map<String, dynamic> fc(List<double> s, String level) => {
            'days': [
              for (final v in s) {'score': v, 'level': level, 'date': '2026-10-11'}
            ]
          };
      return {
        'fc': [
          fc([86, 78, 64], '很适合'),
          fc([72, 81, 70], '适合'),
          fc([58, 66, 75], '一般'),
        ],
      };
  }
  return {};
}

int _seq = 0;

MiniApp fakeApp(String templateId,
    {String? uuid, bool mounted = true, int position = 0, String? title}) {
  final t = templateById(templateId);
  return MiniApp(
    uuid: uuid ?? 'app-${templateId.replaceAll('.', '-')}',
    topic: t.topic,
    title: title ?? t.title,
    icon: t.icon,
    summary: t.summary,
    status: 'active',
    version: 1,
    mounted: mounted,
    position: position,
    cardSize: t.cardSize,
    sessionId: '',
    templateId: templateId,
    spec: t.spec,
  );
}

/// 内存版接口。
class FakeMiniAppApi extends MiniAppApi {
  FakeMiniAppApi({this.apps = const [], this.genScript = const []});

  List<MiniApp> apps;

  /// generate / gen 依次返回的结果（最后一个保持）。
  final List<MiniAppGen> genScript;
  int _gi = 0;
  final List<String> sent = [];
  int fromTemplateCalls = 0;

  MiniAppRun _run(String tplId) => MiniAppRun(
      inputs: const {},
      data: fakeData(tplId),
      errors: const {},
      fetchedAt: DateTime(2026, 10, 11, 9, 30).toUtc().millisecondsSinceEpoch);

  @override
  Future<MiniAppCatalog> catalog(String topic) async =>
      MiniAppCatalog(disclaimer: topic == 'money' ? '仅供参考，不构成投资建议' : '');

  @override
  Future<List<MiniAppTemplate>> templates(String topic) async =>
      officialTemplates(topic);

  @override
  Future<MiniAppRun> runTemplate(String id, {Map<String, dynamic>? inputs}) async =>
      _run(id);

  @override
  Future<List<MiniApp>> list(String topic) async =>
      apps.where((a) => a.topic == topic).toList();

  @override
  Future<MiniApp> get(String id) async => apps.firstWhere((a) => a.uuid == id,
      orElse: () => throw ApiException(
          code: 'MINIAPP.NOT_FOUND', message: '小应用不存在或已删除', statusCode: 404));

  @override
  Future<MiniAppRun> run(String id, {Map<String, dynamic>? inputs}) async {
    final a = await get(id);
    return _run(a.templateId ?? '');
  }

  MiniAppGen _next() {
    final g = genScript[_gi < genScript.length ? _gi : genScript.length - 1];
    if (_gi < genScript.length) _gi++;
    return g;
  }

  @override
  Future<(MiniAppGen, int?)> generate({
    required String requestId,
    required String topic,
    required String message,
    String? appUuid,
    String? sessionId,
  }) async {
    sent.add(message);
    final g = _next();
    return (g, 95);
  }

  @override
  Future<(MiniAppGen, int?)> gen(String requestId) async => (_next(), 95);

  @override
  Future<List<MiniAppGen>> session(String sessionId) async => const [];

  @override
  Future<MiniApp> mount(String id, {String? cardSize}) async {
    final a = await get(id);
    final m = MiniApp(
        uuid: a.uuid,
        topic: a.topic,
        title: a.title,
        icon: a.icon,
        summary: a.summary,
        status: a.status,
        version: a.version,
        mounted: true,
        position: apps.where((x) => x.mounted).length,
        cardSize: a.cardSize,
        sessionId: a.sessionId,
        templateId: a.templateId,
        spec: a.spec);
    apps = [for (final x in apps) x.uuid == id ? m : x];
    return m;
  }

  @override
  Future<MiniApp> fromTemplate(String templateId) async {
    fromTemplateCalls++;
    final a = fakeApp(templateId, uuid: 'tpl-copy-${_seq++}');
    apps = [...apps, a];
    return a;
  }
}

MiniAppGen fakeGen({
  String requestId = 'req-1',
  String status = 'done',
  String stage = 'thinking',
  String outcome = '',
  String message = '沪深300 ETF 定投计算器',
  String kind = 'create',
  bool refunded = false,
  Map<String, dynamic> result = const {},
}) =>
    MiniAppGen.fromJson({
      'request_id': requestId,
      'session_id': 'sess-1',
      'topic': 'money',
      'kind': kind,
      'status': status,
      'stage': stage,
      'outcome': outcome,
      'message': message,
      'credits': kind == 'create' ? 5 : 2,
      'refunded': refunded,
      'result': result,
    });
