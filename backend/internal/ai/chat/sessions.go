// Package chat 是服务端 AI 助理的会话存储 + SSE 流式 + tool calling loop。
//
// 1. 会话上下文：客户端只发"本轮 user 消息 + session_id"，后端拼齐 history。
// 2. tool calling loop：循环调用 LLM；遇到 tool_calls 由 ToolRegistry 派发，
//    把结果作为新的 role=tool 消息送回，直到 LLM 给出最终 stop。
// 3. 喜点扣费：开 stream 前预检余额；done 之前按 (基础 + 深度 + 工具数) 一次性扣。
package chat

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/store"
)

// Session 是一段聊天的元数据。
type Session struct {
	ID        int64  `db:"id"`
	UUID      string `db:"uuid"`
	UserID    int64  `db:"user_id"`
	Title     string `db:"title"`
	PersonaID string `db:"persona_id"`
	CreatedAt int64  `db:"created_at"`
	UpdatedAt int64  `db:"updated_at"`
}

// Message 是会话内的一条消息（与 OpenAI 协议对齐）。
type Message struct {
	ID               int64          `db:"id"`
	SessionID        int64          `db:"session_id"`
	Role             string         `db:"role"`
	Content          string         `db:"content"`
	ToolCallsJSON    sql.NullString `db:"tool_calls_json"`
	ToolCallID       sql.NullString `db:"tool_call_id"`
	ToolName         sql.NullString `db:"tool_name"`
	PromptTokens     sql.NullInt64  `db:"prompt_tokens"`
	CompletionTokens sql.NullInt64  `db:"completion_tokens"`
	CreditsCharged   sql.NullInt64  `db:"credits_charged"`
	CreatedAt        int64          `db:"created_at"`
}

// SessionRepo 直接对 ai_chat_* 两张表操作。
type SessionRepo struct {
	st *store.Store
}

// NewSessionRepo 构造。
func NewSessionRepo(st *store.Store) *SessionRepo { return &SessionRepo{st: st} }

// CreateOrLoad 加载已有 session（user 必须匹配），不存在或为空时新建。
func (r *SessionRepo) CreateOrLoad(ctx context.Context, userID int64, sessionUUID, persona string) (*Session, error) {
	if persona == "" {
		persona = "default"
	}
	now := time.Now().UnixMilli()
	if sessionUUID != "" {
		var s Session
		err := r.st.DB.GetContext(ctx, &s,
			"SELECT * FROM ai_chat_sessions WHERE uuid=? AND user_id=?",
			sessionUUID, userID)
		if err == nil {
			return &s, nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("load session: %w", err)
		}
	}
	id := uuid.NewString()
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO ai_chat_sessions(uuid, user_id, title, persona_id, created_at, updated_at)
		VALUES(?, ?, '', ?, ?, ?)`,
		id, userID, persona, now, now)
	if err != nil {
		return nil, fmt.Errorf("insert session: %w", err)
	}
	pk, _ := res.LastInsertId()
	return &Session{
		ID:        pk,
		UUID:      id,
		UserID:    userID,
		PersonaID: persona,
		CreatedAt: now,
		UpdatedAt: now,
	}, nil
}

// LoadHistory 取该 session 最近 N 条消息（按 id 升序）。
//
// N <= 0 时返回全部。第一条若是 system，会保留；user/assistant/tool 之间的
// 顺序保持。
func (r *SessionRepo) LoadHistory(ctx context.Context, sessionID int64, limit int) ([]Message, error) {
	if limit <= 0 {
		var rows []Message
		if err := r.st.DB.SelectContext(ctx, &rows,
			"SELECT * FROM ai_chat_messages WHERE session_id=? ORDER BY id", sessionID); err != nil {
			return nil, err
		}
		return rows, nil
	}
	var rows []Message
	if err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM ai_chat_messages
		WHERE session_id=? ORDER BY id DESC LIMIT ?`, sessionID, limit); err != nil {
		return nil, err
	}
	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}
	return rows, nil
}

// AppendUser 追加一条 user 消息（事务内）。
func (r *SessionRepo) AppendUser(ctx context.Context, sessionID int64, content string) (*Message, error) {
	return r.appendMessage(ctx, Message{
		SessionID: sessionID,
		Role:      "user",
		Content:   content,
	})
}

// AppendAssistant 追加一条 assistant 消息（可能带 tool_calls）。
func (r *SessionRepo) AppendAssistant(
	ctx context.Context,
	sessionID int64,
	content string,
	toolCalls []llm.ToolCall,
	usage *llm.Usage,
	credits int64,
) (*Message, error) {
	m := Message{
		SessionID: sessionID,
		Role:      "assistant",
		Content:   content,
	}
	if len(toolCalls) > 0 {
		raw, _ := json.Marshal(toolCalls)
		m.ToolCallsJSON = sql.NullString{String: string(raw), Valid: true}
	}
	if usage != nil {
		m.PromptTokens = sql.NullInt64{Int64: usage.PromptTokens, Valid: true}
		m.CompletionTokens = sql.NullInt64{Int64: usage.CompletionTokens, Valid: true}
	}
	if credits > 0 {
		m.CreditsCharged = sql.NullInt64{Int64: credits, Valid: true}
	}
	return r.appendMessage(ctx, m)
}

// AppendTool 追加一条 tool 消息（assistant 的 tool_call 结果）。
func (r *SessionRepo) AppendTool(ctx context.Context, sessionID int64, toolCallID, toolName, content string) (*Message, error) {
	return r.appendMessage(ctx, Message{
		SessionID:  sessionID,
		Role:       "tool",
		Content:    content,
		ToolCallID: sql.NullString{String: toolCallID, Valid: true},
		ToolName:   sql.NullString{String: toolName, Valid: true},
	})
}

func (r *SessionRepo) appendMessage(ctx context.Context, m Message) (*Message, error) {
	now := time.Now().UnixMilli()
	m.CreatedAt = now
	err := r.st.Tx(ctx, func(tx *sqlx.Tx) error {
		res, err := tx.ExecContext(ctx, `
			INSERT INTO ai_chat_messages(
				session_id, role, content, tool_calls_json, tool_call_id, tool_name,
				prompt_tokens, completion_tokens, credits_charged, created_at)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			m.SessionID, m.Role, m.Content, m.ToolCallsJSON,
			m.ToolCallID, m.ToolName,
			m.PromptTokens, m.CompletionTokens, m.CreditsCharged, now,
		)
		if err != nil {
			return err
		}
		id, _ := res.LastInsertId()
		m.ID = id
		_, err = tx.ExecContext(ctx,
			"UPDATE ai_chat_sessions SET updated_at=? WHERE id=?", now, m.SessionID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// SetTitleIfEmpty 如果 session.title 还空，把第一条 user 消息前 32 字截作标题。
func (r *SessionRepo) SetTitleIfEmpty(ctx context.Context, sessionID int64, content string) error {
	if content == "" {
		return nil
	}
	rs := []rune(content)
	if len(rs) > 32 {
		rs = rs[:32]
	}
	title := string(rs)
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE ai_chat_sessions
		SET title=?, updated_at=?
		WHERE id=? AND (title='' OR title IS NULL)`,
		title, now, sessionID)
	return err
}
