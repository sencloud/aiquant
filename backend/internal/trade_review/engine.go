package trade_review

import (
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Trade struct {
	SourceIndex int     `json:"source_index"`
	TradeDate   string  `json:"trade_date"`
	TradeTime   string  `json:"trade_time,omitempty"`
	Symbol      string  `json:"symbol"`
	Name        string  `json:"name"`
	Side        string  `json:"side"`
	Quantity    float64 `json:"quantity"`
	Price       float64 `json:"price"`
	Fee         float64 `json:"fee"`

	occurredAt time.Time
}

type AnalyzeInput struct {
	Trades         []Trade  `json:"trades"`
	BrokerHint     string   `json:"broker_hint"`
	Currency       string   `json:"currency"`
	ParserWarnings []string `json:"warnings"`
}

type Metrics struct {
	RealizedPnl             float64 `json:"realized_pnl"`
	GrossProfit             float64 `json:"gross_profit"`
	GrossLoss               float64 `json:"gross_loss"`
	MatchedSellCount        int     `json:"matched_sell_count"`
	WinningSellCount        int     `json:"winning_sell_count"`
	LosingSellCount         int     `json:"losing_sell_count"`
	WinRate                 float64 `json:"win_rate"`
	AverageWin              float64 `json:"average_win"`
	AverageLoss             float64 `json:"average_loss"`
	ProfitLossRatio         float64 `json:"profit_loss_ratio"`
	Expectancy              float64 `json:"expectancy"`
	AverageHoldingHours     float64 `json:"average_holding_hours"`
	AverageWinningHoldHours float64 `json:"average_winning_holding_hours"`
	AverageLosingHoldHours  float64 `json:"average_losing_holding_hours"`
	MaxWinStreak            int     `json:"max_win_streak"`
	MaxLossStreak           int     `json:"max_loss_streak"`
	SameDayRoundTrips       int     `json:"same_day_round_trips"`
	TotalFees               float64 `json:"total_fees"`
	Turnover                float64 `json:"turnover"`
	FeeRatio                float64 `json:"fee_ratio"`
	ConcentrationRatio      float64 `json:"concentration_ratio"`
	MaxSymbolsInDay         int     `json:"max_symbols_in_day"`
	AverageSymbolsPerDay    float64 `json:"average_symbols_per_day"`
	MaxTradesInDay          int     `json:"max_trades_in_day"`
	AverageTradesPerTrading float64 `json:"average_trades_per_trading_day"`
	TradingDayCount         int     `json:"trading_day_count"`
	OpenLotCount            int     `json:"open_lot_count"`
	BestTradePnl            float64 `json:"best_trade_pnl"`
	WorstTradePnl           float64 `json:"worst_trade_pnl"`
}

type Insight struct {
	Kind     string   `json:"kind"`
	Title    string   `json:"title"`
	Body     string   `json:"body"`
	Evidence []string `json:"evidence"`
}

type Report struct {
	ID           string    `json:"id"`
	CreatedAt    time.Time `json:"created_at"`
	Title        string    `json:"title"`
	BrokerHint   string    `json:"broker_hint"`
	Currency     string    `json:"currency"`
	Trades       []Trade   `json:"trades"`
	Metrics      Metrics   `json:"metrics"`
	Logic        []Insight `json:"logic"`
	Problems     []Insight `json:"problems"`
	Improvements []Insight `json:"improvements"`
	Warnings     []string  `json:"warnings"`
}

type lot struct {
	remaining   float64
	costPerUnit float64
	acquiredAt  time.Time
}

type closedTrade struct {
	pnl          float64
	quantity     float64
	holdingHours float64
	sameDay      bool
}

// Analyze 只从截图中可确认的成交行还原行为。所有指标都可由返回的成交行复算。
func Analyze(in AnalyzeInput, now time.Time) Report {
	if now.IsZero() {
		now = time.Now()
	}
	warnings := append([]string{}, in.ParserWarnings...)
	trades := append([]Trade{}, in.Trades...)
	for i := range trades {
		t, err := parseTradeMoment(trades[i])
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("第 %d 行成交时间无法确认，未纳入计算。", i+1))
			continue
		}
		trades[i].occurredAt = t
	}
	sort.SliceStable(trades, func(i, j int) bool {
		if !trades[i].occurredAt.Equal(trades[j].occurredAt) {
			return trades[i].occurredAt.Before(trades[j].occurredAt)
		}
		return trades[i].SourceIndex < trades[j].SourceIndex
	})

	valid := make([]Trade, 0, len(trades))
	for _, trade := range trades {
		if trade.occurredAt.IsZero() {
			continue
		}
		trade.Symbol = strings.TrimSpace(trade.Symbol)
		trade.Name = strings.TrimSpace(trade.Name)
		trade.Side = strings.ToLower(strings.TrimSpace(trade.Side))
		if instrumentKey(trade) == "" {
			warnings = append(warnings, "有一笔成交缺少证券代码和名称，未纳入盈亏计算。")
			continue
		}
		if trade.Quantity <= 0 || trade.Price <= 0 || (trade.Side != "buy" && trade.Side != "sell") {
			warnings = append(warnings, instrumentLabel(trade)+" 有一笔成交的数量、价格或方向无效，未纳入计算。")
			continue
		}
		if trade.Fee < 0 {
			warnings = append(warnings, instrumentLabel(trade)+" 有一笔成交手续费为负，已按 0 处理。")
			trade.Fee = 0
		}
		valid = append(valid, trade)
	}

	lots := map[string][]lot{}
	closed := make([]closedTrade, 0)
	turnoverBySymbol := map[string]float64{}
	ordersByDay := map[string]int{}
	symbolsByDay := map[string]map[string]struct{}{}
	var totalFees, turnover float64

	for _, trade := range valid {
		key := instrumentKey(trade)
		day := dateKey(trade.occurredAt)
		ordersByDay[day]++
		if symbolsByDay[day] == nil {
			symbolsByDay[day] = map[string]struct{}{}
		}
		symbolsByDay[day][key] = struct{}{}
		totalFees += trade.Fee
		turnover += trade.Quantity * trade.Price
		turnoverBySymbol[key] += trade.Quantity * trade.Price

		if trade.Side == "buy" {
			cost := trade.Quantity*trade.Price + trade.Fee
			lots[key] = append(lots[key], lot{
				remaining:   trade.Quantity,
				costPerUnit: cost / trade.Quantity,
				acquiredAt:  trade.occurredAt,
			})
			continue
		}

		remaining := trade.Quantity
		var matchedQty, matchedCost, holdingWeighted float64
		matchedSameDay := false
		queue := lots[key]
		for remaining > 1e-9 && len(queue) > 0 {
			first := &queue[0]
			take := math.Min(remaining, first.remaining)
			if sameDate(first.acquiredAt, trade.occurredAt) {
				matchedSameDay = true
			}
			matchedQty += take
			matchedCost += take * first.costPerUnit
			holding := trade.occurredAt.Sub(first.acquiredAt).Hours()
			holdingWeighted += math.Max(0, holding) * take
			remaining -= take
			first.remaining -= take
			if first.remaining <= 1e-9 {
				queue = queue[1:]
			}
		}
		lots[key] = queue
		if remaining > 1e-6 {
			warnings = append(warnings, fmt.Sprintf(
				"%s %d月%d日 的卖出有 %s 股无法与截图中的买入配对，未计入已实现盈亏。",
				instrumentLabel(trade), trade.occurredAt.Month(), trade.occurredAt.Day(), qty(remaining)))
		}
		if matchedQty <= 1e-9 {
			continue
		}
		proceeds := matchedQty*trade.Price - trade.Fee*matchedQty/trade.Quantity
		closed = append(closed, closedTrade{
			pnl:          proceeds - matchedCost,
			quantity:     matchedQty,
			holdingHours: holdingWeighted / matchedQty,
			sameDay:      matchedSameDay,
		})
	}

	var grossProfit, grossLoss, matchedQty, weightedHolding float64
	var wins, losses []closedTrade
	for _, trade := range closed {
		if trade.pnl > 0 {
			grossProfit += trade.pnl
			wins = append(wins, trade)
		} else if trade.pnl < 0 {
			grossLoss += trade.pnl
			losses = append(losses, trade)
		}
		matchedQty += trade.quantity
		weightedHolding += trade.holdingHours * trade.quantity
	}
	realized := grossProfit + grossLoss
	averageWin := 0.0
	if len(wins) > 0 {
		averageWin = grossProfit / float64(len(wins))
	}
	averageLoss := 0.0
	if len(losses) > 0 {
		averageLoss = grossLoss / float64(len(losses))
	}
	profitLossRatio := -1.0
	if averageLoss == 0 {
		if averageWin > 0 {
			profitLossRatio = -1
		} else {
			profitLossRatio = 0
		}
	} else {
		profitLossRatio = averageWin / math.Abs(averageLoss)
	}

	maxSymbols, maxTrades := 0, 0
	var symbolsTotal int
	for day, count := range ordersByDay {
		if count > maxTrades {
			maxTrades = count
		}
		n := len(symbolsByDay[day])
		symbolsTotal += n
		if n > maxSymbols {
			maxSymbols = n
		}
	}
	maxTurnover := 0.0
	for _, value := range turnoverBySymbol {
		if value > maxTurnover {
			maxTurnover = value
		}
	}
	openLots := 0
	for _, queue := range lots {
		for _, item := range queue {
			if item.remaining > 1e-9 {
				openLots++
			}
		}
	}
	winHold, loseHold := 0.0, 0.0
	for _, trade := range wins {
		winHold += trade.holdingHours
	}
	for _, trade := range losses {
		loseHold += trade.holdingHours
	}
	if len(wins) > 0 {
		winHold /= float64(len(wins))
	}
	if len(losses) > 0 {
		loseHold /= float64(len(losses))
	}
	best, worst := 0.0, 0.0
	if len(closed) > 0 {
		best, worst = closed[0].pnl, closed[0].pnl
		for _, trade := range closed[1:] {
			best = math.Max(best, trade.pnl)
			worst = math.Min(worst, trade.pnl)
		}
	}
	metrics := Metrics{
		RealizedPnl:             realized,
		GrossProfit:             grossProfit,
		GrossLoss:               grossLoss,
		MatchedSellCount:        len(closed),
		WinningSellCount:        len(wins),
		LosingSellCount:         len(losses),
		AverageWin:              averageWin,
		AverageLoss:             averageLoss,
		ProfitLossRatio:         profitLossRatio,
		AverageWinningHoldHours: winHold,
		AverageLosingHoldHours:  loseHold,
		MaxWinStreak:            maxStreak(closed, true),
		MaxLossStreak:           maxStreak(closed, false),
		TotalFees:               totalFees,
		Turnover:                turnover,
		MaxSymbolsInDay:         maxSymbols,
		MaxTradesInDay:          maxTrades,
		TradingDayCount:         len(ordersByDay),
		OpenLotCount:            openLots,
		BestTradePnl:            best,
		WorstTradePnl:           worst,
	}
	if len(closed) > 0 {
		metrics.WinRate = float64(len(wins)) / float64(len(closed))
		metrics.Expectancy = realized / float64(len(closed))
	}
	if matchedQty > 0 {
		metrics.AverageHoldingHours = weightedHolding / matchedQty
	}
	if realized == 0 {
		if totalFees > 0 {
			metrics.FeeRatio = 1
		}
	} else {
		metrics.FeeRatio = totalFees / math.Abs(realized)
	}
	if turnover > 0 {
		metrics.ConcentrationRatio = maxTurnover / turnover
	}
	if metrics.TradingDayCount > 0 {
		metrics.AverageSymbolsPerDay = float64(symbolsTotal) / float64(metrics.TradingDayCount)
		metrics.AverageTradesPerTrading = float64(len(valid)) / float64(metrics.TradingDayCount)
	}
	for _, trade := range closed {
		if trade.sameDay {
			metrics.SameDayRoundTrips++
		}
	}

	if len(valid) == 0 {
		warnings = append(warnings, "没有可分析的成交行，请上传包含日期、方向、数量和价格的成交记录截图。")
	} else if len(closed) < 3 {
		warnings = append(warnings, "已配对的卖出记录少于 3 笔，胜率和盈亏比只能作为初步观察。")
	}
	if metrics.OpenLotCount > 0 {
		warnings = append(warnings, fmt.Sprintf(
			"截图结束时仍有 %d 批买入未平仓；这些持仓的浮动盈亏不在本报告的已实现盈亏中。",
			metrics.OpenLotCount))
	}
	warnings = append(warnings, "截图未包含账户总资金与单笔风险预算，因此本报告不判断仓位比例或止损金额。")

	currency := strings.ToUpper(strings.TrimSpace(in.Currency))
	if currency != "CNY" && currency != "HKD" && currency != "USD" {
		currency = "CNY"
	}
	title := "成交复盘"
	if len(valid) > 0 {
		first, last := valid[0].occurredAt, valid[len(valid)-1].occurredAt
		title = fmt.Sprintf("%d月%d日", first.Month(), first.Day())
		if !sameDate(first, last) {
			title += fmt.Sprintf("－%d月%d日", last.Month(), last.Day())
		}
		title += fmt.Sprintf(" · %d 笔成交", len(valid))
	}
	return Report{
		ID:           fmt.Sprintf("review-%d", now.UnixMicro()),
		CreatedAt:    now,
		Title:        title,
		BrokerHint:   strings.TrimSpace(in.BrokerHint),
		Currency:     currency,
		Trades:       valid,
		Metrics:      metrics,
		Logic:        buildLogic(metrics, len(valid), turnoverBySymbol),
		Problems:     buildProblems(metrics),
		Improvements: buildImprovements(metrics),
		Warnings:     unique(warnings),
	}
}

