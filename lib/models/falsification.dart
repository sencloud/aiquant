/// 「证伪档案」的数据模型 —— 对应后端 GET /v1/strategy/falsification，
/// 兜底是 assets/strategy/falsification.json（同一 schema）。
///
/// v2 在旧字段上只做加法：failed_gate、gates{}（每道闸门的结果）、curated、
/// threshold_version、locked 等。旧资产缺这些字段时一律取空值，照常可用。
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
    this.thresholdVersion = '',
    this.origin = '',
    this.prices = const FalsificationPrices(),
  });

  final String generatedAt;

  /// 判定所用的阈值版本（旧资产没有，为空）。
  final String thresholdVersion;

  /// 后端标注的数据来源：remote（alpha-radar 快照）/ seed（后端内置）；
  /// 本地资产为空。
  final String origin;

  /// 解锁 / 跑证伪的喜点价格（后端下发；本地资产用默认值）。
  final FalsificationPrices prices;
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
        thresholdVersion: _str(j['threshold_version']),
        origin: _str(j['origin']),
        prices: j['prices'] is Map
            ? FalsificationPrices.fromJson(_map(j['prices']))
            : const FalsificationPrices(),
      );

  /// 用新的档案条目替换同 id 的旧条目（解锁后拿到完整内容时用）。
  FalsificationData replaceEntry(ArchiveEntry e) => FalsificationData(
        generatedAt: generatedAt,
        source: source,
        gates: gates,
        scales: scales,
        archive: [for (final a in archive) a.id == e.id ? e : a],
        summary: summary,
        thresholdVersion: thresholdVersion,
        origin: origin,
        prices: prices,
      );
}

/// 喜点价格。默认值与后端 config credits.* 的默认一致。
class FalsificationPrices {
  const FalsificationPrices({
    this.unlock = 5,
    this.falsifyDaily = 10,
    this.falsifyMinute = 30,
  });

  final int unlock;
  final int falsifyDaily;
  final int falsifyMinute;

  int forFreq(String freq) => freq == '1d' ? falsifyDaily : falsifyMinute;

