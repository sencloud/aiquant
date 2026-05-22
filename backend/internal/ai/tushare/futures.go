package tushare

import (
	"context"
	"sort"
	"strings"
)

// FuturesDaily 是 Tushare fut_daily 单行的本地结构（行情字段子集）。
type FuturesDaily struct {
	TsCode    string
	TradeDate string
	PreClose  float64
	PreSettle float64
	Open      float64
	High      float64
	Low       float64
	Close     float64
	Settle    float64
	Vol       float64 // 成交量（手）
	Amount    float64 // 成交额（万元）
	OI        float64 // 持仓量（手）
	OIChg     float64 // 持仓量变化
}

// FutDailyParams 是 FuturesDailyBatch 的过滤项。任一字段为零值即不参与过滤。
type FutDailyParams struct {
	TsCode    string // 单合约（与 TradeDate 二选一）
	TradeDate string // YYYYMMDD（与 TsCode 二选一，常用于"取某日全市场期货行情"）
	StartDate string
	EndDate   string
	Exchange  string // CFFEX / SHFE / DCE / CZCE / INE / GFEX，可选
}

// FuturesDailyBatch 拉期货日线。
//
//   - 按 trade_date 查询时返回该日全交易所合约（建议同时传 exchange 缩窄）；
//   - 按 ts_code + start/end 查询时返回单合约时间序列。
//
// Tushare fut_daily 单次返回上限 ~10000 行，配合 exchange 过滤可覆盖
// 国内全部品种。
func (c *Client) FuturesDailyBatch(ctx context.Context, p FutDailyParams) ([]FuturesDaily, error) {
	params := map[string]any{}
	if strings.TrimSpace(p.TsCode) != "" {
		params["ts_code"] = strings.TrimSpace(p.TsCode)
	}
	if strings.TrimSpace(p.TradeDate) != "" {
		params["trade_date"] = strings.TrimSpace(p.TradeDate)
	}
	if strings.TrimSpace(p.StartDate) != "" {
		params["start_date"] = strings.TrimSpace(p.StartDate)
	}
	if strings.TrimSpace(p.EndDate) != "" {
		params["end_date"] = strings.TrimSpace(p.EndDate)
	}
	if strings.TrimSpace(p.Exchange) != "" {
		params["exchange"] = strings.ToUpper(strings.TrimSpace(p.Exchange))
	}
	fields := []string{
		"ts_code", "trade_date", "pre_close", "pre_settle",
		"open", "high", "low", "close", "settle",
		"vol", "amount", "oi", "oi_chg",
	}
	rows, err := c.Query(ctx, "fut_daily", params, fields)
	if err != nil {
		return nil, err
	}
	out := make([]FuturesDaily, 0, len(rows))
	for _, r := range rows {
		out = append(out, FuturesDaily{
			TsCode:    AsString(r["ts_code"]),
			TradeDate: AsString(r["trade_date"]),
			PreClose:  AsFloat(r["pre_close"]),
			PreSettle: AsFloat(r["pre_settle"]),
			Open:      AsFloat(r["open"]),
			High:      AsFloat(r["high"]),
			Low:       AsFloat(r["low"]),
			Close:     AsFloat(r["close"]),
			Settle:    AsFloat(r["settle"]),
			Vol:       AsFloat(r["vol"]),
			Amount:    AsFloat(r["amount"]),
			OI:        AsFloat(r["oi"]),
			OIChg:     AsFloat(r["oi_chg"]),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].TradeDate != out[j].TradeDate {
			return out[i].TradeDate < out[j].TradeDate
		}
		return out[i].TsCode < out[j].TsCode
	})
	return out, nil
}

// FuturesProduct 用 ts_code 推断品种代码与交易所。
//
// 示例：
//
//	"RB2510.SHF" → ("RB", "SHFE")
//	"IF2506.CFE" → ("IF", "CFFEX")
//	"CU2507.SHF" → ("CU", "SHFE")
//	"SC2507.INE" → ("SC", "INE")
//	"M2509.DCE"  → ("M",  "DCE")
//	"FG506.CZC"  → ("FG", "CZCE")
//
// 规则：合约代码 = 字母品种前缀 + 数字（4 位完整年月，或郑商所 3 位短月）。
// 后缀映射回交易所全称。
func FuturesProduct(tsCode string) (product, exchange string) {
	s := strings.ToUpper(strings.TrimSpace(tsCode))
	if s == "" {
		return "", ""
	}
	dotIdx := strings.LastIndex(s, ".")
	body := s
	suffix := ""
	if dotIdx >= 0 {
		body = s[:dotIdx]
		suffix = s[dotIdx+1:]
	}
	exchange = expandFuturesExchange(suffix)
	for i := 0; i < len(body); i++ {
		if body[i] >= '0' && body[i] <= '9' {
			product = body[:i]
			return
		}
	}
	product = body
	return
}

// FuturesDeliveryMonth 从 ts_code 提取交割月份串（如 "2510" / "506"）。
func FuturesDeliveryMonth(tsCode string) string {
	s := strings.ToUpper(strings.TrimSpace(tsCode))
	if dot := strings.LastIndex(s, "."); dot >= 0 {
		s = s[:dot]
	}
	digits := strings.Builder{}
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			digits.WriteByte(s[i])
		}
	}
	return digits.String()
}

// expandFuturesExchange 把简短后缀转回 fut_basic 用的 exchange 全称。
func expandFuturesExchange(suffix string) string {
	switch strings.ToUpper(suffix) {
	case "SHF", "SHFE":
		return "SHFE"
	case "DCE":
		return "DCE"
	case "CZC", "CZCE":
		return "CZCE"
	case "CFE", "CFFEX":
		return "CFFEX"
	case "INE":
		return "INE"
	case "GFE", "GFEX":
		return "GFEX"
	}
	return ""
}
