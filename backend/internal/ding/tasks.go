package ding

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// Task 是用户保存在服务端的 DING 任务。
type Task struct {
	ID                 int64         `db:"id" json:"-"`
	UUID               string        `db:"uuid" json:"uuid"`
	UserID             int64         `db:"user_id" json:"-"`
	Title              string        `db:"title" json:"title"`
	Prompt             string        `db:"prompt" json:"prompt"`
	PersonaID          string        `db:"persona_id" json:"persona_id"`
	Schedule           string        `db:"schedule" json:"schedule"`
	Enabled            int           `db:"enabled" json:"-"`
	NextRunAt          sql.NullInt64 `db:"next_run_at" json:"-"`
	LastRunAt          sql.NullInt64 `db:"last_run_at" json:"-"`
	CostCreditsPerRun  int64         `db:"cost_credits_per_run" json:"cost_credits_per_run"`
	CreatedAt          int64         `db:"created_at" json:"created_at"`
	UpdatedAt          int64         `db:"updated_at" json:"-"`
}

// MarshalJSON：把 sql.Null* 转成 *T，bool / int 翻译成 json 友好形态。
type taskDTO struct {
	UUID              string  `json:"uuid"`
	Title             string  `json:"title"`
	Prompt            string  `json:"prompt"`
	PersonaID         string  `json:"persona_id"`
	Schedule          string  `json:"schedule"`
	Enabled           bool    `json:"enabled"`
	NextRunAt         *int64  `json:"next_run_at,omitempty"`
	LastRunAt         *int64  `json:"last_run_at,omitempty"`
	CostCreditsPerRun int64   `json:"cost_credits_per_run"`
	CreatedAt         int64   `json:"created_at"`
}

func (t Task) ToDTO() taskDTO {
	dto := taskDTO{
		UUID:              t.UUID,
		Title:             t.Title,
		Prompt:            t.Prompt,
		PersonaID:         t.PersonaID,
		Schedule:          t.Schedule,
		Enabled:           t.Enabled != 0,
		CostCreditsPerRun: t.CostCreditsPerRun,
		CreatedAt:         t.CreatedAt,
	}
	if t.NextRunAt.Valid {
		v := t.NextRunAt.Int64
		dto.NextRunAt = &v
	}
	if t.LastRunAt.Valid {
		v := t.LastRunAt.Int64
		dto.LastRunAt = &v
	}
	return dto
}

type TaskRepo struct {
	st *store.Store
}

func NewTaskRepo(st *store.Store) *TaskRepo { return &TaskRepo{st: st} }

type CreateTaskInput struct {
	UserID            int64
	Title             string
	Prompt            string
	PersonaID         string
	Schedule          string
	Enabled           bool
	CostCreditsPerRun int64
}

func (r *TaskRepo) Create(ctx context.Context, in CreateTaskInput) (*Task, error) {
	now := time.Now().UnixMilli()
	uuid := platform.NewUUID()
	enabled := 0
	if in.Enabled {
		enabled = 1
	}

	var nextAt sql.NullInt64
	if in.Enabled {
		t, err := NextFireTime(in.Schedule, time.Now())
		if err != nil {
			return nil, err
		}
		nextAt = sql.NullInt64{Int64: t.UnixMilli(), Valid: true}
	}

	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO ding_tasks(uuid, user_id, title, prompt, persona_id, schedule,
		                       enabled, next_run_at, cost_credits_per_run, created_at, updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
		uuid, in.UserID, in.Title, in.Prompt, in.PersonaID, in.Schedule,
		enabled, nullInt64(nextAt), in.CostCreditsPerRun, now, now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return r.findByID(ctx, id)
}

type UpdateTaskInput struct {
	Title    *string
	Prompt   *string
	Schedule *string
	Persona  *string
	Enabled  *bool
}

func (r *TaskRepo) Update(ctx context.Context, userID int64, uuid string, in UpdateTaskInput) (*Task, error) {
	t, err := r.FindByUUID(ctx, userID, uuid)
	if err != nil {
		return nil, err
	}
	if t == nil {
		return nil, sql.ErrNoRows
	}
	if in.Title != nil {
		t.Title = *in.Title
	}
	if in.Prompt != nil {
		t.Prompt = *in.Prompt
	}
	if in.Persona != nil {
		t.PersonaID = *in.Persona
	}
	if in.Schedule != nil {
		if err := ValidateSchedule(*in.Schedule); err != nil {
			return nil, err
		}
		t.Schedule = *in.Schedule
	}
	if in.Enabled != nil {
		if *in.Enabled {
			t.Enabled = 1
		} else {
			t.Enabled = 0
		}
	}
	// schedule / enabled 任一变化都重算 next_run_at
	if in.Schedule != nil || in.Enabled != nil {
		if t.Enabled != 0 {
			next, err := NextFireTime(t.Schedule, time.Now())
			if err != nil {
				return nil, err
			}
			t.NextRunAt = sql.NullInt64{Int64: next.UnixMilli(), Valid: true}
		} else {
			t.NextRunAt = sql.NullInt64{}
		}
	}
	t.UpdatedAt = time.Now().UnixMilli()
	if _, err := r.st.DB.ExecContext(ctx, `
		UPDATE ding_tasks SET title=?, prompt=?, persona_id=?, schedule=?,
		       enabled=?, next_run_at=?, updated_at=? WHERE id=?`,
		t.Title, t.Prompt, t.PersonaID, t.Schedule,
		t.Enabled, nullInt64(t.NextRunAt), t.UpdatedAt, t.ID,
	); err != nil {
		return nil, err
	}
	return t, nil
}

func (r *TaskRepo) Delete(ctx context.Context, userID int64, uuid string) error {
	_, err := r.st.DB.ExecContext(ctx,
		"DELETE FROM ding_tasks WHERE uuid=? AND user_id=?", uuid, userID)
	return err
}

func (r *TaskRepo) FindByUUID(ctx context.Context, userID int64, uuid string) (*Task, error) {
	var t Task
	err := r.st.DB.GetContext(ctx, &t,
		"SELECT * FROM ding_tasks WHERE uuid=? AND user_id=?", uuid, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *TaskRepo) findByID(ctx context.Context, id int64) (*Task, error) {
	var t Task
	err := r.st.DB.GetContext(ctx, &t, "SELECT * FROM ding_tasks WHERE id=?", id)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *TaskRepo) ListByUser(ctx context.Context, userID int64) ([]Task, error) {
	rows := []Task{}
	err := r.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM ding_tasks WHERE user_id=? ORDER BY created_at ASC", userID)
	return rows, err
}

// MarkRan 在客户端上报本次执行结果后调用：更新 last_run_at + 重算 next_run_at。
func (r *TaskRepo) MarkRan(ctx context.Context, t *Task, ranAt time.Time) error {
	t.LastRunAt = sql.NullInt64{Int64: ranAt.UnixMilli(), Valid: true}
	if t.Enabled != 0 {
		next, err := NextFireTime(t.Schedule, ranAt)
		if err == nil {
			t.NextRunAt = sql.NullInt64{Int64: next.UnixMilli(), Valid: true}
		}
	}
	t.UpdatedAt = time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx,
		"UPDATE ding_tasks SET last_run_at=?, next_run_at=?, updated_at=? WHERE id=?",
		t.LastRunAt.Int64, nullInt64(t.NextRunAt), t.UpdatedAt, t.ID,
	)
	return err
}

func nullInt64(n sql.NullInt64) any {
	if n.Valid {
		return n.Int64
	}
	return nil
}
