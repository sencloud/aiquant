package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// registerBacktest 注册回测系列工具。
//
// 当前提供：
//   - backtest_etf_rotation：双动量 ETF 组合轮动策略回测，配合「策略之王 →
//     ETF 组合轮动」使用，由 AI 在写当期建议前先看历史 3-5 年的表现。
func registerBacktest(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&backtestEtfRotationTool{c: c})
}

// ── backtest_etf_rotation ─────────────────────────────────────────────

type backtestEtfRotationTool struct{ c *tushare.Client }

func (t *backtestEtfRotationTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "backtest_etf_rotation",
		Description: "回测「双动量 ETF 组合轮动」策略：在给定 ETF 池中按 " +
			"score = w_short*R_short + w_long*R_long 排名，每 rebalance_days 个交易日轮换前 top_n 等权；" +
			"若入选标的 score < 0 则该名额切换到 defensive ETF 防御。" +
			"返回总收益、年化、波动率、Sharpe、最大回撤、月胜率、月度净值表、最终持仓，并与 benchmark 对比。" +
			"专门用于「策略之王 → ETF 组合轮动」场景，AI 在写当期建议前必须先调用以呈现历史业绩。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {
					Type:        "array",
					Description: "候选 ETF 代码列表（6 位或 ts_code，最多 12 只）。默认 7 只主流宽基/红利/避险 ETF。",
					Items:       &tool.ParameterProperty{Type: "string"},
				},
				"start_date": {Type: "string", Description: "回测起始日 YYYY-MM-DD（默认今天前 3 年）"},
				"end_date":   {Type: "string", Description: "回测结束日 YYYY-MM-DD（默认今天）"},
				"rebalance_days": {Type: "integer", Description: "再平衡周期，单位交易日（默认 20）"},
				"short_window":   {Type: "integer", Description: "短动量窗口（默认 20 个交易日）"},
				"long_window":    {Type: "integer", Description: "长动量窗口（默认 60 个交易日）"},
				"w_short":        {Type: "number", Description: "短动量权重（默认 0.6）"},
				"w_long":         {Type: "number", Description: "长动量权重（默认 0.4）"},
				"top_n":          {Type: "integer", Description: "持仓数（默认 3，1–5）"},
				"defensive":      {Type: "string", Description: "防御 ETF（默认 511260 国债 ETF）"},
				"benchmark":      {Type: "string", Description: "基准 ETF（默认 510300 沪深 300）"},
			},
		},
	}
}

type backtestInput struct {
	Symbols       []string `json:"symbols,omitempty"`
	StartDate     string   `json:"start_date,omitempty"`
	EndDate       string   `json:"end_date,omitempty"`
	RebalanceDays int      `json:"rebalance_days,omitempty"`
	ShortWindow   int      `json:"short_window,omitempty"`
	LongWindow    int      `json:"long_window,omitempty"`
	WShort        float64  `json:"w_short,omitempty"`
	WLong         float64  `json:"w_long,omitempty"`
	TopN          int      `json:"top_n,omitempty"`
	Defensive     string   `json:"defensive,omitempty"`
	Benchmark     string   `json:"benchmark,omitempty"`
}

