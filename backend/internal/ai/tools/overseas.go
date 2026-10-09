package tools

import (
	"context"
	"encoding/json"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/weather"
)

// registerOverseasWeather 注册「外盘期货 + 产区天气」两个工具。
//
// 这两个是判断国内农产品 / 油脂 / 软商品的前置输入：内盘豆粕看 CBOT 大豆，
// 白糖看 ICE 原糖与印度/巴西天气，油脂看南美与东南亚产区。以前只能在提示词里
// 空谈「关注外盘」，现在能真正取到数。
func registerOverseasWeather(r *tool.Registry, rt *realtime.Client, wx *weather.Client) {
	if rt != nil {
		r.MustRegister(&getOverseasFuturesTool{c: rt})
	}
	if wx != nil {
		r.MustRegister(&getRegionWeatherTool{w: wx})
	}
}

// ── get_overseas_futures ───────────────────────────────────────────────

type getOverseasFuturesTool struct{ c *realtime.Client }

func (t *getOverseasFuturesTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_overseas_futures",
		Description: "获取外盘期货实时报价（腾讯财经，含 CBOT 农产品 / NYMEX 能源 / COMEX 金属 / ICE 软商品）。" +
			"用于判断国内豆粕、油脂、玉米、白糖、棉花的内盘定价锚。支持品种：" +
			strings.Join(realtime.OverseasFutureAliases(), "、") +
			"。不传 symbols 时返回大豆、玉米、小麦、豆粕、原油、黄金。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {
					Type:        "array",
					Description: "品种别名数组，中英文均可（大豆 / ZS / 玉米 / C / 原油 / CL / 黄金 / GC）",
					Items:       &tool.ParameterProperty{Type: "string"},
				},
			},
		},
	}
}

func (t *getOverseasFuturesTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbols []string `json:"symbols,omitempty"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	quotes, err := t.c.FetchOverseasFutures(ctx, in.Symbols)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error()}), nil
	}
	out := make([]map[string]any, 0, len(quotes))
	for _, q := range quotes {
		out = append(out, map[string]any{
			"name":      q.Symbol,
			"contract":  q.SecID,
			"last":      q.Last,
			"pct_chg":   q.PctChg,
			"change":    q.Change,
			"open":      q.Open,
			"high":      q.High,
			"low":       q.Low,
			"pre_close": q.PreClose,
			"delayed":   q.Delayed,
		})
	}
	return tool.EncodeJSON(map[string]any{
		"count":  len(out),
		"quotes": out,
		"source": "tencent_hf",
		"notice": "外盘为延时行情；单位与国内不同（CBOT 大豆/玉米/小麦为美分/蒲式耳，原油为美元/桶，黄金为美元/盎司），跨市场比较时注意换算。",
	}), nil
}

// ── get_region_weather ─────────────────────────────────────────────────

type getRegionWeatherTool struct{ w *weather.Client }

func (t *getRegionWeatherTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_region_weather",
		Description: "获取大宗商品产区 / 城市的未来天气（Open-Meteo，免费）。用于天气驱动的品种分析：" +
			"美豆看美国玉米带、白糖看印度北方邦、咖啡看巴西米纳斯、可可看科特迪瓦、棉花看美国得州。" +
			"不传 keys 时返回主要农产品产区。注意：天气是商品的间接驱动，" +
			"结论要落到「影响产量或物流」的链条上，不要只罗列气温数字。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"keys": {
					Type:        "array",
					Description: "产区/城市 key（如 us_corn_belt / india_sugar_up），也可直接传中文名（美国玉米带·爱荷华）",
					Items:       &tool.ParameterProperty{Type: "string"},
				},
				"days": {Type: "integer", Description: "预报天数（默认 7，最多 14）"},
			},
		},
	}
}

func (t *getRegionWeatherTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Keys []string `json:"keys,omitempty"`
		Days int      `json:"days,omitempty"`
	}
	if len(args) > 0 {
		if err := json.Unmarshal(args, &in); err != nil {
			return "", err
		}
	}
	days := in.Days
	if days <= 0 {
		days = 7
	}
	if days > 14 {
		days = 14
	}
	cities := resolveCities(in.Keys)
	if len(cities) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "没有匹配到任何产区/城市"}), nil
	}

	rows := make([]map[string]any, 0, len(cities))
	for _, c := range cities {
		wctx, cancel := context.WithTimeout(ctx, 15*time.Second)
		daily, err := t.w.FetchDaily(wctx, c.Lat, c.Lon)
		cancel()
		if err != nil {
			rows = append(rows, map[string]any{"name": c.Name, "error": err.Error()})
			continue
		}
		dates := make([]string, 0, len(daily))
		for d := range daily {
			dates = append(dates, d)
		}
		sort.Strings(dates)
		if len(dates) > days {
			dates = dates[:days]
		}
		forecast := make([]map[string]any, 0, len(dates))
		var sumPrecip float64
		for _, d := range dates {
			f := daily[d]
			sumPrecip += f.Precip
			forecast = append(forecast, map[string]any{
				"date":      d,
				"t_max":     round1(f.TMax),
				"t_min":     round1(f.TMin),
				"precip_mm": round1(f.Precip),
			})
		}
		rows = append(rows, map[string]any{
			"name":         c.Name,
			"key":          c.Key,
			"crop":         c.Crop,
			"precip_total": round1(sumPrecip),
			"forecast":     forecast,
		})
	}
	return tool.EncodeJSON(map[string]any{
		"count":  len(rows),
		"places": rows,
		"source": "open-meteo",
	}), nil
}

// resolveCities 把用户输入解析成天气地点；空输入给主要农产品产区。
func resolveCities(keys []string) []weather.City {
	if len(keys) == 0 {
		keys = []string{"us_corn_belt", "brazil_soy_mt", "us_wheat_kansas", "india_sugar_up"}
	}
	out := make([]weather.City, 0, len(keys))
	for _, k := range keys {
		if c, ok := weather.CityByKey(k); ok {
			out = append(out, c)
			continue
		}
		for _, c := range weather.Cities {
			if strings.TrimSpace(k) == c.Name {
				out = append(out, c)
				break
			}
		}
	}
	return out
}

func round1(v float64) float64 {
	return float64(int(v*10+0.5)) / 10
}
