package realtime

import (
	"context"
	"fmt"
	"strings"
)

// sina_futures.go 实现新浪 hq.sinajs.cn 的国内期货实时快照。
//
// 新浪期货 symbol 规则（已统一）：
//
//	前缀 nf_ + 大写品种代码 + 月份
//	  SHFE / INE / DCE / CZCE / CFFEX / GFEX 一律大写
//	  CZCE 月份必须压成 3 位 YMM（SR2509 → SR509、CF2607 → CF607）
//
// 字段映射分两种：
//
//  1. 商品期货（SHFE / INE / DCE / CZCE / GFEX）
//     0  name         合约中文名（GBK）
//     1  time         HHMMSS
//     2  open
//     3  high
//     4  low
//     5  pre_close    昨收盘
//     6  bid1
//     7  ask1
//     8  last         最新价
//     9  avg_price    均价（不取）
//     10 pre_settle   昨结算（涨跌幅的基准）
//     11 bid_vol
//     12 ask_vol
//     13 hold         持仓量
//     14 volume       成交量（手）
//     ...
//     17/18 date      YYYY-MM-DD
//
//  2. 股指 / 国债期货（CFFEX：IF / IC / IH / IM / T / TS / TF）
//     0  open
//     1  high
//     2  low
//     3  last         最新价
//     4  volume
//     5  amount
//     6  hold
//     9  limit_up
//     10 limit_down
//     13 pre_settle
//     14 pre_close
//     16 bid1   17 bid_vol1
//     26 ask1   27 ask_vol1
//     -2 avg_price
//     -1 name (GBK)
//
// 涨跌幅按"昨结算"计算：pct_chg = (last - pre_settle) / pre_settle * 100。

// tsCodeToSinaFutures 把 tushare 期货 ts_code 转新浪 symbol（统一大写 + nf_ 前缀）。
//
// 例：
//
//	RB2510.SHF → nf_RB2510
//	IF2509.CFE → nf_IF2509
//	SR2509.ZCE → nf_SR509   （CZCE 月份压 3 位）
//	SI2510.GFE → nf_SI2510  （注意新浪 GFEX 用大写，和东财相反）
//	sc2509.INE → nf_SC2509
//	m2509.DCE  → nf_M2509
func tsCodeToSinaFutures(tsCode string) string {
	s := strings.TrimSpace(tsCode)
	if s == "" {
		return ""
	}
	dot := strings.LastIndex(s, ".")
	if dot < 0 {
		return ""
	}
	body := strings.ToUpper(s[:dot])
	suf := strings.ToUpper(s[dot+1:])
	switch suf {
	case "CFE", "CFFEX":
		return "nf_" + body
	case "SHF", "SHFE":
		return "nf_" + body
	case "INE":
		return "nf_" + body
	case "DCE":
		return "nf_" + body
	case "CZC", "CZCE", "ZCE":
		return "nf_" + czceCompressMonth(body)
	case "GFE", "GFEX":
		return "nf_" + body
	}
	return ""
}

// isCFFEXTsCode 判断是否为 CFFEX 合约（决定走股指字段格式）。
func isCFFEXTsCode(tsCode string) bool {
	dot := strings.LastIndex(tsCode, ".")
	if dot < 0 {
		return false
	}
	suf := strings.ToUpper(tsCode[dot+1:])
	return suf == "CFE" || suf == "CFFEX"
}

// fetchSinaFuturesSnapshot 拉单合约期货实时行情。
func (c *Client) fetchSinaFuturesSnapshot(ctx context.Context, tsCode string) (*FuturesQuote, error) {
	sym := tsCodeToSinaFutures(tsCode)
	if sym == "" {
		return nil, fmt.Errorf("invalid futures ts_code for sina: %s", tsCode)
	}
	out, err := c.fetchSinaList(ctx, []string{sym})
	if err != nil {
		return nil, err
	}
	fields, ok := out[sym]
	if !ok {
		return nil, fmt.Errorf("sina futures empty for %s（合约不存在 / 已退市 / 非交易时段）", tsCode)
	}
	var q *FuturesQuote
	if isCFFEXTsCode(tsCode) {
		q = parseSinaCFFEXRow(fields)
	} else {
		q = parseSinaCommodityRow(fields)
	}
	if q == nil {
		return nil, fmt.Errorf("sina futures bad fields for %s: len=%d", tsCode, len(fields))
	}
	q.TsCode = strings.ToUpper(tsCode)
	q.Code = stripFuturesPrefix(sym)
	q.Exchange = futuresExchangeFromTsCode(tsCode)
	return q, nil
}

