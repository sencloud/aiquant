package strategy

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"
)

// LivePortfolioID 是「组合管理」里系统托管组合的 id（客户端用它做 Hive 主键）。
// 名字沿用早期的 live: 前缀以免客户端出现两个组合；内容已经是「策略模拟」。
const LivePortfolioID = "live:" + PrimaryID

// DefaultSimCapital 是策略模拟组合的默认名义本金。
const DefaultSimCapital = 1_000_000.0

// simVersion 变了就会让已落库的日快照在下一轮被重算（模拟口径变更时 +1）。
const simVersion = 1

// 成本模型：从上游回测成交反推，与策略回测同一口径。
//
//	买入：成交价 = 收盘价 × (1 + 滑点万5)；佣金 万2.5（最低 5 元）+ 过户费 万0.1
//	卖出：成交价 = 收盘价 × (1 − 滑点万5)；佣金 万2.5（最低 5 元）+ 过户费 万0.1 + 印花税 万5
//	股数按 100 股整数倍向下取整。
const (
	simSlippage      = 0.0005
	simCommission    = 0.00025
	simMinCommission = 5.0
	simTransfer      = 0.00001
	simStamp         = 0.0005
	simLot           = 100.0
)

// SimCostModel 是给用户看的成本口径说明。
const SimCostModel = "收盘价成交，滑点万5；佣金万2.5（最低5元）、过户费万0.1、卖出印花税万5；100股整数倍"

// LivePortfolio 是「组合管理」里的策略模拟组合：按策略每期调仓结论、用名义本金
// 模拟出来的持仓 + 交易流水 + 每日净值。与人工实盘账户无关。
type LivePortfolio struct {
	ID          string `json:"id"`
	StrategyID  string `json:"strategy_id"`
	Mode        string `json:"mode"` // simulation
	Name        string `json:"name"`
	Description string `json:"description"`
	Currency    string `json:"currency"`

	AsOf           string `json:"as_of"`
	Inception      string `json:"inception"`
	MaterializedAt int64  `json:"materialized_at"`
	Stale          bool   `json:"stale"`
	StaleDays      int    `json:"stale_days"`

	Capital     float64 `json:"capital"`
	Cash        float64 `json:"cash"`
	MarketValue float64 `json:"market_value"`
	Total       float64 `json:"total"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
	Realized    float64 `json:"realized"`
	Fees        float64 `json:"fees"`
	Dividends   float64 `json:"dividends"`

	Holdings     []LiveHolding  `json:"holdings"`
	Transactions []LiveTxn      `json:"transactions"`
	Rebalances   []SimRebalance `json:"rebalances"`

	CostModel   string `json:"cost_model"`
	HistoryNote string `json:"history_note,omitempty"`
	// Notes 是模拟过程中的降级说明（某只停牌用前收、分红数据取不到等）。
	Notes []string `json:"notes,omitempty"`

	Target     []TargetItem `json:"target,omitempty"`
	SignalDate string       `json:"signal_date,omitempty"`
	ExecDate   string       `json:"exec_date,omitempty"`
	Curve      []LivePoint  `json:"curve,omitempty"`

	// SourceKey / SnapshotAsOf 用来判断输入没变时跳过重算。
	SourceKey    string `json:"source_key"`
	SnapshotAsOf string `json:"snapshot_as_of"`
}

type LiveHolding struct {
	Symbol      string  `json:"symbol"`
	Name        string  `json:"name"`
	Industry    string  `json:"industry,omitempty"`
	AssetClass  string  `json:"asset_class"`
	Shares      float64 `json:"shares"`
	AvgCost     float64 `json:"avg_cost"`
	Price       float64 `json:"price"`
	MarketValue float64 `json:"market_value"`
	Weight      float64 `json:"weight"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
	InTarget    bool    `json:"in_target"`
}

