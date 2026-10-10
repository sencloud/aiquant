package falsification

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/billing"
)

// 任务状态。
const (
	RunQueued      = "queued"
	RunRunning     = "running"
	RunDone        = "done"
	RunFailed      = "failed"
	RunUnsupported = "unsupported"
)

// RunRefType 是跑证伪扣费 / 退款流水的 ref_type（ref_id = run uuid）。
const RunRefType = "falsification_run"

// Freqs 是可选周期；1d 按日线计价，其余按分钟线计价。
var Freqs = []string{"1d", "60min", "30min", "15min", "5min"}

var (
	ErrInvalidRunInput = errors.New("invalid falsification run input")
	ErrRunNotFound     = errors.New("falsification run not found")
)

var symbolRe = regexp.MustCompile(`^[A-Za-z0-9]{1,12}\.[A-Za-z]{2,4}$`)

// Run 是一次「跑一次证伪」任务（对客户端的形态）。
type Run struct {
	ID        string         `json:"id"`
	Strategy  string         `json:"strategy"`
	Symbol    string         `json:"symbol"`
	Freq      string         `json:"freq"`
	Credits   int64          `json:"credits"`
	Status    string         `json:"status"`
	Charged   bool           `json:"charged"`
	Refunded  bool           `json:"refunded"`
	Result    map[string]any `json:"result,omitempty"`
	Error     string         `json:"error,omitempty"`
	Message   string         `json:"message,omitempty"`
	CreatedAt int64          `json:"created_at"`
	UpdatedAt int64          `json:"updated_at"`
}

type runRow struct {
	ID            int64          `db:"id"`
	UUID          string         `db:"uuid"`
	UserID        int64          `db:"user_id"`
	Strategy      string         `db:"strategy"`
	Symbol        string         `db:"symbol"`
	Freq          string         `db:"freq"`
	Credits       int64          `db:"credits"`
	Status        string         `db:"status"`
	Charged       bool           `db:"charged"`
	Refunded      bool           `db:"refunded"`
	UpstreamJobID sql.NullString `db:"upstream_job_id"`
	ResultJSON    sql.NullString `db:"result_json"`
	Error         sql.NullString `db:"error"`
	CreatedAt     int64          `db:"created_at"`
	UpdatedAt     int64          `db:"updated_at"`
}

func (r runRow) toRun() *Run {
	out := &Run{
		ID: r.UUID, Strategy: r.Strategy, Symbol: r.Symbol, Freq: r.Freq,
		Credits: r.Credits, Status: r.Status, Charged: r.Charged, Refunded: r.Refunded,
		Error: r.Error.String, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt,
	}
	if r.ResultJSON.Valid && r.ResultJSON.String != "" {
		var m map[string]any
		if json.Unmarshal([]byte(r.ResultJSON.String), &m) == nil {
			stripKey(m, "report_url")
			out.Result = m
		}
	}
	if r.Status == RunUnsupported {
		out.Message = UnsupportedMessage
	}
	return out
}

// UnsupportedMessage 上游没有任务接口时给用户的说明。
const UnsupportedMessage = "「跑一次证伪」的计算队列还在接入，这次没有扣喜点。我们已记下你的需求，开放后优先处理。"

// StrategyOption 是可选策略。
type StrategyOption struct {
	Key    string `json:"key"`
	Name   string `json:"name"`
	Family string `json:"family"`
}

// RunOptions 下单页需要的选项与价格。
type RunOptions struct {
	Available  bool             `json:"available"`
	Strategies []StrategyOption `json:"strategies"`
	Symbols    []string         `json:"symbols"`
	Freqs      []string         `json:"freqs"`
	Prices     Prices           `json:"prices"`
}

