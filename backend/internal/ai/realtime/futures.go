package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"sync"
)

// FuturesQuote 是单合约期货实时行情快照。
//
// 与股票 Quote 的差异：
//   - 期货独有 PreSettle（昨结算价）：日内涨跌幅按"昨结算"计，不是昨收；
//   - 期货独有 OI（持仓量）/ OIChg（持仓量变化）；
//   - 期货独有 Bid / Ask（买一卖一，部分非交易时段会为 0）；
//   - 价格统一已用 push2 字段 f59（小数位数）还原成"真实合约价"。
type FuturesQuote struct {
	Code      string  `json:"code"`      // 合约代码（如 RB2510 / IF2509 / sc2509）
	TsCode    string  `json:"ts_code"`   // 标准化 ts_code（RB2510.SHF）
	Name      string  `json:"name"`      // 合约中文名（如 螺纹钢2510）
	Exchange  string  `json:"exchange"`  // CFFEX / SHFE / DCE / CZCE / INE / GFEX
	Last      float64 `json:"last"`      // 最新价
	PctChg    float64 `json:"pct_chg"`   // 涨跌幅 %
	Change    float64 `json:"change"`    // 涨跌额
	Open      float64 `json:"open"`
	High      float64 `json:"high"`
	Low       float64 `json:"low"`
	PreClose  float64 `json:"pre_close,omitempty"`
	PreSettle float64 `json:"pre_settle"`
	Volume    int64   `json:"volume"`     // 成交量（手）
	Amount    float64 `json:"amount"`     // 成交额（元）
	OI        int64   `json:"oi"`         // 持仓量（手）
	Bid       float64 `json:"bid,omitempty"`
	Ask       float64 `json:"ask,omitempty"`
	Delayed   bool    `json:"delayed"`
}

// fetchFuturesSnapshotEM 拉单期货合约实时行情（东方财富 push2 实现）。
//
// 当前公开入口 FetchFuturesSnapshot 默认走新浪 hq.sinajs.cn（更稳定，详见 sina_futures.go）。
// 本函数保留为可切回的备用实现。
//
// 端点：https://push2.eastmoney.com/api/qt/stock/get?secid=<m.code>
// 字段：f43 最新 f44 高 f45 低 f46 开 f47 成交量 f48 成交额 f49 持仓量
//
//	f50 买一 f51 卖一 f57 代码 f58 名称 f59 价格小数位
//	f60 昨收 f161 昨结 f169 涨跌额(分?) f170 涨跌幅(‱)
//	f1 delay flag
//
// 价格还原：raw / 10^f59。RB(1 位) → raw 32450 / 10 = 3245；
// AU(2 位) → raw 56050 / 100 = 560.50；IF(1 位) → 38520 / 10 = 3852.0。
func (c *Client) fetchFuturesSnapshotEM(ctx context.Context, tsCode string) (*FuturesQuote, error) {
	secid := FuturesSecID(tsCode)
	if secid == "" {
		return nil, fmt.Errorf("invalid futures ts_code: %s", tsCode)
	}
	fields := []string{
		"f1", "f43", "f44", "f45", "f46", "f47", "f48", "f49",
		"f50", "f51", "f57", "f58", "f59", "f60", "f161", "f169", "f170",
	}
	u := "https://push2.eastmoney.com/api/qt/stock/get" +
		"?secid=" + secid +
		"&fields=" + strings.Join(fields, ",")
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney futures snapshot http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("eastmoney futures snapshot %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney futures snapshot parse: %w", err)
	}
	if r.Data == nil || asString(r.Data["f57"]) == "" {
		return nil, fmt.Errorf("eastmoney futures snapshot empty for %s（可能合约已退市或代码错误）", tsCode)
	}

	decimals := int(asInt(r.Data["f59"]))
	if decimals < 0 || decimals > 6 {
		decimals = 0
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

	q := &FuturesQuote{
		Code:      asString(r.Data["f57"]),
		Name:      asString(r.Data["f58"]),
		Last:      scale(r.Data["f43"]),
		High:      scale(r.Data["f44"]),
		Low:       scale(r.Data["f45"]),
		Open:      scale(r.Data["f46"]),
		Volume:    asInt(r.Data["f47"]),
		Amount:    asFloat(r.Data["f48"]),
		OI:        asInt(r.Data["f49"]),
		Bid:       scale(r.Data["f50"]),
		Ask:       scale(r.Data["f51"]),
		PreClose:  scale(r.Data["f60"]),
		PreSettle: scale(r.Data["f161"]),
		Change:    scale(r.Data["f169"]),
		PctChg:    toPercent(asInt(r.Data["f170"])),
		Delayed:   asInt(r.Data["f1"]) > 1,
	}
	q.TsCode = strings.ToUpper(tsCode)
	q.Exchange = futuresExchangeFromSecID(secid)
	return q, nil
}

// fetchFuturesBatchEM 并发批量拉多个合约实时行情（东方财富 push2 实现）。
//
// 当前公开入口 FetchFuturesBatch 默认走新浪 hq.sinajs.cn 的 list= 单次批量调用。
//
// push2 期货 ulist 不返回 f59（价格小数位），无法正确还原各品种价格，
// 因此走"并发调 fetchFuturesSnapshotEM"路径。并发上限 8，避免触发限流。
// 任何单合约失败被静默丢弃，结果按入参顺序返回。
func (c *Client) fetchFuturesBatchEM(ctx context.Context, tsCodes []string) ([]FuturesQuote, error) {
	codes := make([]string, 0, len(tsCodes))
	for _, s := range tsCodes {
		s = strings.TrimSpace(s)
		if s != "" {
			codes = append(codes, s)
		}
	}
	if len(codes) == 0 {
		return nil, fmt.Errorf("no valid ts_codes")
	}
	res := make([]*FuturesQuote, len(codes))
	sem := make(chan struct{}, 8)
	var wg sync.WaitGroup
	for i, code := range codes {
		wg.Add(1)
		go func(i int, code string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			q, err := c.fetchFuturesSnapshotEM(ctx, code)
			if err != nil {
				return
			}
			res[i] = q
		}(i, code)
	}
	wg.Wait()
	out := make([]FuturesQuote, 0, len(res))
	for _, q := range res {
		if q != nil {
			out = append(out, *q)
		}
	}
	return out, nil
}