// LiveTxn 对齐客户端 PortfolioTransaction：type ∈ buy / sell / dividend / split。
//
// Price 是「含费净价」：买入 = (成交额 + 费用) / 股数，卖出 = (成交额 − 费用) / 股数，
// 客户端按加权平均成本回放即得到与模拟一致的均价。split 的 Quantity 是比例。
type LiveTxn struct {
	ID         string  `json:"id"`
	Date       string  `json:"date"`
	Type       string  `json:"type"`
	Symbol     string  `json:"symbol"`
	Name       string  `json:"name"`
	Industry   string  `json:"industry,omitempty"`
	AssetClass string  `json:"asset_class"`
	Quantity   float64 `json:"quantity"`
	Price      float64 `json:"price"`
	GrossPrice float64 `json:"gross_price,omitempty"`
	Fees       float64 `json:"fees,omitempty"`
	Amount     float64 `json:"amount"`
	Note       string  `json:"note,omitempty"`
}

// SimRebalance 是一期策略调仓结论：执行日、调仓后目标名单、买入与剔除。
type SimRebalance struct {
	Date    string       `json:"date"`
	Target  []TargetItem `json:"target"`
	Buys    []TargetItem `json:"buys"`
	Sells   []TargetItem `json:"sells"`
	Initial bool         `json:"initial,omitempty"`
}

// DailyClose 是一只股票某日的不复权收盘价。Date 为 YYYY-MM-DD。
type DailyClose struct {
	Date  string
	Close float64
}

// Dividend 是一次已实施的分红送转：每股现金（税前）与每股送转股数。
type Dividend struct {
	ExDate        string
	CashPerShare  float64
	StockPerShare float64
}

// PriceSource 给模拟提供行情（生产用 Tushare，测试用假数据）。
type PriceSource interface {
	DailyCloses(ctx context.Context, code string, start, end time.Time) ([]DailyClose, error)
	Dividends(ctx context.Context, code string) ([]Dividend, error)
}

