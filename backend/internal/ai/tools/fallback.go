package tools

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// 本文件集中放「主源不可达时的兜底取数」。
//
// 起因：东财 push2 / push2delay 在阿里云出口整体不可达（TLS unexpected eof），
// 而美股 / 全球指数 / 外汇 / 涨跌幅榜 / 内盘期货实时原先全依赖东财，表现为
// 「一问就报错」。可用源与兜底策略：
//
//	美股 / 全球指数 / 外盘期货  → 腾讯（已切为主源，见 realtime/tencent_global.go）
//	外汇                        → 腾讯拿不到快照，退 Tushare fx_daily（日线）
//	涨跌幅榜                    → 东财 clist 不可达，退 Tushare daily 自行排序
//	内盘期货实时                → 腾讯/新浪/雪球/金十都不提供，退 Tushare fut_daily
//
// 兜底一律显式标注 source / realtime=false / as_of，让模型知道这是收盘口径，
// 不要拿它当盘中价用。

// latestTradeDate 取最近一个交易日（用于按日期的全市场查询）。
func latestTradeDate(ctx context.Context, tu *tushare.Client) string {
	if tu == nil || !tu.Configured() {
		return ""
	}
	qctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	rows, err := tu.Query(qctx, "trade_cal", map[string]any{
		"exchange":   "SSE",
		"end_date":   time.Now().Format("20060102"),
		"is_open":    "1",
		"start_date": time.Now().AddDate(0, 0, -30).Format("20060102"),
	}, []string{"cal_date"})
	if err != nil || len(rows) == 0 {
		return ""
	}
	best := ""
	for _, r := range rows {
		s := toStr(r["cal_date"])
		if s > best {
			best = s
		}
	}
	return best
}

// futuresDailyFallback 用 Tushare 日线给内盘期货兜底，返回最近一根日线。
func futuresDailyFallback(
	ctx context.Context, tu *tushare.Client, tsCode string,
) (map[string]any, error) {
	if tu == nil || !tu.Configured() {
		return nil, fmt.Errorf("Tushare 未配置，无法兜底")
	}
	qctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	rows, err := tu.Query(qctx, "fut_daily", map[string]any{"ts_code": tsCode},
		[]string{"trade_date", "pre_close", "pre_settle", "open", "high", "low",
			"close", "change1", "change2", "vol", "amount", "oi"})
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("Tushare 无 %s 的日线数据", tsCode)
	}
	sort.Slice(rows, func(i, j int) bool {
		return toStr(rows[i]["trade_date"]) > toStr(rows[j]["trade_date"])
	})
	r := rows[0]
	return map[string]any{
		"ts_code":    tsCode,
		"trade_date": toStr(r["trade_date"]),
		"open":       toFloat(r["open"]),
		"high":       toFloat(r["high"]),
		"low":        toFloat(r["low"]),
		"last":       toFloat(r["close"]),
		"pre_settle": toFloat(r["pre_settle"]),
		"change":     toFloat(r["change1"]),
		"pct_chg":    toFloat(r["change2"]),
		"volume":     toFloat(r["vol"]),
		"amount":     toFloat(r["amount"]),
		"oi":         toFloat(r["oi"]),
		"source":     "tushare_fut_daily",
		"realtime":   false,
	}, nil
}

