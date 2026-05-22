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

// get_dominant_contract —— 给 LLM 用的"任意期货 / 期权 → 当前主力合约"工具。
//
// LLM 在被问"螺纹钢现在多少 / IF 主力 / 50ETF 期权近月 / 豆粕期权 / 沪深300股指期权"
// 这类话题时，**禁止自行编合约月份**（模型训练时的"主力"早就过期了），必须先
// 调用这个工具拿到真实合约 ts_code，再喂回 get_quote / get_option_quote。
//
// 支持的资产：
//   - 期货      （CFFEX / SHFE / DCE / CZCE / INE / GFEX 全品种）
//   - ETF 期权  （SSE / SZSE 共 6 只）
//   - 商品期权  （SHFE / DCE / CZCE / INE / GFEX 全市场）
//   - 股指期权  （CFFEX：IO / HO / MO）

func registerDominant(r *tool.Registry, c *tushare.Client) {
	r.MustRegister(&getDominantContractTool{c: c})
}

type getDominantContractTool struct{ c *tushare.Client }

func (t *getDominantContractTool) Spec() tool.Spec {
	return tool.Spec{
		Name: "get_dominant_contract",
		Description: "把『螺纹钢 / 焦煤 / 沪深300股指 / 原油 / 50ETF期权 / 沪深300期权 / 豆粕期权 / 铜期权 / 沪深300股指期权 / 中证1000股指期权』等品种名（或品种字母如 RB / IF / IO）解析为真实的当前主力合约 ts_code，附带最新成交量、持仓量、收盘价。覆盖期货、ETF 期权、商品期权、股指期权。模型不知道现在是几月，禁止凭印象猜测合约月份；一律先调本工具拿真实合约，再调用 get_quote / get_option_quote。",
		Parameters: tool.ParameterSchema{
			Properties: map[string]tool.ParameterProperty{
				"product": {Type: "string", Description: "品种关键字：① 期货：螺纹钢/焦煤/铁矿石/原油/沪深300股指/IF/RB/CU/M/SC ② ETF 期权：50ETF期权/沪深300期权/510050/159919 ③ 商品期权：豆粕期权/铜期权/白糖期权/PTA期权/铁矿石期权… ④ 股指期权：沪深300股指期权/上证50股指期权/中证1000股指期权/IO/HO/MO"},
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

	// 解析顺序很重要：先匹配更具体的（"豆粕期权"）再到泛的（"豆粕"）。
	// 1) 股指期权（IO/HO/MO）
	if so, ok := resolveStockIndexOption(q); ok {
		return t.runStockIndexOption(ctx, so, q)
	}
	// 2) 商品期权（豆粕期权 / 铜期权 …）
	if co, ok := resolveCommodityOption(q); ok {
		return t.runCommodityOption(ctx, co, q)
	}
	// 3) ETF 期权
	if etf, ok := resolveOptionUnderlying(q); ok {
		return t.runETFOption(ctx, etf, q)
	}
	// 4) 期货
	prodCode, exchange := resolveFuturesProduct(q)
	if prodCode == "" {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("无法识别品种 %q；示例：螺纹钢/焦煤/铁矿石/原油/沪深300股指/IF/RB/CU/50ETF期权/豆粕期权/沪深300股指期权 …", q),
			"product": q,
		}), nil
	}
	return t.runFutures(ctx, prodCode, exchange, q)
}

// ── 期货主力 ────────────────────────────────────────────────────────────

func (t *getDominantContractTool) runFutures(ctx context.Context, prod, exchange, query string) (string, error) {
	main, secondary, all, latest, err := t.pickFuturesDominant(ctx, prod, exchange)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error(), "product": query}), nil
	}
	allList := make([]map[string]any, 0, len(all))
	for _, r := range all {
		allList = append(allList, map[string]any{
			"ts_code":        r.TsCode,
			"delivery_month": tushare.FuturesDeliveryMonth(r.TsCode),
			"close":          round(r.Close, 4),
			"vol":            int(r.Vol),
			"oi":             int(r.OI),
		})
	}
	out := map[string]any{
		"product":     prod,
		"asset_class": "futures",
		"exchange":    exchange,
		"as_of":       formatDate(latest),
		"dominant": map[string]any{
			"ts_code":        main.TsCode,
			"delivery_month": tushare.FuturesDeliveryMonth(main.TsCode),
			"close":          round(main.Close, 4),
			"settle":         round(main.Settle, 4),
			"vol":            int(main.Vol),
			"oi":             int(main.OI),
		},
		"contracts_count": len(all),
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

// pickFuturesDominant 内部复用：拉最近 8 天某交易所行情，过滤出某品种，
// 按成交量降序选主力，按持仓量降序选次主力。
func (t *getDominantContractTool) pickFuturesDominant(
	ctx context.Context, prod, exchange string,
) (main *tushare.FuturesDaily, secondary *tushare.FuturesDaily,
	all []tushare.FuturesDaily, latest string, err error) {
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)
	rows, e := t.c.FuturesDailyBatch(ctx, tushare.FutDailyParams{
		Exchange:  exchange,
		StartDate: ymd(start),
		EndDate:   ymd(now),
	})
	if e != nil {
		err = fmt.Errorf("fut_daily(%s) 失败: %s", exchange, e.Error())
		return
	}
	if len(rows) == 0 {
		err = fmt.Errorf("fut_daily(%s) 近 8 天无数据（token 无权或全节假日）", exchange)
		return
	}
	for _, r := range rows {
		if r.TradeDate > latest {
			latest = r.TradeDate
		}
	}
	for _, r := range rows {
		if r.TradeDate != latest {
			continue
		}
		p, _ := tushare.FuturesProduct(r.TsCode)
		if strings.EqualFold(p, prod) {
			all = append(all, r)
		}
	}
	if len(all) == 0 {
		err = fmt.Errorf("品种 %s 在 %s 最新交易日无合约", prod, formatDate(latest))
		return
	}
	byVol := append([]tushare.FuturesDaily(nil), all...)
	sort.Slice(byVol, func(i, j int) bool { return byVol[i].Vol > byVol[j].Vol })
	dom := byVol[0]
	main = &dom
	for _, r := range byVol[1:] {
		if r.TsCode != main.TsCode && r.OI > 0 {
			s := r
			secondary = &s
			break
		}
	}
	byOI := append([]tushare.FuturesDaily(nil), all...)
	sort.Slice(byOI, func(i, j int) bool { return byOI[i].OI > byOI[j].OI })
	for _, r := range byOI {
		if r.TsCode != main.TsCode {
			s := r
			secondary = &s
			break
		}
	}
	return
}

