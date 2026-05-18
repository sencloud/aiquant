package tools

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// registerFundamental 注册 6 个基本面工具。
func registerFundamental(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&getValuationTool{c: c})
	r.MustRegister(&getIncomeStatementTool{c: c})
	r.MustRegister(&getBalanceSheetTool{c: c})
	r.MustRegister(&getCashFlowTool{c: c})
	r.MustRegister(&getTopHoldersTool{c: c})
	r.MustRegister(&getDividendTool{c: c})
}

func mustStock(code string) (string, bool) {
	if !tushare.IsStock(code) {
		return code, false
	}
	return code, true
}

func sortRowsByEndDateDesc(rows []map[string]any, key string) {
	sort.SliceStable(rows, func(i, j int) bool {
		return tushare.AsString(rows[i][key]) > tushare.AsString(rows[j][key])
	})
}

func takeRows(rows []map[string]any, n int) []map[string]any {
	if n > len(rows) {
		n = len(rows)
	}
	return rows[:n]
}

// ── 9. get_valuation ───────────────────────────────────────────────────

type getValuationTool struct{ c *tushare.Client }

func (t *getValuationTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_valuation",
		Description: "获取一只 A 股最新的 PE/PE_TTM/PB/PS/股息率/换手率/总市值/流通市值。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string", Description: "A 股代码"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getValuationTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "daily_basic 只支持 A 股个股"}), nil
	}
	end := time.Now()
	start := end.AddDate(0, 0, -14)
	rows, err := t.c.Query(ctx, "daily_basic",
		map[string]any{
			"ts_code":    code,
			"start_date": ymd(start),
			"end_date":   ymd(end),
		},
		splitFields("ts_code,trade_date,close,turnover_rate,volume_ratio,pe,pe_ttm,pb,ps,ps_ttm,dv_ratio,dv_ttm,total_share,float_share,total_mv,circ_mv"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无估值数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "trade_date")
	r := rows[0]
	return tool.EncodeJSON(map[string]any{
		"symbol":                    code,
		"trade_date":                r["trade_date"],
		"close":                     r["close"],
		"pe":                        r["pe"],
		"pe_ttm":                    r["pe_ttm"],
		"pb":                        r["pb"],
		"ps":                        r["ps"],
		"ps_ttm":                    r["ps_ttm"],
		"dividend_yield_pct":        r["dv_ratio"],
		"dividend_yield_ttm_pct":    r["dv_ttm"],
		"turnover_rate_pct":         r["turnover_rate"],
		"total_market_cap_yuan_wan": r["total_mv"],
		"float_market_cap_yuan_wan": r["circ_mv"],
	}), nil
}

// ── 10. get_income_statement ───────────────────────────────────────────

type getIncomeStatementTool struct{ c *tushare.Client }

