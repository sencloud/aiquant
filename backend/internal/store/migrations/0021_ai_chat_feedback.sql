-- 对话回答的点赞 / 点踩反馈（客户端回答下方的操作栏）。
-- 以 (user_id, message_id) 唯一：同一条回答重复点击只更新评分；取消即删除。
-- message_id 是客户端本地消息 id（服务端消息 id 不下发给客户端）。
CREATE TABLE IF NOT EXISTS ai_chat_feedback (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id       INTEGER NOT NULL,
  session_uuid  TEXT    NOT NULL DEFAULT '',
  message_id    TEXT    NOT NULL,
  rating        INTEGER NOT NULL,
  question      TEXT    NOT NULL DEFAULT '',
  answer        TEXT    NOT NULL DEFAULT '',
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE(user_id, message_id)
);
CREATE INDEX IF NOT EXISTS idx_ai_chat_feedback_rating
  ON ai_chat_feedback(rating, updated_at DESC);
