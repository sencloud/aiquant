package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Mover 是涨幅 / 跌幅榜的单条记录。
type Mover struct {
	Code         string  `json:"code"`
	TsCode       string  `json:"ts_code"`
	Name         string  `json:"name"`
	Last         float64 `json:"last"`
	PctChg       float64 `json:"pct_chg"`
	Change       float64 `json:"change"`
	Volume       int64   `json:"volume"`
	Amount       float64 `json:"amount"`
	TurnoverRate float64 `json:"turnover_rate,omitempty"`
}

// MoversOptions 控制 FetchTopMovers 行为。
type MoversOptions struct {
	// Direction：up = 涨幅榜，down = 跌幅榜。默认 up。
	Direction string
	// Scope：a / hs / sh / sz / cy / kc / 板块码（BK0478…）。
	//
	//   a/hs    ：沪深 A 股全部
	//   sh      ：仅沪市主板
	//   sz      ：仅深市主板
	//   cy      ：创业板
	//   kc      ：科创板
	//   板块码   ：直接 fs=b:<board>，对应行业 / 概念板块
	Scope string
	// BoardCode 当 Scope=board 时取该值（BK 开头）。
	BoardCode string
	// Limit 返回前 N 条（最多 100）。
	Limit int
}

// fsForScope 拼装东财 push2 的 fs 参数。
//
// 沪深 A 股全部：m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048
// 创业板：m:0+t:80
// 科创板：m:1+t:23
// 板块：b:BK0478
func fsForScope(scope, board string) string {
	scope = strings.ToLower(strings.TrimSpace(scope))
	switch scope {
	case "", "a", "hs", "all":
		return "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048"
	case "sh":
		return "m:1+t:2"
	case "sz":
		return "m:0+t:6"
	case "cy", "chinext":
		return "m:0+t:80"
	case "kc", "star":
		return "m:1+t:23"
	case "board", "industry":
		b := strings.ToUpper(strings.TrimSpace(board))
		if b == "" {
			return ""
		}
		return "b:" + b
	}
	if strings.HasPrefix(strings.ToUpper(scope), "BK") {
		return "b:" + strings.ToUpper(scope)
	}
	return "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048"
}

// FetchTopMovers 拉涨幅 / 跌幅榜。
//
// 端点：https://push2.eastmoney.com/api/qt/clist/get
// 关键参数 po：1=desc 2=asc；fid=f3 按涨跌幅排。
func (c *Client) FetchTopMovers(ctx context.Context, opt MoversOptions) ([]Mover, error) {
	limit := opt.Limit
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	po := "1"
	if strings.ToLower(opt.Direction) == "down" {
		po = "2"
	}
	fs := fsForScope(opt.Scope, opt.BoardCode)
	if fs == "" {
		return nil, fmt.Errorf("invalid scope/board")
	}
	u := fmt.Sprintf(
		"https://push2.eastmoney.com/api/qt/clist/get"+
			"?pn=1&pz=%d&po=%s&np=1&fid=f3"+
			"&fs=%s"+
			"&fields=f2,f3,f4,f5,f6,f8,f12,f13,f14",
		limit, po, fs,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney clist http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("eastmoney clist %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Data *struct {
			// diff 在不同上游版本里既可能是 array 也可能是 object（key 为序号字符串）。
			Diff json.RawMessage `json:"diff"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney clist parse: %w", err)
	}
	if r.Data == nil {
		return []Mover{}, nil
	}
	rows := decodeDiff(r.Data.Diff)
	out := make([]Mover, 0, len(rows))
	for _, m := range rows {
		mkt := asInt(m["f13"])
		code := asString(m["f12"])
		secid := fmt.Sprintf("%d.%s", mkt, code)
		out = append(out, Mover{
			Code:         code,
			TsCode:       restoreTsCode(secid, code),
			Name:         asString(m["f14"]),
			Last:         toRMB(asInt(m["f2"])),
			PctChg:       toPercent(asInt(m["f3"])),
			Change:       toRMB(asInt(m["f4"])),
			Volume:       asInt(m["f5"]),
			Amount:       asFloat(m["f6"]),
			TurnoverRate: toPercent(asInt(m["f8"])),
		})
	}
	return out, nil
}

// decodeDiff 兼容 array / object 两种 diff 形态。
//
//   array  → [ {...}, {...} ]
//   object → { "0": {...}, "1": {...} }
func decodeDiff(raw json.RawMessage) []map[string]any {
	if len(raw) == 0 {
		return nil
	}
	var arr []map[string]any
	if err := json.Unmarshal(raw, &arr); err == nil {
		return arr
	}
	var obj map[string]map[string]any
	if err := json.Unmarshal(raw, &obj); err == nil {
		out := make([]map[string]any, 0, len(obj))
		// 把 "0","1",... 排个序保证榜单顺序
		keys := make([]string, 0, len(obj))
		for k := range obj {
			keys = append(keys, k)
		}
		// 简单字符串顺序：东财本来就是 "0","1",...,"99"，需要数字序
		sortNumericKeys(keys)
		for _, k := range keys {
			out = append(out, obj[k])
		}
		return out
	}
	return nil
}

func sortNumericKeys(ss []string) {
	// 局部 insertion sort 按数值，量级 ≤ 100，不引第三方
	for i := 1; i < len(ss); i++ {
		j := i
		for j > 0 && atoiSafe(ss[j]) < atoiSafe(ss[j-1]) {
			ss[j], ss[j-1] = ss[j-1], ss[j]
			j--
		}
	}
}

func atoiSafe(s string) int {
	n := 0
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0
		}
		n = n*10 + int(ch-'0')
	}
	return n
}
