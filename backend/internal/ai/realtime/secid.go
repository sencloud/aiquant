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
