package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tool"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// get_dominant_contract —— 给 LLM 用的"任意期货 / ETF 期权 → 当前主力合约"工具。
//
// LLM 在被问"螺纹钢现在多少 / IF 主力 / 50ETF 期权近月" 这类话题时，**禁止
// 自行编合约月份**（模型训练时的"主力"早就过期了），必须先调用这个工具拿到
// 真实合约 ts_code，再喂回 get_quote / get_option_quote。
//
// 主力定义：
//   - 期货：取该品种在"最新交易日"的合约清单中，**成交量 vol 最大**的合约；
//     同时返回"持仓量 oi 最大"的合约作为次主力对照。
//   - ETF 期权：取该标的的「当月 + ATM」近月主力（按当日成交量降序选 1 张
//     ATM 附近的 PUT 与 CALL）。

func registerDominant(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&getDominantContractTool{c: c})
}

type getDominantContractTool struct{ c *tushare.Client }

func (t *getDominantContractTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_dominant_contract",
		Description: "把『螺纹钢 / 焦煤 / 沪深300股指 / 原油 / 50ETF期权 / 沪深300期权』等品种名（或品种字母如 RB / IF / CU）解析为真实的当前主力合约 ts_code，附带最新成交量、持仓量、收盘价。模型不知道现在是几月，禁止凭印象猜测月份；一律先调本工具拿真实合约，再调用 get_quote / get_option_quote。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"product": {Type: "string", Description: "品种关键字：中文名（螺纹钢/焦煤/铁矿石/原油/沪深300股指/50ETF期权 等）、英文品种字母（RB/IF/IC/IH/IM/T/TF/CU/AL/NI/AU/AG/SC/M/Y/P/CF/SR/FG …）或 ETF 代码（510050/510300/159919/159915/588000）"},
			},
			Required: []string{"product"},
		},
	}
}

func (t *getDominantContractTool) Run(ctx context.Context, args json.RawMessage) (string, error) {
	var in struct {
		Product string `json:"product"`
	}
	if err := json.Unmarshal(args, &in); err != nil {
		return "", err
	}
	q := strings.TrimSpace(in.Product)
	if q == "" {
		return tool.EncodeJSON(map[string]any{"error": "product 必填"}), nil
	}

	// 1) 先尝试映射成"期权 ETF 标的"
	if etf, ok := resolveOptionUnderlying(q); ok {
		return t.runOption(ctx, etf, q)
	}

	// 2) 否则按期货品种处理
	prodCode, exchange := resolveFuturesProduct(q)
	if prodCode == "" {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("无法识别品种 %q；支持的关键字示例：螺纹钢/焦煤/铁矿石/原油/沪深300股指/IF/RB/CU/50ETF期权 等", q),
			"product": q,
		}), nil
	}
	return t.runFutures(ctx, prodCode, exchange, q)
}

// ── 期货主力 ────────────────────────────────────────────────────────────

