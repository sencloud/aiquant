package tools

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/news"
	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// registerEvent 注册 5 个事件工具。
func registerEvent(r *tool.Registry, c *news.Client) {
	r.MustRegister(&searchGlobalEventsTool{c: c})
	r.MustRegister(&searchChineseNewsTool{c: c})
	r.MustRegister(&searchShippingEventsTool{c: c})
	r.MustRegister(&searchGeopoliticsEventsTool{c: c})
	r.MustRegister(&getFireHotspotsTool{c: c})
}

// parseLookbackHours 把 "6h"/"3d"/"2w" 转成小时数；无效则用 fallback。
var lookbackRE = regexp.MustCompile(`(?i)^(\d+)\s*([hdw])$`)

func parseLookbackHours(s string, fallbackHours int) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return fallbackHours
	}
	m := lookbackRE.FindStringSubmatch(s)
	if m == nil {
		return fallbackHours
	}
	n, _ := strconv.Atoi(m[1])
	switch strings.ToLower(m[2]) {
	case "h":
		return n
	case "d":
		return n * 24
	case "w":
		return n * 24 * 7
	}
	return fallbackHours
}

func formatLookback(hours int) string {
	if hours >= 24 {
		return fmt.Sprintf("%dd", hours/24)
	}
	return fmt.Sprintf("%dh", hours)
}

func eventsToJSON(items []news.Event) []map[string]any {
	out := make([]map[string]any, 0, len(items))
	for _, ev := range items {
		m := map[string]any{
			"source": ev.Source,
			"title":  ev.Title,
		}
		if ev.URL != "" {
			m["url"] = ev.URL
		}
		if ev.Type != "" {
			m["type"] = ev.Type
		}
		if ev.Snippet != "" {
			m["snippet"] = ev.Snippet
		}
		if ev.Lang != "" {
			m["lang"] = ev.Lang
		}
		if ev.Country != "" {
			m["country"] = ev.Country
		}
		if ev.PublishedAt != 0 {
			m["published_at"] = news.FormatTime(ev.PublishedAt)
		}
		if ev.Score != 0 {
			m["score"] = ev.Score
		}
		if ev.Lat != 0 || ev.Lon != 0 {
			m["lat"] = ev.Lat
			m["lon"] = ev.Lon
		}
		if len(ev.Extra) > 0 {
			m["extra"] = ev.Extra
		}
		out = append(out, m)
	}
	return out
}

func avgTone(items []news.Event) (float64, bool) {
	sum, n := 0.0, 0
	for _, ev := range items {
		if ev.Source != "gdelt" {
			continue
		}
		sum += ev.Score
		n++
	}
	if n == 0 {
		return 0, false
	}
	return sum / float64(n), true
}

// ── 19. search_global_events ───────────────────────────────────────────

type searchGlobalEventsTool struct{ c *news.Client }

func (t *searchGlobalEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "search_global_events",
		Description: "在 GDELT 全球新闻数据库（100+ 国家、65 种语言）按关键词搜索国际事件、地缘政治、宏观新闻、大宗商品。返回标题/来源/时间/基调（tone）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query":    {Type: "string", Description: "关键词（中英文均可）"},
				"lookback": {Type: "string", Description: "回看时长，如 6h/24h/3d/7d/2w（默认 24h）"},
				"country":  {Type: "string", Description: "限定来源国家（ISO-2，如 CN/US）"},
				"lang":     {Type: "string", Description: "限定来源语言（chinese/english 等）"},
				"limit":    {Type: "integer", Description: "前 N 条（默认 12，最大 50）"},
			},
			Required: []string{"query"},
		},
	}
}

func (t *searchGlobalEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Query    string `json:"query"`
		Lookback string `json:"lookback,omitempty"`
		Country  string `json:"country,omitempty"`
		Lang     string `json:"lang,omitempty"`
		Limit    int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Query)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "query 必填"}), nil
	}
	hours := parseLookbackHours(in.Lookback, 24)
	limit := clampInt(in.Limit, 1, 50, 12)
	items, err := t.c.SearchGDELT(ctx, q, hours, limit, news.GDELTOptions{
		Country:    in.Country,
		SourceLang: in.Lang,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := map[string]any{
		"query":    q,
		"lookback": formatLookback(hours),
		"count":    len(items),
		"articles": eventsToJSON(items),
	}
	if t, ok := avgTone(items); ok {
		out["avg_tone"] = round(t, 3)
	}
	return tool.EncodeJSON(out), nil
}

// ── 20. search_chinese_news ────────────────────────────────────────────

type searchChineseNewsTool struct{ c *news.Client }

func (t *searchChineseNewsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "search_chinese_news",
		Description: "搜索 Google News 中文环境下与关键词匹配的最新新闻（适合具体公司、A 股板块、政策、行业动态）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query": {Type: "string", Description: "中文关键词"},
				"limit": {Type: "integer", Description: "前 N 条（默认 10，最大 25）"},
			},
			Required: []string{"query"},
		},
	}
}

func (t *searchChineseNewsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Query string `json:"query"`
		Limit int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Query)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "query 必填"}), nil
	}
	limit := clampInt(in.Limit, 1, 25, 10)
	items, err := t.c.SearchGoogleNews(ctx, q, "zh-CN", limit)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"query":    q,
		"count":    len(items),
		"articles": eventsToJSON(items),
	}), nil
}

// ── 21. search_shipping_events ─────────────────────────────────────────

type searchShippingEventsTool struct{ c *news.Client }

