package realtime

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
)

// 本文件实现「全球行情」的标的解析(symbol → 东财 secid)与对外取数方法。
//
// 设计（便于后续不断扩展）：
//   - secMeta + SecIDResolver 抽象出「把用户输入解析成 secid」这一步（策略模式）；
//   - 当前内置三类解析器：美股(走 suggest 在线解析) / 全球指数(静态表) / 外汇(静态表)；
//   - 新增港股、加密、伦敦金等市场时，只要再加一个 resolver + 一个薄取数方法即可，
//     底层 emStockGet / decodeGlobalQuote / 缓存全部复用。

// secMeta 是标的解析结果。
type secMeta struct {
	SecID    string // 105.AAPL
	Name     string // 苹果
	Classify string // UsStock / Index / Forex …
}

// ── 静态映射表（已在生产实测可用的 secid）──────────────────────────────

// indexSecID 主流全球指数别名 → 东财 secid（mkt=100）。
var indexSecID = map[string]string{
	"DJIA": "100.DJIA", "道指": "100.DJIA", "道琼斯": "100.DJIA",
	"SPX": "100.SPX", "标普": "100.SPX", "标普500": "100.SPX",
	"NDX": "100.NDX", "IXIC": "100.NDX", "纳指": "100.NDX", "纳斯达克": "100.NDX",
	"HSI": "100.HSI", "恒生": "100.HSI", "恒生指数": "100.HSI",
	"N225": "100.N225", "日经": "100.N225", "日经225": "100.N225",
	"GDAXI": "100.GDAXI", "DAX": "100.GDAXI", "德指": "100.GDAXI",
	"FTSE": "100.FTSE", "富时": "100.FTSE", "英国富时100": "100.FTSE",
	"UDI": "100.UDI", "DXY": "100.UDI", "美元指数": "100.UDI",
}

// defaultGlobalIndexes 是 get_global_index 不传参时的默认快照集合。
var defaultGlobalIndexes = []string{"DJIA", "SPX", "NDX", "HSI", "N225", "GDAXI", "FTSE", "UDI"}

// forexSecID 主流货币对别名 → 东财 secid（各货币对 mkt 不同，已实测）。
var forexSecID = map[string]string{
	"USDCNH": "133.USDCNH", "美元离岸人民币": "133.USDCNH", "离岸人民币": "133.USDCNH",
	"USDCNYC": "120.USDCNYC", "USDCNY": "120.USDCNYC", "人民币中间价": "120.USDCNYC",
	"EURUSD": "119.EURUSD", "欧元美元": "119.EURUSD",
	"USDJPY": "119.USDJPY", "美元日元": "119.USDJPY",
	"GBPUSD": "119.GBPUSD", "英镑美元": "119.GBPUSD",
	"AUDUSD": "119.AUDUSD", "澳元美元": "119.AUDUSD",
	"USDCAD": "119.USDCAD", "USDCHF": "119.USDCHF",
	"UDI": "100.UDI", "美元指数": "100.UDI",
}

// defaultForexPairs 是 get_forex_rate 不传参时的默认货币对集合。
var defaultForexPairs = []string{"UDI", "USDCNH", "USDCNYC", "EURUSD", "USDJPY", "GBPUSD"}

// ── 取数公开方法 ───────────────────────────────────────────────────────

// FetchUSStock 拉单支美股实时快照。symbol 用美股代码（AAPL / MSFT / BABA / BRK.A）。
func (c *Client) FetchUSStock(ctx context.Context, symbol string) (*GlobalQuote, error) {
	meta, err := c.resolveUSSecID(ctx, symbol)
	if err != nil {
		return nil, err
	}
	q, err := c.fetchGlobalCached(ctx, meta.SecID, "us")
	if err != nil {
		return nil, err
	}
	if meta.Name != "" {
		q.Name = meta.Name
	}
	return q, nil
}

// FetchUSBatch 并发批量拉多支美股快照（失败项静默丢弃，按入参顺序返回）。
func (c *Client) FetchUSBatch(ctx context.Context, symbols []string) ([]GlobalQuote, error) {
	return c.fetchGlobalBatch(ctx, symbols, func(s string) (*GlobalQuote, error) {
		return c.FetchUSStock(ctx, s)
	})
}

// FetchGlobalIndex 拉单个全球指数快照（别名见 indexSecID）。
func (c *Client) FetchGlobalIndex(ctx context.Context, alias string) (*GlobalQuote, error) {
	secid := lookupSecID(indexSecID, alias)
	if secid == "" {
		return nil, fmt.Errorf("unsupported global index: %s", alias)
	}
	return c.fetchGlobalCached(ctx, secid, "index")
}

// FetchGlobalIndexes 并发批量拉多个全球指数；aliases 为空时用默认主流集合。
func (c *Client) FetchGlobalIndexes(ctx context.Context, aliases []string) ([]GlobalQuote, error) {
	if len(aliases) == 0 {
		aliases = defaultGlobalIndexes
	}
	return c.fetchGlobalBatch(ctx, aliases, func(s string) (*GlobalQuote, error) {
		return c.FetchGlobalIndex(ctx, s)
	})
}

