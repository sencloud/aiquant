package strategy

// 外部看板 /api/dashboard 的响应结构。只声明我们用到的字段。
type dashResp struct {
	Params struct {
		Universe string   `json:"universe"`
		TopN     int      `json:"topn"`
		Exclude  []string `json:"exclude"`
		Capital  float64  `json:"capital"`
		Since    string   `json:"since"`
		Until    string   `json:"until"`
	} `json:"params"`
	KPI struct {
		Capital  float64 `json:"capital"`
		Equity   float64 `json:"equity"`
		PnL      float64 `json:"pnl"`
		PnLPct   float64 `json:"pnl_pct"`
		CAGR     float64 `json:"backtest_cagr"`
		Sharpe   float64 `json:"backtest_sharpe"`
		DD       float64 `json:"backtest_dd"`
		MonthWin float64 `json:"month_win"`
		Fees     float64 `json:"fees"`
		Trades   int     `json:"trades"`
	} `json:"kpi"`
	Equity    [][]any `json:"equity"`
	Benchmark [][]any `json:"benchmark"`
	Yearly    []struct {
		Year int     `json:"year"`
		Ret  float64 `json:"ret"`
	} `json:"yearly"`
	Holdings []struct {
		Code     string             `json:"code"`
		Name     string             `json:"name"`
		Industry string             `json:"industry"`
		Price    float64            `json:"price"`
		Score    float64            `json:"score"`
		Z        map[string]float64 `json:"z"`
	} `json:"holdings"`
	Factors []struct {
		Factor string  `json:"factor"`
		IC     float64 `json:"ic"`
		T      float64 `json:"t"`
		OOS    float64 `json:"oos"`
		Win    float64 `json:"win"`
	} `json:"factors"`
	// factor_meta: 因子key → [中文名, 分类, 方向, 一句话说明]
	FactorMeta map[string][]string `json:"factor_meta"`
	Universes []struct {
		Name   string  `json:"name"`
		Total  float64 `json:"total"`
		CAGR   float64 `json:"cagr"`
		Sharpe float64 `json:"sharpe"`
		DD     float64 `json:"dd"`
	} `json:"universes"`
	Next struct {
		Signal string `json:"signal"`
		Exec   string `json:"exec"`
		Changed bool  `json:"changed"`
		Note   string `json:"note"`
		Target []struct {
			Code string `json:"code"`
			Name string `json:"name"`
		} `json:"target"`
		PrevTarget []struct {
			Code string `json:"code"`
			Name string `json:"name"`
		} `json:"prev_target"`
	} `json:"next"`
}

// livePosition / liveCurvePoint 是 /api/live 里的子结构，单独命名便于测试构造。
type livePosition struct {
	Code        string  `json:"code"`
	Name        string  `json:"name"`
	Shares      float64 `json:"shares"`
	AvgCost     float64 `json:"avg_cost"`
	Price       float64 `json:"price"`
	MarketValue float64 `json:"market_value"`
	Cost        float64 `json:"cost"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
}

type liveCurvePoint struct {
	Date  string  `json:"date"`
	Total float64 `json:"total"`
}

// 外部看板 /api/live 的响应结构。
type liveResp struct {
	AsOf        string  `json:"as_of"`
	Inception   string  `json:"inception"`
	Capital     float64 `json:"capital"`
	Cash        float64 `json:"cash"`
	MarketValue float64 `json:"market_value"`
	Total       float64 `json:"total"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
	Realized    float64 `json:"realized"`
	Fees        float64 `json:"fees"`
	Dividends   float64 `json:"dividends"`
	Positions []livePosition   `json:"positions"`
	Curve     []liveCurvePoint `json:"curve"`
	Trades    []LiveTrade      `json:"trades"`
	CashFlows []CashFlow       `json:"cash_flows"`
}

