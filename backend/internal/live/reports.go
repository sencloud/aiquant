package live

import (
	"context"
	"database/sql"
	"errors"

	"github.com/sencloud/finme-backend/internal/store"
)

// ReportRepo 负责 live_reports CRUD。
type ReportRepo struct{ st *store.Store }

func NewReportRepo(st *store.Store) *ReportRepo { return &ReportRepo{st: st} }

type CreateReportInput struct {
	SessionID    int64
	Symbol       string
	SymbolName   string
	PersonaID    string
	PersonaName  string
	View         string
	Rating       string
	TargetPrice  *float64
	StopLoss     *float64
	TakeProfit   *float64
	PositionHint string
	Summary      string
	HTMLBody     string
	ToolCalls    int
	DurationMs   int64
}

// Insert 是单条报告落库。UNIQUE(session,symbol,persona) 防重。
func (r *ReportRepo) Insert(ctx context.Context, in CreateReportInput) (int64, error) {
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO live_reports
		  (session_id, symbol, symbol_name, persona_id, persona_name,
		   view, rating, target_price, stop_loss, take_profit, position_hint,
		   summary, html_body, tool_calls, duration_ms, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		in.SessionID, in.Symbol, in.SymbolName, in.PersonaID, in.PersonaName,
		nullStr(in.View), nullStr(in.Rating),
		nullFloat(in.TargetPrice), nullFloat(in.StopLoss), nullFloat(in.TakeProfit),
		nullStr(in.PositionHint),
		in.Summary, in.HTMLBody, in.ToolCalls, in.DurationMs, nowMs(),
	)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// ListBySession 取一场的所有报告（按 symbol 分组用,顺序: symbol asc, persona asc）。
func (r *ReportRepo) ListBySession(ctx context.Context, sessionID int64) ([]Report, error) {
	rows := []Report{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_reports
		WHERE session_id=?
		ORDER BY symbol ASC, persona_id ASC`, sessionID)
	return rows, err
}

// GetByID 取单份完整报告（含 html_body）。
func (r *ReportRepo) GetByID(ctx context.Context, id int64) (*Report, error) {
	var rp Report
	err := r.st.DB.GetContext(ctx, &rp, `
		SELECT * FROM live_reports WHERE id=?`, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &rp, nil
}

// ListBySymbol 客户端「按股票查所有家观点」用：最近 N 份。
func (r *ReportRepo) ListBySymbol(ctx context.Context, symbol string, limit int) ([]Report, error) {
	if limit <= 0 || limit > 50 {
		limit = 12
	}
	rows := []Report{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_reports
		WHERE symbol=?
		ORDER BY created_at DESC LIMIT ?`, symbol, limit)
	return rows, err
}

func nullFloat(p *float64) any {
	if p == nil {
		return nil
	}
	return *p
}
