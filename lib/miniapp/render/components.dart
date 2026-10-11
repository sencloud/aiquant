/// 小应用渲染器：把 spec 的组件树画成原生组件。
///
/// 每个组件独立兜底：某个组件的数据或表达式出错时只把它画成一条灰色占位，
/// 不影响同一页的其他组件。没有任何可执行代码，只有组件目录 v1 里的 10 种组件。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../expr/xel.dart';
import 'charts.dart';
import 'input_controls.dart';
import 'spec_runtime.dart';

/// 本客户端渲染器版本（spec.min_renderer 大于它时提示升级）。
const int kMiniAppRendererVersion = 1;

typedef InputChanged = void Function(String key, dynamic value);

class MiniAppRenderer extends StatelessWidget {
  const MiniAppRenderer({
    super.key,
    required this.runtime,
    required this.node,
    required this.env,
    this.compact = false,
    this.onInput,
    this.errors = const {},
  });

  final SpecRuntime runtime;
  final Map<String, dynamic>? node;
  final XelEnv env;

  /// 发现页卡片：不画输入控件，字号收一档。
  final bool compact;
  final InputChanged? onInput;

  /// 数据源错误（data 别名 → 错误信息），用于把依赖它的组件标灰。
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    if (runtime.minRenderer > kMiniAppRendererVersion) {
      return const _Broken('这个小应用需要新版 App，请先升级');
    }
    final n = node;
    if (n == null) return const SizedBox.shrink();
    return _Builder(runtime, compact, onInput, errors).build(n, env);
  }
}

class _Builder {
  _Builder(this.rt, this.compact, this.onInput, this.errors);
  final SpecRuntime rt;
  final bool compact;
  final InputChanged? onInput;
  final Map<String, String> errors;

  Widget build(dynamic raw, XelEnv env) {
    if (raw is! Map) return const SizedBox.shrink();
    final n = raw.cast<String, dynamic>();
    try {
      if (n.containsKey('visible') && !truthy(rt.value(n['visible'], env))) {
        return const SizedBox.shrink();
      }
      switch (n['type']) {
        case 'column':
          return _column(n, env);
        case 'row':
          return _row(n, env);
        case 'card':
          return _card(n, env);
        case 'text':
          return _text(n, env);
        case 'stat':
          return _stat(n, env);
        case 'list':
          return _list(n, env);
        case 'table':
          return _table(n, env);
        case 'chart':
          return _chart(n, env);
        case 'kline':
          return _kline(n, env);
        case 'input':
          return _input(n, env);
      }
      return _Broken('不认识的组件 ${n['type']}');
    } catch (_) {
      return const _Broken('这一块暂时显示不了');
    }
  }

  List<Widget> _children(Map<String, dynamic> n, XelEnv env) => [
        for (final c in (n['children'] as List? ?? const [])) build(c, env)
      ];

  double _gap(Map<String, dynamic> n) =>
      (n['gap'] as num?)?.toDouble() ?? (compact ? AppSpace.sm : AppSpace.md);

