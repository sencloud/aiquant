package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// 期权工具集合：
//
//   list_option_contracts  — opt_basic 合约清单（按标的 / 看涨看跌 / 到期日范围）
//   get_option_quote       — opt_daily 单合约多日 OR 多合约单日 行情
//   screen_sell_put        — 面向 Sell Put 策略的"一站式筛选"（推荐 LLM 首选）
//
// 设计原则（与项目其他工具保持一致）：
//   - 严禁兜底；接口失败 / 数据缺失 → 返回 `{"error":"..."}`
//   - 输出全部 markdown 友好的字段名（snake_case）
//   - 数值统一 round 到合理小数位，避免 LLM 在表格里渲染 14 位小数

func registerOptions(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&listOptionContractsTool{c: c})
	r.MustRegister(&getOptionQuoteTool{c: c})
	r.MustRegister(&screenSellPutTool{c: c})
}

// ── 1. list_option_contracts ───────────────────────────────────────────

type listOptionContractsTool struct{ c *tushare.Client }

func (t *listOptionContractsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "list_option_contracts",
		Description: "列出 A 股 ETF 期权合约（opt_basic）。按标的代码（如 510050.SH / 510300.SH / 159919.SZ / 159915.SZ / 588000.SH）、看涨/看跌、到期日范围过滤。返回合约代码、行权价、到期日、剩余天数、合约乘数等。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"underlying": {Type: "string", Description: "标的代码：6 位数字或 ts_code（如 510050 / 510050.SH）。可选；不传则按 exchange 列全交易所期权。"},
				"call_put":   {Type: "string", Enum: []string{"C", "P"}, Description: "认购 C / 认沽 P，可选"},
				"exchange":   {Type: "string", Enum: []string{"SSE", "SZSE"}, Description: "交易所，可选；不传则按 underlying 自动推断"},
				"min_dte":    {Type: "integer", Description: "剩余自然日下限（默认 0）"},
				"max_dte":    {Type: "integer", Description: "剩余自然日上限（默认 90）"},
				"limit":      {Type: "integer", Description: "返回前 N 条（默认 40，最大 200）"},
			},
		},
	}
}

func (t *listOptionContractsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Underlying string `json:"underlying,omitempty"`
		CallPut    string `json:"call_put,omitempty"`
		Exchange   string `json:"exchange,omitempty"`
		MinDTE     int    `json:"min_dte,omitempty"`
		MaxDTE     int    `json:"max_dte,omitempty"`
		Limit      int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	und := tushare.NormalizeSymbol(strings.TrimSpace(in.Underlying))
	ex := strings.ToUpper(strings.TrimSpace(in.Exchange))
	if ex == "" && und != "" {
		ex = tushare.OptionExchangeOf(und)
	}
	if ex == "" {
		return tool.EncodeJSON(map[string]any{"error": "exchange 与 underlying 至少需提供其一（且 underlying 必须能推断出 SSE/SZSE）"}), nil
	}
	cp := strings.ToUpper(strings.TrimSpace(in.CallPut))
	if cp != "" && cp != "C" && cp != "P" {
		return tool.EncodeJSON(map[string]any{"error": "call_put 只能是 C 或 P"}), nil
	}
	maxDTE := in.MaxDTE
	if maxDTE <= 0 {
		maxDTE = 90
	}
	minDTE := in.MinDTE
	if minDTE < 0 {
		minDTE = 0
	}
	limit := clampInt(in.Limit, 1, 200, 40)

	rows, err := t.c.OptionBasic(ctx, tushare.OptBasicParams{
		Exchange: ex,
		OptCode:  und,
		CallPut:  cp,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	today := time.Now()
	out := make([]map[string]any, 0, len(rows))
	for _, oc := range rows {
		dte := daysUntil(today, oc.MaturityDate)
		if dte < minDTE || dte > maxDTE {
			continue
		}
		out = append(out, map[string]any{
			"ts_code":        oc.TsCode,
			"name":           oc.Name,
			"underlying":     oc.OptCode,
			"exchange":       oc.Exchange,
			"call_put":       oc.CallPut,
			"exercise_type":  oc.ExerciseType,
			"exercise_price": oc.ExercisePrice,
			"maturity_date":  formatDate(oc.MaturityDate),
			"list_date":      formatDate(oc.ListDate),
			"dte":            dte,
			"per_unit":       int(oc.PerUnit),
		})
		if len(out) >= limit {
			break
		}
	}
	return tool.EncodeJSON(map[string]any{
		"exchange":   ex,
		"underlying": und,
		"call_put":   cp,
		"min_dte":    minDTE,
		"max_dte":    maxDTE,
		"count":      len(out),
		"contracts":  out,
	}), nil
}

// ── 2. get_option_quote ────────────────────────────────────────────────

type getOptionQuoteTool struct{ c *tushare.Client }

func (t *getOptionQuoteTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_option_quote",
		Description: "查询期权合约日线（opt_daily）。两种用法：① 传 ts_code + days：单合约近 N 日序列（含收盘价、成交量、持仓量）；② 传 trade_date + exchange：取某一天交易所内所有合约（用于横截面筛选）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"ts_code":    {Type: "string", Description: "合约代码（如 10004567.SH），与 trade_date 二选一"},
				"trade_date": {Type: "string", Description: "交易日 YYYY-MM-DD 或 YYYYMMDD"},
				"exchange":   {Type: "string", Enum: []string{"SSE", "SZSE"}, Description: "trade_date 模式下推荐传，减少返回行数"},
				"days":       {Type: "integer", Description: "ts_code 模式下的回溯天数（默认 20，最大 120）"},
			},
		},
	}
}

