/// 小应用受限表达式（XEL）的 Dart 实现。
///
/// 与后端 `backend/internal/miniapp/xel` 逐字同构：同一份
/// `testdata/conformance.json` 两端各跑一遍（见 test/miniapp_xel_test.dart）。
/// 没有循环、赋值、自定义函数，也不能联网或读写存储 —— 下发的是数据，不是程序。
///
/// 值的形态与 JSON 一致：null / bool / double / String / List / Map<String, dynamic>。
/// 数字一律是 double（[normalize] 把 JSON 里的 int 转成 double）。
library;

import 'dart:convert' show utf8;
import 'dart:math' as math;

const int maxExprLen = 512;
const int maxDepth = 32;
const int maxSteps = 10000;
const int maxArray = 5000;

class XelError implements Exception {
  XelError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 把 JSON 值规整成求值用的形态（int → double，Map 键转 String）。
dynamic normalize(dynamic v) {
  if (v == null || v is bool || v is String || v is double) return v;
  if (v is num) return v.toDouble();
  if (v is List) return [for (final e in v) normalize(e)];
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): normalize(e.value)
    };
  }
  return null;
}

// ─── AST ───────────────────────────────────────────────────────────────

abstract class _Node {}

class _Lit extends _Node {
  _Lit(this.v);
  final dynamic v;
}

class _Ident extends _Node {
  _Ident(this.name);
  final String name;
}

class _Member extends _Node {
  _Member(this.obj, this.name);
  final _Node obj;
  final String name;
}

class _Index extends _Node {
  _Index(this.obj, this.idx);
  final _Node obj, idx;
}

class _Unary extends _Node {
  _Unary(this.op, this.x);
  final String op;
  final _Node x;
}

class _Binary extends _Node {
  _Binary(this.op, this.l, this.r);
  final String op;
  final _Node l, r;
}

class _Cond extends _Node {
  _Cond(this.c, this.a, this.b);
  final _Node c, a, b;
}

class _Call extends _Node {
  _Call(this.name, this.args);
  final String name;
  final List<_Node> args;
}

class _Array extends _Node {
  _Array(this.elems);
  final List<_Node> elems;
}

class _Obj extends _Node {
  _Obj(this.keys, this.vals);
  final List<String> keys;
  final List<_Node> vals;
}

Iterable<_Node> _children(_Node n) sync* {
  if (n is _Member) {
    yield n.obj;
  } else if (n is _Index) {
    yield n.obj;
    yield n.idx;
  } else if (n is _Unary) {
    yield n.x;
  } else if (n is _Binary) {
    yield n.l;
    yield n.r;
  } else if (n is _Cond) {
    yield n.c;
    yield n.a;
    yield n.b;
  } else if (n is _Call) {
    yield* n.args;
  } else if (n is _Array) {
    yield* n.elems;
  } else if (n is _Obj) {
    yield* n.vals;
  }
}

int _depthOf(_Node n) {
  var m = 0;
  for (final c in _children(n)) {
    final d = _depthOf(c);
    if (d > m) m = d;
  }
  return m + 1;
}

void _walk(_Node n, void Function(_Node) f) {
  f(n);
  for (final c in _children(n)) {
    _walk(c, f);
  }
}

// ─── 词法 ───────────────────────────────────────────────────────────────

enum _K { eof, num, str, ident, punct }

class _Tok {
  _Tok(this.kind, this.pos, {this.s = '', this.n = 0});
  final _K kind;
  final String s;
  final double n;
  final int pos;
}

const _puncts = [
  '&&', '||', '??', '==', '!=', '<=', '>=', //
  '(', ')', '[', ']', '{', '}', ',', '.', ':', '?', '+', '-', '*', '/', '%',
  '!', '<', '>',
];

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isIdentStart(int c) =>
    c == 0x5F || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);

