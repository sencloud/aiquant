import 'dart:convert';
import 'dart:io';

import 'package:fincept_app/miniapp/expr/xel.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与后端 backend/internal/miniapp/xel/xel_test.go 共用同一份用例：两端结果必须逐字一致。
bool _near(dynamic a, dynamic b) {
  if (a is double && b is double) {
    return a == b || (a - b).abs() < 1e-9 * (b.abs() > 1 ? b.abs() : 1);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_near(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_near(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  final conf = jsonDecode(File('backend/internal/miniapp/xel/testdata/conformance.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final now = DateTime.parse(conf['now'] as String);
  final env = XelEnv(normalize(conf['vars']) as Map<String, dynamic>, now: () => now);

  test('conformance.json', () {
    final failures = <String>[];
    final cases = conf['cases'] as List;
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i] as Map<String, dynamic>;
      final wantErr = c['err'] == true;
      final want = normalize(c['want']);
      if (c['expr'] != null) {
        final src = c['expr'] as String;
        Expr e;
        try {
          e = Expr.compile(src);
        } on XelError catch (err) {
          if (!wantErr) failures.add('#$i "$src": compile: $err');
          continue;
        }
        if (wantErr) {
          failures.add('#$i "$src": want compile error');
          continue;
        }
        dynamic got;
        try {
          got = e.eval(env);
        } on XelError catch (err) {
          failures.add('#$i "$src": eval: $err');
          continue;
        }
        if (!_near(got, want)) failures.add('#$i "$src" = $got, want $want');
      } else if (c['tpl'] != null) {
        final src = c['tpl'] as String;
        XelTemplate t;
        try {
          t = XelTemplate.compile(src);
        } on XelError catch (err) {
          if (!wantErr) failures.add('#$i tpl "$src": $err');
          continue;
        }
        if (wantErr) {
          failures.add('#$i tpl "$src": want error');
          continue;
        }
        final got = t.render(env);
        if (got != want) failures.add('#$i tpl "$src" = "$got", want "$want"');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(cases.length, greaterThan(80));
  });

  test('limits', () {
    expect(() => Expr.compile('${'1+' * 300}1'), throwsA(isA<XelError>()));
    expect(() => Expr.compile('${'[' * 40}1${']' * 40}'), throwsA(isA<XelError>()));
    final big = [for (var i = 0; i < 200; i++) i.toDouble()];
    final e = Expr.compile('map(xs, sum(map(xs, item + 1)))');
    expect(() => e.eval(XelEnv({'xs': big})), throwsA(isA<XelError>()));
    expect(e.evalOrNull(XelEnv({'xs': big})), isNull);
    final huge = List<dynamic>.filled(maxArray + 1, null);
    expect(() => Expr.compile('count(xs)').eval(XelEnv({'xs': huge})),
        throwsA(isA<XelError>()));
  });

  test('dataRefs', () {
    final e = Expr.compile(
        "data.main.ts_code + px.x + data['wx'].a + map(inputs.places, item.name)");
    expect(e.dataRefs(), ['main', 'wx']);
  });
}