  factory FalsificationPrices.fromJson(Map<String, dynamic> j) =>
      FalsificationPrices(
        unlock: j.containsKey('unlock') ? _int(j['unlock']) : 5,
        falsifyDaily:
            j.containsKey('falsify_daily') ? _int(j['falsify_daily']) : 10,
        falsifyMinute:
            j.containsKey('falsify_minute') ? _int(j['falsify_minute']) : 30,
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
    this.failedGate = '',
    this.gateResults = const {},
    this.updatedAt = '',
    this.assetClass = '',
    this.license = '',
    this.curated = false,
    this.thresholdVersion = '',
    this.rerunPending = false,
    this.locked = false,
    this.strategyKey = '',
    this.familyKey = '',
    this.name = '',
    this.origin = '',
    this.licenseStatus = '',
    this.flags = const [],
    this.editorVerdict = '',
    this.insufficientReason = '',
    this.rerunNote = '',
    this.judgedAt = '',
  });

  final String id;
  final String strategy;
  final String family;
  final String source;
  final String symbol;
  final String freq;

  /// insufficient = 样本不足（不算淘汰，不进主列表）；reject = 淘汰；
  /// pending = 仍在验证（自动闸门全过，稳健性待复核）；tradable = 可交易
  /// （只能人工判定）；finding = 研究发现（不是策略）。
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

  /// 第一道没过的闸门 id（sample / scale / yearly / drawdown / robust），可能为空。
  final String failedGate;

  /// 每道闸门的结果。旧资产没有，为空。
  final Map<String, GateResult> gateResults;
  final String updatedAt;

  /// stock / etf / futures
  final String assetClass;
  final String license;

  /// 手写机制的精选档案。
  final bool curated;
  final String thresholdVersion;

  /// 结论待重判（如 clean-room 重写后还没重跑）。
  final bool rerunPending;

  /// 后端标注：付费字段（分年 / 机制 / 复现命令）没有下发，需要解锁。
  final bool locked;

  // ── alpha-radar 导出契约（schema_version 1）新增字段 ──────────────────
  /// 注册表 key（「跑一次证伪」用它下单）。
  final String strategyKey;

  /// 家族英文 key：trend / breakout / reversal / …；通讯录分组按它。
  final String familyKey;

  /// 品种中文名（棕榈油）。
  final String name;

  /// 思路来源（原创实现时必填）。
  final String origin;

  /// open / unknown。
  final String licenseStatus;

  /// scale_marginal / yearly_degraded / rerun_pending。
  final List<String> flags;

  /// 精选档案的手写结论。
  final String editorVerdict;

  /// sample 或 data:<gate>。
  final String insufficientReason;
  final String rerunNote;
  final String judgedAt;

  /// 有没有需要付费才能看的内容。
  bool get hasPaidContent =>
      locked ||
      yearly.isNotEmpty ||
      mechanism.trim().isNotEmpty ||
      command.trim().isNotEmpty;

  String get verdictLabel => verdictLabelOf(verdict);

  static String verdictLabelOf(String v) => switch (v) {
        'insufficient' => '样本不足',
        'reject' => '淘汰',
        'pending' => '仍在验证',
        'tradable' => '可交易',
        'finding' => '研究发现',
        _ => '待判定',
      };

  /// 尺度闸门勉强通过（25%–40%）。
  bool get scaleMarginal =>
      flags.contains('scale_marginal') ||
      gateResults['scale']?.status == 'marginal';

  /// 需要重跑后重判（clean-room 重写等）。
  bool get needsRerun => rerunPending || flags.contains('rerun_pending');

  /// 失败闸门的中文名（找不到时返回 id）。
  String failedGateName(List<FalsificationGate> gates) {
    if (failedGate.isEmpty) return '';
    for (final g in gates) {
      if (g.id == failedGate) return g.name;
    }
    return gateNameOf(failedGate);
  }

  static String gateNameOf(String id) => switch (id) {
        'sample' => '样本闸门',
        'scale' => '尺度闸门',
        'yearly' => '分年闸门',
        'drawdown' => '收益回撤比',
        'robust' => '参数稳健性',
        _ => id,
      };

  /// 搜索匹配：策略名 / 品种 / 家族 / 结论 / headline。
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      strategy,
      symbol,
      name,
      family,
      FamilyKeys.label(familyKey),
      familyKey,
      strategyKey,
      freq,
      headline,
      verdictLabel,
      id,
      source,
    ].any((f) => f.isNotEmpty && f.toLowerCase().contains(q));
  }

  /// 解锁后用完整内容覆盖（保留本条已有的免费字段）。
  ArchiveEntry mergedWith(ArchiveEntry full) => ArchiveEntry(
        id: id,
        strategy: full.strategy.isEmpty ? strategy : full.strategy,
        family: full.family.isEmpty ? family : full.family,
        source: full.source.isEmpty ? source : full.source,
        symbol: full.symbol.isEmpty ? symbol : full.symbol,
        freq: full.freq.isEmpty ? freq : full.freq,
        verdict: full.verdict.isEmpty ? verdict : full.verdict,
        headline: full.headline.isEmpty ? headline : full.headline,
        few: full.few.isEmpty ? few : full.few,
        mechanism: full.mechanism,
        command: full.command,
        metrics: full.metrics,
        yearly: full.yearly,
        failedGate: full.failedGate,
        gateResults: full.gateResults.isEmpty ? gateResults : full.gateResults,
        updatedAt: full.updatedAt.isEmpty ? updatedAt : full.updatedAt,
        assetClass: full.assetClass.isEmpty ? assetClass : full.assetClass,
        license: full.license.isEmpty ? license : full.license,
        curated: full.curated || curated,
        thresholdVersion: full.thresholdVersion.isEmpty
            ? thresholdVersion
            : full.thresholdVersion,
        rerunPending: full.rerunPending,
        locked: false,
        strategyKey: full.strategyKey.isEmpty ? strategyKey : full.strategyKey,
        familyKey: full.familyKey.isEmpty ? familyKey : full.familyKey,
        name: full.name.isEmpty ? name : full.name,
        origin: full.origin.isEmpty ? origin : full.origin,
        licenseStatus:
            full.licenseStatus.isEmpty ? licenseStatus : full.licenseStatus,
        flags: full.flags.isEmpty ? flags : full.flags,
        editorVerdict:
            full.editorVerdict.isEmpty ? editorVerdict : full.editorVerdict,
        insufficientReason: full.insufficientReason.isEmpty
            ? insufficientReason
            : full.insufficientReason,
        rerunNote: full.rerunNote.isEmpty ? rerunNote : full.rerunNote,
        judgedAt: full.judgedAt.isEmpty ? judgedAt : full.judgedAt,
      );

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
        failedGate: _str(j['failed_gate']),
        gateResults: _gateResults(j['gates']),
        updatedAt: _str(j['updated_at']),
        assetClass: _str(j['asset_class']),
        license: _str(j['license']),
        curated: j['curated'] == true,
        thresholdVersion: _str(j['threshold_version']),
        rerunPending: j['rerun_pending'] == true,
        locked: j['locked'] == true,
        strategyKey: _str(j['strategy_key']),
        familyKey: _str(j['family_key']),
        name: _str(j['name']),
        origin: _str(j['origin']),
        licenseStatus: _str(j['license_status']),
        flags: [
          if (j['flags'] is List)
            for (final f in j['flags'] as List) '$f'
        ],
        editorVerdict: _str(j['editor_verdict']),
        insufficientReason: _str(j['insufficient_reason']),
        rerunNote: _str(j['rerun_note']),
        judgedAt: _str(j['judged_at']),
      );
}

