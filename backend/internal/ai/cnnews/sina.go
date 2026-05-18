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

// SinaLid 把语义化频道名映射到新浪滚动新闻 lid 数字。
//
// 经线上验证可用的 lid（pageid=153）：
//   - 2509：财经
//   - 2510：国内
//   - 2511：国际
//   - 2516：综合
//
// 失效的（meta=11 = 未注册）：1686 / 1687 / 1688 / 1689 / 2519。
var SinaLid = map[string]string{
	"finance": "2509",
	"china":   "2510",
	"world":   "2511",
	"all":     "2516",
}

// FetchSinaRoll 调新浪滚动新闻 API。
//
// 端点：
//
//	https://feed.mix.sina.com.cn/api/roll/get?pageid=153&lid=<lid>&num=<n>&page=1
func (c *Client) FetchSinaRoll(ctx context.Context, channel string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	lid, ok := SinaLid[strings.ToLower(strings.TrimSpace(channel))]
	if !ok {
		lid = SinaLid["finance"]
	}
	u := fmt.Sprintf(
		"https://feed.mix.sina.com.cn/api/roll/get?pageid=153&lid=%s&num=%d&versionNumber=1.2.4&page=1",
		lid, limit,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("sina roll http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("sina roll %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Result struct {
			Status struct {
				Code int    `json:"code"`
				Msg  string `json:"msg"`
			} `json:"status"`
			Data []struct {
				Title       string `json:"title"`
				URL         string `json:"url"`
				Intro       string `json:"intro"`
				Media       string `json:"media_name"`
				CTime       string `json:"ctime"` // unix s 字符串
				Keywords    string `json:"keywords"`
			} `json:"data"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("sina roll parse: %w", err)
	}
	if r.Result.Status.Code != 0 {
		return nil, fmt.Errorf("sina roll status %d: %s", r.Result.Status.Code, r.Result.Status.Msg)
	}
	out := make([]Event, 0, len(r.Result.Data))
	for _, d := range r.Result.Data {
		ts := parseSinaCTime(d.CTime)
		ev := Event{
			Source:      "sina_roll",
			Type:        "article",
			Title:       strings.TrimSpace(d.Title),
			URL:         d.URL,
			Snippet:     clsTrimSnippet(firstNonEmpty(d.Intro, d.Media), 160),
			Lang:        "zh-CN",
			Country:     "CN",
			PublishedAt: ts,
		}
		if d.Keywords != "" {
			ev.Extra = map[string]any{"keywords": d.Keywords}
		}
		out = append(out, ev)
	}
	return out, nil
}

func parseSinaCTime(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	t, err := time.Parse("2006-01-02 15:04:05", s)
	if err == nil {
		return t.UTC().UnixMilli()
	}
	var sec int64
	for _, ch := range s {
		if ch < '0' || ch > '9' {
			return 0
		}
		sec = sec*10 + int64(ch-'0')
	}
	if sec > 0 {
		return sec * 1000
	}
	return 0
}

func firstNonEmpty(ss ...string) string {
	for _, s := range ss {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}
