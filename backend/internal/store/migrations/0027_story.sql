-- 《喜爱 · 天亮以前》二次元试用版：进度、消息、结局。
--
-- 客户端是剧情内容的作者（night/beat/choice 在 Dart 内容包里），服务端负责：
--   1. 跨设备保存进度（story_runs / story_messages）；
--   2. 用当前场景 + 最近对话跑 AI 自由聊天；
--   3. 记录已解锁结局（story_endings），供结局册回读。
-- 因此这里不复制三套剧本，只存状态；改剧情不需要迁移。
CREATE TABLE IF NOT EXISTS story_runs (
  id              TEXT PRIMARY KEY,
  user_id         INTEGER NOT NULL,
  season_id       TEXT NOT NULL DEFAULT 'before_dawn_s1',
  character_id    TEXT NOT NULL,
  night           INTEGER NOT NULL DEFAULT 1,
  beat            INTEGER NOT NULL DEFAULT 0,
  hearts          INTEGER NOT NULL DEFAULT 2,
  flags           TEXT NOT NULL DEFAULT '[]',
  night_complete  INTEGER NOT NULL DEFAULT 0,
  finished        INTEGER NOT NULL DEFAULT 0,
  ending_id       TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_story_runs_user_updated
  ON story_runs(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS story_messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id      TEXT NOT NULL,
  role        TEXT NOT NULL,
  content     TEXT NOT NULL,
  safety      INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  FOREIGN KEY(run_id) REFERENCES story_runs(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_story_messages_run
  ON story_messages(run_id, id);

CREATE TABLE IF NOT EXISTS story_endings (
  user_id      INTEGER NOT NULL,
  season_id    TEXT NOT NULL,
  ending_id    TEXT NOT NULL,
  run_id       TEXT NOT NULL,
  unlocked_at  INTEGER NOT NULL,
  PRIMARY KEY(user_id, season_id, ending_id)
);