// ── 期权通用挑选逻辑（按月份 + ATM） ───────────────────────────────────

type enrichedOpt struct {
	Contract tushare.OptionContract
	Daily    tushare.OptionDaily
	DTE      int
}

type monthAgg struct {
	Month string
	Vol   float64
	OI    float64
	Calls []enrichedOpt
	Puts  []enrichedOpt
}

// pickOptionMonthAndATM 输入"某资产范围内"的合约清单 + 当日行情 map +
// spot 现价，输出排序好的月份聚合 + 主力月份内的 ATM call & put。
func pickOptionMonthAndATM(
	contracts []tushare.OptionContract,
	dailyByCode map[string]tushare.OptionDaily,
	spot float64,
	now time.Time,
) (months []*monthAgg, main *monthAgg, atmCall, atmPut *enrichedOpt) {
	monthMap := map[string]*monthAgg{}
	for _, oc := range contracts {
		dte := daysUntil(now, oc.MaturityDate)
		if dte < 0 {
			continue
		}
		q, ok := dailyByCode[oc.TsCode]
		if !ok {
			continue
		}
		m := oc.SMonth
		if m == "" && len(oc.MaturityDate) >= 6 {
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
		return
	}
	months = make([]*monthAgg, 0, len(monthMap))
	for _, m := range monthMap {
		months = append(months, m)
	}
	sort.Slice(months, func(i, j int) bool { return months[i].Vol > months[j].Vol })
	main = months[0]

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
	atmCall = pickATM(main.Calls)
	atmPut = pickATM(main.Puts)
	return
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

// renderOptionResult 把 picker 结果渲染成统一的工具输出。
func renderOptionResult(
	query string,
	assetClass, exchange string,
	extra map[string]any,
	spot float64,
	spotDate, latestDate string,
	months []*monthAgg,
	main *monthAgg,
	atmCall, atmPut *enrichedOpt,
) string {
	if main == nil {
		out := map[string]any{
			"error":       "未匹配到任何在交易的合约（可能 token 缺权限或非交易日）",
			"product":     query,
			"asset_class": assetClass,
			"exchange":    exchange,
		}
		for k, v := range extra {
			out[k] = v
		}
		return tool.EncodeJSON(out)
	}
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
		"product":         query,
		"asset_class":     assetClass,
		"exchange":        exchange,
		"as_of":           formatDate(latestDate),
		"spot":            round(spot, 4),
		"spot_date":       formatDate(spotDate),
		"dominant_month":  main.Month,
		"month_total_vol": int(main.Vol),
		"months_overview": monthOut,
	}
	for k, v := range extra {
		out[k] = v
	}
	if atmCall != nil {
		out["atm_call"] = enrichedToMap(atmCall)
	}
	if atmPut != nil {
		out["atm_put"] = enrichedToMap(atmPut)
	}
	out["notes"] = "dominant_month 按主力月份选取（成交量最大）。atm_call / atm_put 是该月份内行权价最贴近 spot 的合约；如需别的虚值档可调 list_option_contracts 配合月份过滤。"
	return tool.EncodeJSON(out)
}

// ── ETF 期权主力 ───────────────────────────────────────────────────────

func (t *getDominantContractTool) runETFOption(ctx context.Context, underlying, query string) (string, error) {
	exchange := tushare.OptionExchangeOf(underlying)
	if exchange == "" {
		return tool.EncodeJSON(map[string]any{
			"error":   "无法推断期权交易所（仅支持 SSE/SZSE 的 ETF 期权）",
			"product": query,
		}), nil
	}
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)

	hist, err := t.c.HistoryFor(ctx, underlying, start, now)
	if err != nil || len(hist) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("ETF %s 行情拉取失败/为空", underlying),
			"product": query,
		}), nil
	}
	spot := hist[len(hist)-1].Close
	spotDate := hist[len(hist)-1].TradeDate

	dailyByCode, latestDate, err := t.latestOptionDailyByCode(ctx, exchange)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error(), "product": query}), nil
	}
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

	months, main, atmCall, atmPut := pickOptionMonthAndATM(contracts, dailyByCode, spot, now)
	return renderOptionResult(query, "etf_option", exchange,
		map[string]any{"underlying": underlying},
		spot, spotDate, latestDate, months, main, atmCall, atmPut), nil
}

