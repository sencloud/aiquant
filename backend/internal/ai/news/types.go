// Package news 是事件 / 新闻 / 卫星 / 地缘多源数据的服务端聚合。
//
// 数据源：
//   - GDELT V2 doc API（全球事件 / 文章；公开免费）
//   - Google News RSS（中文 / 英文新闻；公开免费）
//   - NASA FIRMS area CSV（卫星火点；需要 map_key，免费申请）
package news

import "time"

// Event 是聚合后的统一事件 / 新闻条目。
type Event struct {
	Source     string    `json:"source"`               // gdelt / google_news / firms / shipping / geopolitics
	Type       string    `json:"type,omitempty"`       // article / event / hotspot
	Title      string    `json:"title"`
	URL        string    `json:"url,omitempty"`
	Snippet    string    `json:"snippet,omitempty"`
	Lang       string    `json:"lang,omitempty"`
	PublishedAt int64    `json:"published_at,omitempty"` // unix ms
	Country    string    `json:"country,omitempty"`
	Lat        float64   `json:"lat,omitempty"`
	Lon        float64   `json:"lon,omitempty"`
	Score      float64   `json:"score,omitempty"`        // tone / brightness / 等
	Extra      map[string]any `json:"extra,omitempty"`
}

// FormatTime 把 unix ms 转成 ISO 字符串（仅工具内部使用）。
func FormatTime(ms int64) string {
	if ms == 0 {
		return ""
	}
	return time.UnixMilli(ms).UTC().Format(time.RFC3339)
}