func (t *getDominantContractTool) runFutures(ctx context.Context, prod, exchange, query string) (string, error) {
	// 拉最近 8 天该交易所行情（足够覆盖周末 + 节假日）
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)
	rows, err := t.c.FuturesDailyBatch(ctx, tushare.FutDailyParams{
		Exchange:  exchange,
		StartDate: ymd(start),
		EndDate:   ymd(now),
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error": fmt.Sprintf("fut_daily(%s) 失败: %s", exchange, err.Error()),
		}), nil
	}
	if len(rows) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("fut_daily(%s) 近 8 天无数据，可能 token 无权或当周全节假日", exchange),
			"product": query,
		}), nil
	}

	// 找最新交易日 & 过滤该品种
	latest := ""
	for _, r := range rows {
		if r.TradeDate > latest {
			latest = r.TradeDate
		}
	}
	filtered := []tushare.FuturesDaily{}
	for _, r := range rows {
		if r.TradeDate != latest {
			continue
		}
		p, _ := tushare.FuturesProduct(r.TsCode)
		if !strings.EqualFold(p, prod) {
			continue
		}
		filtered = append(filtered, r)
	}
	if len(filtered) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("品种 %s 在 %s 没有最新合约（exchange=%s 可能配错）", prod, formatDate(latest), exchange),
			"product": query,
		}), nil
	}

	// 主力：vol 最大；次主力：oi 最大且与主力不同
	byVol := make([]tushare.FuturesDaily, len(filtered))
	copy(byVol, filtered)
	sort.Slice(byVol, func(i, j int) bool { return byVol[i].Vol > byVol[j].Vol })

	byOI := make([]tushare.FuturesDaily, len(filtered))
	copy(byOI, filtered)
	sort.Slice(byOI, func(i, j int) bool { return byOI[i].OI > byOI[j].OI })

	dominant := byVol[0]
	var secondary *tushare.FuturesDaily
	for _, r := range byOI {
		if r.TsCode != dominant.TsCode {
			secondary = &r
			break
		}
	}

	allList := make([]map[string]any, 0, len(filtered))
	for _, r := range filtered {
		allList = append(allList, map[string]any{
			"ts_code":        r.TsCode,
			"delivery_month": tushare.FuturesDeliveryMonth(r.TsCode),
			"close":          round(r.Close, 4),
			"vol":            int(r.Vol),
			"oi":             int(r.OI),
		})
	}
	sort.Slice(allList, func(i, j int) bool {
		ai, _ := allList[i]["vol"].(int)
		bj, _ := allList[j]["vol"].(int)
		return ai > bj
	})

	out := map[string]any{
		"product":     prod,
		"asset_class": "futures",
		"exchange":    exchange,
		"as_of":       formatDate(dominant.TradeDate),
		"dominant": map[string]any{
			"ts_code":        dominant.TsCode,
			"delivery_month": tushare.FuturesDeliveryMonth(dominant.TsCode),
			"close":          round(dominant.Close, 4),
			"settle":         round(dominant.Settle, 4),
			"vol":            int(dominant.Vol),
			"oi":             int(dominant.OI),
		},
		"contracts_count": len(filtered),
		"all_contracts":   allList,
	}
	if secondary != nil {
		out["secondary"] = map[string]any{
			"ts_code":        secondary.TsCode,
			"delivery_month": tushare.FuturesDeliveryMonth(secondary.TsCode),
			"close":          round(secondary.Close, 4),
			"vol":            int(secondary.Vol),
			"oi":             int(secondary.OI),
		}
	}
	return tool.EncodeJSON(out), nil
}

// ── ETF 期权主力 ───────────────────────────────────────────────────────