List<_Tok> _lex(String src) {
  final out = <_Tok>[];
  var i = 0;
  while (i < src.length) {
    final c = src.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
    } else if (_isDigit(c)) {
      var j = i;
      while (j < src.length && _isDigit(src.codeUnitAt(j))) {
        j++;
      }
      if (j < src.length &&
          src.codeUnitAt(j) == 0x2E &&
          j + 1 < src.length &&
          _isDigit(src.codeUnitAt(j + 1))) {
        j++;
        while (j < src.length && _isDigit(src.codeUnitAt(j))) {
          j++;
        }
      }
      final n = double.parse(src.substring(i, j));
      if (n.isInfinite) throw XelError('位置 $i：数字格式不正确');
      out.add(_Tok(_K.num, i, n: n));
      i = j;
    } else if (c == 0x27 || c == 0x22) {
      final q = c;
      var j = i + 1;
      final sb = StringBuffer();
      var closed = false;
      while (j < src.length) {
        final d = src.codeUnitAt(j);
        if (d == 0x5C && j + 1 < src.length) {
          final e = src[j + 1];
          sb.write(e == 'n' ? '\n' : (e == 't' ? '\t' : e));
          j += 2;
          continue;
        }
        if (d == q) {
          closed = true;
          j++;
          break;
        }
        sb.writeCharCode(d);
        j++;
      }
      if (!closed) throw XelError('位置 $i：字符串缺少结束引号');
      out.add(_Tok(_K.str, i, s: sb.toString()));
      i = j;
    } else if (_isIdentStart(c)) {
      var j = i;
      while (j < src.length &&
          (_isIdentStart(src.codeUnitAt(j)) || _isDigit(src.codeUnitAt(j)))) {
        j++;
      }
      out.add(_Tok(_K.ident, i, s: src.substring(i, j)));
      i = j;
    } else {
      String? m;
      for (final p in _puncts) {
        if (src.startsWith(p, i)) {
          m = p;
          break;
        }
      }
      if (m == null) {
        throw XelError('位置 $i：不支持的字符 "${String.fromCharCode(src.runes.elementAt(_runeIndex(src, i)))}"');
      }
      out.add(_Tok(_K.punct, i, s: m));
      i += m.length;
    }
  }
  out.add(_Tok(_K.eof, src.length));
  return out;
}

int _runeIndex(String s, int unitIndex) {
  var r = 0;
  for (var k = 0; k < unitIndex && k < s.length; k++) {
    final c = s.codeUnitAt(k);
    if (c < 0xDC00 || c > 0xDFFF) r++;
  }
  return r;
}

// ─── 语法 ───────────────────────────────────────────────────────────────

class _FnSpec {
  const _FnSpec(this.min, this.max, {this.lazy = false});
  final int min, max;
  final bool lazy;
}

const Map<String, _FnSpec> _funcs = {
  'round': _FnSpec(1, 2),
  'floor': _FnSpec(1, 1),
  'ceil': _FnSpec(1, 1),
  'abs': _FnSpec(1, 1),
  'pow': _FnSpec(2, 2),
  'sqrt': _FnSpec(1, 1),
  'clamp': _FnSpec(3, 3),
  'min': _FnSpec(1, -1),
  'max': _FnSpec(1, -1),
  'sum': _FnSpec(1, 2, lazy: true),
  'avg': _FnSpec(1, 2, lazy: true),
  'count': _FnSpec(1, 2, lazy: true),
  'map': _FnSpec(2, 2, lazy: true),
  'filter': _FnSpec(2, 2, lazy: true),
  'sort_by': _FnSpec(2, 3, lazy: true),
  'zip_with': _FnSpec(3, 3, lazy: true),
  'len': _FnSpec(1, 1),
  'range': _FnSpec(2, 2),
  'group_sum': _FnSpec(3, 3, lazy: true),
  'first': _FnSpec(1, 1),
  'last': _FnSpec(1, 1),
  'slice': _FnSpec(2, 3),
  'reverse': _FnSpec(1, 1),
  'join': _FnSpec(1, 2),
  'contains': _FnSpec(2, 2),
  'fmt': _FnSpec(1, 2),
  'pct': _FnSpec(1, 2),
  'str': _FnSpec(1, 1),
  'num': _FnSpec(1, 1),
  'today': _FnSpec(0, 0),
  'now': _FnSpec(0, 0),
  'date': _FnSpec(1, 1),
  'date_add': _FnSpec(2, 2),
  'month_start': _FnSpec(0, 0),
  'days_between': _FnSpec(2, 2),
};

const _precedence = <Set<String>>[
  {'??'},
  {'||'},
  {'&&'},
  {'==', '!='},
  {'<', '<=', '>', '>='},
  {'+', '-'},
  {'*', '/', '%'},
];

class _Parser {
  _Parser(this.toks);
  final List<_Tok> toks;
  int i = 0;