func (t *backtestEtfRotationTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in backtestInput
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}

	cfg := resolveBacktestInput(in)

	// 1) 拉所有 symbols + benchmark 的历史日线，预留 long_window 个交易日的"暖机"。
	allCodes := append([]string{}, cfg.symbols...)
	allCodes = append(allCodes, cfg.benchmark)
	if cfg.defensive != cfg.benchmark && !containsStr(cfg.symbols, cfg.defensive) {
		allCodes = append(allCodes, cfg.defensive)
	}

	// 数据起点 = 用户 start - 2*long_window 个自然日，给动量计算暖机。
	dataStart := cfg.start.AddDate(0, 0, -cfg.longWindow*2-30)
	series := make(map[string][]tushare.Candle, len(allCodes))
	for _, code := range uniqueStr(allCodes) {
		s, err := t.c.HistoryFor(ctx, code, dataStart, cfg.end)
		if err != nil {
			return tool.EncodeJSON(map[string]any{
				"error": fmt.Sprintf("拉取 %s 行情失败：%s", code, err.Error()),
			}), nil
		}
		if len(s) < cfg.longWindow+5 {
			return tool.EncodeJSON(map[string]any{
				"error": fmt.Sprintf("%s 行情数据不足以计算 %d 日动量（实际 %d 个交易日）", code, cfg.longWindow, len(s)),
			}), nil
		}
		series[tushare.NormalizeSymbol(code)] = s
	}

	// 2) 对齐 trade_date：取所有候选 symbols 的交集（benchmark 不强制）。
	symCodes := make([]string, 0, len(cfg.symbols))
	for _, s := range cfg.symbols {
		symCodes = append(symCodes, tushare.NormalizeSymbol(s))
	}
	dates := intersectDates(series, symCodes)
	if len(dates) < cfg.longWindow+cfg.rebalanceDays {
		return tool.EncodeJSON(map[string]any{
			"error": fmt.Sprintf("候选池交集后仅 %d 个交易日，不足以回测（至少需要 %d）", len(dates), cfg.longWindow+cfg.rebalanceDays),
		}), nil
	}

	// 3) 构建每个 code 在每个对齐交易日的收盘价。
	closes := make(map[string][]float64, len(symCodes)+2)
	for _, code := range symCodes {
		closes[code] = pickCloses(series[code], dates)
	}
	// benchmark 用自己的交易日（不强制和池子相同），单独构造价格序列对齐到 dates
	benchCloses := pickClosesAllowFill(series[tushare.NormalizeSymbol(cfg.benchmark)], dates)
	defCloses := pickClosesAllowFill(series[tushare.NormalizeSymbol(cfg.defensive)], dates)

	// 4) 找出策略实际起始 index：≥ long_window 且 ≥ 用户 start_date 中较晚者。
	startIdx := cfg.longWindow
	userStartStr := cfg.start.Format("20060102")
	for i, d := range dates {
		if d >= userStartStr {
			if i > startIdx {
				startIdx = i
			}
			break
		}
	}
	if startIdx >= len(dates)-cfg.rebalanceDays {
		return tool.EncodeJSON(map[string]any{
			"error": "回测窗口过短，请扩大时间范围",
		}), nil
	}

	// 5) 模拟：NAV[startIdx] = 1，每 rebalance_days 触发一次再平衡。
	nav := 1.0
	benchStartClose := benchCloses[startIdx]
	benchNAV := 1.0
	var navSeries []navPoint
	var benchSeries []navPoint
	navSeries = append(navSeries, navPoint{Date: dates[startIdx], NAV: 1.0})
	benchSeries = append(benchSeries, navPoint{Date: dates[startIdx], NAV: 1.0})

	weights := rebalance(closes, dates, startIdx, cfg, defCloses)
	rebCount := 1
	finalWeights := weights

	dailyReturns := make([]float64, 0, len(dates)-startIdx)
	monthlyWins := 0
	monthlyTotal := 0
	monthStartNAV, monthStartBench := 1.0, 1.0
	monthStartDate := dates[startIdx][:6]

	for i := startIdx + 1; i < len(dates); i++ {
		dayRet := 0.0
		for code, w := range weights {
			prev := lookupClose(closes, defCloses, code, i-1)
			cur := lookupClose(closes, defCloses, code, i)
			if prev <= 0 || cur <= 0 {
				continue
			}
			dayRet += w * (cur/prev - 1)
		}
		nav *= 1 + dayRet
		dailyReturns = append(dailyReturns, dayRet)

		if benchCloses[i] > 0 && benchStartClose > 0 {
			benchNAV = benchCloses[i] / benchStartClose
		}

		// 月末（YYYYMM 变化）就记录一个月度点 + 计胜率
		curMonth := dates[i][:6]
		if curMonth != monthStartDate {
			navSeries = append(navSeries, navPoint{
				Date: dates[i-1], NAV: round(nav, 6),
			})
			benchSeries = append(benchSeries, navPoint{
				Date: dates[i-1], NAV: round(benchNAV, 6),
			})
			monthlyTotal++
			stratRet := nav/monthStartNAV - 1
			benchRet := benchNAV/monthStartBench - 1
			if stratRet > benchRet {
				monthlyWins++
			}
			monthStartNAV = nav
			monthStartBench = benchNAV
			monthStartDate = curMonth
		}

		// 触发再平衡：距上次 rebalance 已经 rebalance_days 个交易日
		if (i-startIdx)%cfg.rebalanceDays == 0 {
			weights = rebalance(closes, dates, i, cfg, defCloses)
			finalWeights = weights
			rebCount++
		}
	}
	// 收尾：补上最后一个月度点
	if len(navSeries) == 0 || navSeries[len(navSeries)-1].Date != dates[len(dates)-1] {
		navSeries = append(navSeries, navPoint{Date: dates[len(dates)-1], NAV: round(nav, 6)})
		benchSeries = append(benchSeries, navPoint{Date: dates[len(dates)-1], NAV: round(benchNAV, 6)})
	}

	// 6) 指标统计
	stratStats := backtestStats(dailyReturns, nav)
	benchDaily := benchDailyReturns(benchCloses, startIdx)
	benchStats := backtestStats(benchDaily, benchNAV)

	winRate := 0.0
	if monthlyTotal > 0 {
		winRate = float64(monthlyWins) / float64(monthlyTotal) * 100
	}

	out := map[string]any{
		"strategy":     "ETF 组合轮动（双动量）",
		"period_start": formatDate(dates[startIdx]),
		"period_end":   formatDate(dates[len(dates)-1]),
		"observations": len(dailyReturns) + 1,
		"rebalances":   rebCount,
		"params": map[string]any{
			"symbols":        cfg.symbols,
			"rebalance_days": cfg.rebalanceDays,
			"short_window":   cfg.shortWindow,
			"long_window":    cfg.longWindow,
			"w_short":        cfg.wShort,
			"w_long":         cfg.wLong,
			"top_n":          cfg.topN,
			"defensive":      cfg.defensive,
			"benchmark":      cfg.benchmark,
		},
		"strategy_metrics": map[string]any{
			"total_return_pct":          round(stratStats.totalReturn*100, 3),
			"annualized_return_pct":     round(stratStats.annReturn*100, 3),
			"annualized_volatility_pct": round(stratStats.annVol*100, 3),
			"sharpe":                    round(stratStats.sharpe, 3),
			"max_drawdown_pct":          round(stratStats.maxDrawdown*100, 3),
		},
		"benchmark_metrics": map[string]any{
			"symbol":                    cfg.benchmark,
			"total_return_pct":          round(benchStats.totalReturn*100, 3),
			"annualized_return_pct":     round(benchStats.annReturn*100, 3),
			"annualized_volatility_pct": round(benchStats.annVol*100, 3),
			"sharpe":                    round(benchStats.sharpe, 3),
			"max_drawdown_pct":          round(benchStats.maxDrawdown*100, 3),
		},
		"alpha_pct":          round((stratStats.annReturn-benchStats.annReturn)*100, 3),
		"monthly_win_rate_pct": round(winRate, 2),
		"monthly_nav":          downsampleNav(navSeries, 60),
		"benchmark_monthly_nav": downsampleNav(benchSeries, 60),
		"final_holdings":      formatWeights(finalWeights),
	}
	return tool.EncodeJSON(out), nil
}

