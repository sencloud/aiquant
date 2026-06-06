package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
)

// emQuoteHost 是东财 push2 行情根地址。
//
// 用 push2delay 而非 push2：后者 CNAME 到 Azure trafficmanager，在阿里云生产出口
// TLS 握手会被重置（unexpected eof）；push2delay 解析到另一组可达 IP，同一套 API、
// 字段一致（延迟行情，海外标的场景可接受）。详见 client.go 的策略说明。
const emQuoteHost = "https://push2delay.eastmoney.com"

// GlobalQuote 是东财 push2 stock/get 的统一快照模型，覆盖
// 美股 / 全球指数 / 外汇 / 港股等所有走 stock/get 的标的。
//
// 价格已按 f59 小数位还原成真实报价，涨跌幅已转百分比。
// 不同市场的部分字段可能缺省（指数无成交额、外汇无量），缺省时为 0 并 omitempty。
type GlobalQuote struct {
	Symbol   string  `json:"symbol"`   // 东财代码（AAPL / DJIA / USDCNH）
	SecID    string  `json:"secid"`    // 东财 secid（105.AAPL）
	Name     string  `json:"name"`     // 中文名（苹果 / 道琼斯）
	Market   string  `json:"market"`   // us / index / forex（调用方注入的市场标签）
	Last     float64 `json:"last"`     // 最新价
	PctChg   float64 `json:"pct_chg"`  // 涨跌幅 %
	Change   float64 `json:"change"`   // 涨跌额
	Open     float64 `json:"open"`
	High     float64 `json:"high"`
	Low      float64 `json:"low"`
	PreClose float64 `json:"pre_close"`
	Volume   int64   `json:"volume,omitempty"`
	Amount   float64 `json:"amount,omitempty"`
	Delayed  bool    `json:"delayed"`
}

// globalQuoteFields 是 stock/get 拉全球标的需要的字段集。
var globalQuoteFields = []string{
	"f43", "f44", "f45", "f46", "f47", "f48",
	"f57", "f58", "f59", "f60", "f169", "f170", "f1",
}

// emStockGet 是东财 push2 stock/get 的底层取数，所有 secid 通用。
//
// 这是「全球行情」复用的唯一出网入口：美股 / 指数 / 外汇 / 港股的取数方法都建在它之上，
// 后续新增任何走 stock/get 的市场只要给出 secid 即可，无需重复写 HTTP / 解析骨架。
func (c *Client) emStockGet(ctx context.Context, secid string, fields []string) (map[string]any, error) {
	u := emQuoteHost + "/api/qt/stock/get?secid=" + secid + "&fields=" + strings.Join(fields, ",")
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney stock/get http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("eastmoney stock/get %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney stock/get parse: %w", err)
	}
	if r.Data == nil || asString(r.Data["f57"]) == "" {
		return nil, fmt.Errorf("eastmoney stock/get empty for %s（代码错误或该标的不支持）", secid)
	}
	return r.Data, nil
}

// decodeGlobalQuote 把 stock/get 的 data 解码成 GlobalQuote。
//
// 价格还原与期货一致：raw / 10^f59。AAPL(f59=3) 307340 → 307.340；
// BRK_A(f59=2) 73355000 → 733550.00；USDCNH(f59=4) 67910 → 6.7910。
func decodeGlobalQuote(secid, market string, data map[string]any) *GlobalQuote {
	decimals := int(asInt(data["f59"]))
	if decimals < 0 || decimals > 6 {
		decimals = 2
	}
	div := math.Pow10(decimals)
	if div <= 0 {
		div = 1
	}
	scale := func(v any) float64 {
		i := asInt(v)
		if i == 0 {
			return 0
		}
		return float64(i) / div
	}
	return &GlobalQuote{
		Symbol:   asString(data["f57"]),
		SecID:    secid,
		Name:     asString(data["f58"]),
		Market:   market,
		Last:     scale(data["f43"]),
		High:     scale(data["f44"]),
		Low:      scale(data["f45"]),
		Open:     scale(data["f46"]),
		Volume:   asInt(data["f47"]),
		Amount:   asFloat(data["f48"]),
		PreClose: scale(data["f60"]),
		Change:   scale(data["f169"]),
		PctChg:   toPercent(asInt(data["f170"])),
		Delayed:  asInt(data["f1"]) > 1,
	}
}