  _Tok get peek => toks[i];
  _Tok next() => toks[i++];
  bool isP(String s) => peek.kind == _K.punct && peek.s == s;
  void expect(String s) {
    if (!isP(s)) throw XelError('位置 ${peek.pos}：缺少 "$s"');
    i++;
  }

  _Node parseExpr() {
    final c = parseBinary(0);
    if (isP('?')) {
      i++;
      final a = parseExpr();
      expect(':');
      final b = parseExpr();
      return _Cond(c, a, b);
    }
    return c;
  }

  _Node parseBinary(int level) {
    if (level >= _precedence.length) return parseUnary();
    var l = parseBinary(level + 1);
    while (true) {
      final t = peek;
      if (t.kind != _K.punct || !_precedence[level].contains(t.s)) return l;
      i++;
      final r = parseBinary(level + 1);
      l = _Binary(t.s, l, r);
    }
  }

  _Node parseUnary() {
    if (isP('!') || isP('-')) {
      final op = next().s;
      return _Unary(op, parseUnary());
    }
    return parsePostfix();
  }

  _Node parsePostfix() {
    var n = parsePrimary();
    while (true) {
      if (isP('.')) {
        i++;
        final t = next();
        if (t.kind != _K.ident) throw XelError('位置 ${t.pos}：. 后面应是字段名');
        n = _Member(n, t.s);
      } else if (isP('[')) {
        i++;
        final idx = parseExpr();
        expect(']');
        n = _Index(n, idx);
      } else {
        return n;
      }
    }
  }

  _Node parsePrimary() {
    final t = next();
    switch (t.kind) {
      case _K.num:
        return _Lit(t.n);
      case _K.str:
        return _Lit(t.s);
      case _K.ident:
        if (t.s == 'true') return _Lit(true);
        if (t.s == 'false') return _Lit(false);
        if (t.s == 'null') return _Lit(null);
        if (isP('(')) {
          i++;
          final f = _funcs[t.s];
          if (f == null) throw XelError('不支持的函数 ${t.s}()');
          final args = <_Node>[];
          while (!isP(')')) {
            args.add(parseExpr());
            if (isP(',')) {
              i++;
              continue;
            }
            if (!isP(')')) throw XelError('位置 ${peek.pos}：参数之间缺少逗号');
          }
          i++;
          if (args.length < f.min || (f.max >= 0 && args.length > f.max)) {
            throw XelError('${t.s}() 参数个数不对');
          }
          return _Call(t.s, args);
        }
        return _Ident(t.s);
      case _K.punct:
        if (t.s == '(') {
          final n = parseExpr();
          expect(')');
          return n;
        }
        if (t.s == '[') {
          final elems = <_Node>[];
          while (!isP(']')) {
            elems.add(parseExpr());
            if (isP(',')) {
              i++;
              continue;
            }
            if (!isP(']')) throw XelError('位置 ${peek.pos}：数组元素之间缺少逗号');
          }
          i++;
          return _Array(elems);
        }
        if (t.s == '{') {
          final keys = <String>[];
          final vals = <_Node>[];
          while (!isP('}')) {
            final k = next();
            if (k.kind != _K.str && k.kind != _K.ident) {
              throw XelError('位置 ${k.pos}：对象的键应是字符串');
            }
            expect(':');
            keys.add(k.s);
            vals.add(parseExpr());
            if (isP(',')) {
              i++;
              continue;
            }
            if (!isP('}')) throw XelError('位置 ${peek.pos}：对象成员之间缺少逗号');
          }
          i++;
          return _Obj(keys, vals);
        }
        break;
      case _K.eof:
        throw XelError('表达式不完整');
    }
    throw XelError('位置 ${t.pos}：意外的 "${t.s}"');
  }
}

/// 编译好的表达式。
class Expr {
  Expr._(this.src, this._root);
  final String src;
  final _Node _root;

  /// 编译表达式源码（不含开头的 "="）。失败抛 [XelError]。
  static Expr compile(String src) {
    if (utf8.encode(src).length > maxExprLen) {
      throw XelError('表达式超过 $maxExprLen 字符');
    }
    if (src.trim().isEmpty) throw XelError('表达式为空');
    final p = _Parser(_lex(src));
    final n = p.parseExpr();
    if (p.peek.kind != _K.eof) throw XelError('位置 ${p.peek.pos}：多余的内容');
    if (_depthOf(n) > maxDepth) throw XelError('表达式嵌套太深');
    return Expr._(src, n);
  }

