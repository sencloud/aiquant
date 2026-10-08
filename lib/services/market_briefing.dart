import 'package:dio/dio.dart';

import '../core/api/api_client.dart' show ApiClient, buildNoProxyAdapter;
import '../models/instrument.dart' show CandlePoint;
import 'tushare_service.dart';

/// A 股交易时段。首页快捷提问按当前时段 + 开/收盘行情生成。
enum MarketPhase {
  preOpen, // 盘前（09:15 前）
  morning, // 早盘（09:15–11:30）
  noon, // 午间休市（上午收盘 11:30–13:00）
  afternoon, // 午后（13:00–15:00）
  closed, // 已收盘（15:00 后）
  holiday, // 周末 / 非交易日
}

extension MarketPhaseLabel on MarketPhase {
  String get label {
    switch (this) {
      case MarketPhase.preOpen:
        return '盘前';
      case MarketPhase.morning:
        return '早盘';
      case MarketPhase.noon:
        return '午间休市';
      case MarketPhase.afternoon:
        return '午后';
      case MarketPhase.closed:
        return '已收盘';
      case MarketPhase.holiday:
        return '非交易日';
    }
  }
}

/// 单个宽基指数的行情快照（元 / 点，涨跌幅为百分比）。
class IndexQuote {
  const IndexQuote({
    required this.name,
    required this.last,
    required this.pctChg,
    this.open,
    this.high,
    this.low,
    this.preClose,
  });

  final String name;
  final double last;
  final double pctChg;
  final double? open;
  final double? high;
  final double? low;
  final double? preClose;

  bool get valid => last > 0;
}

/// 首页快捷提问生成器。
///
/// 思路：先定位当前 A 股时段（盘前 / 早盘 / 午间 / 午后 / 收盘），再拉一组
/// 宽基指数的最新行情（东方财富 push2 实时，失败退回 Tushare 日线），最后把
/// 「开盘价 / 最新价（收盘价）+ 涨跌幅 + 领涨领跌」组织成 3 条口语化提问。
///
/// 任何一步失败都返回空列表，由调用方回退到 Persona 默认建议。
class MarketBriefingService {
  MarketBriefingService({Dio? dio, TushareService? tushare})
      : _dio = dio ?? Dio(),
        _tushare = tushare ?? TushareService() {
    _dio.options.connectTimeout = const Duration(seconds: 8);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _dio.httpClientAdapter = buildNoProxyAdapter();
  }

  final Dio _dio;
  final TushareService _tushare;

  /// 关注的一组宽基指数：secid（东财） + 中文名 + Tushare 代码。
  static const List<({String secid, String name, String tsCode})> _targets = [
    (secid: '1.000001', name: '上证指数', tsCode: '000001.SH'),
    (secid: '0.399001', name: '深证成指', tsCode: '399001.SZ'),
    (secid: '0.399006', name: '创业板指', tsCode: '399006.SZ'),
    (secid: '1.000300', name: '沪深300', tsCode: '000300.SH'),
    (secid: '1.000688', name: '科创50', tsCode: '000688.SH'),
  ];

  /// 北京时间（与运行设备时区无关）。
  static DateTime beijingNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  /// 按北京时间判断当前时段（仅按工作日近似；真假日由行情数据兜底）。
  static MarketPhase phaseAt(DateTime beijing) {
    if (beijing.weekday == DateTime.saturday ||
        beijing.weekday == DateTime.sunday) {
      return MarketPhase.holiday;
    }
    final minutes = beijing.hour * 60 + beijing.minute;
    if (minutes < 9 * 60 + 15) return MarketPhase.preOpen;
    if (minutes < 11 * 60 + 30) return MarketPhase.morning;
    if (minutes < 13 * 60) return MarketPhase.noon;
    if (minutes < 15 * 60) return MarketPhase.afternoon;
    return MarketPhase.closed;
  }

