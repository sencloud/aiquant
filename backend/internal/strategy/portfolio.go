package strategy

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// LivePortfolioID 是「组合管理」里系统托管的实盘组合 id（客户端用它做 Hive 主键）。
const LivePortfolioID = "live:" + PrimaryID

// LivePortfolio 把主策略的实盘账户翻译成「组合管理」能直接吃的形态：
// 持仓 + 可回放的交易流水。客户端把它落成一个只读组合，十个 tab 都按真实持仓算。
type LivePortfolio struct {
	ID          string `json:"id"`
	StrategyID  string `json:"strategy_id"`
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
	Divergence  bool    `json:"divergence"`

	Holdings     []LiveHolding `json:"holdings"`
	Transactions []LiveTxn     `json:"transactions"`
	// Reconciled=false 表示成交回放出的股数与券商持仓对不上，已补了「对账调整」流水。
	Reconciled bool `json:"reconciled"`

	Target     []TargetItem `json:"target,omitempty"`
	SignalDate string       `json:"signal_date,omitempty"`
	ExecDate   string       `json:"exec_date,omitempty"`
	Curve      []LivePoint  `json:"curve,omitempty"`
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

// LiveTxn 对齐客户端 PortfolioTransaction：type ∈ buy / sell / dividend。
//
// Price 是「含费净价」：买入 = (成交额 + 费用) / 股数，卖出 = (成交额 − 费用) / 股数。
// 这样客户端按加权平均成本回放，得到的持仓均价与券商口径一致。
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

var dividendNote = regexp.MustCompile(`^(.+?)分红\s*([0-9.]+)\s*股\s*[×xX*]\s*([0-9.]+)`)

// BuildLivePortfolio 是纯映射：快照 → 实盘组合。没有实盘段返回 nil。
func BuildLivePortfolio(snap *Snapshot) *LivePortfolio {
	if snap == nil || snap.Live == nil {
		return nil
	}
	l := snap.Live
	industry := map[string]string{}
	for _, d := range snap.Action.TargetDetail {
		if d.Industry != "" {
			industry[d.Code] = d.Industry
		}
	}
	p := &LivePortfolio{
		ID:          LivePortfolioID,
		StrategyID:  snap.StrategyID,
		Name:        "实盘：" + shortName(snap.Meta.Name),
		Currency:    "CNY",
		AsOf:        l.AsOf,
		Inception:   l.Inception,
		Stale:       snap.Stale,
		StaleDays:   snap.StaleDays,
		Capital:     l.Capital,
		Cash:        l.Cash,
		MarketValue: l.MarketValue,
		Total:       l.Total,
		PnL:         l.PnL,
		PnLPct:      l.PnLPct,
		Realized:    l.Realized,
		Fees:        l.Fees,
		Dividends:   l.Dividends,
		Divergence:  l.Divergence,
		Target:      snap.Action.Target,
		SignalDate:  snap.Action.SignalDate,
		ExecDate:    snap.Action.ExecDate,
		Curve:       l.Curve,
		Reconciled:  true,
	}
	p.Description = fmt.Sprintf("系统托管 · 跟随「%s」实盘账户自动同步，只读。数据截至 %s。", snap.Meta.Name, l.AsOf)

	for _, pos := range l.Positions {
		p.Holdings = append(p.Holdings, LiveHolding{
			Symbol: pos.Code, Name: pos.Name, Industry: industry[pos.Code],
			AssetClass: "股票", Shares: float64(pos.Shares), AvgCost: pos.AvgCost,
			Price: pos.Price, MarketValue: pos.MarketValue, Weight: pos.Weight,
			PnL: pos.PnL, PnLPct: pos.PnLPct, InTarget: pos.InTarget,
		})
	}

	// 1) 成交回放（按日期 + 原始顺序）。
	trades := append([]LiveTrade(nil), l.Trades...)
	sort.SliceStable(trades, func(i, j int) bool {
		return trades[i].TradeDate+trades[i].TradeTime < trades[j].TradeDate+trades[j].TradeTime
	})
	names := map[string]string{}
	replayed := map[string]float64{}
	for i, t := range trades {
		if t.Shares <= 0 || t.Code == "" {
			continue
		}
		side := strings.ToLower(strings.TrimSpace(t.Action))
		if side != "buy" && side != "sell" {
			continue
		}
		fees := t.Commission + t.StampTax + t.TransferFee
		amount := t.Amount
		if amount == 0 {
			amount = t.Price * t.Shares
		}
		net := amount + fees
		if side == "sell" {
			net = amount - fees
			replayed[t.Code] -= t.Shares
		} else {
			replayed[t.Code] += t.Shares
		}
		names[t.Name] = t.Code
		p.Transactions = append(p.Transactions, LiveTxn{
			ID:   fmt.Sprintf("%s:t%d:%s:%s", LivePortfolioID, i, t.TradeDate, t.Code),
			Date: t.TradeDate, Type: side, Symbol: t.Code, Name: t.Name,
			Industry: industry[t.Code], AssetClass: "股票",
			Quantity: t.Shares, Price: round4(net / t.Shares), GrossPrice: t.Price,
			Fees: round2(fees), Amount: round2(net), Note: t.Note,
		})
	}

	// 2) 分红：上游只在资金流水里写「中国石化分红 2400股×0.105」，按名称回找代码。
	for i, f := range l.CashFlows {
		if f.Kind != "dividend" {
			continue
		}
		m := dividendNote.FindStringSubmatch(strings.TrimSpace(f.Note))
		if m == nil {
			continue
		}
		code, ok := names[m[1]]
		if !ok {
			continue
		}
		qty, _ := strconv.ParseFloat(m[2], 64)
		dps, _ := strconv.ParseFloat(m[3], 64)
		if qty <= 0 || dps <= 0 {
			continue
		}
		p.Transactions = append(p.Transactions, LiveTxn{
			ID:   fmt.Sprintf("%s:d%d:%s:%s", LivePortfolioID, i, f.FlowDate, code),
			Date: f.FlowDate, Type: "dividend", Symbol: code, Name: m[1],
			Industry: industry[code], AssetClass: "股票",
			Quantity: qty, Price: dps, Amount: round2(f.Amount), Note: f.Note,
		})
	}

	// 3) 对账：回放股数必须等于券商持仓，否则补一条调整流水，保证十个 tab
	//    看到的持仓就是真实持仓（宁可成本口径有出入，也不能股数错）。
	held := map[string]LiveHolding{}
	for _, h := range p.Holdings {
		held[h.Symbol] = h
	}
	codes := map[string]bool{}
	for c := range replayed {
		codes[c] = true
	}
	for c := range held {
		codes[c] = true
	}
	sorted := make([]string, 0, len(codes))
	for c := range codes {
		sorted = append(sorted, c)
	}
	sort.Strings(sorted)
	for _, code := range sorted {
		h := held[code]
		diff := h.Shares - replayed[code]
		if math.Abs(diff) < 1e-6 {
			continue
		}
		p.Reconciled = false
		txn := LiveTxn{
			ID:   fmt.Sprintf("%s:adj:%s:%s", LivePortfolioID, l.AsOf, code),
			Date: l.AsOf, Symbol: code, Name: h.Name, Industry: h.Industry,
			AssetClass: "股票", Note: "对账调整（成交记录与券商持仓不一致）",
		}
		if diff > 0 {
			txn.Type, txn.Quantity, txn.Price = "buy", diff, h.AvgCost
		} else {
			price := h.Price
			if price == 0 {
				price = h.AvgCost
			}
			txn.Type, txn.Quantity, txn.Price = "sell", -diff, price
			if txn.Name == "" {
				for n, c := range names {
					if c == code {
						txn.Name = n
					}
				}
			}
		}
		txn.Amount = round2(txn.Quantity * txn.Price)
		p.Transactions = append(p.Transactions, txn)
	}
	sort.SliceStable(p.Transactions, func(i, j int) bool {
		return p.Transactions[i].Date < p.Transactions[j].Date
	})
	return p
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

// MaterializeLivePortfolio 把最新快照翻成实盘组合，按「数据截至日」每天落一份。
// 同一天重复跑会覆盖（幂等），返回本次的组合与是否新的一天。
func (s *Service) MaterializeLivePortfolio(ctx context.Context) (*LivePortfolio, bool, error) {
	snap, err := s.Latest(ctx)
	if err != nil {
		return nil, false, err
	}
	p := BuildLivePortfolio(snap)
	if p == nil {
		return nil, false, nil
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
		return nil, false, fmt.Errorf("upsert live portfolio: %w", err)
	}
	// 留一年多的日快照就够回答「某天实盘拿着什么」。
	_, _ = s.st.DB.ExecContext(ctx, `
		DELETE FROM live_portfolio_daily WHERE portfolio_id=? AND as_of NOT IN (
			SELECT as_of FROM live_portfolio_daily WHERE portfolio_id=? ORDER BY as_of DESC LIMIT 400)`,
		p.ID, p.ID)
	return p, existed == 0, nil
}

// LatestLivePortfolio 读最近一份日快照；还没有就现算一份（不落库）。
func (s *Service) LatestLivePortfolio(ctx context.Context) (*LivePortfolio, error) {
	var row struct {
		Payload string `db:"payload_json"`
	}
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT payload_json FROM live_portfolio_daily WHERE portfolio_id=?
		ORDER BY as_of DESC LIMIT 1`, LivePortfolioID)
	if errors.Is(err, sql.ErrNoRows) {
		snap, err := s.Latest(ctx)
		if err != nil {
			return nil, err
		}
		return BuildLivePortfolio(snap), nil
	}
	if err != nil {
		return nil, err
	}
	var p LivePortfolio
	if err := json.Unmarshal([]byte(row.Payload), &p); err != nil {
		return nil, fmt.Errorf("decode live portfolio: %w", err)
	}
	p.Stale, p.StaleDays = s.staleness(ctx, p.AsOf, time.Now())
	return &p, nil
}
