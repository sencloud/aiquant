/// 「证伪台」的数据模型 —— 对应 assets/strategy/falsification.json。
///
/// 这份资产由 tools/strategy-mvp/build_falsification_data.py 从本机
/// alpha-radar 仓库（策略证伪器）的行情缓存离线算出，App 侧只读不写。
///
/// 解析一律走容错路径：缺字段降级为空值，不因为一条记录坏了就整页报错。
library;

class FalsificationData {
  const FalsificationData({
    required this.generatedAt,
    required this.source,
    required this.gates,
    required this.scales,
    required this.archive,
    required this.summary,
  });

  final String generatedAt;
  final FalsificationSource source;
  final List<FalsificationGate> gates;
  final List<CostScale> scales;
  final List<ArchiveEntry> archive;
  final FalsificationSummary summary;

  factory FalsificationData.fromJson(Map<String, dynamic> j) =>
      FalsificationData(
        generatedAt: _str(j['generated_at']),
        source: FalsificationSource.fromJson(_map(j['source'])),
        gates: _list(j['gates'], FalsificationGate.fromJson),
        scales: _list(j['cost_scales'], CostScale.fromJson),
        archive: _list(j['archive'], ArchiveEntry.fromJson),
        summary: FalsificationSummary.fromJson(_map(j['summary'])),
      );
}

class FalsificationSource {
  const FalsificationSource({
    required this.project,
    required this.what,
    required this.notWhat,
    required this.data,
    required this.costModel,
  });

  final String project;
  final String what;
  final String notWhat;
  final String data;
  final String costModel;

  factory FalsificationSource.fromJson(Map<String, dynamic> j) =>
      FalsificationSource(
        project: _str(j['project']),
        what: _str(j['what']),
        notWhat: _str(j['not']),
        data: _str(j['data']),
        costModel: _str(j['cost_model']),
      );
}

/// 一道闸门：名称 + 判定线 + 为什么。
class FalsificationGate {
  const FalsificationGate({
    required this.id,
    required this.name,
    required this.rule,
    required this.why,
    required this.verdict,
  });

  final String id;
  final String name;
  final String rule;
  final String why;
  final String verdict;

  factory FalsificationGate.fromJson(Map<String, dynamic> j) =>
      FalsificationGate(
        id: _str(j['id']),
        name: _str(j['name']),
        rule: _str(j['rule']),
        why: _str(j['why']),
        verdict: _str(j['verdict']),
      );
}

/// 尺度闸门的一行：某品种某周期的「往返成本 ÷ 平均振幅」。
class CostScale {
  const CostScale({
    required this.symbol,
    required this.name,
    required this.market,
    required this.freq,
    required this.bars,
    required this.years,
    required this.amplitude,
    required this.cost,
    required this.perLotYuan,
    required this.ratio,
    required this.verdict,
    required this.note,
    required this.source,
  });

  final String symbol;
  final String name;
  final String market;
  final String freq;
  final int bars;
  final double years;
  final double amplitude;
  final double cost;

  /// 往返成本折算成元/手，方便不看点数也能感知量级。
  final double perLotYuan;
  final double ratio;

  /// pass / marginal / fail
  final String verdict;
  final String note;

  /// computed = 本机缓存现算；recorded = 取自 alpha-radar 的 findings 记录。
  final String source;

  bool get isComputed => source == 'computed';

  /// 成本 ÷ 振幅的百分比（0–100，用于画条；超过 100 截到 100）。
  double get ratioPct => (ratio * 100).clamp(0, 100).toDouble();

  String get verdictLabel => switch (verdict) {
        'pass' => '通过',
        'marginal' => '勉强',
        _ => '淘汰',
      };

  factory CostScale.fromJson(Map<String, dynamic> j) => CostScale(
        symbol: _str(j['symbol']),
        name: _str(j['name']),
        market: _str(j['market']),
        freq: _str(j['freq']),
        bars: _int(j['bars']),
        years: _dbl(j['years']),
        amplitude: _dbl(j['amplitude']),
        cost: _dbl(j['cost']),
        perLotYuan: _dbl(j['per_lot_yuan']),
        ratio: _dbl(j['ratio']),
        verdict: _str(j['verdict']),
        note: _str(j['note']),
        source: _str(j['source']).isEmpty ? 'computed' : _str(j['source']),
      );
}