// ── 内部工具 ─────────────────────────────────────────────────────────

type resolvedBacktest struct {
	symbols       []string
	start, end    time.Time
	rebalanceDays int
	shortWindow   int
	longWindow    int
	wShort, wLong float64
	topN          int
	defensive     string
	benchmark     string
}

func resolveBacktestInput(in backtestInput) resolvedBacktest {
	now := time.Now()

	syms := make([]string, 0)
	for _, s := range in.Symbols {
		s = strings.TrimSpace(s)
		if s != "" {
			syms = append(syms, s)
		}
	}
	if len(syms) == 0 {
		syms = []string{"510300", "510500", "159915", "588000", "510880", "518880", "511260"}
	}
	if len(syms) > 12 {
		syms = syms[:12]
	}

	start, _ := time.Parse("2006-01-02", in.StartDate)
	if start.IsZero() {
		start = now.AddDate(-3, 0, 0)
	}
	end, _ := time.Parse("2006-01-02", in.EndDate)
	if end.IsZero() || end.After(now) {
		end = now
	}
	if !end.After(start) {
		start = end.AddDate(-1, 0, 0)
	}

	defensive := strings.TrimSpace(in.Defensive)
	if defensive == "" {
		defensive = "511260"
	}
	benchmark := strings.TrimSpace(in.Benchmark)
	if benchmark == "" {
		benchmark = "510300"
	}
	wShort, wLong := in.WShort, in.WLong
	if wShort <= 0 && wLong <= 0 {
		wShort, wLong = 0.6, 0.4
	}
	if wShort < 0 {
		wShort = 0
	}
	if wLong < 0 {
		wLong = 0
	}
	if wShort+wLong == 0 {
		wShort, wLong = 0.6, 0.4
	}

	return resolvedBacktest{
		symbols:       syms,
		start:         start,
		end:           end,
		rebalanceDays: clampInt(in.RebalanceDays, 5, 60, 20),
		shortWindow:   clampInt(in.ShortWindow, 5, 120, 20),
		longWindow:    clampInt(in.LongWindow, 20, 252, 60),
		wShort:        wShort,
		wLong:         wLong,
		topN:          clampInt(in.TopN, 1, 5, 3),
		defensive:     defensive,
		benchmark:     benchmark,
	}
}

