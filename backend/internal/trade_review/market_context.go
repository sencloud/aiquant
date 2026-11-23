package trade_review

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/calendar"
	"github.com/sencloud/finme-backend/internal/ai/cnnews"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

const (
	maxContextInstruments = 8
	newsLookbackDays      = 3
	newsLookaheadDays     = 1
)

var shanghaiTime = time.FixedZone("CST", 8*60*60)

// QuoteSource 提供标的日线。接口化后，复盘分析和背景补充可以分别测试。
type QuoteSource interface {
	HistoryFor(
		ctx context.Context,
		symbol string,
		start, end time.Time,
	) ([]tushare.Candle, error)
}

// CalendarSource 提供成交日附近的经济数据发布日历。
type CalendarSource interface {
	FetchEconomicCalendar(
		ctx context.Context,
		startDate, endDate string,
	) ([]calendar.Event, error)
}

// NewsSource 是国内与国际财经新闻的聚合接口。
type NewsSource interface {
	SearchAllResult(ctx context.Context, opt cnnews.SearchOptions) *cnnews.Result
	SearchGlobalResult(
		ctx context.Context,
		opt cnnews.GlobalSearchOptions,
	) *cnnews.Result
}

// MarketContextEnricher 把成交行为放回下单日附近的价格、宏观、海外和热点环境。
// 它只描述可核验事实和时间相邻关系，不从相关性推断交易动机。
type MarketContextEnricher struct {
	quotes   QuoteSource
	calendar CalendarSource
	news     NewsSource
}

func NewMarketContextEnricher(
	quotes QuoteSource,
	calendarSource CalendarSource,
	news NewsSource,
) *MarketContextEnricher {
	return &MarketContextEnricher{
		quotes:   quotes,
		calendar: calendarSource,
		news:     news,
	}
}

type contextInstrument struct {
	key      string
	symbol   string
	name     string
	notional float64
	count    int
}

type quoteQueryResult struct {
	key     string
	candles []tushare.Candle
	err     error
}

type contextSourceResult struct {
	name     string
	quotes   map[string][]tushare.Candle
	quoteErr map[string]error
	calendar []calendar.Event
	err      error
	news     *cnnews.Result
}

