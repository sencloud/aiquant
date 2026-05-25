package live

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/google/uuid"

	"github.com/sencloud/finme-backend/internal/store"
)

// SessionRepo 封装 live_sessions 的 CRUD。
type SessionRepo struct{ st *store.Store }

func NewSessionRepo(st *store.Store) *SessionRepo { return &SessionRepo{st: st} }

// SeedIfAbsent 按 scheduled_at 幂等插入一条 pending 场次。
// 同一时刻被多个 daemon 同时插会因 UNIQUE 冲突而忽略，调用方不需关心结果。
func (r *SessionRepo) SeedIfAbsent(ctx context.Context, scheduledAt int64, phase string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT OR IGNORE INTO live_sessions
		  (uuid, scheduled_at, phase, status, created_at)
		VALUES (?, ?, ?, 'pending', ?)`,
		uuid.NewString(), scheduledAt, phase, nowMs())
	return err
}

// AcquireDue 找到一条 due 且 pending 的场次，立刻 CAS 标 running 占位。
// 找不到 → 返回 sql.ErrNoRows，调用方应优雅退出本轮。
func (r *SessionRepo) AcquireDue(ctx context.Context, now int64) (*Session, error) {
	tx, err := r.st.DB.BeginTxx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	var s Session
	if err := tx.GetContext(ctx, &s, `
		SELECT * FROM live_sessions
		WHERE status='pending' AND scheduled_at <= ?
		ORDER BY scheduled_at ASC
		LIMIT 1`, now); err != nil {
		return nil, err
	}
	res, err := tx.ExecContext(ctx, `
		UPDATE live_sessions
		SET status='running', started_at=?
		WHERE id=? AND status='pending'`, now, s.ID)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n != 1 {
		return nil, sql.ErrNoRows
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	s.Status = SessionRunning
	s.StartedAt = sql.NullInt64{Int64: now, Valid: true}
	return &s, nil
}

// MarkPicked 在选股完成后把入选标的 + 选取理由落库。
func (r *SessionRepo) MarkPicked(ctx context.Context, id int64, symbolsJSON, reason string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_sessions
		SET picked_symbols=?, selection_reason=?
		WHERE id=?`, symbolsJSON, reason, id)
	return err
}

// MarkDone 全部 persona 跑完且至少一份成功 → done；否则 failed。
func (r *SessionRepo) MarkDone(ctx context.Context, id int64, ok bool, errMsg string) error {
	status := SessionDone
	if !ok {
		status = SessionFailed
	}
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_sessions
		SET status=?, finished_at=?, error=?
		WHERE id=?`, status, nowMs(), nullStr(errMsg), id)
	return err
}

// List 返回最近 N 场（已完成 / 失败 / 进行中，不含纯 pending 未来场次）。
func (r *SessionRepo) List(ctx context.Context, limit int) ([]Session, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows := []Session{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_sessions
		WHERE status IN ('running','done','failed')
		ORDER BY scheduled_at DESC
		LIMIT ?`, limit)
	return rows, err
}

// GetByUUID 详情接口用：按 uuid 取一场（含 pending 未来场次）。
func (r *SessionRepo) GetByUUID(ctx context.Context, u string) (*Session, error) {
	var s Session
	err := r.st.DB.GetContext(ctx, &s, `
		SELECT * FROM live_sessions WHERE uuid=?`, u)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

// LatestDone 返回最近一场 done 的（用于客户端首屏直接进入）。
func (r *SessionRepo) LatestDone(ctx context.Context) (*Session, error) {
	var s Session
	err := r.st.DB.GetContext(ctx, &s, `
		SELECT * FROM live_sessions
		WHERE status='done'
		ORDER BY scheduled_at DESC LIMIT 1`)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

// PruneOlderThan 删超过 retention 的旧场次（连级删 reports）。
func (r *SessionRepo) PruneOlderThan(ctx context.Context, beforeMs int64) (int64, error) {
	res, err := r.st.DB.ExecContext(ctx, `
		DELETE FROM live_sessions WHERE scheduled_at < ?`, beforeMs)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return n, nil
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// ensure import used in some builds
var _ = fmt.Sprintf
