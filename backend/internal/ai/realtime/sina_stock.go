package realtime

import (
	"context"
	"fmt"
	"math"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// sina_stock.go 实现新浪 hq.sinajs.cn 的 A 股 / ETF / 指数实时快照。
//
// A 股 / ETF 字段映射（33 字段，位置式）：
//
//	 0 name          名称
//	 1 open          今开
//	 2 pre_close     昨收
//	 3 last          最新价
//	 4 high          今日最高
//	 5 low           今日最低
//	 6 bid1          买一价（不用）
//	 7 ask1          卖一价（不用）
//	 8 volume(股)    今日累计成交量（除以 100 → 手）
//	 9 amount(元)    今日累计成交额
//	10-29 买卖五档（价、量交替；本工具不取）
//	30 date          交易日 YYYY-MM-DD
//	31 time          最新报价时间 HH:MM:SS
//	32 status        "00" = 收盘后；其他 = 盘中
//
// 指数走完全相同的 33 字段格式（普通前缀 sh/sz 即可，无需 s_）。
// 不同点：指数 volume 字段单位是"手"，不需要 / 100。

// tsCodeToSinaStock 把 tushare 形 ts_code 转新浪股票 symbol（sh600519 / sz000001 / bj430139）。
func tsCodeToSinaStock(symbol string) string {
	code := tushare.NormalizeSymbol(symbol)
	switch {
	case strings.HasSuffix(code, ".SH"):
		return "sh" + strings.ToLower(strings.TrimSuffix(code, ".SH"))
	case strings.HasSuffix(code, ".SZ"):
		return "sz" + strings.ToLower(strings.TrimSuffix(code, ".SZ"))
	case strings.HasSuffix(code, ".BJ"):
		return "bj" + strings.ToLower(strings.TrimSuffix(code, ".BJ"))
	}
	return ""
}

// tsCodeToSinaIndex 把指数 ts_code 转新浪 symbol（sh000300 / sz399006）。
// 指数与 A 股共用相同的 6 位数字代码段，统一不带 s_ 前缀（拿到字段更全）。
func tsCodeToSinaIndex(tsCode string) string {
	code := strings.ToUpper(strings.TrimSpace(tsCode))
	switch {
	case strings.HasSuffix(code, ".SH"):
		return "sh" + strings.TrimSuffix(code, ".SH")
	case strings.HasSuffix(code, ".SZ"):
		return "sz" + strings.TrimSuffix(code, ".SZ")
	}
	return ""
}

// isLikelyIndexTsCode 粗判 ts_code 是否为指数（沪 0000xx / 0008xx / 0009xx；深 399xxx）。
//
// 用于 FetchSnapshot 调用方传入指数代码时的内部分发；不增加新数据源兜底，
// 只是把 symbol 路由到对应字段映射。
func isLikelyIndexTsCode(symbol string) bool {
	code := tushare.NormalizeSymbol(symbol)
	if _, ok := IndexSecID[strings.ToUpper(code)]; ok {
		return true
	}
	if strings.HasSuffix(code, ".SH") {
		body := strings.TrimSuffix(code, ".SH")
		// 上证指数 / 行业指数大多以 000、0008、0009 开头
		return strings.HasPrefix(body, "0000") ||
			strings.HasPrefix(body, "0008") ||
			strings.HasPrefix(body, "0009")
	}
	if strings.HasSuffix(code, ".SZ") {
		return strings.HasPrefix(strings.TrimSuffix(code, ".SZ"), "399")
	}
	return false
}

// fetchSinaStockSnapshot 拉 A 股 / ETF 单标的快照。
func (c *Client) fetchSinaStockSnapshot(ctx context.Context, symbol string) (*Quote, error) {
	if isLikelyIndexTsCode(symbol) {
		// 指数走指数分支（字段单位差异）
		qs, err := c.fetchSinaIndexes(ctx, []string{tushare.NormalizeSymbol(symbol)})
		if err != nil {
			return nil, err
		}
		if len(qs) == 0 {
			return nil, fmt.Errorf("sina index empty for %s", symbol)
		}
		q := qs[0]
		return &q, nil
	}
	sinaSym := tsCodeToSinaStock(symbol)
	if sinaSym == "" {
		return nil, fmt.Errorf("unsupported symbol for sina realtime: %s", symbol)
	}
	out, err := c.fetchSinaList(ctx, []string{sinaSym})
	if err != nil {
		return nil, err
	}
	fields, ok := out[sinaSym]
	if !ok {
		return nil, fmt.Errorf("sina snapshot empty for %s（标的不存在或已退市）", symbol)
	}
	q := parseSinaStockRow(fields, sinaSym, false)
	if q == nil {
		return nil, fmt.Errorf("sina snapshot bad fields for %s: len=%d", symbol, len(fields))
	}
	q.TsCode = strings.ToUpper(tushare.NormalizeSymbol(symbol))
	return q, nil
}

// fetchSinaIndexes 批量拉指数快照。
func (c *Client) fetchSinaIndexes(ctx context.Context, tsCodes []string) ([]Quote, error) {
	syms := make([]string, 0, len(tsCodes))
	back := make(map[string]string, len(tsCodes)) // sinaSym → ts_code
	for _, ts := range tsCodes {
		ts = strings.ToUpper(strings.TrimSpace(ts))
		sym := tsCodeToSinaIndex(ts)
		if sym == "" {
			continue
		}
		syms = append(syms, sym)
		back[sym] = ts
	}
	if len(syms) == 0 {
		return nil, fmt.Errorf("no valid index ts_code")
	}
	out, err := c.fetchSinaList(ctx, syms)
	if err != nil {
		return nil, err
	}
	res := make([]Quote, 0, len(out))
	for _, sym := range syms {
		fields, ok := out[sym]
		if !ok {
			continue
		}
		q := parseSinaStockRow(fields, sym, true)
		if q == nil {
			continue
		}
		q.TsCode = back[sym]
		res = append(res, *q)
	}
	return res, nil
}

// parseSinaStockRow 解析新浪 A 股 / ETF / 指数共用的 33 字段格式。
//
//	asIndex=true 时 volume 视为"手"，不再除以 100。
func parseSinaStockRow(fields []string, sinaSym string, asIndex bool) *Quote {
	if len(fields) < 10 {
		return nil
	}
	name := strings.TrimSpace(sinaFieldAt(fields, 0))
	open := sinaParseFloat(sinaFieldAt(fields, 1))
	preClose := sinaParseFloat(sinaFieldAt(fields, 2))
	last := sinaParseFloat(sinaFieldAt(fields, 3))
	high := sinaParseFloat(sinaFieldAt(fields, 4))
	low := sinaParseFloat(sinaFieldAt(fields, 5))
	rawVol := sinaParseInt(sinaFieldAt(fields, 8))
	amount := sinaParseFloat(sinaFieldAt(fields, 9))

	volume := rawVol
	if !asIndex {
		volume = rawVol / 100 // 股 → 手
	}

	var change, pctChg float64
	if preClose > 0 {
		change = round2(last - preClose)
		pctChg = round4((last - preClose) / preClose * 100)
	}

	// 从 sinaSym 提取 6 位代码（去掉 sh/sz/bj 前缀）
	code := stripSinaPrefix(sinaSym)

	return &Quote{
		Code:     code,
		Name:     name,
		Last:     last,
		PctChg:   pctChg,
		Change:   change,
		Open:     open,
		High:     high,
		Low:      low,
		PreClose: preClose,
		Volume:   volume,
		Amount:   amount,
		Delayed:  false,
	}
}

func stripSinaPrefix(sym string) string {
	switch {
	case strings.HasPrefix(sym, "sh"), strings.HasPrefix(sym, "sz"), strings.HasPrefix(sym, "bj"):
		return sym[2:]
	}
	return sym
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }
func round4(v float64) float64 { return math.Round(v*10000) / 10000 }