func (e *MarketContextEnricher) Enrich(
	ctx context.Context,
	report Report,
) (MarketContext, []Perspective, []string) {
	marketContext := MarketContext{
		Events:   []ContextEvent{},
		Coverage: []ContextCoverage{},
		Gaps:     []string{},
	}
	if len(report.Trades) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "没有可核验的成交日期，无法补充市场背景。")
		return marketContext, []Perspective{}, []string{}
	}

	tradeDates := uniqueTradeDates(report.Trades)
	instruments, missingSymbolCount := contextInstruments(report.Trades)
	earliest := report.Trades[0].occurredAt
	latest := report.Trades[0].occurredAt
	for _, trade := range report.Trades[1:] {
		if trade.occurredAt.Before(earliest) {
			earliest = trade.occurredAt
		}
		if trade.occurredAt.After(latest) {
			latest = trade.occurredAt
		}
	}
	if earliest.IsZero() || latest.IsZero() {
		marketContext.Gaps = append(marketContext.Gaps, "成交时间无法解析，无法补充市场背景。")
		return marketContext, []Perspective{}, []string{}
	}

	quoteStart := startOfDay(earliest.AddDate(0, 0, -7))
	quoteEnd := endOfDay(latest.AddDate(0, 0, 2))
	newsStart := startOfDay(earliest.AddDate(0, 0, -newsLookbackDays))
	newsEnd := endOfDay(latest.AddDate(0, 0, newsLookaheadDays))
	now := time.Now().In(shanghaiTime)
	if quoteEnd.After(now) {
		quoteEnd = now
	}
	if newsEnd.After(now) {
		newsEnd = now
	}

	taskCount := 0
	results := make(chan contextSourceResult, 4)
	if e.quotes != nil && len(instruments) > 0 {
		taskCount++
		go func() {
			quotes, quoteErrors := e.fetchQuotes(
				ctx,
				instruments,
				quoteStart,
				quoteEnd,
			)
			results <- contextSourceResult{
				name:     "quotes",
				quotes:   quotes,
				quoteErr: quoteErrors,
			}
		}()
	}
	if e.calendar != nil {
		taskCount++
		go func() {
			events, err := e.calendar.FetchEconomicCalendar(
				ctx,
				newsStart.Format("2006-01-02"),
				newsEnd.Format("2006-01-02"),
			)
			results <- contextSourceResult{
				name:     "calendar",
				calendar: events,
				err:      err,
			}
		}()
	}
	if e.news != nil {
		taskCount++
		go func() {
			result := e.news.SearchAllResult(ctx, cnnews.SearchOptions{
				Keyword: domesticNewsKeyword(report),
				Limit:   50,
			})
			results <- contextSourceResult{name: "domestic_news", news: result}
		}()
		taskCount++
		go func() {
			result := e.news.SearchGlobalResult(ctx, cnnews.GlobalSearchOptions{
				Keyword:         globalNewsKeyword(report),
				Limit:           50,
				IncludeArticles: true,
			})
			results <- contextSourceResult{name: "global_news", news: result}
		}()
	}

	collected := map[string]contextSourceResult{}
	for index := 0; index < taskCount; index++ {
		select {
		case <-ctx.Done():
			marketContext.Gaps = append(
				marketContext.Gaps,
				"市场背景查询超时，已保留可复算的成交指标。",
			)
			index = taskCount
		case result := <-results:
			collected[result.name] = result
		}
	}

	quotes := collected["quotes"].quotes
	quoteErrors := collected["quotes"].quoteErr
	priceEvents := buildPriceEvents(report, instruments, quotes)
	marketContext.Events = append(marketContext.Events, priceEvents...)

	calendarEvents := buildCalendarEvents(
		collected["calendar"].calendar,
		tradeDates,
	)
	marketContext.Events = append(marketContext.Events, calendarEvents...)

	domesticNews := buildNewsEvents(
		collected["domestic_news"].news,
		"domestic",
		tradeDates,
		12,
	)
	globalNews := buildNewsEvents(
		collected["global_news"].news,
		"global",
		tradeDates,
		10,
	)
	marketContext.Events = append(marketContext.Events, domesticNews...)
	marketContext.Events = append(marketContext.Events, globalNews...)
	marketContext.Events = uniqueContextEvents(marketContext.Events)
	sortContextEvents(marketContext.Events)

	marketContext.Coverage = append(
		marketContext.Coverage,
		quoteCoverage(instruments, quotes, quoteErrors, len(priceEvents)),
		calendarCoverage(collected["calendar"], len(calendarEvents)),
		newsCoverage("国内新闻", collected["domestic_news"].news, len(domesticNews)),
		newsCoverage("国际与跨市场新闻", collected["global_news"].news, len(globalNews)),
	)

	if missingSymbolCount > 0 {
		marketContext.Gaps = append(marketContext.Gaps, fmt.Sprintf(
			"有 %d 个标的缺少证券代码，无法查询对应日线。",
			missingSymbolCount,
		))
	}
	if len(instruments) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "截图中没有可查询的证券代码，价格维度只能保持缺失。")
	}
	if len(priceEvents) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "没有取得可用的成交日行情，无法判断成交价在当日区间中的位置。")
	}
	if len(calendarEvents) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "成交日附近没有取得可核验的重要经济日历事件。")
	}
	if len(domesticNews) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "国内新闻源未返回发布时间落在成交窗口内的记录。")
	}
	if len(globalNews) == 0 {
		marketContext.Gaps = append(marketContext.Gaps, "国际新闻源未返回发布时间落在成交窗口内的记录。")
	}
	marketContext.Gaps = append(
		marketContext.Gaps,
		"日线行情无法还原下单时的分钟走势、盘口和消息先后顺序。",
		"新闻只按发布时间与下单日相邻筛选，不能证明你当时看到过，也不能单独证明交易动机。",
	)
	marketContext.Gaps = unique(marketContext.Gaps)

	perspectives := []Perspective{
		buildPricePerspective(report, instruments, quotes),
		buildDomesticPerspective(calendarEvents, domesticNews),
		buildInternationalPerspective(calendarEvents, globalNews),
		buildHotspotPerspective(report, calendarEvents, domesticNews, globalNews),
	}
	return marketContext, perspectives, []string{}
}

func (e *MarketContextEnricher) fetchQuotes(
	ctx context.Context,
	instruments []contextInstrument,
	start, end time.Time,
) (map[string][]tushare.Candle, map[string]error) {
	queries := make([]contextInstrument, 0, len(instruments)+1)
	queries = append(queries, instruments...)

	hasBenchmark := false
	for _, item := range instruments {
		if tushare.NormalizeSymbol(item.symbol) == "000300.SH" ||
			strings.Contains(item.name, "沪深300") {
			hasBenchmark = true
			break
		}
	}
	if !hasBenchmark {
		queries = append(queries, contextInstrument{
			key:    "000300.SH",
			symbol: "000300.SH",
			name:   "沪深300",
		})
	}

	ch := make(chan quoteQueryResult, len(queries))
	var wg sync.WaitGroup
	for _, query := range queries {
		query := query
		wg.Add(1)
		go func() {
			defer wg.Done()
			candles, err := e.quotes.HistoryFor(ctx, query.symbol, start, end)
			ch <- quoteQueryResult{
				key:     query.key,
				candles: candles,
				err:     err,
			}
		}()
	}
	go func() {
		wg.Wait()
		close(ch)
	}()

	quotes := map[string][]tushare.Candle{}
	errorsByKey := map[string]error{}
	for result := range ch {
		if result.err != nil {
			errorsByKey[result.key] = result.err
			continue
		}
		quotes[result.key] = result.candles
	}
	return quotes, errorsByKey
}