// intersectDates 取所有 symbols 在 series 里都出现的 trade_date 并按升序返回。
func intersectDates(series map[string][]tushare.Candle, codes []string) []string {
	if len(codes) == 0 {
		return nil
	}
	count := make(map[string]int)
	for _, code := range codes {
		seen := make(map[string]bool, len(series[code]))
		for _, c := range series[code] {
			if seen[c.TradeDate] {
				continue
			}
			seen[c.TradeDate] = true
			count[c.TradeDate]++
		}
	}
	out := make([]string, 0, len(count))
	for d, n := range count {
		if n == len(codes) {
			out = append(out, d)
		}
	}
	sort.Strings(out)
	return out
}

// pickCloses 取 series 在指定日期列表上的收盘价（要求全部命中）。
func pickCloses(s []tushare.Candle, dates []string) []float64 {
	m := make(map[string]float64, len(s))
	for _, c := range s {
		m[c.TradeDate] = c.Close
	}
	out := make([]float64, len(dates))
	for i, d := range dates {
		out[i] = m[d]
	}
	return out
}

// pickClosesAllowFill 同 pickCloses 但缺失日用前一日补（benchmark/defensive 用）。
func pickClosesAllowFill(s []tushare.Candle, dates []string) []float64 {
	m := make(map[string]float64, len(s))
	for _, c := range s {
		m[c.TradeDate] = c.Close
	}
	out := make([]float64, len(dates))
	var last float64
	for i, d := range dates {
		if v, ok := m[d]; ok && v > 0 {
			last = v
		}
		out[i] = last
	}
	return out
}

func lookupClose(closes map[string][]float64, defCloses []float64, code string, idx int) float64 {
	if v, ok := closes[code]; ok {
		if idx < len(v) {
			return v[idx]
		}
	}
	if idx < len(defCloses) {
		return defCloses[idx]
	}
	return 0
}

// rebalance 在 idx 这一天用过去 short/long 窗口计算动量打分，
// 选 top_n 等权；负动量的名额转给 defensive。
func rebalance(closes map[string][]float64, dates []string, idx int, cfg resolvedBacktest, defCloses []float64) map[string]float64 {
	type scored struct {
		code  string
		score float64
	}
	scores := make([]scored, 0, len(cfg.symbols))
	for _, raw := range cfg.symbols {
		code := tushare.NormalizeSymbol(raw)
		cs, ok := closes[code]
		if !ok || idx >= len(cs) {
			continue
		}
		curPrice := cs[idx]
		if curPrice <= 0 {
			continue
		}
		shortBack := idx - cfg.shortWindow
		longBack := idx - cfg.longWindow
		if shortBack < 0 || longBack < 0 {
			continue
		}
		prevShort := cs[shortBack]
		prevLong := cs[longBack]
		if prevShort <= 0 || prevLong <= 0 {
			continue
		}
		rs := curPrice/prevShort - 1
		rl := curPrice/prevLong - 1
		scores = append(scores, scored{code: code, score: cfg.wShort*rs + cfg.wLong*rl})
	}
	sort.Slice(scores, func(i, j int) bool { return scores[i].score > scores[j].score })

	w := make(map[string]float64)
	defCode := tushare.NormalizeSymbol(cfg.defensive)
	slots := cfg.topN
	if slots > len(scores) {
		slots = len(scores)
	}
	per := 1.0 / float64(cfg.topN)
	defenseTotal := 0.0
	for i := 0; i < slots; i++ {
		if scores[i].score <= 0 {
			defenseTotal += per
			continue
		}
		w[scores[i].code] += per
	}
	// 候选数不足 top_n 时，剩余名额也给防御
	if slots < cfg.topN {
		defenseTotal += per * float64(cfg.topN-slots)
	}
	if defenseTotal > 0 {
		w[defCode] += defenseTotal
	}
	return w
}