// ── 商品期权主力 ───────────────────────────────────────────────────────

func (t *getDominantContractTool) runCommodityOption(ctx context.Context, co commodityOptionTarget, query string) (string, error) {
	// 1) 用对应期货品种的主力合约 close 作 spot 参照
	main, _, _, _, err := t.pickFuturesDominant(ctx, co.Product, co.Exchange)
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("拉取 %s 主力期货失败: %s", co.Product, err.Error()),
			"product": query,
		}), nil
	}
	spot := main.Close
	if main.Settle > 0 && spot <= 0 {
		spot = main.Settle
	}
	spotDate := main.TradeDate

	// 2) 拉当日全 exchange 期权行情 → 按 ts_code 前缀过滤本品种
	dailyByCode, latestDate, err := t.latestOptionDailyByCode(ctx, co.Exchange)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error(), "product": query}), nil
	}
	filteredDaily := map[string]tushare.OptionDaily{}
	for code, d := range dailyByCode {
		if matchOptionProductPrefix(code, co.Product) {
			filteredDaily[code] = d
		}
	}

	// 3) 拉 opt_basic 全 exchange（缓存）→ 同前缀过滤
	allContracts, err := t.c.OptionBasic(ctx, tushare.OptBasicParams{Exchange: co.Exchange})
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("opt_basic(%s) 失败: %s", co.Exchange, err.Error()),
			"product": query,
		}), nil
	}
	contracts := make([]tushare.OptionContract, 0, 256)
	for _, oc := range allContracts {
		if matchOptionProductPrefix(oc.TsCode, co.Product) {
			contracts = append(contracts, oc)
		}
	}

	months, mainMonth, atmCall, atmPut := pickOptionMonthAndATM(contracts, filteredDaily, spot, time.Now().In(shanghaiLoc()))
	return renderOptionResult(query, "commodity_option", co.Exchange,
		map[string]any{
			"underlying_product": co.Product,
			"spot_source":        "对应期货主力合约 close",
			"underlying_future":  main.TsCode,
		},
		spot, spotDate, latestDate, months, mainMonth, atmCall, atmPut), nil
}

