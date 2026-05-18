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

// registerMacro 注册 4 个宏观资金工具。
func registerMacro(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&getIndexComponentsTool{c: c})
	r.MustRegister(&getMarginTradingTool{c: c})
	r.MustRegister(&getNorthboundFlowTool{c: c})
	r.MustRegister(&getIndustryMoneyFlowTool{c: c})
}

// ── 15. get_index_components ───────────────────────────────────────────

type getIndexComponentsTool struct{ c *tushare.Client }

func (t *getIndexComponentsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_index_components",
		Description: "获取 A 股宽基指数（沪深300/中证500/上证50/科创50/中证1000）的成分股与权重。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"index_code": {Type: "string", Description: "指数 ts_code"},
				"top":        {Type: "integer", Description: "权重前 N（默认 30，最大 100）"},
			},
			Required: []string{"index_code"},
		},
	}
}

func (t *getIndexComponentsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		IndexCode string `json:"index_code"`
		Top       int    `json:"top,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.IndexCode))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "index_code 必填"}), nil
	}
	top := clampInt(in.Top, 1, 100, 30)
	end := time.Now()
	start := end.AddDate(0, 0, -60)
	rows, err := t.c.Query(ctx, "index_weight",
		map[string]any{
			"index_code": code,
			"start_date": ymd(start),
			"end_date":   ymd(end),
		},
		splitFields("index_code,con_code,trade_date,weight"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"index_code": code, "error": "无成分股权重数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "trade_date")
	latestDate := tushare.AsString(rows[0]["trade_date"])
	latest := []map[string]any{}
	for _, r := range rows {
		if tushare.AsString(r["trade_date"]) == latestDate {
			latest = append(latest, r)
		}
	}
	sort.SliceStable(latest, func(i, j int) bool {
		return tushare.AsFloat(latest[i]["weight"]) > tushare.AsFloat(latest[j]["weight"])
	})
	out := []map[string]any{}
	for _, r := range takeRows(latest, top) {
		out = append(out, map[string]any{
			"ts_code":    r["con_code"],
			"weight_pct": r["weight"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"index_code":     code,
		"as_of":          latestDate,
		"count_total":    len(latest),
		"top_components": out,
	}), nil
}

// ── 16. get_margin_trading ─────────────────────────────────────────────

type getMarginTradingTool struct{ c *tushare.Client }

func (t *getMarginTradingTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_margin_trading",
		Description: "获取最近 N 天 A 股市场两融余额（融资余额、融券余额、合计），用于判断杠杆资金情绪。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"days":     {Type: "integer", Description: "回看交易日数（默认 10，最大 60）"},
				"exchange": {Type: "string", Enum: []string{"SSE", "SZSE", "BSE", "ALL"}, Description: "交易所（默认 ALL）"},
			},
		},
	}
}

func (t *getMarginTradingTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Days     int    `json:"days,omitempty"`
		Exchange string `json:"exchange,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	days := clampInt(in.Days, 1, 60, 10)
	exchange := strings.ToUpper(strings.TrimSpace(in.Exchange))
	if exchange == "" {
		exchange = "ALL"
	}
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 7))
	params := map[string]any{
		"start_date": ymd(start),
		"end_date":   ymd(end),
	}
	if exchange != "ALL" {
		params["exchange_id"] = exchange
	}
	rows, err := t.c.Query(ctx, "margin", params,
		splitFields("trade_date,exchange_id,rzye,rqye,rzrqye,rzmre,rzche,rqmcl,rqchl"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "无两融数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "trade_date")
	tail := takeRows(rows, days)
	out := []map[string]any{}
	for _, r := range tail {
		out = append(out, map[string]any{
			"trade_date":                  r["trade_date"],
			"exchange":                    r["exchange_id"],
			"financing_balance_yuan":      r["rzye"],
			"short_selling_balance_yuan":  r["rqye"],
			"total_margin_balance_yuan":   r["rzrqye"],
			"financing_buy_amount_yuan":   r["rzmre"],
			"financing_repay_amount_yuan": r["rzche"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"days":     len(tail),
		"exchange": exchange,
		"records":  out,
	}), nil
}

// ── 17. get_northbound_flow ────────────────────────────────────────────

type getNorthboundFlowTool struct{ c *tushare.Client }

func (t *getNorthboundFlowTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_northbound_flow",
		Description: "获取最近 N 天沪深股通北向资金净买入金额（外资风向标）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"days": {Type: "integer", Description: "回看交易日数（默认 10，最大 60）"},
			},
		},
	}
}

func (t *getNorthboundFlowTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Days int `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	days := clampInt(in.Days, 1, 60, 10)
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 7))
	rows, err := t.c.Query(ctx, "moneyflow_hsgt",
		map[string]any{
			"start_date": ymd(start),
			"end_date":   ymd(end),
		},
		splitFields("trade_date,ggt_ss,ggt_sz,hgt,sgt,north_money,south_money"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "无沪深港通数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "trade_date")
	tail := takeRows(rows, days)
	sumNorth := 0.0
	out := []map[string]any{}
	for _, r := range tail {
		sumNorth += tushare.AsFloat(r["north_money"])
		out = append(out, map[string]any{
			"trade_date":                r["trade_date"],
			"north_inflow_yuan_wan":     r["north_money"],
			"south_inflow_hkd_wan":      r["south_money"],
			"shanghai_connect_yuan_wan": r["hgt"],
			"shenzhen_connect_yuan_wan": r["sgt"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"days":                             len(tail),
		"cumulative_north_inflow_yuan_wan": round(sumNorth, 2),
		"records":                          out,
	}), nil
}

// ── 18. get_industry_money_flow ────────────────────────────────────────

type getIndustryMoneyFlowTool struct{ c *tushare.Client }

func (t *getIndustryMoneyFlowTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_industry_money_flow",
		Description: "获取最近一日 A 股行业（东财分类）资金净流入排名。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"top": {Type: "integer", Description: "前 N（默认 15，最大 50）"},
			},
		},
	}
}

func (t *getIndustryMoneyFlowTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Top int `json:"top,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	top := clampInt(in.Top, 1, 50, 15)
	end := time.Now()
	start := end.AddDate(0, 0, -7)
	rows, err := t.c.Query(ctx, "moneyflow_ind_dc",
		map[string]any{
			"start_date": ymd(start),
			"end_date":   ymd(end),
		},
		splitFields("trade_date,name,pct_change,close,net_amount,buy_elg_amount,buy_lg_amount,buy_md_amount,buy_sm_amount"),
	)
	if err != nil {
		return "", err
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "无行业资金流数据"}), nil
	}
	sortRowsByEndDateDesc(rows, "trade_date")
	latestDate := tushare.AsString(rows[0]["trade_date"])
	latest := []map[string]any{}
	for _, r := range rows {
		if tushare.AsString(r["trade_date"]) == latestDate {
			latest = append(latest, r)
		}
	}
	sort.SliceStable(latest, func(i, j int) bool {
		return tushare.AsFloat(latest[i]["net_amount"]) > tushare.AsFloat(latest[j]["net_amount"])
	})
	out := []map[string]any{}
	for _, r := range takeRows(latest, top) {
		out = append(out, map[string]any{
			"industry":            r["name"],
			"net_inflow_yuan_wan": r["net_amount"],
			"pct_change":          r["pct_change"],
			"close_index":         r["close"],
			"extra_large_inflow":  r["buy_elg_amount"],
			"large_inflow":        r["buy_lg_amount"],
		})
	}
	return tool.EncodeJSON(map[string]any{
		"trade_date": latestDate,
		"industries": out,
	}), nil
}