func contextInstruments(trades []Trade) ([]contextInstrument, int) {
	byKey := map[string]*contextInstrument{}
	missingSymbol := map[string]struct{}{}
	for _, trade := range trades {
		key := instrumentKey(trade)
		if key == "" {
			continue
		}
		if strings.TrimSpace(trade.Symbol) == "" {
			missingSymbol[key] = struct{}{}
			continue
		}
		item := byKey[key]
		if item == nil {
			item = &contextInstrument{
				key:    key,
				symbol: strings.TrimSpace(trade.Symbol),
				name:   strings.TrimSpace(trade.Name),
			}
			byKey[key] = item
		}
		if item.name == "" && strings.TrimSpace(trade.Name) != "" {
			item.name = strings.TrimSpace(trade.Name)
		}
		item.count++
		item.notional += trade.Quantity * trade.Price
	}

	out := make([]contextInstrument, 0, len(byKey))
	for _, item := range byKey {
		out = append(out, *item)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if math.Abs(out[i].notional-out[j].notional) > 1e-9 {
			return out[i].notional > out[j].notional
		}
		if out[i].count != out[j].count {
			return out[i].count > out[j].count
		}
		return out[i].key < out[j].key
	})
	if len(out) > maxContextInstruments {
		out = out[:maxContextInstruments]
	}
	return out, len(missingSymbol)
}

func uniqueTradeDates(trades []Trade) []time.Time {
	byDate := map[string]time.Time{}
	for _, trade := range trades {
		if trade.occurredAt.IsZero() {
			continue
		}
		key := dateKey(trade.occurredAt)
		byDate[key] = startOfDay(trade.occurredAt)
	}
	out := make([]time.Time, 0, len(byDate))
	for _, value := range byDate {
		out = append(out, value)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Before(out[j]) })
	return out
}

func buildPriceEvents(
	report Report,
	instruments []contextInstrument,
	quotes map[string][]tushare.Candle,
) []ContextEvent {
	byInstrumentDate := map[string]map[string][]Trade{}
	for _, trade := range report.Trades {
		key := instrumentKey(trade)
		day := dateKey(trade.occurredAt)
		if byInstrumentDate[key] == nil {
			byInstrumentDate[key] = map[string][]Trade{}
		}
		byInstrumentDate[key][day] = append(byInstrumentDate[key][day], trade)
	}

	out := []ContextEvent{}
	appendSeries := func(label string, candles []tushare.Candle, tradesByDate map[string][]Trade) {
		if len(candles) == 0 {
			return
		}
		byDate := map[string]tushare.Candle{}
		for _, candle := range candles {
			byDate[candle.TradeDate] = candle
		}
		days := make([]string, 0, len(tradesByDate))
		for day := range tradesByDate {
			days = append(days, day)
		}
		sort.Strings(days)
		for _, day := range days {
			candle, ok := byDate[strings.ReplaceAll(day, "-", "")]
			if !ok || candle.High <= 0 || candle.Low <= 0 {
				continue
			}
			trades := tradesByDate[day]
			title := fmt.Sprintf("%s：当日 %+.2f%%", label, candle.PctChg)
			summary := candleSummary(candle, trades)
			if len(out) >= 18 {
				return
			}
			importance := 2
			if math.Abs(candle.PctChg) >= 2 {
				importance = 3
			}
			out = append(out, ContextEvent{
				Date:              day,
				Time:              "15:00",
				Scope:             "market",
				Category:          "price",
				Title:             title,
				Summary:           summary,
				Source:            "Tushare 日线",
				Importance:        importance,
				Timing:            "当日",
				RelatedTradeDates: []string{day},
			})
		}
	}

	for _, instrument := range instruments {
		label := instrument.name
		if label == "" {
			label = instrument.symbol
		}
		appendSeries(
			label,
			quotes[instrument.key],
			byInstrumentDate[instrument.key],
		)
	}
	benchmarkTrades := map[string][]Trade{}
	for _, day := range uniqueTradeDates(report.Trades) {
		key := day.Format("2006-01-02")
		benchmarkTrades[key] = []Trade{{TradeDate: key, occurredAt: day}}
	}
	benchmarkQuotes := quotes["000300.SH"]
	if len(benchmarkQuotes) > 0 &&
		!hasInstrumentNamed(report.Trades, "沪深300") {
		appendSeries("沪深300", benchmarkQuotes, benchmarkTrades)
	}
	return out
}

func hasInstrumentNamed(trades []Trade, fragment string) bool {
	for _, trade := range trades {
		if strings.Contains(trade.Name, fragment) ||
			strings.Contains(trade.Symbol, fragment) {
			return true
		}
	}
	return false
}