// ── 股指期权主力 ───────────────────────────────────────────────────────

func (t *getDominantContractTool) runStockIndexOption(ctx context.Context, so stockIndexOptionTarget, query string) (string, error) {
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)

	// 1) 现价：指数 close
	idx, err := t.c.IndexDaily(ctx, so.IndexCode, start, now)
	if err != nil || len(idx) == 0 {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("指数 %s 行情拉取失败/为空", so.IndexCode),
			"product": query,
		}), nil
	}
	spot := idx[len(idx)-1].Close
	spotDate := idx[len(idx)-1].TradeDate

	// 2) CFFEX 当日全期权行情
	dailyByCode, latestDate, err := t.latestOptionDailyByCode(ctx, so.Exchange)
	if err != nil {
		return tool.EncodeJSON(map[string]any{"error": err.Error(), "product": query}), nil
	}
	filteredDaily := map[string]tushare.OptionDaily{}
	for code, d := range dailyByCode {
		if matchOptionProductPrefix(code, so.Product) {
			filteredDaily[code] = d
		}
	}

	// 3) CFFEX opt_basic（缓存）+ 前缀过滤
	allContracts, err := t.c.OptionBasic(ctx, tushare.OptBasicParams{Exchange: so.Exchange})
	if err != nil {
		return tool.EncodeJSON(map[string]any{
			"error":   fmt.Sprintf("opt_basic(%s) 失败: %s", so.Exchange, err.Error()),
			"product": query,
		}), nil
	}
	contracts := make([]tushare.OptionContract, 0, 256)
	for _, oc := range allContracts {
		if matchOptionProductPrefix(oc.TsCode, so.Product) {
			contracts = append(contracts, oc)
		}
	}

	months, mainMonth, atmCall, atmPut := pickOptionMonthAndATM(contracts, filteredDaily, spot, now)
	return renderOptionResult(query, "stock_index_option", so.Exchange,
		map[string]any{
			"underlying_product": so.Product,
			"underlying_index":   so.IndexCode,
			"spot_source":        "对应指数 close",
		},
		spot, spotDate, latestDate, months, mainMonth, atmCall, atmPut), nil
}

// ── 期权行情聚合（每个 ts_code 取最新一日） ────────────────────────────

func (t *getDominantContractTool) latestOptionDailyByCode(ctx context.Context, exchange string) (map[string]tushare.OptionDaily, string, error) {
	now := time.Now().In(shanghaiLoc())
	start := now.AddDate(0, 0, -8)
	rows, err := t.c.OptionDailyBatch(ctx, tushare.OptDailyParams{
		Exchange:  exchange,
		StartDate: ymd(start),
		EndDate:   ymd(now),
	})
	if err != nil {
		return nil, "", fmt.Errorf("opt_daily(%s) 失败: %s", exchange, err.Error())
	}
	if len(rows) == 0 {
		return nil, "", fmt.Errorf("opt_daily(%s) 近 8 天无数据（token 无权或全节假日）", exchange)
	}
	out := make(map[string]tushare.OptionDaily, len(rows))
	latest := ""
	for _, r := range rows {
		cur, ok := out[r.TsCode]
		if !ok || r.TradeDate > cur.TradeDate {
			out[r.TsCode] = r
		}
		if r.TradeDate > latest {
			latest = r.TradeDate
		}
	}
	return out, latest, nil
}

// ── 品种映射 ───────────────────────────────────────────────────────────

// commodityOptionTarget 描述一个商品期权品种的解析结果。
type commodityOptionTarget struct {
	Product  string // 品种字母（CU/M/SR/...）
	Exchange string // SHFE/DCE/CZCE/INE/GFEX
}

// stockIndexOptionTarget 描述一个股指期权品种的解析结果。
type stockIndexOptionTarget struct {
	Product   string // IO / HO / MO
	Exchange  string // CFFEX
	IndexCode string // 对应指数 ts_code，用于取 spot
}

// resolveFuturesProduct 把中文 / 缩写关键字解析成 (品种代码, 交易所)。
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
// 等关键字解析成 ETF ts_code（仅 ETF 期权，股指 / 商品另算）。
func resolveOptionUnderlying(q string) (string, bool) {
	key := strings.TrimSpace(q)
	if v, ok := optionUnderlyingAlias[key]; ok {
		return v, true
	}
	if v, ok := optionUnderlyingAlias[strings.ToUpper(key)]; ok {
		return v, true
	}
	if norm := tushare.NormalizeSymbol(key); norm != "" {
		if _, ok := etfOptionUnderlyings[strings.ToUpper(norm)]; ok {
			return strings.ToUpper(norm), true
		}
	}
	return "", false
}

