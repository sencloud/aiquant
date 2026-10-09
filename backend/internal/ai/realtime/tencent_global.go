package realtime

import (
	"context"
	"fmt"
	"strconv"
	"strings"
)

// 腾讯全球行情：美股 / 全球指数 / 外盘期货（含 CBOT 农产品）。
//
// 为什么必须有这一层：东财 push2 与 push2delay 在阿里云出口已整体不可达
// （TLS 握手完成后 unexpected eof），而原先的美股 / 全球指数 / 外汇全走东财，
// 表现为「海外数据一律拿不到」。腾讯 qt.gtimg.cn 在生产出口稳定可用，覆盖：
//
//	us<SYM>    美股个股     usAAPL
//	us<IDX>    全球指数     usDJI(道指) us.INX(标普500) usIXIC(纳指) usNDX(纳指100)
//	hkHSI      恒生指数
//	hf<CODE>   外盘期货     hf_S(大豆) hf_C(玉米) hf_W(小麦) hf_CL(原油) …
//
// 注意：腾讯不提供内盘期货（nf_/RB 等前缀全部 none_match），内盘期货只能退到
// Tushare 日线，见 tools 层的兜底实现。

// tencentIndexAlias 是全球指数别名到腾讯代码的映射。
var tencentIndexAlias = map[string]string{
	"DJIA": "usDJI", "道指": "usDJI", "道琼斯": "usDJI",
	"SPX": "us.INX", "标普": "us.INX", "标普500": "us.INX", "INX": "us.INX",
	"IXIC": "usIXIC", "纳指": "usIXIC", "纳斯达克": "usIXIC",
	"NDX": "usNDX", "纳斯达克100": "usNDX", "纳指100": "usNDX",
	"HSI": "hkHSI", "恒生": "hkHSI", "恒生指数": "hkHSI",
}

// tencentOverseasFuture 是外盘期货别名到腾讯代码的映射。
// 代码沿用新浪外盘约定（S=大豆 C=玉米 W=小麦 SM=豆粕 BO=豆油 CL=原油…），
// 腾讯 hf_ 前缀与之一致。
var tencentOverseasFuture = map[string]string{
	"S": "hf_S", "ZS": "hf_S", "大豆": "hf_S", "美豆": "hf_S", "CBOT大豆": "hf_S",
	"SM": "hf_SM", "豆粕": "hf_SM", "美豆粕": "hf_SM", "CBOT豆粕": "hf_SM",
	"BO": "hf_BO", "豆油": "hf_BO", "美豆油": "hf_BO",
	"C": "hf_C", "ZC": "hf_C", "玉米": "hf_C", "CBOT玉米": "hf_C",
	"W": "hf_W", "ZW": "hf_W", "小麦": "hf_W", "CBOT小麦": "hf_W",
	"CL": "hf_CL", "原油": "hf_CL", "WTI": "hf_CL", "NYMEX原油": "hf_CL",
	"NG": "hf_NG", "天然气": "hf_NG",
	"GC": "hf_GC", "黄金": "hf_GC", "COMEX黄金": "hf_GC",
	"SI": "hf_SI", "白银": "hf_SI", "COMEX白银": "hf_SI",
	"HG": "hf_HG", "铜": "hf_HG", "COMEX铜": "hf_HG",
	"LHC": "hf_LHC", "瘦肉猪": "hf_LHC",
}

// 注：腾讯 hf_ 不覆盖 ICE 软商品（原糖 SB / 棉花 CT / 咖啡 KC），
// 这几个品种目前没有可用的公开实时源，工具描述里也不承诺。

// OverseasFutureAliases 返回支持的外盘期货别名（供工具描述展示）。
func OverseasFutureAliases() []string {
	return []string{
		"大豆/S", "豆粕/SM", "豆油/BO", "玉米/C", "小麦/W", "瘦肉猪/LHC",
		"原油/CL", "天然气/NG",
		"黄金/GC", "白银/SI", "铜/HG",
	}
}

// ── 底层取数 ────────────────────────────────────────────────────────────

