// Package share 存取「AI 问答分享」快照，对应公开网页 GET /s/{id}。
package share

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"time"

	"github.com/sencloud/finme-backend/internal/store"
)

// ErrNotFound 表示分享 id 不存在。
var ErrNotFound = errors.New("share not found")

// Share 是一条问答分享快照。
type Share struct {
	ID        string `db:"id"`
	UserID    int64  `db:"user_id"`
	Question  string `db:"question"`
	Answer    string `db:"answer"`
	CreatedAt int64  `db:"created_at"`
	ViewCount int64  `db:"view_count"`
}

// Repo 是分享存储。
type Repo struct {
	st *store.Store
}

// NewRepo 构造分享存储。
func NewRepo(st *store.Store) *Repo {
	return &Repo{st: st}
}

// Create 落一条分享，返回带生成 id 的记录。
func (r *Repo) Create(ctx context.Context, userID int64, question, answer string) (*Share, error) {
	id, err := newID()
	if err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	if _, err := r.st.DB.ExecContext(ctx,
		`INSERT INTO ai_shares(id, user_id, question, answer, created_at, view_count)
		 VALUES(?, ?, ?, ?, ?, 0)`,
		id, userID, question, answer, now,
	); err != nil {
		return nil, err
	}
	return &Share{
		ID:        id,
		UserID:    userID,
		Question:  question,
		Answer:    answer,
		CreatedAt: now,
	}, nil
}

// Get 取一条分享并尽力自增浏览数（自增失败不影响读取）。
func (r *Repo) Get(ctx context.Context, id string) (*Share, error) {
	var s Share
	err := r.st.DB.GetContext(ctx, &s,
		`SELECT id, user_id, question, answer, created_at, view_count
		 FROM ai_shares WHERE id = ?`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	_, _ = r.st.DB.ExecContext(ctx,
		`UPDATE ai_shares SET view_count = view_count + 1 WHERE id = ?`, id)
	return &s, nil
}

// newID 生成 12 位 base62 短 id（约 71 bit 熵，碰撞与不可枚举性足够）。
const idAlphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

func newID() (string, error) {
	const n = 12
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	for i := range buf {
		buf[i] = idAlphabet[int(buf[i])%len(idAlphabet)]
	}
	return string(buf), nil
}