// fetchSinaFuturesBatch 批量拉多合约期货实时行情。
//
// 与东财不同：新浪 list= 原生支持多 symbol，一次 HTTP 调用即可，
// 不需要并发拉 N 次。请求大小做了上限保护（avoid URL 过长）。
func (c *Client) fetchSinaFuturesBatch(ctx context.Context, tsCodes []string) ([]FuturesQuote, error) {
	type item struct {
		ts, sym string
		cffex   bool
	}
	items := make([]item, 0, len(tsCodes))
	syms := make([]string, 0, len(tsCodes))
	for _, ts := range tsCodes {
		ts = strings.TrimSpace(ts)
		if ts == "" {
			continue
		}
		sym := tsCodeToSinaFutures(ts)
		if sym == "" {
			continue
		}
		items = append(items, item{ts: ts, sym: sym, cffex: isCFFEXTsCode(ts)})
		syms = append(syms, sym)
	}
	if len(syms) == 0 {
		return nil, fmt.Errorf("no valid futures ts_codes")
	}
	out, err := c.fetchSinaList(ctx, syms)
	if err != nil {
		return nil, err
	}
	res := make([]FuturesQuote, 0, len(items))
	for _, it := range items {
		fields, ok := out[it.sym]
		if !ok {
			continue
		}
		var q *FuturesQuote
		if it.cffex {
			q = parseSinaCFFEXRow(fields)
		} else {
			q = parseSinaCommodityRow(fields)
		}
		if q == nil {
			continue
		}
		q.TsCode = strings.ToUpper(it.ts)
		q.Code = stripFuturesPrefix(it.sym)
		q.Exchange = futuresExchangeFromTsCode(it.ts)
		res = append(res, *q)
	}
	return res, nil
}

// parseSinaCommodityRow 解析商品期货行（SHFE/INE/DCE/CZCE/GFEX）。
func parseSinaCommodityRow(f []string) *FuturesQuote {
	if len(f) < 15 {
		return nil
	}
	name := strings.TrimSpace(sinaFieldAt(f, 0))
	open := sinaParseFloat(sinaFieldAt(f, 2))
	high := sinaParseFloat(sinaFieldAt(f, 3))
	low := sinaParseFloat(sinaFieldAt(f, 4))
	preClose := sinaParseFloat(sinaFieldAt(f, 5))
	bid := sinaParseFloat(sinaFieldAt(f, 6))
	ask := sinaParseFloat(sinaFieldAt(f, 7))
	last := sinaParseFloat(sinaFieldAt(f, 8))
	preSettle := sinaParseFloat(sinaFieldAt(f, 10))
	hold := sinaParseInt(sinaFieldAt(f, 13))
	volume := sinaParseInt(sinaFieldAt(f, 14))

	var change, pctChg float64
	if preSettle > 0 {
		change = round2(last - preSettle)
		pctChg = round4((last - preSettle) / preSettle * 100)
	}

	return &FuturesQuote{
		Name:      name,
		Last:      last,
		PctChg:    pctChg,
		Change:    change,
		Open:      open,
		High:      high,
		Low:       low,
		PreClose:  preClose,
		PreSettle: preSettle,
		Volume:    volume,
		OI:        hold,
		Bid:       bid,
		Ask:       ask,
		Delayed:   false,
	}
}

// parseSinaCFFEXRow 解析 CFFEX 行（IF/IC/IH/IM/T/TS/TF）。
func parseSinaCFFEXRow(f []string) *FuturesQuote {
	if len(f) < 28 {
		return nil
	}
	open := sinaParseFloat(sinaFieldAt(f, 0))
	high := sinaParseFloat(sinaFieldAt(f, 1))
	low := sinaParseFloat(sinaFieldAt(f, 2))
	last := sinaParseFloat(sinaFieldAt(f, 3))
	volume := sinaParseInt(sinaFieldAt(f, 4))
	amount := sinaParseFloat(sinaFieldAt(f, 5))
	hold := sinaParseInt(sinaFieldAt(f, 6))
	preSettle := sinaParseFloat(sinaFieldAt(f, 13))
	preClose := sinaParseFloat(sinaFieldAt(f, 14))
	bid := sinaParseFloat(sinaFieldAt(f, 16))
	ask := sinaParseFloat(sinaFieldAt(f, 26))

	// 名称：从尾部往前找第一个含中文字符的字段
	name := ""
	for i := len(f) - 1; i >= 0; i-- {
		s := strings.TrimSpace(f[i])
		if containsCJK(s) {
			name = s
			break
		}
	}

	var change, pctChg float64
	if preSettle > 0 {
		change = round2(last - preSettle)
		pctChg = round4((last - preSettle) / preSettle * 100)
	}

	return &FuturesQuote{
		Name:      name,
		Last:      last,
		PctChg:    pctChg,
		Change:    change,
		Open:      open,
		High:      high,
		Low:       low,
		PreClose:  preClose,
		PreSettle: preSettle,
		Volume:    volume,
		Amount:    amount,
		OI:        hold,
		Bid:       bid,
		Ask:       ask,
		Delayed:   false,
	}
}

// containsCJK 检查字符串是否含 CJK 中文字符。
func containsCJK(s string) bool {
	for _, r := range s {
		if r >= 0x4E00 && r <= 0x9FFF {
			return true
		}
	}
	return false
}

// futuresExchangeFromTsCode 由 ts_code 后缀反查交易所简称。
func futuresExchangeFromTsCode(tsCode string) string {
	dot := strings.LastIndex(tsCode, ".")
	if dot < 0 {
		return ""
	}
	switch strings.ToUpper(tsCode[dot+1:]) {
	case "CFE", "CFFEX":
		return "CFFEX"
	case "SHF", "SHFE":
		return "SHFE"
	case "INE":
		return "INE"
	case "DCE":
		return "DCE"
	case "CZC", "CZCE", "ZCE":
		return "CZCE"
	case "GFE", "GFEX":
		return "GFEX"
	}
	return ""
}

func stripFuturesPrefix(sym string) string {
	return strings.TrimPrefix(sym, "nf_")
}
