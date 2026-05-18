package news

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// SearchGoogleNews 走 Google News RSS（无需 key）。
//
// 拼装的 URL 形如：
//
//	https://news.google.com/rss/search?q=<query>&hl=zh-CN&gl=CN&ceid=CN:zh
//
// 用 hl/gl/ceid 控制语言 + 国家。
func (c *Client) SearchGoogleNews(ctx context.Context, query string, lang string, limit int) ([]Event, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	hl, gl, ceid := googleLocale(lang)
	q := url.Values{}
	q.Set("q", query)
	q.Set("hl", hl)
	q.Set("gl", gl)
	q.Set("ceid", ceid)
	u := strings.TrimRight(c.cfg.GoogleRSSBase, "/") + "?" + q.Encode()
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 finme-backend")
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("google news http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("google news %d: %s", resp.StatusCode, string(b))
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	type itemRaw struct {
		Title       string `xml:"title"`
		Link        string `xml:"link"`
		Description string `xml:"description"`
		Source      string `xml:"source"`
		PubDate     string `xml:"pubDate"`
	}
	var rss struct {
		Channel struct {
			Items []itemRaw `xml:"item"`
		} `xml:"channel"`
	}
	if err := xml.Unmarshal(body, &rss); err != nil {
		return nil, fmt.Errorf("google news xml: %w", err)
	}
	out := make([]Event, 0, len(rss.Channel.Items))
	for i, it := range rss.Channel.Items {
		if i >= limit {
			break
		}
		ts, _ := time.Parse(time.RFC1123Z, it.PubDate)
		out = append(out, Event{
			Source:      "google_news",
			Type:        "article",
			Title:       cleanText(it.Title),
			URL:         it.Link,
			Snippet:     cleanText(it.Source),
			Lang:        hl,
			PublishedAt: ts.UnixMilli(),
		})
	}
	return out, nil
}

func googleLocale(lang string) (string, string, string) {
	l := strings.ToLower(strings.TrimSpace(lang))
	switch l {
	case "zh", "zh-cn", "cn", "":
		return "zh-CN", "CN", "CN:zh"
	case "en", "en-us":
		return "en-US", "US", "US:en"
	default:
		return "en-US", "US", "US:en"
	}
}

func cleanText(s string) string {
	s = strings.ReplaceAll(s, "&#39;", "'")
	s = strings.ReplaceAll(s, "&quot;", "\"")
	s = strings.ReplaceAll(s, "&amp;", "&")
	s = strings.TrimSpace(s)
	return s
}