/// 一道闸门在某条档案上的结果。
class GateResult {
  const GateResult({
    required this.status,
    required this.value,
    required this.threshold,
    this.note = '',
  });

  /// pass / marginal / fail / review / unknown / insufficient
  /// （旧资产里还有 pending / skip）。
  final String status;

  /// 给人看的值 / 门槛：契约里是结构化对象，这里按闸门格式化成一行字。
  final String value;
  final String threshold;
  final String note;

  /// [id] 是闸门 id，用来决定结构化 value / threshold 的读法。
  factory GateResult.fromJson(Map<String, dynamic> j, [String id = '']) =>
      GateResult(
        // alpha-radar 早期草案里叫 result，两种都认。
        status: _str(j['status']).isNotEmpty
            ? _str(j['status'])
            : _str(j['result']),
        value: _gateValue(id, j['value']),
        threshold: _gateThreshold(id, j['threshold']),
        note: _str(j['note']),
      );
}

String _num(dynamic v, [int digits = 2]) {
  if (v is int) return '$v';
  if (v is num) {
    return v == v.roundToDouble() && digits > 0 && v.abs() >= 100
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(digits);
  }
  return v == null ? '' : '$v';
}

String _pct(dynamic v) =>
    v is num ? '${(v * 100).toStringAsFixed(1)}%' : _str(v);

String _gateValue(String id, dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map) {
    final m = v.cast<String, dynamic>();
    switch (id) {
      case 'sample':
        if (m['trades'] == null && m['years'] == null) return '';
        return '${_num(m['trades'], 0)} 笔 / ${_num(m['years'], 0)} 年';
      case 'yearly':
        if (m['years'] == null) return '';
        return '${_num(m['positive_years'], 0)}/${_num(m['years'], 0)} 年为正';
    }
    return m.entries
        .where((e) => e.value is num || e.value is String)
        .map((e) => '${e.key} ${e.value}')
        .join(' · ');
  }
  if (v is num) return id == 'scale' ? _pct(v) : _num(v);
  return '$v';
}

String _gateThreshold(String id, dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Map) {
    final m = v.cast<String, dynamic>();
    switch (id) {
      case 'sample':
        return '≥ ${_num(m['min_trades'], 0)} 笔且 ≥ ${_num(m['min_years'], 0)} 年';
      case 'scale':
        return '< ${_pct(m['pass_below'])}（至 ${_pct(m['fail_at'])} 为勉强）';
      case 'yearly':
        return '正年占比 ≥ ${_num(m['min_positive_ratio'], 1)}'
            '，或近 ${_num(m['recent_full_years'], 0)} 个完整年度不为负';
      case 'drawdown':
        return '≥ ${_num(m['min_pnl_dd'], 1)}'
            '${m['require_positive_pnl'] == true ? ' 且总盈亏为正' : ''}';
    }
    return m.entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }
  return _num(v);
}

/// 家族英文 key → 中文名（alpha-radar 契约的 family_key 取值）。
class FamilyKeys {
  static const labels = {
    'trend': '趋势跟随',
    'breakout': '突破',
    'reversal': '反转',
    'oscillator': '震荡指标',
    'bands': '通道',
    'level': '关键价位',
    'volatility': '波动率',
    'volume': '量能',
    'pattern': '形态',
    'research': '研究发现',
    'unknown': '其他',
  };

  static String label(String key) => labels[key] ?? '';
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
    this.totalPnl,
    this.maxDd,
  });

  /// 契约新增：总盈亏 / 最大回撤（元，回撤为负）；未知为 null。
  final double? totalPnl;
  final double? maxDd;

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
        totalPnl: j['total_pnl'] is num ? _dbl(j['total_pnl']) : null,
        maxDd: j['max_dd'] is num ? _dbl(j['max_dd']) : null,
      );
}

class FalsificationSummary {
  const FalsificationSummary({
    required this.archiveTotal,
    required this.archiveRejected,
    required this.archivePending,
    this.archiveInsufficient = 0,
    required this.tradable,
    required this.scaleRows,
    required this.scaleFail,
    required this.scalePass,
  });