  /// 编译失败时返回 null。
  static Expr? tryCompile(String src) {
    try {
      return compile(src);
    } on XelError {
      return null;
    }
  }

  /// 求值。超限时抛 [XelError]；访问不存在的字段不算错误，结果为 null。
  dynamic eval(XelEnv env) => _Evaluator(env).eval(_root);

  /// 求值，出错时返回 null（渲染层用）。
  dynamic evalOrNull(XelEnv env) {
    try {
      return eval(env);
    } on XelError {
      return null;
    }
  }

  /// 引用到的顶层标识符（去重、排序）。
  List<String> roots() {
    final set = <String>{};
    _walk(_root, (n) {
      if (n is _Ident) set.add(n.name);
    });
    return set.toList()..sort();
  }

  /// data.<alias> 形式引用到的别名。
  List<String> dataRefs() {
    final set = <String>{};
    _walk(_root, (n) {
      if (n is _Member && n.obj is _Ident && (n.obj as _Ident).name == 'data') {
        set.add(n.name);
      } else if (n is _Index &&
          n.obj is _Ident &&
          (n.obj as _Ident).name == 'data' &&
          n.idx is _Lit &&
          (n.idx as _Lit).v is String) {
        set.add((n.idx as _Lit).v as String);
      }
    });
    return set.toList()..sort();
  }
}

/// 求值环境。
class XelEnv {
  XelEnv(this.vars, {DateTime Function()? now}) : now = now ?? DateTime.now;
  final Map<String, dynamic> vars;
  final DateTime Function() now;

  XelEnv withVars(Map<String, dynamic> extra) =>
      XelEnv({...vars, ...extra}, now: now);
}

class _Evaluator {
  _Evaluator(this.env);
  final XelEnv env;
  int steps = 0;
  final List<Map<String, dynamic>> scopes = [];

  dynamic lookup(String name) {
    for (var i = scopes.length - 1; i >= 0; i--) {
      if (scopes[i].containsKey(name)) return scopes[i][name];
    }
    return env.vars[name];
  }

  dynamic eval(_Node n) {
    steps++;
    if (steps > maxSteps) throw XelError('表达式计算量超限');
    if (n is _Lit) return n.v;
    if (n is _Ident) return lookup(n.name);
    if (n is _Member) {
      final o = eval(n.obj);
      return o is Map ? o[n.name] : null;
    }
    if (n is _Index) {
      final o = eval(n.obj);
      final i = eval(n.idx);
      return _index(o, i);
    }
    if (n is _Unary) {
      final x = eval(n.x);
      if (n.op == '!') return !truthy(x);
      return x is double ? -x : null;
    }
    if (n is _Binary) return binary(n);
    if (n is _Cond) return truthy(eval(n.c)) ? eval(n.a) : eval(n.b);
    if (n is _Array) return [for (final e in n.elems) eval(e)];
    if (n is _Obj) {
      final out = <String, dynamic>{};
      for (var i = 0; i < n.keys.length; i++) {
        out[n.keys[i]] = eval(n.vals[i]);
      }
      return out;
    }
    if (n is _Call) return call(n);
    return null;
  }

  dynamic binary(_Binary v) {
    final l = eval(v.l);
    switch (v.op) {
      case '&&':
        if (!truthy(l)) return false;
        return truthy(eval(v.r));
      case '||':
        if (truthy(l)) return true;
        return truthy(eval(v.r));
      case '??':
        if (l != null) return l;
        return eval(v.r);
    }
    final r = eval(v.r);
    switch (v.op) {
      case '==':
        return _equal(l, r);
      case '!=':
        return !_equal(l, r);
      case '+':
        if (l is String || r is String) {
          return (l is String ? l : str(l)) + (r is String ? r : str(r));
        }
        break;
      case '<':
      case '<=':
      case '>':
      case '>=':
        if (l is double && r is double) return _cmpOp(v.op, _compareF(l, r));
        if (l is String && r is String) {
          return _cmpOp(v.op, _compareStr(l, r));
        }
        return false;
    }
    if (l is! double || r is! double) return null;
    switch (v.op) {
      case '+':
        return l + r;
      case '-':
        return l - r;
      case '*':
        return l * r;
      case '/':
        return r == 0 ? null : l / r;
      case '%':
        return r == 0 ? null : l.remainder(r);
    }
    return null;
  }

