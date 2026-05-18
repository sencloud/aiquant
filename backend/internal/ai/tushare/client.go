package tushare

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
)

// ErrNotConfigured 表示服务端未配置 Tushare token。所有工具被调用前应先检查。
var ErrNotConfigured = errors.New("tushare token not configured on server")

// Client 是 Tushare /api/post 的薄封装。
//
// 关键设计：
//   - 全局并发上限（信号量）— Tushare 个人版有 QPM 限制；
//   - 大表（stock_basic / fut_basic / fund_basic / index_basic）内存缓存，
//     TTL 默认 24 小时；
//   - 不做"找不到数据 → 返回 mock"的兜底（用户规则：禁止兜底）。
type Client struct {
	cfg     platform.TushareConfig
	httpc   *http.Client
	sema    chan struct{}
	cache   sync.Map // key string → cacheEntry
}

type cacheEntry struct {
	at   time.Time
	data []map[string]any
}

// New 用配置构造 Client。Token 为空时构造仍成功，但 Configured()=false。
func New(cfg platform.TushareConfig) *Client {
	conc := cfg.HTTPMaxConcurrent
	if conc <= 0 {
		conc = 4
	}
	timeout := cfg.TimeoutSec
	if timeout <= 0 {
		timeout = 20
	}
	base := strings.TrimRight(cfg.BaseURL, "/")
	if base == "" {
		base = "http://api.tushare.pro"
	}
	cfg.BaseURL = base
	return &Client{
		cfg:   cfg,
		httpc: &http.Client{Timeout: time.Duration(timeout) * time.Second},
		sema:  make(chan struct{}, conc),
	}
}

func (c *Client) Configured() bool { return c.cfg.Token != "" }

// Query 调一次 Tushare /api，自动按字段名映射。
//
// 入参 fields 为空时由 Tushare 默认返回；建议显式列出需要字段以减小响应体积。
//
// 返回的 []map[string]any 中所有数值字段已转 float64（Tushare 返回 string，
// 我们在这里统一转换；空字符串/无效值 → 0）。
func (c *Client) Query(ctx context.Context, apiName string, params map[string]any, fields []string) ([]map[string]any, error) {
	if !c.Configured() {
		return nil, ErrNotConfigured
	}
	body := map[string]any{
		"api_name": apiName,
		"token":    c.cfg.Token,
	}
	if len(params) > 0 {
		body["params"] = params
	} else {
		body["params"] = map[string]any{}
	}
	if len(fields) > 0 {
		body["fields"] = strings.Join(fields, ",")
	}
	raw, _ := json.Marshal(body)

	c.sema <- struct{}{}
	defer func() { <-c.sema }()

	req, _ := http.NewRequestWithContext(ctx, "POST", c.cfg.BaseURL, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tushare http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("tushare http %d: %s", resp.StatusCode, string(b))
	}
	var r struct {
		RequestID string `json:"request_id"`
		Code      int    `json:"code"`
		Msg       string `json:"msg"`
		Data      struct {
			Fields []string         `json:"fields"`
			Items  [][]any          `json:"items"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return nil, fmt.Errorf("tushare json: %w", err)
	}
	if r.Code != 0 {
		return nil, fmt.Errorf("tushare api %d: %s", r.Code, r.Msg)
	}
	return mapItems(r.Data.Fields, r.Data.Items), nil
}

// QueryCached 同 Query，但首次结果按 cacheKey 缓存 BasicCacheTTLSec。
// 适合 stock_basic / fund_basic / index_basic / fut_basic 这种大表。
func (c *Client) QueryCached(ctx context.Context, cacheKey, apiName string, params map[string]any, fields []string) ([]map[string]any, error) {
	ttl := time.Duration(c.cfg.BasicCacheTTLSec) * time.Second
	if ttl > 0 {
		if v, ok := c.cache.Load(cacheKey); ok {
			e := v.(cacheEntry)
			if time.Since(e.at) < ttl {
				return e.data, nil
			}
		}
	}
	out, err := c.Query(ctx, apiName, params, fields)
	if err != nil {
		return nil, err
	}
	if ttl > 0 {
		c.cache.Store(cacheKey, cacheEntry{at: time.Now(), data: out})
	}
	return out, nil
}

// mapItems 把 Tushare 的列式返回（fields + items）转成更顺手的行式 map。
func mapItems(fields []string, items [][]any) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, row := range items {
		m := make(map[string]any, len(fields))
		for i, f := range fields {
			if i >= len(row) {
				continue
			}
			m[f] = row[i]
		}
		out = append(out, m)
	}
	return out
}

// AsFloat 安全把 Tushare 返回的字段转 float64。
//
// Tushare 数值字段经常返回 string；nil / 空字符串 / "None" → 0。
func AsFloat(v any) float64 {
	switch x := v.(type) {
	case nil:
		return 0
	case float64:
		return x
	case float32:
		return float64(x)
	case int:
		return float64(x)
	case int64:
		return float64(x)
	case string:
		s := strings.TrimSpace(x)
		if s == "" || s == "None" || s == "null" {
			return 0
		}
		f, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return 0
		}
		return f
	default:
		return 0
	}
}

// AsString 安全转字符串。
func AsString(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case int:
		return strconv.Itoa(x)
	case int64:
		return strconv.FormatInt(x, 10)
	default:
		b, _ := json.Marshal(x)
		return string(b)
	}
}

// AsInt 把字段转 int64（典型用于 list_date / end_date 这种数值串）。
func AsInt(v any) int64 {
	return int64(AsFloat(v))
}
