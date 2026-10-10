package cnnews

import (
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// 新增的公开源（2026-10 在阿里云杭州出口逐个实测可达）：
//
//	关键词搜索型（召回的主力——以前只有「最近几十条电报 + 子串过滤」，
//	稍冷一点的关键词，比如「厄尔尼诺」，几乎必然 0 条）：
//	  - wallstreetcn_search 华尔街见闻文章搜索 api-one-wscn.awtmt.com/apiv1/search/article
//	    （东方财富的搜索接口对非浏览器客户端返回占位数据，属反爬，不接）
//	滚动/快讯型（取最新 N 条，再按关键词过滤）：
//	  - ths_724            同花顺 7×24 快讯
//	  - sina_7x24          新浪财经 7×24 直播（zhibo_id=152）
//	  - caixin_scroll      财新网滚动新闻
//	  - chinanews_finance  中新网财经 RSS
//	  - people_finance     人民网财经 RSS
//	  - cnbc / marketwatch / un_news_zh  海外 RSS（英文 / 联合国中文）
//
// 实测不可达或被反爬、已从默认源移除：财联社 nodeapi（404）、新浪滚动 feed.mix（403）、
// 雪球（302 滑块）、FT 中文网 / BBC / Yahoo / Google News（连接超时）、GDELT（429）。

var cst = time.FixedZone("CST", 8*3600)

const browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

// 各源默认地址；测试里通过 Client.Overrides[name] 换成 httptest 地址。
var defaultURLs = map[string]string{
	"wallstreetcn_search": "https://api-one-wscn.awtmt.com/apiv1/search/article",
	"ths_724":             "https://news.10jqka.com.cn/tapp/news/push/stock/",
	"sina_7x24":           "https://zhibo.sina.com.cn/api/zhibo/feed",
	"caixin_scroll":       "https://gateway.caixin.com/api/dataplatform/scroll/index",
	"chinanews_finance":   "https://www.chinanews.com.cn/rss/finance.xml",
	"people_finance":      "http://www.people.com.cn/rss/finance.xml",
	"cnbc":                "https://www.cnbc.com/id/10000664/device/rss/rss.html",
	"marketwatch":         "https://feeds.content.dowjones.io/public/rss/mw_topstories",
	"un_news_zh":          "https://news.un.org/feed/subscribe/zh/news/all/rss.xml",
}

func (c *Client) urlFor(name string) string {
	if u := c.Overrides[name]; u != "" {
		return u
	}
	return defaultURLs[name]
}

func (c *Client) getBody(ctx context.Context, u, referer string, max int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", browserUA)
	if referer != "" {
		req.Header.Set("Referer", referer)
	}
	resp, err := c.httpc.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, max))
}

var emTag = regexp.MustCompile(`</?em>`)

func cleanText(s string) string {
	s = emTag.ReplaceAllString(s, "")
	s = stripHTML(s)
	s = strings.ReplaceAll(s, "\u3000", " ")
	return strings.TrimSpace(s)
}

// ── 华尔街见闻文章搜索 ─────────────────────────────────────────────────

