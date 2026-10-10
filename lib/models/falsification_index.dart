/// 证伪档案的「通讯录」索引：把一份档案切成顶部入口、精选档案和按策略家族
/// 分组的主列表。纯函数，不依赖 Flutter，便于单测。
library;

import 'falsification.dart';

/// 主列表里的一个家族分组（相当于通讯录里的一个字母段）。
class FamilySection {
  const FamilySection({
    required this.key,
    required this.family,
    required this.label,
    required this.entries,
  });

  /// 分组 key：优先 alpha-radar 契约的 family_key（trend / breakout …），
  /// 旧资产没有时用归一后的中文家族名。
  final String key;

  /// 展示用的家族中文名。
  final String family;

  /// 右侧索引上显示的短标签（家族名首字）。
  final String label;
  final List<ArchiveEntry> entries;
}

class ArchiveIndex {
  const ArchiveIndex({
    required this.tradable,
    required this.pending,
    required this.recentRejects,
    required this.curated,
    required this.sections,
    required this.all,
  });

  /// 可交易（只能人工判定；P2 之前恒为空）。
  final List<ArchiveEntry> tradable;

  /// 仍在验证（自动闸门全过，稳健性待复核）。
  final List<ArchiveEntry> pending;

  /// 本周新证伪：最近 7 天判定为淘汰的。
  final List<ArchiveEntry> recentRejects;

  /// 精选档案（手写机制）。和微信的星标朋友一样，同时出现在自己的家族分组里。
  final List<ArchiveEntry> curated;

  /// 主列表：按家族分组，不含样本不足。
  final List<FamilySection> sections;

  /// 全量（含样本不足），给搜索用。
  final List<ArchiveEntry> all;

  int get mainCount => sections.fold(0, (n, s) => n + s.entries.length);

  /// 样本不足的条数（不进主列表，只能搜到）。
  int get insufficientCount =>
      all.where((e) => e.verdict == 'insufficient').length;

  static ArchiveIndex build(List<ArchiveEntry> archive, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final weekAgo = t.subtract(const Duration(days: 7));

    final byFamily = <String, List<ArchiveEntry>>{};
    final names = <String, String>{};
    for (final e in archive) {
      if (e.verdict == 'insufficient') continue;
      final k = familyKeyOf(e);
      byFamily.putIfAbsent(k, () => []).add(e);
      names.putIfAbsent(k, () => familyLabelOf(e));
    }
    final families = byFamily.keys.toList()
      ..sort((a, b) {
        // 条目多的家族在前；同数按 key，保证顺序稳定。
        final c = byFamily[b]!.length.compareTo(byFamily[a]!.length);
        return c != 0 ? c : a.compareTo(b);
      });
    final sections = <FamilySection>[
      for (final f in families)
        FamilySection(
          key: f,
          family: names[f]!,
          label: indexLabel(names[f]!),
          entries: [...byFamily[f]!]
            ..sort((a, b) => a.strategy.compareTo(b.strategy)),
        ),
    ];

    return ArchiveIndex(
      tradable: [
        for (final e in archive)
          if (e.verdict == 'tradable') e
      ],
      pending: [
        for (final e in archive)
          if (e.verdict == 'pending') e
      ],
      recentRejects: [
        for (final e in archive)
          if (e.verdict == 'reject' && _after(e.updatedAt, weekAgo)) e
      ],
      curated: [
        for (final e in archive)
          if (e.curated) e
      ],
      sections: sections,
      all: archive,
    );
  }

  /// 搜索：包含样本不足的条目。
  List<ArchiveEntry> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return [
      for (final e in all)
        if (e.matches(q)) e
    ];
  }

  /// 分组 key：family_key 优先，旧资产回落到归一后的中文家族名。
  static String familyKeyOf(ArchiveEntry e) =>
      e.familyKey.isNotEmpty ? e.familyKey : normalizeFamily(e.family);

  /// 分组标题：已知 family_key 用统一中文名，否则用条目自己的家族名。
  static String familyLabelOf(ArchiveEntry e) {
    final known = FamilyKeys.label(e.familyKey);
    return known.isNotEmpty ? known : normalizeFamily(e.family);
  }

  /// 「趋势跟随 + 体制过滤」→「趋势跟随」；空 → 「其他」。
  static String normalizeFamily(String family) {
    final f = family.split('+').first.trim();
    return f.isEmpty ? '其他' : f;
  }

  static String indexLabel(String family) =>
      family.isEmpty ? '#' : String.fromCharCode(family.runes.first);

  static bool _after(String ts, DateTime since) {
    if (ts.isEmpty) return false;
    final d = DateTime.tryParse(ts.length == 16 ? '$ts:00' : ts);
    return d != null && !d.isBefore(since);
  }
}