  final int archiveTotal;
  final int archiveRejected;
  final int archivePending;

  /// 样本不足条数（旧资产没有，为 0）。
  final int archiveInsufficient;

  /// 通过全部闸门、可以实盘的策略数。当前是 0，而且这个 0 是产品结论本身。
  final int tradable;
  final int scaleRows;
  final int scaleFail;
  final int scalePass;

  int get findings =>
      archiveTotal - archiveRejected - archivePending - archiveInsufficient;

  factory FalsificationSummary.fromJson(Map<String, dynamic> j) =>
      FalsificationSummary(
        archiveTotal: _int(j['archive_total']),
        // 旧资产：archive_*；alpha-radar 契约：rejected / pending / by_verdict。
        archiveRejected: _firstInt(j, ['archive_rejected', 'rejected'],
            _map(j['by_verdict'])['reject']),
        archivePending: _firstInt(j, ['archive_pending', 'pending'],
            _map(j['by_verdict'])['pending']),
        archiveInsufficient: _firstInt(
            j, ['archive_insufficient'], _map(j['by_verdict'])['insufficient']),
        tradable: _firstInt(j, ['tradable'], _map(j['by_verdict'])['tradable']),
        scaleRows: _int(j['scale_rows']),
        scaleFail: _int(j['scale_fail']),
        scalePass: _int(j['scale_pass']),
      );
}

/// 「跑一次证伪」下单页的选项。
class RunOptions {
  const RunOptions({
    required this.available,
    required this.strategies,
    required this.symbols,
    required this.freqs,
    required this.prices,
  });

  /// 后端是否已接通 alpha-radar 的计算队列；false 时下单只登记、不扣费。
  final bool available;
  final List<RunStrategyOption> strategies;
  final List<String> symbols;
  final List<String> freqs;
  final FalsificationPrices prices;

  factory RunOptions.fromJson(Map<String, dynamic> j) => RunOptions(
        available: j['available'] == true,
        strategies: _list(j['strategies'], RunStrategyOption.fromJson),
        symbols: [
          if (j['symbols'] is List)
            for (final s in j['symbols'] as List) '$s'
        ],
        freqs: [
          if (j['freqs'] is List)
            for (final s in j['freqs'] as List) '$s'
        ],
        prices: FalsificationPrices.fromJson(_map(j['prices'])),
      );
}

class RunStrategyOption {
  const RunStrategyOption(
      {required this.key, required this.name, required this.family});
  final String key;
  final String name;
  final String family;

  factory RunStrategyOption.fromJson(Map<String, dynamic> j) =>
      RunStrategyOption(
        key: _str(j['key']),
        name: _str(j['name']),
        family: _str(j['family']),
      );
}

/// 一次「跑一次证伪」任务。
class FalsificationRun {
  const FalsificationRun({
    required this.id,
    required this.strategy,
    required this.symbol,
    required this.freq,
    required this.credits,
    required this.status,
    required this.charged,
    required this.refunded,
    required this.message,
    required this.error,
    this.result,
  });

  final String id;
  final String strategy;
  final String symbol;
  final String freq;
  final int credits;

  /// queued / running / done / failed / unsupported
  final String status;
  final bool charged;
  final bool refunded;
  final String message;
  final String error;
  final ArchiveEntry? result;

  bool get finished =>
      status == 'done' || status == 'failed' || status == 'unsupported';

  factory FalsificationRun.fromJson(Map<String, dynamic> j) => FalsificationRun(
        id: _str(j['id']),
        strategy: _str(j['strategy']),
        symbol: _str(j['symbol']),
        freq: _str(j['freq']),
        credits: _int(j['credits']),
        status: _str(j['status']),
        charged: j['charged'] == true,
        refunded: j['refunded'] == true,
        message: _str(j['message']),
        error: _str(j['error']),
        result: j['result'] is Map
            ? ArchiveEntry.fromJson(_map(j['result']))
            : null,
      );
}

// ── 容错解析工具 ────────────────────────────────────────────────────────

int _firstInt(Map<String, dynamic> j, List<String> keys, dynamic fallback) {
  for (final k in keys) {
    if (j[k] != null) return _int(j[k]);
  }
  return _int(fallback);
}

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

Map<String, GateResult> _gateResults(dynamic v) {
  // 顶层 gates 是闸门说明（List），条目里的 gates 是结果（Map）。
  if (v is! Map) return const {};
  final out = <String, GateResult>{};
  v.forEach((k, e) {
    if (e is Map) {
      out['$k'] = GateResult.fromJson(e.cast<String, dynamic>(), '$k');
    }
  });
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
