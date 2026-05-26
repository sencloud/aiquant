package realtime

import (
	"context"
	"fmt"
	"math"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// tencent_stock.go 实现腾讯 qt.gtimg.cn 的 A 股 / ETF / 指数实时快照。
//
// 接口 GET https://qt.gtimg.cn/q=<sym1>,<sym2>...
// 单 symbol 形态:sh600519 / sz000001 / sh000300(指数与 A 股共用 sh/sz 前缀)。
//
// 字段映射(80+ 字段,本工具用其中 ~12 个;位置式):
//
//	  0 market_type     市场类型(数字)
//	  1 name            名称(GBK,需 decode)
//	  2 code            6 位代码
//	  3 last            最新价
//	  4 pre_close       昨收
//	  5 open            今开
//	  6 volume          成交量(**单位:手**,与新浪的"股"不同)
//	 30 time            时间戳 YYYYMMDDHHmmss
//	 31 change          涨跌额
//	 32 pct_chg         涨跌幅 %
//	 33 high            今日最高
//	 34 low             今日最低
//	 37 amount          成交额(**单位:万元**,× 10000 → 元)
//	 38 turnover_rate   换手率 %(指数 / 部分 ETF 没有,为 0)
//	 39 pe              TTM 市盈率
//
// 指数与 A 股共用字段位置:不同点仅是指数的换手率 / 振幅等字段会是 0。
// ETF 字段格式与 A 股完全一致。

// tsCodeToTencentStock 把 tushare ts_code 转腾讯 symbol(sh600519 / sz000001 / bj430139)。
func tsCodeToTencentStock(symbol string) string {
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

// tsCodeToTencentIndex 把指数 ts_code 转腾讯 symbol(sh000300 / sz399006)。
// 指数与 A 股共用 6 位代码段,统一不带 s_ 前缀(拿到字段更全)。
func tsCodeToTencentIndex(tsCode string) string {
	code := strings.ToUpper(strings.TrimSpace(tsCode))
	switch {
	case strings.HasSuffix(code, ".SH"):
		return "sh" + strings.TrimSuffix(code, ".SH")
	case strings.HasSuffix(code, ".SZ"):
		return "sz" + strings.TrimSuffix(code, ".SZ")
	}
	return ""
}

// isLikelyIndexTsCodeT 粗判 ts_code 是否为指数,内部分发用(不增加数据源)。
func isLikelyIndexTsCodeT(symbol string) bool {
	code := tushare.NormalizeSymbol(symbol)
	if _, ok := IndexSecID[strings.ToUpper(code)]; ok {
		return true
	}
	if strings.HasSuffix(code, ".SH") {
		body := strings.TrimSuffix(code, ".SH")
		return strings.HasPrefix(body, "0000") ||
			strings.HasPrefix(body, "0008") ||
			strings.HasPrefix(body, "0009")
	}
	if strings.HasSuffix(code, ".SZ") {
		return strings.HasPrefix(strings.TrimSuffix(code, ".SZ"), "399")
	}
	return false
}

// fetchTencentStockSnapshot 拉 A 股 / ETF 单标的快照。
//
// 自动识别 ts_code 是不是指数,是则走指数分支。
func (c *Client) fetchTencentStockSnapshot(ctx context.Context, symbol string) (*Quote, error) {
	if isLikelyIndexTsCodeT(symbol) {
		qs, err := c.fetchTencentIndexes(ctx, []string{tushare.NormalizeSymbol(symbol)})
		if err != nil {
			return nil, err
		}
		if len(qs) == 0 {
			return nil, fmt.Errorf("tencent: empty index quote for %s", symbol)
		}
		q := qs[0]
		return &q, nil
	}

	tsym := tsCodeToTencentStock(symbol)
	if tsym == "" {
		return nil, fmt.Errorf("tencent: unsupported symbol for realtime: %s", symbol)
	}
	rows, err := c.fetchTencentList(ctx, []string{tsym})
	if err != nil {
		return nil, err
	}
	fields, ok := rows[tsym]
	if !ok {
		return nil, fmt.Errorf("tencent: no data for %s (deleted / suspended?)", symbol)
	}
	q := parseTencentStockRow(fields, tushare.NormalizeSymbol(symbol), false)
	return &q, nil
}

// fetchTencentIndexes 批量拉指数快照。tsCodes 输入 tushare 形(000300.SH 等)。
func (c *Client) fetchTencentIndexes(ctx context.Context, tsCodes []string) ([]Quote, error) {
	if len(tsCodes) == 0 {
		return nil, nil
	}
	syms := make([]string, 0, len(tsCodes))
	mapBack := make(map[string]string, len(tsCodes)) // 腾讯 sym → 标准 ts_code
	for _, ts := range tsCodes {
		t := tsCodeToTencentIndex(ts)
		if t == "" {
			continue
		}
		syms = append(syms, t)
		mapBack[t] = strings.ToUpper(strings.TrimSpace(ts))
	}
	if len(syms) == 0 {
		return nil, fmt.Errorf("tencent: no valid index symbols")
	}
	rows, err := c.fetchTencentList(ctx, syms)
	if err != nil {
		return nil, err
	}
	out := make([]Quote, 0, len(rows))
	for tsym, fields := range rows {
		ts := mapBack[tsym]
		if ts == "" {
			ts = restoreTsCodeFromTencent(tsym)
		}
		q := parseTencentStockRow(fields, ts, true)
		out = append(out, q)
	}
	return out, nil
}

// parseTencentStockRow 把 33+ 字段切片解为 Quote。
//
// isIndex 控制部分单位差异:指数无换手率 / PE,直接 0。
func parseTencentStockRow(fields []string, tsCode string, isIndex bool) Quote {
	name := fieldAtT(fields, 1)
	code := fieldAtT(fields, 2)
	last := parseFloatSafe(fieldAtT(fields, 3))
	preClose := parseFloatSafe(fieldAtT(fields, 4))
	open := parseFloatSafe(fieldAtT(fields, 5))
	volumeHands := parseIntSafe(fieldAtT(fields, 6)) // 单位:手

	change := parseFloatSafe(fieldAtT(fields, 31))
	pctChg := parseFloatSafe(fieldAtT(fields, 32))
	high := parseFloatSafe(fieldAtT(fields, 33))
	low := parseFloatSafe(fieldAtT(fields, 34))
	// amount 字段 37 单位"万元",× 10000 转元
	amount := parseFloatSafe(fieldAtT(fields, 37)) * 10000.0

	var (
		turnover float64
		pe       float64
	)
	if !isIndex {
		turnover = parseFloatSafe(fieldAtT(fields, 38))
		pe = parseFloatSafe(fieldAtT(fields, 39))
	}

	// 若 change/pctChg 缺失(返回 0)但 preClose 与 last 都有,自己算
	if (change == 0 || pctChg == 0) && preClose > 0 && last > 0 {
		if change == 0 {
			change = round2(last - preClose)
		}
		if pctChg == 0 {
			pctChg = round4((last - preClose) / preClose * 100)
		}
	}

	q := Quote{
		Code:         code,
		TsCode:       tsCode,
		Name:         name,
		Last:         round4(last),
		PctChg:       round4(pctChg),
		Change:       round2(change),
		Open:         round4(open),
		High:         round4(high),
		Low:          round4(low),
		PreClose:     round4(preClose),
		Volume:       volumeHands,
		Amount:       amount,
		TurnoverRate: round4(turnover),
		PE:           round4(pe),
		Delayed:      false,
	}
	return q
}

// restoreTsCodeFromTencent sh600519 → 600519.SH(用于反查不在 mapBack 里的 symbol)。
func restoreTsCodeFromTencent(tsym string) string {
	if strings.HasPrefix(tsym, "sh") {
		return strings.ToUpper(strings.TrimPrefix(tsym, "sh")) + ".SH"
	}
	if strings.HasPrefix(tsym, "sz") {
		return strings.ToUpper(strings.TrimPrefix(tsym, "sz")) + ".SZ"
	}
	if strings.HasPrefix(tsym, "bj") {
		return strings.ToUpper(strings.TrimPrefix(tsym, "bj")) + ".BJ"
	}
	return strings.ToUpper(tsym)
}

// round2 保留 2 位小数。
func round2(v float64) float64 {
	if v == 0 {
		return 0
	}
	return math.Round(v*100) / 100
}

// round4 保留 4 位小数(价格 / 涨跌幅常用)。
func round4(v float64) float64 {
	if v == 0 {
		return 0
	}
	return math.Round(v*10000) / 10000
}
