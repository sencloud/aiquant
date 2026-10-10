import 'dart:convert';
import 'dart:io';

import 'package:fincept_app/models/falsification.dart';
import 'package:fincept_app/models/falsification_index.dart';
import 'package:flutter_test/flutter_test.dart';

FalsificationData _load(String path) => FalsificationData.fromJson(
    json.decode(File(path).readAsStringSync()) as Map<String, dynamic>);

/// alpha-radar docs/falsification-export.md 里的自动条目示例（节选）。
const _autoEntry = {
  'id': 'supertrend-p-dce-5min',
  'strategy': 'SuperTrend',
  'strategy_key': 'supertrend',
  'family': '趋势跟随',
  'family_key': 'trend',
  'source': 'TradingView @KivancOzbilgic',
  'origin': '',
  'license': 'MPL-2.0',
  'license_status': 'open',
  'symbol': 'P.DCE',
  'name': '棕榈油',
  'asset_class': 'futures',
  'freq': '5min',
  'verdict': 'pending',
  'failed_gate': null,
  'gates': {
    'sample': {
      'status': 'pass',
      'value': {'trades': 500, 'years': 4},
      'threshold': {'min_trades': 200, 'min_years': 3},
    },
    'scale': {
      'status': 'marginal',
      'value': 0.3,
      'threshold': {'pass_below': 0.25, 'fail_at': 0.4},
    },
    'drawdown': {
      'status': 'pass',
      'value': 5.0,
      'threshold': {'min_pnl_dd': 1.0, 'require_positive_pnl': true},
    },
    'robust': {
      'status': 'review',
      'value': null,
      'threshold': null,
      'note': 'MVP 不做自动判定，待人工复核',
    },
  },
  'threshold_version': '2026-10-10.v1',
  'flags': ['scale_marginal'],
  'insufficient_reason': null,
  'editor_verdict': null,
  'headline': '四道闸门全过，等待参数稳健性人工复核',
  'metrics': {
    'trades': 500,
    'win': 0.45,
    'pf': 1.3,
    'avg_points': 2.0,
    'max_dd_pct': null,
    'pnl_dd': 5.0,
    'positive_years': 4,
    'years': 4,
    'total_pnl': 50000.0,
    'max_dd': -10000.0,
  },
  'yearly': [
    ['2022', 10],
    ['2023', 10],
  ],
  'mechanism': '',
  'command': 'alpharadar run --symbol P.DCE --strategy supertrend --freq 5min',
  'window': {'start': '20220101', 'end': '20260930'},
  'curated': false,
  'rerun_note': null,
  'judged_at': '2026-10-10T18:00:00',
  'updated_at': '2026-10-09T12:00:00',
};

