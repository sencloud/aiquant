// 小应用渲染器：每种组件一张金图（含组件级兜底）。
import 'dart:io';

import 'package:fincept_app/miniapp/render/components.dart';
import 'package:fincept_app/miniapp/render/spec_runtime.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'miniapp_fakes.dart';

final _now = DateTime(2026, 10, 11, 9, 30);

Map<String, dynamic> _spec(Map<String, dynamic> layout,
        {Map<String, dynamic> inputs = const {},
        Map<String, dynamic> computed = const {}}) =>
    {
      'schema': 'xiai.miniapp/1',
      'topic': 'money',
      'meta': {'title': 't', 'icon': 'apps', 'card_size': 'medium'},
      'inputs': inputs,
      'computed': computed,
      'card_view': layout,
      'layout': layout,
    };

final _bars = (fakeData('money.palm_morning')['bars'] as Map)['items'] as List;

final _data = <String, dynamic>{
  'q': {'last': 8932.0, 'pct_chg': 0.86},
  'bars': {'items': _bars},
  'news': {
    'items': [
      {'title': '马棕 9 月出口环比增 6%', 'source': '新华财经'},
      {'title': '印尼生柴政策维持 B40', 'source': '新华财经'},
    ]
  },
};

final _cases = <String, (Map<String, dynamic>, Map<String, String>)>{
  'text': (
    _spec({
      'type': 'column',
      'children': [
        {'type': 'text', 'style': 'title', 'text': '棕榈油早报'},
        {'type': 'text', 'style': 'subtitle', 'text': '主力 \${fmt(data.q.last, 0)}'},
        {'type': 'text', 'text': '正文：今天偏强。'},
        {'type': 'text', 'style': 'up', 'text': '上涨 \${pct(data.q.pct_chg)}'},
        {'type': 'text', 'style': 'down', 'text': '下跌示例'},
        {'type': 'text', 'style': 'muted', 'text': '仅供参考'},
      ]
    }),
    const {}
  ),
  'stat': (
    _spec({
      'type': 'row',
      'children': [
        {
          'type': 'stat',
          'label': '主力',
          'value': '=data.q.last',
          'digits': 0,
          'delta': '=data.q.pct_chg',
          'caption': '较昨收'
        },
        {'type': 'stat', 'label': '持仓', 'value': 512340, 'unit': '手', 'tone': 'neutral'},
      ]
    }),
    const {}
  ),
  'row_column_card': (
    _spec({
      'type': 'card',
      'title': '卡片标题',
      'subtitle': '副标题',
      'children': [
        {
          'type': 'row',
          'children': [
            {'type': 'text', 'text': '左'},
            {'type': 'text', 'text': '中'},
            {'type': 'text', 'text': '右'},
          ]
        },
        {'type': 'text', 'style': 'caption', 'text': '下面一行'},
      ]
    }),
    const {}
  ),
  'list': (
    _spec({
      'type': 'list',
      'items': '=data.news.items',
      'item': {
        'type': 'column',
        'gap': 2,
        'children': [
          {'type': 'text', 'style': 'subtitle', 'text': '\${item.title}'},
          {'type': 'text', 'style': 'muted', 'text': '\${item.source}'},
        ]
      }
    }),
    const {}
  ),
  'table': (
    _spec({
      'type': 'table',
      'rows':
          "=[{'n': '千岛湖', 'a': 86, 'b': 0.012}, {'n': '青山湖', 'a': 72, 'b': -0.004}]",
      'highlight_max': ['a'],
      'columns': [
        {'key': 'n', 'title': '名称'},
        {'key': 'a', 'title': '指数', 'format': 'num'},
        {'key': 'b', 'title': '涨跌', 'format': 'pct'},
      ]
    }),
    const {}
  ),
  'chart_line': (
    _spec({
      'type': 'chart',
      'kind': 'line',
      'x': "=map(data.bars.items, 'date')",
      'series': [
        {'name': '收盘', 'y': "=map(data.bars.items, 'close')"},
        {'name': '开盘', 'y': "=map(data.bars.items, 'open')"},
      ]
    }),
    const {}
  ),
  'chart_bar': (
    _spec({
      'type': 'chart',
      'kind': 'bar',
      'x': "=['周一', '周二', '周三', '周四']",
      'series': [
        {'name': '渔获', 'y': '=[3, 5, -2, 8]'}
      ],
      'height': 140,
    }),
    const {}
  ),
  'kline': (
    _spec({'type': 'kline', 'bars': '=data.bars.items'}),
    const {}
  ),
  'input': (
    _spec({
      'type': 'column',
      'children': [
        {'type': 'input', 'bind': 'amount'},
        {'type': 'input', 'bind': 'kind', 'style': 'chips'},
        {'type': 'input', 'bind': 'on'},
        {'type': 'input', 'bind': 'name'},
      ]
    }, inputs: {
      'amount': {'type': 'number', 'label': '每月定投', 'default': 1000, 'min': 100, 'max': 10000, 'step': 100, 'unit': '元'},
      'kind': {'type': 'enum', 'label': '品种', 'options': ['豆油', '棕榈油', '菜籽油'], 'default': '棕榈油'},
      'on': {'type': 'bool', 'label': '包含夜盘', 'default': true},
      'name': {'type': 'text', 'label': '备注', 'default': '早盘看'},
    }),
    const {}
  ),
  'broken': (
    _spec({
      'type': 'column',
      'children': [
        {'type': 'mystery'},
        {'type': 'kline', 'bars': '=data.bars.items'},
        {'type': 'stat', 'label': '取不到时', 'value': '=data.bars.last'},
      ]
    }),
    const {'bars': '数据源超时'}
  ),
};