// ReconstructRebalances 从快照还原策略每期的调仓结论。
//
// 上游只给最近 N 笔回测成交（每期只交易名单变化的部分），以及最新一期信号的
// 目标名单。做法：以回测期末持仓（= 最新目标名单，若最新一期尚未执行则为上期名单）
// 为终点，按执行日倒推「调仓前名单 = 调仓后 − 买入 + 卖出」，一直推到成交记录
// 的最早一期；推不通（名单数对不上）就在那一期截断。返回按日期升序的各期，
// 第一期视为建仓。
func ReconstructRebalances(snap *Snapshot) ([]SimRebalance, string) {
	if snap == nil || len(snap.Action.Target) == 0 {
		return nil, ""
	}
	names := map[string]string{}
	for _, t := range snap.Action.Target {
		names[t.Code] = t.Name
	}
	for _, t := range snap.Action.PrevTarget {
		names[t.Code] = t.Name
	}
	byDate := map[string][]BacktestTrade{}
	for _, t := range snap.BacktestTrades {
		if t.Name != "" {
			names[t.Code] = t.Name
		}
		byDate[t.Date] = append(byDate[t.Date], t)
	}
	dates := make([]string, 0, len(byDate))
	for d := range byDate {
		dates = append(dates, d)
	}
	sort.Strings(dates)

	item := func(code string) TargetItem { return TargetItem{Code: code, Name: names[code]} }
	toSet := func(ts []TargetItem) map[string]bool {
		m := map[string]bool{}
		for _, t := range ts {
			m[t.Code] = true
		}
		return m
	}
	setItems := func(m map[string]bool) []TargetItem {
		codes := make([]string, 0, len(m))
		for c := range m {
			codes = append(codes, c)
		}
		sort.Strings(codes)
		out := make([]TargetItem, 0, len(codes))
		for _, c := range codes {
			out = append(out, item(c))
		}
		return out
	}

	// 最新一期：已执行（或名单没变）→ 回测期末持仓就是最新名单。
	end := snap.Action.Target
	var pending *SimRebalance
	_, execInTrades := byDate[snap.Action.ExecDate]
	if snap.Action.Changed && len(snap.Action.PrevTarget) > 0 && !execInTrades {
		end = snap.Action.PrevTarget
		cur, prev := toSet(snap.Action.Target), toSet(snap.Action.PrevTarget)
		p := SimRebalance{Date: snap.Action.ExecDate, Target: setItems(cur)}
		for c := range cur {
			if !prev[c] {
				p.Buys = append(p.Buys, item(c))
			}
		}
		for c := range prev {
			if !cur[c] {
				p.Sells = append(p.Sells, item(c))
			}
		}
		sortItems(p.Buys)
		sortItems(p.Sells)
		pending = &p
	}

	topN := len(end)
	after := toSet(end)
	var plans []SimRebalance
	truncated := false
	for i := len(dates) - 1; i >= 0; i-- {
		d := dates[i]
		before := map[string]bool{}
		for c := range after {
			before[c] = true
		}
		var buys, sells []TargetItem
		ok := true
		for _, t := range byDate[d] {
			switch strings.ToLower(t.Action) {
			case "buy":
				if !after[t.Code] {
					ok = false
				}
				delete(before, t.Code)
				buys = append(buys, item(t.Code))
			case "sell":
				if after[t.Code] {
					ok = false
				}
				before[t.Code] = true
				sells = append(sells, item(t.Code))
			}
		}
		if !ok || len(before) != topN {
			truncated = true
			break
		}
		sortItems(buys)
		sortItems(sells)
		plans = append(plans, SimRebalance{Date: d, Target: setItems(after), Buys: buys, Sells: sells})
		after = before
	}
	// 倒序 → 升序。
	for i, j := 0, len(plans)-1; i < j; i, j = i+1, j-1 {
		plans[i], plans[j] = plans[j], plans[i]
	}
	if len(plans) == 0 {
		// 没有任何可用的调仓成交：只能从最新一期信号建仓。
		d := snap.Action.ExecDate
		if d == "" {
			d = snap.Action.SignalDate
		}
		p := SimRebalance{Date: d, Target: setItems(toSet(snap.Action.Target)), Initial: true}
		p.Buys = p.Target
		return []SimRebalance{p}, "上游只提供了最新一期目标名单，模拟从该期执行日开始"
	}
	plans[0].Initial = true
	plans[0].Buys = plans[0].Target
	plans[0].Sells = nil
	if pending != nil && pending.Date != "" && pending.Date <= snap.DataAsOf {
		plans = append(plans, *pending)
	}
	note := fmt.Sprintf("上游提供最近 %d 笔回测调仓成交，可还原 %s 起共 %d 期调仓结论；更早的历史上游未提供",
		len(snap.BacktestTrades), plans[0].Date, len(plans))
	if truncated {
		note += "（更早的成交与名单对不上，已截断）"
	}
	return plans, note
}

func sortItems(ts []TargetItem) {
	sort.Slice(ts, func(i, j int) bool { return ts[i].Code < ts[j].Code })
}

type simPos struct {
	shares float64
	cost   float64 // 含费总成本
}

func buyFees(gross float64) float64 {
	return math.Max(simMinCommission, gross*simCommission) + gross*simTransfer
}

func sellFees(gross float64) float64 {
	return math.Max(simMinCommission, gross*simCommission) + gross*simTransfer + gross*simStamp
}

func parseDay(s string) (time.Time, error) { return time.Parse("2006-01-02", s) }