  double? _num(List<dynamic> args, int i) {
    if (i >= args.length) return null;
    final f = args[i];
    if (f is double && !f.isNaN) return f;
    return null;
  }

  dynamic call(_Call c) {
    final f = _funcs[c.name]!;
    if (f.lazy) return callLazy(c);
    final args = [for (final a in c.args) eval(a)];
    switch (c.name) {
      case 'round':
        final x = _num(args, 0);
        if (x == null) return null;
        var n = 0.0;
        if (args.length > 1) {
          final m = _num(args, 1);
          if (m == null) return null;
          n = m;
        }
        final d = _clamp(n, 0, 6).toInt();
        final p = math.pow(10, d).toDouble();
        return (x * p).roundToDouble() / p;
      case 'floor':
      case 'ceil':
      case 'abs':
      case 'sqrt':
        final x = _num(args, 0);
        if (x == null) return null;
        switch (c.name) {
          case 'floor':
            return x.floorToDouble();
          case 'ceil':
            return x.ceilToDouble();
          case 'abs':
            return x.abs();
        }
        if (x < 0) return null;
        return math.sqrt(x);
      case 'pow':
        final x = _num(args, 0), y = _num(args, 1);
        if (x == null || y == null) return null;
        final r = math.pow(x, y).toDouble();
        if (r.isNaN || r.isInfinite) return null;
        return r;
      case 'clamp':
        final x = _num(args, 0), lo = _num(args, 1), hi = _num(args, 2);
        if (x == null || lo == null || hi == null) return null;
        return _clamp(x, lo, hi);
      case 'min':
      case 'max':
        var vals = args;
        if (args.length == 1 && args[0] is List) vals = args[0] as List;
        double? best;
        for (final v in vals) {
          if (v is! double || v.isNaN) continue;
          if (best == null ||
              (c.name == 'min' && v < best) ||
              (c.name == 'max' && v > best)) {
            best = v;
          }
        }
        return best;
      case 'len':
        final x = args[0];
        if (x is String) return x.runes.length.toDouble();
        if (x is List) return x.length.toDouble();
        if (x is Map) return x.length.toDouble();
        return 0.0;
      case 'range':
        var a = _num(args, 0), b = _num(args, 1);
        if (a == null || b == null) return null;
        a = a.truncateToDouble();
        b = b.truncateToDouble();
        if (b - a > 1000) b = a + 1000;
        return [for (var x = a; x < b; x++) x];
      case 'first':
      case 'last':
        final arr = args[0];
        if (arr is! List || arr.isEmpty) return null;
        return c.name == 'first' ? arr.first : arr.last;
      case 'slice':
        final arr = args[0];
        if (arr is! List) return null;
        final s = _num(args, 1);
        if (s == null) return null;
        var e = arr.length.toDouble();
        if (args.length > 2) {
          final m = _num(args, 2);
          if (m == null) return null;
          e = m;
        }
        final si = _normIdx(_toInt(s), arr.length);
        final ei = _normIdx(_toInt(e), arr.length);
        if (si >= ei) return <dynamic>[];
        return arr.sublist(si, ei);
      case 'reverse':
        final arr = args[0];
        if (arr is! List) return null;
        return arr.reversed.toList();
      case 'join':
        final arr = args[0];
        if (arr is! List) return null;
        var sep = ', ';
        if (args.length > 1 && args[1] is String) sep = args[1] as String;
        return arr.map(str).join(sep);
      case 'contains':
        final x = args[0];
        if (x is String) return args[1] is String && x.contains(args[1] as String);
        if (x is List) return x.any((v) => _equal(v, args[1]));
        return false;
      case 'fmt':
        final x = _num(args, 0);
        if (x == null) return null;
        if (args.length > 1) {
          final d = _num(args, 1);
          if (d == null) return null;
          return fmtNum(x, _clamp(d, 0, 6).toInt(), true);
        }
        return fmtNum(x, 0, false);
      case 'pct':
        final x = _num(args, 0);
        if (x == null) return null;
        var d = 2.0;
        if (args.length > 1) {
          final m = _num(args, 1);
          if (m == null) return null;
          d = m;
        }
        return pct(x, _clamp(d, 0, 6).toInt());
      case 'str':
        return str(args[0]);
      case 'num':
        final x = args[0];
        if (x is double) return x;
        if (x is String) return _parseNum(x);
        return null;
      case 'today':
        return _ymd(_cst(env.now()));
      case 'now':
        return env.now().millisecondsSinceEpoch.toDouble();
      case 'date':
        final x = _num(args, 0);
        if (x == null || x.isInfinite) return null;
        return _ymd(_cst(DateTime.fromMillisecondsSinceEpoch(_toInt(x), isUtc: true)));
      case 'date_add':
        final s = args[0];
        final n = _num(args, 1);
        if (s is! String || n == null || n.isInfinite) return null;
        final t = _parseYmd(s);
        if (t == null) return null;
        return _ymd(DateTime.utc(t.year, t.month, t.day + _toInt(n)));
      case 'month_start':
        final t = _cst(env.now());
        return (DateTime.utc(t.year, t.month, 1).millisecondsSinceEpoch - _cstMs)
            .toDouble();
      case 'days_between':
        final a = args[0], b = args[1];
        if (a is! String || b is! String) return null;
        final ta = _parseYmd(a), tb = _parseYmd(b);
        if (ta == null || tb == null) return null;
        return (tb.difference(ta).inHours / 24).roundToDouble();
    }
    return null;
  }

