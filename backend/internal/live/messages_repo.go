package live

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/sencloud/finme-backend/internal/store"
)

// MessageRepo 封装 live_messages 的 CRUD。
type MessageRepo struct{ st *store.Store }

func NewMessageRepo(st *store.Store) *MessageRepo { return &MessageRepo{st: st} }

// AppendInput 是 Append 的入参。Idx 由 repo 自动取 max+1,调用方不必填。
type AppendInput struct {
	RoomID        int64
	Role          string
	Persona       string
	PersonaName   string
	TargetPersona string
	FocusSymbol   string
	FocusName     string
	Content       string
	// Annotations 是已 marshal 好的 JSON 字符串(由调用方拼好,通常来自
	// guest_speaker LLM 输出的 annotations 数组)。空字符串表示无标注。
	Annotations string
}

// Append 在事务内取 idx = max(idx)+1 后插入新消息,返回完整 Message。
//
// 使用事务避免并发追加时 idx 冲突(SQLite + sqlx 默认 serialized,但保险起见)。
func (r *MessageRepo) Append(ctx context.Context, in AppendInput) (*Message, error) {
	tx, err := r.st.DB.BeginTxx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	var nextIdx int
	if err := tx.GetContext(ctx, &nextIdx, `
		SELECT COALESCE(MAX(idx), 0) + 1
		FROM live_messages WHERE room_id = ?`, in.RoomID); err != nil {
		return nil, fmt.Errorf("next idx: %w", err)
	}

	now := nowMs()
	res, err := tx.ExecContext(ctx, `
		INSERT INTO live_messages
		  (room_id, idx, role, persona, persona_name,
		   target_persona, focus_symbol, focus_name, content, annotations, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		in.RoomID, nextIdx, in.Role, in.Persona, in.PersonaName,
		nullStr(in.TargetPersona), nullStr(in.FocusSymbol), nullStr(in.FocusName),
		in.Content, nullStr(in.Annotations), now,
	)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	m := &Message{
		ID:          id,
		RoomID:      in.RoomID,
		Idx:         nextIdx,
		Role:        in.Role,
		Persona:     in.Persona,
		PersonaName: in.PersonaName,
		Content:     in.Content,
		CreatedAt:   now,
	}
	if in.TargetPersona != "" {
		m.TargetPersona = sql.NullString{String: in.TargetPersona, Valid: true}
	}
	if in.FocusSymbol != "" {
		m.FocusSymbol = sql.NullString{String: in.FocusSymbol, Valid: true}
	}
	if in.FocusName != "" {
		m.FocusName = sql.NullString{String: in.FocusName, Valid: true}
	}
	if in.Annotations != "" {
		m.Annotations = sql.NullString{String: in.Annotations, Valid: true}
	}
	return m, nil
}

// ListSince 增量拉取:返回 idx > sinceIdx 的所有消息,上限 limit 条。
//
// 客户端轮询用:?since_idx=N → 服务端返回 idx>N 的新消息。
func (r *MessageRepo) ListSince(ctx context.Context, roomID int64, sinceIdx, limit int) ([]Message, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows := []Message{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_messages
		WHERE room_id=? AND idx>?
		ORDER BY idx ASC
		LIMIT ?`, roomID, sinceIdx, limit)
	return rows, err
}

// ListRecent 返回最近 N 条消息(按 idx 升序),用于:
//   * 前端首次进入房间拉历史(取最新尾巴)
//   * 后端 LLM prompt 注入"最近上下文"
func (r *MessageRepo) ListRecent(ctx context.Context, roomID int64, n int) ([]Message, error) {
	if n <= 0 {
		n = 20
	}
	rows := []Message{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM (
		  SELECT * FROM live_messages
		  WHERE room_id=?
		  ORDER BY idx DESC LIMIT ?
		) ORDER BY idx ASC`, roomID, n)
	return rows, err
}

// CountByRoom 返回房间总消息数。
func (r *MessageRepo) CountByRoom(ctx context.Context, roomID int64) (int, error) {
	var n int
	err := r.st.DB.GetContext(ctx, &n, `
		SELECT COUNT(*) FROM live_messages WHERE room_id=?`, roomID)
	return n, err
}

// DeleteByRoomID 删除某房间的全部消息。用于删除已结束直播间(连同其聊天记录)。
func (r *MessageRepo) DeleteByRoomID(ctx context.Context, roomID int64) error {
	_, err := r.st.DB.ExecContext(ctx,
		`DELETE FROM live_messages WHERE room_id=?`, roomID)
	return err
}
