package cnnews

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// cstZone 是国内源统一使用的时间区（快讯时间都是北京时间）。
var cstZone = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return time.FixedZone("CST", 8*3600)
	}
	return loc
}()

// FetchJin10Flash 拉金十数据 7×24 快讯。
//
// 端点（公开，返回 JS 字面量而非纯 JSON）：
//
//	https://www.jin10.com/flash_newest.js
//	  → var newest = [{"id","time","data":{"title","content"},"important","channel"}]
//
// 为什么加这一源：财联社 nodeapi 已 404（站点改版），而金十是同一类"最实时"的
// 快讯源，覆盖宏观 / 期货 / 农产品 / 地缘，且在阿里云出口稳定可达。
func (c *Client) FetchJin10Flash(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	const u = "https://www.jin10.com/flash_newest.js"
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126 Safari/537.36")
	req.Header.Set("Referer", "https://www.jin10.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("jin10 http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("jin10 %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	raw := string(body)
	// 剥掉 `var newest = ` 前缀与结尾分号，剩下才是 JSON 数组。
	if i := strings.IndexByte(raw, '['); i >= 0 {
		raw = raw[i:]
	}
	if j := strings.LastIndexByte(raw, ']'); j >= 0 {
		raw = raw[:j+1]
	}

	var items []struct {
		ID        string `json:"id"`
		Time      string `json:"time"`
		Important int    `json:"important"`
		Data      struct {
			Title   string `json:"title"`
			Content string `json:"content"`
			Source  string `json:"source"`
		} `json:"data"`
		Channel []int `json:"channel"`
	}
	if err := json.Unmarshal([]byte(raw), &items); err != nil {
		return nil, fmt.Errorf("jin10 parse: %w", err)
	}

	out := make([]Event, 0, len(items))
	for _, it := range items {
		content := strings.TrimSpace(it.Data.Content)
		title := strings.TrimSpace(it.Data.Title)
		if title == "" {
			title = truncateRunes(content, 60)
		}
		if title == "" && content == "" {
			continue
		}
		out = append(out, Event{
			Source:      "jin10",
			Type:        "article",
			Title:       title,
			Snippet:     content,
			URL:         "https://www.jin10.com/",
			Lang:        "zh-CN",
			PublishedAt: parseJin10Time(it.Time),
			Extra: map[string]any{
				"important": it.Important == 1,
				"source":    it.Data.Source,
				"channels":  it.Channel,
			},
		})
		if len(out) >= limit {
			break
		}
	}
	return out, nil
}

// parseJin10Time 解析 "2026-10-10 05:55:29"（北京时间）为 unix ms。
func parseJin10Time(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	if t, err := time.ParseInLocation("2006-01-02 15:04:05", s, cstZone); err == nil {
		return t.UnixMilli()
	}
	return 0
}

func truncateRunes(s string, n int) string {
	rs := []rune(strings.TrimSpace(s))
	if len(rs) <= n {
		return string(rs)
	}
	return string(rs[:n]) + "…"
}