  dynamic Function(dynamic item, int idx) elemFn(_Node n) {
    if (n is _Lit && n.v is String) {
      final field = n.v as String;
      return (item, _) => item is Map ? item[field] : null;
    }
    return (item, idx) {
      scopes.add({'item': item, 'index': idx.toDouble()});
      try {
        return eval(n);
      } finally {
        scopes.removeLast();
      }
    };
  }

  dynamic callLazy(_Call c) {
    final first = eval(c.args[0]);
    if (first is! List) {
      switch (c.name) {
        case 'count':
        case 'sum':
          return 0.0;
        case 'map':
        case 'filter':
        case 'sort_by':
        case 'zip_with':
        case 'group_sum':
          return <dynamic>[];
      }
      return null;
    }
    final arr = first;
    if (arr.length > maxArray) throw XelError('数组太大');
    if (c.name == 'zip_with') {
      final second = eval(c.args[1]);
      final brr = second is List ? second : const [];
      if (brr.length > maxArray) throw XelError('数组太大');
      final n = math.min(arr.length, brr.length);
      final out = <dynamic>[];
      for (var i = 0; i < n; i++) {
        scopes.add({'x': arr[i], 'y': brr[i], 'index': i.toDouble()});
        try {
          out.add(eval(c.args[2]));
        } finally {
          scopes.removeLast();
        }
      }
      return out;
    }
    final fn = c.args.length > 1 ? elemFn(c.args[1]) : null;
    List<dynamic> vals() {
      if (fn == null) return arr;
      return [for (var i = 0; i < arr.length; i++) fn(arr[i], i)];
    }

    switch (c.name) {
      case 'group_sum':
        final keyFn = elemFn(c.args[1]);
        final valFn = elemFn(c.args[2]);
        final sums = <String, double>{};
        final order = <String>[];
        for (var i = 0; i < arr.length; i++) {
          final k = keyFn(arr[i], i);
          final v = valFn(arr[i], i);
          final ks = str(k);
          if (!sums.containsKey(ks)) {
            order.add(ks);
            sums[ks] = 0;
          }
          if (v is double && !v.isNaN) sums[ks] = sums[ks]! + v;
        }
        _stableSort(order, (a, b) {
          if (sums[a] != sums[b]) return sums[a]! > sums[b]! ? -1 : 1;
          return _compareStr(a, b);
        });
        return [
          for (final k in order) <String, dynamic>{'key': k, 'value': sums[k]}
        ];
      case 'map':
        return vals();
      case 'filter':
        return [
          for (var i = 0; i < arr.length; i++)
            if (truthy(fn!(arr[i], i))) arr[i]
        ];
      case 'count':
        if (fn == null) return arr.length.toDouble();
        var n = 0;
        for (var i = 0; i < arr.length; i++) {
          if (truthy(fn(arr[i], i))) n++;
        }
        return n.toDouble();
      case 'sum':
      case 'avg':
        var s = 0.0;
        var n = 0;
        for (final v in vals()) {
          if (v is double && !v.isNaN) {
            s += v;
            n++;
          }
        }
        if (c.name == 'sum') return s;
        return n == 0 ? null : s / n;
      case 'sort_by':
        final keys = vals();
        var desc = false;
        if (c.args.length > 2) desc = eval(c.args[2]) == 'desc';
        final idx = List<int>.generate(arr.length, (i) => i);
        _stableSort(idx, (a, b) {
          final r = _compareAny(keys[a], keys[b]);
          return desc ? -r : r;
        });
        return [for (final k in idx) arr[k]];
    }
    return null;
  }
}

