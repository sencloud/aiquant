// Package predict 实现鹦鹉螺预测市场：奖池瓜分制(parimutuel)下注 + 结算。
//
// 核心规则：
//   - 一个市场(market)有 2+ 个互斥选项(option)，用户用螺壳下注进对应选项池；
//   - close_at 后停止下注；结果判定后一次性结算：
//     可分配奖池 = 全部选项池合计 × (1 - rake_bps/10000)，
//     赢方每注按「本注金额 / 赢方池」比例瓜分，向下取整；
//   - 赢方池为空(无人押中)或市场取消 → 全部退款；
//   - 金融类支持自动结算(resolve_rule + 东财实时行情)，天气类人工录入结果。
package predict

import (
	"database/sql"
	"encoding/json"
)

// 市场状态机：open → closed → settled；open/closed → cancelled。
const (
	StatusOpen      = "open"
	StatusClosed    = "closed"
	StatusSettled   = "settled"
	StatusCancelled = "cancelled"
)

const (
	CategoryWeather = "weather"
	CategoryFinance = "finance"
)

const (
	ResolveAuto   = "auto"
	ResolveManual = "manual"
)

// Market 一个预测市场。
type Market struct {
	ID               int64          `db:"id" json:"id"`
	Category         string         `db:"category" json:"category"`
	Title            string         `db:"title" json:"title"`
	Description      string         `db:"description" json:"description"`
	Status           string         `db:"status" json:"status"`
	CloseAt          int64          `db:"close_at" json:"close_at"`
	ResolveAt        int64          `db:"resolve_at" json:"resolve_at"`
	ResolveKind      string         `db:"resolve_kind" json:"resolve_kind"`
	ResolveRule      string         `db:"resolve_rule" json:"-"`
	ResolvedOptionID sql.NullInt64  `db:"resolved_option_id" json:"-"`
	RakeBps          int64          `db:"rake_bps" json:"rake_bps"`
	CreatedAt        int64          `db:"created_at" json:"created_at"`
	UpdatedAt        int64          `db:"updated_at" json:"-"`
}

// Option 市场的一个互斥结果选项。
type Option struct {
	ID          int64  `db:"id" json:"id"`
	MarketID    int64  `db:"market_id" json:"-"`
	Idx         int    `db:"idx" json:"idx"`
	Label       string `db:"label" json:"label"`
	PoolShells  int64  `db:"pool_shells" json:"pool_shells"`
	BettorCount int64  `db:"bettor_count" json:"bettor_count"`
}

// Bet 一笔下注。
type Bet struct {
	ID        int64         `db:"id" json:"id"`
	MarketID  int64         `db:"market_id" json:"market_id"`
	OptionID  int64         `db:"option_id" json:"option_id"`
	UserID    int64         `db:"user_id" json:"-"`
	Amount    int64         `db:"amount" json:"amount"`
	Payout    int64         `db:"payout" json:"payout"`
	Status    string        `db:"status" json:"status"`
	CreatedAt int64         `db:"created_at" json:"created_at"`
	SettledAt sql.NullInt64 `db:"settled_at" json:"-"`
}

// MarketView 是客户端看到的市场聚合：市场 + 选项 + 总池。
type MarketView struct {
	Market
	Options          []Option `json:"options"`
	TotalPool        int64    `json:"total_pool"`
	ResolvedOptionID int64    `json:"resolved_option_id,omitempty"`
}

// ResolveRule 金融类自动结算规则。
//
// source 决定走 realtime 哪条取数路径：
//   - cn           A股/ETF/指数代码，如 600519.SH / 000300.SH
//   - us           美股代码，如 AAPL
//   - global_index 全球指数别名，如 道琼斯 / 纳斯达克 / 标普500
//   - forex        外汇对，如 USDCNH
//
// 判定：现价 op value 成立 → yes_idx 选项获胜，否则 no_idx 获胜。
type ResolveRule struct {
	Source string  `json:"source"`
	Symbol string  `json:"symbol"`
	Op     string  `json:"op"` // gte / lte / gt / lt
	Value  float64 `json:"value"`
	YesIdx int     `json:"yes_idx"`
	NoIdx  int     `json:"no_idx"`
}

func ParseResolveRule(raw string) (*ResolveRule, error) {
	var r ResolveRule
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		return nil, err
	}
	return &r, nil
}
