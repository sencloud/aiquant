package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

// Service 是 live 模块对外的 facade，给 HTTP handler 用。
//
// 负责把多表组合查询包装成"客户端友好"的视图 DTO。
type Service struct {
	sessions *SessionRepo
	reports  *ReportRepo
	watch    *WatchlistRepo
}

func NewService(s *SessionRepo, r *ReportRepo, w *WatchlistRepo) *Service {
	return &Service{sessions: s, reports: r, watch: w}
}

// ── DTO ────────────────────────────────────────────────────────────────

// SessionListItem 是 GET /v1/live/sessions 的列表项。
type SessionListItem struct {
	UUID            string         `json:"uuid"`
	ScheduledAt     int64          `json:"scheduled_at"`
	Phase           string         `json:"phase"`
	Status          string         `json:"status"`
	StartedAt       *int64         `json:"started_at,omitempty"`
	FinishedAt      *int64         `json:"finished_at,omitempty"`
	SelectionReason string         `json:"selection_reason,omitempty"`
	PickedSymbols   []PickedSymbol `json:"picked_symbols"`
	ReportCount     int            `json:"report_count"`
}

// PickedSymbol 是 live_sessions.picked_symbols JSON 中的一条。
type PickedSymbol struct {
	Symbol string `json:"symbol"`
	Name   string `json:"name"`
	Source string `json:"source"`
}

// SessionDetail 是 GET /v1/live/sessions/{uuid} 的返回。
type SessionDetail struct {
	SessionListItem
	Reports []ReportBrief `json:"reports"`
}

// ReportBrief 是单只票 × 单分析师的概览（用于列表，不含 html_body）。
type ReportBrief struct {
	ID           int64    `json:"id"`
	Symbol       string   `json:"symbol"`
	SymbolName   string   `json:"symbol_name"`
	PersonaID    string   `json:"persona_id"`
	PersonaName  string   `json:"persona_name"`
	View         string   `json:"view,omitempty"`
	Rating       string   `json:"rating,omitempty"`
	TargetPrice  *float64 `json:"target_price,omitempty"`
	StopLoss     *float64 `json:"stop_loss,omitempty"`
	TakeProfit   *float64 `json:"take_profit,omitempty"`
	PositionHint string   `json:"position_hint,omitempty"`
	Summary      string   `json:"summary"`
	CreatedAt    int64    `json:"created_at"`
}

// ReportFull 含 html_body，给 WebView 渲染用。
type ReportFull struct {
	ReportBrief
	HTMLBody string `json:"html_body"`
}

// WatchItem 是关注表对客户端的 DTO。
type WatchItem struct {
	Symbol     string `json:"symbol"`
	SymbolName string `json:"symbol_name"`
	CreatedAt  int64  `json:"created_at"`
}

// ── facade methods ─────────────────────────────────────────────────────

func (s *Service) ListSessions(ctx context.Context, limit int) ([]SessionListItem, error) {
	rows, err := s.sessions.List(ctx, limit)
	if err != nil {
		return nil, err
	}
	out := make([]SessionListItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, toSessionListItem(r, countOfReports(ctx, s.reports, r.ID)))
	}
	return out, nil
}

func (s *Service) GetSessionDetail(ctx context.Context, uuid string) (*SessionDetail, error) {
	sess, err := s.sessions.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if sess == nil {
		return nil, nil
	}
	reps, err := s.reports.ListBySession(ctx, sess.ID)
	if err != nil {
		return nil, err
	}
	briefs := make([]ReportBrief, 0, len(reps))
	for _, r := range reps {
		briefs = append(briefs, toReportBrief(r))
	}
	item := toSessionListItem(*sess, len(briefs))
	return &SessionDetail{SessionListItem: item, Reports: briefs}, nil
}

func (s *Service) GetReport(ctx context.Context, id int64) (*ReportFull, error) {
	r, err := s.reports.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if r == nil {
		return nil, nil
	}
	out := ReportFull{ReportBrief: toReportBrief(*r), HTMLBody: r.HTMLBody}
	return &out, nil
}