// fetchTencentOne 拉单个腾讯 symbol，返回 `~` 切分后的字段。
func (c *Client) fetchTencentOne(ctx context.Context, symbol string) ([]string, error) {
	rows, err := c.fetchTencentList(ctx, []string{symbol})
	if err != nil {
		return nil, err
	}
	fields, ok := rows[symbol]
	if !ok || len(fields) < 8 {
		return nil, fmt.Errorf("tencent: %s 无行情", symbol)
	}
	return fields, nil
}

// fetchTencentComma 拉逗号分隔的那类（hf_ 外盘期货）。
func (c *Client) fetchTencentComma(ctx context.Context, symbol string) ([]string, error) {
	// 注意：不能走 fetchTencentOne —— 它要求 `~` 切分后 ≥8 段，而 hf_ 是逗号格式，
	// `~` 切分只剩一段，会被误判成"无行情"。
	rows, err := c.fetchTencentList(ctx, []string{symbol})
	if err != nil {
		return nil, err
	}
	fields, ok := rows[symbol]
	if !ok || len(fields) == 0 {
		return nil, fmt.Errorf("tencent: %s 无行情", symbol)
	}
	// hf_ 的整段内容是 "511.25,-1.25,..."，`~` 切分后只剩一段。
	joined := strings.Join(fields, "~")
	if !strings.Contains(joined, ",") {
		return nil, fmt.Errorf("tencent: %s 行情格式异常", symbol)
	}
	return strings.Split(joined, ","), nil
}

// ── 解析 ────────────────────────────────────────────────────────────────

// parseTencentQuote 解析腾讯 `~` 格式（美股 / 全球指数与 A 股共用同一套字段位）。
//
// 字段位（0 起）：1 名称 2 代码 3 最新 4 昨收 5 今开 6 成交量
//
//	30 时间 31 涨跌额 32 涨跌幅% 33 最高 34 最低 36 成交量 37 成交额
func parseTencentQuote(symbol, market string, f []string) *GlobalQuote {
	if len(f) < 35 {
		return nil
	}
	q := &GlobalQuote{
		Symbol:   symbol,
		SecID:    symbol,
		Name:     fieldAt(f, 1),
		Market:   market,
		Last:     atof(fieldAt(f, 3)),
		PreClose: atof(fieldAt(f, 4)),
		Open:     atof(fieldAt(f, 5)),
		High:     atof(fieldAt(f, 33)),
		Low:      atof(fieldAt(f, 34)),
		Change:   atof(fieldAt(f, 31)),
		PctChg:   atof(fieldAt(f, 32)),
		Volume:   int64(atof(fieldAt(f, 36))),
		Amount:   atof(fieldAt(f, 37)),
		Delayed:  true, // 腾讯对海外标的普遍是延时行情，如实标记
	}
	if q.Last <= 0 {
		return nil
	}
	if q.PctChg == 0 && q.PreClose > 0 {
		q.PctChg = (q.Last/q.PreClose - 1) * 100
		q.Change = q.Last - q.PreClose
	}
	return q
}

// parseTencentOverseasFuture 解析 hf_ 外盘期货（新浪同款逗号格式）。
//
// 字段位：0 最新 1 涨跌额 2 买价 3 卖价 4 最高 5 最低 6 时间 7 昨收 8 开盘
func parseTencentOverseasFuture(symbol string, f []string) *GlobalQuote {
	if len(f) < 8 {
		return nil
	}
	q := &GlobalQuote{
		Symbol:   symbol,
		SecID:    symbol,
		Name:     symbol,
		Market:   "overseas_futures",
		Last:     atof(f[0]),
		Change:   atof(f[1]),
		High:     atof(f[4]),
		Low:      atof(f[5]),
		PreClose: atof(f[7]),
		Delayed:  true,
	}
	if len(f) > 8 {
		q.Open = atof(f[8])
	}
	if q.Last <= 0 {
		return nil
	}
	if q.PreClose > 0 {
		q.PctChg = (q.Last/q.PreClose - 1) * 100
		if q.Change == 0 {
			q.Change = q.Last - q.PreClose
		}
	}
	return q
}

