package tools

import (
	"context"
	"encoding/json"
	"math"
	"sort"
	"strings"
	"sync"
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
		Description: "获取大宗商品产区 / 城市的天气：最近 3 天实况 + 未来 N 天预报（Open-Meteo，失败自动切 MET Norway）。" +
			"用于天气驱动的品种分析：棕榈油看马来西亚/印尼（柔佛、沙巴、砂拉越、廖内、南苏门答腊、加里曼丹）、" +
			"美豆看美国玉米带/伊利诺伊、南美看马托格罗索/巴拉那/潘帕斯、白糖看巴西圣保罗/印度北方邦/泰国/广西、" +
			"咖啡看米纳斯/越南、可可看科特迪瓦、棉花看得州/新疆、国内看黑龙江/河南/山东。" +
			"keys 可传内置 key、中文地名（柔佛 / 廖内 / 黑龙江）、作物或国家（棕榈油 / 大豆 / 马来西亚），" +
			"未内置的地名会自动地理编码。不传 keys 时返回主要农产品产区。注意：天气是商品的间接驱动，" +
			"结论要落到「影响产量或物流」的链条上，不要只罗列气温数字。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"keys": {
					Type:        "array",
					Description: "产区/城市：key（如 my_palm_johor / us_corn_belt）、中文地名（柔佛 / 廖内）或作物/国家（棕榈油 / 印尼）",
					Items:       &tool.ParameterProperty{Type: "string"},
				},
				"days": {Type: "integer", Description: "未来预报天数（默认 7，最多 14）"},
			},
		},
	}
}

// maxWeatherPlaces 限制一次查询的地点数：模型按作物展开时可能一下要十几个点。
const maxWeatherPlaces = 8

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
	cities, unresolved := resolveCities(in.Keys)
	// 内置表里没有的地名，再试一次地理编码（例如「巴西南马托格罗索州」「宋卡府」）。
	if len(unresolved) > 0 {
		left := unresolved[:0]
		for _, k := range unresolved {
			gctx, cancel := context.WithTimeout(ctx, 8*time.Second)
			c, ok, err := t.w.Geocode(gctx, k)
			cancel()
			if err == nil && ok {
				cities = appendUniqueCity(cities, c)
				continue
			}
			left = append(left, k)
		}
		unresolved = left
	}
	if len(cities) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":      "没有匹配到任何产区/城市，请改用下列 key 之一或直接写中文地名/作物",
			"unresolved": unresolved,
			"available":  weather.RegionKeys(),
		}), nil
	}
	truncated := false
	if len(cities) > maxWeatherPlaces {
		cities = cities[:maxWeatherPlaces]
		truncated = true
	}

	rows := make([]map[string]any, len(cities))
	var wg sync.WaitGroup
	for i, c := range cities {
		wg.Add(1)
		go func(i int, c weather.City) {
			defer wg.Done()
			wctx, cancel := context.WithTimeout(ctx, 20*time.Second)
			defer cancel()
			fc, err := t.w.FetchForecast(wctx, c.Lat, c.Lon, days+1, 3)
			if err != nil {
				rows[i] = map[string]any{"name": c.Name, "key": c.Key, "error": err.Error()}
				return
			}
			rows[i] = weatherRow(c, fc, days)
		}(i, c)
	}
	wg.Wait()

	okCount := 0
	sources := map[string]bool{}
	for _, r := range rows {
		if _, bad := r["error"]; !bad {
			okCount++
			if s, _ := r["source"].(string); s != "" {
				sources[s] = true
			}
		}
	}
	out := map[string]any{
		"count":  len(rows),
		"ok":     okCount,
		"places": rows,
	}
	srcList := make([]string, 0, len(sources))
	for s := range sources {
		srcList = append(srcList, s)
	}
	sort.Strings(srcList)
	out["source"] = strings.Join(srcList, ",")
	if len(unresolved) > 0 {
		out["unresolved"] = unresolved
	}
	if truncated {
		out["notice"] = "地点过多，只返回前 8 个；需要其余地点请分批查询"
	}
	return tool.EncodeJSON(out), nil
}

// weatherRow 把一个地点的逐日数据拆成「近期实况」和「未来预报」，并给出汇总。
func weatherRow(c weather.City, fc *weather.Forecast, days int) map[string]any {
	recent := make([]map[string]any, 0, 3)
	forecast := make([]map[string]any, 0, days)
	var sumPrecip, maxT float64
	maxT = -100
	dryDays, hotDays := 0, 0
	for _, d := range fc.Days {
		item := map[string]any{
			"date":      d.Date,
			"t_max":     round1(d.TMax),
			"t_min":     round1(d.TMin),
			"precip_mm": round1(d.Precip),
		}
		if d.Date < fc.Today {
			recent = append(recent, item)
			continue
		}
		if len(forecast) >= days {
			continue
		}
		forecast = append(forecast, item)
		sumPrecip += d.Precip
		if d.TMax > maxT {
			maxT = d.TMax
		}
		if d.Precip < 1 {
			dryDays++
		}
		if d.TMax >= 35 {
			hotDays++
		}
	}
	row := map[string]any{
		"name":         c.Name,
		"key":          c.Key,
		"lat":          c.Lat,
		"lon":          c.Lon,
		"source":       fc.Source,
		"today":        fc.Today,
		"recent":       recent,
		"forecast":     forecast,
		"precip_total": round1(sumPrecip),
		"dry_days":     dryDays,
		"hot_days":     hotDays,
	}
	if c.Crop != "" {
		row["crop"] = c.Crop
	}
	if len(forecast) > 0 {
		row["t_max_peak"] = round1(maxT)
	}
	return row
}

// resolveCities 把用户输入解析成天气地点；空输入给主要农产品产区。
// 返回去重后的地点和没解析出来的输入（交给地理编码兜底）。
func resolveCities(keys []string) ([]weather.City, []string) {
	if len(keys) == 0 {
		keys = []string{"us_corn_belt", "brazil_soy_mt", "us_wheat_kansas", "india_sugar_up"}
	}
	out := make([]weather.City, 0, len(keys))
	var unresolved []string
	for _, k := range keys {
		k = strings.TrimSpace(k)
		if k == "" {
			continue
		}
		cs := weather.Resolve(k)
		if len(cs) == 0 {
			unresolved = append(unresolved, k)
			continue
		}
		for _, c := range cs {
			out = appendUniqueCity(out, c)
		}
	}
	return out, unresolved
}

func appendUniqueCity(list []weather.City, c weather.City) []weather.City {
	for _, x := range list {
		if x.Key == c.Key {
			return list
		}
	}
	return append(list, c)
}

func round1(v float64) float64 {
	return math.Round(v*10) / 10
}