func (t *getDominantContractTool) runOption(ctx context.Context, underlying, query string) (string, error) {
	exchange := tushare.OptionExchangeOf(underlying)
	if exchange == "" {
		return tool.EncodeJSON(map[string]any{
			"error":   "无法推断期权交易所（仅支持 SSE/SZSE 的 ETF 期权）",
			"product": query,
		}), nil
	}
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)

	// 现价
	hist, err := t.c.HistoryFor(ctx, underlying, start, now)
	if err != nil || len(hist) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("ETF %s 行情拉取失败/为空", underlying),
			"product": query,
		}), nil
	}
	spot := hist[len(hist)-1].Close
	spotDate := hist[len(hist)-1].TradeDate

	// 全市场 PUT + CALL（近 8 天，取每个合约的最新一行）
	allDaily, err := t.c.OptionDailyBatch(ctx, tushare.OptDailyParams{
		Exchange:  exchange,
		StartDate: ymd(start),
		EndDate:   ymd(now),
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("opt_daily(%s) 失败: %s", exchange, err.Error()),
			"product": query,
		}), nil
	}
	latestByCode := map[string]tushare.OptionDaily{}
	latestDate := ""
	for _, r := range allDaily {
		cur, ok := latestByCode[r.TsCode]
		if !ok || r.TradeDate > cur.TradeDate {
			latestByCode[r.TsCode] = r
		}
		if r.TradeDate > latestDate {
			latestDate = r.TradeDate
		}
	}

	// 合约清单（只该标的）
	contracts, err := t.c.OptionBasic(ctx, tushare.OptBasicParams{
		Exchange: exchange,
		OptCode:  underlying,
	})
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("opt_basic 失败: %s", err.Error()),
			"product": query,
		}), nil
	}

	// 按"合约月份"分组并算每月总成交量，找成交量最大的月份当作主力月
	type monthAgg struct {
		Month string
		Vol   float64
		OI    float64
		Calls []enrichedOpt
		Puts  []enrichedOpt
	}
	monthMap := map[string]*monthAgg{}
	for _, oc := range contracts {
		dte := daysUntil(now, oc.MaturityDate)
		if dte < 0 {
			continue
		}
		q, ok := latestByCode[oc.TsCode]
		if !ok {
			continue
		}
		m := oc.SMonth
		if m == "" {
			m = oc.MaturityDate[:6]
		}
		agg := monthMap[m]
		if agg == nil {
			agg = &monthAgg{Month: m}
			monthMap[m] = agg
		}
		agg.Vol += q.Vol
		agg.OI += q.OI
		enr := enrichedOpt{Contract: oc, Daily: q, DTE: dte}
		if oc.CallPut == "C" {
			agg.Calls = append(agg.Calls, enr)
		} else if oc.CallPut == "P" {
			agg.Puts = append(agg.Puts, enr)
		}
	}
	if len(monthMap) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   "未匹配到任何在交易的合约（可能 token 缺权限）",
			"product": query, "underlying": underlying,
		}), nil
	}
	months := make([]*monthAgg, 0, len(monthMap))
	for _, m := range monthMap {
		months = append(months, m)
	}
	sort.Slice(months, func(i, j int) bool { return months[i].Vol > months[j].Vol })
	main := months[0]

	// 在主力月份里挑 ATM call & put（行权价距 spot 最近）
	pickATM := func(list []enrichedOpt) *enrichedOpt {
		if len(list) == 0 {
			return nil
		}
		var best *enrichedOpt
		bestDist := -1.0
		for i := range list {
			d := list[i].Contract.ExercisePrice - spot
			if d < 0 {
				d = -d
			}
			if best == nil || d < bestDist {
				best = &list[i]
				bestDist = d
			}
		}
		return best
	}
	atmCall := pickATM(main.Calls)
	atmPut := pickATM(main.Puts)

	// 月份摘要（前 4 个月）
	if len(months) > 4 {
		months = months[:4]
	}
	monthOut := make([]map[string]any, 0, len(months))
	for _, m := range months {
		monthOut = append(monthOut, map[string]any{
			"month":     m.Month,
			"total_vol": int(m.Vol),
			"total_oi":  int(m.OI),
			"calls":     len(m.Calls),
			"puts":      len(m.Puts),
		})
	}

	out := map[string]any{
		"product":          query,
		"asset_class":      "option",
		"underlying":       underlying,
		"exchange":         exchange,
		"as_of":            formatDate(latestDate),
		"spot":             round(spot, 4),
		"spot_date":        formatDate(spotDate),
		"dominant_month":   main.Month,
		"month_total_vol":  int(main.Vol),
		"months_overview":  monthOut,
	}
	if atmCall != nil {
		out["atm_call"] = enrichedToMap(atmCall)
	}
	if atmPut != nil {
		out["atm_put"] = enrichedToMap(atmPut)
	}
	out["notes"] = "dominant_month 按主力月份选取（成交量最大）。atm_call / atm_put 是该月份内行权价最贴近 spot 的合约；如需别的虚值档可直接用 list_option_contracts 配合月份过滤。"
	return tool.EncodeJSON(out), nil
}