// ── 指标统计 ─────────────────────────────────────────────────────────

type backtestStatsResult struct {
	totalReturn float64
	annReturn   float64
	annVol      float64
	sharpe      float64
	maxDrawdown float64
}

func backtestStats(dailyReturns []float64, finalNAV float64) backtestStatsResult {
	res := backtestStatsResult{}
	n := len(dailyReturns)
	if n < 2 {
		return res
	}
	res.totalReturn = finalNAV - 1
	years := float64(n) / 252.0
	if years > 0 {
		res.annReturn = math.Pow(1+res.totalReturn, 1/years) - 1
	}
	mean := 0.0
	for _, r := range dailyReturns {
		mean += r
	}
	mean /= float64(n)
	varSum := 0.0
	for _, r := range dailyReturns {
		d := r - mean
		varSum += d * d
	}
	std := math.Sqrt(varSum / float64(n-1))
	res.annVol = std * math.Sqrt(252)
	if res.annVol > 0 {
		res.sharpe = (res.annReturn - 0.02) / res.annVol
	}

	// 最大回撤：从日收益还原 NAV 序列
	nav := 1.0
	peak := 1.0
	maxDd := 0.0
	for _, r := range dailyReturns {
		nav *= 1 + r
		if nav > peak {
			peak = nav
		}
		dd := (peak - nav) / peak
		if dd > maxDd {
			maxDd = dd
		}
	}
	res.maxDrawdown = maxDd
	return res
}

func benchDailyReturns(benchCloses []float64, startIdx int) []float64 {
	out := make([]float64, 0, len(benchCloses)-startIdx)
	for i := startIdx + 1; i < len(benchCloses); i++ {
		prev := benchCloses[i-1]
		if prev <= 0 {
			out = append(out, 0)
			continue
		}
		out = append(out, benchCloses[i]/prev-1)
	}
	return out
}

// ── 输出辅助 ─────────────────────────────────────────────────────────

type navPoint struct {
	Date string  `json:"date"`
	NAV  float64 `json:"nav"`
}

func downsampleNav(s []navPoint, maxPoints int) []map[string]any {
	if len(s) == 0 {
		return []map[string]any{}
	}
	if len(s) > maxPoints {
		step := (len(s) + maxPoints - 1) / maxPoints
		if step < 1 {
			step = 1
		}
		out := make([]map[string]any, 0, maxPoints+1)
		for i := 0; i < len(s); i += step {
			out = append(out, map[string]any{
				"date": formatDate(s[i].Date),
				"nav":  s[i].NAV,
			})
		}
		last := s[len(s)-1]
		if out[len(out)-1]["date"] != formatDate(last.Date) {
			out = append(out, map[string]any{
				"date": formatDate(last.Date),
				"nav":  last.NAV,
			})
		}
		return out
	}
	out := make([]map[string]any, len(s))
	for i, p := range s {
		out[i] = map[string]any{"date": formatDate(p.Date), "nav": p.NAV}
	}
	return out
}

func formatWeights(weights map[string]float64) []map[string]any {
	type kv struct {
		code   string
		weight float64
	}
	rows := make([]kv, 0, len(weights))
	for k, v := range weights {
		if v > 0 {
			rows = append(rows, kv{code: k, weight: v})
		}
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].weight > rows[j].weight })
	out := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		out = append(out, map[string]any{
			"symbol":     r.code,
			"weight_pct": round(r.weight*100, 2),
		})
	}
	return out
}

// ── 小工具 ───────────────────────────────────────────────────────────

func containsStr(list []string, x string) bool {
	x = tushare.NormalizeSymbol(x)
	for _, v := range list {
		if tushare.NormalizeSymbol(v) == x {
			return true
		}
	}
	return false
}

func uniqueStr(list []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(list))
	for _, v := range list {
		n := tushare.NormalizeSymbol(v)
		if seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}
