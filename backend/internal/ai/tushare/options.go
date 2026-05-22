package tushare

import (
	"context"
	"sort"
	"strings"
)

// OptionContract 是 Tushare opt_basic 单行的本地结构。
//
// 仅保留我们写期权工具会用到的字段；不暴露原始接口的 list_price 等冷门字段，
// 避免 LLM 看到太多噪音字段。
type OptionContract struct {
	TsCode        string  // 合约代码（如 "10004567.SH"）
	Exchange      string  // SSE / SZSE / CFFEX / SHFE / DCE / CZCE
	Name          string  // 合约名（如 "50ETF沽3月3000"）
	OptCode       string  // 标的代码（如 "510050.SH"）
	CallPut       string  // "C" / "P"
	ExerciseType  string  // "E"(欧式) / "A"(美式)
	ExercisePrice float64 // 行权价
	SMonth        string  // 合约月份（"YYYYMM"）
	MaturityDate  string  // 到期日 YYYYMMDD
	ListDate      string  // 上市日
	DelistDate    string  // 退市日
	PerUnit       float64 // 合约乘数（ETF 期权一般为 10000）
}

// OptionDaily 是 Tushare opt_daily 单行的本地结构。
type OptionDaily struct {
	TsCode    string
	TradeDate string
	Exchange  string
	PreSettle float64
	PreClose  float64
	Open      float64
	High      float64
	Low       float64
	Close     float64
	Settle    float64
	Vol       float64 // 成交量（张）
	Amount    float64 // 成交额（元）
	OI        float64 // 持仓量（张）
}

// OptBasicParams 是 OptionBasic 的过滤项。任一字段为零值即不参与过滤。
type OptBasicParams struct {
	Exchange string // SSE/SZSE/CFFEX/SHFE/DCE/CZCE
	TsCode   string // 单个合约代码
	OptCode  string // 标的代码（ETF/股票/期货合约），用于"列出某标的的所有期权"
	CallPut  string // "C" 或 "P"，过滤认购/认沽
}

// OptionBasic 拉期权合约清单。
//
// 注：Tushare opt_basic 单次默认上限 ~10000 行；ETF 期权（上证 50/沪深 300/
// 创业板/科创板 等）合约总数远低于此，所以我们直接一次拿。
//
// 由于 opt_basic 不接受 "in 多标的" 之类的过滤，当 caller 想拿
// 多个标的的期权时应自行多次调用并按 OptCode 过滤；本函数已经做了
// 内存层 OptCode 精确匹配（Tushare 接口本身也支持 opt_code 参数，
// 但部分老 token 不识别，这里走"先拉 exchange 全集 + 内存过滤"
// 路径，单 exchange 也就 1-2k 条，开销可接受）。
func (c *Client) OptionBasic(ctx context.Context, p OptBasicParams) ([]OptionContract, error) {
	params := map[string]any{}
	if strings.TrimSpace(p.Exchange) != "" {
		params["exchange"] = strings.ToUpper(strings.TrimSpace(p.Exchange))
	}
	if strings.TrimSpace(p.TsCode) != "" {
		params["ts_code"] = strings.TrimSpace(p.TsCode)
	}
	if strings.TrimSpace(p.CallPut) != "" {
		params["call_put"] = strings.ToUpper(strings.TrimSpace(p.CallPut))
	}
	if strings.TrimSpace(p.OptCode) != "" {
		// 部分 token 支持 opt_code 过滤；不支持也无副作用（被忽略）。
		params["opt_code"] = strings.TrimSpace(p.OptCode)
	}
	fields := []string{
		"ts_code", "exchange", "name", "opt_code", "call_put",
		"exercise_type", "exercise_price", "s_month",
		"maturity_date", "list_date", "delist_date", "per_unit",
	}

	// 仅当只指定 exchange 时缓存（典型场景：列出"上交所所有期权"做内存过滤）。
	var rows []map[string]any
	var err error
	if p.TsCode == "" && p.OptCode == "" && p.CallPut == "" && p.Exchange != "" {
		rows, err = c.QueryCached(ctx, "opt_basic_"+strings.ToUpper(p.Exchange), "opt_basic", params, fields)
	} else {
		rows, err = c.Query(ctx, "opt_basic", params, fields)
	}
	if err != nil {
		return nil, err
	}

	wantOptCode := strings.TrimSpace(p.OptCode)
	wantCP := strings.ToUpper(strings.TrimSpace(p.CallPut))

	out := make([]OptionContract, 0, len(rows))
	for _, r := range rows {
		oc := OptionContract{
			TsCode:        AsString(r["ts_code"]),
			Exchange:      AsString(r["exchange"]),
			Name:          AsString(r["name"]),
			OptCode:       AsString(r["opt_code"]),
			CallPut:       strings.ToUpper(AsString(r["call_put"])),
			ExerciseType:  AsString(r["exercise_type"]),
			ExercisePrice: AsFloat(r["exercise_price"]),
			SMonth:        AsString(r["s_month"]),
			MaturityDate:  AsString(r["maturity_date"]),
			ListDate:      AsString(r["list_date"]),
			DelistDate:    AsString(r["delist_date"]),
			PerUnit:       AsFloat(r["per_unit"]),
		}
		if wantOptCode != "" && oc.OptCode != wantOptCode {
			continue
		}
		if wantCP != "" && oc.CallPut != wantCP {
			continue
		}
		out = append(out, oc)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].MaturityDate != out[j].MaturityDate {
			return out[i].MaturityDate < out[j].MaturityDate
		}
		return out[i].ExercisePrice < out[j].ExercisePrice
	})
	return out, nil
}

