package tools

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/sencloud/finme-backend/internal/ai/cnnews"
	"github.com/sencloud/finme-backend/internal/ai/news"
	"github.com/sencloud/finme-backend/internal/ai/tool"
)

// registerEvent 注册新闻 / 事件 / 卫星类工具。
//
// 国内中文 + 国际宏观 全部走 cnnews（财联社 / 东财快讯 / 华尔街见闻）；
// GDELT 在阿里云出口稳定 8s 超时，已不再使用，对应工具改用华尔街见闻 +
// 财联社的中文国际频道。卫星火点仍走 NASA FIRMS（公网无替代源）。
func registerEvent(r *tool.Registry, c *news.Client, cn *cnnews.Client) {
	r.MustRegister(&searchGlobalEventsTool{cn: cn})
	r.MustRegister(&searchChineseNewsTool{cn: cn})
	r.MustRegister(&getIndustryNewsTool{cn: cn})
	r.MustRegister(&searchShippingEventsTool{cn: cn})
	r.MustRegister(&searchGeopoliticsEventsTool{cn: cn})
	r.MustRegister(&getFireHotspotsTool{c: c})
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

// ── 19. search_global_events ───────────────────────────────────────────

type searchGlobalEventsTool struct{ cn *cnnews.Client }

func (t *searchGlobalEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "search_global_events",
		Description: "搜索国际宏观 / 地缘 / 全球商品 / 外汇相关新闻（中文）。" +
			"数据源：华尔街见闻实时电报 + 深度文章 + 财联社电报中的国际议题。" +
			"按关键字 OR 过滤（多个用空格 / 逗号分隔）。" +
			"返回标题/来源/时间/摘要/标签。" +
			"国内 A 股板块/政策请用 search_chinese_news；行业期货农产品请用 get_industry_news。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query":   {Type: "string", Description: "关键词（多个用空格 / 逗号分隔做 OR 匹配）"},
				"channel": {Type: "string", Description: "华尔街见闻 channel，默认 global-channel；可选 forex-channel/oil-channel/commodities-channel"},
				"limit":   {Type: "integer", Description: "前 N 条（默认 15，最大 50）"},
			},
			Required: []string{"query"},
		},
	}
}

func (t *searchGlobalEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Query   string `json:"query"`
		Channel string `json:"channel,omitempty"`
		Limit   int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Query)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "query 必填"}), nil
	}
	limit := clampInt(in.Limit, 1, 50, 15)
	items, err := t.cn.SearchGlobal(ctx, cnnews.GlobalSearchOptions{
		Keyword:         q,
		Channel:         in.Channel,
		Limit:           limit,
		IncludeArticles: true,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"query":    q,
		"count":    len(items),
		"articles": eventsToJSON(items),
		"sources":  []string{"wallstreetcn_lives", "wallstreetcn_article", "cls_telegraph"},
	}), nil
}

// ── 20. search_chinese_news ────────────────────────────────────────────

type searchChineseNewsTool struct{ cn *cnnews.Client }

func (t *searchChineseNewsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "search_chinese_news",
		Description: "搜索国内中文财经/A 股/期货/农产品/政策最新新闻。" +
			"聚合源：财联社电报（最实时） + 东方财富 7×24 快讯。" +
			"关键词支持空格 / 中文逗号分隔做或匹配（如「锂电 有色」表示锂电或有色）。" +
			"返回标题/来源/发布时间/摘要/标签。" +
			"国际/海外议题请改用 search_global_events。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query": {Type: "string", Description: "中文关键词；多个用空格 / 逗号分隔（OR 匹配）"},
				"limit": {Type: "integer", Description: "前 N 条（默认 15，最大 50）"},
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
	limit := clampInt(in.Limit, 1, 50, 15)
	items, err := t.cn.SearchAll(ctx, cnnews.SearchOptions{
		Keyword: q,
		Limit:   limit,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"query":    q,
		"count":    len(items),
		"articles": eventsToJSON(items),
		"sources":  []string{"cls_telegraph", "eastmoney_kuaixun"},
	}), nil
}

// ── 20.5 get_industry_news ─────────────────────────────────────────────
//
// 行业 / 期货 / 农产品 / 化工 / 能源 / 有色 / 半导体 / 军工 等大频道滚动。
// 内部仍是上面三源聚合，但 query 用预设别名 → 关键字集，提升召回。

type getIndustryNewsTool struct{ cn *cnnews.Client }

func (t *getIndustryNewsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_industry_news",
		Description: "按行业 / 主题大类获取最新国内新闻（财联社+东财+新浪聚合）。" +
			"theme 支持：'futures' (期货) / 'agricultural' (农产品) / 'metals' (有色金属) / " +
			"'energy' (能源/原油/煤炭) / 'chemical' (化工) / 'semiconductor' (半导体) / " +
			"'military' (军工) / 'newenergy' (新能源车/锂电/光伏) / 'realestate' (房地产) / " +
			"'macro' (宏观政策/央行/财政) 。" +
			"也可以传 free_keyword 自定义关键字（OR 匹配）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"theme":        {Type: "string", Description: "行业主题别名（见说明）；为空时仅按 free_keyword 过滤"},
				"free_keyword": {Type: "string", Description: "可选自定义关键字"},
				"limit":        {Type: "integer", Description: "前 N 条（默认 20，最大 60）"},
			},
		},
	}
}

