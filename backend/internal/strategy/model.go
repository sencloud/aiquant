// Package strategy 把「主策略」的外部数据源抓取、归一化后提供给 App。
//
// 数据源是 x.singzquant.com 上的量化看板接口（/api/dashboard 与 /api/live），
// 它们由本机的 Python 管线（tradingview_ctp/deploy/publish.py）重算并上传。
// 这层只做三件事：抓、归一化、判断「数据截至哪天 / 是否已经过期」。
//
// 为什么要归一化：外部接口是那套 Python 工程的内部结构，改一处就可能变；
// App 与这里约定的结构才是稳定契约。
package strategy

// PrimaryID 是当前唯一在跑的主策略。
const PrimaryID = "sse50_9f_top5"

// CatalogEntry 是策略目录项（P3 的多策略位复用同一份定义）。
type CatalogEntry struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Subtitle string `json:"subtitle"`
	Live     bool   `json:"live"` // 是否已有在跑的数据
}

// Catalog 返回全部已登记策略，第一个是主策略。
func Catalog() []CatalogEntry {
	return []CatalogEntry{
		{
			ID:       PrimaryID,
			Name:     "上证50 九因子选股",
			Subtitle: "上证50 成分内按估值 / 现金流质量 / 低风险九因子打分，取前 5 只，月度调仓",
			Live:     true,
		},
		{
			ID:       "etf_rotation",
			Name:     "ETF 组合轮动",
			Subtitle: "宽基 ETF 动量轮动（引擎已内置，等待接入实盘口径）",
			Live:     false,
		},
		{
			ID:       "commodity_trend",
			Name:     "商品期货趋势",
			Subtitle: "主要工业品与农产品趋势跟踪（研究中）",
			Live:     false,
		},
	}
}

// Snapshot 是给客户端的一份完整策略快照。
type Snapshot struct {
	StrategyID string `json:"strategy_id"`
	Meta       Meta   `json:"meta"`

	// DataAsOf 是数据实际算到哪一天；Stale 表示它已经不是最近一个交易日了。
	// 调仓指令过期就可能让人按旧名单下单，所以这两个字段必须在 UI 上露出来。
	DataAsOf  string `json:"data_as_of"`
	SyncedAt  int64  `json:"synced_at"`
	Stale     bool   `json:"stale"`
	StaleDays int    `json:"stale_days"` // 落后了几个交易日

	Action     Action       `json:"action"`
	Live       *Live        `json:"live,omitempty"`
	Metrics    Metrics      `json:"metrics"`
	Benchmarks []Benchmark  `json:"benchmarks,omitempty"`
	Yearly     []YearRet    `json:"yearly,omitempty"`
	Factors    []Factor     `json:"factors,omitempty"`
	Universes  []Universe   `json:"universes,omitempty"`
	Curve      []CurvePoint `json:"curve,omitempty"`

	// BacktestTrades 是策略回测引擎的调仓成交（上游 /api/dashboard 的 trades，
	// 最近 N 笔）。它代表「策略结论」：每期剔除谁、买入谁；与人工实盘无关。
	BacktestTrades []BacktestTrade `json:"backtest_trades,omitempty"`
}

// BacktestTrade 是回测引擎的一笔调仓成交。Date 是执行日（信号次一交易日）。
type BacktestTrade struct {
	Date   string   `json:"date"`
	Action string   `json:"action"` // buy / sell
	Code   string   `json:"code"`
	Name   string   `json:"name"`
	Shares float64  `json:"shares"`
	Price  float64  `json:"price"`
	Amount float64  `json:"amount"`
	Fee    float64  `json:"fee"`
	PnL    *float64 `json:"pnl,omitempty"`
}

// Meta 是策略的自我介绍（口径说明，长期稳定）。
type Meta struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Subtitle  string   `json:"subtitle"`
	Universe  string   `json:"universe"`
	TopN      int      `json:"topn"`
	Exclude   []string `json:"exclude"`
	Rebalance string   `json:"rebalance"`
	Since     string   `json:"since"`
	Capital   float64  `json:"capital"`
	Summary   string   `json:"summary"`
	// Disclosure 是必须跟着一起展示的口径与风险说明——可信度就来自这里。
	Disclosure string `json:"disclosure"`
}

// Action 是「要不要动手」卡片：本期信号、执行日、目标名单。
type Action struct {
	SignalDate string       `json:"signal_date"`
	ExecDate   string       `json:"exec_date"`
	Changed    bool         `json:"changed"`
	Note       string       `json:"note"`
	Target     []TargetItem `json:"target"`
	PrevTarget []TargetItem `json:"prev_target"`
	// Orders 是逐笔下单清单；上游还没提供时为空，客户端降级展示目标名单。
	Orders []Order `json:"orders,omitempty"`
	// TargetDetail 带因子分与 z 值，供「为什么选它」与 AI 追问使用。
	TargetDetail []TargetDetail `json:"target_detail,omitempty"`
}

type TargetItem struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

type TargetDetail struct {
	Code     string             `json:"code"`
	Name     string             `json:"name"`
	Industry string             `json:"industry,omitempty"`
	Price    float64            `json:"price,omitempty"`
	Score    float64            `json:"score,omitempty"`
	Z        map[string]float64 `json:"z,omitempty"`
}

