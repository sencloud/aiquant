/// spec 的客户端运行时：参数解析、computed 求值（拓扑序）、表达式缓存。
///
/// 与后端 run.go 的 ResolveInputs / EvalComputed 同构。数据（data.*）只来自
/// 服务端 run 接口；computed 与组件属性全在本地求值，所以纯计算器类的小应用
/// 改参数时立即重算、离线也能用。
library;

import '../expr/xel.dart';

/// 一个参数定义。
class InputDef {
  InputDef(this.key, Map<String, dynamic> m)
      : type = m['type'] as String? ?? 'text',
        label = m['label'] as String? ?? key,
        options = [for (final o in (m['options'] as List? ?? const [])) '$o'],
        min = (m['min'] as num?)?.toDouble(),
        max = (m['max'] as num?)?.toDouble(),
        step = (m['step'] as num?)?.toDouble(),
        unit = m['unit'] as String?,
        placeholder = m['placeholder'] as String?,
        maxItems = (m['max_items'] as num?)?.toInt() ?? 5,
        fields = {
          for (final e in ((m['item'] as Map?) ?? const {}).entries)
            '${e.key}': ((e.value as Map?)?['type'] as String?) ?? 'text'
        },
        rawDefault = m['default'];

  final String key;
  final String type;
  final String label;
  final List<String> options;
  final double? min, max, step;
  final String? unit;
  final String? placeholder;
  final int maxItems;
  final Map<String, String> fields;
  final dynamic rawDefault;

  dynamic get defaultValue {
    switch (type) {
      case 'number':
        return rawDefault is num ? (rawDefault as num).toDouble() : 0.0;
      case 'enum':
        return rawDefault is String
            ? rawDefault
            : (options.isNotEmpty ? options.first : '');
      case 'bool':
        return rawDefault == true;
      case 'list':
        return rawDefault is List ? normalize(rawDefault) : <dynamic>[];
      default:
        return rawDefault is String ? rawDefault : '';
    }
  }

  bool accepts(dynamic v) {
    switch (type) {
      case 'number':
        return v is num;
      case 'text':
        return v is String && v.runes.length <= 40;
      case 'enum':
        return v is String && options.contains(v);
      case 'date':
        return v is String &&
            (v.isEmpty || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v));
      case 'bool':
        return v is bool;
      case 'list':
        if (v is! List || v.length > maxItems) return false;
        for (final e in v) {
          if (e is! Map) return false;
          for (final f in e.entries) {
            final t = fields['${f.key}'];
            if (t == 'text' && !(f.value is String && (f.value as String).runes.length <= 30)) {
              return false;
            }
            if (t == 'number' && f.value is! num) return false;
            if (t == null) return false;
          }
        }
        return true;
    }
    return false;
  }
}

/// 编译好的 spec。
class SpecRuntime {
  SpecRuntime(Map<String, dynamic> spec)
      : spec = spec,
        meta = (spec['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        inputs = {
          for (final e
              in ((spec['inputs'] as Map?) ?? const {}).entries)
            '${e.key}': InputDef('${e.key}',
                (e.value as Map?)?.cast<String, dynamic>() ?? const {})
        } {
    final comp = (spec['computed'] as Map?) ?? const {};
    final raw = <String, Expr>{};
    for (final e in comp.entries) {
      final ex = Expr.tryCompile('${e.value}');
      if (ex != null) raw['${e.key}'] = ex;
    }
    _computed = raw;
    _order = _topo(raw);
    final data = (spec['data'] as Map?) ?? const {};
    for (final b in data.values) {
      if (b is! Map) continue;
      final srcs = <String>[
        if (b['each'] is String) b['each'] as String,
        for (final p in ((b['params'] as Map?) ?? const {}).values)
          if (p is String && p.startsWith('=')) p,
      ];
      for (final s in srcs) {
        for (final k in inputs.keys) {
          if (s.contains('inputs.$k')) dataInputs.add(k);
        }
      }
    }
    hasData = data.isNotEmpty;
  }

  final Map<String, dynamic> spec;
  final Map<String, dynamic> meta;
  final Map<String, InputDef> inputs;

  /// 被数据绑定参数引用的参数：改它们需要重新取数（其余只需本地重算）。
  final Set<String> dataInputs = {};
  late final bool hasData;
  late final Map<String, Expr> _computed;
  late final List<String> _order;
  final Map<String, Expr?> _exprCache = {};
  final Map<String, XelTemplate?> _tplCache = {};

  String get title => meta['title'] as String? ?? '';
  String get icon => meta['icon'] as String? ?? 'apps';
  String get disclaimer => meta['disclaimer'] as String? ?? '';
  String get cardSize => meta['card_size'] as String? ?? 'medium';
  int get minRenderer => (spec['min_renderer'] as num?)?.toInt() ?? 1;
  Map<String, dynamic>? get cardView =>
      (spec['card_view'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get layout =>
      (spec['layout'] as Map?)?.cast<String, dynamic>();

  static List<String> _topo(Map<String, Expr> m) {
    final out = <String>[];
    final state = <String, int>{};
    void visit(String k) {
      if (state[k] == 2) return;
      if (state[k] == 1) return; // 环（服务端已拒绝）：忽略
      state[k] = 1;
      for (final r in m[k]!.roots()) {
        if (r != k && m.containsKey(r)) visit(r);
      }
      state[k] = 2;
      out.add(k);
    }

    final keys = m.keys.toList()..sort();
    for (final k in keys) {
      visit(k);
    }
    return out;
  }

  /// 用户值 + 默认值 → 完整参数（不合法的回落到默认值；数字夹在 min/max 内）。
  Map<String, dynamic> resolveInputs(Map<String, dynamic> user, DateTime now) {
    final out = <String, dynamic>{};
    inputs.forEach((k, d) {
      var v = user[k];
      if (v == null || !d.accepts(v)) v = d.defaultValue;
      if (d.type == 'number') {
        var f = v is num ? v.toDouble() : 0.0;
        if (d.min != null && f < d.min!) f = d.min!;
        if (d.max != null && f > d.max!) f = d.max!;
        v = f;
      }
      if (d.type == 'date' && v == '') {
        v = Expr.compile('today()').eval(XelEnv(const {}, now: () => now));
      }
      out[k] = normalize(v);
    });
    return out;
  }

  /// 构造求值环境：inputs / data / state + computed（按拓扑序逐个求值）。
  XelEnv env({
    required Map<String, dynamic> inputs,
    required Map<String, dynamic> data,
    Map<String, dynamic> state = const {},
    DateTime Function()? now,
  }) {
    final vars = <String, dynamic>{
      'inputs': inputs,
      'data': data,
      'state': state,
    };
    final e = XelEnv(vars, now: now);
    for (final k in _order) {
      vars[k] = _computed[k]!.evalOrNull(e);
    }
    return e;
  }

  Expr? expr(String src) =>
      _exprCache.putIfAbsent(src, () => Expr.tryCompile(src));

  XelTemplate? template(String src) =>
      _tplCache.putIfAbsent(src, () => XelTemplate.tryCompile(src));

  /// 求属性值：字面量原样返回；"=表达式" 求值。
  dynamic value(dynamic v, XelEnv env) {
    if (v is String && v.startsWith('=')) {
      return expr(v.substring(1))?.evalOrNull(env);
    }
    return v;
  }

  /// 渲染字符串模板属性。
  String text(dynamic v, XelEnv env) {
    if (v == null) return '';
    if (v is! String) return str(v);
    if (v.startsWith('=')) return str(value(v, env));
    if (!v.contains(r'${')) return v;
    return template(v)?.render(env) ?? '';
  }
}