func candleSummary(candle tushare.Candle, trades []Trade) string {
	amplitude := 0.0
	if candle.PreClose > 0 {
		amplitude = (candle.High - candle.Low) / candle.PreClose * 100
	}
	parts := []string{
		fmt.Sprintf(
			"开 %s / 高 %s / 低 %s / 收 %s",
			contextPrice(candle.Open),
			contextPrice(candle.High),
			contextPrice(candle.Low),
			contextPrice(candle.Close),
		),
		fmt.Sprintf("振幅 %.2f%%", amplitude),
	}
	if len(trades) > 0 {
		buyBasis, buyCount := weightedBasis(trades, TradeSideBuy, candle.Close)
		sellBasis, sellCount := weightedBasis(trades, TradeSideSell, candle.Close)
		execution := []string{}
		if buyCount > 0 {
			execution = append(execution, fmt.Sprintf("买入均价较收盘 %s", signedBps(buyBasis)))
		}
		if sellCount > 0 {
			execution = append(execution, fmt.Sprintf("卖出均价较收盘 %s", signedBps(sellBasis)))
		}
		if len(execution) > 0 {
			parts = append(parts,
				fmt.Sprintf("%d 笔成交：%s", len(trades), strings.Join(execution, "，")))
		}
	}
	return strings.Join(parts, "；")
}

const (
	TradeSideBuy  = "buy"
	TradeSideSell = "sell"
)

func weightedBasis(trades []Trade, side string, closePrice float64) (float64, int) {
	if closePrice <= 0 {
		return 0, 0
	}
	var weighted, quantity float64
	count := 0
	for _, trade := range trades {
		if trade.Side != side || trade.Quantity <= 0 {
			continue
		}
		weighted += (trade.Price - closePrice) / closePrice * 10000 * trade.Quantity
		quantity += trade.Quantity
		count++
	}
	if quantity <= 0 {
		return 0, count
	}
	return weighted / quantity, count
}

func contextPrice(value float64) string {
	if value <= 0 {
		return "-"
	}
	if math.Abs(value) < 10 {
		return strconv.FormatFloat(value, 'f', 3, 64)
	}
	return strconv.FormatFloat(value, 'f', 2, 64)
}

func signedBps(value float64) string {
	return fmt.Sprintf("%+.0fbp", value)
}

func buildCalendarEvents(
	events []calendar.Event,
	tradeDates []time.Time,
) []ContextEvent {
	type rankedEvent struct {
		event  calendar.Event
		date   time.Time
		recent int
	}
	ranked := make([]rankedEvent, 0, len(events))
	for _, event := range events {
		if event.Star < 2 && !isDomesticRegion(event.Region) {
			continue
		}
		date, err := time.ParseInLocation("2006-01-02", event.Date, shanghaiTime)
		if err != nil {
			continue
		}
		if !withinTradingContext(date, tradeDates, 2, 1) {
			continue
		}
		ranked = append(ranked, rankedEvent{
			event:  event,
			date:   date,
			recent: nearestTradeDistance(date, tradeDates),
		})
	}
	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].recent != ranked[j].recent {
			return ranked[i].recent < ranked[j].recent
		}
		if ranked[i].event.Star != ranked[j].event.Star {
			return ranked[i].event.Star > ranked[j].event.Star
		}
		return ranked[i].date.Before(ranked[j].date)
	})
	if len(ranked) > 16 {
		ranked = ranked[:16]
	}

	out := make([]ContextEvent, 0, len(ranked))
	for _, item := range ranked {
		scope := "global"
		if isDomesticRegion(item.event.Region) {
			scope = "domestic"
		}
		summary := []string{}
		if item.event.Period != "" {
			summary = append(summary, "统计期 "+item.event.Period)
		}
		if item.event.Previous != "" {
			summary = append(summary, "前值 "+item.event.Previous)
		}
		if item.event.Forecast != "" {
			summary = append(summary, "预期 "+item.event.Forecast)
		}
		if item.event.Actual != "" {
			summary = append(summary, "公布 "+item.event.Actual)
		}
		out = append(out, ContextEvent{
			Date:              item.event.Date,
			Time:              item.event.Time,
			Scope:             scope,
			Category:          "calendar",
			Title:             strings.TrimSpace(item.event.Region + " · " + item.event.Title),
			Summary:           strings.Join(summary, "；"),
			Source:            "百度财经日历",
			Importance:        item.event.Star,
			Timing:            timingForTradeDates(item.event.Date, tradeDates),
			RelatedTradeDates: relatedTradeDates(item.event.Date, tradeDates, 2, 1),
		})
	}
	return out
}

func buildNewsEvents(
	result *cnnews.Result,
	scope string,
	tradeDates []time.Time,
	limit int,
) []ContextEvent {
	if result == nil {
		return []ContextEvent{}
	}
	type rankedNews struct {
		event    cnnews.Event
		at       time.Time
		recent   int
		topic    string
		orderKey int
	}
	ranked := []rankedNews{}
	for index, event := range result.Events {
		if event.PublishedAt <= 0 || strings.TrimSpace(event.Title) == "" {
			continue
		}
		at := time.UnixMilli(event.PublishedAt).In(shanghaiTime)
		if !withinTradingContext(dateOnlyTime(at), tradeDates, newsLookbackDays, newsLookaheadDays) {
			continue
		}
		ranked = append(ranked, rankedNews{
			event:    event,
			at:       at,
			recent:   nearestTradeDistance(dateOnlyTime(at), tradeDates),
			topic:    classifyNewsTopic(event.Title + " " + event.Snippet),
			orderKey: index,
		})
	}
	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].recent != ranked[j].recent {
			return ranked[i].recent < ranked[j].recent
		}
		if ranked[i].event.Score != ranked[j].event.Score {
			return ranked[i].event.Score > ranked[j].event.Score
		}
		return ranked[i].at.After(ranked[j].at)
	})
	if len(ranked) > limit {
		ranked = ranked[:limit]
	}
	out := make([]ContextEvent, 0, len(ranked))
	for _, item := range ranked {
		date := item.at.Format("2006-01-02")
		out = append(out, ContextEvent{
			Date:              date,
			Time:              item.at.Format("15:04"),
			Scope:             scope,
			Category:          item.topic,
			Title:             shortText(item.event.Title, 90),
			Summary:           shortText(item.event.Snippet, 180),
			Source:            shortText(item.event.Source, 40),
			URL:               item.event.URL,
			Importance:        2,
			Timing:            timingForTradeDates(date, tradeDates),
			RelatedTradeDates: relatedTradeDates(date, tradeDates, newsLookbackDays, newsLookaheadDays),
		})
	}
	return out
}