  /// 生成首页 3 条快捷提问；数据不可用时返回空列表。
  ///
  /// 优先用服务端定时任务生成的结果（模型写的、带真实点位），拿不到或已是
  /// 隔夜的则回退到本地按当前时段行情拼装。
  Future<List<String>> loadSuggestions() async {
    final remote = await _fetchServerSuggestions();
    if (remote.isNotEmpty) return remote;

    final phase = phaseAt(beijingNow());
    var quotes = const <IndexQuote>[];
    try {
      quotes = await _fetchRealtime();
    } catch (_) {
      try {
        quotes = await _fetchDaily();
      } catch (_) {
        return const [];
      }
    }
    return _buildSuggestions(phase, quotes);
  }

  /// 读服务端 `/v1/ai/home-suggestions`（由 scheduler 按时段生成）。
  ///
  /// 接口公开、无用户数据；未生成、隔夜或网络异常一律返回空列表交由上层兜底。
  Future<List<String>> _fetchServerSuggestions() async {
    try {
      final resp = await ApiClient.instance.dio
          .get<Map<String, dynamic>>('/v1/ai/home-suggestions');
      final data = resp.data;
      if (data == null || data['stale'] == true) return const [];
      final list = data['questions'];
      if (list is! List) return const [];
      return [
        for (final q in list)
          if (q is String && q.trim().isNotEmpty) q.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ── 数据源 1：东方财富 push2 实时行情 ──────────────────────────────────

  Future<List<IndexQuote>> _fetchRealtime() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      'https://push2delay.eastmoney.com/api/qt/ulist.np/get',
      queryParameters: {
        'secids': _targets.map((t) => t.secid).join(','),
        'fields': 'f1,f2,f3,f4,f12,f13,f14,f15,f16,f17,f18',
      },
      options: Options(headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; finme-app)',
        'Referer': 'https://quote.eastmoney.com/',
      }),
    );
    final diff = (resp.data?['data'] as Map?)?['diff'];
    if (diff is! List || diff.isEmpty) {
      throw StateError('empty eastmoney diff');
    }
    final quotes = <IndexQuote>[];
    for (final raw in diff) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final last = _scaled(m['f2']);
      if (last == null || last <= 0) continue;
      quotes.add(IndexQuote(
        name: (m['f14'] ?? '').toString(),
        last: last,
        pctChg: _scaled(m['f3']) ?? 0,
        open: _scaled(m['f17']),
        high: _scaled(m['f15']),
        low: _scaled(m['f16']),
        preClose: _scaled(m['f18']),
      ));
    }
    if (quotes.isEmpty) throw StateError('no valid eastmoney quote');
    return quotes;
  }

  // ── 数据源 2：Tushare 日线兜底（收盘后才含当日） ────────────────────────

  Future<List<IndexQuote>> _fetchDaily() async {
    final now = beijingNow();
    final start = now.subtract(const Duration(days: 20));
    final results = await Future.wait([
      for (final t in _targets)
        _tushare
            .indexDaily(tsCode: t.tsCode, startDate: _ymd(start), endDate: _ymd(now))
            .then((rows) => (t.name, rows))
            .catchError((_) => (t.name, const <CandlePoint>[])),
    ]);
    final quotes = <IndexQuote>[];
    for (final (name, rows) in results) {
      if (rows.isEmpty) continue;
      final last = rows.last;
      quotes.add(IndexQuote(
        name: name,
        last: last.close,
        pctChg: last.pctChg ?? 0,
        open: last.open,
        high: last.high,
        low: last.low,
      ));
    }
    return quotes;
  }

  // ── 组装提问文案 ──────────────────────────────────────────────────────

  List<String> _buildSuggestions(MarketPhase phase, List<IndexQuote> quotes) {
    final valid = [for (final q in quotes) if (q.valid) q];
    if (valid.isEmpty) return const [];
    final sh = valid.firstWhere(
      (q) => q.name.contains('上证'),
      orElse: () => valid.first,
    );
    final ranked = [...valid]..sort((a, b) => b.pctChg.compareTo(a.pctChg));
    final lead = ranked.first;
    final lag = ranked.last;
    final hasBreadth = ranked.length > 1 && lead.name != lag.name;

    final shClose = sh.last.toStringAsFixed(2);
    final shPct = _pct(sh.pctChg);
    final shOpen = sh.open?.toStringAsFixed(2);
    // 领涨 / 领跌：用「最强 / 最弱」+ 带符号百分比，涨跌都能读通顺。
    final breadth =
        '${lead.name}最强（${_pct(lead.pctChg)}）、${lag.name}最弱（${_pct(lag.pctChg)}）';

    switch (phase) {
      case MarketPhase.preOpen:
        return [
          '昨日${sh.name}收于 $shClose 点（$shPct），今天开盘前有哪些消息值得关注？',
          if (hasBreadth)
            '昨日主要指数里$breadth，今天开盘这些方向怎么跟？'
          else
            '结合昨日收盘和隔夜外盘，帮我做一份今天的开盘策略',
          '帮我梳理今天 A 股开盘前的关注要点和风险',
        ];
      case MarketPhase.morning:
        return [
          '今天早盘${sh.name}现报 $shClose 点（$shPct），现在市场情绪怎么样？',
          if (shOpen != null)
            '今天${sh.name}开在 $shOpen、现价 $shClose（$shPct），帮我解读早盘资金流向'
          else
            '帮我解读今天早盘的成交结构和资金流向',
          if (hasBreadth)
            '早盘$breadth，现在该关注哪些方向？'
          else
            '早盘哪些板块和个股在领涨，背后是什么逻辑？',
        ];
      case MarketPhase.noon:
        return [
          '今天上午${sh.name}收于 $shClose 点（$shPct），帮我复盘上午盘面',
          if (hasBreadth)
            '上午$breadth，午后哪些板块值得盯？'
          else
            '上午哪些板块领涨，午后应该重点关注什么？',
          '结合上午收盘情况，帮我梳理下午的操作要点',
        ];
      case MarketPhase.afternoon:
        return [
          '今天${sh.name}现报 $shClose 点（$shPct），尾盘会怎么走？',
          if (shOpen != null)
            '今天${sh.name}开盘 $shOpen、现价 $shClose，帮我分析下午的走势'
          else
            '帮我分析今天下午的走势和可能的收盘情况',
          if (hasBreadth)
            '今天$breadth，尾盘该加仓还是减仓？'
          else
            '当前盘面下，尾盘该加仓还是减仓？',
        ];
      case MarketPhase.closed:
        return [
          '今天${sh.name}收于 $shClose 点（$shPct），帮我复盘今天 A 股走势',
          if (hasBreadth)
            '今天$breadth，明天可以关注什么？'
          else
            '今天市场收涨/收跌的原因是什么，明天可以关注什么？',
          if (shOpen != null)
            '今天${sh.name}开 $shOpen、收 $shClose、振幅 ${_amplitude(sh)}，'
                '成交和资金面说明了什么？'
          else
            '帮我梳理今天的资金流向和板块轮动，明天怎么应对',
        ];
      case MarketPhase.holiday:
        return [
          '最近交易日${sh.name}收于 $shClose 点（$shPct），帮我回顾这段行情',
          if (hasBreadth)
            '上个交易日$breadth，下个交易日怎么应对？'
          else
            '帮我回顾最近一周 A 股主要指数的表现和资金流向',
          '休市期间有哪些消息可能影响下个交易日？',
        ];
    }
  }

  static String _pct(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

  static String _amplitude(IndexQuote q) {
    final pre = q.preClose ?? q.low;
    if (q.high == null || q.low == null || pre == null || pre <= 0) return '--';
    return '${((q.high! - q.low!) / pre * 100).toStringAsFixed(2)}%';
  }

  /// 东财 push2 的价格 / 百分比都是 ×100 的整数，还原成 2 位小数。
  static double? _scaled(dynamic raw) {
    final v = _num(raw);
    if (v == null) return null;
    return v / 100.0;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}