// forexDailyFallback 用 Tushare fx_daily 给外汇兜底。
func forexDailyFallback(
	ctx context.Context, tu *tushare.Client, pair string,
) (map[string]any, error) {
	if tu == nil || !tu.Configured() {
		return nil, fmt.Errorf("Tushare 未配置，无法兜底")
	}
	tsCode := forexTushareCode(pair)
	if tsCode == "" {
		return nil, fmt.Errorf("不支持的外汇品种: %s", pair)
	}
	qctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	rows, err := tu.Query(qctx, "fx_daily", map[string]any{
		"ts_code":    tsCode,
		"start_date": time.Now().AddDate(0, 0, -20).Format("20060102"),
		"end_date":   time.Now().Format("20060102"),
	}, []string{"ts_code", "trade_date", "bid_open", "bid_close", "bid_high", "bid_low", "tick_qty"})
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("Tushare 无 %s 的日线数据", tsCode)
	}
	sort.Slice(rows, func(i, j int) bool {
		return toStr(rows[i]["trade_date"]) > toStr(rows[j]["trade_date"])
	})
	r := rows[0]
	last := toFloat(r["bid_close"])
	prev := 0.0
	if len(rows) > 1 {
		prev = toFloat(rows[1]["bid_close"])
	}
	out := map[string]any{
		"symbol":     pair,
		"ts_code":    tsCode,
		"trade_date": toStr(r["trade_date"]),
		"last":       last,
		"open":       toFloat(r["bid_open"]),
		"high":       toFloat(r["bid_high"]),
		"low":        toFloat(r["bid_low"]),
		"source":     "tushare_fx_daily",
		"realtime":   false,
	}
	if prev > 0 {
		out["pre_close"] = prev
		out["pct_chg"] = (last/prev - 1) * 100
	}
	return out, nil
}

// forexTushareCode 把常见货币对映射到 Tushare fx_daily 的 ts_code（FXCM）。
func forexTushareCode(pair string) string {
	switch toUpperTrim(pair) {
	case "USDCNH", "美元离岸人民币", "离岸人民币":
		return "USDCNH.FXCM"
	case "USDCNY", "USDCNYC", "人民币中间价":
		return "USDCNH.FXCM" // Tushare 无在岸中间价，用离岸近似
	case "EURUSD", "欧元美元":
		return "EURUSD.FXCM"
	case "USDJPY", "美元日元":
		return "USDJPY.FXCM"
	case "GBPUSD", "英镑美元":
		return "GBPUSD.FXCM"
	case "AUDUSD", "澳元美元":
		return "AUDUSD.FXCM"
	case "USDCAD", "美元加元":
		return "USDCAD.FXCM"
	case "USDCHF", "美元瑞郎":
		return "USDCHF.FXCM"
	case "UDI", "美元指数", "DXY":
		return "UDI.FXCM"
	}
	return ""
}

// topMoversFallback 用 Tushare daily 自行算涨跌幅榜（东财 clist 不可达时的兜底）。
func topMoversFallback(
	ctx context.Context, tu *tushare.Client, direction string, limit int,
) (map[string]any, error) {
	if tu == nil || !tu.Configured() {
		return nil, fmt.Errorf("Tushare 未配置，无法兜底")
	}
	date := latestTradeDate(ctx, tu)
	if date == "" {
		return nil, fmt.Errorf("取不到最近交易日")
	}
	qctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	rows, err := tu.Query(qctx, "daily", map[string]any{"trade_date": date},
		[]string{"ts_code", "name", "close", "pct_chg", "amount", "vol"})
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("Tushare 无 %s 的日线数据", date)
	}
	sort.Slice(rows, func(i, j int) bool {
		a, b := toFloat(rows[i]["pct_chg"]), toFloat(rows[j]["pct_chg"])
		if toUpperTrim(direction) == "down" {
			return a < b
		}
		return a > b
	})
	if limit > len(rows) {
		limit = len(rows)
	}
	movers := make([]map[string]any, 0, limit)
	for _, r := range rows[:limit] {
		movers = append(movers, map[string]any{
			"ts_code": toStr(r["ts_code"]),
			"name":    toStr(r["name"]),
			"last":    toFloat(r["close"]),
			"pct_chg": toFloat(r["pct_chg"]),
			"amount":  toFloat(r["amount"]),
			"volume":  toFloat(r["vol"]),
		})
	}
	return map[string]any{
		"as_of":     date,
		"direction": toUpperTrim(direction),
		"count":     len(movers),
		"movers":    movers,
		"source":    "tushare_daily",
		"realtime":  false,
		"notice":    fmt.Sprintf("实时榜单接口在服务器出口不可达，这里是 %s 收盘后的口径", date),
	}, nil
}

// ── 小工具 ──────────────────────────────────────────────────────────────

func toStr(v any) string {
	if v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	}
	return fmt.Sprintf("%v", v)
}

func toFloat(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int64:
		return float64(x)
	case int:
		return float64(x)
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
}

func toUpperTrim(s string) string {
	return strings.ToUpper(strings.TrimSpace(s))
}