// ─── 工具 ───────────────────────────────────────────────────────────────

/// nil / false / 0 / "" / NaN 为假，其余（包括空数组）为真。
bool truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is double) return v != 0 && !v.isNaN;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  return true;
}

bool _equal(dynamic a, dynamic b) {
  if (a == null) return b == null;
  if (a is bool) return b is bool && a == b;
  if (a is double) return b is double && a == b;
  if (a is String) return b is String && a == b;
  return false;
}

dynamic _index(dynamic o, dynamic i) {
  if (o is List) {
    if (i is! double || i.isInfinite || i != i.truncateToDouble()) return null;
    var k = i.toInt();
    if (k < 0) k += o.length;
    if (k < 0 || k >= o.length) return null;
    return o[k];
  }
  if (o is Map && i is String) return o[i];
  return null;
}

int _compareF(double a, double b) => a < b ? -1 : (a > b ? 1 : 0);

/// 按 Unicode 码点比较（与 Go 的按 UTF-8 字节比较顺序一致）。
int _compareStr(String a, String b) {
  final ra = a.runes.toList(), rb = b.runes.toList();
  final n = math.min(ra.length, rb.length);
  for (var i = 0; i < n; i++) {
    if (ra[i] != rb[i]) return ra[i] < rb[i] ? -1 : 1;
  }
  return ra.length.compareTo(rb.length);
}

bool _cmpOp(String op, int c) => switch (op) {
      '<' => c < 0,
      '<=' => c <= 0,
      '>' => c > 0,
      _ => c >= 0,
    };

int _compareAny(dynamic a, dynamic b) {
  int rank(dynamic v) {
    if (v is double) return 0;
    if (v is String) return 1;
    if (v == null) return 3;
    return 2;
  }

  final ra = rank(a), rb = rank(b);
  if (ra != rb) return ra - rb;
  if (a is double) return _compareF(a, b as double);
  if (a is String) return _compareStr(a, b as String);
  return 0;
}

/// 稳定排序（Dart 的 List.sort 不保证稳定）。
void _stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
  if (list.length < 2) return;
  final tagged = [for (var i = 0; i < list.length; i++) (i, list[i])];
  tagged.sort((x, y) {
    final r = cmp(x.$2, y.$2);
    return r != 0 ? r : x.$1 - y.$1;
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = tagged[i].$2;
  }
}

double _clamp(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);

int _toInt(double x) {
  if (x.isNaN) return 0;
  if (x.isInfinite) return x > 0 ? 1 << 53 : -(1 << 53);
  return x.toInt();
}

int _normIdx(int i, int n) {
  if (i < 0) i += n;
  if (i < 0) return 0;
  if (i > n) return n;
  return i;
}

dynamic _parseNum(String s) {
  s = s.replaceAll(',', '').trim();
  if (s.isEmpty) return null;
  List<_Tok> toks;
  try {
    toks = _lex(s);
  } on XelError {
    return null;
  }
  var neg = false;
  if (toks.length == 3 && toks[0].kind == _K.punct && toks[0].s == '-') {
    neg = true;
    toks = toks.sublist(1);
  }
  if (toks.length != 2 || toks[0].kind != _K.num) return null;
  return neg ? -toks[0].n : toks[0].n;
}

const int _cstMs = 8 * 3600 * 1000;

/// 转成「北京时间的墙上时间」（用 UTC DateTime 承载）。
DateTime _cst(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch + _cstMs,
        isUtc: true);

String _ymd(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

final _ymdRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime? _parseYmd(String s) {
  final m = _ymdRe.firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1) return null;
  final dim = DateTime.utc(y, mo + 1, 0).day;
  if (d > dim) return null;
  return DateTime.utc(y, mo, d);
}

// ─── 字符串化与格式化（两端必须逐字一致）──────────────────────────────

/// nil→""；数字见 [numStr]；数组用 ", " 连接标量；对象→""。
String str(dynamic v) {
  if (v == null) return '';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return numStr(v.toDouble());
  if (v is String) return v;
  if (v is List) {
    return v.where((e) => e is! List && e is! Map).map(str).join(', ');
  }
  return '';
}

