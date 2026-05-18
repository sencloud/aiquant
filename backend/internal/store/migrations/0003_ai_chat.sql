-- AI 助理服务端会话上下文 + 消息存储。
-- 客户端不再持有上下文，每次只发"本轮 user 消息"，后端按 session_id 把
-- 历史 messages 拼齐。

CREATE TABLE IF NOT EXISTS ai_chat_sessions (
  id          INTEGER PRIMARY KEY,
  uuid        TEXT NOT NULL UNIQUE,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL DEFAULT '',
  persona_id  TEXT NOT NULL DEFAULT 'default',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ai_sessions_user_time
  ON ai_chat_sessions(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS ai_chat_messages (
  id              INTEGER PRIMARY KEY,
  session_id      INTEGER NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
  -- role: system / user / assistant / tool
  role            TEXT NOT NULL,
  content         TEXT NOT NULL DEFAULT '',
  -- assistant 发起 tool_call 时存一份 JSON 数组（OpenAI 协议）
  tool_calls_json TEXT,
  -- tool 角色消息引用的 tool_call_id + tool 名称（喂回 LLM 用）
  tool_call_id    TEXT,
  tool_name       TEXT,
  -- 单条消息消耗的 token / 喜点（assistant 终态行）
  prompt_tokens     INTEGER,
  completion_tokens INTEGER,
  credits_charged   INTEGER,
  created_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ai_msgs_session
  ON ai_chat_messages(session_id, id);
