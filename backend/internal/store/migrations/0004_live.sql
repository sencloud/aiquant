-- AI 直播：每整点一场 AI 自动场次，每场针对若干股票，按"具体人名分析师"
-- (巴菲特/格雷厄姆/林奇/芒格/达里奥/索罗斯) 各自独立生成结构化 HTML 报告。
--
-- 设计要点：
--   * 调度键 = scheduled_at (UNIQUE)，runner 抢占落 status='running'，
--     避免同一场被多次触发；
--   * 每场预先 INSERT pending 行（日历填充），跑完写 selection_reason + picked_symbols；
--   * live_reports 一行 = (session × symbol × persona) 三元组，
--     unique 保证不会重复写入；
--   * live_watchlist 走 user 维度，关注列表用于 picker 优先纳入选股。

CREATE TABLE IF NOT EXISTS live_sessions (
  id                INTEGER PRIMARY KEY,
  uuid              TEXT NOT NULL UNIQUE,
  scheduled_at      INTEGER NOT NULL UNIQUE,        -- 计划开始时刻 ms（整点 / 半点）
  phase             TEXT NOT NULL,                  -- pre / intraday / post
  status            TEXT NOT NULL DEFAULT 'pending',-- pending / running / done / failed
  started_at        INTEGER,
  finished_at       INTEGER,
  picked_symbols    TEXT,                           -- JSON ["600519.SH",...]
  selection_reason  TEXT,                           -- 「龙虎榜净流入 Top3 + 关注 2 只」
  error             TEXT,
  created_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_live_sessions_status_time
  ON live_sessions(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_live_sessions_time
  ON live_sessions(scheduled_at DESC);

CREATE TABLE IF NOT EXISTS live_reports (
  id              INTEGER PRIMARY KEY,
  session_id      INTEGER NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  symbol          TEXT NOT NULL,                    -- ts_code 600519.SH
  symbol_name     TEXT NOT NULL,                    -- 贵州茅台
  persona_id      TEXT NOT NULL,                    -- buffett / graham ...
  persona_name    TEXT NOT NULL,                    -- 巴菲特
  -- 结构化要点（强制 prompt 让 LLM 输出 JSON 前导块）
  view            TEXT,                             -- bullish / neutral / bearish
  rating          TEXT,                             -- 强烈买入 / 买入 / 持有 / 减持 / 卖出
  target_price    REAL,
  stop_loss       REAL,
  take_profit     REAL,
  position_hint   TEXT,                             -- 「建议 5-10% 仓位」
  -- 全文
  summary         TEXT NOT NULL DEFAULT '',         -- 一句话 ≤80 字
  html_body       TEXT NOT NULL,                    -- 含 inline CSS 的完整 HTML
  tool_calls      INTEGER NOT NULL DEFAULT 0,
  duration_ms     INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  UNIQUE(session_id, symbol, persona_id)
);
CREATE INDEX IF NOT EXISTS idx_live_reports_session
  ON live_reports(session_id);
CREATE INDEX IF NOT EXISTS idx_live_reports_symbol_time
  ON live_reports(symbol, created_at DESC);

CREATE TABLE IF NOT EXISTS live_watchlist (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  symbol      TEXT NOT NULL,                       -- 600519.SH
  symbol_name TEXT NOT NULL DEFAULT '',            -- 贵州茅台
  created_at  INTEGER NOT NULL,
  UNIQUE(user_id, symbol)
);
CREATE INDEX IF NOT EXISTS idx_live_watch_user
  ON live_watchlist(user_id, created_at DESC);
