-- 每个用户同时只允许 1 个进行中(status='live')的自建直播间。
--
-- 此前仅靠 CountLiveByCreator 应用层前置检查 + 失败退款自愈，
-- 两次近乎同时的创建请求理论上可绕过。用部分唯一索引在 DB 层兜死：
--   * 仅约束 status='live' 的行；房间结束(ended/ended_abnormal)后即释放，可再建。
--   * creator_user_id IS NOT NULL 才约束：自动场次(creator 为 NULL)不受影响，
--     且 SQLite 允许多个 NULL 共存。
CREATE UNIQUE INDEX IF NOT EXISTS idx_live_rooms_one_live_per_creator
  ON live_rooms(creator_user_id)
  WHERE status = 'live' AND creator_user_id IS NOT NULL;