// Options 从当前档案里汇总可选策略与品种（已过滤非商用许可）。
func (s *Service) Options(ctx context.Context) RunOptions {
	p, _ := s.Current(ctx)
	seenK := map[string]bool{}
	seenS := map[string]bool{}
	out := RunOptions{Available: s.runner.Available(), Freqs: Freqs, Prices: s.prices,
		Strategies: []StrategyOption{}, Symbols: []string{}}
	for _, e := range Archive(p) {
		if str(e["verdict"]) == VerdictFinding {
			continue
		}
		if k := StrategyKey(e); k != "" && !seenK[k] {
			seenK[k] = true
			out.Strategies = append(out.Strategies, StrategyOption{
				Key: k, Name: str(e["strategy"]), Family: str(e["family"]),
			})
		}
		if sym := str(e["symbol"]); sym != "" && !seenS[sym] {
			seenS[sym] = true
			out.Symbols = append(out.Symbols, sym)
		}
	}
	if scales, ok := p["cost_scales"].([]any); ok {
		for _, r := range scales {
			if m, ok := r.(map[string]any); ok {
				if sym := str(m["symbol"]); sym != "" && !seenS[sym] {
					seenS[sym] = true
					out.Symbols = append(out.Symbols, sym)
				}
			}
		}
	}
	sort.Strings(out.Symbols)
	return out
}

// PriceFor 按周期计价：日线 FalsifyDaily，分钟线 FalsifyMinute。
func (s *Service) PriceFor(freq string) int64 {
	if freq == "1d" {
		return s.prices.FalsifyDaily
	}
	return s.prices.FalsifyMinute
}

// CreateRun 下单。
//
//   - 上游不可用（StubRunner）：登记为 unsupported，不扣费；
//   - 上游可用：同一事务里登记 queued + 扣 consume_falsify（余额不足整体回滚），
//     再提交上游；提交失败标 failed 并退款 refund_falsify。
func (s *Service) CreateRun(ctx context.Context, userID int64, strategy, symbol, freq string) (*Run, error) {
	strategy = strings.TrimSpace(strategy)
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	freq = strings.TrimSpace(freq)
	if !validFreq(freq) || !symbolRe.MatchString(symbol) || strategy == "" {
		return nil, ErrInvalidRunInput
	}
	opts := s.Options(ctx)
	known := false
	for _, o := range opts.Strategies {
		if o.Key == strategy {
			known = true
			break
		}
	}
	if !known {
		return nil, ErrInvalidRunInput
	}

	price := s.PriceFor(freq)
	now := time.Now().UnixMilli()
	row := runRow{
		UUID: newUUID(), UserID: userID, Strategy: strategy, Symbol: symbol, Freq: freq,
		Credits: price, CreatedAt: now, UpdatedAt: now,
	}

	if !s.runner.Available() {
		row.Status = RunUnsupported
		if err := s.insertRun(ctx, nil, &row); err != nil {
			return nil, err
		}
		return row.toRun(), nil
	}

	row.Status = RunQueued
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if price > 0 {
			if _, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{
				UserID: userID, Delta: -price,
				Reason: billing.ReasonConsumeFalsify, RefType: RunRefType, RefID: row.UUID,
				Remark: "跑一次证伪：" + strategy + " " + symbol + " " + freq,
			}); err != nil {
				return err
			}
			row.Charged = true
		}
		return s.insertRun(ctx, tx, &row)
	})
	if err != nil {
		return nil, err
	}

	jobID, err := s.runner.Submit(ctx, RunRequest{RunID: row.UUID, Strategy: strategy, Symbol: symbol, Freq: freq})
	if err != nil {
		s.logger.Warn().Err(err).Str("run", row.UUID).Msg("falsification: submit failed, refund")
		return s.failAndRefund(ctx, &row, "提交计算任务失败，喜点已退回")
	}
	row.UpstreamJobID = sql.NullString{String: jobID, Valid: true}
	row.UpdatedAt = time.Now().UnixMilli()
	if _, err := s.st.DB.ExecContext(ctx,
		"UPDATE falsification_runs SET upstream_job_id=?, updated_at=? WHERE id=?",
		jobID, row.UpdatedAt, row.ID); err != nil {
		return nil, err
	}
	return row.toRun(), nil
}

