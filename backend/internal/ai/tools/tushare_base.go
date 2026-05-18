package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// 共享缓存，避免每次工具调用都重拉 stock_basic / fund_basic 大表。
type instrumentCache struct {
	mu     sync.Mutex
	stocks []tushare.Instrument
	etfs   []tushare.Instrument
	idxs   []tushare.Instrument
	futs   []tushare.Instrument
}

var sharedInstrumentCache = &instrumentCache{}

func (i *instrumentCache) all(ctx context.Context, c *tushare.Client) (
	stocks, etfs, idxs, futs []tushare.Instrument, err error,
) {
	i.mu.Lock()
	defer i.mu.Unlock()
	if i.stocks == nil {
		s, e := c.StockBasic(ctx)
		if e != nil {
			err = e
			return
		}
		i.stocks = s
	}
	if i.etfs == nil {
		s, e := c.FundBasic(ctx, "E")
		if e != nil {
			err = e
			return
		}
		i.etfs = s
	}
	if i.idxs == nil {
		s, e := c.IndexBasic(ctx, "SSE")
		if e != nil {
			err = e
			return
		}
		// 同时拉一份 SZSE 指数做并集（深证成指等）
		if s2, e2 := c.IndexBasic(ctx, "SZSE"); e2 == nil {
			s = append(s, s2...)
		}
		i.idxs = s
	}
	if i.futs == nil {
		i.futs = c.AllFutures(ctx)
	}
	return i.stocks, i.etfs, i.idxs, i.futs, nil
}

func registerBaseTushare(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&searchInstrumentTool{c: c})
	r.MustRegister(&getQuoteTool{c: c})
	r.MustRegister(&compareQuotesTool{c: c})
	r.MustRegister(&listIndustryStocksTool{c: c})
	r.MustRegister(&listEtfsByThemeTool{c: c})
	// 注：get_market_snapshot 已迁移到 realtime.go，使用东方财富 push2 实时数据。
}

// ── 1. search_instrument ────────────────────────────────────────────────

type searchInstrumentTool struct{ c *tushare.Client }

func (t *searchInstrumentTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "search_instrument",
		Description: "按关键字（中文名 / 代码 / 行业关键字）在 A 股、ETF、指数、期货全集里搜索标的，返回 ts_code、名称、所属类别、行业。当用户提到\"茅台\"、\"军工 ETF\"、\"沪深 300\"等模糊描述时使用。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"query":       {Type: "string", Description: "搜索关键字（中文名/代码/行业）"},
				"asset_class": {Type: "string", Enum: []string{"stock", "etf", "index", "futures", "all"}, Description: "限定资产类别（默认 all）"},
				"limit":       {Type: "integer", Description: "返回前 N 条匹配（默认 8，最大 20）"},
			},
			Required: []string{"query"},
		},
	}
}

func (t *searchInstrumentTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Query      string `json:"query"`
		AssetClass string `json:"asset_class,omitempty"`
		Limit      int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Query)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "查询关键字不能为空"}), nil
	}
	limit := clampInt(in.Limit, 1, 20, 8)
	ac := strings.ToLower(strings.TrimSpace(in.AssetClass))
	if ac == "" {
		ac = "all"
	}
	stocks, etfs, idxs, futs, err := sharedInstrumentCache.all(ctx, t.c)
	if err != nil {
		return "", err
	}
	pools := []struct {
		name string
		list []tushare.Instrument
	}{}
	if ac == "all" || ac == "stock" {
		pools = append(pools, struct {
			name string
			list []tushare.Instrument
		}{"stock", stocks})
	}
	if ac == "all" || ac == "etf" {
		pools = append(pools, struct {
			name string
			list []tushare.Instrument
		}{"etf", etfs})
	}
	if ac == "all" || ac == "index" {
		pools = append(pools, struct {
			name string
			list []tushare.Instrument
		}{"index", idxs})
	}
	if ac == "all" || ac == "futures" {
		pools = append(pools, struct {
			name string
			list []tushare.Instrument
		}{"futures", futs})
	}

	qLow := strings.ToLower(q)
	matches := []map[string]any{}
	for _, pool := range pools {
		for _, ins := range pool.list {
			if matched(ins, qLow) {
				m := map[string]any{
					"ts_code": ins.TsCode,
					"name":    ins.Name,
					"asset":   pool.name,
				}
				if ins.Industry != "" {
					m["industry"] = ins.Industry
				}
				if ins.Market != "" {
					m["exchange"] = ins.Market
				}
				matches = append(matches, m)
				if len(matches) >= limit {
					break
				}
			}
		}
		if len(matches) >= limit {
			break
		}
	}
	return tool.EncodeJSON(map[string]any{
		"query":   q,
		"count":   len(matches),
		"matches": matches,
	}), nil
}