type enrichedOpt struct {
	Contract tushare.OptionContract
	Daily    tushare.OptionDaily
	DTE      int
}

func enrichedToMap(e *enrichedOpt) map[string]any {
	return map[string]any{
		"ts_code":       e.Contract.TsCode,
		"name":          e.Contract.Name,
		"call_put":      e.Contract.CallPut,
		"strike":        e.Contract.ExercisePrice,
		"maturity_date": formatDate(e.Contract.MaturityDate),
		"dte":           e.DTE,
		"per_unit":      int(e.Contract.PerUnit),
		"close":         round(e.Daily.Close, 4),
		"vol":           int(e.Daily.Vol),
		"oi":            int(e.Daily.OI),
	}
}

// ── 品种映射 ───────────────────────────────────────────────────────────

// resolveFuturesProduct 把中文 / 缩写关键字解析成 (品种代码, 交易所)。
//
// 规则：先在 alias map 找；找不到再判定纯字母字符串是否本身就是品种字母
// 直接用（exchange 由 product → exchange 二级表反查）。
func resolveFuturesProduct(q string) (product, exchange string) {
	key := strings.TrimSpace(q)
	keyUpper := strings.ToUpper(key)
	if hit, ok := futuresProductAlias[key]; ok {
		return hit.product, hit.exchange
	}
	if hit, ok := futuresProductAlias[keyUpper]; ok {
		return hit.product, hit.exchange
	}
	if isAllLetters(keyUpper) {
		if ex, ok := productToExchange[keyUpper]; ok {
			return keyUpper, ex
		}
	}
	return "", ""
}

// resolveOptionUnderlying 把"50ETF期权 / 沪深300期权 / 510300 / 159915"
// 等关键字解析成 ETF ts_code（仅 ETF 期权，股指期权另算）。
func resolveOptionUnderlying(q string) (string, bool) {
	key := strings.TrimSpace(q)
	if v, ok := optionUnderlyingAlias[key]; ok {
		return v, true
	}
	if v, ok := optionUnderlyingAlias[strings.ToUpper(key)]; ok {
		return v, true
	}
	// 直接给了 ETF 代码
	if norm := tushare.NormalizeSymbol(key); norm != "" {
		if _, ok := etfOptionUnderlyings[strings.ToUpper(norm)]; ok {
			return strings.ToUpper(norm), true
		}
	}
	return "", false
}

func isAllLetters(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'A' && c <= 'Z') {
			return false
		}
	}
	return true
}

type productAlias struct{ product, exchange string }