// industryThemeKeywords 把行业别名展开成「财联社/东财常用词」。
//
// 经验：财联社电报里期货 / 农产品的标题经常用「白糖」「豆粕」「棉花」这类品种名而
// 不是「农产品」三个字，所以要用品种关键字做 OR 匹配。
var industryThemeKeywords = map[string][]string{
	"futures":       {"期货", "主力合约", "玻璃", "纯碱", "甲醇", "PTA", "螺纹", "焦煤", "焦炭", "铁矿"},
	"agricultural":  {"白糖", "豆粕", "豆油", "棕榈油", "棉花", "玉米", "小麦", "生猪", "鸡蛋", "苹果", "红枣", "花生", "农产品", "粮食"},
	"metals":        {"有色", "铜", "铝", "黄金", "白银", "锌", "铅", "镍", "锂", "稀土", "钨", "钼", "金属"},
	"energy":        {"原油", "石油", "WTI", "布伦特", "OPEC", "煤炭", "动力煤", "天然气", "LNG", "能源"},
	"chemical":      {"化工", "PVC", "纯碱", "甲醇", "乙烯", "丙烯", "PTA", "尿素", "PX"},
	"semiconductor": {"半导体", "芯片", "晶圆", "光刻", "存储", "GPU", "封测", "EDA"},
	"military":      {"军工", "国防", "航天", "导弹", "战机", "舰船", "兵器"},
	"newenergy":     {"新能源", "锂电", "电池", "光伏", "风电", "储能", "新能源车", "比亚迪", "宁德时代"},
	"realestate":    {"房地产", "楼市", "土拍", "地产", "保交楼", "房贷"},
	"macro":         {"央行", "MLF", "LPR", "财政部", "国常会", "GDP", "PMI", "CPI", "PPI", "降准", "降息"},
}

func (t *getIndustryNewsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Theme       string `json:"theme,omitempty"`
		FreeKeyword string `json:"free_keyword,omitempty"`
		Limit       int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	limit := clampInt(in.Limit, 1, 60, 20)
	theme := strings.ToLower(strings.TrimSpace(in.Theme))
	free := strings.TrimSpace(in.FreeKeyword)

	parts := []string{}
	if kws, ok := industryThemeKeywords[theme]; ok {
		parts = append(parts, kws...)
	} else if theme != "" {
		parts = append(parts, theme)
	}
	if free != "" {
		parts = append(parts, free)
	}
	if len(parts) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error": "theme 与 free_keyword 至少填一个；可用 theme 见 spec",
		}), nil
	}

	items, err := t.cn.SearchAll(ctx, cnnews.SearchOptions{
		Keyword: strings.Join(parts, " "),
		Limit:   limit,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := map[string]any{
		"theme":    theme,
		"keywords": parts,
		"count":    len(items),
		"articles": eventsToJSON(items),
	}
	if free != "" {
		out["free_keyword"] = free
	}
	return tool.EncodeJSON(out), nil
}

// ── 21. search_shipping_events ─────────────────────────────────────────

type searchShippingEventsTool struct{ cn *cnnews.Client }

func (t *searchShippingEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "search_shipping_events",
		Description: "搜索全球航运 / 港口 / 海事 / 海运中断相关事件（红海、苏伊士、巴拿马、马六甲、台湾海峡等）。" +
			"数据源走华尔街见闻 + 财联社电报。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"limit":         {Type: "integer", Description: "默认 15，最大 50"},
				"extra_keyword": {Type: "string", Description: "额外限定词（红海 / 霍尔木兹 / 巴拿马 / 苏伊士 等）"},
			},
		},
	}
}

const shippingZhKeywords = "航运 港口 海运 货船 油轮 集装箱 红海 苏伊士 巴拿马 马六甲 海峡 台湾海峡 霍尔木兹"

func (t *searchShippingEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Limit        int    `json:"limit,omitempty"`
		ExtraKeyword string `json:"extra_keyword,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	limit := clampInt(in.Limit, 1, 50, 15)
	kw := shippingZhKeywords
	if extra := strings.TrimSpace(in.ExtraKeyword); extra != "" {
		kw = kw + " " + extra
	}
	items, err := t.cn.SearchGlobal(ctx, cnnews.GlobalSearchOptions{
		Keyword:         kw,
		Limit:           limit,
		IncludeArticles: true,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"theme":    "global_shipping",
		"keywords": kw,
		"count":    len(items),
		"articles": eventsToJSON(items),
	}), nil
}

// ── 22. search_geopolitics_events ──────────────────────────────────────

type searchGeopoliticsEventsTool struct{ cn *cnnews.Client }

func (t *searchGeopoliticsEventsTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "search_geopolitics_events",
		Description: "搜索全球地缘政治 / 武装冲突 / 制裁 / 外交摩擦事件，便于分析军工、能源、避险板块。" +
			"数据源走华尔街见闻 + 财联社电报。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"region": {Type: "string", Description: "可选地理限定（中东 / 俄乌 / 台海 / 朝鲜半岛 等）"},
				"limit":  {Type: "integer", Description: "默认 15，最大 50"},
			},
		},
	}
}

const geoZhKeywords = "地缘 制裁 冲突 战争 停火 关税 加征关税 联合国 北约 武装 军演 外交"

func (t *searchGeopoliticsEventsTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Region string `json:"region,omitempty"`
		Limit  int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	limit := clampInt(in.Limit, 1, 50, 15)
	kw := geoZhKeywords
	if region := strings.TrimSpace(in.Region); region != "" {
		kw = kw + " " + region
	}
	items, err := t.cn.SearchGlobal(ctx, cnnews.GlobalSearchOptions{
		Keyword:         kw,
		Limit:           limit,
		IncludeArticles: true,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"theme":    "geopolitics",
		"keywords": kw,
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