void main() {
  setUpAll(loadGoldenFonts);

  for (final e in _cases.entries) {
    testWidgets('组件金图：${e.key}', (tester) async {
      tester.view.physicalSize = const Size(390, 420);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final (spec, errors) = e.value;
      final rt = SpecRuntime(spec);
      final inputs = rt.resolveInputs(const {}, _now);
      final data = errors.isEmpty
          ? _data
          : {for (final d in _data.entries) if (!errors.containsKey(d.key)) d.key: d.value};
      final env = rt.env(inputs: inputs, data: data, now: () => _now);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(ThemeMode.light),
        home: Scaffold(
          backgroundColor: AppColors.bgBase,
          body: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: SingleChildScrollView(
              child: MiniAppRenderer(
                runtime: rt,
                node: rt.layout,
                env: env,
                errors: errors,
                onInput: (_, __) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 不应该出现兜底（broken 用例除外）。
      if (e.key != 'broken') {
        expect(find.textContaining('暂时显示不了'), findsNothing);
        expect(find.textContaining('不认识的组件'), findsNothing);
      } else {
        expect(find.textContaining('不认识的组件'), findsOneWidget);
        expect(find.textContaining('数据暂时取不到'), findsOneWidget);
      }
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/miniapp_component_${e.key}.png'));
    }, skip: !Platform.environment.containsKey('STRATEGY_FONT_DIR'));
  }

  testWidgets('卡片模式（compact）不画输入控件', (tester) async {
    final (spec, _) = _cases['input']!;
    final rt = SpecRuntime(spec);
    final env = rt.env(
        inputs: rt.resolveInputs(const {}, _now), data: const {}, now: () => _now);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: MiniAppRenderer(runtime: rt, node: rt.layout, env: env, compact: true)),
    ));
    expect(find.text('每月定投'), findsNothing);
  });

  testWidgets('需要更高渲染器版本时给升级提示', (tester) async {
    final spec = {..._cases['text']!.$1, 'min_renderer': kMiniAppRendererVersion + 1};
    final rt = SpecRuntime(spec);
    final env = rt.env(inputs: const {}, data: const {}, now: () => _now);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MiniAppRenderer(runtime: rt, node: rt.layout, env: env)),
    ));
    expect(find.textContaining('新版 App'), findsOneWidget);
  });
}