  Widget _column(Map<String, dynamic> n, XelEnv env) {
    final kids = _children(n, env);
    final gap = _gap(n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < kids.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          kids[i],
        ]
      ],
    );
  }

  Widget _row(Map<String, dynamic> n, XelEnv env) {
    final kids = _children(n, env);
    final gap = _gap(n);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kids.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: kids[i]),
        ]
      ],
    );
  }

  Widget _card(Map<String, dynamic> n, XelEnv env) {
    final title = rt.text(n['title'], env);
    final sub = rt.text(n['subtitle'], env);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Text(title,
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (sub.isNotEmpty)
            Text(sub,
                style: AppType.caption.copyWith(color: AppColors.textSecondary)),
          if (title.isNotEmpty || sub.isNotEmpty)
            const SizedBox(height: AppSpace.sm),
          _column({'children': n['children']}, env),
        ],
      ),
    );
  }

  Widget _text(Map<String, dynamic> n, XelEnv env) {
    final s = rt.text(n['text'], env);
    if (s.isEmpty) return const SizedBox.shrink();
    TextStyle st;
    switch (n['style']) {
      case 'title':
        st = AppType.title.copyWith(color: AppColors.textPrimary);
      case 'subtitle':
        st = AppType.body
            .copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary);
      case 'caption':
        st = AppType.caption.copyWith(color: AppColors.textSecondary);
      case 'up':
        st = AppType.body.copyWith(color: AppColors.positive);
      case 'down':
        st = AppType.body.copyWith(color: AppColors.negative);
      case 'muted':
        st = AppType.caption.copyWith(color: AppColors.textTertiary);
      default:
        st = AppType.body.copyWith(color: AppColors.textPrimary);
    }
    return Text(s,
        style: compact ? st.copyWith(fontSize: (st.fontSize ?? 15) - 1) : st,
        maxLines: compact ? 2 : null,
        overflow: compact ? TextOverflow.ellipsis : null);
  }

  Color _tone(String? tone, double? basis) {
    switch (tone) {
      case 'up':
        return AppColors.positive;
      case 'down':
        return AppColors.negative;
      case 'neutral':
        return AppColors.textPrimary;
    }
    if (basis == null || basis == 0) return AppColors.textPrimary;
    return basis > 0 ? AppColors.positive : AppColors.negative;
  }

  Widget _stat(Map<String, dynamic> n, XelEnv env) {
    final label = rt.text(n['label'], env);
    final v = rt.value(n['value'], env);
    final digits = (n['digits'] as num?)?.toInt();
    final String value;
    if (v is double) {
      value = digits != null ? fmtNum(v, digits, true) : fmtNum(v, 0, false);
    } else {
      final s = str(v);
      value = s.isEmpty ? '—' : s;
    }
    final unit = rt.text(n['unit'], env);
    final d = n.containsKey('delta') ? rt.value(n['delta'], env) : null;
    String? delta;
    if (d is double) {
      delta = n['delta_format'] == 'abs'
          ? '${d > 0 ? '+' : ''}${fmtNum(d, 0, false)}'
          : pct(d, 2);
    }
    final caption = rt.text(n['caption'], env);
    final color = _tone(n['tone'] as String?, d is double ? d : (v is double ? v : null));
    final big = compact ? 20.0 : 24.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: AppColors.textSecondary)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          // 样式放在 Text.rich 的 style 上（与 DefaultTextStyle 合并，保留字族）；
          // 子 span 里只改字号 / 颜色：子 span 若带 fontFamilyFallback 会整个替换
          // 继承来的字族列表。
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: value),
              if (unit.isNotEmpty)
                TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                        fontSize: AppType.caption.fontSize,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                        color: AppColors.textSecondary)),
            ]),
            style: AppType.display.copyWith(
                fontSize: big,
                color: color,
                fontFamilyFallback: AppType.numericFallback),
          ),
        ),
        if (delta != null)
          Text(delta,
              style: AppType.caption.copyWith(
                  color: _tone(n['tone'] == 'neutral' ? null : n['tone'] as String?, d as double),
                  fontWeight: FontWeight.w600)),
        if (caption.isNotEmpty)
          Text(caption,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  String _emptyText(Map<String, dynamic> n, XelEnv env, String fallback) {
    final s = rt.text(n['empty_text'], env);
    return s.isEmpty ? fallback : s;
  }

  Widget _empty(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Text(s,
            textAlign: TextAlign.center,
            style: AppType.caption.copyWith(color: AppColors.textTertiary)),
      );

  bool _depsFailed(String? exprSrc) {
    if (exprSrc == null || errors.isEmpty || !exprSrc.startsWith('=')) {
      return false;
    }
    final e = rt.expr(exprSrc.substring(1));
    return e != null && e.dataRefs().any(errors.containsKey);
  }

  Widget _list(Map<String, dynamic> n, XelEnv env) {
    if (_depsFailed(n['items'] as String?)) {
      return const _Broken('数据暂时取不到，稍后下拉刷新');
    }
    final items = rt.value(n['items'], env);
    final max = (n['max'] as num?)?.toInt() ?? (compact ? 3 : 20);
    if (items is! List || items.isEmpty) {
      return _empty(_emptyText(n, env, '暂无内容'));
    }
    final shown = items.take(max).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0)
            Divider(height: compact ? 8 : 16, thickness: 0.5, color: AppColors.borderDim),
          build(n['item'], env.withVars({'item': shown[i], 'index': i.toDouble()})),
        ]
      ],
    );
  }

  String _cell(dynamic v, Map col) {
    final digits = (col['digits'] as num?)?.toInt();
    switch (col['format']) {
      case 'num':
        if (v is! double) return str(v);
        return digits != null ? fmtNum(v, digits, true) : fmtNum(v, 0, false);
      case 'pct':
        if (v is! double) return str(v);
        return pct(v, digits ?? 2);
      case 'date':
        if (v is double) {
          return str(Expr.compile('date(x)').evalOrNull(XelEnv({'x': v})));
        }
        return str(v);
    }
    return str(v);
  }

  Widget _table(Map<String, dynamic> n, XelEnv env) {
    if (_depsFailed(n['rows'] as String?)) {
      return const _Broken('数据暂时取不到，稍后下拉刷新');
    }
    final rows = rt.value(n['rows'], env);
    final cols = [
      for (final c in (n['columns'] as List? ?? const []))
        if (c is Map) c
    ];
    if (rows is! List || rows.isEmpty || cols.isEmpty) {
      return _empty(_emptyText(n, env, '暂无数据'));
    }
    final maxRows = (n['max_rows'] as num?)?.toInt() ?? (compact ? 3 : 50);
    final shown = rows.take(maxRows).toList();
    final hl = {for (final s in (n['highlight_max'] as List? ?? const [])) '$s'};
    final maxOf = <String, double>{};
    for (final k in hl) {
      for (final r in shown) {
        final v = r is Map ? r[k] : null;
        if (v is double && (maxOf[k] == null || v > maxOf[k]!)) maxOf[k] = v;
      }
    }
    TextStyle head = AppType.micro.copyWith(color: AppColors.textTertiary);
    TextStyle body = (compact ? AppType.caption : AppType.body)
        .copyWith(color: AppColors.textPrimary);
    Widget cell(String s, TextStyle st, {bool right = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(s,
              style: st,
              textAlign: right ? TextAlign.right : TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        );
    final table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var i = 0; i < cols.length; i++)
          i: i == 0 ? const FlexColumnWidth(1.4) : const FlexColumnWidth(1),
      },
      border: TableBorder(
          horizontalInside: BorderSide(color: AppColors.borderDim, width: 0.5)),
      children: [
        TableRow(children: [
          for (var i = 0; i < cols.length; i++)
            cell('${cols[i]['title'] ?? ''}', head, right: i > 0),
        ]),
        for (final r in shown)
          TableRow(children: [
            for (var i = 0; i < cols.length; i++)
              () {
                final k = '${cols[i]['key']}';
                final v = r is Map ? r[k] : null;
                final isMax = maxOf[k] != null && v == maxOf[k];
                return cell(
                    _cell(v, cols[i]),
                    isMax
                        ? body.copyWith(
                            color: AppColors.amber, fontWeight: FontWeight.w700)
                        : body,
                    right: i > 0);
              }(),
          ]),
      ],
    );
    if (cols.length <= 4) return table;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: cols.length * 84.0),
          child: SizedBox(width: cols.length * 84.0, child: table)),
    );
  }

  Widget _chart(Map<String, dynamic> n, XelEnv env) {
    if (_depsFailed(n['x'] as String?)) {
      return const _Broken('数据暂时取不到，稍后下拉刷新');
    }
    final x = rt.value(n['x'], env);
    final labels = x is List ? x.map(str).toList() : <String>[];
    final series = <ChartSeries>[
      for (final s in (n['series'] as List? ?? const []))
        if (s is Map)
          () {
            final y = rt.value(s['y'], env);
            return ChartSeries('${s['name'] ?? ''}', [
              if (y is List)
                for (final v in y) v is double && v.isFinite ? v : null
            ]);
          }(),
    ];
    final h = (n['height'] as num?)?.toDouble() ?? (compact ? 72 : 160);
    return MiniChart(
        kind: '${n['kind'] ?? 'line'}', labels: labels, series: series, height: h);
  }

  Widget _kline(Map<String, dynamic> n, XelEnv env) {
    if (_depsFailed(n['bars'] as String?)) {
      return const _Broken('数据暂时取不到，稍后下拉刷新');
    }
    final raw = rt.value(n['bars'], env);
    final bars = <KBar>[
      if (raw is List)
        for (final b in raw)
          if (b is Map &&
              b['open'] is double &&
              b['high'] is double &&
              b['low'] is double &&
              b['close'] is double)
            KBar('${b['date'] ?? ''}', b['open'] as double, b['high'] as double,
                b['low'] as double, b['close'] as double),
    ];
    final h = (n['height'] as num?)?.toDouble() ?? (compact ? 96 : 200);
    return MiniKline(bars: bars, height: h);
  }

  Widget _input(Map<String, dynamic> n, XelEnv env) {
    if (compact) return const SizedBox.shrink();
    final key = '${n['bind']}';
    final def = rt.inputs[key];
    if (def == null) return const _Broken('参数不存在');
    final inputs = env.vars['inputs'];
    final value = inputs is Map ? inputs[key] : null;
    return MiniAppInputControl(
      def: def,
      value: value,
      style: '${n['style'] ?? 'auto'}',
      onChanged: onInput == null ? null : (v) => onInput!(key, v),
    );
  }
}

/// 组件级兜底：灰色一行。
class _Broken extends StatelessWidget {
  const _Broken(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
        ),
      ]),
    );
  }
}
