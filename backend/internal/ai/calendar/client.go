// Package calendar 对接百度股市通财经日历，提供全球经济数据发布日程
// （非农 / CPI / 议息 / GDP 等的公布时间、重要性、前值 / 预期 / 公布值）。
//
// 数据源：https://finance.pae.baidu.com/sapi/v1/financecalendar
//   - 境内可达（阿里云生产出口稳定，不像 GDELT/海外源被墙）；
//   - 无需 cookie / token，直连即返回结构化 JSON；
//   - 同 akshare news_economic_baidu 的底层接口，字段一致。
package calendar

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const calendarURL = "https://finance.pae.baidu.com/sapi/v1/financecalendar"

// Event 是一条经济数据发布事件。
//
// 数值字段（Previous/Forecast/Actual）保留字符串原样，以兼容带单位 / 空值 /
// 区间（如 "3.2%"、"-"、"125"）的情况，交给上层 / 模型理解。
type Event struct {
	Date     string `json:"date"`               // 2026-06-06
	Time     string `json:"time"`               // 20:30（北京时间）
	Region   string `json:"region"`             // 美国 / 欧元区 / 中国
	Title    string `json:"title"`              // 美国5月非农就业人口
	Star     int    `json:"star"`               // 重要性 1~3（越大越重要）
	Previous string `json:"previous,omitempty"` // 前值
	Forecast string `json:"forecast,omitempty"` // 预期
	Actual   string `json:"actual,omitempty"`   // 公布值（未公布为空）
	Period   string `json:"period,omitempty"`   // 统计周期
}

// Client 持有 *http.Client + 短期缓存。
type Client struct {
	httpc *http.Client
	cache *ttlCache[[]Event]
}

// New 默认 timeout 10s（百度接口国内 < 300ms）。缓存 TTL 5 分钟：
// 日历当天会随数据公布回填 Actual，5 分钟新鲜度足够，又能吸收高频重复请求。
func New(timeoutSec int) *Client {
	if timeoutSec <= 0 {
		timeoutSec = 10
	}
	return &Client{
		httpc: &http.Client{Timeout: time.Duration(timeoutSec) * time.Second},
		cache: newTTLCache[[]Event](5 * time.Minute),
	}
}

// FetchEconomicCalendar 拉 [startDate, endDate] 区间的经济数据日历。
//
// 日期格式 YYYY-MM-DD。返回按时间排序的事件，跨多天时合并所有天。
func (c *Client) FetchEconomicCalendar(ctx context.Context, startDate, endDate string) ([]Event, error) {
	key := startDate + "~" + endDate
	return c.cache.Do(key, func() ([]Event, error) {
		return c.fetch(ctx, startDate, endDate)
	})
}

func (c *Client) fetch(ctx context.Context, startDate, endDate string) ([]Event, error) {
	q := url.Values{}
	q.Set("start_date", startDate)
	q.Set("end_date", endDate)
	q.Set("pn", "0")
	q.Set("rn", "200")
	q.Set("cate", "economic_data")
	q.Set("finClientType", "pc")
	u := calendarURL + "?" + q.Encode()

	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("Accept", "application/vnd.finance-web.v1+json")
	req.Header.Set("Referer", "https://finance.baidu.com/")
	req.Header.Set("Origin", "https://finance.baidu.com")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "+
		"(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("baidu calendar http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("baidu calendar %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Result struct {
			CalendarInfo []struct {
				Date string `json:"date"`
				List []struct {
					Date        string `json:"date"`
					Time        string `json:"time"`
					Title       string `json:"title"`
					Region      string `json:"region"`
					Star        string `json:"star"`
					FormerVal   string `json:"formerVal"`
					IndicateVal string `json:"indicateVal"`
					PubVal      string `json:"pubVal"`
					TimePeriod  string `json:"timePeriod"`
				} `json:"list"`
			} `json:"calendarInfo"`
		} `json:"Result"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("baidu calendar parse: %w", err)
	}
	out := make([]Event, 0, 64)
	for _, day := range r.Result.CalendarInfo {
		for _, it := range day.List {
			out = append(out, Event{
				Date:     it.Date,
				Time:     it.Time,
				Region:   it.Region,
				Title:    it.Title,
				Star:     atoiSafe(it.Star),
				Previous: cleanVal(it.FormerVal),
				Forecast: cleanVal(it.IndicateVal),
				Actual:   cleanVal(it.PubVal),
				Period:   strings.TrimSpace(it.TimePeriod),
			})
		}
	}
	return out, nil
}

// cleanVal 归一空占位（百度用 "" / "-" 表示缺省）。
func cleanVal(s string) string {
	s = strings.TrimSpace(s)
	if s == "" || s == "-" || s == "--" {
		return ""
	}
	return s
}

func atoiSafe(s string) int {
	n := 0
	for _, ch := range strings.TrimSpace(s) {
		if ch < '0' || ch > '9' {
			return n
		}
		n = n*10 + int(ch-'0')
	}
	return n
}

// ── 短期缓存（泛型 TTL + 单飞）──────────────────────────────────────────

type ttlCache[V any] struct {
	ttl      time.Duration
	mu       sync.Mutex
	items    map[string]cacheEntry[V]
	inflight map[string]*cacheCall[V]
}

type cacheEntry[V any] struct {
	val    V
	expire time.Time
}

type cacheCall[V any] struct {
	done chan struct{}
	val  V
	err  error
}

func newTTLCache[V any](ttl time.Duration) *ttlCache[V] {
	return &ttlCache[V]{
		ttl:      ttl,
		items:    make(map[string]cacheEntry[V]),
		inflight: make(map[string]*cacheCall[V]),
	}
}

func (c *ttlCache[V]) Do(key string, load func() (V, error)) (V, error) {
	c.mu.Lock()
	if e, ok := c.items[key]; ok && time.Now().Before(e.expire) {
		c.mu.Unlock()
		return e.val, nil
	}
	if call, ok := c.inflight[key]; ok {
		c.mu.Unlock()
		<-call.done
		return call.val, call.err
	}
	call := &cacheCall[V]{done: make(chan struct{})}
	c.inflight[key] = call
	c.mu.Unlock()

	call.val, call.err = load()

	c.mu.Lock()
	if call.err == nil {
		c.items[key] = cacheEntry[V]{val: call.val, expire: time.Now().Add(c.ttl)}
	}
	delete(c.inflight, key)
	c.mu.Unlock()
	close(call.done)
	return call.val, call.err
}
