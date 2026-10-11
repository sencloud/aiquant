-- 喜爱 · 主题化（TopicPack）。
-- 1) 会话按主题打标签：老会话一律归「喜爱钱」(money)，互不串台；
-- 2) 用户偏好主题：登录用户换机后恢复（NULL = 未设置，客户端按本地 / 默认 money）。
-- credit_ledger 不改表：钓鱼主题的流水用 reason 前缀 fishing.* 区分。
ALTER TABLE ai_chat_sessions ADD COLUMN topic TEXT NOT NULL DEFAULT 'money';
CREATE INDEX IF NOT EXISTS idx_ai_chat_sessions_user_topic
  ON ai_chat_sessions(user_id, topic, updated_at DESC);

ALTER TABLE users ADD COLUMN preferred_topic TEXT;
