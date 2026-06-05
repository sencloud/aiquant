-- AI 直播 v2 社交化：房间归属 + 公开/私密可见性 + 用户参与发言。
--
-- 需求：
--   1) 区分用户自己创建的直播间（公开 public / 私密 private 仅自己可见）。
--   4) 用户可在自己创建的直播间里发言参与讨论（按喜点计费）。
--
-- 列：
--   * live_rooms.creator_user_id  创建者 user id；自动场次(origin='auto')为 NULL，对所有人公开。
--   * live_rooms.visibility       'public' / 'private'；既往房间默认 'public'（旧行为不变）。
--   * live_messages.user_id       用户发言记录发言人 id；AI 主持人/嘉宾发言为 NULL。
--                                 用户发言 role='user'（role 为 TEXT，无需约束变更）。
--
-- 索引 idx_live_rooms_creator：服务于 CountLiveByCreator(每用户至多 1 个进行中房间) +
--   列表按 (visibility public OR creator=自己) 过滤。

ALTER TABLE live_rooms ADD COLUMN creator_user_id INTEGER;
ALTER TABLE live_rooms ADD COLUMN visibility TEXT NOT NULL DEFAULT 'public';
ALTER TABLE live_messages ADD COLUMN user_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_live_rooms_creator
  ON live_rooms(creator_user_id, status);