func (t *getIncomeStatementTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_income_statement",
		Description: "获取一只 A 股最近 N 期利润表关键科目（营收/营业成本/营业利润/归母净利润/研发费用/EPS）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":  {Type: "string"},
				"periods": {Type: "integer", Description: "默认 4，最大 12"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getIncomeStatementTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol  string `json:"symbol"`
		Periods int    `json:"periods,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "income 只支持 A 股个股"}), nil
	}
	n := clampInt(in.Periods, 1, 12, 4)
	rows, err := t.c.Query(ctx, "income",
		map[string]any{"ts_code": code},
		splitFields("ts_code,end_date,report_type,revenue,oper_cost,total_cogs,operate_profit,total_profit,n_income_attr_p,basic_eps,diluted_eps,rd_exp"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无利润表数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "end_date")
	tail := takeRows(rows, n)
	out := []map[string]any{}
	for _, r := range tail {
		out = append(out, map[string]any{
			"end_date":                    r["end_date"],
			"revenue_yuan":                r["revenue"],
			"oper_cost_yuan":              r["oper_cost"],
			"operating_profit_yuan":       r["operate_profit"],
			"total_profit_yuan":           r["total_profit"],
			"net_profit_attr_parent_yuan": r["n_income_attr_p"],
			"rd_expense_yuan":             r["rd_exp"],
			"basic_eps":                   r["basic_eps"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":            code,
		"periods":           len(tail),
		"income_statements": out,
	}), nil
}

// ── 11. get_balance_sheet ──────────────────────────────────────────────

type getBalanceSheetTool struct{ c *tushare.Client }

func (t *getBalanceSheetTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_balance_sheet",
		Description: "获取一只 A 股最近 N 期资产负债表关键科目（总资产/总负债/所有者权益/现金/应收/存货/有息负债）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":  {Type: "string"},
				"periods": {Type: "integer", Description: "默认 4"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getBalanceSheetTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol  string `json:"symbol"`
		Periods int    `json:"periods,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "balancesheet 只支持 A 股"}), nil
	}
	n := clampInt(in.Periods, 1, 12, 4)
	rows, err := t.c.Query(ctx, "balancesheet",
		map[string]any{"ts_code": code},
		splitFields("ts_code,end_date,total_assets,total_liab,total_hldr_eqy_inc_min_int,money_cap,accounts_receiv,inventories,st_borr,lt_borr,bond_payable"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无资产负债表数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "end_date")
	tail := takeRows(rows, n)
	out := []map[string]any{}
	for _, r := range tail {
		out = append(out, map[string]any{
			"end_date":                  r["end_date"],
			"total_assets_yuan":         r["total_assets"],
			"total_liabilities_yuan":    r["total_liab"],
			"total_equity_yuan":         r["total_hldr_eqy_inc_min_int"],
			"cash_yuan":                 r["money_cap"],
			"accounts_receivable_yuan":  r["accounts_receiv"],
			"inventories_yuan":          r["inventories"],
			"short_term_borrowing_yuan": r["st_borr"],
			"long_term_borrowing_yuan":  r["lt_borr"],
			"bond_payable_yuan":         r["bond_payable"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":         code,
		"periods":        len(tail),
		"balance_sheets": out,
	}), nil
}

// ── 12. get_cash_flow ──────────────────────────────────────────────────

type getCashFlowTool struct{ c *tushare.Client }

func (t *getCashFlowTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_cash_flow",
		Description: "获取一只 A 股最近 N 期现金流量表（经营/投资/融资活动净现金流、capex、自由现金流）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":  {Type: "string"},
				"periods": {Type: "integer"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getCashFlowTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol  string `json:"symbol"`
		Periods int    `json:"periods,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "cashflow 只支持 A 股"}), nil
	}
	n := clampInt(in.Periods, 1, 12, 4)
	rows, err := t.c.Query(ctx, "cashflow",
		map[string]any{"ts_code": code},
		splitFields("ts_code,end_date,n_cashflow_act,n_cashflow_inv_act,n_cash_flows_fnc_act,c_pay_acq_const_fiolta,free_cashflow"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无现金流量数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "end_date")
	tail := takeRows(rows, n)
	out := []map[string]any{}
	for _, r := range tail {
		out = append(out, map[string]any{
			"end_date":                 r["end_date"],
			"operating_cash_flow_yuan": r["n_cashflow_act"],
			"investing_cash_flow_yuan": r["n_cashflow_inv_act"],
			"financing_cash_flow_yuan": r["n_cash_flows_fnc_act"],
			"capex_yuan":               r["c_pay_acq_const_fiolta"],
			"free_cash_flow_yuan":      r["free_cashflow"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":               code,
		"periods":              len(tail),
		"cash_flow_statements": out,
	}), nil
}

// ── 13. get_top_holders ────────────────────────────────────────────────

type getTopHoldersTool struct{ c *tushare.Client }

func (t *getTopHoldersTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_top_holders",
		Description: "获取一只 A 股最新一期的十大股东名单与持股比例。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getTopHoldersTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "top10_holders 只支持 A 股"}), nil
	}
	rows, err := t.c.Query(ctx, "top10_holders",
		map[string]any{"ts_code": code},
		splitFields("ts_code,end_date,holder_name,hold_amount,hold_ratio"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无十大股东数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "end_date")
	latestEndDate := tushare.AsString(rows[0]["end_date"])
	holders := []map[string]any{}
	for _, r := range rows {
		if tushare.AsString(r["end_date"]) != latestEndDate {
			break
		}
		holders = append(holders, map[string]any{
			"name":      r["holder_name"],
			"shares":    r["hold_amount"],
			"ratio_pct": r["hold_ratio"],
		})
		if len(holders) >= 10 {
			break
		}
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":   code,
		"end_date": latestEndDate,
		"holders":  holders,
	}), nil
}

// ── 14. get_dividend_history ───────────────────────────────────────────

type getDividendTool struct{ c *tushare.Client }

func (t *getDividendTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_dividend_history",
		Description: "获取一只 A 股最近 N 次分红送转记录（每股股利、每股转增、除权除息日）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string"},
				"limit":  {Type: "integer", Description: "默认 10"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getDividendTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Limit  int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	if _, ok := mustStock(code); !ok {
		return tool.EncodeJSON(map[string]any{"error": "dividend 只支持 A 股"}), nil
	}
	limit := clampInt(in.Limit, 1, 30, 10)
	rows, err := t.c.Query(ctx, "dividend",
		map[string]any{"ts_code": code},
		splitFields("ts_code,ann_date,end_date,div_proc,stk_div,stk_bo_rate,stk_co_rate,cash_div,cash_div_tax,record_date,ex_date,pay_date,imp_ann_date"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "无分红记录"}), nil
	}
	sortRowsByEndDateDesc(rows, "end_date")
	tail := takeRows(rows, limit)
	out := []map[string]any{}
	for _, r := range tail {
		out = append(out, map[string]any{
			"end_date":                     r["end_date"],
			"announce_date":                r["ann_date"],
			"ex_dividend_date":             r["ex_date"],
			"pay_date":                     r["pay_date"],
			"cash_dividend_per_share_yuan": r["cash_div"],
			"cash_dividend_after_tax_yuan": r["cash_div_tax"],
			"stock_dividend_per_share":     r["stk_div"],
			"process_status":               r["div_proc"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":  code,
		"count":   len(rows),
		"records": out,
	}), nil
}
