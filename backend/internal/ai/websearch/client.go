// Package websearch 封装 DeepSeek 官方联网搜索接口。
package websearch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Result 是搜索接口返回的一条网页结果。
type Result struct {
	RerankScore float64 `json:"rerank_score,omitempty"`
	Title       string  `json:"title"`
	URL         string  `json:"url"`
	Snippet     string  `json:"snippet,omitempty"`
	Summary     string  `json:"summary,omitempty"`
	Content     string  `json:"content,omitempty"`
	SiteName    string  `json:"site_name,omitempty"`
	SiteIcon    string  `json:"site_icon,omitempty"`
	Date        string  `json:"date,omitempty"`
	Authority   int     `json:"authority,omitempty"`
}

// Query 是一次联网搜索的入参。
type Query struct {
	Query       string
	Original    string
	Count       int
	NeedContent bool
	Localize    string
}

// Client 是 DeepSeek 搜索服务客户端。
type Client struct {
	apiKey    string
	endpoint  string
	httpc     *http.Client
	retryBase time.Duration
}

// New 创建一个搜索客户端。缺少 API key 时 Configured 返回 false。
func New(apiKey, baseURL string, timeout time.Duration) *Client {
	if timeout <= 0 {
		timeout = 20 * time.Second
	}
	base := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if base == "" {
		base = "https://api.deepseek.com"
	}
	endpoint := base + "/v1/tools/search"
	if strings.HasSuffix(base, "/v1") {
		endpoint = base + "/tools/search"
	}
	return &Client{
		apiKey:    strings.TrimSpace(apiKey),
		endpoint:  endpoint,
		httpc:     &http.Client{Timeout: timeout},
		retryBase: 150 * time.Millisecond,
	}
}

// Configured 表示是否具备调用官方搜索接口的凭据。
func (c *Client) Configured() bool { return c != nil && c.apiKey != "" }

// Search 调用官方接口，并对 408、429 和服务端 5xx 做有限退避重试。
func (c *Client) Search(ctx context.Context, q Query) ([]Result, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("联网搜索未配置")
	}
	query := strings.TrimSpace(q.Query)
	if query == "" {
		return nil, fmt.Errorf("query 不能为空")
	}
	if len([]rune(query)) > 128 {
		query = string([]rune(query)[:128])
	}
	count := q.Count
	if count <= 0 {
		count = 10
	}
	if count > 20 {
		count = 20
	}
	payload, err := json.Marshal(map[string]any{
		"query":         query,
		"count":         count,
		"ori_question":  strings.TrimSpace(q.Original),
		"localization":  strings.TrimSpace(q.Localize),
		"need_content":  q.NeedContent,
	})
	if err != nil {
		return nil, err
	}

	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			delay := c.retryBase * time.Duration(1<<(attempt-1))
			timer := time.NewTimer(delay)
			select {
			case <-ctx.Done():
				timer.Stop()
				return nil, ctx.Err()
			case <-timer.C:
			}
		}
		results, retry, err := c.once(ctx, payload)
		if err == nil {
			return results, nil
		}
		lastErr = err
		if !retry {
			return nil, err
		}
	}
	return nil, lastErr
}

func (c *Client) once(ctx context.Context, payload []byte) ([]Result, bool, error) {
	req, err := http.NewRequestWithContext(
		ctx, http.MethodPost, c.endpoint, bytes.NewReader(payload))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, false, fmt.Errorf("联网搜索请求失败: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, false, fmt.Errorf("读取联网搜索结果失败: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		retry := resp.StatusCode == http.StatusRequestTimeout ||
			resp.StatusCode == http.StatusTooManyRequests ||
			resp.StatusCode >= 500
		detail := strings.TrimSpace(string(body))
		if len([]rune(detail)) > 180 {
			detail = string([]rune(detail)[:180])
		}
		switch resp.StatusCode {
		case http.StatusUnauthorized:
			return nil, retry, fmt.Errorf("联网搜索鉴权失败，请检查 API key")
		case http.StatusPaymentRequired:
			return nil, retry, fmt.Errorf("联网搜索额度不足，请检查 DeepSeek 账户余额")
		case http.StatusTooManyRequests:
			return nil, retry, fmt.Errorf("联网搜索请求过于频繁，请稍后重试")
		default:
			return nil, retry, fmt.Errorf(
				"联网搜索服务返回 %d: %s", resp.StatusCode, detail)
		}
	}
	var out struct {
		Results []Result `json:"results"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return nil, false, fmt.Errorf("解析联网搜索结果失败: %w", err)
	}
	return out.Results, false, nil
}