func buildLogic(metrics Metrics, tradeCount int, turnoverBySymbol map[string]float64) []Insight {
	if tradeCount == 0 {
		return []Insight{}
	}
	speed := "持有周期相对较长"
	if metrics.AverageHoldingHours <= 24 {
		speed = "偏短周期"
	} else if metrics.AverageHoldingHours <= 24*5 {
		speed = "以数日持有为主"
	}
	body := fmt.Sprintf(
		"卖出按先进先出与买入配对后，已平仓交易的平均持有时间约为 %s。",
		hours(metrics.AverageHoldingHours))
	if metrics.MatchedSellCount == 0 {
		body = "现有成交尚未形成可配对的卖出闭环，无法判断持仓时长。"
	}
	out := []Insight{{
		Kind: "logic", Title: "持仓节奏：" + speed, Body: body,
		Evidence: []string{
			fmt.Sprintf("%d 笔卖出与同日买入形成闭环", metrics.SameDayRoundTrips),
			fmt.Sprintf("共 %d 个交易日、%d 笔已配对卖出", metrics.TradingDayCount, metrics.MatchedSellCount),
		},
	}}
	if metrics.MatchedSellCount > 0 {
		outcome := "盈利"
		if metrics.RealizedPnl < 0 {
			outcome = "亏损"
		}
		body := fmt.Sprintf(
			"当前胜率为 %s，平均盈利 / 平均亏损为 %s，每笔已配对卖出的期望为 %.2f。",
			percent(metrics.WinRate), ratio(metrics.ProfitLossRatio), metrics.Expectancy)
		if metrics.ProfitLossRatio < 0 {
			body = "样本内没有亏损卖出，当前盈亏比无法稳定估计；这通常也意味着样本偏少或区间偏短。"
		}
		out = append(out, Insight{
			Kind: "logic", Title: "结果结构：" + outcome + "由胜率和赔率共同决定", Body: body,
			Evidence: []string{
				fmt.Sprintf("盈利 %d 笔，亏损 %d 笔", metrics.WinningSellCount, metrics.LosingSellCount),
				fmt.Sprintf("最大连续盈利 %d 笔，最大连续亏损 %d 笔", metrics.MaxWinStreak, metrics.MaxLossStreak),
			},
		})
	}
	if len(turnoverBySymbol) > 0 {
		leader := ""
		for key := range turnoverBySymbol {
			if leader == "" || turnoverBySymbol[key] > turnoverBySymbol[leader] {
				leader = key
			}
		}
		title, body := "标的选择：成交分散在多个标的",
			fmt.Sprintf("成交金额没有集中在单一标的，最高占比为 %s。", percent(metrics.ConcentrationRatio))
		if metrics.ConcentrationRatio >= 0.5 {
			title = "标的选择：明显集中于单一标的"
			body = fmt.Sprintf("成交金额占比最高的标的是 %s，占全部成交金额的 %s。",
				leader, percent(metrics.ConcentrationRatio))
		}
		out = append(out, Insight{
			Kind: "logic", Title: title, Body: body,
			Evidence: []string{
				fmt.Sprintf("单日最多涉及 %d 个标的", metrics.MaxSymbolsInDay),
				fmt.Sprintf("日均涉及 %.1f 个标的", metrics.AverageSymbolsPerDay),
			},
		})
	}
	out = append(out, Insight{
		Kind: "logic", Title: "执行密度：" + densityLabel(metrics.AverageTradesPerTrading),
		Body: fmt.Sprintf(
			"按截图中的交易日计算，日均成交 %.1f 笔，单日最多 %d 笔。这是成交频率，不等同于仓位轻重。",
			metrics.AverageTradesPerTrading, metrics.MaxTradesInDay),
		Evidence: []string{
			fmt.Sprintf("累计成交金额 %.2f", metrics.Turnover),
			fmt.Sprintf("累计手续费 %.2f", metrics.TotalFees),
		},
	})
	if len(out) > 4 {
		out = out[:4]
	}
	return out
}