func matched(ins tushare.Instrument, qLow string) bool {
	for _, f := range []string{ins.Name, ins.TsCode, ins.Symbol} {
		if f != "" && strings.Contains(strings.ToLower(f), qLow) {
			return true
		}
	}
	if ins.Industry != "" && matchAnyIndustry(ins.Industry, qLow) {
		return true
	}
	return false
}

// ── 2. get_quote ────────────────────────────────────────────────────────

type getQuoteTool struct{ c *tushare.Client }

func (t *getQuoteTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "get_quote",
		Description: "查询单只 A 股 / ETF / 指数 / 期货最近 N 个交易日的日线行情，返回收盘价、涨跌幅、成交量序列以及汇总（最新价、区间最高/最低、累计涨跌幅）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbol": {Type: "string", Description: "标的代码：6 位数字或 ts_code 全码"},
				"days":   {Type: "integer", Description: "返回最近多少个交易日（默认 20，最大 120）"},
			},
			Required: []string{"symbol"},
		},
	}
}

func (t *getQuoteTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbol string `json:"symbol"`
		Days   int    `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	raw := strings.TrimSpace(in.Symbol)
	if raw == "" {
		return tool.EncodeJSON(map[string]any{"error": "symbol 必填"}), nil
	}
	code := tushare.NormalizeSymbol(raw)
	days := clampInt(in.Days, 1, 120, 20)
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 30))
	candles, err := t.c.HistoryFor(ctx, code, start, end)
	if err != nil {
		return "", err
	}
	if len(candles) == 0 {
		return tool.EncodeJSON(map[string]any{
			"symbol": code,
			"asset":  tushare.AssetClassOf(code),
			"error":  "未拉到任何行情（代码可能错误或非交易日）",
		}), nil
	}
	tail := tailN(candles, days)
	first, last := tail[0], tail[len(tail)-1]
	periodPct := 0.0
	if first.Close != 0 {
		periodPct = (last.Close - first.Close) / first.Close * 100.0
	}
	hi, lo := -1e18, 1e18
	for _, c := range tail {
		if c.High > hi {
			hi = c.High
		}
		if c.Low > 0 && c.Low < lo {
			lo = c.Low
		}
	}
	series := make([]map[string]any, 0, len(tail))
	for _, c := range tail {
		series = append(series, map[string]any{
			"date":    formatDate(c.TradeDate),
			"close":   c.Close,
			"pct_chg": c.PctChg,
		})
	}
	return tool.EncodeJSON(map[string]any{
		"symbol":         code,
		"asset":          tushare.AssetClassOf(code),
		"exchange":       tushare.ExchangeOf(code),
		"days":           len(tail),
		"period_start":   formatDate(first.TradeDate),
		"period_end":     formatDate(last.TradeDate),
		"last_close":     last.Close,
		"last_pct_chg":   last.PctChg,
		"period_pct_chg": round(periodPct, 3),
		"period_high":    nonNeg(hi),
		"period_low":     posOnly(lo),
		"series":         series,
	}), nil
}

// ── 3. compare_quotes ──────────────────────────────────────────────────

type compareQuotesTool struct{ c *tushare.Client }

func (t *compareQuotesTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "compare_quotes",
		Description: "一次性比较多个标的（最多 6 个）最近 N 天的累计涨跌幅、最新价、区间最高最低，用于横向对比问题。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"symbols": {Type: "array", Items: &tool.ParameterProperty{Type: "string"}, Description: "标的代码数组"},
				"days":    {Type: "integer", Description: "比较窗口（默认 30）"},
			},
			Required: []string{"symbols"},
		},
	}
}

func (t *compareQuotesTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Symbols []string `json:"symbols"`
		Days    int      `json:"days,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	var syms []string
	for _, s := range in.Symbols {
		s = strings.TrimSpace(s)
		if s != "" {
			syms = append(syms, s)
		}
	}
	if len(syms) == 0 {
		return tool.EncodeJSON(map[string]any{"error": "symbols 不能为空"}), nil
	}
	if len(syms) > 6 {
		return tool.EncodeJSON(map[string]any{"error": "一次最多比较 6 个标的，请拆分多次调用"}), nil
	}
	days := clampInt(in.Days, 1, 120, 30)
	end := time.Now()
	start := end.AddDate(0, 0, -(days*2 + 30))
	out := []map[string]any{}
	for _, raw := range syms {
		code := tushare.NormalizeSymbol(raw)
		candles, err := t.c.HistoryFor(ctx, code, start, end)
		if err != nil {
			out = append(out, map[string]any{"symbol": code, "error": err.Error()})
			continue
		}
		if len(candles) == 0 {
			out = append(out, map[string]any{"symbol": code, "error": "未拉到行情"})
			continue
		}
		tail := tailN(candles, days)
		first, last := tail[0], tail[len(tail)-1]
		pct := 0.0
		if first.Close != 0 {
			pct = (last.Close - first.Close) / first.Close * 100.0
		}
		out = append(out, map[string]any{
			"symbol":         code,
			"asset":          tushare.AssetClassOf(code),
			"days":           len(tail),
			"last_close":     last.Close,
			"period_pct_chg": round(pct, 3),
			"last_date":      formatDate(last.TradeDate),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		ai, _ := out[i]["period_pct_chg"].(float64)
		bj, _ := out[j]["period_pct_chg"].(float64)
		return ai > bj
	})
	return tool.EncodeJSON(map[string]any{
		"days":                     days,
		"ranked_by_period_pct_chg": out,
	}), nil
}

// ── 4. list_industry_stocks ────────────────────────────────────────────

type listIndustryStocksTool struct{ c *tushare.Client }

func (t *listIndustryStocksTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "list_industry_stocks",
		Description: "按行业关键字列出 A 股个股（支持\"有色金属/新能源/半导体/医药/钢铁/军工/金融\"等大类，会自动展开为细分子行业；也支持\"白酒/铜/光伏\"等细分名）。返回该行业内的股票 ts_code 与名称，便于后续 get_quote / compare_quotes。当关键字 0 命中时返回 distinct_industries 让上层选择。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"industry_keyword": {Type: "string", Description: "行业关键字（大类或细分均可）"},
				"limit":            {Type: "integer", Description: "前 N 只（默认 30，最大 80）"},
			},
			Required: []string{"industry_keyword"},
		},
	}
}

