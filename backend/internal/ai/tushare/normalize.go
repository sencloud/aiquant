package tushare

import (
	"regexp"
	"strings"
)

// 这些规则与客户端 lib/core/utils/china_market.dart 对齐 — 服务端要重新实现
// 是因为客户端规则将来可以删，但 LLM 工具调用只能在服务端归一。

var sixDigit = regexp.MustCompile(`^\d{6}$`)
var letterPrefix = regexp.MustCompile(`^[A-Z]+`)

// futureSuffixes 列出所有可能出现的期货交易所后缀（含 Tushare 原生与东财/akshare 变体）。
//
// Tushare fut_daily 原生后缀：CFFEX=.CFX、CZCE=.ZCE、SHFE=.SHF、DCE=.DCE、INE=.INE、GFEX=.GFE。
// 这里把东财风格的 .CFE / .CZC 也保留，便于 IsFuture 在归一前后都能识别。
var futureSuffixes = []string{
	".ZCE", ".CZC", ".CZCE",
	".DCE",
	".SHF", ".SHFE",
	".INE",
	".GFE", ".GFEX",
	".CFX", ".CFE", ".CFFEX",
}

// NormalizeSymbol 把用户输入的代码转成 Tushare 可识别形态。
//
// 期货后缀一律归一到 **Tushare fut_daily 原生形态**（这是 get_dominant_contract
// 的输出形态，也是历史/财务接口要求的形态），消除「东财 .CFE/.CZC」与
// 「Tushare .CFX/.ZCE」两套约定导致的路由错配：
//   - CFFEX：.CFFEX / .CFE → .CFX
//   - CZCE ：.CZCE  / .CZC → .ZCE
//   - SHFE ：.SHFE → .SHF；GFEX：.GFEX → .GFE
//   - DCE / INE / .SHF / .CFX / .ZCE / .GFE 已是原生，原样透传
//
// 股票/ETF/指数规则不变：
//   - 6 位纯数字：6/900 → .SH；0/3/200 → .SZ；4/8/920 → .BJ
func NormalizeSymbol(input string) string {
	s := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(input), " ", ""))
	if s == "" {
		return ""
	}
	if strings.Contains(s, ".") {
		switch {
		case strings.HasSuffix(s, ".CFFEX"):
			return s[:len(s)-6] + ".CFX"
		case strings.HasSuffix(s, ".CFE"):
			return s[:len(s)-4] + ".CFX"
		case strings.HasSuffix(s, ".CZCE"):
			return s[:len(s)-5] + ".ZCE"
		case strings.HasSuffix(s, ".CZC"):
			return s[:len(s)-4] + ".ZCE"
		case strings.HasSuffix(s, ".SHFE"):
			return s[:len(s)-5] + ".SHF"
		case strings.HasSuffix(s, ".GFEX"):
			return s[:len(s)-5] + ".GFE"
		}
		return s
	}
	if sixDigit.MatchString(s) {
		switch {
		case strings.HasPrefix(s, "6") || strings.HasPrefix(s, "900"):
			return s + ".SH"
		case strings.HasPrefix(s, "0") || strings.HasPrefix(s, "3") || strings.HasPrefix(s, "200"):
			return s + ".SZ"
		case strings.HasPrefix(s, "4") || strings.HasPrefix(s, "8") || strings.HasPrefix(s, "920"):
			return s + ".BJ"
		}
	}
	return s
}

// IsFuture 是否期货代码。
func IsFuture(s string) bool {
	u := strings.ToUpper(s)
	for _, suf := range futureSuffixes {
		if strings.HasSuffix(u, suf) {
			return true
		}
	}
	return false
}

// IsIndex 是否指数。
func IsIndex(s string) bool {
	u := strings.ToUpper(s)
	if strings.HasPrefix(u, "000") && strings.HasSuffix(u, ".SH") {
		return true
	}
	if strings.HasPrefix(u, "399") && strings.HasSuffix(u, ".SZ") {
		return true
	}
	return false
}

// IsStock 是否 A 股。
func IsStock(s string) bool {
	u := strings.ToUpper(s)
	return strings.HasSuffix(u, ".SH") || strings.HasSuffix(u, ".SZ") || strings.HasSuffix(u, ".BJ")
}

// AssetClassOf 简单判定标的类别。
func AssetClassOf(s string) string {
	if IsFuture(s) {
		return "futures"
	}
	if IsIndex(s) {
		return "index"
	}
	if IsStock(s) {
		// ETF 经常以 .SH/.SZ 结尾，不在这里区分；调用方自己 lookup instrument。
		return "stock"
	}
	return "other"
}

// ExchangeOf 返回中文交易所名称。
func ExchangeOf(s string) string {
	u := strings.ToUpper(s)
	switch {
	case strings.HasSuffix(u, ".SH"):
		return "SSE"
	case strings.HasSuffix(u, ".SZ"):
		return "SZSE"
	case strings.HasSuffix(u, ".BJ"):
		return "BSE"
	case strings.HasSuffix(u, ".ZCE") || strings.HasSuffix(u, ".CZC") || strings.HasSuffix(u, ".CZCE"):
		return "郑商所"
	case strings.HasSuffix(u, ".DCE"):
		return "大商所"
	case strings.HasSuffix(u, ".SHF") || strings.HasSuffix(u, ".SHFE"):
		return "上期所"
	case strings.HasSuffix(u, ".INE"):
		return "上海能源"
	case strings.HasSuffix(u, ".GFE") || strings.HasSuffix(u, ".GFEX"):
		return "广期所"
	case strings.HasSuffix(u, ".CFX") || strings.HasSuffix(u, ".CFE") || strings.HasSuffix(u, ".CFFEX"):
		return "中金所"
	}
	return ""
}