func buildProblems(metrics Metrics) []Insight {
	out := []Insight{}
	if metrics.MatchedSellCount < 3 {
		out = append(out, Insight{
			Kind: "problem", Title: "样本不足，暂不把短期结果当作稳定规律",
			Body: "可配对的卖出少于 3 笔。此时胜率、连续亏损和盈亏比都容易受单笔交易影响，更适合先核对数据是否完整，再扩大复盘区间。",
		})
	}
	if metrics.AverageWinningHoldHours > 0 &&
		metrics.AverageLosingHoldHours > 0 &&
		metrics.AverageWinningHoldHours+0.01 < metrics.AverageLosingHoldHours &&
		metrics.WinningSellCount >= 2 && metrics.LosingSellCount >= 2 {
		out = append(out, Insight{
			Kind: "problem", Title: "出现“赢家卖得快、亏损拿得久”的处置效应",
			Body: "盈利交易的平均持有时间短于亏损交易。它可能来自过早兑现，也可能来自亏损后拖延退出；需要结合入场理由复核。",
			Evidence: []string{
				"盈利平均持有 " + hours(metrics.AverageWinningHoldHours),
				"亏损平均持有 " + hours(metrics.AverageLosingHoldHours),
			},
		})
	}
	if metrics.TotalFees > 0 && metrics.RealizedPnl <= 0 && metrics.MatchedSellCount > 0 {
		out = append(out, Insight{
			Kind: "problem", Title: "手续费仍在放大已实现亏损",
			Body:     "样本内已实现结果为亏损，同时产生了手续费。高频或不必要的换手会让本金在方向判断之外继续损耗。",
			Evidence: []string{fmt.Sprintf("累计手续费 %.2f", metrics.TotalFees)},
		})
	} else if metrics.FeeRatio >= 0.2 && metrics.MatchedSellCount > 0 {
		out = append(out, Insight{
			Kind: "problem", Title: "手续费对净收益的侵蚀偏高",
			Body:     "手续费占已实现盈亏绝对值的比例较高。在单笔优势不够明显时，频繁成交更容易把利润磨掉。",
			Evidence: []string{"手续费 / |已实现盈亏| = " + percent(metrics.FeeRatio)},
		})
	}
	if metrics.MaxLossStreak >= 3 {
		out = append(out, Insight{
			Kind: "problem", Title: "连续亏损后的执行稳定性需要检查",
			Body: fmt.Sprintf("样本内出现过 %d 笔连续亏损。重点不是把这段亏损解释成行情，而是检查连亏后是否加速加注、扩大交易频率或取消原有退出条件。",
				metrics.MaxLossStreak),
		})
	}
	if metrics.ProfitLossRatio >= 0 && metrics.ProfitLossRatio < 1 &&
		metrics.WinningSellCount >= 2 && metrics.LosingSellCount >= 2 {
		out = append(out, Insight{
			Kind: "problem", Title: "平均盈利不足以覆盖平均亏损",
			Body:     "即使胜率不低，单笔平均亏损仍大于单笔平均盈利。需要让盈利目标、退出条件和实际波动重新匹配。",
			Evidence: []string{"盈亏比 " + ratio(metrics.ProfitLossRatio)},
		})
	}
	if metrics.MaxSymbolsInDay >= 4 ||
		(metrics.AverageSymbolsPerDay >= 3 && metrics.AverageTradesPerTrading >= 6) {
		out = append(out, Insight{
			Kind: "problem", Title: "同日多标的切换可能压缩复盘深度",
			Body: "成交记录显示同一天频繁切换多个标的。由于截图没有入场理由，不能直接断言追涨或冲动交易；但标的切换越快，越容易遗漏原定退出条件。",
			Evidence: []string{
				fmt.Sprintf("单日最多 %d 个标的", metrics.MaxSymbolsInDay),
				fmt.Sprintf("日均 %.1f 笔成交", metrics.AverageTradesPerTrading),
			},
		})
	}
	if len(out) == 0 {
		out = append(out, Insight{
			Kind: "problem", Title: "截图能证明的问题有限",
			Body: "从成交行本身没有发现明显的频率、赔率或手续费异常。这不等于交易逻辑可靠，仍需要对照每笔交易前的入场理由和退出计划。",
		})
	}
	if len(out) > 4 {
		out = out[:4]
	}
	return out
}

