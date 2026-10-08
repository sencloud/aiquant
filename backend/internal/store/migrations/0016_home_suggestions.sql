-- 首页「今天想聊点什么」快捷提问：由 scheduler 按 A 股时段生成并落库。
--
-- slot_key = <trade_date>:<phase>（如 2026-10-08:closed），唯一约束保证同一
-- 时段只生成一次；客户端只读最近一条，因此表会随天数缓慢增长，无需实时清理。
CREATE TABLE IF NOT EXISTS ai_home_suggestions (
  id             INTEGER PRIMARY KEY,
  slot_key       TEXT NOT NULL UNIQUE,
  trade_date     TEXT NOT NULL,
  phase          TEXT NOT NULL,
  questions_json TEXT NOT NULL,
  snapshot_json  TEXT,
  source         TEXT NOT NULL DEFAULT 'llm',
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_home_suggestions_created
  ON ai_home_suggestions(created_at DESC);