type Order struct {
	Side   string  `json:"side"` // buy / sell
	Code   string  `json:"code"`
	Name   string  `json:"name"`
	Shares int     `json:"shares"`
	Price  float64 `json:"price"`
	Amount float64 `json:"amount"`
	Note   string  `json:"note,omitempty"`
}

// Live 是真金白银在跑的那笔实盘账户。
type Live struct {
	AsOf        string     `json:"as_of"`
	Inception   string     `json:"inception"`
	Capital     float64    `json:"capital"`
	Cash        float64    `json:"cash"`
	MarketValue float64    `json:"market_value"`
	Total       float64    `json:"total"`
	PnL         float64    `json:"pnl"`
	PnLPct      float64    `json:"pnl_pct"`
	Realized    float64    `json:"realized"`
	Fees        float64    `json:"fees"`
	Dividends   float64    `json:"dividends"`
	Positions   []Position `json:"positions"`
	Curve       []LivePoint `json:"curve,omitempty"`
	// Divergence 表示实盘持仓与策略目标不一致（人工调过仓），必须如实提示，
	// 否则「跟着策略走」这句话就是假的。
	Divergence bool `json:"divergence"`
	// Trades / CashFlows 是实盘逐笔成交与资金流水（本金、分红），
	// 用于在「组合管理」里还原成交易记录。旧快照里没有这两段。
	Trades    []LiveTrade `json:"trades,omitempty"`
	CashFlows []CashFlow  `json:"cash_flows,omitempty"`
}

// LiveTrade 是实盘的一笔成交（上游 /api/live 的 trades）。
type LiveTrade struct {
	TradeDate   string  `json:"trade_date"`
	TradeTime   string  `json:"trade_time,omitempty"`
	Action      string  `json:"action"` // buy / sell
	Code        string  `json:"code"`
	Name        string  `json:"name"`
	Shares      float64 `json:"shares"`
	Price       float64 `json:"price"`
	Amount      float64 `json:"amount"`
	Commission  float64 `json:"commission"`
	StampTax    float64 `json:"stamp_tax"`
	TransferFee float64 `json:"transfer_fee"`
	Note        string  `json:"note,omitempty"`
}

// CashFlow 是实盘资金流水：principal 本金 / dividend 分红 / 其它。
type CashFlow struct {
	FlowDate string  `json:"flow_date"`
	Kind     string  `json:"kind"`
	Amount   float64 `json:"amount"`
	Note     string  `json:"note,omitempty"`
}

// LivePoint 是实盘净值曲线上的一个点。
type LivePoint struct {
	Date  string  `json:"date"`
	Total float64 `json:"total"`
}

type Position struct {
	Code        string  `json:"code"`
	Name        string  `json:"name"`
	Shares      int     `json:"shares"`
	AvgCost     float64 `json:"avg_cost"`
	Price       float64 `json:"price"`
	MarketValue float64 `json:"market_value"`
	Cost        float64 `json:"cost"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
	Weight      float64 `json:"weight,omitempty"`
	InTarget    bool    `json:"in_target"`
}

// Metrics 是回测绩效（与实盘同一口径的策略成绩）。
type Metrics struct {
	Capital     float64 `json:"capital"`
	Equity      float64 `json:"equity"`
	PnL         float64 `json:"pnl"`
	PnLPct      float64 `json:"pnl_pct"`
	CAGR        float64 `json:"cagr"`
	Sharpe      float64 `json:"sharpe"`
	MaxDrawdown float64 `json:"max_drawdown"`
	MonthWin    float64 `json:"month_win"`
	Trades      int     `json:"trades"`
	Fees        float64 `json:"fees"`
}

// Benchmark 是对照组：指数本身、以及等权持有同一批成分股。
// 没有对照的收益率没法判断策略有没有超额。
type Benchmark struct {
	Name    string  `json:"name"`
	Total   float64 `json:"total_return"`
	CAGR    float64 `json:"cagr"`
	Comment string  `json:"comment,omitempty"`
}

type YearRet struct {
	Year int     `json:"year"`
	Ret  float64 `json:"ret"`
}

// Factor 是单因子检验结果：样本内 IC、t 值、样本外 IC、胜率。
// 带上中文名与说明，客户端不必再维护一份因子字典。
type Factor struct {
	Factor string  `json:"factor"`
	Name   string  `json:"name"`
	Group  string  `json:"group"`
	Desc   string  `json:"desc"`
	IC     float64 `json:"ic"`
	T      float64 `json:"t"`
	OOS    float64 `json:"oos"`
	Win    float64 `json:"win"`
}

type Universe struct {
	Name   string  `json:"name"`
	CAGR   float64 `json:"cagr"`
	Sharpe float64 `json:"sharpe"`
	DD     float64 `json:"dd"`
}

// CurvePoint 是净值曲线上的一个点（已降采样，够画图即可）。
type CurvePoint struct {
	Date   string  `json:"date"`
	Equity float64 `json:"equity"`
	Bench  float64 `json:"bench"`
}