func (t *listIndustryStocksTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		IndustryKeyword string `json:"industry_keyword"`
		Limit           int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	kw := strings.TrimSpace(in.IndustryKeyword)
	if kw == "" {
		return tool.EncodeJSON(map[string]any{"error": "industry_keyword 必填"}), nil
	}
	limit := clampInt(in.Limit, 1, 80, 30)
	stocks, _, _, _, err := sharedInstrumentCache.all(ctx, t.c)
	if err != nil {
		return "", err
	}
	hits := []map[string]any{}
	for _, s := range stocks {
		if matchAnyIndustry(s.Industry, kw) {
			m := map[string]any{
				"ts_code":  s.TsCode,
				"name":     s.Name,
				"industry": s.Industry,
			}
			if s.Area != "" {
				m["area"] = s.Area
			}
			hits = append(hits, m)
			if len(hits) >= limit {
				break
			}
		}
	}
	if len(hits) == 0 {
		seen := map[string]bool{}
		indus := []string{}
		for _, s := range stocks {
			if s.Industry == "" || seen[s.Industry] {
				continue
			}
			seen[s.Industry] = true
			indus = append(indus, s.Industry)
		}
		sort.Strings(indus)
		if len(indus) > 80 {
			indus = indus[:80]
		}
		return tool.EncodeJSON(map[string]any{
			"industry_keyword":    kw,
			"count":               0,
			"stocks":              []any{},
			"hint":                "未匹配到该行业。请从 distinct_industries 中挑选实际存在的细分行业关键字重试，或换用 search_instrument 按子行业逐一查询。",
			"distinct_industries": indus,
		}), nil
	}
	return tool.EncodeJSON(map[string]any{
		"industry_keyword": kw,
		"count":            len(hits),
		"stocks":           hits,
	}), nil
}