// SimulatePortfolio 按各期调仓结论用名义本金模拟组合，逐日按收盘价估值。
//
// 规则：建仓期按目标名单等权分配本金；之后每期与策略回测同口径——卖出被剔除的、
// 用可用现金等额买入新进的，留在名单里的不动；名单不变的月份不交易。
// 成交用执行日收盘价（停牌取最近收盘价）；现金分红按除权日持股入账（税前），
// 送转按比例增股。
func SimulatePortfolio(ctx context.Context, snap *Snapshot, src PriceSource, capital float64) (*LivePortfolio, error) {
	if capital <= 0 {
		capital = DefaultSimCapital
	}
	plans, historyNote := ReconstructRebalances(snap)
	if len(plans) == 0 {
		return nil, errors.New("strategy sim: no rebalance signals in snapshot")
	}
	start, err := parseDay(plans[0].Date)
	if err != nil {
		return nil, fmt.Errorf("strategy sim: bad start date %q", plans[0].Date)
	}
	endDay := snap.DataAsOf
	if endDay == "" || endDay < plans[len(plans)-1].Date {
		endDay = plans[len(plans)-1].Date
	}
	end, err := parseDay(endDay)
	if err != nil {
		return nil, fmt.Errorf("strategy sim: bad end date %q", endDay)
	}

	names := map[string]string{}
	codeSet := map[string]bool{}
	for _, p := range plans {
		for _, t := range p.Target {
			codeSet[t.Code] = true
			names[t.Code] = t.Name
		}
		for _, t := range p.Sells {
			codeSet[t.Code] = true
			names[t.Code] = t.Name
		}
	}
	codes := make([]string, 0, len(codeSet))
	for c := range codeSet {
		codes = append(codes, c)
	}
	sort.Strings(codes)
	industry := map[string]string{}
	for _, d := range snap.Action.TargetDetail {
		if d.Industry != "" {
			industry[d.Code] = d.Industry
		}
	}

	var notes []string
	closes := map[string]map[string]float64{}
	calSet := map[string]bool{}
	for _, c := range codes {
		rows, err := src.DailyCloses(ctx, c, start.AddDate(0, 0, -15), end)
		if err != nil {
			return nil, fmt.Errorf("strategy sim: closes %s: %w", c, err)
		}
		m := map[string]float64{}
		for _, r := range rows {
			if r.Close <= 0 {
				continue
			}
			m[r.Date] = r.Close
			if r.Date >= plans[0].Date && r.Date <= endDay {
				calSet[r.Date] = true
			}
		}
		closes[c] = m
	}
	cal := make([]string, 0, len(calSet))
	for d := range calSet {
		cal = append(cal, d)
	}
	sort.Strings(cal)
	if len(cal) == 0 {
		return nil, errors.New("strategy sim: no price data in simulation window")
	}
	divs := map[string]map[string]Dividend{}
	for _, c := range codes {
		rows, err := src.Dividends(ctx, c)
		if err != nil {
			notes = append(notes, fmt.Sprintf("%s 分红数据获取失败，未计入分红", names[c]))
			continue
		}
		m := map[string]Dividend{}
		for _, d := range rows {
			if d.ExDate != "" {
				m[d.ExDate] = d
			}
		}
		divs[c] = m
	}

	p := &LivePortfolio{
		ID:          LivePortfolioID,
		StrategyID:  snap.StrategyID,
		Mode:        "simulation",
		Name:        "策略模拟：" + shortName(snap.Meta.Name),
		Currency:    "CNY",
		Inception:   cal[0],
		Capital:     capital,
		CostModel:   SimCostModel,
		HistoryNote: historyNote,
		Target:      snap.Action.Target,
		SignalDate:  snap.Action.SignalDate,
		ExecDate:    snap.Action.ExecDate,
		Stale:       snap.Stale,
		StaleDays:   snap.StaleDays,
	}

	cash := capital
	pos := map[string]*simPos{}
	last := map[string]float64{}
	// 起始日之前的最近收盘价也要能取到（建仓日恰好停牌时用）。
	for _, c := range codes {
		best := ""
		for d := range closes[c] {
			if d < cal[0] && d > best {
				best = d
			}
		}
		if best != "" {
			last[c] = closes[c][best]
		}
	}
	txnSeq := 0
	addTxn := func(t LiveTxn) {
		txnSeq++
		t.ID = fmt.Sprintf("%s:s%d:%s:%s", LivePortfolioID, txnSeq, t.Date, t.Symbol)
		t.Name = names[t.Symbol]
		t.Industry = industry[t.Symbol]
		t.AssetClass = "股票"
		p.Transactions = append(p.Transactions, t)
	}
	planIdx := 0
	for _, day := range cal {
		for _, c := range codes {
			if px, ok := closes[c][day]; ok {
				last[c] = px
			}
		}
		// 分红送转：除权日按前一日持股入账。
		for _, c := range codes {
			ps := pos[c]
			if ps == nil || ps.shares <= 0 {
				continue
			}
			d, ok := divs[c][day]
			if !ok {
				continue
			}
			if d.CashPerShare > 0 {
				amt := round2(ps.shares * d.CashPerShare)
				cash += amt
				p.Dividends += amt
				addTxn(LiveTxn{Date: day, Type: "dividend", Symbol: c, Quantity: ps.shares,
					Price: d.CashPerShare, Amount: amt, Note: "现金分红（税前）"})
			}
			if d.StockPerShare > 0 {
				ratio := 1 + d.StockPerShare
				ps.shares = math.Floor(ps.shares*ratio + 1e-6)
				addTxn(LiveTxn{Date: day, Type: "split", Symbol: c, Quantity: ratio, Note: "送转股"})
			}
		}
		// 调仓：执行日（或其后第一个有行情的交易日）。
		for planIdx < len(plans) && plans[planIdx].Date <= day {
			pl := plans[planIdx]
			planIdx++
			label := "策略调仓"
			if pl.Initial {
				label = "策略建仓"
			}
			for _, s := range pl.Sells {
				ps := pos[s.Code]
				if ps == nil || ps.shares <= 0 {
					continue
				}
				px := last[s.Code]
				if px <= 0 {
					notes = append(notes, fmt.Sprintf("%s %s 无行情，未能卖出", day, names[s.Code]))
					continue
				}
				exec := px * (1 - simSlippage)
				gross := ps.shares * exec
				fees := sellFees(gross)
				net := gross - fees
				cash += net
				p.Fees += fees
				p.Realized += net - ps.cost
				addTxn(LiveTxn{Date: day, Type: "sell", Symbol: s.Code, Quantity: ps.shares,
					Price: round4(net / ps.shares), GrossPrice: round4(exec), Fees: round2(fees),
					Amount: round2(net), Note: label + "：剔除"})
				delete(pos, s.Code)
			}
			// 只买当前没拿着的新进标的；可用现金等额分。
			var buys []TargetItem
			for _, b := range pl.Buys {
				if ps := pos[b.Code]; ps == nil || ps.shares <= 0 {
					buys = append(buys, b)
				}
			}
			for i, b := range buys {
				px := last[b.Code]
				if px <= 0 {
					notes = append(notes, fmt.Sprintf("%s %s 无行情，未能买入", day, names[b.Code]))
					continue
				}
				budget := cash / float64(len(buys)-i)
				exec := px * (1 + simSlippage)
				shares := math.Floor(budget/(exec*(1+simCommission+simTransfer))/simLot) * simLot
				for shares > 0 && shares*exec+buyFees(shares*exec) > budget+1e-9 {
					shares -= simLot
				}
				if shares <= 0 {
					notes = append(notes, fmt.Sprintf("%s %s 资金不足一手，未买入", day, names[b.Code]))
					continue
				}
				gross := shares * exec
				fees := buyFees(gross)
				cash -= gross + fees
				p.Fees += fees
				pos[b.Code] = &simPos{shares: shares, cost: gross + fees}
				addTxn(LiveTxn{Date: day, Type: "buy", Symbol: b.Code, Quantity: shares,
					Price: round4((gross + fees) / shares), GrossPrice: round4(exec), Fees: round2(fees),
					Amount: round2(gross + fees), Note: label + "：买入"})
			}
			p.Rebalances = append(p.Rebalances, pl)
		}
		mv := 0.0
		for c, ps := range pos {
			mv += ps.shares * last[c]
		}
		p.Curve = append(p.Curve, LivePoint{Date: day, Total: round2(cash + mv)})
	}

	p.AsOf = cal[len(cal)-1]
	p.Cash = round2(cash)
	held := make([]string, 0, len(pos))
	for c := range pos {
		held = append(held, c)
	}
	sort.Strings(held)
	target := map[string]bool{}
	for _, t := range snap.Action.Target {
		target[t.Code] = true
	}
	for _, c := range held {
		ps := pos[c]
		mv := ps.shares * last[c]
		p.MarketValue += mv
		p.Holdings = append(p.Holdings, LiveHolding{
			Symbol: c, Name: names[c], Industry: industry[c], AssetClass: "股票",
			Shares: ps.shares, AvgCost: round4(ps.cost / ps.shares), Price: last[c],
			MarketValue: round2(mv), PnL: round2(mv - ps.cost),
			PnLPct:   round4((mv - ps.cost) / ps.cost),
			InTarget: target[c],
		})
	}
	p.MarketValue = round2(p.MarketValue)
	p.Total = round2(cash + p.MarketValue)
	for i := range p.Holdings {
		if p.Total > 0 {
			p.Holdings[i].Weight = round4(p.Holdings[i].MarketValue / p.Total)
		}
	}
	p.PnL = round2(p.Total - capital)
	p.PnLPct = round4(p.PnL / capital)
	p.Fees = round2(p.Fees)
	p.Realized = round2(p.Realized)
	p.Dividends = round2(p.Dividends)
	p.Notes = notes
	p.Description = fmt.Sprintf("策略模拟资金 · 非实盘：按「%s」每期调仓结论，以名义本金 %s元自 %s 起模拟（%s）。数据截至 %s，只读。",
		snap.Meta.Name, formatCapital(capital), p.Inception, SimCostModel, p.AsOf)
	p.SnapshotAsOf = snap.DataAsOf
	p.SourceKey = simSourceKey(snap, capital)
	return p, nil
}

