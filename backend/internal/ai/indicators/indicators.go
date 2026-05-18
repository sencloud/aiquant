// Package indicators 是纯计算量化指标库（无网络 IO，无 Tushare 依赖），
// 输入是日线收盘序列，移植自 lib/services/indicators.dart 同语义函数。
package indicators

import (
	"math"
	"sort"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// ── 基础工具 ────────────────────────────────────────────────────────────

// Closes 提取收盘序列副本。
func Closes(s []tushare.Candle) []float64 {
	out := make([]float64, len(s))
	for i, c := range s {
		out[i] = c.Close
	}
	return out
}

// DailyReturns 日收益率序列；长度 = len(s) - 1。
func DailyReturns(s []tushare.Candle) []float64 {
	out := make([]float64, 0, len(s))
	for i := 1; i < len(s); i++ {
		prev := s[i-1].Close
		if prev == 0 {
			out = append(out, 0)
			continue
		}
		out = append(out, (s[i].Close-prev)/prev)
	}
	return out
}

func mean(xs []float64) float64 {
	if len(xs) == 0 {
		return 0
	}
	sum := 0.0
	for _, x := range xs {
		sum += x
	}
	return sum / float64(len(xs))
}

func variance(xs []float64) float64 {
	if len(xs) < 2 {
		return 0
	}
	m := mean(xs)
	sum := 0.0
	for _, x := range xs {
		d := x - m
		sum += d * d
	}
	return sum / float64(len(xs)-1)
}

func stddev(xs []float64) float64 { return math.Sqrt(variance(xs)) }

// Round 四舍五入到 digits 位。
func Round(v float64, digits int) float64 {
	mul := math.Pow10(digits)
	return math.Round(v*mul) / mul
}

// ── 收益 / 波动 / Sharpe / 最大回撤 ─────────────────────────────────────

// CumulativeReturn 区间累计收益率。
func CumulativeReturn(s []tushare.Candle) float64 {
	if len(s) < 2 {
		return 0
	}
	first := s[0].Close
	if first == 0 {
		return 0
	}
	return (s[len(s)-1].Close - first) / first
}

// AnnualizedReturn 按 252 个交易日折算的年化。
func AnnualizedReturn(s []tushare.Candle) float64 {
	if len(s) < 2 {
		return 0
	}
	r := CumulativeReturn(s)
	years := float64(len(s)-1) / 252.0
	if years <= 0 {
		return 0
	}
	return math.Pow(1+r, 1/years) - 1
}

// AnnualizedVolatility 日收益率标准差 * sqrt(252)。
func AnnualizedVolatility(s []tushare.Candle) float64 {
	rs := DailyReturns(s)
	if len(rs) < 2 {
		return 0
	}
	return stddev(rs) * math.Sqrt(252)
}

// SharpeRatio 年化 Sharpe Ratio。
func SharpeRatio(s []tushare.Candle, riskFree float64) float64 {
	ar := AnnualizedReturn(s)
	av := AnnualizedVolatility(s)
	if av == 0 {
		return 0
	}
	return (ar - riskFree) / av
}

// MaxDrawdownResult 包含最大回撤和峰/谷日期。
type MaxDrawdownResult struct {
	Drawdown   float64
	PeakDate   time.Time
	TroughDate time.Time
	Has        bool
}

// MaxDrawdown 返回区间最大回撤（正数，例 0.235 = -23.5%）。
func MaxDrawdown(s []tushare.Candle) MaxDrawdownResult {
	if len(s) < 2 {
		return MaxDrawdownResult{}
	}
	peak := s[0].Close
	peakDate := parseTradeDate(s[0].TradeDate)
	maxDd := 0.0
	var mddPeak, mddTrough time.Time
	has := false
	for _, c := range s {
		if c.Close > peak {
			peak = c.Close
			peakDate = parseTradeDate(c.TradeDate)
		}
		if peak > 0 {
			dd := (peak - c.Close) / peak
			if dd > maxDd {
				maxDd = dd
				mddPeak = peakDate
				mddTrough = parseTradeDate(c.TradeDate)
				has = true
			}
		}
	}
	return MaxDrawdownResult{
		Drawdown:   Round(maxDd, 4),
		PeakDate:   mddPeak,
		TroughDate: mddTrough,
		Has:        has,
	}
}

// ── 移动平均 / RSI / MACD ───────────────────────────────────────────────

// SMA 简单移动平均；长度不足返回 (0, false)。
func SMA(s []tushare.Candle, n int) (float64, bool) {
	if n <= 0 || len(s) < n {
		return 0, false
	}
	closes := Closes(s)
	tail := closes[len(closes)-n:]
	return Round(mean(tail), 4), true
}

// EMASeries 指数加权移动平均整段序列。
func EMASeries(values []float64, n int) []float64 {
	if len(values) == 0 || n <= 0 {
		return nil
	}
	k := 2.0 / (float64(n) + 1.0)
	out := make([]float64, len(values))
	out[0] = values[0]
	for i := 1; i < len(values); i++ {
		out[i] = values[i]*k + out[i-1]*(1-k)
	}
	return out
}

// RSI 相对强弱指数（默认 14 日）。
func RSI(s []tushare.Candle, period int) (float64, bool) {
	if period <= 0 || len(s) <= period {
		return 0, false
	}
	gains, losses := 0.0, 0.0
	for i := len(s) - period; i < len(s); i++ {
		diff := s[i].Close - s[i-1].Close
		if diff > 0 {
			gains += diff
		} else {
			losses -= diff
		}
	}
	if gains+losses == 0 {
		return 50, true
	}
	avgGain := gains / float64(period)
	avgLoss := losses / float64(period)
	if avgLoss == 0 {
		return 100, true
	}
	rs := avgGain / avgLoss
	return Round(100-100/(1+rs), 2), true
}

// MacdResult 是 MACD 三值与金/死叉信号。
type MacdResult struct {
	Dif   *float64
	Dea   *float64
	Macd  *float64
	Cross string
}

// MACD 计算最后一日的 DIF/DEA/MACD 与是否金叉/死叉。
func MACD(s []tushare.Candle, fast, slow, signal int) MacdResult {
	if len(s) < slow+signal {
		return MacdResult{}
	}
	closes := Closes(s)
	emaFast := EMASeries(closes, fast)
	emaSlow := EMASeries(closes, slow)
	dif := make([]float64, len(closes))
	for i := range closes {
		dif[i] = emaFast[i] - emaSlow[i]
	}
	dea := EMASeries(dif, signal)
	last := len(dif) - 1
	macdVal := 2 * (dif[last] - dea[last])
	cross := ""
	if last >= 1 {
		prevDif, prevDea := dif[last-1], dea[last-1]
		if prevDif <= prevDea && dif[last] > dea[last] {
			cross = "golden"
		}
		if prevDif >= prevDea && dif[last] < dea[last] {
			cross = "death"
		}
	}
	d := Round(dif[last], 4)
	a := Round(dea[last], 4)
	m := Round(macdVal, 4)
	return MacdResult{Dif: &d, Dea: &a, Macd: &m, Cross: cross}
}

// ── Beta / 相关性 ────────────────────────────────────────────────────────

// AlignReturns 把两段日线按日期交集对齐成日收益率序列。
func AlignReturns(a, b []tushare.Candle) (ra, rb []float64) {
	mapA := make(map[string]float64, len(a))
	mapB := make(map[string]float64, len(b))
	for _, c := range a {
		mapA[c.TradeDate] = c.Close
	}
	for _, c := range b {
		mapB[c.TradeDate] = c.Close
	}
	dates := make([]string, 0, len(mapA))
	for d := range mapA {
		if _, ok := mapB[d]; ok {
			dates = append(dates, d)
		}
	}
	sort.Strings(dates)
	if len(dates) < 2 {
		return nil, nil
	}
	for i := 1; i < len(dates); i++ {
		pa0 := mapA[dates[i-1]]
		pb0 := mapB[dates[i-1]]
		if pa0 == 0 || pb0 == 0 {
			continue
		}
		ra = append(ra, (mapA[dates[i]]-pa0)/pa0)
		rb = append(rb, (mapB[dates[i]]-pb0)/pb0)
	}
	return ra, rb
}

// Correlation Pearson 相关系数。
func Correlation(x, y []float64) float64 {
	if len(x) != len(y) || len(x) < 2 {
		return 0
	}
	mx := mean(x)
	my := mean(y)
	num, dx2, dy2 := 0.0, 0.0, 0.0
	for i := range x {
		dx := x[i] - mx
		dy := y[i] - my
		num += dx * dy
		dx2 += dx * dx
		dy2 += dy * dy
	}
	den := math.Sqrt(dx2 * dy2)
	if den == 0 {
		return 0
	}
	return Round(num/den, 4)
}

// BetaResult 包含 beta、年化 alpha、r²。
type BetaResult struct {
	Beta  *float64
	Alpha *float64
	R2    *float64
}

// Beta 估算资产相对基准的 Beta、年化 Alpha 和 R²。
func Beta(asset, benchmark []tushare.Candle, riskFree float64) BetaResult {
	ra, rb := AlignReturns(asset, benchmark)
	if len(ra) < 5 {
		return BetaResult{}
	}
	ma := mean(ra)
	mb := mean(rb)
	cov, varB := 0.0, 0.0
	for i := range ra {
		dx := ra[i] - ma
		dy := rb[i] - mb
		cov += dx * dy
		varB += dy * dy
	}
	cov /= float64(len(ra) - 1)
	varB /= float64(len(ra) - 1)
	if varB == 0 {
		return BetaResult{}
	}
	betaVal := cov / varB
	dailyRf := riskFree / 252.0
	alphaVal := (ma - dailyRf) - betaVal*(mb-dailyRf)
	corr := Correlation(ra, rb)
	b := Round(betaVal, 4)
	a := Round(alphaVal*252, 4)
	r := Round(corr*corr, 4)
	return BetaResult{Beta: &b, Alpha: &a, R2: &r}
}

func parseTradeDate(yyyymmdd string) time.Time {
	if len(yyyymmdd) != 8 {
		return time.Time{}
	}
	t, err := time.Parse("20060102", yyyymmdd)
	if err != nil {
		return time.Time{}
	}
	return t
}