void main() {
  group('旧资产（v1，无闸门结果）', () {
    final data = _load('test/fixtures/falsification_v1.json');

    test('能解析，计数与旧版一致', () {
      expect(data.archive, hasLength(8));
      expect(data.summary.archiveRejected, greaterThan(0));
      expect(data.gates, isNotEmpty);
      for (final e in data.archive) {
        expect(e.gateResults, isEmpty);
        expect(e.familyKey, isEmpty);
        expect(e.locked, isFalse);
      }
    });

    test('没有 family_key 时按中文家族名分组', () {
      final idx = ArchiveIndex.build(data.archive, now: DateTime(2026, 10, 10));
      expect(idx.sections.map((s) => s.key), contains('趋势跟随'));
      // 「趋势跟随 + 体制过滤」归进「趋势跟随」。
      final trend = idx.sections.firstWhere((s) => s.key == '趋势跟随');
      expect(trend.entries.map((e) => e.id), contains('utbot-5min'));
    });
  });

  group('新资产（alpha-radar 导出契约）', () {
    final data = _load('assets/strategy/falsification.json');

    test('顶层与 summary 兼容新旧两套计数', () {
      expect(data.thresholdVersion, isNotEmpty);
      expect(data.gates.map((g) => g.id),
          ['sample', 'scale', 'yearly', 'drawdown', 'robust']);
      expect(data.summary.archiveRejected, 4);
      expect(data.summary.archiveInsufficient, 1);
      expect(data.summary.tradable, 0);
      expect(data.scales, isNotEmpty);
    });

    test('条目：结构化闸门值被格式化成一行字', () {
      final orb = data.archive.firstWhere((e) => e.id == 'orb-5min');
      expect(orb.strategyKey, 'orb_classic');
      expect(orb.familyKey, 'breakout');
      expect(orb.needsRerun, isTrue);
      expect(orb.rerunNote, isNotEmpty);
      expect(orb.failedGate, 'yearly');
      expect(orb.gateResults['sample']!.value, '1223 笔 / 5 年');
      expect(orb.gateResults['sample']!.threshold, '≥ 200 笔且 ≥ 3 年');
      expect(orb.gateResults['scale']!.value, '22.2%');
      expect(orb.gateResults['yearly']!.value, '0/5 年为正');
      expect(orb.gateResults['robust']!.status, 'review');
      expect(orb.failedGateName(data.gates), '分年闸门');
      // 未知数字是 null，解析成 0 而不是抛异常。
      expect(orb.metrics.avgPoints, 0);
    });
  });

  test('契约自动条目：null、flags、新指标', () {
    final e = ArchiveEntry.fromJson(
        json.decode(json.encode(_autoEntry)) as Map<String, dynamic>);
    expect(e.verdict, 'pending');
    expect(e.failedGate, isEmpty);
    expect(e.scaleMarginal, isTrue);
    expect(e.needsRerun, isFalse);
    expect(e.name, '棕榈油');
    expect(e.metrics.totalPnl, 50000);
    expect(e.metrics.maxDd, -10000);
    expect(e.metrics.maxDdPct, 0);
    expect(e.gateResults['scale']!.value, '30.0%');
    expect(e.gateResults['drawdown']!.threshold, '≥ 1.0 且总盈亏为正');
    expect(e.gateResults['robust']!.value, isEmpty);
    expect(e.gateResults['robust']!.note, contains('人工复核'));
    expect(e.yearly, hasLength(2));
    expect(e.hasPaidContent, isTrue);
  });

  test('后端锁住的条目：locked=true，解锁后合并完整内容', () {
    final locked = ArchiveEntry.fromJson({
      ..._autoEntry,
      'yearly': null,
      'command': null,
      'locked': true,
    });
    expect(locked.locked, isTrue);
    expect(locked.yearly, isEmpty);
    expect(locked.hasPaidContent, isTrue);
    final full = locked.mergedWith(ArchiveEntry.fromJson(_autoEntry));
    expect(full.locked, isFalse);
    expect(full.yearly, hasLength(2));
    expect(full.command, contains('supertrend'));
    expect(full.familyKey, 'trend');
  });

  group('ArchiveIndex（通讯录分组）', () {
    ArchiveEntry entry(String id,
            {String verdict = 'reject',
            String familyKey = 'trend',
            String family = '趋势跟随',
            bool curated = false,
            String updatedAt = '2026-10-01'}) =>
        ArchiveEntry.fromJson({
          ..._autoEntry,
          'id': id,
          'strategy': id,
          'verdict': verdict,
          'family_key': familyKey,
          'family': family,
          'curated': curated,
          'updated_at': updatedAt,
        });

    final archive = [
      entry('a', updatedAt: '2026-10-09T12:00:00'),
      entry('b', verdict: 'pending'),
      entry('c', familyKey: 'breakout', family: '日内突破', curated: true),
      entry('d', familyKey: 'breakout', family: '开盘突破'),
      entry('e', familyKey: 'breakout', family: '突破'),
      entry('f', verdict: 'insufficient', familyKey: 'reversal', family: '反转'),
      entry('g', verdict: 'insufficient', curated: true),
    ];
    final idx = ArchiveIndex.build(archive, now: DateTime(2026, 10, 10));

    test('按 family_key 分组，多的在前，标题用统一中文名', () {
      expect(idx.sections.map((s) => s.key), ['breakout', 'trend']);
      expect(idx.sections.first.family, '突破');
      expect(idx.sections.first.label, '突');
      expect(idx.sections.first.entries.map((e) => e.id), ['c', 'd', 'e']);
    });

    test('样本不足不进主列表，但能搜到；精选不受影响', () {
      final ids = [for (final s in idx.sections) ...s.entries.map((e) => e.id)];
      expect(ids, isNot(contains('f')));
      expect(ids, isNot(contains('g')));
      expect(idx.insufficientCount, 2);
      expect(idx.mainCount, 5);
      expect(idx.search('f').map((e) => e.id), contains('f'));
      expect(idx.search('棕榈油'), hasLength(archive.length));
      expect(idx.search('  '), isEmpty);
      expect(idx.curated.map((e) => e.id), ['c', 'g']);
    });

    test('顶部入口：可交易 / 仍在验证 / 本周新证伪', () {
      expect(idx.tradable, isEmpty);
      expect(idx.pending.map((e) => e.id), ['b']);
      expect(idx.recentRejects.map((e) => e.id), ['a']);
    });
  });

  test('后端收窄列表的 list 元信息 + 搜索结果；旧资产没有 list 时为空', () {
    final d = FalsificationData.fromJson({
      'archive': [_autoEntry],
      'list': {
        'mode': 'representative',
        'total': 2008,
        'returned': 41,
        'omitted': {'reject': 1967, 'insufficient': 2},
        'searchable': true,
      },
    });
    expect(d.listMeta.isNarrowed, isTrue);
    expect(d.listMeta.omittedRejects, 1967);
    expect(d.listMeta.omittedTotal, 1969);
    expect(d.listMeta.total, 2008);
    // 解锁回写不丢元信息。
    expect(
        d.replaceEntry(ArchiveEntry.fromJson(_autoEntry)).listMeta.total, 2008);

    final legacy = FalsificationData.fromJson({'archive': []});
    expect(legacy.listMeta.isNarrowed, isFalse);
    expect(legacy.listMeta.omittedRejects, 0);

    final r = ArchiveSearchResult.fromJson({
      'archive': [_autoEntry],
      'search': {'q': 'super', 'matched': 120, 'returned': 1},
    });
    expect(r.query, 'super');
    expect(r.matched, 120);
    expect(r.entries.single.id, 'supertrend-p-dce-5min');
  });
}
