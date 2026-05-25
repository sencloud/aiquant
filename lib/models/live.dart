// AI 直播相关 DTO，与后端 internal/live/service.go 一一对应。
//
// - LiveSession 单场直播（含选股列表 + 报告概览）
// - LiveReportBrief 单只票 × 单分析师的概览（列表用）
// - LiveReportFull 含完整 html_body（详情用，WebView 渲染）
// - LiveWatchItem 用户关注表

class LiveSession {
  const LiveSession({
    required this.uuid,
    required this.scheduledAt,
    required this.phase,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.selectionReason = '',
    this.pickedSymbols = const [],
    this.reportCount = 0,
    this.reports = const [],
  });

  final String uuid;
  final int scheduledAt; // unix ms
  final String phase; // pre / intraday / post
  final String status; // pending / running / done / failed
  final int? startedAt;
  final int? finishedAt;
  final String selectionReason;
  final List<LivePickedSymbol> pickedSymbols;
  final int reportCount;
  final List<LiveReportBrief> reports;

  bool get isDone => status == 'done';
  bool get isRunning => status == 'running';
  bool get isFailed => status == 'failed';

  String get phaseLabel => switch (phase) {
        'pre' => '盘前',
        'intraday' => '盘中',
        'post' => '盘后',
        _ => phase,
      };

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final picksRaw = (json['picked_symbols'] as List?) ?? const [];
    final reportsRaw = (json['reports'] as List?) ?? const [];
    return LiveSession(
      uuid: json['uuid'] as String,
      scheduledAt: (json['scheduled_at'] as num).toInt(),
      phase: (json['phase'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      startedAt: (json['started_at'] as num?)?.toInt(),
      finishedAt: (json['finished_at'] as num?)?.toInt(),
      selectionReason: (json['selection_reason'] as String?) ?? '',
      pickedSymbols: picksRaw
          .cast<Map<String, dynamic>>()
          .map(LivePickedSymbol.fromJson)
          .toList(),
      reportCount: ((json['report_count'] as num?) ?? 0).toInt(),
      reports: reportsRaw
          .cast<Map<String, dynamic>>()
          .map(LiveReportBrief.fromJson)
          .toList(),
    );
  }
}

class LivePickedSymbol {
  const LivePickedSymbol({
    required this.symbol,
    required this.name,
    required this.source,
  });
  final String symbol;
  final String name;
  final String source;

  factory LivePickedSymbol.fromJson(Map<String, dynamic> json) =>
      LivePickedSymbol(
        symbol: (json['symbol'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        source: (json['source'] as String?) ?? '',
      );
}

class LiveReportBrief {
  const LiveReportBrief({
    required this.id,
    required this.symbol,
    required this.symbolName,
    required this.personaId,
    required this.personaName,
    this.view = '',
    this.rating = '',
    this.targetPrice,
    this.stopLoss,
    this.takeProfit,
    this.positionHint = '',
    this.summary = '',
    required this.createdAt,
  });

  final int id;
  final String symbol;
  final String symbolName;
  final String personaId;
  final String personaName;
  final String view; // bullish / neutral / bearish
  final String rating;
  final double? targetPrice;
  final double? stopLoss;
  final double? takeProfit;
  final String positionHint;
  final String summary;
  final int createdAt;

  factory LiveReportBrief.fromJson(Map<String, dynamic> json) =>
      LiveReportBrief(
        id: (json['id'] as num).toInt(),
        symbol: (json['symbol'] as String?) ?? '',
        symbolName: (json['symbol_name'] as String?) ?? '',
        personaId: (json['persona_id'] as String?) ?? '',
        personaName: (json['persona_name'] as String?) ?? '',
        view: (json['view'] as String?) ?? '',
        rating: (json['rating'] as String?) ?? '',
        targetPrice: (json['target_price'] as num?)?.toDouble(),
        stopLoss: (json['stop_loss'] as num?)?.toDouble(),
        takeProfit: (json['take_profit'] as num?)?.toDouble(),
        positionHint: (json['position_hint'] as String?) ?? '',
        summary: (json['summary'] as String?) ?? '',
        createdAt: (json['created_at'] as num).toInt(),
      );
}

class LiveReportFull extends LiveReportBrief {
  const LiveReportFull({
    required super.id,
    required super.symbol,
    required super.symbolName,
    required super.personaId,
    required super.personaName,
    super.view,
    super.rating,
    super.targetPrice,
    super.stopLoss,
    super.takeProfit,
    super.positionHint,
    super.summary,
    required super.createdAt,
    required this.htmlBody,
  });

  final String htmlBody;

  factory LiveReportFull.fromJson(Map<String, dynamic> json) => LiveReportFull(
        id: (json['id'] as num).toInt(),
        symbol: (json['symbol'] as String?) ?? '',
        symbolName: (json['symbol_name'] as String?) ?? '',
        personaId: (json['persona_id'] as String?) ?? '',
        personaName: (json['persona_name'] as String?) ?? '',
        view: (json['view'] as String?) ?? '',
        rating: (json['rating'] as String?) ?? '',
        targetPrice: (json['target_price'] as num?)?.toDouble(),
        stopLoss: (json['stop_loss'] as num?)?.toDouble(),
        takeProfit: (json['take_profit'] as num?)?.toDouble(),
        positionHint: (json['position_hint'] as String?) ?? '',
        summary: (json['summary'] as String?) ?? '',
        createdAt: (json['created_at'] as num).toInt(),
        htmlBody: (json['html_body'] as String?) ?? '',
      );
}

class LiveWatchItem {
  const LiveWatchItem({
    required this.symbol,
    required this.symbolName,
    required this.createdAt,
  });
  final String symbol;
  final String symbolName;
  final int createdAt;

  factory LiveWatchItem.fromJson(Map<String, dynamic> json) => LiveWatchItem(
        symbol: (json['symbol'] as String?) ?? '',
        symbolName: (json['symbol_name'] as String?) ?? '',
        createdAt: ((json['created_at'] as num?) ?? 0).toInt(),
      );
}
