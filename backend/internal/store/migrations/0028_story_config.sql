-- 《天亮以前》试用版的远程开关。
-- 一行配置，客户端每次打开试用版时读取：
--   enabled        总开关（0 = 显示「试用已结束」）
--   characters     开放的路线，逗号分隔；空串 = 全关
--   share_enabled  结局卡分享开关
--   max_turns      每夜自由聊天上限（服务端同时有硬上限 40）
--   notice         试用结束 / 维护时显示给用户的一句话
CREATE TABLE IF NOT EXISTS story_config (
  id            TEXT PRIMARY KEY CHECK(id = 'default'),
  enabled       INTEGER NOT NULL DEFAULT 1,
  characters    TEXT NOT NULL DEFAULT 'linxia,suyu,chenye',
  share_enabled INTEGER NOT NULL DEFAULT 1,
  max_turns     INTEGER NOT NULL DEFAULT 40,
  notice        TEXT NOT NULL DEFAULT '',
  updated_at    INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO story_config(id, enabled, characters, share_enabled, max_turns, notice, updated_at)
VALUES('default', 1, 'linxia,suyu,chenye', 1, 40, '', 0);