// 主流品种白名单（中文 + 英文别名）。覆盖国内活跃期货品种 90%+。
var futuresProductAlias = map[string]productAlias{
	// CFFEX 股指 / 国债
	"沪深300股指": {"IF", "CFFEX"}, "沪深300期指": {"IF", "CFFEX"}, "if": {"IF", "CFFEX"},
	"中证500股指": {"IC", "CFFEX"}, "ic": {"IC", "CFFEX"},
	"上证50股指": {"IH", "CFFEX"}, "ih": {"IH", "CFFEX"},
	"中证1000股指": {"IM", "CFFEX"}, "im": {"IM", "CFFEX"},
	"5年期国债": {"TF", "CFFEX"}, "tf": {"TF", "CFFEX"},
	"10年期国债": {"T", "CFFEX"}, "10年国债": {"T", "CFFEX"}, "t": {"T", "CFFEX"},
	"2年期国债": {"TS", "CFFEX"}, "ts": {"TS", "CFFEX"},
	"30年期国债": {"TL", "CFFEX"}, "tl": {"TL", "CFFEX"},
	// SHFE 黑色 / 有色 / 贵金属
	"螺纹钢": {"RB", "SHFE"}, "螺纹": {"RB", "SHFE"}, "rb": {"RB", "SHFE"},
	"热卷": {"HC", "SHFE"}, "热轧": {"HC", "SHFE"}, "hc": {"HC", "SHFE"},
	"线材": {"WR", "SHFE"}, "wr": {"WR", "SHFE"},
	"铜":  {"CU", "SHFE"}, "cu": {"CU", "SHFE"},
	"铝":  {"AL", "SHFE"}, "al": {"AL", "SHFE"},
	"锌":  {"ZN", "SHFE"}, "zn": {"ZN", "SHFE"},
	"铅":  {"PB", "SHFE"}, "pb": {"PB", "SHFE"},
	"镍":  {"NI", "SHFE"}, "ni": {"NI", "SHFE"},
	"锡":  {"SN", "SHFE"}, "sn": {"SN", "SHFE"},
	"黄金": {"AU", "SHFE"}, "au": {"AU", "SHFE"},
	"白银": {"AG", "SHFE"}, "ag": {"AG", "SHFE"},
	"沥青": {"BU", "SHFE"}, "bu": {"BU", "SHFE"},
	"燃油": {"FU", "SHFE"}, "燃料油": {"FU", "SHFE"}, "fu": {"FU", "SHFE"},
	"橡胶": {"RU", "SHFE"}, "天然橡胶": {"RU", "SHFE"}, "ru": {"RU", "SHFE"},
	// INE 能源
	"原油":   {"SC", "INE"}, "sc": {"SC", "INE"},
	"低硫燃油": {"LU", "INE"}, "lu": {"LU", "INE"},
	"20号胶": {"NR", "INE"}, "nr": {"NR", "INE"},
	// DCE 农产品 / 能化
	"豆粕":  {"M", "DCE"}, "m": {"M", "DCE"},
	"豆油":  {"Y", "DCE"}, "y": {"Y", "DCE"},
	"豆一":  {"A", "DCE"}, "黄大豆1号": {"A", "DCE"}, "a": {"A", "DCE"},
	"豆二":  {"B", "DCE"}, "黄大豆2号": {"B", "DCE"}, "b": {"B", "DCE"},
	"棕榈油": {"P", "DCE"}, "棕榈": {"P", "DCE"}, "p": {"P", "DCE"},
	"玉米":  {"C", "DCE"}, "c": {"C", "DCE"},
	"淀粉":  {"CS", "DCE"}, "玉米淀粉": {"CS", "DCE"}, "cs": {"CS", "DCE"},
	"鸡蛋":  {"JD", "DCE"}, "jd": {"JD", "DCE"},
	"铁矿":  {"I", "DCE"}, "铁矿石": {"I", "DCE"}, "i": {"I", "DCE"},
	"焦煤":  {"JM", "DCE"}, "jm": {"JM", "DCE"},
	"焦炭":  {"J", "DCE"}, "j": {"J", "DCE"},
	"塑料":  {"L", "DCE"}, "聚乙烯": {"L", "DCE"}, "l": {"L", "DCE"},
	"pp":  {"PP", "DCE"}, "聚丙烯": {"PP", "DCE"},
	"pvc": {"V", "DCE"}, "v": {"V", "DCE"},
	"乙二醇": {"EG", "DCE"}, "eg": {"EG", "DCE"},
	"苯乙烯": {"EB", "DCE"}, "eb": {"EB", "DCE"},
	"液化气": {"PG", "DCE"}, "lpg": {"PG", "DCE"}, "pg": {"PG", "DCE"},
	// CZCE 农产品 / 能化
	"棉花":  {"CF", "CZCE"}, "cf": {"CF", "CZCE"},
	"棉纱":  {"CY", "CZCE"}, "cy": {"CY", "CZCE"},
	"白糖":  {"SR", "CZCE"}, "sr": {"SR", "CZCE"},
	"菜油":  {"OI", "CZCE"}, "菜籽油": {"OI", "CZCE"}, "oi": {"OI", "CZCE"},
	"菜粕":  {"RM", "CZCE"}, "rm": {"RM", "CZCE"},
	"苹果":  {"AP", "CZCE"}, "ap": {"AP", "CZCE"},
	"红枣":  {"CJ", "CZCE"}, "cj": {"CJ", "CZCE"},
	"花生":  {"PK", "CZCE"}, "pk": {"PK", "CZCE"},
	"pta": {"TA", "CZCE"}, "ta": {"TA", "CZCE"},
	"甲醇":  {"MA", "CZCE"}, "ma": {"MA", "CZCE"},
	"玻璃":  {"FG", "CZCE"}, "fg": {"FG", "CZCE"},
	"纯碱":  {"SA", "CZCE"}, "sa": {"SA", "CZCE"},
	"动力煤": {"ZC", "CZCE"}, "zc": {"ZC", "CZCE"},
	"尿素":  {"UR", "CZCE"}, "ur": {"UR", "CZCE"},
	"硅铁":  {"SF", "CZCE"}, "sf": {"SF", "CZCE"},
	"锰硅":  {"SM", "CZCE"}, "sm": {"SM", "CZCE"},
	// GFEX 广州 — 工业硅 / 碳酸锂
	"工业硅":  {"SI", "GFEX"}, "si": {"SI", "GFEX"},
	"碳酸锂":  {"LC", "GFEX"}, "lc": {"LC", "GFEX"},
}