func buildImprovements(metrics Metrics) []Insight {
	out := []Insight{}
	if metrics.TotalFees > 0 {
		out = append(out, Insight{
			Kind: "improvement", Title: "给每笔交易写一句入场理由和退出条件",
			Body: "下单前写清“为什么现在买 / 什么情况下退出”，成交后再用截图核对执行是否偏离。这样下一次复盘能区分判断问题与执行问题。",
		})
	}
	if metrics.SameDayRoundTrips > 0 || metrics.AverageTradesPerTrading >= 6 {
		out = append(out, Insight{
			Kind: "improvement", Title: "设置“冷静一笔”规则",
			Body:     "在同一标的卖出后，先记录结果和原因，再决定是否立即寻找下一个标的。先减少无计划的同日切换，再观察胜率和手续费是否改善。",
			Evidence: []string{fmt.Sprintf("当前有 %d 笔同日闭环交易", metrics.SameDayRoundTrips)},
		})
	}
	if metrics.MaxLossStreak >= 3 {
		out = append(out, Insight{
			Kind: "improvement", Title: "为连续亏损设置暂停与复核条件",
			Body: "连续亏损达到预设笔数时暂停新开仓，逐笔核对入场理由、退出条件和是否临时改变计划。暂停条件应提前写下，避免亏损发生后临时决定。",
		})
	}
	if metrics.ProfitLossRatio >= 0 && metrics.ProfitLossRatio < 1 &&
		metrics.WinningSellCount >= 2 && metrics.LosingSellCount >= 2 {
		out = append(out, Insight{
			Kind: "improvement", Title: "把退出条件放在入场之前",
			Body: "复盘亏损单时，不只看亏损金额，还要记录当时依据什么继续持有。下一批交易先写退出点，再执行，避免把短线交易拖成被动持有。",
		})
	}
	if metrics.ConcentrationRatio >= 0.5 {
		out = append(out, Insight{
			Kind: "improvement", Title: "复核单一标的的重复决策",
			Body: "高集中度本身不是错误，但需要确认每笔增减仓都有独立理由，避免把上一笔的盈亏情绪带进下一笔。",
		})
	}
	if metrics.MatchedSellCount < 3 {
		out = append([]Insight{{
			Kind: "improvement", Title: "先补全一段完整成交区间",
			Body: "优先上传覆盖多笔买入和卖出的成交记录，确保每一笔卖出都能与买入配对，再比较胜率和盈亏比。",
		}}, out...)
	}
	if len(out) < 2 {
		out = append(out, Insight{
			Kind: "improvement", Title: "每周固定复看一次连续亏损段",
			Body: "不要只复盘赚钱单。把连续亏损前后的成交频率、标的切换和退出执行放在一起看，更容易发现行为变化。",
		})
	}
	if len(out) > 4 {
		out = out[:4]
	}
	return out
}