func quoteCoverage(
	instruments []contextInstrument,
	quotes map[string][]tushare.Candle,
	errorsByKey map[string]error,
	eventCount int,
) ContextCoverage {
	status := "ok"
	success := 0
	for _, instrument := range instruments {
		if len(quotes[instrument.key]) > 0 {
			success++
		}
	}
	if success == 0 {
		status = "error"
	} else if success < len(instruments) || len(errorsByKey) > 0 {
		status = "partial"
	}
	detail := fmt.Sprintf(
		"%d/%d 个标的取得日线；已生成 %d 条成交日价格背景",
		success,
		len(instruments),
		eventCount,
	)
	if len(errorsByKey) > 0 {
		detail += fmt.Sprintf("；%d 个行情请求失败", len(errorsByKey))
	}
	return ContextCoverage{
		Source: "标的与大盘行情",
		Status: status,
		Count:  eventCount,
		Detail: detail,
	}
}

func calendarCoverage(
	result contextSourceResult,
	count int,
) ContextCoverage {
	status := "ok"
	detail := fmt.Sprintf("已筛选 %d 条成交日附近的重要事件", count)
	if result.err != nil {
		status = "error"
		detail = "财经日历请求失败，成交分析不受影响"
	} else if count == 0 {
		status = "empty"
		detail = "日历请求成功，但成交窗口内没有重要事件"
	}
	return ContextCoverage{
		Source: "经济数据日历",
		Status: status,
		Count:  count,
		Detail: detail,
	}
}

func newsCoverage(
	label string,
	result *cnnews.Result,
	count int,
) ContextCoverage {
	if result == nil {
		return ContextCoverage{
			Source: label,
			Status: "error",
			Count:  0,
			Detail: "新闻源不可用",
		}
	}
	okSources := len(result.OKSources())
	failedSources := len(result.FailedSources())
	status := "ok"
	if okSources == 0 {
		status = "error"
	} else if failedSources > 0 {
		status = "partial"
	} else if count == 0 {
		status = "empty"
	}
	detail := fmt.Sprintf(
		"%d 条原始候选，%d 条发布时间落在成交窗口内；%d 个源成功",
		len(result.Events),
		count,
		okSources,
	)
	if failedSources > 0 {
		detail += fmt.Sprintf("，%d 个源失败", failedSources)
	}
	return ContextCoverage{
		Source: label,
		Status: status,
		Count:  count,
		Detail: detail,
	}
}

