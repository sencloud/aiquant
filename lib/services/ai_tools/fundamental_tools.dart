import 'dart:convert';

import '../../core/utils/china_market.dart';
import '../ai_tools.dart';
import 'tushare_tools.dart';

/// Tushare 上市公司财务接口大多需要 Pro 5000+ 积分，部分接口免费但有
/// 频次/字段限制。这里所有工具都对接口异常容错——返回 {error} 而不是
/// crash，让 AI 可以继续推理。
class _Yeoman {
  // 共享 helper，避免重复代码
  static String formatYmd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 9. 估值快照（PE/PB/PS/股息率/换手率）
class GetValuationTool extends AiTool {
  GetValuationTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_valuation';
  @override
  String get description =>
      '获取一只 A 股最新的市盈率(PE/PE_TTM)、市净率(PB)、市销率(PS)、股息率、换手率、'
      '总市值/流通市值。回答"现在贵不贵 / 估值合理吗"等问题时使用。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string', 'description': 'A 股代码'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'daily_basic 只支持 A 股个股'});
    }
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 14));
    final rows = await _ctx.svc.query(
      apiName: 'daily_basic',
      params: {
        'ts_code': code,
        'start_date': _Yeoman.formatYmd(start),
        'end_date': _Yeoman.formatYmd(end),
      },
      fields:
          'ts_code,trade_date,close,turnover_rate,volume_ratio,pe,pe_ttm,pb,ps,ps_ttm,dv_ratio,dv_ttm,total_share,float_share,total_mv,circ_mv',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无估值数据（接口权限或当日休市）'});
    }
    rows.sort((a, b) =>
        (b['trade_date'] ?? '').toString().compareTo((a['trade_date'] ?? '').toString()));
    final r = rows.first;
    return jsonEncode({
      'symbol': code,
      'trade_date': r['trade_date'],
      'close': r['close'],
      'pe': r['pe'],
      'pe_ttm': r['pe_ttm'],
      'pb': r['pb'],
      'ps': r['ps'],
      'ps_ttm': r['ps_ttm'],
      'dividend_yield_pct': r['dv_ratio'],
      'dividend_yield_ttm_pct': r['dv_ttm'],
      'turnover_rate_pct': r['turnover_rate'],
      'total_market_cap_yuan_wan': r['total_mv'],
      'float_market_cap_yuan_wan': r['circ_mv'],
    });
  }
}

/// 10. 利润表
class GetIncomeStatementTool extends AiTool {
  GetIncomeStatementTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_income_statement';
  @override
  String get description =>
      '获取一只 A 股最近 N 期（年报/季报）利润表关键科目：营业收入、营业成本、'
      '毛利、研发费用、营业利润、归母净利润、扣非净利润。'
      '用于回答"营收增速 / 利润率 / 利润趋势"等基本面问题。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'periods': {'type': 'integer', 'description': '返回最近 N 期（默认 4，最大 12）'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'income 只支持 A 股个股'});
    }
    final n = ((args['periods'] as num?)?.toInt() ?? 4).clamp(1, 12);
    final rows = await _ctx.svc.query(
      apiName: 'income',
      params: {'ts_code': code},
      fields:
          'ts_code,end_date,report_type,revenue,oper_cost,total_cogs,operate_profit,total_profit,n_income_attr_p,basic_eps,diluted_eps,rd_exp',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无利润表数据（可能权限不足）'});
    }
    rows.sort((a, b) =>
        (b['end_date'] ?? '').toString().compareTo((a['end_date'] ?? '').toString()));
    final tail = rows.take(n).toList();
    return jsonEncode({
      'symbol': code,
      'periods': tail.length,
      'income_statements': [
        for (final r in tail)
          {
            'end_date': r['end_date'],
            'revenue_yuan': r['revenue'],
            'oper_cost_yuan': r['oper_cost'],
            'operating_profit_yuan': r['operate_profit'],
            'total_profit_yuan': r['total_profit'],
            'net_profit_attr_parent_yuan': r['n_income_attr_p'],
            'rd_expense_yuan': r['rd_exp'],
            'basic_eps': r['basic_eps'],
          },
      ],
    });
  }
}

/// 11. 资产负债表
class GetBalanceSheetTool extends AiTool {
  GetBalanceSheetTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_balance_sheet';
  @override
  String get description =>
      '获取一只 A 股最近 N 期资产负债表的关键科目：总资产、总负债、所有者权益、'
      '现金及等价物、应收账款、存货、有息负债。用于评估资产负债结构与偿债能力。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'periods': {'type': 'integer', 'description': '默认 4'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'balancesheet 只支持 A 股'});
    }
    final n = ((args['periods'] as num?)?.toInt() ?? 4).clamp(1, 12);
    final rows = await _ctx.svc.query(
      apiName: 'balancesheet',
      params: {'ts_code': code},
      fields:
          'ts_code,end_date,total_assets,total_liab,total_hldr_eqy_inc_min_int,money_cap,accounts_receiv,inventories,st_borr,lt_borr,bond_payable',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无资产负债表数据'});
    }
    rows.sort((a, b) => (b['end_date'] ?? '')
        .toString()
        .compareTo((a['end_date'] ?? '').toString()));
    final tail = rows.take(n).toList();
    return jsonEncode({
      'symbol': code,
      'periods': tail.length,
      'balance_sheets': [
        for (final r in tail)
          {
            'end_date': r['end_date'],
            'total_assets_yuan': r['total_assets'],
            'total_liabilities_yuan': r['total_liab'],
            'total_equity_yuan': r['total_hldr_eqy_inc_min_int'],
            'cash_yuan': r['money_cap'],
            'accounts_receivable_yuan': r['accounts_receiv'],
            'inventories_yuan': r['inventories'],
            'short_term_borrowing_yuan': r['st_borr'],
            'long_term_borrowing_yuan': r['lt_borr'],
            'bond_payable_yuan': r['bond_payable'],
          },
      ],
    });
  }
}