// OptDailyParams 是 OptionDaily 过滤参数。
type OptDailyParams struct {
	TsCode    string // 单个合约代码（与 TradeDate 二选一）
	TradeDate string // YYYYMMDD（与 TsCode 二选一）
	StartDate string // YYYYMMDD
	EndDate   string // YYYYMMDD
	Exchange  string // 可选；按交易所过滤
}

// OptionDailyBatch 拉期权日线。
//
// 两种典型用法：
//  1. 按 trade_date 取"某一天所有合约的行情"（不传 ts_code）— 适合
//     screen_sell_put 一次拿到全市场 PUT 的当日价/量/OI；
//  2. 按 ts_code + start_date/end_date 取"单合约时间序列" — 适合
//     研究单张期权的近月走势。
//
// 注意：Tushare opt_daily 单次最多约 4000-6000 行，按 exchange 过滤
// 后基本不会超。
func (c *Client) OptionDailyBatch(ctx context.Context, p OptDailyParams) ([]OptionDaily, error) {
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
		"ts_code", "trade_date", "exchange",
		"pre_settle", "pre_close", "open", "high", "low",
		"close", "settle", "vol", "amount", "oi",
	}
	rows, err := c.Query(ctx, "opt_daily", params, fields)
	if err != nil {
		return nil, err
	}
	out := make([]OptionDaily, 0, len(rows))
	for _, r := range rows {
		out = append(out, OptionDaily{
			TsCode:    AsString(r["ts_code"]),
			TradeDate: AsString(r["trade_date"]),
			Exchange:  AsString(r["exchange"]),
			PreSettle: AsFloat(r["pre_settle"]),
			PreClose:  AsFloat(r["pre_close"]),
			Open:      AsFloat(r["open"]),
			High:      AsFloat(r["high"]),
			Low:       AsFloat(r["low"]),
			Close:     AsFloat(r["close"]),
			Settle:    AsFloat(r["settle"]),
			Vol:       AsFloat(r["vol"]),
			Amount:    AsFloat(r["amount"]),
			OI:        AsFloat(r["oi"]),
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].TradeDate < out[j].TradeDate })
	return out, nil
}

// OptionExchangeOf 用 ETF 标的代码推断期权所在交易所。
//
// 例：510300.SH → SSE 期权；159919.SZ → SZSE 期权。
// 期货期权（CFFEX/SHFE/DCE/CZCE）需要 caller 显式传 exchange。
func OptionExchangeOf(optCode string) string {
	s := strings.ToUpper(strings.TrimSpace(optCode))
	switch {
	case strings.HasSuffix(s, ".SH"):
		return "SSE"
	case strings.HasSuffix(s, ".SZ"):
		return "SZSE"
	}
	return ""
}
