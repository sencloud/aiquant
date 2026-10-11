package miniapp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
	"github.com/sencloud/finme-backend/internal/fishing"
)

// ToolDispatcher 是 *tool.Registry 的最小接口：按名字调用 AI 工具，返回 JSON 字符串。
type ToolDispatcher interface {
	Has(name string) bool
	Dispatch(ctx context.Context, name string, argsJSON string) string
}

// BuiltinDeps 是内置数据源的下游。任何一项为 nil 时，相关数据源不注册。
type BuiltinDeps struct {
	Tools   ToolDispatcher
	History func(ctx context.Context, symbol string, start, end time.Time) ([]tushare.Candle, error)
	Fishing *fishing.Service
	Now     func() time.Time
}

// BuiltinRegistry 注册 P0 内置数据源。适配器把工具输出规整成固定结构，
// 输出字段写在 Output 里，由 sources_test.go 的快照测试锁定。
func BuiltinRegistry(d BuiltinDeps) *Registry {
	r := NewRegistry()
	now := d.Now
	if now == nil {
		now = time.Now
	}
	money := []string{"money"}
	both := []string{"money", "fishing"}
	fish := []string{"fishing"}
	has := func(name string) bool { return d.Tools != nil && d.Tools.Has(name) }

	if has("get_dominant_contract") {
		r.Register(&Source{
			ID: "futures.dominant", Title: "期货主力合约", Topics: money, TTL: time.Hour, Cost: 2,
			Doc: "把品种名（棕榈油 / 豆油 / 螺纹钢 / P / Y / RB）解析成当前主力合约及最近收盘",
			Params: []ParamDef{{Name: "product", Type: "string", Required: true,
				Doc: "品种名或品种字母，例如 棕榈油、豆油、螺纹钢、P、Y、RB"}},
			Output: `{"product":"P","exchange":"DCE","as_of":"2026-10-09","ts_code":"P2601.DCE","delivery_month":"2601","close":8712,"settle":8700,"vol":123456,"oi":234567}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				m, err := callTool(ctx, d.Tools, "get_dominant_contract", map[string]any{"product": c.Params["product"]})
				if err != nil {
					return nil, err
				}
				if m["asset_class"] != "futures" {
					return nil, errors.New("只支持期货品种")
				}
				dom, _ := m["dominant"].(map[string]any)
				if dom == nil {
					return nil, errors.New("没有找到主力合约")
				}
				return map[string]any{
					"product": m["product"], "exchange": m["exchange"], "as_of": m["as_of"],
					"ts_code": dom["ts_code"], "delivery_month": dom["delivery_month"],
					"close": dom["close"], "settle": dom["settle"], "vol": dom["vol"], "oi": dom["oi"],
				}, nil
			},
		})
	}
	if has("get_futures_realtime") {
		r.Register(&Source{
			ID: "futures.quote", Title: "期货行情", Topics: money, TTL: 30 * time.Second, Cost: 1,
			Doc: "期货合约最新行情；盘中拿不到实时价时退回最近交易日收盘（intraday=false）",
			Params: []ParamDef{{Name: "ts_code", Type: "string", Required: true,
				Doc: "完整合约代码（来自 futures.dominant 的 ts_code），例如 P2601.DCE"}},
			Output: `{"ts_code":"P2601.DCE","name":"棕榈2601","last":8712,"pct_chg":1.23,"change":106,"open":8650,"high":8730,"low":8640,"pre_settle":8606,"volume":120000,"oi":230000,"intraday":true}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				m, err := callTool(ctx, d.Tools, "get_futures_realtime", map[string]any{"ts_code": c.Params["ts_code"]})
				if err != nil {
					return nil, err
				}
				intraday := true
				if v, ok := m["realtime"].(bool); ok && !v {
					intraday = false
				}
				return pick(m, map[string]any{"intraday": intraday},
					"ts_code", "name", "last", "pct_chg", "change", "open", "high", "low",
					"pre_settle", "volume", "oi"), nil
			},
		})
	}
	if has("get_realtime_quote") {
		r.Register(&Source{
			ID: "stock.quote", Title: "A 股 / ETF / 指数行情", Topics: money, TTL: 30 * time.Second, Cost: 1,
			Doc: "A 股、ETF、指数实时快照（少量延迟）",
			Params: []ParamDef{{Name: "symbol", Type: "string", Required: true,
				Doc: "6 位代码或 ts_code，例如 600519、510300、000300.SH"}},
			Output: `{"ts_code":"510300.SH","name":"沪深300ETF","last":4.123,"pct_chg":0.56,"change":0.023,"open":4.1,"high":4.13,"low":4.09,"pre_close":4.1,"volume":1234567,"amount":5.1e8}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				sym := tushare.NormalizeSymbol(fmt.Sprint(c.Params["symbol"]))
				m, err := callTool(ctx, d.Tools, "get_realtime_quote", map[string]any{"symbol": sym})
				if err != nil {
					return nil, err
				}
				return pick(m, nil, "ts_code", "name", "last", "pct_chg", "change", "open", "high",
					"low", "pre_close", "volume", "amount"), nil
			},
		})
	}
	if d.History != nil {
		r.Register(&Source{
			ID: "market.daily_bars", Title: "日线行情", Topics: money, TTL: time.Hour, Cost: 3,
			Doc: "A 股 / ETF / 指数 / 期货合约最近 N 个交易日日线（含开高低收），可直接喂给 kline",
			Params: []ParamDef{
				{Name: "symbol", Type: "string", Required: true, Doc: "6 位代码、ts_code 或期货合约代码（P2601.DCE）"},
				{Name: "days", Type: "integer", Doc: "交易日数，默认 60", Min: f64(5), Max: f64(250), Default: 60.0},
			},
			Output: `{"symbol":"P2601.DCE","items":[{"date":"2026-10-09","open":8650,"high":8730,"low":8640,"close":8712,"pct_chg":1.23,"vol":120000}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				sym := tushare.NormalizeSymbol(fmt.Sprint(c.Params["symbol"]))
				days := int(c.Params["days"].(float64))
				end := now()
				start := end.AddDate(0, 0, -(days*2 + 30))
				cs, err := d.History(ctx, sym, start, end)
				if err != nil {
					return nil, fmt.Errorf("日线获取失败：%v", err)
				}
				if len(cs) == 0 {
					return nil, errors.New("没有拉到行情（代码可能不对或非交易日）")
				}
				if len(cs) > days {
					cs = cs[len(cs)-days:]
				}
				items := make([]map[string]any, 0, len(cs))
				for _, k := range cs {
					items = append(items, map[string]any{
						"date": fmtYMD(k.TradeDate), "open": k.Open, "high": k.High, "low": k.Low,
						"close": k.Close, "pct_chg": k.PctChg, "vol": k.Vol,
					})
				}
				return map[string]any{"symbol": sym, "items": items}, nil
			},
		})
	}
	if has("get_global_index") {
		r.Register(&Source{
			ID: "market.global_index", Title: "全球股指", Topics: money, TTL: time.Minute, Cost: 1,
			Doc: "道指、标普500、纳指、恒生、日经、德指、富时、美元指数快照",
			Params: []ParamDef{{Name: "symbols", Type: "array", MaxItems: 8,
				Doc: "可选：DJIA / SPX / NDX / HSI / N225 / GDAXI / FTSE / UDI"}},
			Output: `{"items":[{"symbol":"SPX","name":"标普500","last":7811.54,"change":46.18,"pct_chg":0.59}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				args := map[string]any{}
				if v, ok := c.Params["symbols"]; ok {
					args["symbols"] = v
				}
				m, err := callTool(ctx, d.Tools, "get_global_index", args)
				if err != nil {
					return nil, err
				}
				return map[string]any{"items": pickList(m["indexes"], "symbol", "name", "last", "change", "pct_chg")}, nil
			},
		})
	}
	if has("get_forex_rate") {
		r.Register(&Source{
			ID: "market.forex", Title: "外汇", Topics: money, TTL: time.Minute, Cost: 1,
			Doc: "美元指数、离岸人民币、欧元美元等汇率",
			Params: []ParamDef{{Name: "pairs", Type: "array", MaxItems: 8,
				Doc: "可选：UDI / USDCNH / USDCNYC / EURUSD / USDJPY / GBPUSD / AUDUSD"}},
			Output: `{"items":[{"symbol":"USDCNH","name":"离岸人民币","last":7.12,"change":0.01,"pct_chg":0.14}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				args := map[string]any{}
				if v, ok := c.Params["pairs"]; ok {
					args["pairs"] = v
				}
				m, err := callTool(ctx, d.Tools, "get_forex_rate", args)
				if err != nil {
					return nil, err
				}
				return map[string]any{"items": pickList(m["rates"], "symbol", "name", "last", "change", "pct_chg")}, nil
			},
		})
	}
	if has("search_chinese_news") {
		r.Register(&Source{
			ID: "news.cn", Title: "中文财经资讯", Topics: money, TTL: 10 * time.Minute, Cost: 2,
			Doc: "国内财经 / 期货 / 农产品新闻搜索（标题、来源、时间、链接）",
			Params: []ParamDef{
				{Name: "query", Type: "string", Required: true, Doc: "关键词，多个用空格分隔（或匹配）"},
				{Name: "limit", Type: "integer", Doc: "条数，默认 5", Min: f64(1), Max: f64(20), Default: 5.0},
			},
			Output: `{"items":[{"title":"……","source":"wallstreetcn_search","published_at":"2026-10-10T09:10:39Z","url":"https://…"}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				m, err := callTool(ctx, d.Tools, "search_chinese_news", map[string]any{"query": c.Params["query"], "limit": c.Params["limit"]})
				if err != nil {
					return nil, err
				}
				return map[string]any{"items": pickList(m["articles"], "title", "source", "published_at", "url")}, nil
			},
		})
	}
	if has("get_region_weather") {
		r.Register(&Source{
			ID: "weather.region", Title: "地区天气", Topics: both, TTL: 30 * time.Minute, Cost: 1,
			Doc: "城市 / 产区天气：未来 N 天预报 + 最近 3 天实况（中文地名、产区名都可以）",
			Params: []ParamDef{
				{Name: "place", Type: "string", Required: true, Doc: "地名，例如 柔佛、廖内、杭州、千岛湖"},
				{Name: "days", Type: "integer", Doc: "预报天数，默认 3", Min: f64(1), Max: f64(14), Default: 3.0},
			},
			Output: `{"name":"马来西亚·柔佛","today":"2026-10-11","forecast":[{"date":"2026-10-11","precip_mm":3.2,"t_max":31,"t_min":24}],"recent":[{"date":"2026-10-10","precip_mm":0,"t_max":32,"t_min":24}],"precip_total":15.8,"dry_days":1,"hot_days":0}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				m, err := callTool(ctx, d.Tools, "get_region_weather", map[string]any{
					"keys": []any{c.Params["place"]}, "days": c.Params["days"]})
				if err != nil {
					return nil, err
				}
				places, _ := m["places"].([]any)
				for _, p := range places {
					pm, _ := p.(map[string]any)
					if pm == nil || pm["error"] != nil {
						continue
					}
					return pick(pm, nil, "name", "today", "forecast", "recent", "precip_total",
						"dry_days", "hot_days"), nil
				}
				return nil, errors.New("没找到这个地名的天气")
			},
		})
	}
	if d.Fishing != nil {
		fs := d.Fishing
		r.Register(&Source{
			ID: "fishing.forecast", Title: "出钓指数", Topics: fish, TTL: time.Hour, Cost: 1,
			Doc: "某个水域 / 地名未来 N 天的出钓指数（0–100）、等级、最佳时段、天气摘要",
			Params: []ParamDef{
				{Name: "place", Type: "string", Required: true, Doc: "地名或水库名，例如 千岛湖、青山湖、杭州"},
				{Name: "days", Type: "integer", Doc: "天数，默认 3", Min: f64(1), Max: f64(7), Default: 3.0},
			},
			Output: `{"place":"中国·浙江·千岛湖","days":[{"date":"2026-10-11","score":86,"level":"很适合","summary":"……","temp_min":15,"temp_max":24,"precip_sum":0,"wind_max":3.2,"pressure":1016,"windows":[{"from":"05:30","to":"08:00","label":"清晨"}],"warnings":[]}],"active_bans":[]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				place, nDays := fmt.Sprint(c.Params["place"]), int(c.Params["days"].(float64))
				fc, err := fs.Forecast.ForPlace(ctx, place, nDays)
				// 地名库认不出「XX水库」这类水域名：去掉后缀再试（新安江水库 → 新安江）。
				for _, alt := range placeFallbacks(place) {
					if !errors.Is(err, fishing.ErrPlaceNotFound) {
						break
					}
					fc, err = fs.Forecast.ForPlace(ctx, alt, nDays)
				}
				if errors.Is(err, fishing.ErrPlaceNotFound) {
					return nil, errors.New("没找到这个地名，换成城市或区县名试试")
				}
				if err != nil {
					return nil, err
				}
				days := make([]map[string]any, 0, len(fc.Days))
				for _, d := range fc.Days {
					warn := d.Warnings
					if warn == nil {
						warn = []string{}
					}
					days = append(days, map[string]any{
						"date": d.Date, "score": d.Score, "level": d.Level, "summary": d.Summary,
						"temp_min": d.TempMin, "temp_max": d.TempMax, "precip_sum": d.PrecipSum,
						"wind_max": d.WindMax, "pressure": d.Pressure, "windows": d.Windows, "warnings": warn,
					})
				}
				bans := fc.ActiveBans
				if bans == nil {
					bans = []string{}
				}
				return map[string]any{"place": fc.Place, "days": days, "active_bans": bans}, nil
			},
		})
		r.Register(&Source{
			ID: "fishing.regulations", Title: "禁渔提示", Topics: fish, TTL: 6 * time.Hour, Cost: 0,
			Doc:    "某天生效的全国性禁渔规定（以当地渔政公告为准）",
			Params: []ParamDef{{Name: "date", Type: "string", Doc: "YYYY-MM-DD，默认今天"}},
			Output: `{"date":"2026-10-11","regulations":[{"name":"长江十年禁渔","…":"…"}]}`,
			Fetch: func(_ context.Context, c Call) (any, error) {
				s, _ := c.Params["date"].(string)
				day, err := fishing.ParseDate(s, now())
				if err != nil {
					return nil, errors.New("日期格式应为 YYYY-MM-DD")
				}
				resp := fishing.RegulationsResponse(day)
				return map[string]any{"date": resp["date"], "regulations": resp["regulations"]}, nil
			},
		})
		r.Register(&Source{
			ID: "fishing.catches", Title: "我的渔获", Topics: fish, Cost: 0, UserScoped: true,
			Doc:    "当前用户最近的渔获记录（按时间倒序；caught_at 是毫秒时间戳）",
			Params: []ParamDef{{Name: "limit", Type: "integer", Doc: "条数，默认 100", Min: f64(1), Max: f64(100), Default: 100.0}},
			Output: `{"items":[{"caught_at":1791648000000,"date":"2026-10-11","species":"鲫鱼","count":3,"weight_g":800,"length_cm":22,"spot_name":"千岛湖","method":"台钓","bait":"蚯蚓","released":false}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				list, err := fs.Journal.ListCatches(ctx, c.UserID, 0, int(c.Params["limit"].(float64)))
				if err != nil {
					return nil, err
				}
				items := make([]map[string]any, 0, len(list))
				for _, k := range list {
					items = append(items, map[string]any{
						"caught_at": k.CaughtAt, "date": time.UnixMilli(k.CaughtAt).In(shanghai).Format("2006-01-02"),
						"species": k.Species, "count": k.Count, "weight_g": k.WeightG, "length_cm": k.LengthCM,
						"spot_name": k.SpotName, "method": k.Method, "bait": k.Bait, "released": k.Released,
					})
				}
				return map[string]any{"items": items}, nil
			},
		})
		r.Register(&Source{
			ID: "fishing.catch_stats", Title: "渔获统计", Topics: fish, Cost: 0, UserScoped: true,
			Doc:    "当前用户累计出钓次数、鱼获条数、鱼种数、放流条数",
			Output: `{"trips":12,"fish":56,"species":7,"released":10}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				return fs.Journal.Stats(ctx, c.UserID)
			},
		})
		r.Register(&Source{
			ID: "fishing.spots", Title: "我的钓点", Topics: fish, Cost: 0, UserScoped: true,
			Doc:    "当前用户保存的私人钓点（名称、坐标、水域类型）",
			Output: `{"items":[{"name":"千岛湖东南湖区","lat":29.6,"lon":119.0,"water_type":"水库","note":""}]}`,
			Fetch: func(ctx context.Context, c Call) (any, error) {
				list, err := fs.Journal.ListSpots(ctx, c.UserID)
				if err != nil {
					return nil, err
				}
				items := make([]map[string]any, 0, len(list))
				for _, s := range list {
					items = append(items, map[string]any{"name": s.Name, "lat": s.Lat, "lon": s.Lon,
						"water_type": s.WaterType, "note": s.Note})
				}
				return map[string]any{"items": items}, nil
			},
		})
	}
	return r
}

// callTool 调用 AI 工具并解析 JSON；工具返回 {"error":...} 时转成 Go error。
func callTool(ctx context.Context, t ToolDispatcher, name string, args map[string]any) (map[string]any, error) {
	b, _ := json.Marshal(args)
	out := t.Dispatch(ctx, name, string(b))
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		return nil, fmt.Errorf("数据源返回格式不正确")
	}
	if e, ok := m["error"]; ok && e != nil && e != "" {
		return nil, fmt.Errorf("%v", shorten(fmt.Sprint(e), 120))
	}
	return m, nil
}

func pick(m map[string]any, extra map[string]any, keys ...string) map[string]any {
	out := map[string]any{}
	for _, k := range keys {
		if v, ok := m[k]; ok {
			out[k] = v
		}
	}
	for k, v := range extra {
		out[k] = v
	}
	return out
}

func pickList(v any, keys ...string) []any {
	arr, _ := v.([]any)
	out := make([]any, 0, len(arr))
	for _, e := range arr {
		if m, ok := e.(map[string]any); ok {
			out = append(out, pick(m, nil, keys...))
		}
	}
	return out
}

func fmtYMD(s string) string {
	if len(s) == 8 && !strings.Contains(s, "-") {
		return s[:4] + "-" + s[4:6] + "-" + s[6:]
	}
	return s
}

func shorten(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

// placeSuffixes 是地名库常认不出的水域后缀（按长度从长到短）。
var placeSuffixes = []string{"水利枢纽", "水电站", "水库", "钓场", "钓点", "河段", "湖区", "大坝"}

// placeFallbacks 给出地名查不到时依次尝试的候选：去掉水域后缀（至少留 2 个字）。
func placeFallbacks(place string) []string {
	p := strings.TrimSpace(place)
	var out []string
	for _, suf := range placeSuffixes {
		if strings.HasSuffix(p, suf) {
			base := strings.TrimSpace(strings.TrimSuffix(p, suf))
			if len([]rune(base)) >= 2 && base != p {
				out = append(out, base)
			}
			break
		}
	}
	return out
}
