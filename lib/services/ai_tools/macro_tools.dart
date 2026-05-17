import 'dart:convert';

import '../../core/utils/china_market.dart';
import '../ai_tools.dart';
import 'tushare_tools.dart';

String _formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// 15. 指数成分股（沪深 300 / 中证 500 / 上证 50 等）
class GetIndexComponentsTool extends AiTool {
  GetIndexComponentsTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_index_components';
  @override
  String get description =>
      '获取一个 A 股宽基指数最新一期的成分股及权重（沪深 300=000300.SH、'
      '中证 500=000905.SH、上证 50=000016.SH、科创 50=000688.SH、中证 1000=000852.SH 等）。'
      '用于回答"沪深 300 里权重最大的是哪几只 / 中证 500 都有哪些股票"。';

  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'index_code': {
            'type': 'string',
            'description': '指数 ts_code，如 000300.SH',
          },
          'top': {
            'type': 'integer',
            'description': '只返回权重前 N 大（默认 30，最大 100）',
          },
        },
        required: ['index_code'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['index_code'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'index_code 必填'});
    final top = (toNum(args['top'])?.toInt() ?? 30).clamp(1, 100);
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 60));
    final rows = await _ctx.svc.query(
      apiName: 'index_weight',
      params: {
        'index_code': code,
        'start_date': _formatYmd(start),
        'end_date': _formatYmd(end),
      },
      fields: 'index_code,con_code,trade_date,weight',
    );
    if (rows.isEmpty) {
      return jsonEncode({'index_code': code, 'error': '无成分股权重数据'});
    }
    rows.sort((a, b) => (b['trade_date'] ?? '')
        .toString()
        .compareTo((a['trade_date'] ?? '').toString()));
    final latestDate = rows.first['trade_date'];
    final latest = rows.where((r) => r['trade_date'] == latestDate).toList();
    latest.sort((a, b) {
      final wa = toNum(a['weight'])?.toDouble() ?? 0;
      final wb = toNum(b['weight'])?.toDouble() ?? 0;
      return wb.compareTo(wa);
    });
    return jsonEncode({
      'index_code': code,
      'as_of': latestDate,
      'count_total': latest.length,
      'top_components': [
        for (final r in latest.take(top))
          {
            'ts_code': r['con_code'],
            'weight_pct': r['weight'],
          },
      ],
    });
  }
}

/// 16. 融资融券余额
class GetMarginTradingTool extends AiTool {
  GetMarginTradingTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_margin_trading';
  @override
  String get description =>
      '获取最近 N 天 A 股市场两融（融资融券）余额走势：融资余额、融券余额、'
      '总两融余额。两融余额是市场杠杆资金情绪的重要指标，余额激增通常预示风险偏好抬升。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'days': {'type': 'integer', 'description': '回看交易日数（默认 10，最大 60）'},
          'exchange': {
            'type': 'string',
            'enum': ['SSE', 'SZSE', 'BSE', 'ALL'],
            'description': '交易所（默认 ALL = 上交+深交合计）',
          },
        },
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final days = (toNum(args['days'])?.toInt() ?? 10).clamp(1, 60);
    final exchange =
        (args['exchange'] as String? ?? 'ALL').toUpperCase();
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days * 2 + 7));
    final params = <String, dynamic>{
      'start_date': _formatYmd(start),
      'end_date': _formatYmd(end),
    };
    if (exchange != 'ALL') params['exchange_id'] = exchange;
    final rows = await _ctx.svc.query(
      apiName: 'margin',
      params: params,
      fields: 'trade_date,exchange_id,rzye,rqye,rzrqye,rzmre,rzche,rqmcl,rqchl',
    );
    if (rows.isEmpty) {
      return jsonEncode({'error': '无两融数据'});
    }
    rows.sort((a, b) => (b['trade_date'] ?? '')
        .toString()
        .compareTo((a['trade_date'] ?? '').toString()));
    final tail = rows.take(days).toList();
    return jsonEncode({
      'days': tail.length,
      'exchange': exchange,
      'records': [
        for (final r in tail)
          {
            'trade_date': r['trade_date'],
            'exchange': r['exchange_id'],
            'financing_balance_yuan': r['rzye'],
            'short_selling_balance_yuan': r['rqye'],
            'total_margin_balance_yuan': r['rzrqye'],
            'financing_buy_amount_yuan': r['rzmre'],
            'financing_repay_amount_yuan': r['rzche'],
          },
      ],
    });
  }
}

