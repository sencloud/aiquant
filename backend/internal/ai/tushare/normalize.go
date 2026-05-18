package tushare

import (
	"regexp"
	"strings"
)

// 这些规则与客户端 lib/core/utils/china_market.dart 对齐 — 服务端要重新实现
// 是因为客户端规则将来可以删，但 LLM 工具调用只能在服务端归一。

var sixDigit = regexp.MustCompile(`^\d{6}$`)
var letterPrefix = regexp.MustCompile(`^[A-Z]+`)

var futureSuffixes = []string{
	".CZC", ".CZCE",
	".DCE",
	".SHF", ".SHFE",
	".INE",
	".GFE", ".GFEX",
	".CFE", ".CFFEX",
}

// NormalizeSymbol 把用户输入的代码转成 Tushare 可识别形态。
//
// 规则：
//   - 已含 ".XXXX" 的，CZCE → CZC，SHFE → SHF，CFFEX → CFE，GFEX → GFE
//   - 6 位纯数字：6/900 → .SH；0/3/200 → .SZ；4/8/920 → .BJ
//   - 否则原样返回
func NormalizeSymbol(input string) string {
	s := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(input), " ", ""))
	if s == "" {
		return ""
	}
	if strings.Contains(s, ".") {
		switch {
		case strings.HasSuffix(s, ".CZCE"):
			return s[:len(s)-1]
		case strings.HasSuffix(s, ".SHFE"):
			return s[:len(s)-5] + ".SHF"
		case strings.HasSuffix(s, ".GFEX"):
			return s[:len(s)-5] + ".GFE"
		case strings.HasSuffix(s, ".CFFEX"):
			return s[:len(s)-6] + ".CFE"
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
	case strings.HasSuffix(u, ".CZC") || strings.HasSuffix(u, ".CZCE"):
		return "郑商所"
	case strings.HasSuffix(u, ".DCE"):
		return "大商所"
	case strings.HasSuffix(u, ".SHF") || strings.HasSuffix(u, ".SHFE"):
		return "上期所"
	case strings.HasSuffix(u, ".INE"):
		return "上海能源"
	case strings.HasSuffix(u, ".GFE") || strings.HasSuffix(u, ".GFEX"):
		return "广期所"
	case strings.HasSuffix(u, ".CFE") || strings.HasSuffix(u, ".CFFEX"):
		return "中金所"
	}
	return ""
}