// ── 5. list_etfs_by_theme ──────────────────────────────────────────────

type listEtfsByThemeTool struct{ c *tushare.Client }

func (t *listEtfsByThemeTool) Spec() tool.Spec {
	return tool.Spec{
		Name:        "list_etfs_by_theme",
		Description: "按主题/类型关键字筛选场内 ETF（如\"科创\"、\"医疗\"、\"红利\"、\"债券\"等）。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"theme_keyword": {Type: "string", Description: "主题/类型关键字"},
				"limit":         {Type: "integer", Description: "前 N 只（默认 15，最大 40）"},
			},
			Required: []string{"theme_keyword"},
		},
	}
}

func (t *listEtfsByThemeTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		ThemeKeyword string `json:"theme_keyword"`
		Limit        int    `json:"limit,omitempty"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	kw := strings.TrimSpace(in.ThemeKeyword)
	if kw == "" {
		return tool.EncodeJSON(map[string]any{"error": "theme_keyword 必填"}), nil
	}
	limit := clampInt(in.Limit, 1, 40, 15)
	_, etfs, _, _, err := sharedInstrumentCache.all(ctx, t.c)
	if err != nil {
		return "", err
	}
	kwLow := strings.ToLower(kw)
	hits := []map[string]any{}
	for _, f := range etfs {
		if strings.Contains(strings.ToLower(f.Name), kwLow) ||
			strings.Contains(strings.ToLower(f.Industry), kwLow) ||
			strings.Contains(strings.ToLower(f.Area), kwLow) {
			m := map[string]any{
				"ts_code": f.TsCode,
				"name":    f.Name,
			}
			if f.Industry != "" {
				m["fund_type"] = f.Industry
			}
			if f.Area != "" {
				m["manager"] = f.Area
			}
			hits = append(hits, m)
			if len(hits) >= limit {
				break
			}
		}
	}
	return tool.EncodeJSON(map[string]any{
		"theme_keyword": kw,
		"count":         len(hits),
		"etfs":          hits,
	}), nil
}

// ── helpers ─────────────────────────────────────────────────────────────

func ymd(t time.Time) string {
	return t.Format("20060102")
}

func splitFields(fields string) []string {
	parts := strings.Split(fields, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func clampInt(v, lo, hi, def int) int {
	if v <= 0 {
		return def
	}
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func tailN[T any](s []T, n int) []T {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:]
}

func formatDate(yyyymmdd string) string {
	if len(yyyymmdd) != 8 {
		return yyyymmdd
	}
	return fmt.Sprintf("%s-%s-%s", yyyymmdd[:4], yyyymmdd[4:6], yyyymmdd[6:8])
}

func round(v float64, digits int) float64 {
	mul := 1.0
	for i := 0; i < digits; i++ {
		mul *= 10
	}
	return float64(int64(v*mul+0.5*sign(v))) / mul
}

func sign(v float64) float64 {
	if v < 0 {
		return -1
	}
	return 1
}

func nonNeg(v float64) any {
	if v <= -1e17 {
		return nil
	}
	return v
}

func posOnly(v float64) any {
	if v >= 1e17 {
		return nil
	}
	return v
}

// industryAliases 把常见大类映射到 Tushare stock_basic.industry 里实际存在的细分行业关键字。
//
// 背景：Tushare 的 industry 字段是细分（如"铜"、"铝"、"黄金"、"半导体"），
// 模型经常用大类提问（"有色金属"、"新能源"），直接 substring 匹配会 0 命中。
// 用这张表把大类展开成多个子串，做 OR 匹配。
var industryAliases = map[string][]string{
	"有色金属":   {"铜", "铝", "铅锌", "黄金", "稀土", "钼", "钨", "镍", "锂", "小金属", "金属新材", "工业金属"},
	"有色":     {"铜", "铝", "铅锌", "黄金", "稀土", "钼", "钨", "镍", "锂", "小金属", "金属新材", "工业金属"},
	"金属":     {"铜", "铝", "铅锌", "黄金", "稀土", "钼", "钨", "镍", "小金属", "金属新材"},
	"新能源":    {"锂电池", "光伏", "风电", "新能源车", "储能", "锂", "电池"},
	"新能源车":   {"汽车整车", "汽车零部件", "锂电池"},
	"半导体":    {"半导体", "集成电路", "电子元件", "芯片"},
	"芯片":     {"半导体", "集成电路", "芯片"},
	"医药":     {"医药商业", "化学制药", "中药", "生物制品", "医疗器械", "医疗服务"},
	"生物医药":   {"生物制品", "化学制药", "医药"},
	"中药":     {"中药"},
	"白酒":     {"白酒"},
	"消费":     {"白酒", "食品饮料", "饮料制造", "服装家纺", "家用轻工", "化妆品"},
	"食品饮料":   {"白酒", "食品饮料", "饮料制造", "调味发酵品"},
	"钢铁":     {"普钢", "特钢", "钢铁"},
	"煤炭":     {"煤炭开采", "焦炭加工", "动力煤"},
	"石油":     {"石油开采", "石油加工", "油气"},
	"军工":     {"航空装备", "航天装备", "兵器兵装", "军工电子", "船舶制造"},
	"金融":     {"银行", "保险", "证券", "多元金融"},
	"地产":     {"房地产开发", "园区开发", "房地产服务"},
	"房地产":    {"房地产开发", "园区开发", "房地产服务"},
	"光伏":     {"光伏", "光伏设备", "光伏材料"},
	"风电":     {"风电设备", "风电"},
	"汽车":     {"汽车整车", "汽车零部件", "汽车服务"},
	"机器人":    {"机器人", "工业自动化"},
	"AI":     {"软件开发", "互联网", "计算机应用", "电子元件"},
	"人工智能":   {"软件开发", "互联网", "计算机应用"},
}

// expandIndustryKeywords 返回与 kw 匹配的子行业候选关键字（小写）。
// 若 kw 命中别名表，返回别名集合；否则返回 kw 本身。
func expandIndustryKeywords(kw string) []string {
	kw = strings.TrimSpace(kw)
	if kw == "" {
		return nil
	}
	if subs, ok := industryAliases[kw]; ok {
		out := make([]string, 0, len(subs))
		for _, s := range subs {
			out = append(out, strings.ToLower(s))
		}
		return out
	}
	return []string{strings.ToLower(kw)}
}

// matchAnyIndustry 检查 industry 字段是否匹配 kw 或其任意别名（子串包含）。
func matchAnyIndustry(industry, kw string) bool {
	if industry == "" {
		return false
	}
	indLow := strings.ToLower(industry)
	for _, k := range expandIndustryKeywords(kw) {
		if k != "" && strings.Contains(indLow, k) {
			return true
		}
	}
	return false
}