func (t *searchShippingEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "search_shipping_events",
		Description: "搜索全球航运 / 港口 / 海事 / 海运中断相关事件（红海、苏伊士、巴拿马、马六甲、台湾海峡等）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"lookback":      {Type: "string", Description: "默认 7d，最长 4w"},
				"limit":         {Type: "integer", Description: "默认 15，最大 50"},
				"extra_keyword": {Type: "string", Description: "额外限定词（red sea / hormuz 等）"},
			},
		},
	}
}

const shippingBaseQuery = `(shipping OR port OR maritime OR vessel OR strait OR canal OR "sea route")`

func (t *searchShippingEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Lookback     string `json:"lookback,omitempty"`
		Limit        int    `json:"limit,omitempty"`
		ExtraKeyword string `json:"extra_keyword,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	hours := parseLookbackHours(in.Lookback, 7*24)
	if hours > 4*7*24 {
		hours = 4 * 7 * 24
	}
	limit := clampInt(in.Limit, 1, 50, 15)
	extra := strings.TrimSpace(in.ExtraKeyword)
	query := shippingBaseQuery
	if extra != "" {
		query = fmt.Sprintf("%s AND (%s)", shippingBaseQuery, extra)
	}
	items, err := t.c.SearchGDELT(ctx, query, hours, limit)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"theme":    "global_shipping",
		"query":    query,
		"lookback": formatLookback(hours),
		"count":    len(items),
		"articles": eventsToJSON(items),
	}), nil
}

// ── 22. search_geopolitics_events ──────────────────────────────────────

type searchGeopoliticsEventsTool struct{ c *news.Client }

func (t *searchGeopoliticsEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "search_geopolitics_events",
		Description: "搜索全球地缘政治 / 武装冲突 / 制裁 / 外交摩擦事件，便于分析军工、能源、避险板块。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"lookback": {Type: "string", Description: "默认 3d"},
				"region":   {Type: "string", Description: "可选地理限定（middle east / taiwan strait / ukraine 等）"},
				"limit":    {Type: "integer", Description: "默认 15，最大 50"},
			},
		},
	}
}

const geoBaseQuery = `(conflict OR sanction OR military OR war OR treaty OR summit OR diplomatic)`

func (t *searchGeopoliticsEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Lookback string `json:"lookback,omitempty"`
		Region   string `json:"region,omitempty"`
		Limit    int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	hours := parseLookbackHours(in.Lookback, 3*24)
	limit := clampInt(in.Limit, 1, 50, 15)
	region := strings.TrimSpace(in.Region)
	query := geoBaseQuery
	if region != "" {
		query = fmt.Sprintf(`%s AND ("%s")`, geoBaseQuery, region)
	}
	items, err := t.c.SearchGDELT(ctx, query, hours, limit)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"theme":    "geopolitics",
		"query":    query,
		"lookback": formatLookback(hours),
		"count":    len(items),
		"articles": eventsToJSON(items),
	}), nil
}

// ── 23. get_satellite_fire_hotspots ────────────────────────────────────

type getFireHotspotsTool struct{ c *news.Client }

func (t *getFireHotspotsTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_satellite_fire_hotspots",
		Description: "通过 NASA FIRMS 拉取最近 N 天卫星观测到的火点（热源），可指定经纬度边界。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"west":      {Type: "number", Description: "经度西界 (-180~180)"},
				"south":     {Type: "number", Description: "纬度南界 (-90~90)"},
				"east":      {Type: "number", Description: "经度东界"},
				"north":     {Type: "number", Description: "纬度北界"},
				"day_range": {Type: "integer", Description: "回看天数（1~10，默认 1）"},
				"dataset":   {Type: "string", Enum: []string{"VIIRS_SNPP_NRT", "VIIRS_NOAA20_NRT", "MODIS_NRT"}, Description: "默认 VIIRS_SNPP_NRT"},
			},
			Required: []string{"west", "south", "east", "north"},
		},
	}
}

func (t *getFireHotspotsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	if !t.c.FirmsConfigured() {
		return tool.EncodeJSON(map[string]any{
			"error": "服务端未配置 FIRMS_MAP_KEY；请联系管理员开通卫星火点数据。",
		}), nil
	}
	var in struct {
		West     *float64 `json:"west"`
		South    *float64 `json:"south"`
		East     *float64 `json:"east"`
		North    *float64 `json:"north"`
		DayRange int      `json:"day_range,omitempty"`
		Dataset  string   `json:"dataset,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	if in.West == nil || in.South == nil || in.East == nil || in.North == nil {
		return tool.EncodeJSON(map[string]any{"error": "需要 west/south/east/north 四个边界"}), nil
	}
	dayRange := clampInt(in.DayRange, 1, 10, 1)
	dataset := strings.TrimSpace(in.Dataset)
	if dataset == "" {
		dataset = "VIIRS_SNPP_NRT"
	}
	bbox := fmt.Sprintf("%g,%g,%g,%g", *in.West, *in.South, *in.East, *in.North)
	pts, err := t.c.FetchFireHotspots(ctx, dataset, bbox, dayRange)
	if err != nil {
		if errors.Is(err, news.ErrFirmsNotConfigured) {
			return tool.EncodeJSON(map[string]any{"error": "服务端未配置 FIRMS_MAP_KEY"}), nil
		}
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := map[string]any{
		"bbox": map[string]any{
			"west":  *in.West,
			"south": *in.South,
			"east":  *in.East,
			"north": *in.North,
		},
		"dataset":   dataset,
		"day_range": dayRange,
		"count":     len(pts),
	}
	max := 50
	if len(pts) < max {
		max = len(pts)
	}
	out["hotspots"] = eventsToJSON(pts[:max])
	return tool.EncodeJSON(out), nil
}
