package news

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// GDELTOptions 控制 GDELT 检索的可选字段（country/sourceLang）。
type GDELTOptions struct {
	Country    string
	SourceLang string
}

// SearchGDELT 调 GDELT V2 doc API。query 走自然语言；hours 控制窗口。
//
// API 地址：https://api.gdeltproject.org/api/v2/doc/doc?...
//
// mode=ArtList&format=json 返回精选的文章列表，含 title / url / domain /
// language / sourcecountry / tone / seendate。
func (c *Client) SearchGDELT(ctx context.Context, query string, hours int, limit int, opts ...GDELTOptions) ([]Event, error) {
	if hours <= 0 || hours > 24*30 {
		hours = 24
	}
	if limit <= 0 || limit > 75 {
		limit = 25
	}
	var opt GDELTOptions
	if len(opts) > 0 {
		opt = opts[0]
	}
	if opt.Country = strings.TrimSpace(opt.Country); opt.Country != "" {
		query = fmt.Sprintf("%s sourcecountry:%s", query, strings.ToUpper(opt.Country))
	}
	if opt.SourceLang = strings.TrimSpace(opt.SourceLang); opt.SourceLang != "" {
		query = fmt.Sprintf("%s sourcelang:%s", query, strings.ToLower(opt.SourceLang))
	}
	q := url.Values{}
	q.Set("query", query)
	q.Set("mode", "ArtList")
	q.Set("format", "json")
	q.Set("maxrecords", fmt.Sprintf("%d", limit))
	q.Set("sort", "DateDesc")
	q.Set("timespan", fmt.Sprintf("%dh", hours))

	u := strings.TrimRight(c.cfg.GdeltBaseURL, "/") + "?" + q.Encode()
	req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gdelt http: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("gdelt %d: %s", resp.StatusCode, string(b))
	}
	var r struct {
		Articles []struct {
			URL           string  `json:"url"`
			URLMobile     string  `json:"url_mobile,omitempty"`
			Title         string  `json:"title"`
			SeenDate      string  `json:"seendate"` // 20240115T120000Z
			SocialImage   string  `json:"socialimage,omitempty"`
			Domain        string  `json:"domain,omitempty"`
			Language      string  `json:"language,omitempty"`
			SourceCountry string  `json:"sourcecountry,omitempty"`
			Tone          float64 `json:"tone,omitempty"`
		} `json:"articles"`
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("gdelt parse: %w", err)
	}
	out := make([]Event, 0, len(r.Articles))
	for _, a := range r.Articles {
		ts, _ := time.Parse("20060102T150405Z", a.SeenDate)
		ev := Event{
			Source:      "gdelt",
			Type:        "article",
			Title:       a.Title,
			URL:         a.URL,
			Snippet:     a.Domain,
			Lang:        a.Language,
			Country:     a.SourceCountry,
			Score:       a.Tone,
			PublishedAt: ts.UnixMilli(),
		}
		out = append(out, ev)
	}
	return out, nil
}