func (s *Service) ListReportsBySymbol(ctx context.Context, symbol string, limit int) ([]ReportBrief, error) {
	if strings.TrimSpace(symbol) == "" {
		return nil, errors.New("symbol empty")
	}
	rows, err := s.reports.ListBySymbol(ctx, strings.ToUpper(strings.TrimSpace(symbol)), limit)
	if err != nil {
		return nil, err
	}
	out := make([]ReportBrief, 0, len(rows))
	for _, r := range rows {
		out = append(out, toReportBrief(r))
	}
	return out, nil
}

// ── 关注 ───────────────────────────────────────────────────────────────

func (s *Service) ListWatch(ctx context.Context, userID int64) ([]WatchItem, error) {
	rows, err := s.watch.List(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]WatchItem, 0, len(rows))
	for _, w := range rows {
		out = append(out, WatchItem{
			Symbol:     w.Symbol,
			SymbolName: w.SymbolName,
			CreatedAt:  w.CreatedAt,
		})
	}
	return out, nil
}

func (s *Service) AddWatch(ctx context.Context, userID int64, symbol, name string) error {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return errors.New("symbol required")
	}
	return s.watch.Add(ctx, userID, symbol, strings.TrimSpace(name))
}

func (s *Service) RemoveWatch(ctx context.Context, userID int64, symbol string) error {
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return errors.New("symbol required")
	}
	return s.watch.Remove(ctx, userID, symbol)
}

// ── 辅助：DB row → DTO ────────────────────────────────────────────────

func toSessionListItem(s Session, reportCount int) SessionListItem {
	item := SessionListItem{
		UUID:        s.UUID,
		ScheduledAt: s.ScheduledAt,
		Phase:       s.Phase,
		Status:      s.Status,
		ReportCount: reportCount,
	}
	if s.StartedAt.Valid {
		v := s.StartedAt.Int64
		item.StartedAt = &v
	}
	if s.FinishedAt.Valid {
		v := s.FinishedAt.Int64
		item.FinishedAt = &v
	}
	if s.SelectionReason.Valid {
		item.SelectionReason = s.SelectionReason.String
	}
	if s.PickedSymbols.Valid && s.PickedSymbols.String != "" {
		var picks []PickedSymbol
		if err := json.Unmarshal([]byte(s.PickedSymbols.String), &picks); err == nil {
			item.PickedSymbols = picks
		}
	}
	if item.PickedSymbols == nil {
		item.PickedSymbols = []PickedSymbol{}
	}
	return item
}

func toReportBrief(r Report) ReportBrief {
	b := ReportBrief{
		ID:          r.ID,
		Symbol:      r.Symbol,
		SymbolName:  r.SymbolName,
		PersonaID:   r.PersonaID,
		PersonaName: r.PersonaName,
		Summary:     r.Summary,
		CreatedAt:   r.CreatedAt,
	}
	if r.View.Valid {
		b.View = r.View.String
	}
	if r.Rating.Valid {
		b.Rating = r.Rating.String
	}
	if r.PositionHint.Valid {
		b.PositionHint = r.PositionHint.String
	}
	if r.TargetPrice.Valid {
		v := r.TargetPrice.Float64
		b.TargetPrice = &v
	}
	if r.StopLoss.Valid {
		v := r.StopLoss.Float64
		b.StopLoss = &v
	}
	if r.TakeProfit.Valid {
		v := r.TakeProfit.Float64
		b.TakeProfit = &v
	}
	return b
}

// countOfReports 给列表项填 report_count。出错返回 0，不影响渲染。
func countOfReports(ctx context.Context, r *ReportRepo, sessionID int64) int {
	rows, err := r.ListBySession(ctx, sessionID)
	if err != nil {
		return 0
	}
	return len(rows)
}

// ensure import used
var _ = fmt.Sprintf
