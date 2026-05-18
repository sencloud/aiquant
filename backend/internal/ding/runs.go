package ding

import (
	"context"
	"database/sql"
	"time"

	"github.com/sencloud/finme-backend/internal/store"
)

// Run 是一次 DING 任务的执行记录。
//
// 当前阶段（W3 第一阶段）：客户端在本地驱动定时执行，执行完通过 ReportRun
// 上报结果到服务端；服务端把结果落库为 Run + Notification（"邮件"）。
type Run struct {
	ID             int64          `db:"id" json:"-"`
	TaskID         int64          `db:"task_id" json:"-"`
	Status         string         `db:"status" json:"status"`
	NotificationID sql.NullInt64  `db:"notification_id" json:"-"`
	TotalTokens    sql.NullInt64  `db:"total_tokens" json:"total_tokens,omitempty"`
	DurationMs     sql.NullInt64  `db:"duration_ms" json:"duration_ms,omitempty"`
	Error          sql.NullString `db:"error" json:"error,omitempty"`
	StartedAt      int64          `db:"started_at" json:"started_at"`
	FinishedAt     sql.NullInt64  `db:"finished_at" json:"finished_at,omitempty"`
}

const (
	RunStatusRunning         = "running"
	RunStatusSuccess         = "success"
	RunStatusFailed          = "failed"
	RunStatusSkippedNoCredit = "skipped_no_credit"
)

type RunRepo struct {
	st *store.Store
}

func NewRunRepo(st *store.Store) *RunRepo { return &RunRepo{st: st} }

type ReportRunInput struct {
	TaskID         int64
	Status         string
	TotalTokens    int64
	DurationMs     int64
	Error          string
	NotificationID int64
	StartedAt      time.Time
}

// Insert 幂等：同 (task_id, started_at) 已存在时直接返回原记录，避免弱网
// 客户端重试时为同一次执行创建多条 run。依赖 0002 迁移建立的唯一索引。
func (r *RunRepo) Insert(ctx context.Context, in ReportRunInput) (*Run, error) {
	now := time.Now().UnixMilli()
	var notifID sql.NullInt64
	if in.NotificationID > 0 {
		notifID = sql.NullInt64{Int64: in.NotificationID, Valid: true}
	}
	var startedAt int64 = in.StartedAt.UnixMilli()
	if startedAt == 0 {
		startedAt = now
	}
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT OR IGNORE INTO ding_runs(task_id, status, notification_id, total_tokens, duration_ms,
		                                error, started_at, finished_at)
		VALUES(?,?,?,?,?,?,?,?)`,
		in.TaskID, in.Status,
		nilNotif(notifID),
		nilInt64Pos(in.TotalTokens),
		nilInt64Pos(in.DurationMs),
		nilStrIfEmpty(in.Error),
		startedAt, now,
	)
	if err != nil {
		return nil, err
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		// 命中幂等：同 (task_id, started_at) 的旧记录直接返回
		var rec Run
		if err := r.st.DB.GetContext(ctx, &rec,
			"SELECT * FROM ding_runs WHERE task_id=? AND started_at=?",
			in.TaskID, startedAt); err != nil {
			return nil, err
		}
		return &rec, nil
	}
	id, _ := res.LastInsertId()
	var rec Run
	if err := r.st.DB.GetContext(ctx, &rec,
		"SELECT * FROM ding_runs WHERE id=?", id); err != nil {
		return nil, err
	}
	return &rec, nil
}

func nilNotif(v sql.NullInt64) any {
	if v.Valid {
		return v.Int64
	}
	return nil
}

func nilInt64Pos(v int64) any {
	if v <= 0 {
		return nil
	}
	return v
}

func nilStrIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