// resolveCommodityOption 解析"豆粕期权 / 铜期权 / m 期权 / cu期权"等。
func resolveCommodityOption(q string) (commodityOptionTarget, bool) {
	key := strings.TrimSpace(q)
	keyUpper := strings.ToUpper(key)
	if hit, ok := commodityOptionAlias[key]; ok {
		return hit, true
	}
	if hit, ok := commodityOptionAlias[keyUpper]; ok {
		return hit, true
	}
	// "豆粕期权" / "铜期权" / "PTA期权" 这种结构：剥掉后缀「期权 / 期權 / option」再
	// 试一次 futures 别名，命中即视作"该品种的期权"。
	for _, suf := range optionSuffixes {
		if strings.HasSuffix(key, suf) {
			base := strings.TrimSuffix(key, suf)
			if base == "" {
				continue
			}
			if prod, ex := resolveFuturesProduct(base); prod != "" && isCommodityExchange(ex) {
				return commodityOptionTarget{Product: prod, Exchange: ex}, true
			}
		}
		if strings.HasSuffix(keyUpper, strings.ToUpper(suf)) {
			base := strings.TrimSuffix(keyUpper, strings.ToUpper(suf))
			if base == "" {
				continue
			}
			if prod, ex := resolveFuturesProduct(base); prod != "" && isCommodityExchange(ex) {
				return commodityOptionTarget{Product: prod, Exchange: ex}, true
			}
		}
	}
	return commodityOptionTarget{}, false
}

// resolveStockIndexOption 解析 IO / HO / MO + 中文别名。
func resolveStockIndexOption(q string) (stockIndexOptionTarget, bool) {
	key := strings.TrimSpace(q)
	keyUpper := strings.ToUpper(key)
	if hit, ok := stockIndexOptionAlias[key]; ok {
		return hit, true
	}
	if hit, ok := stockIndexOptionAlias[keyUpper]; ok {
		return hit, true
	}
	return stockIndexOptionTarget{}, false
}

// matchOptionProductPrefix 判断"期权 ts_code"的品种前缀是否等于 product。
//
// 关键防冲突：M（豆粕）↔ MA（甲醇），CU ↔ CY 不会误匹配，因为前缀后必须紧跟数字。
//
// 期权 ts_code 形态：
//
//	DCE / GFEX / SHFE / INE：  品种字母 + 数字 + (C|P 或 -C-|-P-) + 行权价 + .XXX
//	CZCE：                    品种字母 + 数字 + (C|P) + 行权价 + .CZC
//	CFFEX：                   IO/HO/MO + 数字 + -C-|-P- + 行权价 + .CFE
func matchOptionProductPrefix(tsCode, product string) bool {
	body := tsCode
	if dot := strings.LastIndex(tsCode, "."); dot >= 0 {
		body = tsCode[:dot]
	}
	bodyUpper := strings.ToUpper(body)
	prodUpper := strings.ToUpper(product)
	if !strings.HasPrefix(bodyUpper, prodUpper) {
		return false
	}
	if len(bodyUpper) <= len(prodUpper) {
		return false
	}
	c := bodyUpper[len(prodUpper)]
	// 紧跟必须是数字（防止 M 匹配 MA、CU 匹配 CY 这种品种前缀重合）。
	return c >= '0' && c <= '9'
}