/// 12. 现金流量表
class GetCashFlowTool extends AiTool {
  GetCashFlowTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_cash_flow';
  @override
  String get description =>
      '获取一只 A 股最近 N 期现金流量表：经营/投资/融资活动的净现金流、'
      '资本支出（capex）、自由现金流估算。用于判断"赚的钱是不是真现金"。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'periods': {'type': 'integer'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'cashflow 只支持 A 股'});
    }
    final n = ((args['periods'] as num?)?.toInt() ?? 4).clamp(1, 12);
    final rows = await _ctx.svc.query(
      apiName: 'cashflow',
      params: {'ts_code': code},
      fields:
          'ts_code,end_date,n_cashflow_act,n_cashflow_inv_act,n_cash_flows_fnc_act,c_pay_acq_const_fiolta,free_cashflow',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无现金流量数据'});
    }
    rows.sort((a, b) => (b['end_date'] ?? '')
        .toString()
        .compareTo((a['end_date'] ?? '').toString()));
    final tail = rows.take(n).toList();
    return jsonEncode({
      'symbol': code,
      'periods': tail.length,
      'cash_flow_statements': [
        for (final r in tail)
          {
            'end_date': r['end_date'],
            'operating_cash_flow_yuan': r['n_cashflow_act'],
            'investing_cash_flow_yuan': r['n_cashflow_inv_act'],
            'financing_cash_flow_yuan': r['n_cash_flows_fnc_act'],
            'capex_yuan': r['c_pay_acq_const_fiolta'],
            'free_cash_flow_yuan': r['free_cashflow'],
          },
      ],
    });
  }
}

/// 13. 十大股东
class GetTopHoldersTool extends AiTool {
  GetTopHoldersTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_top_holders';
  @override
  String get description =>
      '获取一只 A 股最新一期的十大股东名单与持股比例（机构 / 国家队 / 实控人）。'
      '用于回答"机构持仓 / 大股东动向"。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'top10_holders 只支持 A 股'});
    }
    final rows = await _ctx.svc.query(
      apiName: 'top10_holders',
      params: {'ts_code': code},
      fields: 'ts_code,end_date,holder_name,hold_amount,hold_ratio',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无十大股东数据'});
    }
    rows.sort((a, b) => (b['end_date'] ?? '')
        .toString()
        .compareTo((a['end_date'] ?? '').toString()));
    final latestEndDate = rows.first['end_date'];
    final latest =
        rows.where((r) => r['end_date'] == latestEndDate).take(10).toList();
    return jsonEncode({
      'symbol': code,
      'end_date': latestEndDate,
      'holders': [
        for (final r in latest)
          {
            'name': r['holder_name'],
            'shares': r['hold_amount'],
            'ratio_pct': r['hold_ratio'],
          },
      ],
    });
  }
}

/// 14. 分红送转历史
class GetDividendTool extends AiTool {
  GetDividendTool(this._ctx);
  final TushareToolsContext _ctx;

  @override
  String get name => 'get_dividend_history';
  @override
  String get description =>
      '获取一只 A 股最近 N 次分红送转记录（每股股利、每股转增、除权除息日）。'
      '用于回答"股息持续性 / 高股息策略"。';
  @override
  ToolParameterSchema get parameters => const ToolParameterSchema(
        properties: {
          'symbol': {'type': 'string'},
          'limit': {'type': 'integer', 'description': '默认 10'},
        },
        required: ['symbol'],
      );

  @override
  Future<String> run(Map<String, dynamic> args) async {
    final code = ChinaMarket.normalizeSymbol(
        (args['symbol'] as String? ?? '').trim());
    if (code.isEmpty) return jsonEncode({'error': 'symbol 必填'});
    if (!ChinaMarket.isStock(code)) {
      return jsonEncode({'error': 'dividend 只支持 A 股'});
    }
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 30);
    final rows = await _ctx.svc.query(
      apiName: 'dividend',
      params: {'ts_code': code},
      fields:
          'ts_code,ann_date,end_date,div_proc,stk_div,stk_bo_rate,stk_co_rate,cash_div,cash_div_tax,record_date,ex_date,pay_date,imp_ann_date',
    );
    if (rows.isEmpty) {
      return jsonEncode({'symbol': code, 'error': '无分红记录'});
    }
    rows.sort((a, b) => (b['end_date'] ?? '')
        .toString()
        .compareTo((a['end_date'] ?? '').toString()));
    return jsonEncode({
      'symbol': code,
      'count': rows.length,
      'records': [
        for (final r in rows.take(limit))
          {
            'end_date': r['end_date'],
            'announce_date': r['ann_date'],
            'ex_dividend_date': r['ex_date'],
            'pay_date': r['pay_date'],
            'cash_dividend_per_share_yuan': r['cash_div'],
            'cash_dividend_after_tax_yuan': r['cash_div_tax'],
            'stock_dividend_per_share': r['stk_div'],
            'process_status': r['div_proc'],
          },
      ],
    });
  }
}

/// 工厂
List<AiTool> buildFundamentalTools(TushareToolsContext ctx) => [
      GetValuationTool(ctx),
      GetIncomeStatementTool(ctx),
      GetBalanceSheetTool(ctx),
      GetCashFlowTool(ctx),
      GetTopHoldersTool(ctx),
      GetDividendTool(ctx),
    ];