// 字母 product → exchange 二级反查（当 alias 命中失败但用户给了纯字母品种）。
var productToExchange = map[string]string{
	"IF": "CFFEX", "IC": "CFFEX", "IH": "CFFEX", "IM": "CFFEX",
	"T": "CFFEX", "TF": "CFFEX", "TS": "CFFEX", "TL": "CFFEX",
	"RB": "SHFE", "HC": "SHFE", "WR": "SHFE", "CU": "SHFE", "AL": "SHFE",
	"ZN": "SHFE", "PB": "SHFE", "NI": "SHFE", "SN": "SHFE",
	"AU": "SHFE", "AG": "SHFE", "BU": "SHFE", "FU": "SHFE", "RU": "SHFE",
	"SC": "INE", "LU": "INE", "NR": "INE",
	"M": "DCE", "Y": "DCE", "A": "DCE", "B": "DCE", "P": "DCE",
	"C": "DCE", "CS": "DCE", "JD": "DCE", "I": "DCE", "JM": "DCE", "J": "DCE",
	"L": "DCE", "PP": "DCE", "V": "DCE", "EG": "DCE", "EB": "DCE", "PG": "DCE",
	"CF": "CZCE", "CY": "CZCE", "SR": "CZCE", "OI": "CZCE", "RM": "CZCE",
	"AP": "CZCE", "CJ": "CZCE", "PK": "CZCE", "TA": "CZCE", "MA": "CZCE",
	"FG": "CZCE", "SA": "CZCE", "ZC": "CZCE", "UR": "CZCE", "SF": "CZCE", "SM": "CZCE",
	"SI": "GFEX", "LC": "GFEX",
}

// ETF 期权关键字 → ETF ts_code。
var optionUnderlyingAlias = map[string]string{
	"50ETF期权": "510050.SH", "50etf": "510050.SH", "上证50期权": "510050.SH",
	"沪深300ETF期权": "510300.SH", "300etf期权": "510300.SH", "300etf": "510300.SH",
	"沪深300期权(深)": "159919.SZ", "深300etf": "159919.SZ",
	"中证500etf期权": "510500.SH", "500etf期权": "510500.SH",
	"创业板etf期权": "159915.SZ", "创业板期权": "159915.SZ",
	"科创50etf期权": "588000.SH", "科创50期权": "588000.SH",
}

var etfOptionUnderlyings = map[string]struct{}{
	"510050.SH": {}, "510300.SH": {}, "159919.SZ": {},
	"510500.SH": {}, "159915.SZ": {}, "588000.SH": {},
}

// shanghaiLoc 与 chat.service 共享语义：所有内部时间均以中国上海为准。
func shanghaiLoc() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}
