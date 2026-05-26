-- AI 直播 v2：从「分析师独立写报告」改为「主持人 + 嘉宾真聊天直播间」。
--
-- 数据形态的差异：
--   旧（0004_live.sql）：live_sessions 每场预选 3-5 只票 + live_reports 每只票每个 persona 独立 markdown→HTML 报告。
--   新（本文件）        ：live_rooms 长会话（1-2 小时）+ live_messages 时间序列的对话流，
--                         每条消息聚焦一只票（focus_symbol），主图 K 线随焦点切换。
--
-- 设计要点：
--   * 一个 room = 一场直播间，有主持人 + 若干嘉宾 persona，状态 live → ended（异常 → ended_abnormal）；
--   * 消息按 idx 严格递增，前端拉「since_idx=N」做增量轮询；
--   * focus_symbol 记录该条消息聚焦的股票（前端用最近一条非空的 focus 决定 K 线主图）；
--   * target_persona 记录主持人点名的对象（前端可高亮）；
--   * 不再有 picked_symbols 概念：哪只票都是主持人当下决策的，记录在消息上。
--
-- 旧表全部 DROP：用户明确选择「废弃旧形态」。

DROP TABLE IF EXISTS live_reports;
DROP TABLE IF EXISTS live_sessions;
DROP TABLE IF EXISTS live_watchlist;

CREATE TABLE IF NOT EXISTS live_rooms (
  id                    INTEGER PRIMARY KEY,
  uuid                  TEXT NOT NULL UNIQUE,
  title                 TEXT NOT NULL,                    -- 「盘后复盘 · 主持人:老韩」
  phase                 TEXT NOT NULL,                    -- pre / intraday / post
  status                TEXT NOT NULL DEFAULT 'live',     -- live / ended / ended_abnormal
  host_persona          TEXT NOT NULL,                    -- 主持人 persona id
  host_persona_name     TEXT NOT NULL,
  guest_personas        TEXT NOT NULL,                    -- JSON [{"id":"buffett","name":"巴菲特"},...]
  current_focus_symbol  TEXT,                             -- 最新焦点 ts_code(冗余字段,加速首屏)
  current_focus_name    TEXT,
  message_count         INTEGER NOT NULL DEFAULT 0,
  started_at            INTEGER NOT NULL,                 -- ms
  ended_at              INTEGER,
  error                 TEXT,
  created_at            INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_live_rooms_status_time
  ON live_rooms(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_rooms_time
  ON live_rooms(started_at DESC);

CREATE TABLE IF NOT EXISTS live_messages (
  id              INTEGER PRIMARY KEY,
  room_id         INTEGER NOT NULL REFERENCES live_rooms(id) ON DELETE CASCADE,
  idx             INTEGER NOT NULL,                       -- 房间内 1-based 顺序号
  role            TEXT NOT NULL,                          -- host_open / host_ask / host_switch / host_close /
                                                          -- guest_answer / guest_react / system
  persona         TEXT NOT NULL,                          -- 说话人 persona id
  persona_name    TEXT NOT NULL,
  target_persona  TEXT,                                   -- 主持人点名时:被问的对象 id
  focus_symbol    TEXT,                                   -- 此条消息聚焦的票(可空,如"开场")
  focus_name      TEXT,
  content         TEXT NOT NULL,                          -- markdown 文本
  created_at      INTEGER NOT NULL,                       -- ms
  UNIQUE(room_id, idx)
);
CREATE INDEX IF NOT EXISTS idx_live_messages_room
  ON live_messages(room_id, idx);
CREATE INDEX IF NOT EXISTS idx_live_messages_focus
  ON live_messages(focus_symbol, created_at DESC);
