package tools

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/indicators"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// registerQuant 注册 8 个量化工具。
func registerQuant(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&calcReturnsTool{c: c})
	r.MustRegister(&calcSharpeTool{c: c})
	r.MustRegister(&calcMaxDrawdownTool{c: c})
	r.MustRegister(&calcCorrelationTool{c: c})
	r.MustRegister(&calcBetaTool{c: c})
	r.MustRegister(&calcMovingAverageTool{c: c})
	r.MustRegister(&calcRsiTool{c: c})
	r.MustRegister(&calcMacdTool{c: c})
}

func loadSeries(ctx context.Context, c *tushare.Client, code string, days int) ([]tushare.Candle, error) {
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 30))
	all, err := c.HistoryFor(ctx, code, start, end)
	if err != nil {
		return nil, err
	}
	if len(all) > days {
		return all[len(all)-days:], nil
	}
	return all, nil
}

// ── 1. calc_returns ────────────────────────────────────────────────────

type calcReturnsTool struct{ c *tushare.Client }

func (t *calcReturnsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_returns",
		Description: "计算单一标的最近 N 个交易日的累计收益率、年化收益率、年化波动率。回答\"茅台过去一年涨了多少 / 波动多大\"等问题时使用。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string", Description: "标的代码（6位数字或 ts_code）"},
				"days":   {Type: "integer", Description: "回看交易日数（默认 252，最大 750）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcReturnsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Days   int    `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	days := clampInt(in.Days, 20, 750, 252)
	series, err := loadSeries(ctx, t.c, code, days)
	if err != nil {
		return "", err
	}
	if len(series) < 5 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "行情数据不足以计算"}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":                    code,
		"period_start":              formatDate(series[0].TradeDate),
		"period_end":                formatDate(series[len(series)-1].TradeDate),
		"observations":              len(series),
		"cumulative_return_pct":     indicators.Round(indicators.CumulativeReturn(series)*100, 3),
		"annualized_return_pct":     indicators.Round(indicators.AnnualizedReturn(series)*100, 3),
		"annualized_volatility_pct": indicators.Round(indicators.AnnualizedVolatility(series)*100, 3),
	}), nil
}

// ── 2. calc_sharpe ─────────────────────────────────────────────────────

type calcSharpeTool struct{ c *tushare.Client }

func (t *calcSharpeTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_sharpe",
		Description: "计算单一标的的年化 Sharpe Ratio（默认无风险利率 2%）。用于回答风险调整后的回报问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":         {Type: "string"},
				"days":           {Type: "integer", Description: "回看交易日数（默认 252）"},
				"risk_free_rate": {Type: "number", Description: "年化无风险利率（默认 0.02）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcSharpeTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol       string  `json:"symbol"`
		Days         int     `json:"days,omitempty"`
		RiskFreeRate float64 `json:"risk_free_rate,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	days := clampInt(in.Days, 20, 750, 252)
	rf := in.RiskFreeRate
	if rf == 0 {
		rf = 0.02
	}
	series, err := loadSeries(ctx, t.c, code, days)
	if err != nil {
		return "", err
	}
	if len(series) < 20 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "样本不足以计算 Sharpe"}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":                    code,
		"observations":              len(series),
		"risk_free_rate":            rf,
		"annualized_return_pct":     indicators.Round(indicators.AnnualizedReturn(series)*100, 3),
		"annualized_volatility_pct": indicators.Round(indicators.AnnualizedVolatility(series)*100, 3),
		"sharpe_ratio":              indicators.Round(indicators.SharpeRatio(series, rf), 3),
	}), nil
}

// ── 3. calc_max_drawdown ───────────────────────────────────────────────

type calcMaxDrawdownTool struct{ c *tushare.Client }

func (t *calcMaxDrawdownTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_max_drawdown",
		Description: "计算单一标的回看期内的最大回撤和对应峰值/谷底日期。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string"},
				"days":   {Type: "integer", Description: "回看交易日数（默认 252）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcMaxDrawdownTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Days   int    `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	days := clampInt(in.Days, 20, 1500, 252)
	series, err := loadSeries(ctx, t.c, code, days)
	if err != nil {
		return "", err
	}
	if len(series) < 5 {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "样本不足"}), nil
	}
	r := indicators.MaxDrawdown(series)
	out := map[string]any{
		"symbol":           code,
		"observations":     len(series),
		"max_drawdown_pct": indicators.Round(r.Drawdown*100, 3),
	}
	if r.Has {
		out["peak_date"] = r.PeakDate.Format("2006-01-02")
		out["trough_date"] = r.TroughDate.Format("2006-01-02")
	}
	return tool.EncodeJSON(out), nil
}

