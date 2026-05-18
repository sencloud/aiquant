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

// FetchEastmoneyKuaixun 调东方财富 7×24 快讯 API。
//
// 端点（公开）：
//
//	https://newsapi.eastmoney.com/kuaixun/v2/api/list?column=<col>&limit=<n>&page=1
//
// column：
//   - 102：综合财经要闻 / 公司动态（默认）
//
// 返回 news[]，字段 title/digest/url_w/sort 等。sort 是毫秒时间戳。
func (c *Client) FetchEastmoneyKuaixun(ctx context.Context, column string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	col := strings.TrimSpace(column)
	if col == "" {
		col = "102"
	}
	u := fmt.Sprintf(
		"https://newsapi.eastmoney.com/kuaixun/v2/api/list?column=%s&limit=%d&page=1",
		col, limit,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://kuaixun.eastmoney.com/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("eastmoney kuaixun http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("eastmoney kuaixun %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		News []struct {
			ID       string `json:"id"`
			Title    string `json:"title"`
			Digest   string `json:"digest"`
			URLW     string `json:"url_w"`
			URLM     string `json:"url_m"`
			Sort     string `json:"sort"`     // 毫秒时间戳字符串
			ShowTime string `json:"showtime"` // "2026-05-18 11:30:00"
		} `json:"news"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("eastmoney kuaixun parse: %w", err)
	}
	out := make([]Event, 0, len(r.News))
	for _, n := range r.News {
		ts := parseEastmoneyTime(n.ShowTime, n.Sort)
		ev := Event{
			Source:      "eastmoney_kuaixun",
			Type:        "article",
			Title:       strings.TrimSpace(n.Title),
			URL:         n.URLW,
			Snippet:     clsTrimSnippet(n.Digest, 160),
			Lang:        "zh-CN",
			Country:     "CN",
			PublishedAt: ts,
		}
		out = append(out, ev)
	}
	return out, nil
}

// parseEastmoneyTime 优先 showtime（精确到秒），fallback 用 sort 的毫秒戳。
func parseEastmoneyTime(showTime, sort string) int64 {
	showTime = strings.TrimSpace(showTime)
	if showTime != "" {
		if t, err := time.ParseInLocation("2006-01-02 15:04:05", showTime, time.Local); err == nil {
			return t.UnixMilli()
		}
	}
	sort = strings.TrimSpace(sort)
	if sort == "" {
		return 0
	}
	// sort 通常是 16 位类似 1779079183004912 的字符串，前 13 位是毫秒戳
	if len(sort) >= 13 {
		var ms int64
		for i := 0; i < 13; i++ {
			ch := sort[i]
			if ch < '0' || ch > '9' {
				return 0
			}
			ms = ms*10 + int64(ch-'0')
		}
		return ms
	}
	return 0
}