func (t *getOptionQuoteTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		TsCode    string `json:"ts_code,omitempty"`
		TradeDate string `json:"trade_date,omitempty"`
		Exchange  string `json:"exchange,omitempty"`
		Days      int    `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	ts := strings.TrimSpace(in.TsCode)
	td := normalizeDate(strings.TrimSpace(in.TradeDate))
	ex := strings.ToUpper(strings.TrimSpace(in.Exchange))
	if ts == "" && td == "" {
		return tool.EncodeJSON(map[string]any{"error": "ts_code 与 trade_date 至少需提供其一"}), nil
	}

	if ts != "" {
		days := clampInt(in.Days, 1, 120, 20)
		end := time.Now()
		start := end.AddDate(0, 0, -(days*2 + 30))
		rows, err := t.c.OptionDailyBatch(ctx, tushare.OptDailyParams{
			TsCode:    ts,
			StartDate: ymd(start),
			EndDate:   ymd(end),
		})
		if err != nil {
			return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
		}
		if len(rows) == 0 {
			return tool.EncodeJSON(map[string]any{
				"ts_code": ts,
				"error":   "未拉到任何行情（合约代码可能错误 / 已退市 / 非交易日）",
			}), nil
		}
		tail := tailN(rows, days)
		series := make([]map[string]any, 0, len(tail))
		for _, r := range tail {
			series = append(series, map[string]any{
				"date":   formatDate(r.TradeDate),
				"close":  round(r.Close, 4),
				"settle": round(r.Settle, 4),
				"vol":    int(r.Vol),
				"oi":     int(r.OI),
			})
		}
		last := tail[len(tail)-1]
		return tool.EncodeJSON(map[string]any{
			"ts_code":    ts,
			"days":       len(tail),
			"last_date":  formatDate(last.TradeDate),
			"last_close": round(last.Close, 4),
			"last_vol":   int(last.Vol),
			"last_oi":    int(last.OI),
			"series":     series,
		}), nil
	}

	rows, err := t.c.OptionDailyBatch(ctx, tushare.OptDailyParams{
		TradeDate: td,
		Exchange:  ex,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		out = append(out, map[string]any{
			"ts_code":  r.TsCode,
			"exchange": r.Exchange,
			"close":    round(r.Close, 4),
			"settle":   round(r.Settle, 4),
			"vol":      int(r.Vol),
			"oi":       int(r.OI),
		})
	}
	return tool.EncodeJSON(map[string]any{
		"trade_date": formatDate(td),
		"exchange":   ex,
		"count":      len(out),
		"quotes":     out,
	}), nil
}

// ── 3. screen_sell_put ─────────────────────────────────────────────────

type screenSellPutTool struct{ c *tushare.Client }

func (t *screenSellPutTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "screen_sell_put",
		Description: "面向 Cash-Secured Sell Put 策略的一站式筛选：传入 ETF 标的池，自动拉每只 ETF 最新收盘价 + 在交易的近月认沽合约（opt_basic）+ 当日行情（opt_daily），按虚值幅度 / 流动性过滤后，按静态年化权利金 APY = 权利金*合约乘数/现金担保 × 365/剩余天数 降序，返回 top_n 优选 PUT 合约。同时给出现金担保、被指派接货成本。LLM 写「卖出认沽」策略时优先用此工具，避免多次 list+get 调用。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"underlyings": {Type: "array", Items: &tool.ParameterProperty{Type: "string"},
					Description: "ETF 标的池（默认：510050,510300,159919,510500,159915,588000）。每个元素可以是 6 位数字或 ts_code。"},
				"min_dte":    {Type: "integer", Description: "剩余自然日下限（默认 7）"},
				"max_dte":    {Type: "integer", Description: "剩余自然日上限（默认 45）"},
				"min_otm":   {Type: "number", Description: "虚值幅度下限，例如 0.05 表示 5%（默认 0.05）"},
				"max_otm":   {Type: "number", Description: "虚值幅度上限（默认 0.12）"},
				"min_volume": {Type: "integer", Description: "当日成交量下限（张，默认 100）"},
				"min_oi":     {Type: "integer", Description: "持仓量下限（张，默认 500）"},
				"top_n":      {Type: "integer", Description: "最终返回的 top N（默认 5，最大 20）"},
			},
		},
	}
}

func (t *screenSellPutTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Underlyings []string `json:"underlyings,omitempty"`
		MinDTE      int      `json:"min_dte,omitempty"`
		MaxDTE      int      `json:"max_dte,omitempty"`
		MinOTM      float64  `json:"min_otm,omitempty"`
		MaxOTM      float64  `json:"max_otm,omitempty"`
		MinVolume   int      `json:"min_volume,omitempty"`
		MinOI       int      `json:"min_oi,omitempty"`
		TopN        int      `json:"top_n,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	und := in.Underlyings
	if len(und) == 0 {
		und = []string{"510050.SH", "510300.SH", "159919.SZ", "510500.SH", "159915.SZ", "588000.SH"}
	}
	minDTE := in.MinDTE
	if minDTE <= 0 {
		minDTE = 7
	}
	maxDTE := in.MaxDTE
	if maxDTE <= 0 {
		maxDTE = 45
	}
	if maxDTE < minDTE {
		return tool.EncodeJSON(map[string]any{"error": "max_dte 必须 >= min_dte"}), nil
	}
	minOTM := in.MinOTM
	if minOTM <= 0 {
		minOTM = 0.05
	}
	maxOTM := in.MaxOTM
	if maxOTM <= 0 {
		maxOTM = 0.12
	}
	if maxOTM <= minOTM {
		return tool.EncodeJSON(map[string]any{"error": "max_otm 必须 > min_otm"}), nil
	}
	minVol := in.MinVolume
	if minVol <= 0 {
		minVol = 100
	}
	minOI := in.MinOI
	if minOI <= 0 {
		minOI = 500
	}
	topN := clampInt(in.TopN, 1, 20, 5)

	now := time.Now()
	startWin := now.AddDate(0, 0, -8) // 最近 8 个自然日，足够拿到最新交易日

	// 1) 按 exchange 分组拉每个交易所"最新一天"的全 PUT 行情，缓存到 map[ts_code]OptionDaily
	exchanges := map[string]bool{}
	for _, u := range und {
		ex := tushare.OptionExchangeOf(tushare.NormalizeSymbol(u))
		if ex != "" {
			exchanges[ex] = true
		}
	}
	dailyByCode := map[string]tushare.OptionDaily{}
	latestTradeDate := ""
	for ex := range exchanges {
		// trade_date 留空，让 Tushare 给最近一天；为了减少返回行数，必须传 start_date~end_date
		rows, err := t.c.OptionDailyBatch(ctx, tushare.OptDailyParams{
			Exchange:  ex,
			StartDate: ymd(startWin),
			EndDate:   ymd(now),
		})
		if err != nil {
			return tool.EncodeJSON(map[string]any{
				"error": fmt.Sprintf("opt_daily(%s) 失败: %s", ex, err.Error()),
			}), nil
		}
		// 取每个 ts_code 的最新一行
		for _, r := range rows {
			cur, ok := dailyByCode[r.TsCode]
			if !ok || r.TradeDate > cur.TradeDate {
				dailyByCode[r.TsCode] = r
			}
			if r.TradeDate > latestTradeDate {
				latestTradeDate = r.TradeDate
			}
		}
	}
	if len(dailyByCode) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "opt_daily 全空：可能 token 无 SSE/SZSE 期权权限或当日为节假日"}), nil
	}

	// 2) 按标的逐一处理：拉 ETF 收盘价 + opt_basic(PUT) + 算 APY
	results := []map[string]any{}
	underlyingMeta := []map[string]any{}

	for _, u := range und {
		code := tushare.NormalizeSymbol(u)
		ex := tushare.OptionExchangeOf(code)
		if ex == "" {
			underlyingMeta = append(underlyingMeta, map[string]any{
				"underlying": code, "error": "无法推断 SSE/SZSE",
			})
			continue
		}
		// ETF 最新收盘价
		hist, err := t.c.HistoryFor(ctx, code, startWin, now)
		if err != nil || len(hist) == 0 {
			underlyingMeta = append(underlyingMeta, map[string]any{
				"underlying": code,
				"error":      "ETF 行情拉取失败/为空",
			})
			continue
		}
		spot := hist[len(hist)-1].Close
		spotDate := hist[len(hist)-1].TradeDate

		// PUT 合约清单
		contracts, err := t.c.OptionBasic(ctx, tushare.OptBasicParams{
			Exchange: ex,
			OptCode:  code,
			CallPut:  "P",
		})
		if err != nil {
			underlyingMeta = append(underlyingMeta, map[string]any{
				"underlying": code, "error": "opt_basic 失败: " + err.Error(),
			})
			continue
		}
		uMeta := map[string]any{
			"underlying":     code,
			"exchange":       ex,
			"spot":           round(spot, 4),
			"spot_date":      formatDate(spotDate),
			"put_contracts":  len(contracts),
		}
		underlyingMeta = append(underlyingMeta, uMeta)

		for _, oc := range contracts {
			dte := daysUntil(now, oc.MaturityDate)
			if dte < minDTE || dte > maxDTE {
				continue
			}
			otm := 0.0
			if spot > 0 {
				otm = (spot - oc.ExercisePrice) / spot
			}
			if otm < minOTM || otm > maxOTM {
				continue
			}
			q, ok := dailyByCode[oc.TsCode]
			if !ok || q.Close <= 0 {
				continue
			}
			if int(q.Vol) < minVol || int(q.OI) < minOI {
				continue
			}
			perUnit := oc.PerUnit
			if perUnit <= 0 {
				perUnit = 10000
			}
			cash := oc.ExercisePrice * perUnit
			premium := q.Close * perUnit
			if cash <= 0 {
				continue
			}
			apy := premium / cash * 365.0 / float64(dte)
			effCost := oc.ExercisePrice - q.Close
			results = append(results, map[string]any{
				"ts_code":             oc.TsCode,
				"name":                oc.Name,
				"underlying":          code,
				"exchange":            ex,
				"spot":                round(spot, 4),
				"strike":              oc.ExercisePrice,
				"maturity_date":       formatDate(oc.MaturityDate),
				"dte":                 dte,
				"otm_pct":             round(otm*100, 2),
				"premium":             round(q.Close, 4),
				"vol":                 int(q.Vol),
				"oi":                  int(q.OI),
				"per_unit":            int(perUnit),
				"cash_required":       round(cash, 2),
				"premium_received":    round(premium, 2),
				"apy_pct":             round(apy*100, 2),
				"effective_buy_price": round(effCost, 4),
				"quote_date":          formatDate(q.TradeDate),
			})
		}
	}

	if len(results) == 0 {
		return tool.EncodeJSON(map[string]any{
			"as_of":         formatDate(latestTradeDate),
			"underlyings":   underlyingMeta,
			"filters": map[string]any{
				"min_dte": minDTE, "max_dte": maxDTE,
				"min_otm_pct": round(minOTM*100, 2), "max_otm_pct": round(maxOTM*100, 2),
				"min_volume": minVol, "min_oi": minOI,
			},
			"count":     0,
			"contracts": []any{},
			"hint":      "当前无符合条件合约（可适当放宽 max_otm / min_oi）",
		}), nil
	}

	sort.Slice(results, func(i, j int) bool {
		ai, _ := results[i]["apy_pct"].(float64)
		bj, _ := results[j]["apy_pct"].(float64)
		return ai > bj
	})
	if len(results) > topN {
		results = results[:topN]
	}

	return tool.EncodeJSON(map[string]any{
		"as_of":       formatDate(latestTradeDate),
		"underlyings": underlyingMeta,
		"filters": map[string]any{
			"min_dte": minDTE, "max_dte": maxDTE,
			"min_otm_pct": round(minOTM*100, 2), "max_otm_pct": round(maxOTM*100, 2),
			"min_volume": minVol, "min_oi": minOI,
		},
		"top_n":     topN,
		"count":     len(results),
		"contracts": results,
		"notes": "APY = premium*per_unit/cash_required × 365/dte（静态年化，不含被指派情况下的标的浮亏）；effective_buy_price = strike - premium（被指派后的接货价）。",
	}), nil
}

// ── helpers ────────────────────────────────────────────────────────────

// daysUntil 计算 maturity (YYYYMMDD) 距今天的自然日数（含负数表示已过期）。
func daysUntil(now time.Time, maturity string) int {
	if len(maturity) != 8 {
		return -1
	}
	mt, err := time.ParseInLocation("20060102", maturity, time.Local)
	if err != nil {
		return -1
	}
	return int(mt.Sub(now).Hours()/24) + 1
}

// normalizeDate 接受 "YYYY-MM-DD" / "YYYYMMDD"，统一返回 "YYYYMMDD"。
func normalizeDate(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	if strings.Contains(s, "-") {
		t, err := time.Parse("2006-01-02", s)
		if err == nil {
			return t.Format("20060102")
		}
	}
	return s
}