func isCommodityExchange(ex string) bool {
	switch ex {
	case "SHFE", "DCE", "CZCE", "INE", "GFEX":
		return true
	}
	return false
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

var optionSuffixes = []string{"期权", "期權", "Option", "option", "OPTION"}

type productAlias struct{ product, exchange string }

// 主流期货品种白名单（中文 + 英文别名）。覆盖国内活跃期货品种 90%+。
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

// 商品期权关键字 → (品种, 交易所)。
// 注：未在此列出的品种依然能命中——resolveCommodityOption 会剥掉"期权"
// 后缀再 fallback 到 resolveFuturesProduct，所以任何商品期货品种 + "期权"
// 都自动支持。这里只放需要"特殊别名"或者中文带歧义的条目。
var commodityOptionAlias = map[string]commodityOptionTarget{
	"豆粕期权":   {"M", "DCE"},
	"玉米期权":   {"C", "DCE"},
	"铁矿石期权":  {"I", "DCE"},
	"铁矿期权":   {"I", "DCE"},
	"棕榈油期权":  {"P", "DCE"},
	"棕榈期权":   {"P", "DCE"},
	"聚乙烯期权":  {"L", "DCE"},
	"塑料期权":   {"L", "DCE"},
	"PVC期权":  {"V", "DCE"},
	"pvc期权":  {"V", "DCE"},
	"PP期权":   {"PP", "DCE"},
	"pp期权":   {"PP", "DCE"},
	"聚丙烯期权":  {"PP", "DCE"},
	"液化气期权":  {"PG", "DCE"},
	"鸡蛋期权":   {"JD", "DCE"},
	"乙二醇期权":  {"EG", "DCE"},
	"苯乙烯期权":  {"EB", "DCE"},
	"白糖期权":   {"SR", "CZCE"},
	"棉花期权":   {"CF", "CZCE"},
	"PTA期权":  {"TA", "CZCE"},
	"pta期权":  {"TA", "CZCE"},
	"甲醇期权":   {"MA", "CZCE"},
	"菜籽油期权":  {"OI", "CZCE"},
	"菜油期权":   {"OI", "CZCE"},
	"菜粕期权":   {"RM", "CZCE"},
	"玻璃期权":   {"FG", "CZCE"},
	"纯碱期权":   {"SA", "CZCE"},
	"动力煤期权":  {"ZC", "CZCE"},
	"尿素期权":   {"UR", "CZCE"},
	"花生期权":   {"PK", "CZCE"},
	"苹果期权":   {"AP", "CZCE"},
	"红枣期权":   {"CJ", "CZCE"},
	"硅铁期权":   {"SF", "CZCE"},
	"锰硅期权":   {"SM", "CZCE"},
	"铜期权":    {"CU", "SHFE"},
	"铝期权":    {"AL", "SHFE"},
	"锌期权":    {"ZN", "SHFE"},
	"铅期权":    {"PB", "SHFE"},
	"镍期权":    {"NI", "SHFE"},
	"黄金期权":   {"AU", "SHFE"},
	"白银期权":   {"AG", "SHFE"},
	"螺纹钢期权":  {"RB", "SHFE"},
	"螺纹期权":   {"RB", "SHFE"},
	"燃料油期权":  {"FU", "SHFE"},
	"燃油期权":   {"FU", "SHFE"},
	"沥青期权":   {"BU", "SHFE"},
	"橡胶期权":   {"RU", "SHFE"},
	"原油期权":   {"SC", "INE"},
	"工业硅期权":  {"SI", "GFEX"},
	"碳酸锂期权":  {"LC", "GFEX"},
}

// 股指期权关键字。
var stockIndexOptionAlias = map[string]stockIndexOptionTarget{
	"IO":          {"IO", "CFFEX", "000300.SH"},
	"io":          {"IO", "CFFEX", "000300.SH"},
	"沪深300股指期权":  {"IO", "CFFEX", "000300.SH"},
	"300股指期权":    {"IO", "CFFEX", "000300.SH"},
	"沪深300指数期权": {"IO", "CFFEX", "000300.SH"},

	"HO":         {"HO", "CFFEX", "000016.SH"},
	"ho":         {"HO", "CFFEX", "000016.SH"},
	"上证50股指期权": {"HO", "CFFEX", "000016.SH"},
	"50股指期权":    {"HO", "CFFEX", "000016.SH"},
	"上证50指数期权": {"HO", "CFFEX", "000016.SH"},

	"MO":           {"MO", "CFFEX", "000852.SH"},
	"mo":           {"MO", "CFFEX", "000852.SH"},
	"中证1000股指期权": {"MO", "CFFEX", "000852.SH"},
	"1000股指期权":    {"MO", "CFFEX", "000852.SH"},
	"中证1000指数期权": {"MO", "CFFEX", "000852.SH"},
}

// shanghaiLoc 与 chat.service 共享语义：所有内部时间均以中国上海为准。
func shanghaiLoc() *time.Location {
	if loc, err := time.LoadLocation("Asia/Shanghai"); err == nil {
		return loc
	}
	return time.FixedZone("CST", 8*3600)
}