func buildPricePerspective(
	report Report,
	instruments []contextInstrument,
	quotes map[string][]tushare.Candle,
) Perspective {
	if len(instruments) == 0 {
		return missingPerspective(
			"price",
			"价格位置：缺少可查询的证券代码",
			"截图没有提供足够证券代码，无法把成交价放回当天的开高低收区间。",
		)
	}
	primary := instruments[0]
	candles := quotes[primary.key]
	if len(candles) == 0 {
		return missingPerspective(
			"price",
			"价格位置：行情数据暂缺",
			"没有取得主标的日线，暂时无法判断成交价相对当日收盘和波动区间的位置。",
		)
	}
	byDate := map[string]tushare.Candle{}
	for _, candle := range candles {
		byDate[candle.TradeDate] = candle
	}

	var buyWeighted, sellWeighted, rangeWeighted float64
	var buyQty, sellQty, rangeQty float64
	var strongest time.Time
	var strongestMove float64
	var rangeCount int
	for _, trade := range report.Trades {
		key := instrumentKey(trade)
		if primary.key != key {
			continue
		}
		candle, ok := byDate[strings.ReplaceAll(dateKey(trade.occurredAt), "-", "")]
		if !ok || candle.Close <= 0 || candle.High <= 0 || candle.Low <= 0 {
			continue
		}
		if math.Abs(candle.PctChg) > math.Abs(strongestMove) {
			strongestMove = candle.PctChg
			strongest = trade.occurredAt
		}
		if trade.Quantity <= 0 {
			continue
		}
		basis := (trade.Price - candle.Close) / candle.Close * 10000
		position := 0.5
		if candle.High > candle.Low {
			position = (trade.Price - candle.Low) / (candle.High - candle.Low)
			position = math.Max(0, math.Min(1, position))
		}
		if trade.Side == "buy" {
			buyWeighted += basis * trade.Quantity
			buyQty += trade.Quantity
		} else {
			sellWeighted += basis * trade.Quantity
			sellQty += trade.Quantity
		}
		rangeWeighted += position * trade.Quantity
		rangeQty += trade.Quantity
		rangeCount++
	}
	if rangeCount == 0 {
		return missingPerspective(
			"price",
			"价格位置：成交日与日线没有对齐",
			"行情已经返回，但成交日期没有匹配到对应交易日，暂时不能判断成交价在日内区间的位置。",
		)
	}
	execution := []string{}
	if buyQty > 0 {
		execution = append(execution, "买入均价较收盘 "+signedBps(buyWeighted/buyQty))
	}
	if sellQty > 0 {
		execution = append(execution, "卖出均价较收盘 "+signedBps(sellWeighted/sellQty))
	}
	position := rangeWeighted / rangeQty
	rangeLabel := "日内区间中部"
	if position <= 0.25 {
		rangeLabel = "更靠近当日低点"
	} else if position >= 0.75 {
		rangeLabel = "更靠近当日高点"
	}
	title := "价格位置：成交总体落在" + rangeLabel
	if len(execution) > 0 && buyQty > 0 {
		if buyWeighted/buyQty < -20 {
			title = "价格位置：买入价多数低于当日收盘"
		} else if buyWeighted/buyQty > 20 {
			title = "价格位置：买入价多数高于当日收盘"
		}
	}
	evidence := []string{
		fmt.Sprintf(
			"%s按成交数量加权，平均位于当日高低区间的 %.0f%% 位置",
			instrumentLabel(primaryTrade(primary)),
			position*100,
		),
		strings.Join(execution, "；"),
	}
	if !strongest.IsZero() {
		evidence = append(evidence, fmt.Sprintf(
			"最大单日波动出现在 %d月%d日，涨跌幅 %+.2f%%",
			strongest.Month(),
			strongest.Day(),
			strongestMove,
		))
	}
	return Perspective{
		Dimension: "price",
		Title:     title,
		Body: "把成交价放回当天的开高低收区间后，可以判断执行价相对收盘和日内波动的位置。" +
			"这里只能说明成交落在哪里，无法仅凭成交记录还原你当时追涨、抄底或止盈的主观理由。",
		Basis:      "事实 + 日线推断",
		Evidence:   evidence,
		Confidence: "中",
	}
}

func buildDomesticPerspective(
	calendarEvents, newsEvents []ContextEvent,
) Perspective {
	events := filterContextEvents(
		append(append([]ContextEvent{}, calendarEvents...), newsEvents...),
		"domestic",
	)
	if len(events) == 0 {
		return missingPerspective(
			"domestic",
			"国内环境：成交窗口内没有可核验记录",
			"国内经济日历与新闻源都没有返回符合发布时间窗口的事件。这是数据缺口，不代表当天没有政策或宏观变化。",
		)
	}
	topics := contextTopics(events)
	evidence := contextEvidence(events, 3)
	return Perspective{
		Dimension: "domestic",
		Title:     "国内环境：" + summarizeTopics(topics, "政策与宏观"),
		Body: fmt.Sprintf(
			"在下单日前后可核验的记录中，国内维度找到 %d 条政策、利率、宏观数据或行业事件，主要集中在%s。"+
				"这些事件与下单日在时间上相邻，但不能证明你当时看到过或据此下单。",
			len(events),
			summarizeTopics(topics, "政策与宏观"),
		),
		Basis:      "时间关联",
		Evidence:   evidence,
		Confidence: confidenceForEvidence(len(events)),
	}
}

func buildInternationalPerspective(
	calendarEvents, newsEvents []ContextEvent,
) Perspective {
	events := filterContextEvents(
		append(append([]ContextEvent{}, calendarEvents...), newsEvents...),
		"global",
	)
	if len(events) == 0 {
		return missingPerspective(
			"international",
			"国际环境：成交窗口内没有可核验记录",
			"国际日历与新闻源都没有返回符合发布时间窗口的事件。这是数据缺口，不代表同期没有海外市场、汇率或地缘变化。",
		)
	}
	topics := contextTopics(events)
	return Perspective{
		Dimension: "international",
		Title:     "国际与跨市场：" + summarizeTopics(topics, "海外市场与汇率"),
		Body: fmt.Sprintf(
			"订单日前后可核验的国际记录共有 %d 条，涉及%s。"+
				"对沪深300这类宽基ETF，海外利率、人民币汇率和风险偏好可能通过估值与资金流传导，但截图不能证明具体传导方向或你的交易动机。",
			len(events),
			summarizeTopics(topics, "海外市场与汇率"),
		),
		Basis:      "时间关联",
		Evidence:   contextEvidence(events, 3),
		Confidence: confidenceForEvidence(len(events)),
	}
}

