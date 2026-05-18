package tushare

import (
	"context"
	"sort"
	"strings"
	"time"
)

// HistoryFor 智能路由：按代码后缀决定走 daily / index_daily / fund_daily / fut_daily。
//
// ETF (5xxxxx / 1xxxxx 加 .SH/.SZ) 先试 fund_daily，失败回退 daily。
func (c *Client) HistoryFor(ctx context.Context, symbol string, start, end time.Time) ([]Candle, error) {
	code := NormalizeSymbol(symbol)
	if IsFuture(code) {
		return c.fetchCandles(ctx, "fut_daily", code, start, end,
			"ts_code,trade_date,open,high,low,close,pre_close,vol,amount")
	}
	if IsIndex(code) {
		return c.fetchCandles(ctx, "index_daily", code, start, end,
			"ts_code,trade_date,close,open,high,low,pre_close,change,pct_chg,vol,amount")
	}
	if isLikelyETFCode(code) {
		rows, err := c.fetchCandles(ctx, "fund_daily", code, start, end,
			"ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount")
		if err == nil && len(rows) > 0 {
			return rows, nil
		}
	}
	return c.fetchCandles(ctx, "daily", code, start, end,
		"ts_code,trade_date,open,high,low,close,pre_close,change,pct_chg,vol,amount")
}

// IndexDaily 显式拉指数日线（用于 get_market_snapshot）。
func (c *Client) IndexDaily(ctx context.Context, code string, start, end time.Time) ([]Candle, error) {
	return c.fetchCandles(ctx, "index_daily", code, start, end,
		"ts_code,trade_date,close,open,high,low,pre_close,change,pct_chg,vol,amount")
}

func (c *Client) fetchCandles(
	ctx context.Context,
	api, code string,
	start, end time.Time,
	fields string,
) ([]Candle, error) {
	params := map[string]any{"ts_code": code}
	if !start.IsZero() {
		params["start_date"] = ymd(start)
	}
	if !end.IsZero() {
		params["end_date"] = ymd(end)
	}
	rows, err := c.Query(ctx, api, params, splitFields(fields))
	if err != nil {
		return nil, err
	}
	out := make([]Candle, 0, len(rows))
	for _, r := range rows {
		date := AsString(r["trade_date"])
		if len(date) != 8 {
			continue
		}
		out = append(out, Candle{
			TsCode:    AsString(r["ts_code"]),
			TradeDate: date,
			Open:      AsFloat(r["open"]),
			High:      AsFloat(r["high"]),
			Low:       AsFloat(r["low"]),
			Close:     AsFloat(r["close"]),
			PreClose:  AsFloat(r["pre_close"]),
			Change:    AsFloat(r["change"]),
			PctChg:    AsFloat(r["pct_chg"]),
			Vol:       AsFloat(r["vol"]),
			Amount:    AsFloat(r["amount"]),
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].TradeDate < out[j].TradeDate })
	return out, nil
}

func ymd(t time.Time) string {
	return t.Format("20060102")
}

func splitFields(fields string) []string {
	parts := strings.Split(fields, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func isLikelyETFCode(s string) bool {
	if !IsStock(s) {
		return false
	}
	return strings.HasPrefix(s, "5") || strings.HasPrefix(s, "1")
}