func fieldAt(f []string, i int) string {
	if i < 0 || i >= len(f) {
		return ""
	}
	return strings.TrimSpace(f[i])
}

// atof 容忍空串与异常值；行情字段缺省一律当 0，不让单个坏字段毁掉整条报价。
func atof(s string) float64 {
	if s == "" || s == "-" {
		return 0
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return v
}

// lookupTencentAlias 大小写不敏感地查别名表。
func lookupTencentAlias(m map[string]string, in string) (string, bool) {
	s := strings.TrimSpace(in)
	if v, ok := m[s]; ok {
		return v, true
	}
	if v, ok := m[strings.ToUpper(s)]; ok {
		return v, true
	}
	return "", false
}

// ── 对外取数 ────────────────────────────────────────────────────────────

// FetchUSStockTencent 用腾讯拉美股实时快照（不依赖东财的 symbol 解析）。
func (c *Client) FetchUSStockTencent(ctx context.Context, symbol string) (*GlobalQuote, error) {
	sym := strings.ToUpper(strings.TrimSpace(symbol))
	if sym == "" {
		return nil, fmt.Errorf("empty us symbol")
	}
	// 用户可能直接给 AAPL / AAPL.OQ / usAAPL。
	sym = strings.TrimPrefix(sym, "US")
	if i := strings.IndexByte(sym, '.'); i > 0 {
		sym = sym[:i]
	}
	ts := "us" + sym
	f, err := c.fetchTencentOne(ctx, ts)
	if err != nil {
		return nil, err
	}
	q := parseTencentQuote(ts, "us", f)
	if q == nil {
		return nil, fmt.Errorf("tencent: 美股 %s 无有效行情", symbol)
	}
	q.Symbol = sym
	q.SecID = ts
	return q, nil
}

// FetchGlobalIndexTencent 用腾讯拉全球指数。
func (c *Client) FetchGlobalIndexTencent(ctx context.Context, alias string) (*GlobalQuote, error) {
	ts, ok := lookupTencentAlias(tencentIndexAlias, alias)
	if !ok {
		return nil, fmt.Errorf("unsupported global index: %s", alias)
	}
	f, err := c.fetchTencentOne(ctx, ts)
	if err != nil {
		return nil, err
	}
	q := parseTencentQuote(ts, "index", f)
	if q == nil {
		return nil, fmt.Errorf("tencent: 全球指数 %s 无有效行情", alias)
	}
	q.Symbol = strings.ToUpper(strings.TrimSpace(alias))
	q.SecID = ts
	return q, nil
}

// FetchOverseasFutures 拉外盘期货（CBOT 农产品 / 能源 / 金属）。
// aliases 支持中英文别名，如 大豆 / ZS / 玉米 / CL；为空时给一组默认值。
func (c *Client) FetchOverseasFutures(ctx context.Context, aliases []string) ([]GlobalQuote, error) {
	if len(aliases) == 0 {
		aliases = []string{"大豆", "玉米", "小麦", "豆粕", "原油", "黄金"}
	}
	out := make([]GlobalQuote, 0, len(aliases))
	var lastErr error
	for _, a := range aliases {
		ts, ok := lookupTencentAlias(tencentOverseasFuture, a)
		if !ok {
			lastErr = fmt.Errorf("不支持的外盘品种: %s", a)
			continue
		}
		f, err := c.fetchTencentComma(ctx, ts)
		if err != nil {
			lastErr = err
			continue
		}
		q := parseTencentOverseasFuture(ts, f)
		if q == nil {
			lastErr = fmt.Errorf("tencent: %s 无有效行情", a)
			continue
		}
		q.Symbol = strings.ToUpper(strings.TrimSpace(a))
		q.SecID = ts
		out = append(out, *q)
	}
	if len(out) == 0 {
		if lastErr != nil {
			return nil, lastErr
		}
		return nil, fmt.Errorf("外盘期货：未取到行情")
	}
	return out, nil
}
