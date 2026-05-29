package tushare

import (
	"context"
	"strings"
)

// ResolveEquity 把用户自由输入(代码 / 名称 / 已迁移的旧代码)解析为**当前有效**的
// ts_code + 名称。命中顺序:
//
//	1) ts_code 精确(对输入做 NormalizeSymbol 后比对)
//	2) 6 位 symbol 精确
//	3) 名称精确(先用 nameInput,再用 codeInput 当名称)
//	4) 名称包含
//
// 主要解决:北交所大量股票已从 8xxxxx 迁移到 920xxx(如 贝特瑞 835185→920185),
// 用户输入旧码 / 直接输名称时,据此映射到当前 daily 接口能查到的 ts_code。
// 未命中返回 ("","",false),调用方保留原输入即可。
func (c *Client) ResolveEquity(ctx context.Context, codeInput, nameInput string) (tsCode, name string, ok bool) {
	list, err := c.StockBasic(ctx)
	if err != nil || len(list) == 0 {
		return "", "", false
	}
	code := strings.ToUpper(strings.TrimSpace(codeInput))

	// 1) ts_code 精确
	norm := NormalizeSymbol(code)
	for _, it := range list {
		if strings.EqualFold(it.TsCode, norm) || strings.EqualFold(it.TsCode, code) {
			return it.TsCode, it.Name, true
		}
	}
	// 2) 6 位 symbol 精确(去掉可能的 .XX 后缀)
	bare := code
	if i := strings.IndexByte(bare, '.'); i > 0 {
		bare = bare[:i]
	}
	if bare != "" {
		for _, it := range list {
			if it.Symbol == bare {
				return it.TsCode, it.Name, true
			}
		}
	}
	// 3) / 4) 名称精确 → 名称包含(优先 nameInput,其次把 codeInput 当名称)
	for _, cand := range []string{strings.TrimSpace(nameInput), strings.TrimSpace(codeInput)} {
		if cand == "" {
			continue
		}
		for _, it := range list {
			if it.Name == cand {
				return it.TsCode, it.Name, true
			}
		}
		for _, it := range list {
			if strings.Contains(it.Name, cand) {
				return it.TsCode, it.Name, true
			}
		}
	}
	return "", "", false
}

// StockBasic 返回 A 股 basic 全集，缓存到 c.cache。
func (c *Client) StockBasic(ctx context.Context) ([]Instrument, error) {
	rows, err := c.QueryCached(ctx, "stock_basic", "stock_basic",
		map[string]any{"list_status": "L"},
		[]string{"ts_code", "symbol", "name", "area", "industry", "market", "list_date", "exchange"})
	if err != nil {
		return nil, err
	}
	out := make([]Instrument, 0, len(rows))
	for _, r := range rows {
		out = append(out, Instrument{
			TsCode:   AsString(r["ts_code"]),
			Symbol:   AsString(r["symbol"]),
			Name:     AsString(r["name"]),
			Area:     AsString(r["area"]),
			Industry: AsString(r["industry"]),
			Market:   AsString(coalesce(r["exchange"], r["market"])),
			Type:     "stock",
			ListDate: AsString(r["list_date"]),
		})
	}
	return out, nil
}

// FundBasic 返回 ETF / LOF basic（market='E' 场内 / 'O' 场外）。
func (c *Client) FundBasic(ctx context.Context, market string) ([]Instrument, error) {
	if market == "" {
		market = "E"
	}
	rows, err := c.QueryCached(ctx, "fund_basic_"+market, "fund_basic",
		map[string]any{"market": market},
		[]string{"ts_code", "name", "management", "fund_type", "list_date", "market"})
	if err != nil {
		return nil, err
	}
	out := make([]Instrument, 0, len(rows))
	for _, r := range rows {
		mk := "OTC"
		if market == "E" {
			mk = "ETF"
		}
		out = append(out, Instrument{
			TsCode:   AsString(r["ts_code"]),
			Name:     AsString(r["name"]),
			Industry: AsString(r["fund_type"]),
			Area:     AsString(r["management"]),
			Market:   mk,
			Type:     "fund",
			ListDate: AsString(r["list_date"]),
		})
	}
	return out, nil
}

// FutBasic 返回某交易所的期货 basic。
func (c *Client) FutBasic(ctx context.Context, exchange string) ([]Instrument, error) {
	if exchange == "" {
		exchange = "CFFEX"
	}
	rows, err := c.QueryCached(ctx, "fut_basic_"+exchange, "fut_basic",
		map[string]any{"exchange": exchange},
		[]string{"ts_code", "symbol", "name", "fut_code", "exchange", "multiplier", "list_date", "delist_date"})
	if err != nil {
		return nil, err
	}
	out := make([]Instrument, 0, len(rows))
	for _, r := range rows {
		out = append(out, Instrument{
			TsCode:     AsString(r["ts_code"]),
			Symbol:     AsString(r["symbol"]),
			Name:       AsString(r["name"]),
			Industry:   AsString(r["fut_code"]),
			Market:     AsString(r["exchange"]),
			Type:       "futures",
			ListDate:   AsString(r["list_date"]),
			DelistDate: AsString(r["delist_date"]),
			Multiplier: AsFloat(r["multiplier"]),
		})
	}
	return out, nil
}

// IndexBasic 返回指数 basic（market: SSE/SZSE/CSI 等）。
func (c *Client) IndexBasic(ctx context.Context, market string) ([]Instrument, error) {
	if market == "" {
		market = "SSE"
	}
	rows, err := c.QueryCached(ctx, "index_basic_"+market, "index_basic",
		map[string]any{"market": market},
		[]string{"ts_code", "name", "market", "publisher", "category", "base_date", "list_date"})
	if err != nil {
		return nil, err
	}
	out := make([]Instrument, 0, len(rows))
	for _, r := range rows {
		out = append(out, Instrument{
			TsCode:   AsString(r["ts_code"]),
			Name:     AsString(r["name"]),
			Market:   AsString(r["market"]),
			Industry: AsString(r["category"]),
			Area:     AsString(r["publisher"]),
			Type:     "index",
			ListDate: AsString(r["list_date"]),
		})
	}
	return out, nil
}

// AllFutures 一次拿 4 个常用交易所的期货合并；某一个失败不影响其它。
func (c *Client) AllFutures(ctx context.Context) []Instrument {
	out := []Instrument{}
	for _, ex := range []string{"CFFEX", "SHFE", "DCE", "CZCE"} {
		rows, err := c.FutBasic(ctx, ex)
		if err == nil {
			out = append(out, rows...)
		}
	}
	return out
}

func coalesce(vs ...any) any {
	for _, v := range vs {
		if v == nil {
			continue
		}
		if s, ok := v.(string); ok && s == "" {
			continue
		}
		return v
	}
	return nil
}
