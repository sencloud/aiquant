-- AI 问答分享：用户把一条助理回答存成可公开访问的网页短链（GET /s/{id}）。
-- 仅存这一问一答的快照，不关联会话历史；删除用户时级联清理。

CREATE TABLE IF NOT EXISTS ai_shares (
  id          TEXT PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question    TEXT NOT NULL DEFAULT '',
  answer      TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  view_count  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_ai_shares_user ON ai_shares(user_id, created_at DESC);
