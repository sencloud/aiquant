package realtime

import (
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// ToSecID 把 Tushare 形 (000001.SZ / 600519.SH / 000300.SH / 399006.SZ) 转成
// 东财 push2 的 secid（mkt.code）。
//
//	mkt: 1=沪市 (SSE), 0=深市/创业板/北交所, 105=美股, 106=美股(纳)，本工具只关心 A 股。
func ToSecID(symbol string) string {
	code := tushare.NormalizeSymbol(symbol)
	switch {
	case strings.HasSuffix(code, ".SH"):
		return "1." + strings.TrimSuffix(code, ".SH")
	case strings.HasSuffix(code, ".SZ"):
		return "0." + strings.TrimSuffix(code, ".SZ")
	case strings.HasSuffix(code, ".BJ"):
		return "0." + strings.TrimSuffix(code, ".BJ")
	}
	return ""
}

// IndexSecID 显式指定指数代码到东财 secid 映射。
//
// 主流指数：沪深 300 / 上证 50 / 中证 500 都在沪市 (mkt=1)，
// 创业板指 / 中小板指 在深市 (mkt=0)。
var IndexSecID = map[string]string{
	"000300.SH": "1.000300",
	"000016.SH": "1.000016",
	"000905.SH": "1.000905",
	"000688.SH": "1.000688",
	"000001.SH": "1.000001", // 上证综指
	"399001.SZ": "0.399001", // 深证成指
	"399006.SZ": "0.399006", // 创业板指
	"399005.SZ": "0.399005", // 中小100
}

// FuturesSecID 把期货 ts_code（如 RB2510.SHF / IF2509.CFE / sc2509.INE）
// 转成东财 push2 的 secid（mkt.code）。
//
// 各交易所 mkt 值（与 akshare futures_zh_spot 对齐）：
//
//	CFFEX  中金所         → 8
//	SHFE   上期所         → 113
//	INE    上海能源       → 142
//	DCE    大商所         → 114
//	CZCE   郑商所         → 115
//	GFEX   广期所         → 225
//
// 代码大小写约定（东财对此敏感）：
//
//	SHFE / INE / DCE / GFEX 用小写（cu2510、sc2509、m2509、si2509）
//	CFFEX 用大写（IF2509、T2509）
//	CZCE  用大写，且月份必须压缩成 3 位 YMM：
//	  Tushare 的 SR2509.ZCE 在东财是 SR509，CF2607.ZCE → CF607。
func FuturesSecID(tsCode string) string {
	s := strings.TrimSpace(tsCode)
	if s == "" {
		return ""
	}
	dot := strings.LastIndex(s, ".")
	if dot < 0 {
		return ""
	}
	body, suf := s[:dot], strings.ToUpper(s[dot+1:])
	switch suf {
	case "CFE", "CFFEX":
		return "8." + strings.ToUpper(body)
	case "SHF", "SHFE":
		return "113." + strings.ToLower(body)
	case "INE":
		return "142." + strings.ToLower(body)
	case "DCE":
		return "114." + strings.ToLower(body)
	case "CZC", "CZCE", "ZCE":
		return "115." + czceCompressMonth(strings.ToUpper(body))
	case "GFE", "GFEX":
		return "225." + strings.ToLower(body)
	}
	return ""
}

// czceCompressMonth 把 CZCE 合约代码的 4 位月份压成 3 位（东财格式）。
//
// Tushare 习惯把所有合约月份写成 YYMM（SR2509、CF2607、MA2511），但
// 郑商所原生交易代码是 YMM（SR509、CF607、MA511）。东财 push2 必须用
// 原生 3 位，否则返回 data:null。
//
// 规则：从结尾抓连续数字段，长度==4 则去掉首位。其余情况原样返回。
func czceCompressMonth(body string) string {
	n := len(body)
	if n == 0 {
		return body
	}
	// 找出末尾连续数字段
	digStart := n
	for digStart > 0 && body[digStart-1] >= '0' && body[digStart-1] <= '9' {
		digStart--
	}
	prefix := body[:digStart]
	digits := body[digStart:]
	if len(digits) == 4 {
		digits = digits[1:]
	}
	return prefix + digits
}

// futuresExchangeFromSecID 反查 mkt → 交易所名（用于回填 FuturesQuote.Exchange）。
func futuresExchangeFromSecID(secid string) string {
	dot := strings.Index(secid, ".")
	if dot < 0 {
		return ""
	}
	switch secid[:dot] {
	case "8":
		return "CFFEX"
	case "113":
		return "SHFE"
	case "142":
		return "INE"
	case "114":
		return "DCE"
	case "115":
		return "CZCE"
	case "225":
		return "GFEX"
	}
	return ""
}