func parseTradeMoment(trade Trade) (time.Time, error) {
	date := strings.TrimSpace(trade.TradeDate)
	clock := strings.TrimSpace(trade.TradeTime)
	value := date
	if clock != "" {
		value += "T" + clock
	}
	for _, layout := range []string{
		"2006-01-02T15:04:05", "2006-01-02T15:04", "2006-01-02",
		"2006/01/02T15:04:05", "2006/01/02",
	} {
		if parsed, err := time.ParseInLocation(layout, value, time.Local); err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, fmt.Errorf("invalid trade moment")
}

func instrumentKey(trade Trade) string {
	value := strings.TrimSpace(trade.Symbol)
	if value == "" {
		value = strings.TrimSpace(trade.Name)
	}
	return strings.ToUpper(value)
}

func instrumentLabel(trade Trade) string {
	name, symbol := strings.TrimSpace(trade.Name), strings.TrimSpace(trade.Symbol)
	if name != "" && symbol != "" && name != symbol {
		return name + " · " + symbol
	}
	if name != "" {
		return name
	}
	if symbol != "" {
		return symbol
	}
	return "未命名标的"
}

func dateKey(value time.Time) string {
	return fmt.Sprintf("%04d-%02d-%02d", value.Year(), value.Month(), value.Day())
}

func sameDate(a, b time.Time) bool {
	return a.Year() == b.Year() && a.YearDay() == b.YearDay()
}

func maxStreak(trades []closedTrade, winning bool) int {
	current, best := 0, 0
	for _, trade := range trades {
		matches := trade.pnl < 0
		if winning {
			matches = trade.pnl > 0
		}
		if matches {
			current++
			if current > best {
				best = current
			}
		} else {
			current = 0
		}
	}
	return best
}

func unique(values []string) []string {
	seen := map[string]struct{}{}
	out := []string{}
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}

func qty(value float64) string {
	if math.Abs(value-math.Round(value)) < 1e-9 {
		return strconv.FormatFloat(value, 'f', 0, 64)
	}
	return strconv.FormatFloat(value, 'f', 2, 64)
}

func percent(value float64) string {
	return strconv.FormatFloat(value*100, 'f', 1, 64) + "%"
}

func ratio(value float64) string {
	if value < 0 {
		return "∞ : 1"
	}
	return strconv.FormatFloat(value, 'f', 2, 64) + " : 1"
}

func hours(value float64) string {
	if value <= 0 {
		return "不到 1 小时"
	}
	if value < 24 {
		return strconv.FormatFloat(value, 'f', 1, 64) + " 小时"
	}
	return strconv.FormatFloat(value/24, 'f', 1, 64) + " 天"
}

func densityLabel(value float64) string {
	if value >= 8 {
		return "偏高"
	}
	if value >= 3 {
		return "中等"
	}
	return "较低"
}