// FetchForex 拉单个货币对 / 美元指数快照（别名见 forexSecID）。
func (c *Client) FetchForex(ctx context.Context, pair string) (*GlobalQuote, error) {
	secid := lookupSecID(forexSecID, pair)
	if secid == "" {
		return nil, fmt.Errorf("unsupported forex pair: %s", pair)
	}
	return c.fetchGlobalCached(ctx, secid, "forex")
}

// FetchForexBatch 并发批量拉多个货币对；pairs 为空时用默认集合。
func (c *Client) FetchForexBatch(ctx context.Context, pairs []string) ([]GlobalQuote, error) {
	if len(pairs) == 0 {
		pairs = defaultForexPairs
	}
	return c.fetchGlobalBatch(ctx, pairs, func(s string) (*GlobalQuote, error) {
		return c.FetchForex(ctx, s)
	})
}

// ── 内部公共逻辑 ───────────────────────────────────────────────────────

// fetchGlobalCached 带短 TTL 缓存的快照取数（按 secid 去重，吸收高频重复请求）。
func (c *Client) fetchGlobalCached(ctx context.Context, secid, market string) (*GlobalQuote, error) {
	return c.quoteCache.Do(secid, func() (*GlobalQuote, error) {
		data, err := c.emStockGet(ctx, secid, globalQuoteFields)
		if err != nil {
			return nil, err
		}
		return decodeGlobalQuote(secid, market, data), nil
	})
}

// fetchGlobalBatch 把单标的取数函数并发跑成批量（并发上限 8，借缓存自动去重）。
func (c *Client) fetchGlobalBatch(ctx context.Context, inputs []string, one func(string) (*GlobalQuote, error)) ([]GlobalQuote, error) {
	codes := make([]string, 0, len(inputs))
	for _, s := range inputs {
		if s = strings.TrimSpace(s); s != "" {
			codes = append(codes, s)
		}
	}
	if len(codes) == 0 {
		return nil, fmt.Errorf("no valid symbols")
	}
	res := make([]*GlobalQuote, len(codes))
	sem := make(chan struct{}, 8)
	var wg sync.WaitGroup
	for i, code := range codes {
		wg.Add(1)
		go func(i int, code string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if q, err := one(code); err == nil {
				res[i] = q
			}
		}(i, code)
	}
	wg.Wait()
	out := make([]GlobalQuote, 0, len(res))
	for _, q := range res {
		if q != nil {
			out = append(out, *q)
		}
	}
	return out, nil
}

// lookupSecID 在静态表里大小写不敏感地查 secid（中文键 ToUpper 无副作用）。
func lookupSecID(table map[string]string, alias string) string {
	return table[strings.ToUpper(strings.TrimSpace(alias))]
}

// ── 美股 secid 在线解析（东财 suggest，带长 TTL 缓存）─────────────────

const emSuggestURL = "https://searchapi.eastmoney.com/api/suggest/get"

// emSuggestToken 是东财 suggest 接口的公开 web token（前端硬编码，长期稳定）。
const emSuggestToken = "D43BF722C8E33BDC906FB84D85E326E8"

// resolveUSSecID 把美股代码解析成 secid（105/106/107.<code>）。
//
// 走东财 suggest 接口在线判市场（NASDAQ→105 / NYSE→106 / AMEX→107），
// 自动处理 BRK.A→BRK_A 这类点号差异。结果按 6 小时 TTL 缓存（符号→市场基本不变）。
func (c *Client) resolveUSSecID(ctx context.Context, symbol string) (secMeta, error) {
	in := strings.ToUpper(strings.TrimSpace(symbol))
	if in == "" {
		return secMeta{}, fmt.Errorf("empty us symbol")
	}
	return c.secidCache.Do("us:"+in, func() (secMeta, error) {
		return c.fetchUSSecID(ctx, in)
	})
}

func (c *Client) fetchUSSecID(ctx context.Context, input string) (secMeta, error) {
	q := url.Values{}
	q.Set("input", input)
	q.Set("type", "14")
	q.Set("token", emSuggestToken)
	q.Set("count", "10")
	u := emSuggestURL + "?" + q.Encode()
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://quote.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return secMeta{}, fmt.Errorf("eastmoney suggest http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return secMeta{}, fmt.Errorf("eastmoney suggest %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return secMeta{}, err
	}
	var r struct {
		QuotationCodeTable struct {
			Data []struct {
				Code     string `json:"Code"`
				Name     string `json:"Name"`
				Classify string `json:"Classify"`
				QuoteID  string `json:"QuoteID"`
			} `json:"Data"`
		} `json:"QuotationCodeTable"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return secMeta{}, fmt.Errorf("eastmoney suggest parse: %w", err)
	}
	rows := r.QuotationCodeTable.Data
	// 优先：Classify==UsStock 且 Code 精确匹配；否则首个 UsStock。
	var fallback *secMeta
	for i := range rows {
		row := rows[i]
		if row.Classify != "UsStock" || row.QuoteID == "" {
			continue
		}
		m := secMeta{SecID: row.QuoteID, Name: row.Name, Classify: row.Classify}
		if strings.EqualFold(row.Code, input) {
			return m, nil
		}
		if fallback == nil {
			mm := m
			fallback = &mm
		}
	}
	if fallback != nil {
		return *fallback, nil
	}
	return secMeta{}, fmt.Errorf("未找到美股代码 %s（请确认是美股上市代码，如 AAPL / MSFT / BABA）", input)
}