/// 17. 北向资金（陆股通）流向
class GetNorthboundFlowTool extends AiTool {
  GetNorthboundFlowTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_northbound_flow';
  @override
  String get description =>
      '获取最近 N 天沪股通+深股通的北向资金净买入金额（俗称"北水"）。'
      '北向资金是 A 股的重要外资风向标，连续大幅净流入通常意味外资看多 A 股。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'days': {'type': 'integer', 'description': '回看交易日数（默认 10，最大 60）'},
        },
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final days = (toNum(args['days'])?.toInt() ?? 10).clamp(1, 60);
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days * 2 + 7));
    final rows = await _ctx.svc.query(
      apiName: 'moneyflow_hsgt',
      params: {
        'start_date': _formatYmd(start),
        'end_date': _formatYmd(end),
      },
      fields:
          'trade_date,ggt_ss,ggt_sz,hgt,sgt,north_money,south_money',
    );
    if (rows.isEmpty) {
      return jsonEncode({'error': '无沪深港通数据'});
    }
    rows.sort((a, b) => (b['trade_date'] ?? '')
        .toString()
        .compareTo((a['trade_date'] ?? '').toString()));
    final tail = rows.take(days).toList();
    var sumNorth = 0.0;
    for (final r in tail) {
      final n = toNum(r['north_money'])?.toDouble() ?? 0;
      sumNorth += n;
    }
    return jsonEncode({
      'days': tail.length,
      'cumulative_north_inflow_yuan_wan':
          double.parse(sumNorth.toStringAsFixed(2)),
      'records': [
        for (final r in tail)
          {
            'trade_date': r['trade_date'],
            'north_inflow_yuan_wan': r['north_money'],
            'south_inflow_hkd_wan': r['south_money'],
            'shanghai_connect_yuan_wan': r['hgt'],
            'shenzhen_connect_yuan_wan': r['sgt'],
          },
      ],
    });
  }
}

/// 18. 行业资金流（同花顺/东财）
class GetIndustryMoneyFlowTool extends AiTool {
  GetIndustryMoneyFlowTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_industry_money_flow';
  @override
  String get description =>
      '获取最近一日 A 股行业（东方财富分类）的资金净流入排名。'
      '回答"今天哪个行业最火 / 资金在追什么板块"等问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'top': {'type': 'integer', 'description': '只返回净流入前 N（默认 15，最大 50）'},
        },
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final top = (toNum(args['top'])?.toInt() ?? 15).clamp(1, 50);
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 7));
    final rows = await _ctx.svc.query(
      apiName: 'moneyflow_ind_dc',
      params: {
        'start_date': _formatYmd(start),
        'end_date': _formatYmd(end),
      },
      fields:
          'trade_date,name,pct_change,close,net_amount,buy_elg_amount,buy_lg_amount,buy_md_amount,buy_sm_amount',
    );
    if (rows.isEmpty) {
      return jsonEncode({'error': '无行业资金流数据'});
    }
    rows.sort((a, b) => (b['trade_date'] ?? '')
        .toString()
        .compareTo((a['trade_date'] ?? '').toString()));
    final latestDate = rows.first['trade_date'];
    final latest = rows.where((r) => r['trade_date'] == latestDate).toList();
    latest.sort((a, b) {
      final na = toNum(a['net_amount'])?.toDouble() ?? 0;
      final nb = toNum(b['net_amount'])?.toDouble() ?? 0;
      return nb.compareTo(na);
    });
    return jsonEncode({
      'trade_date': latestDate,
      'industries': [
        for (final r in latest.take(top))
          {
            'industry': r['name'],
            'net_inflow_yuan_wan': r['net_amount'],
            'pct_change': r['pct_change'],
            'close_index': r['close'],
            'extra_large_inflow': r['buy_elg_amount'],
            'large_inflow': r['buy_lg_amount'],
          },
      ],
    });
  }
}

/// 工厂
List<AiTool> buildMacroTools(TushareToolsContext ctx) => [
      GetIndexComponentsTool(ctx),
      GetMarginTradingTool(ctx),
      GetNorthboundFlowTool(ctx),
      GetIndustryMoneyFlowTool(ctx),
    ];