/// 证伪档案的一条记录。
class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.strategy,
    required this.family,
    required this.source,
    required this.symbol,
    required this.freq,
    required this.verdict,
    required this.headline,
    required this.few,
    required this.mechanism,
    required this.command,
    required this.metrics,
    required this.yearly,
  });

  final String id;
  final String strategy;
  final String family;
  final String source;
  final String symbol;
  final String freq;

  /// reject = 已证伪；pending = 方向对但样本不足；finding = 单点结论（不是策略）
  final String verdict;
  final String headline;

  /// 一行关键数字，列表里用。
  final String few;
  final String mechanism;

  /// 可复现命令。
  final String command;
  final ArchiveMetrics metrics;

  /// [年份, 盈亏（元）]，可能为空。
  final List<YearPnl> yearly;

  String get verdictLabel => switch (verdict) {
        'reject' => '不可实盘',
        'pending' => '样本不足',
        _ => '单点结论',
      };

  factory ArchiveEntry.fromJson(Map<String, dynamic> j) => ArchiveEntry(
        id: _str(j['id']),
        strategy: _str(j['strategy']),
        family: _str(j['family']),
        source: _str(j['source']),
        symbol: _str(j['symbol']),
        freq: _str(j['freq']),
        verdict: _str(j['verdict']),
        headline: _str(j['headline']),
        few: _str(j['few']),
        mechanism: _str(j['mechanism']),
        command: _str(j['command']),
        metrics: ArchiveMetrics.fromJson(_map(j['metrics'])),
        yearly: _yearly(j['yearly']),
      );
}

class YearPnl {
  const YearPnl({required this.year, required this.pnl});
  final String year;
  final double pnl;
}

class ArchiveMetrics {
  const ArchiveMetrics({
    required this.trades,
    required this.win,
    required this.pf,
    required this.avgPoints,
    required this.maxDdPct,
    required this.pnlDd,
    required this.positiveYears,
    required this.years,
  });

  final int trades;
  final double win;
  final double pf;
  final double avgPoints;
  final double maxDdPct;
  final double pnlDd;
  final int positiveYears;
  final int years;

  factory ArchiveMetrics.fromJson(Map<String, dynamic> j) => ArchiveMetrics(
        trades: _int(j['trades']),
        win: _dbl(j['win']),
        pf: _dbl(j['pf']),
        avgPoints: _dbl(j['avg_points']),
        maxDdPct: _dbl(j['max_dd_pct']),
        pnlDd: _dbl(j['pnl_dd']),
        positiveYears: _int(j['positive_years']),
        years: _int(j['years']),
      );
}

class FalsificationSummary {
  const FalsificationSummary({
    required this.archiveTotal,
    required this.archiveRejected,
    required this.archivePending,
    required this.tradable,
    required this.scaleRows,
    required this.scaleFail,
    required this.scalePass,
  });

  final int archiveTotal;
  final int archiveRejected;
  final int archivePending;

  /// 通过全部闸门、可以实盘的策略数。当前是 0，而且这个 0 是产品结论本身。
  final int tradable;
  final int scaleRows;
  final int scaleFail;
  final int scalePass;

  int get findings => archiveTotal - archiveRejected - archivePending;

  factory FalsificationSummary.fromJson(Map<String, dynamic> j) =>
      FalsificationSummary(
        archiveTotal: _int(j['archive_total']),
        archiveRejected: _int(j['archive_rejected']),
        archivePending: _int(j['archive_pending']),
        tradable: _int(j['tradable']),
        scaleRows: _int(j['scale_rows']),
        scaleFail: _int(j['scale_fail']),
        scalePass: _int(j['scale_pass']),
      );
}

// ── 容错解析工具 ────────────────────────────────────────────────────────

String _str(dynamic v) => v == null ? '' : '$v';

double _dbl(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : const {};

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) out.add(f(e.cast<String, dynamic>()));
  }
  return out;
}

List<YearPnl> _yearly(dynamic v) {
  if (v is! List) return const [];
  final out = <YearPnl>[];
  for (final e in v) {
    if (e is List && e.length >= 2) {
      out.add(YearPnl(year: '${e[0]}', pnl: _dbl(e[1])));
    }
  }
  return out;
}