func formatCapital(v float64) string {
	if v >= 10000 && math.Mod(v, 10000) == 0 {
		return fmt.Sprintf("%.0f万", v/10000)
	}
	return fmt.Sprintf("%.0f", v)
}

// simSourceKey 概括模拟的全部输入：口径版本、本金、最新信号与回测成交。
func simSourceKey(snap *Snapshot, capital float64) string {
	first, last := "", ""
	if n := len(snap.BacktestTrades); n > 0 {
		first, last = snap.BacktestTrades[n-1].Date, snap.BacktestTrades[0].Date
	}
	codes := make([]string, 0, len(snap.Action.Target))
	for _, t := range snap.Action.Target {
		codes = append(codes, t.Code)
	}
	return fmt.Sprintf("v%d|%.0f|%s|%s|%t|%s|%d|%s|%s", simVersion, capital,
		snap.Action.SignalDate, snap.Action.ExecDate, snap.Action.Changed,
		strings.Join(codes, ","), len(snap.BacktestTrades), first, last)
}

// shortName：「上证50 九因子选股」→「上证50 九因子」，组合选择器里放得下。
func shortName(s string) string {
	s = strings.TrimSpace(s)
	s = strings.TrimSuffix(s, "选股")
	s = strings.TrimSuffix(s, "轮动")
	return strings.TrimSpace(s)
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }
func round4(v float64) float64 { return math.Round(v*10000) / 10000 }

