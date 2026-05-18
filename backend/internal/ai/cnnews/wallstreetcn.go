package cnnews

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// FetchWallstreetcnLives 调华尔街见闻实时快讯接口。
//
// 端点：https://api-one-wscn.awtmt.com/apiv1/content/lives?channel=<channel>&limit=N
//
// 服务器（阿里云）实测稳定可用；返回中文国际财经/外汇/原油/商品快讯。
// channel 取值（已验证）：
//   - global-channel  全球宏观/外汇/原油/商品（推荐做主源）
//
// 单条电报携带 channels 数组，可用于二级过滤（forex-channel/oil-channel）。
func (c *Client) FetchWallstreetcnLives(ctx context.Context, channel string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	ch := strings.TrimSpace(channel)
	if ch == "" {
		ch = "global-channel"
	}
	u := fmt.Sprintf(
		"https://api-one-wscn.awtmt.com/apiv1/content/lives?channel=%s&limit=%d&accept=",
		ch, limit,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://wallstreetcn.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("wallstreetcn lives http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("wallstreetcn lives %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				ID          int64    `json:"id"`
				Title       string   `json:"title"`
				ContentText string   `json:"content_text"`
				URI         string   `json:"uri"`
				DisplayTime int64    `json:"display_time"`
				Channels    []string `json:"channels"`
				Tags        []string `json:"tags"`
				Score       int      `json:"score"`
			} `json:"items"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("wallstreetcn lives parse: %w", err)
	}
	if r.Code != 20000 {
		return nil, fmt.Errorf("wallstreetcn lives code=%d", r.Code)
	}
	out := make([]Event, 0, len(r.Data.Items))
	for _, it := range r.Data.Items {
		title := strings.TrimSpace(it.Title)
		if title == "" {
			title = clsTrimSnippet(it.ContentText, 60)
		}
		ev := Event{
			Source:      "wallstreetcn_lives",
			Type:        "telegraph",
			Title:       title,
			URL:         it.URI,
			Snippet:     clsTrimSnippet(it.ContentText, 220),
			Lang:        "zh-CN",
			PublishedAt: it.DisplayTime * 1000,
		}
		extra := map[string]any{}
		if len(it.Channels) > 0 {
			extra["channels"] = it.Channels
		}
		if len(it.Tags) > 0 {
			extra["tags"] = it.Tags
		}
		if len(extra) > 0 {
			ev.Extra = extra
		}
		if it.Score >= 2 {
			ev.Score = 1.0
		}
		out = append(out, ev)
	}
	return out, nil
}

// FetchWallstreetcnArticles 调华尔街见闻深度文章接口。
//
// 端点：https://api-one-wscn.awtmt.com/apiv1/content/articles?channel=<channel>&limit=N
//
// 与 lives 互补：lives 偏 24h 快讯，articles 偏跨日深度报道。
func (c *Client) FetchWallstreetcnArticles(ctx context.Context, channel string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	ch := strings.TrimSpace(channel)
	if ch == "" {
		ch = "global-channel"
	}
	u := fmt.Sprintf(
		"https://api-one-wscn.awtmt.com/apiv1/content/articles?channel=%s&limit=%d&accept=article&cursor=",
		ch, limit,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://wallstreetcn.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("wallstreetcn articles http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("wallstreetcn articles %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				ID            int64    `json:"id"`
				Title         string   `json:"title"`
				Subtitle      string   `json:"subtitle"`
				ContentShort  string   `json:"content_short"`
				URI           string   `json:"uri"`
				DisplayTime   int64    `json:"display_time"`
				Categories    []string `json:"categories"`
				Tags          []string `json:"tags"`
				IsInVIP       bool     `json:"is_in_vip_privilege"`
				IsPaid        bool     `json:"is_paid"`
			} `json:"items"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("wallstreetcn articles parse: %w", err)
	}
	if r.Code != 20000 {
		return nil, fmt.Errorf("wallstreetcn articles code=%d", r.Code)
	}
	out := make([]Event, 0, len(r.Data.Items))
	for _, it := range r.Data.Items {
		if it.IsPaid || it.IsInVIP {
			continue
		}
		ev := Event{
			Source:      "wallstreetcn_article",
			Type:        "article",
			Title:       strings.TrimSpace(it.Title),
			URL:         it.URI,
			Snippet:     clsTrimSnippet(firstNonEmpty(it.ContentShort, it.Subtitle), 200),
			Lang:        "zh-CN",
			PublishedAt: it.DisplayTime * 1000,
		}
		extra := map[string]any{}
		if len(it.Categories) > 0 {
			extra["categories"] = it.Categories
		}
		if len(it.Tags) > 0 {
			extra["tags"] = it.Tags
		}
		if len(extra) > 0 {
			ev.Extra = extra
		}
		out = append(out, ev)
	}
	return out, nil
}
