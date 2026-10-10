package chat

import (
	"context"
	"errors"
	"strings"
	"time"
)

// Feedback 是用户对一条 AI 回答的点赞 / 点踩。
type Feedback struct {
	UserID      int64
	SessionUUID string
	MessageID   string // 客户端本地消息 id
	Rating      int    // 1 = 赞，-1 = 踩，0 = 取消
	Question    string
	Answer      string
}

// 反馈里保存的问题 / 回答最多多少字（只做回看，不需要全文）。
const (
	feedbackQuestionRunes = 500
	feedbackAnswerRunes   = 4000
)

// ErrBadFeedback 表示反馈参数不合法。
var ErrBadFeedback = errors.New("bad feedback")

// SaveFeedback 记录 / 更新 / 取消一条回答反馈。
func (s *Service) SaveFeedback(ctx context.Context, f Feedback) error {
	if s.d.Sessions == nil {
		return errors.New("chat sessions not configured")
	}
	return s.d.Sessions.UpsertFeedback(ctx, f)
}

// UpsertFeedback 以 (user_id, message_id) 为键写入反馈；rating=0 时删除。
func (r *SessionRepo) UpsertFeedback(ctx context.Context, f Feedback) error {
	f.MessageID = strings.TrimSpace(f.MessageID)
	if f.UserID <= 0 || f.MessageID == "" || len(f.MessageID) > 64 {
		return ErrBadFeedback
	}
	if f.Rating < -1 || f.Rating > 1 {
		return ErrBadFeedback
	}
	if f.Rating == 0 {
		_, err := r.st.DB.ExecContext(ctx,
			`DELETE FROM ai_chat_feedback WHERE user_id=? AND message_id=?`,
			f.UserID, f.MessageID)
		return err
	}
	now := time.Now().UnixMilli()
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO ai_chat_feedback(
			user_id, session_uuid, message_id, rating, question, answer, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(user_id, message_id) DO UPDATE SET
			rating=excluded.rating,
			session_uuid=CASE WHEN excluded.session_uuid<>'' THEN excluded.session_uuid ELSE ai_chat_feedback.session_uuid END,
			question=excluded.question,
			answer=excluded.answer,
			updated_at=excluded.updated_at`,
		f.UserID, truncateRunes(strings.TrimSpace(f.SessionUUID), 64), f.MessageID, f.Rating,
		truncateRunes(f.Question, feedbackQuestionRunes),
		truncateRunes(f.Answer, feedbackAnswerRunes),
		now, now)
	return err
}