// ── 4. calc_correlation ────────────────────────────────────────────────

type calcCorrelationTool struct{ c *tushare.Client }

func (t *calcCorrelationTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_correlation",
		Description: "计算多个标的（最多 6 个）日收益率两两之间的 Pearson 相关系数。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {Type: "array", Items: &tool.ParameterProperty{Type: "string"}, Description: "2~6 个标的代码"},
				"days":    {Type: "integer", Description: "回看交易日数（默认 120）"},
			},
			Required: []string{"symbols"},
		},
	}
}

func (t *calcCorrelationTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbols []string `json:"symbols"`
		Days    int      `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	syms := []string{}
	for _, s := range in.Symbols {
		s = tushare.NormalizeSymbol(strings.TrimSpace(s))
		if s != "" {
			syms = append(syms, s)
		}
	}
	if len(syms) < 2 {
		return tool.EncodeJSON(map[string]any{"error": "至少 2 个标的"}), nil
	}
	if len(syms) > 6 {
		return tool.EncodeJSON(map[string]any{"error": "最多 6 个标的"}), nil
	}
	days := clampInt(in.Days, 20, 500, 120)
	series := make(map[string][]tushare.Candle, len(syms))
	for _, s := range syms {
		v, err := loadSeries(ctx, t.c, s, days)
		if err != nil {
			series[s] = nil
		} else {
			series[s] = v
		}
	}
	matrix := make(map[string]map[string]float64, len(syms))
	for _, a := range syms {
		matrix[a] = make(map[string]float64, len(syms))
		for _, b := range syms {
			if a == b {
				matrix[a][b] = 1
				continue
			}
			if len(series[a]) == 0 || len(series[b]) == 0 {
				matrix[a][b] = 0
				continue
			}
			ra, rb := indicators.AlignReturns(series[a], series[b])
			matrix[a][b] = indicators.Correlation(ra, rb)
		}
	}
	return tool.EncodeJSON(map[string]any{
		"days":    days,
		"symbols": syms,
		"matrix":  matrix,
	}), nil
}

// ── 5. calc_beta ───────────────────────────────────────────────────────

type calcBetaTool struct{ c *tushare.Client }

func (t *calcBetaTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_beta",
		Description: "计算单一 A 股标的相对沪深 300（默认基准）的 Beta、年化 Alpha 和 R²。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":    {Type: "string"},
				"benchmark": {Type: "string", Description: "基准代码（默认 000300.SH）"},
				"days":      {Type: "integer", Description: "回看交易日数（默认 252）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcBetaTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol    string `json:"symbol"`
		Benchmark string `json:"benchmark,omitempty"`
		Days      int    `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	bm := strings.TrimSpace(in.Benchmark)
	if bm == "" {
		bm = "000300.SH"
	}
	bm = tushare.NormalizeSymbol(bm)
	days := clampInt(in.Days, 20, 1000, 252)
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 30))
	asset, err := t.c.HistoryFor(ctx, code, start, end)
	if err != nil {
		return "", err
	}
	bench, err := t.c.HistoryFor(ctx, bm, start, end)
	if err != nil {
		return "", err
	}
	if len(asset) < 20 || len(bench) < 20 {
		return tool.EncodeJSON(map[string]any{"error": "样本不足以估算 Beta"}), nil
	}
	r := indicators.Beta(asset, bench, 0.02)
	obs := len(asset)
	if len(bench) < obs {
		obs = len(bench)
	}
	out := map[string]any{
		"symbol":       code,
		"benchmark":    bm,
		"observations": obs,
	}
	if r.Beta != nil {
		out["beta"] = *r.Beta
	}
	if r.Alpha != nil {
		out["annualized_alpha_pct"] = indicators.Round(*r.Alpha*100, 3)
	}
	if r.R2 != nil {
		out["r_squared"] = *r.R2
	}
	return tool.EncodeJSON(out), nil
}

// ── 6. calc_moving_average ─────────────────────────────────────────────

type calcMovingAverageTool struct{ c *tushare.Client }