// GetRun 读任务状态；未结束的任务顺带向上游刷新一次。
func (s *Service) GetRun(ctx context.Context, userID int64, runID string) (*Run, error) {
	var row runRow
	err := s.st.DB.GetContext(ctx, &row,
		"SELECT * FROM falsification_runs WHERE uuid=? AND user_id=?", runID, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrRunNotFound
	}
	if err != nil {
		return nil, err
	}
	if (row.Status == RunQueued || row.Status == RunRunning) && row.UpstreamJobID.Valid && s.runner.Available() {
		st, err := s.runner.Status(ctx, row.UpstreamJobID.String)
		if err != nil {
			s.logger.Warn().Err(err).Str("run", row.UUID).Msg("falsification: poll failed")
			return row.toRun(), nil
		}
		switch st.Status {
		case RunDone:
			stripKey(st.Result, "report_url")
			b, _ := json.Marshal(st.Result)
			row.Status, row.ResultJSON = RunDone, sql.NullString{String: string(b), Valid: true}
			row.UpdatedAt = time.Now().UnixMilli()
			_, err = s.st.DB.ExecContext(ctx,
				"UPDATE falsification_runs SET status=?, result_json=?, updated_at=? WHERE id=?",
				row.Status, row.ResultJSON, row.UpdatedAt, row.ID)
			if err != nil {
				return nil, err
			}
		case RunFailed:
			msg := st.Error
			if msg == "" {
				msg = "计算失败，喜点已退回"
			}
			return s.failAndRefund(ctx, &row, msg)
		case RunQueued, RunRunning:
			if st.Status != row.Status {
				row.Status = st.Status
				row.UpdatedAt = time.Now().UnixMilli()
				_, _ = s.st.DB.ExecContext(ctx,
					"UPDATE falsification_runs SET status=?, updated_at=? WHERE id=?",
					row.Status, row.UpdatedAt, row.ID)
			}
		}
	}
	return row.toRun(), nil
}

// ListRuns 最近 20 个任务。
func (s *Service) ListRuns(ctx context.Context, userID int64) ([]*Run, error) {
	rows := []runRow{}
	if err := s.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM falsification_runs WHERE user_id=?
		ORDER BY created_at DESC, id DESC LIMIT 20`, userID); err != nil {
		return nil, err
	}
	out := make([]*Run, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.toRun())
	}
	return out, nil
}

// failAndRefund 标记失败并退款（幂等：refund_falsify + run uuid）。
func (s *Service) failAndRefund(ctx context.Context, row *runRow, msg string) (*Run, error) {
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		refunded := row.Refunded
		if row.Charged && !row.Refunded && row.Credits > 0 {
			_, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{
				UserID: row.UserID, Delta: row.Credits,
				Reason: billing.ReasonRefundFalsify, RefType: RunRefType, RefID: row.UUID,
				Remark: "证伪任务失败退款",
			})
			if err != nil && !errors.Is(err, billing.ErrLedgerDuplicate) {
				return err
			}
			refunded = true
		}
		row.Status, row.Refunded = RunFailed, refunded
		row.Error = sql.NullString{String: msg, Valid: true}
		row.UpdatedAt = time.Now().UnixMilli()
		_, err := tx.ExecContext(ctx,
			"UPDATE falsification_runs SET status=?, refunded=?, error=?, updated_at=? WHERE id=?",
			row.Status, row.Refunded, msg, row.UpdatedAt, row.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return row.toRun(), nil
}

func (s *Service) insertRun(ctx context.Context, tx *sqlx.Tx, row *runRow) error {
	q := `INSERT INTO falsification_runs(uuid, user_id, strategy, symbol, freq, credits, status, charged, refunded, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	args := []any{row.UUID, row.UserID, row.Strategy, row.Symbol, row.Freq, row.Credits,
		row.Status, row.Charged, row.Refunded, row.CreatedAt, row.UpdatedAt}
	var (
		res sql.Result
		err error
	)
	if tx != nil {
		res, err = tx.ExecContext(ctx, q, args...)
	} else {
		res, err = s.st.DB.ExecContext(ctx, q, args...)
	}
	if err != nil {
		return err
	}
	row.ID, _ = res.LastInsertId()
	return nil
}

func validFreq(f string) bool {
	for _, x := range Freqs {
		if x == f {
			return true
		}
	}
	return false
}

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