func (c *Client) FetchWallstreetcnSearch(ctx context.Context, keyword string, limit int) ([]Event, error) {
	keyword = strings.TrimSpace(keyword)
	if keyword == "" {
		return nil, nil
	}
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	u := fmt.Sprintf("%s?query=%s&cursor=&limit=%d", c.urlFor("wallstreetcn_search"), url.QueryEscape(keyword), limit)
	body, err := c.getBody(ctx, u, "https://wallstreetcn.com/", 4<<20)
	if err != nil {
		return nil, fmt.Errorf("wallstreetcn search: %w", err)
	}
	var r struct {
		Code int `json:"code"`
		Data struct {
			Items []struct {
				Title       string `json:"title"`
				Content     string `json:"content"`
				DisplayTime int64  `json:"display_time"`
				URI         string `json:"uri"`
				IsPaid      bool   `json:"is_paid"`
			} `json:"items"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("wallstreetcn search parse: %w", err)
	}
	out := make([]Event, 0, len(r.Data.Items))
	for _, it := range r.Data.Items {
		link := it.URI
		if i := strings.Index(link, "?"); i > 0 {
			link = link[:i]
		}
		out = append(out, Event{
			Source: "wallstreetcn_search", Type: "article",
			Title: cleanText(it.Title), URL: link,
			Snippet: truncateRunes(cleanText(it.Content), 200),
			Lang:    "zh-CN", Country: "CN",
			PublishedAt: it.DisplayTime * 1000,
		})
	}
	return out, nil
}

// ── 同花顺 7×24 ─────────────────────────────────────────────────────────

func (c *Client) FetchTHS724(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	u := fmt.Sprintf("%s?page=1&tag=&track=website&pagesize=%d", c.urlFor("ths_724"), limit)
	body, err := c.getBody(ctx, u, "https://news.10jqka.com.cn/", 4<<20)
	if err != nil {
		return nil, fmt.Errorf("ths 7x24: %w", err)
	}
	var r struct {
		Data struct {
			List []struct {
				Title  string `json:"title"`
				Digest string `json:"digest"`
				URL    string `json:"url"`
				CTime  string `json:"ctime"`
				Tag    string `json:"tag"`
			} `json:"list"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("ths 7x24 parse: %w", err)
	}
	out := make([]Event, 0, len(r.Data.List))
	for _, it := range r.Data.List {
		sec, _ := strconv.ParseInt(strings.TrimSpace(it.CTime), 10, 64)
		ev := Event{
			Source: "ths_724", Type: "article",
			Title: cleanText(it.Title), URL: it.URL,
			Snippet: truncateRunes(cleanText(it.Digest), 200),
			Lang:    "zh-CN", Country: "CN",
			PublishedAt: sec * 1000,
		}
		if it.Tag != "" {
			ev.Extra = map[string]any{"tags": it.Tag}
		}
		out = append(out, ev)
	}
	return out, nil
}

// ── 新浪财经 7×24 ───────────────────────────────────────────────────────

func (c *Client) FetchSina7x24(ctx context.Context, limit int) ([]Event, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	u := fmt.Sprintf("%s?page=1&page_size=%d&zhibo_id=152&tag_id=0&dire=f&dpc=1&type=0", c.urlFor("sina_7x24"), limit)
	body, err := c.getBody(ctx, u, "https://finance.sina.com.cn/7x24/", 4<<20)
	if err != nil {
		return nil, fmt.Errorf("sina 7x24: %w", err)
	}
	var r struct {
		Result struct {
			Data struct {
				Feed struct {
					List []struct {
						ID         int64  `json:"id"`
						RichText   string `json:"rich_text"`
						CreateTime string `json:"create_time"`
						DocURL     string `json:"docurl"`
					} `json:"list"`
				} `json:"feed"`
			} `json:"data"`
		} `json:"result"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("sina 7x24 parse: %w", err)
	}
	out := make([]Event, 0, len(r.Result.Data.Feed.List))
	for _, it := range r.Result.Data.Feed.List {
		text := cleanText(it.RichText)
		if text == "" {
			continue
		}
		link := it.DocURL
		if link == "" {
			link = "https://finance.sina.com.cn/7x24/"
		}
		out = append(out, Event{
			Source: "sina_7x24", Type: "article",
			Title: clsExtractTitle(text), URL: link,
			Snippet: truncateRunes(text, 200),
			Lang:    "zh-CN", Country: "CN",
			PublishedAt: parseCST(it.CreateTime),
		})
	}
	return out, nil
}

// ── 财新滚动 ────────────────────────────────────────────────────────────

func (c *Client) FetchCaixinScroll(ctx context.Context, limit int) ([]Event, error) {
	body, err := c.getBody(ctx, c.urlFor("caixin_scroll"), "https://www.caixin.com/", 4<<20)
	if err != nil {
		return nil, fmt.Errorf("caixin scroll: %w", err)
	}
	var r struct {
		Data struct {
			ArticleList []struct {
				Title     string `json:"title"`
				Summary   string `json:"summary"`
				URL       string `json:"url"`
				Time      int64  `json:"time"`
				Keyword   string `json:"keyword"`
				MediaName string `json:"mediaName"`
			} `json:"articleList"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &r); err != nil {
		return nil, fmt.Errorf("caixin scroll parse: %w", err)
	}
	out := make([]Event, 0, len(r.Data.ArticleList))
	for i, it := range r.Data.ArticleList {
		if limit > 0 && i >= limit {
			break
		}
		snippet := cleanText(it.Summary)
		if it.Keyword != "" {
			snippet = strings.TrimSpace(snippet + " 关键词：" + it.Keyword)
		}
		out = append(out, Event{
			Source: "caixin", Type: "article",
			Title: cleanText(it.Title), URL: it.URL,
			Snippet: truncateRunes(snippet, 200),
			Lang:    "zh-CN", Country: "CN",
			PublishedAt: it.Time,
		})
	}
	return out, nil
}

// ── 通用 RSS ────────────────────────────────────────────────────────────

type rssDoc struct {
	Channel struct {
		Items []struct {
			Title       string `xml:"title"`
			Link        string `xml:"link"`
			Description string `xml:"description"`
			PubDate     string `xml:"pubDate"`
		} `xml:"item"`
	} `xml:"channel"`
}

// FetchRSS 拉一个 RSS 2.0 源。name 是 defaultURLs 里的源名，也作为 Event.Source。
func (c *Client) FetchRSS(ctx context.Context, name string, limit int) ([]Event, error) {
	u := c.urlFor(name)
	if u == "" {
		return nil, fmt.Errorf("rss %s: unknown source", name)
	}
	body, err := c.getBody(ctx, u, "", 4<<20)
	if err != nil {
		return nil, fmt.Errorf("rss %s: %w", name, err)
	}
	var doc rssDoc
	dec := xml.NewDecoder(strings.NewReader(string(body)))
	dec.Strict = false
	dec.CharsetReader = func(_ string, in io.Reader) (io.Reader, error) { return in, nil }
	if err := dec.Decode(&doc); err != nil {
		return nil, fmt.Errorf("rss %s parse: %w", name, err)
	}
	lang, country := "zh-CN", "CN"
	switch name {
	case "cnbc", "marketwatch":
		lang, country = "en", "US"
	case "un_news_zh":
		country = ""
	}
	out := make([]Event, 0, len(doc.Channel.Items))
	for i, it := range doc.Channel.Items {
		if limit > 0 && i >= limit {
			break
		}
		title := cleanText(it.Title)
		if title == "" {
			continue
		}
		out = append(out, Event{
			Source: name, Type: "article",
			Title: title, URL: strings.TrimSpace(it.Link),
			Snippet: truncateRunes(cleanText(it.Description), 200),
			Lang:    lang, Country: country,
			PublishedAt: parseRSSTime(it.PubDate),
		})
	}
	return out, nil
}

func parseRSSTime(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	for _, layout := range []string{time.RFC1123Z, time.RFC1123, "Mon, 2 Jan 2006 15:04:05 -0700", "Mon, 2 Jan 2006 15:04:05 MST", time.RFC3339, "2006-01-02 15:04:05"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UnixMilli()
		}
	}
	return parseCST(s)
}

func parseCST(s string) int64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	for _, layout := range []string{"2006-01-02 15:04:05", "2006-01-02 15:04", "2006-01-02"} {
		if t, err := time.ParseInLocation(layout, s, cst); err == nil {
			return t.UnixMilli()
		}
	}
	return 0
}
