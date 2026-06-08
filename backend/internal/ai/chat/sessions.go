// Package chat 是服务端 AI 助理的会话存储 + SSE 流式 + tool calling loop。
//
// 1. 会话上下文：客户端只发"本轮 user 消息 + session_id"，后端拼齐 history。
// 2. tool calling loop：循环调用 LLM；遇到 tool_calls 由 ToolRegistry 派发，
//    把结果作为新的 role=tool 消息送回，直到 LLM 给出最终 stop。
// 3. 喜点扣费：开 stream 前预检余额；done 之前按 (基础 + 深度) 一次性扣，工具调用不计费。
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
//
// 关键约束（OpenAI / DeepSeek 协议）：
//
//	role=tool 必须紧跟在 role=assistant 且带 tool_calls 的消息之后；
//	且每个 tool 消息的 tool_call_id 都要能在前一条 assistant 的 tool_calls
//	里找到。
//
// 直接按 LIMIT 截最近 N 条会出现"截断点把 assistant(tool_calls) 砍掉、
// 只留下后面的 tool 消息"这种孤儿情况，触发 LLM 端 400
//
//	"Messages with role 'tool' must be a response to a preceding
//	 message with 'tool_calls'"。
//
// 我们在截断后做一次清洗：从 head 开始往后扫，丢掉所有"前面没有合法
// assistant tool_calls 提供 id 的 tool 消息"，并丢掉"声明了 tool_calls
// 但配对的 tool 已经不在窗口"的 assistant 消息。
func (r *SessionRepo) LoadHistory(ctx context.Context, sessionID int64, limit int) ([]Message, error) {
	if limit <= 0 {
		var rows []Message
		if err := r.st.DB.SelectContext(ctx, &rows,
			"SELECT * FROM ai_chat_messages WHERE session_id=? ORDER BY id", sessionID); err != nil {
			return nil, err
		}
		return sanitizeToolPairs(rows), nil
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
	return sanitizeToolPairs(rows), nil
}

// sanitizeToolPairs 把窗口内 assistant↔tool 的配对补齐：
//  1. 收集窗口里所有 tool 消息的 tool_call_id 集合；
//  2. 第一遍：遍历 assistant 消息，把 tool_calls 中 id 不在集合的项删掉；
//     若一条 assistant 的 tool_calls 整体都丢失了，但 content 为空，则该
//     消息也整条丢弃（既无文本又无残留 tool_calls）。
//  3. 第二遍：再收集"还活着的 assistant tool_call_id 集合"，遍历 tool
//     消息，把孤儿（id 不在集合）的 tool 整条丢弃。
//  4. 第三遍：从 head 起，连续丢掉以 tool 开头的消息（防止窗口起点就是
//     orphan tool，但其 id 实际指向窗口外那条 assistant — 例如截断点恰
//     好在 assistant↔tool 之间）。
func sanitizeToolPairs(rows []Message) []Message {
	if len(rows) == 0 {
		return rows
	}
	toolIDs := make(map[string]bool, len(rows))
	for _, m := range rows {
		if m.Role == "tool" && m.ToolCallID.Valid && m.ToolCallID.String != "" {
			toolIDs[m.ToolCallID.String] = true
		}
	}

	out := make([]Message, 0, len(rows))
	livingAsstIDs := make(map[string]bool)
	for _, m := range rows {
		if m.Role != "assistant" {
			out = append(out, m)
			continue
		}
		if !m.ToolCallsJSON.Valid || m.ToolCallsJSON.String == "" {
			out = append(out, m)
			continue
		}
		var calls []llm.ToolCall
		if err := json.Unmarshal([]byte(m.ToolCallsJSON.String), &calls); err != nil {
			out = append(out, m)
			continue
		}
		keep := calls[:0]
		for _, c := range calls {
			if toolIDs[c.ID] {
				keep = append(keep, c)
				livingAsstIDs[c.ID] = true
			}
		}
		if len(keep) == 0 {
			if m.Content == "" {
				continue
			}
			m.ToolCallsJSON.Valid = false
			m.ToolCallsJSON.String = ""
			out = append(out, m)
			continue
		}
		raw, _ := json.Marshal(keep)
		m.ToolCallsJSON.String = string(raw)
		out = append(out, m)
	}

	filtered := out[:0]
	for _, m := range out {
		if m.Role == "tool" {
			if !m.ToolCallID.Valid || !livingAsstIDs[m.ToolCallID.String] {
				continue
			}
		}
		filtered = append(filtered, m)
	}

	for len(filtered) > 0 && filtered[0].Role == "tool" {
		filtered = filtered[1:]
	}
	return filtered
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