func (t *calcMovingAverageTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_moving_average",
		Description: "计算单一标的的 MA5/MA10/MA20/MA60/MA120，并判断多/空头排列。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol":  {Type: "string"},
				"periods": {Type: "array", Items: &tool.ParameterProperty{Type: "integer"}, Description: "自定义周期数组（默认 [5,10,20,60,120]）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcMovingAverageTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol  string `json:"symbol"`
		Periods []int  `json:"periods,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	periods := []int{}
	for _, p := range in.Periods {
		if p > 0 && p <= 250 {
			periods = append(periods, p)
		}
	}
	if len(periods) == 0 {
		periods = []int{5, 10, 20, 60, 120}
	}
	maxN := 0
	for _, p := range periods {
		if p > maxN {
			maxN = p
		}
	}
	series, err := loadSeries(ctx, t.c, code, maxN+30)
	if err != nil {
		return "", err
	}
	if len(series) < maxN {
		return tool.EncodeJSON(map[string]any{"symbol": code, "error": "行情样本不足以计算 MA"}), nil
	}
	maOut := map[string]any{}
	values := make([]float64, len(periods))
	allValid := true
	sortedPeriods := append([]int{}, periods...)
	sort.Ints(sortedPeriods)
	for i, n := range sortedPeriods {
		v, ok := indicators.SMA(series, n)
		key := "MA" + itoa(n)
		if !ok {
			maOut[key] = nil
			allValid = false
		} else {
			maOut[key] = v
			values[i] = v
		}
	}
	alignment := ""
	if allValid {
		bullish, bearish := true, true
		for i := 0; i+1 < len(values); i++ {
			if !(values[i] > values[i+1]) {
				bullish = false
			}
			if !(values[i] < values[i+1]) {
				bearish = false
			}
		}
		switch {
		case bullish:
			alignment = "bullish"
		case bearish:
			alignment = "bearish"
		default:
			alignment = "mixed"
		}
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":     code,
		"last_date":  formatDate(series[len(series)-1].TradeDate),
		"last_close": series[len(series)-1].Close,
		"ma":         maOut,
		"alignment":  alignment,
	}), nil
}

// ── 7. calc_rsi ────────────────────────────────────────────────────────

type calcRsiTool struct{ c *tushare.Client }

func (t *calcRsiTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_rsi",
		Description: "计算 RSI（相对强弱指数）。RSI > 70 超买，< 30 超卖。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string"},
				"period": {Type: "integer", Description: "周期（默认 14）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcRsiTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Period int    `json:"period,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	period := clampInt(in.Period, 2, 60, 14)
	series, err := loadSeries(ctx, t.c, code, period*4+20)
	if err != nil {
		return "", err
	}
	rsi, ok := indicators.RSI(series, period)
	out := map[string]any{
		"symbol": code,
		"period": period,
	}
	if len(series) > 0 {
		out["last_date"] = formatDate(series[len(series)-1].TradeDate)
	}
	if ok {
		out["rsi"] = rsi
		switch {
		case rsi > 70:
			out["signal"] = "overbought"
		case rsi < 30:
			out["signal"] = "oversold"
		default:
			out["signal"] = "neutral"
		}
	}
	return tool.EncodeJSON(out), nil
}

// ── 8. calc_macd ───────────────────────────────────────────────────────

type calcMacdTool struct{ c *tushare.Client }

func (t *calcMacdTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "calc_macd",
		Description: "计算 MACD 三值（DIF/DEA/MACD）并标注是否金叉/死叉。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string"},
				"fast":   {Type: "integer", Description: "快线（默认 12）"},
				"slow":   {Type: "integer", Description: "慢线（默认 26）"},
				"signal": {Type: "integer", Description: "信号线（默认 9）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *calcMacdTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Fast   int    `json:"fast,omitempty"`
		Slow   int    `json:"slow,omitempty"`
		Signal int    `json:"signal,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	code := tushare.NormalizeSymbol(strings.TrimSpace(in.Symbol))
	if code == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	fast := clampInt(in.Fast, 3, 60, 12)
	slow := clampInt(in.Slow, 5, 100, 26)
	signal := clampInt(in.Signal, 2, 30, 9)
	series, err := loadSeries(ctx, t.c, code, slow*4+signal+30)
	if err != nil {
		return "", err
	}
	r := indicators.MACD(series, fast, slow, signal)
	out := map[string]any{
		"symbol": code,
		"fast":   fast,
		"slow":   slow,
		"signal": signal,
	}
	if len(series) > 0 {
		out["last_date"] = formatDate(series[len(series)-1].TradeDate)
	}
	if r.Dif != nil {
		out["dif"] = *r.Dif
	}
	if r.Dea != nil {
		out["dea"] = *r.Dea
	}
	if r.Macd != nil {
		out["macd_bar"] = *r.Macd
	}
	if r.Cross != "" {
		out["cross"] = r.Cross
	}
	return tool.EncodeJSON(out), nil
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	buf := [20]byte{}
	pos := len(buf)
	for n > 0 {
		pos--
		buf[pos] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}