func (s *Service) simCapital() float64 {
	if s.SimCapital > 0 {
		return s.SimCapital
	}
	return DefaultSimCapital
}

func (s *Service) priceSource() (PriceSource, error) {
	if s.prices != nil {
		return s.prices, nil
	}
	if s.tu == nil || !s.tu.Configured() {
		return nil, errors.New("strategy sim: tushare not configured")
	}
	return &tushareSource{tu: s.tu}, nil
}

// MaterializeLivePortfolio 用最新快照模拟策略组合，按「数据截至日」每天落一份。
//
// 输入（SourceKey）与快照截至日都没变时直接返回库里那份，不重复拉行情；
// 同一天重复跑会覆盖（幂等）。非模拟口径的旧行（早期按人工实盘生成的）会被清掉。
// 返回本次的组合与是否新的一天。
func (s *Service) MaterializeLivePortfolio(ctx context.Context) (*LivePortfolio, bool, error) {
	snap, err := s.Latest(ctx)
	if err != nil {
		return nil, false, err
	}
	if snap == nil {
		return nil, false, nil
	}
	key := simSourceKey(snap, s.simCapital())
	if prev, err := s.latestStored(ctx); err == nil && prev != nil &&
		prev.Mode == "simulation" && prev.SourceKey == key && prev.SnapshotAsOf == snap.DataAsOf {
		return prev, false, nil
	}
	src, err := s.priceSource()
	if err != nil {
		return nil, false, err
	}
	p, err := SimulatePortfolio(ctx, snap, src, s.simCapital())
	if err != nil {
		return nil, false, err
	}
	p.MaterializedAt = time.Now().UnixMilli()
	payload, err := json.Marshal(p)
	if err != nil {
		return nil, false, err
	}
	var existed int
	_ = s.st.DB.GetContext(ctx, &existed, `SELECT COUNT(1) FROM live_portfolio_daily WHERE portfolio_id=? AND as_of=?`, p.ID, p.AsOf)
	if _, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO live_portfolio_daily(portfolio_id, as_of, payload_json, materialized_at)
		VALUES(?, ?, ?, ?)
		ON CONFLICT(portfolio_id, as_of) DO UPDATE SET
		  payload_json=excluded.payload_json, materialized_at=excluded.materialized_at`,
		p.ID, p.AsOf, string(payload), p.MaterializedAt); err != nil {
		return nil, false, fmt.Errorf("upsert strategy sim portfolio: %w", err)
	}
	// 早期按人工实盘生成的行不再有效，连同超过 400 天的旧快照一起清掉。
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM live_portfolio_daily WHERE portfolio_id=? AND
		  COALESCE(json_extract(payload_json, '$.mode'), '') <> 'simulation'`, p.ID)
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM live_portfolio_daily WHERE portfolio_id=? AND as_of NOT IN (
			SELECT as_of FROM live_portfolio_daily WHERE portfolio_id=? ORDER BY as_of DESC LIMIT 400)`,
		p.ID, p.ID)
	return p, existed == 0, nil
}

func (s *Service) latestStored(ctx context.Context) (*LivePortfolio, error) {
	var row struct {
		Payload string `db:"payload_json"`
	}
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT payload_json FROM live_portfolio_daily WHERE portfolio_id=?
		  AND COALESCE(json_extract(payload_json, '$.mode'), '') = 'simulation'
		ORDER BY as_of DESC LIMIT 1`, LivePortfolioID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var p LivePortfolio
	if err := json.Unmarshal([]byte(row.Payload), &p); err != nil {
		return nil, fmt.Errorf("decode strategy sim portfolio: %w", err)
	}
	return &p, nil
}

// LatestLivePortfolio 读最近一份模拟日快照；还没有就现算并落库一份。
func (s *Service) LatestLivePortfolio(ctx context.Context) (*LivePortfolio, error) {
	p, err := s.latestStored(ctx)
	if err != nil {
		return nil, err
	}
	if p == nil {
		p, _, err = s.MaterializeLivePortfolio(ctx)
		if err != nil || p == nil {
			return nil, err
		}
	}
	p.Stale, p.StaleDays = s.staleness(ctx, p.AsOf, time.Now())
	return p, nil
}