func buildHotspotPerspective(
	report Report,
	calendarEvents, domesticNews, globalNews []ContextEvent,
) Perspective {
	all := append(append([]ContextEvent{}, calendarEvents...), domesticNews...)
	all = append(all, globalNews...)
	if len(all) == 0 {
		return missingPerspective(
			"hotspots",
			"热点话题：暂无可关联的带时间报道",
			"新闻源没有返回能确认发布时间的成交窗口内热点，无法可靠判断当时市场主要在交易什么叙事。",
		)
	}
	topics := contextTopics(all)
	matched := 0
	primaryName := ""
	if len(report.Trades) > 0 {
		primaryName = report.Trades[0].Name
	}
	if primaryName != "" {
		for _, event := range all {
			if strings.Contains(event.Title, primaryName) ||
				strings.Contains(event.Summary, primaryName) {
				matched++
			}
		}
	}
	body := fmt.Sprintf(
		"可核验报道中出现较多的主题是%s。",
		summarizeTopics(topics, "宏观与市场"),
	)
	if primaryName != "" {
		body += fmt.Sprintf("其中标题或摘要直接提到「%s」的有 %d 条。", primaryName, matched)
	}
	body += "热点只能帮助还原当时的叙事环境，不能替代你的入场理由和退出计划。"
	return Perspective{
		Dimension:  "hotspots",
		Title:      "热点话题：" + summarizeTopics(topics, "市场叙事"),
		Body:       body,
		Basis:      "时间关联",
		Evidence:   contextEvidence(all, 4),
		Confidence: confidenceForEvidence(len(all)),
	}
}

func missingPerspective(dimension, title, body string) Perspective {
	return Perspective{
		Dimension:  dimension,
		Title:      title,
		Body:       body,
		Basis:      "数据缺口",
		Evidence:   []string{"该项缺少可核验数据，未用常识或模型记忆补造事实"},
		Confidence: "低",
	}
}

func confidenceForEvidence(count int) string {
	if count >= 6 {
		return "中"
	}
	return "低"
}

func filterContextEvents(events []ContextEvent, scope string) []ContextEvent {
	out := []ContextEvent{}
	for _, event := range events {
		if event.Scope == scope {
			out = append(out, event)
		}
	}
	return out
}

func contextTopics(events []ContextEvent) []string {
	counts := map[string]int{}
	for _, event := range events {
		topic := topicLabel(event.Category)
		if topic == "" {
			continue
		}
		counts[topic]++
	}
	out := make([]string, 0, len(counts))
	for topic := range counts {
		out = append(out, topic)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if counts[out[i]] != counts[out[j]] {
			return counts[out[i]] > counts[out[j]]
		}
		return out[i] < out[j]
	})
	if len(out) > 3 {
		out = out[:3]
	}
	return out
}

func summarizeTopics(topics []string, fallback string) string {
	if len(topics) == 0 {
		return fallback
	}
	if len(topics) == 1 {
		return topics[0]
	}
	return strings.Join(topics[:len(topics)-1], "、") + "与" + topics[len(topics)-1]
}

func contextEvidence(events []ContextEvent, limit int) []string {
	sort.SliceStable(events, func(i, j int) bool {
		if events[i].Date != events[j].Date {
			return events[i].Date < events[j].Date
		}
		return events[i].Time < events[j].Time
	})
	if len(events) > limit {
		events = events[:limit]
	}
	out := make([]string, 0, len(events))
	for _, event := range events {
		timing := event.Timing
		if timing == "" {
			timing = "时间相邻"
		}
		out = append(out, fmt.Sprintf(
			"%s（%s）%s",
			event.Date,
			timing,
			shortText(event.Title, 80),
		))
	}
	return out
}

func topicLabel(category string) string {
	switch category {
	case "calendar":
		return "经济数据与政策"
	case "macro":
		return "政策与宏观"
	case "rates":
		return "利率与汇率"
	case "commodities":
		return "商品与能源"
	case "geopolitics":
		return "地缘与关税"
	case "industry":
		return "行业景气"
	case "market":
		return "A股与资金风险偏好"
	case "overseas":
		return "海外市场"
	default:
		return "市场叙事"
	}
}

func classifyNewsTopic(text string) string {
	value := strings.ToLower(text)
	has := func(words ...string) bool {
		for _, word := range words {
			if strings.Contains(value, strings.ToLower(word)) {
				return true
			}
		}
		return false
	}
	switch {
	case has("地缘", "关税", "制裁", "冲突", "战争", "北约", "中东", "俄乌"):
		return "geopolitics"
	case has("原油", "黄金", "铜价", "白银", "大宗商品", "油价", "OPEC", "天然气"):
		return "commodities"
	case has("美联储", "加息", "降息", "利率", "国债", "美元", "人民币", "汇率"):
		return "rates"
	case has("央行", "财政", "GDP", "CPI", "PPI", "PMI", "国务院", "国常会", "降准", "政策"):
		return "macro"
	case has("半导", "人工智能", "AI", "新能源", "光伏", "锂电", "房地产", "医药", "消费", "汽车"):
		return "industry"
	case has("A股", "沪深300", "上证", "深证", "ETF", "指数", "资金"):
		return "market"
	case has("美股", "纳指", "标普", "欧洲", "日本", "海外"):
		return "overseas"
	default:
		return "market"
	}
}