// normalize 把外部看板数据整理成客户端契约。
func normalize(d *dashResp) *Snapshot {
	entry := Catalog()[0]
	snap := &Snapshot{
		StrategyID: PrimaryID,
		Meta: Meta{
			ID:         PrimaryID,
			Name:       entry.Name,
			Subtitle:   entry.Subtitle,
			Universe:   d.Params.Universe,
			TopN:       d.Params.TopN,
			Exclude:    d.Params.Exclude,
			Rebalance:  "每月最后一个交易日收盘出信号，次一交易日开盘调仓",
			Since:      d.Params.Since,
			Capital:    d.Params.Capital,
			Summary:    strategySummary,
			Disclosure: strategyDisclosure,
		},
		DataAsOf: d.Params.Until,
		Action: Action{
			SignalDate: d.Next.Signal,
			ExecDate:   d.Next.Exec,
			Changed:    d.Next.Changed,
			Note:       d.Next.Note,
		},
		Metrics: Metrics{
			Capital:     d.KPI.Capital,
			Equity:      d.KPI.Equity,
			PnL:         d.KPI.PnL,
			PnLPct:      d.KPI.PnLPct,
			CAGR:        d.KPI.CAGR,
			Sharpe:      d.KPI.Sharpe,
			MaxDrawdown: d.KPI.DD,
			MonthWin:    d.KPI.MonthWin,
			Trades:      d.KPI.Trades,
			Fees:        d.KPI.Fees,
		},
	}
	for _, t := range d.Next.Target {
		snap.Action.Target = append(snap.Action.Target, TargetItem{Code: t.Code, Name: t.Name})
	}
	for _, t := range d.Next.PrevTarget {
		snap.Action.PrevTarget = append(snap.Action.PrevTarget, TargetItem{Code: t.Code, Name: t.Name})
	}
	// 因子明细（z 值 / 得分）外部只对"当前持仓"给出，按代码映射到目标名单上。
	detail := map[string]TargetDetail{}
	for _, h := range d.Holdings {
		detail[h.Code] = TargetDetail{
			Code: h.Code, Name: h.Name, Industry: h.Industry,
			Price: h.Price, Score: h.Score, Z: h.Z,
		}
	}
	for _, t := range snap.Action.Target {
		if det, ok := detail[t.Code]; ok {
			snap.Action.TargetDetail = append(snap.Action.TargetDetail, det)
			continue
		}
		snap.Action.TargetDetail = append(snap.Action.TargetDetail,
			TargetDetail{Code: t.Code, Name: t.Name})
	}
	for _, y := range d.Yearly {
		snap.Yearly = append(snap.Yearly, YearRet{Year: y.Year, Ret: y.Ret})
	}
	for _, f := range d.Factors {
		item := Factor{Factor: f.Factor, IC: f.IC, T: f.T, OOS: f.OOS, Win: f.Win}
		if m := d.FactorMeta[f.Factor]; len(m) >= 4 {
			item.Name, item.Group, item.Desc = m[0], m[1], m[3]
		}
		if item.Name == "" {
			item.Name = f.Factor // 外部没给中文名时至少显示 key，不留空
		}
		snap.Factors = append(snap.Factors, item)
	}
	for _, u := range d.Universes {
		snap.Universes = append(snap.Universes, Universe{
			Name: u.Name, CAGR: u.CAGR, Sharpe: u.Sharpe, DD: u.DD,
		})
	}
	// 基准只放有据可查的那一条：同窗口上证50 指数（不含分红）。
	// 等权持有基准目前只在研究文档里，没进机器可读产物，不臆造数字。
	if n := len(d.Benchmark); n > 0 {
		first, last := toPair(d.Benchmark[0]), toPair(d.Benchmark[n-1])
		if first > 0 {
			total := last/first - 1
			snap.Benchmarks = append(snap.Benchmarks, Benchmark{
				Name:    "上证50 指数（不含分红）",
				Total:   total,
				CAGR:    annualize(total, yearsBetween(d.Params.Since, d.Params.Until)),
				Comment: "同期指数本身的表现；策略要跑赢它才算有超额",
			})
		}
	}
	snap.Curve = downsample(d.Equity, d.Benchmark)
	return snap
}

// normalizeLive 把实盘账户整理成客户端契约，并标出与目标名单的一致性问题。
func normalizeLive(l *liveResp, target []TargetItem) *Live {
	inTarget := map[string]bool{}
	for _, t := range target {
		inTarget[t.Code] = true
	}
	out := &Live{
		AsOf: l.AsOf, Inception: l.Inception, Capital: l.Capital,
		Cash: l.Cash, MarketValue: l.MarketValue, Total: l.Total,
		PnL: l.PnL, PnLPct: l.PnLPct, Realized: l.Realized,
		Fees: l.Fees, Dividends: l.Dividends,
	}
	held := map[string]bool{}
	for _, p := range l.Positions {
		held[p.Code] = true
		weight := 0.0
		if l.Total > 0 {
			weight = p.MarketValue / l.Total
		}
		out.Positions = append(out.Positions, Position{
			Code: p.Code, Name: p.Name, Shares: int(p.Shares),
			AvgCost: p.AvgCost, Price: p.Price, MarketValue: p.MarketValue,
			Cost: p.Cost, PnL: p.PnL, PnLPct: p.PnLPct, Weight: weight,
			InTarget: inTarget[p.Code],
		})
	}
	for _, pt := range l.Curve {
		out.Curve = append(out.Curve, LivePoint{Date: pt.Date, Total: pt.Total})
	}
	// 成交与资金流水原样保留：组合管理里的「实盘组合」用它回放出交易记录。
	out.Trades = l.Trades
	out.CashFlows = l.CashFlows
	// 持仓集合与目标集合不一致（人工调过仓）→ 如实标记，
	// 否则界面上「跟着策略走」这句话就是假的。
	out.Divergence = !sameCodeSet(held, inTarget)
	return out
}

const strategySummary = `在上证50 当期成分股里，用 9 个因子给每只股票打分，取综合分最高的 5 只等权持有：
估值（EP、股息率、BP）、现金流质量（经营现金流/每股收益、负应计）、低风险（特质波动率、beta、换手率、波动率）。
每月最后一个交易日收盘出信号，次一交易日开盘按差额调仓——只做卖出与买入的差额，持仓不动就不交易。`

const strategyDisclosure = `回测与实盘同一口径：含佣金（万 2.5、最低 5 元）、印花税、过户费、滑点 5bp，
现金分红按除权日计入现金；股票池按月取当期成分股，避免只用今天名单造成的幸存者偏差。
历史业绩不代表未来收益，本内容不构成投资建议。`