/// 整数（|x|<1e15）不带小数；否则保留至多 6 位小数（四舍五入、去掉末尾 0）；
/// |x| ≥ 1e9 的非整数取整。NaN / Inf → ""。
String numStr(double x) {
  if (x.isNaN || x.isInfinite) return '';
  if (x == x.truncateToDouble() && x.abs() < 1e15) {
    if (x == 0 && x.isNegative) return '-0';
    return BigInt.from(x).toString();
  }
  if (x.abs() >= 1e9) return _fixed(x, 0, false);
  return _trimZeros(_fixed(x, 6, false));
}

String _fixed(double x, int d, bool group) {
  if (x.isNaN || x.isInfinite) return '';
  if (d < 0) d = 0;
  if (d > 6) d = 6;
  final neg = x < 0;
  final scaled = (x.abs() * math.pow(10, d)).roundToDouble();
  var digits = BigInt.from(scaled).toString();
  while (digits.length <= d) {
    digits = '0$digits';
  }
  var intPart = digits.substring(0, digits.length - d);
  final frac = digits.substring(digits.length - d);
  if (group) intPart = _groupThousands(intPart);
  var s = intPart;
  if (d > 0) s += '.$frac';
  if (neg && scaled != 0) s = '-$s';
  return s;
}

String _groupThousands(String s) {
  if (s.length <= 3) return s;
  final b = StringBuffer();
  final pre = s.length % 3;
  if (pre > 0) b.write(s.substring(0, pre));
  for (var i = pre; i < s.length; i += 3) {
    if (b.isNotEmpty) b.write(',');
    b.write(s.substring(i, i + 3));
  }
  return b.toString();
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s == '-0' ? '0' : s;
}

/// fmt(x, d)：千分位；给 d 时固定 d 位小数，不给时至多 2 位并去掉末尾 0。
String fmtNum(double x, int d, bool hasD) =>
    hasD ? _fixed(x, d, true) : _trimZeros(_fixed(x, 2, true));

/// pct(x, d=2)：x 已经是百分数（1.23 表示 1.23%），正数带 "+"。
String pct(double x, int d) {
  var s = _fixed(x, d, false);
  if (s.isEmpty) return '';
  if (x > 0 && s.replaceAll(RegExp(r'^[0.]+|[0.]+$'), '').isNotEmpty) {
    s = '+$s';
  }
  return '$s%';
}

// ─── 模板 ───────────────────────────────────────────────────────────────

/// "文字 ${表达式} 文字" 形式的字符串模板。
class XelTemplate {
  XelTemplate._(this._parts);
  final List<(String, Expr?)> _parts;

  bool get isStatic => _parts.every((p) => p.$2 == null);

  static XelTemplate compile(String s) {
    final parts = <(String, Expr?)>[];
    var i = 0;
    while (i < s.length) {
      final j = s.indexOf(r'${', i);
      if (j < 0) {
        parts.add((s.substring(i), null));
        break;
      }
      if (j > i) parts.add((s.substring(i, j), null));
      final start = j + 2;
      final end = _matchBrace(s, start);
      final src = s.substring(start, end);
      try {
        parts.add(('', Expr.compile(src)));
      } on XelError catch (e) {
        throw XelError('模板 \${$src}：${e.message}');
      }
      i = end + 1;
    }
    return XelTemplate._(parts);
  }

  static XelTemplate? tryCompile(String s) {
    try {
      return compile(s);
    } on XelError {
      return null;
    }
  }

  /// 渲染；单个表达式出错时该段为空。
  String render(XelEnv env) {
    final b = StringBuffer();
    for (final p in _parts) {
      if (p.$2 == null) {
        b.write(p.$1);
      } else {
        b.write(str(p.$2!.evalOrNull(env)));
      }
    }
    return b.toString();
  }
}

int _matchBrace(String s, int start) {
  var depth = 0;
  int? quote;
  for (var k = start; k < s.length; k++) {
    final c = s.codeUnitAt(k);
    if (quote != null) {
      if (c == 0x5C) {
        k++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == 0x27 || c == 0x22) {
      quote = c;
    } else if (c == 0x7B) {
      depth++;
    } else if (c == 0x7D) {
      if (depth == 0) return k;
      depth--;
    }
  }
  throw XelError(r'模板里的 ${ 缺少结束的 }');
}
