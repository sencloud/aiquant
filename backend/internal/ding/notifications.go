package ding

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// Notification 是通知收件箱里的一条消息（DING 任务执行结果 / 系统消息）。
type Notification struct {
	ID            int64          `db:"id" json:"-"`
	UUID          string         `db:"uuid" json:"uuid"`
	UserID        int64          `db:"user_id" json:"-"`
	Topic         string         `db:"topic" json:"topic"`
	RefType       sql.NullString `db:"ref_type" json:"-"`
	RefID         sql.NullString `db:"ref_id" json:"-"`
	Title         string         `db:"title" json:"title"`
	BodyBrief     string         `db:"body_brief" json:"body_brief"`
	PayloadJSON   sql.NullString `db:"payload_json" json:"-"`
	PushStatus    string         `db:"push_status" json:"push_status"`
	PushAttempts  int            `db:"push_attempts" json:"-"`
	PushedAt      sql.NullInt64  `db:"pushed_at" json:"-"`
	ReadAt        sql.NullInt64  `db:"read_at" json:"-"`
	CreatedAt     int64          `db:"created_at" json:"created_at"`
}

type notificationDTO struct {
	UUID        string  `json:"uuid"`
	Topic       string  `json:"topic"`
	RefType     string  `json:"ref_type,omitempty"`
	RefID       string  `json:"ref_id,omitempty"`
	Title       string  `json:"title"`
	BodyBrief   string  `json:"body_brief"`
	Payload     string  `json:"payload,omitempty"`
	Read        bool    `json:"read"`
	PushStatus  string  `json:"push_status"`
	ReadAt      *int64  `json:"read_at,omitempty"`
	CreatedAt   int64   `json:"created_at"`
}

func (n Notification) ToDTO() notificationDTO {
	dto := notificationDTO{
		UUID:       n.UUID,
		Topic:      n.Topic,
		RefType:    n.RefType.String,
		RefID:      n.RefID.String,
		Title:      n.Title,
		BodyBrief:  n.BodyBrief,
		Payload:    n.PayloadJSON.String,
		Read:       n.ReadAt.Valid,
		PushStatus: n.PushStatus,
		CreatedAt:  n.CreatedAt,
	}
	if n.ReadAt.Valid {
		v := n.ReadAt.Int64
		dto.ReadAt = &v
	}
	return dto
}

type NotificationRepo struct {
	st *store.Store
}

func NewNotificationRepo(st *store.Store) *NotificationRepo {
	return &NotificationRepo{st: st}
}

type CreateNotifInput struct {
	UserID    int64
	Topic     string
	RefType   string
	RefID     string
	Title     string
	BodyBrief string
	Payload   string // 可放完整 markdown / JSON
}

func (r *NotificationRepo) Create(ctx context.Context, in CreateNotifInput) (*Notification, error) {
	now := time.Now().UnixMilli()
	uuid := platform.NewUUID()
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO notifications(uuid, user_id, topic, ref_type, ref_id, title, body_brief,
		                          payload_json, push_status, push_attempts, created_at)
		VALUES(?,?,?,?,?,?,?,?, 'pending', 0, ?)`,
		uuid, in.UserID, in.Topic, nilStr(in.RefType), nilStr(in.RefID),
		in.Title, in.BodyBrief, nilStr(in.Payload), now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return r.findByID(ctx, id)
}

func (r *NotificationRepo) findByID(ctx context.Context, id int64) (*Notification, error) {
	var n Notification
	err := r.st.DB.GetContext(ctx, &n,
		"SELECT * FROM notifications WHERE id=?", id)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

func (r *NotificationRepo) FindByUUID(ctx context.Context, userID int64, uuid string) (*Notification, error) {
	var n Notification
	err := r.st.DB.GetContext(ctx, &n,
		"SELECT * FROM notifications WHERE uuid=? AND user_id=?", uuid, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// List 分页：按 created_at desc。cursor=0 → 从头。
// unreadOnly=true 时只取未读。
func (r *NotificationRepo) List(ctx context.Context, userID int64, cursor int64, limit int, unreadOnly bool) ([]Notification, int64, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	q := "SELECT * FROM notifications WHERE user_id=?"
	args := []any{userID}
	if cursor > 0 {
		q += " AND id < ?"
		args = append(args, cursor)
	}
	if unreadOnly {
		q += " AND read_at IS NULL"
	}
	q += " ORDER BY id DESC LIMIT ?"
	args = append(args, limit)

	rows := []Notification{}
	if err := r.st.DB.SelectContext(ctx, &rows, q, args...); err != nil {
		return nil, 0, err
	}
	var next int64
	if len(rows) == limit {
		next = rows[len(rows)-1].ID
	}
	return rows, next, nil
}

func (r *NotificationRepo) MarkRead(ctx context.Context, userID int64, uuid string) error {
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx,
		"UPDATE notifications SET read_at=? WHERE uuid=? AND user_id=? AND read_at IS NULL",
		now, uuid, userID)
	return err
}

func (r *NotificationRepo) MarkAllRead(ctx context.Context, userID int64) (int64, error) {
	now := time.Now().UnixMilli()
	res, err := r.st.DB.ExecContext(ctx,
		"UPDATE notifications SET read_at=? WHERE user_id=? AND read_at IS NULL",
		now, userID)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return n, nil
}

func (r *NotificationRepo) UnreadCount(ctx context.Context, userID int64) (int, error) {
	var n int
	err := r.st.DB.GetContext(ctx, &n,
		"SELECT COUNT(1) FROM notifications WHERE user_id=? AND read_at IS NULL", userID)
	return n, err
}

func (r *NotificationRepo) Delete(ctx context.Context, userID int64, uuid string) error {
	_, err := r.st.DB.ExecContext(ctx,
		"DELETE FROM notifications WHERE uuid=? AND user_id=?", uuid, userID)
	return err
}

func nilStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}