func domesticNewsKeyword(report Report) string {
	parts := []string{"A股", "沪深300", "ETF", "央行", "利率", "财政", "CPI", "PMI"}
	if len(report.Trades) > 0 {
		if name := strings.TrimSpace(report.Trades[0].Name); name != "" {
			parts = append([]string{name}, parts...)
		}
	}
	return strings.Join(unique(parts), " ")
}

func globalNewsKeyword(report Report) string {
	parts := []string{
		"美联储", "美国", "美元", "人民币", "汇率", "原油", "黄金",
		"关税", "地缘", "海外市场", "纳指",
	}
	if len(report.Trades) > 0 &&
		strings.Contains(report.Trades[0].Name, "沪深300") {
		parts = append(parts, "中国资产")
	}
	return strings.Join(unique(parts), " ")
}

func uniqueContextEvents(events []ContextEvent) []ContextEvent {
	seen := map[string]struct{}{}
	out := make([]ContextEvent, 0, len(events))
	for _, event := range events {
		key := strings.ToLower(strings.TrimSpace(
			event.Date + "|" + event.Time + "|" + event.Source + "|" + event.Title,
		))
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, event)
	}
	return out
}

func sortContextEvents(events []ContextEvent) {
	sort.SliceStable(events, func(i, j int) bool {
		if events[i].Date != events[j].Date {
			return events[i].Date < events[j].Date
		}
		if events[i].Time != events[j].Time {
			return events[i].Time < events[j].Time
		}
		if events[i].Importance != events[j].Importance {
			return events[i].Importance > events[j].Importance
		}
		return events[i].Title < events[j].Title
	})
}

func withinTradingContext(
	date time.Time,
	tradeDates []time.Time,
	lookback, lookahead int,
) bool {
	day := dateOnlyTime(date)
	for _, tradeDate := range tradeDates {
		diff := int(day.Sub(dateOnlyTime(tradeDate)).Hours() / 24)
		if diff >= -lookback && diff <= lookahead {
			return true
		}
	}
	return false
}

func relatedTradeDates(
	date string,
	tradeDates []time.Time,
	lookback, lookahead int,
) []string {
	parsed, err := time.ParseInLocation("2006-01-02", date, shanghaiTime)
	if err != nil {
		return []string{}
	}
	out := []string{}
	for _, tradeDate := range tradeDates {
		diff := int(dateOnlyTime(parsed).Sub(dateOnlyTime(tradeDate)).Hours() / 24)
		if diff >= -lookback && diff <= lookahead {
			out = append(out, tradeDate.Format("2006-01-02"))
		}
	}
	return out
}

func timingForTradeDates(date string, tradeDates []time.Time) string {
	parsed, err := time.ParseInLocation("2006-01-02", date, shanghaiTime)
	if err != nil {
		return ""
	}
	nearest := nearestTradeDistance(parsed, tradeDates)
	label := ""
	for _, tradeDate := range tradeDates {
		diff := int(dateOnlyTime(parsed).Sub(dateOnlyTime(tradeDate)).Hours() / 24)
		if absInt(diff) != nearest {
			continue
		}
		switch {
		case diff == 0:
			label = "当日"
		case diff < 0:
			label = fmt.Sprintf("前%d天", -diff)
		default:
			label = fmt.Sprintf("后%d天", diff)
		}
		break
	}
	return label
}

func nearestTradeDistance(date time.Time, tradeDates []time.Time) int {
	best := math.MaxInt
	for _, tradeDate := range tradeDates {
		diff := absInt(int(dateOnlyTime(date).Sub(dateOnlyTime(tradeDate)).Hours() / 24))
		if diff < best {
			best = diff
		}
	}
	if best == math.MaxInt {
		return 0
	}
	return best
}

func isDomesticRegion(region string) bool {
	value := strings.TrimSpace(region)
	return strings.Contains(value, "中国") ||
		strings.Contains(value, "香港") ||
		strings.Contains(value, "内地")
}

func primaryTrade(instrument contextInstrument) Trade {
	return Trade{Name: instrument.name, Symbol: instrument.symbol}
}

func shortText(value string, limit int) string {
	value = strings.Join(strings.Fields(value), " ")
	runes := []rune(value)
	if len(runes) <= limit {
		return value
	}
	return string(runes[:limit]) + "…"
}

func startOfDay(value time.Time) time.Time {
	return time.Date(
		value.Year(),
		value.Month(),
		value.Day(),
		0,
		0,
		0,
		0,
		value.Location(),
	)
}

func endOfDay(value time.Time) time.Time {
	return startOfDay(value).Add(24*time.Hour - time.Nanosecond)
}

func dateOnlyTime(value time.Time) time.Time {
	return time.Date(
		value.Year(),
		value.Month(),
		value.Day(),
		0,
		0,
		0,
		0,
		shanghaiTime,
	)
}

func absInt(value int) int {
	if value < 0 {
		return -value
	}
	return value
}
