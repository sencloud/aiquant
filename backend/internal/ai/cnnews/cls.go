package cnnews

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// FetchClsTelegraph 调财联社电报 API。
//
// 端点（公开，无需签名）：
//
//	https://www.cls.cn/nodeapi/updateTelegraphList?app=CailianpressWeb&os=web
//	  &rn=<limit>&sv=8.4.6&hasFirstVipArticle=1&lastTime=
//
// 返回 roll_data，单条字段：title / brief / content / ctime / level / id /
// shareurl / subjects[]。content 通常以「【标题】正文」开头。
func (c *Client) FetchClsTelegraph(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	u := fmt.Sprintf(
		"https://www.cls.cn/nodeapi/updateTelegraphList?app=CailianpressWeb&os=web&rn=%d&sv=8.4.6&hasFirstVipArticle=1&lastTime=",
		limit,
	)
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	req.Header.Set("Referer", "https://www.cls.cn/")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("cls http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("cls %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	var r struct {
		Errno int    `json:"error"`
		Data  struct {
			RollData []struct {
				ID       int64    `json:"id"`
				Title    string   `json:"title"`
				Brief    string   `json:"brief"`
				Content  string   `json:"content"`
				ShareURL string   `json:"shareurl"`
				CTime    int64    `json:"ctime"`
				Level    string   `json:"level"`
				Subjects []struct {
					SubjectName string `json:"subject_name"`
				} `json:"subjects"`
			} `json:"roll_data"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("cls parse: %w", err)
	}
	out := make([]Event, 0, len(r.Data.RollData))
	for _, it := range r.Data.RollData {
		title := strings.TrimSpace(it.Title)
		content := strings.TrimSpace(it.Content)
		if title == "" {
			title = clsExtractTitle(content)
		}
		ev := Event{
			Source:      "cls_telegraph",
			Type:        "telegraph",
			Title:       title,
			URL:         it.ShareURL,
			Snippet:     clsTrimSnippet(content, 180),
			Lang:        "zh-CN",
			Country:     "CN",
			PublishedAt: it.CTime * 1000,
		}
		if len(it.Subjects) > 0 {
			tags := make([]string, 0, len(it.Subjects))
			for _, s := range it.Subjects {
				if s.SubjectName != "" {
					tags = append(tags, s.SubjectName)
				}
			}
			if len(tags) > 0 {
				ev.Extra = map[string]any{"tags": tags}
			}
		}
		if it.Level == "A" || it.Level == "B" {
			ev.Score = 1.0 // 红头/重要
		}
		out = append(out, ev)
	}
	return out, nil
}

// clsExtractTitle 从「【XXX】正文」抽取头部 title。
func clsExtractTitle(content string) string {
	if i := strings.Index(content, "】"); i > 0 {
		head := content[:i]
		head = strings.TrimPrefix(head, "【")
		return strings.TrimSpace(head)
	}
	if len(content) > 60 {
		return content[:60]
	}
	return content
}

// clsTrimSnippet 截断到 max 字符（按 rune 边界），剥掉 HTML 标签。
func clsTrimSnippet(s string, max int) string {
	s = stripHTML(s)
	s = strings.TrimSpace(s)
	if max <= 0 {
		return s
	}
	rs := []rune(s)
	if len(rs) <= max {
		return s
	}
	return string(rs[:max]) + "…"
}
