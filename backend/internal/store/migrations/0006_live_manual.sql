-- AI 直播 v2 增量：支持「随时手动新建直播间」。
--
-- 需求：
--   1) 除已有的 4 个定时窗口（9:30/11:30/14:30/15:30）外，用户可在 App 内随时手动开播。
--   2) 全局任一时刻最多只允许 1 个 status='live' 房间（无论 manual / auto）。
--   3) 手动房间硬截止 15 分钟，到期 liveLoop 主动 close 进入历史。
--
-- 列：
--   * origin       'auto' / 'manual'，区分调度来源；既往房间默认 'auto'（旧自动行为不变）。
--   * auto_end_at  ms 时间戳；非空时 liveLoop 每轮检查超期则主动 host_close → MarkEnded。
--
-- 索引 idx_live_rooms_live_origin：服务于 RoomRepo.CountLive() 的唯一性前置检查。

ALTER TABLE live_rooms ADD COLUMN origin TEXT NOT NULL DEFAULT 'auto';
ALTER TABLE live_rooms ADD COLUMN auto_end_at INTEGER;

CREATE INDEX IF NOT EXISTS idx_live_rooms_live_origin
  ON live_rooms(status, origin);
