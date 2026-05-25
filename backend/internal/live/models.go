// Package live 实现「AI 直播」：每个交易日整点 / 半点一场，
// 由后台 cron 自动从龙虎榜 / 涨幅榜 + 用户关注表选股，
// 然后对每只标的依次让 6 位"具体人名分析师"persona（巴菲特/格雷厄姆/林奇/
// 芒格/达里奥/索罗斯）独立给出结构化 HTML 报告（含买卖评级 + 止盈止损）。
//
// 与 DING 区别：DING 是「用户配置的 prompt 定时跑」，扣费走用户；
// 直播是「系统自动跑、所有用户共享报告」，不扣任何用户喜点。
package live

import (
	"database/sql"
	"time"
)

// 直播场次的生命周期。
const (
	SessionPending = "pending" // 已写入日历，待 runner 抢占
	SessionRunning = "running"
	SessionDone    = "done"
	SessionFailed  = "failed"
)

// 直播场次的市场阶段。
const (
	PhasePre      = "pre"      // 盘前（8:00-9:30）
	PhaseIntraday = "intraday" // 盘中（9:30-15:00）
	PhasePost     = "post"     // 盘后（15:00 之后）
)

// 多空观点。
const (
	ViewBullish = "bullish"
	ViewNeutral = "neutral"
	ViewBearish = "bearish"
)

// Session 是单场直播的数据库行。
type Session struct {
	ID              int64          `db:"id"`
	UUID            string         `db:"uuid"`
	ScheduledAt     int64          `db:"scheduled_at"`
	Phase           string         `db:"phase"`
	Status          string         `db:"status"`
	StartedAt       sql.NullInt64  `db:"started_at"`
	FinishedAt      sql.NullInt64  `db:"finished_at"`
	PickedSymbols   sql.NullString `db:"picked_symbols"` // JSON
	SelectionReason sql.NullString `db:"selection_reason"`
	Error           sql.NullString `db:"error"`
	CreatedAt       int64          `db:"created_at"`
}

// Report 是 (session × symbol × persona) 的报告行。
type Report struct {
	ID            int64           `db:"id"`
	SessionID     int64           `db:"session_id"`
	Symbol        string          `db:"symbol"`
	SymbolName    string          `db:"symbol_name"`
	PersonaID     string          `db:"persona_id"`
	PersonaName   string          `db:"persona_name"`
	View          sql.NullString  `db:"view"`
	Rating        sql.NullString  `db:"rating"`
	TargetPrice   sql.NullFloat64 `db:"target_price"`
	StopLoss      sql.NullFloat64 `db:"stop_loss"`
	TakeProfit    sql.NullFloat64 `db:"take_profit"`
	PositionHint  sql.NullString  `db:"position_hint"`
	Summary       string          `db:"summary"`
	HTMLBody      string          `db:"html_body"`
	ToolCalls     int             `db:"tool_calls"`
	DurationMs    int64           `db:"duration_ms"`
	CreatedAt     int64           `db:"created_at"`
}

// Watch 是单条用户关注。
type Watch struct {
	ID         int64  `db:"id"`
	UserID     int64  `db:"user_id"`
	Symbol     string `db:"symbol"`
	SymbolName string `db:"symbol_name"`
	CreatedAt  int64  `db:"created_at"`
}

// nowMs 统一时间戳工具（业务全用 unix ms）。
func nowMs() int64 { return time.Now().UnixMilli() }
