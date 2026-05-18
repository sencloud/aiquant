package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Quote 是单标的实时行情快照（A 股 / ETF / 指数）。
//
// 所有价格已转换为「元」，涨跌幅已转换为「百分比」。
// PreClose 缺失（指数）时为 0；ETF 不一定有 TurnoverRate。
type Quote struct {
	Code         string  `json:"code"`         // 6 位代码
	TsCode       string  `json:"ts_code"`      // 标准化形态：600519.SH
	Name         string  `json:"name"`
	Last         float64 `json:"last"`         // 最新价
	PctChg       float64 `json:"pct_chg"`      // 当日涨跌幅 %
	Change       float64 `json:"change"`       // 涨跌额
	Open         float64 `json:"open"`
	High         float64 `json:"high"`
	Low          float64 `json:"low"`
	PreClose     float64 `json:"pre_close"`
	Volume       int64   `json:"volume"`       // 手 (股票) / 张 (期货)
	Amount       float64 `json:"amount"`       // 成交额 元
	TurnoverRate float64 `json:"turnover_rate,omitempty"` // %
	PE           float64 `json:"pe,omitempty"` // TTM
	Delayed      bool    `json:"delayed"`      // 延时报价
}

// FetchSnapshot 拉单标的实时报价。
//
// 端点：https://push2.eastmoney.com/api/qt/stock/get?secid=<m.code>
func (c *Client) FetchSnapshot(ctx context.Context, symbol string) (*Quote, error) {
	secid := ToSecID(symbol)
	if secid == "" {
		// 指数兜底（NormalizeSymbol 已带后缀的指数）
		secid = IndexSecID[strings.ToUpper(symbol)]
	}
	if secid == "" {
		return nil, fmt.Errorf("unsupported symbol for realtime: %s", symbol)
	}
	u := "https://push2.eastmoney.com/api/qt/stock/get" +
		"?secid=" + secid +
		"&fields=" + strings.Join([]string{
			"f43", "f44", "f45", "f46", "f47", "f48",
			"f57", "f58", "f60", "f168", "f169", "f170",
			"f152", "f162", "f1",
		}, ",")
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney snapshot http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("eastmoney snapshot %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney snapshot parse: %w", err)
	}
	if r.Data == nil {
		return nil, fmt.Errorf("eastmoney snapshot empty data for %s", symbol)
	}
	q := &Quote{
		Code:     asString(r.Data["f57"]),
		Name:     asString(r.Data["f58"]),
		Last:     toRMB(asInt(r.Data["f43"])),
		High:     toRMB(asInt(r.Data["f44"])),
		Low:      toRMB(asInt(r.Data["f45"])),
		Open:     toRMB(asInt(r.Data["f46"])),
		Volume:   asInt(r.Data["f47"]),
		Amount:   asFloat(r.Data["f48"]),
		PreClose: toRMB(asInt(r.Data["f60"])),
		PctChg:   toPercent(asInt(r.Data["f170"])),
		Change:   toRMB(asInt(r.Data["f169"])),
		PE:       float64(asInt(r.Data["f162"])) / 100.0,
		TurnoverRate: float64(asInt(r.Data["f168"])) / 100.0,
		Delayed:  asInt(r.Data["f1"]) > 1,
	}
	q.TsCode = restoreTsCode(secid, q.Code)
	return q, nil
}

// FetchIndexes 批量拉指数实时（沪深300/上证50/中证500/创业板等）。
//
// 端点：ulist.np/get?secids=1.000300,1.000016,...
func (c *Client) FetchIndexes(ctx context.Context, tsCodes []string) ([]Quote, error) {
	secids := make([]string, 0, len(tsCodes))
	codeBack := map[string]string{} // secid → ts_code
	for _, ts := range tsCodes {
		sid, ok := IndexSecID[strings.ToUpper(strings.TrimSpace(ts))]
		if !ok {
			sid = ToSecID(ts)
		}
		if sid != "" {
			secids = append(secids, sid)
			codeBack[sid] = strings.ToUpper(strings.TrimSpace(ts))
		}
	}
	if len(secids) == 0 {
		return nil, fmt.Errorf("no valid secid")
	}
	u := "https://push2.eastmoney.com/api/qt/ulist.np/get" +
		"?secids=" + strings.Join(secids, ",") +
		"&fields=f1,f2,f3,f4,f12,f13,f14,f15,f16,f17,f18"
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney ulist http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("eastmoney ulist %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Data struct {
			Diff []map[string]any `json:"diff"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney ulist parse: %w", err)
	}
	out := make([]Quote, 0, len(r.Data.Diff))
	for _, m := range r.Data.Diff {
		mkt := asInt(m["f13"])
		code := asString(m["f12"])
		secid := fmt.Sprintf("%d.%s", mkt, code)
		ts := codeBack[secid]
		if ts == "" {
			ts = restoreTsCode(secid, code)
		}
		q := Quote{
			Code:     code,
			Name:     asString(m["f14"]),
			Last:     toRMB(asInt(m["f2"])),
			PctChg:   toPercent(asInt(m["f3"])),
			Change:   toRMB(asInt(m["f4"])),
			High:     toRMB(asInt(m["f15"])),
			Low:      toRMB(asInt(m["f16"])),
			Open:     toRMB(asInt(m["f17"])),
			PreClose: toRMB(asInt(m["f18"])),
			TsCode:   ts,
			Delayed:  asInt(m["f1"]) > 1,
		}
		out = append(out, q)
	}
	return out, nil
}

func restoreTsCode(secid, code string) string {
	if strings.HasPrefix(secid, "1.") {
		return code + ".SH"
	}
	if strings.HasPrefix(secid, "0.") {
		return code + ".SZ"
	}
	return code
}

func asInt(v any) int64 {
	switch x := v.(type) {
	case float64:
		return int64(x)
	case int64:
		return x
	case int:
		return int64(x)
	case string:
		var n int64
		neg := false
		s := x
		if strings.HasPrefix(s, "-") {
			neg = true
			s = s[1:]
		}
		for _, ch := range s {
			if ch < '0' || ch > '9' {
				return 0
			}
			n = n*10 + int64(ch-'0')
		}
		if neg {
			return -n
		}
		return n
	}
	return 0
}

func asFloat(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case int64:
		return float64(x)
	case int:
		return float64(x)
	}
	return 0
}

func asString(v any) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return fmt.Sprintf("%v", v)
}
