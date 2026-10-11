-- 对话生成小应用 P0：私人小应用、版本、挂载、参数状态、生成记录、运行记录。
--
-- spec 是声明式 JSON（组件树 + 数据绑定 + 受限表达式），由 App 内置渲染器绘制；
-- 不含任何可执行代码。全部按用户私有（P0 不做分享）。

CREATE TABLE IF NOT EXISTS mini_apps (
  id               INTEGER PRIMARY KEY,
  uuid             TEXT NOT NULL UNIQUE,
  user_id          INTEGER NOT NULL REFERENCES users(id),
  topic            TEXT NOT NULL,               -- money / fishing
  title            TEXT NOT NULL,
  icon             TEXT NOT NULL DEFAULT 'apps',
  summary          TEXT NOT NULL DEFAULT '',
  status           TEXT NOT NULL DEFAULT 'draft', -- draft（生成后未挂载）/ active
  current_version  INTEGER NOT NULL DEFAULT 1,
  session_id       TEXT NOT NULL DEFAULT '',    -- 工坊对话会话（澄清问答与后续修改共用）
  template_id      TEXT,                        -- 从官方模板复制而来
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  deleted_at       INTEGER
);
CREATE INDEX IF NOT EXISTS idx_mini_apps_user_topic
  ON mini_apps(user_id, topic, deleted_at, updated_at DESC);

CREATE TABLE IF NOT EXISTS mini_app_versions (
  id              INTEGER PRIMARY KEY,
  app_id          INTEGER NOT NULL REFERENCES mini_apps(id),
  version         INTEGER NOT NULL,
  schema_ver      TEXT NOT NULL,
  min_renderer    INTEGER NOT NULL DEFAULT 1,
  spec_json       TEXT NOT NULL,
  spec_hash       TEXT NOT NULL,
  change_summary  TEXT NOT NULL DEFAULT '',
  author          TEXT NOT NULL,                -- llm / template / restore / migration
  gen_id          TEXT,
  created_at      INTEGER NOT NULL,
  UNIQUE(app_id, version)
);

CREATE TABLE IF NOT EXISTS mini_app_mounts (
  user_id     INTEGER NOT NULL REFERENCES users(id),
  topic       TEXT NOT NULL,
  app_id      INTEGER NOT NULL REFERENCES mini_apps(id),
  position    INTEGER NOT NULL,
  card_size   TEXT NOT NULL DEFAULT 'medium',
  mounted_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, topic, app_id)
);

CREATE TABLE IF NOT EXISTS mini_app_state (
  app_id       INTEGER PRIMARY KEY REFERENCES mini_apps(id),
  user_id      INTEGER NOT NULL REFERENCES users(id),
  inputs_json  TEXT NOT NULL DEFAULT '{}',
  state_json   TEXT NOT NULL DEFAULT '{}',
  updated_at   INTEGER NOT NULL
);

-- 一次生成（一轮对话）。先扣喜点再调模型；澄清 / 拒绝 / 失败全额退回。
-- (user_id, request_id) 幂等：客户端重试同一个 request_id 不会重复扣费。
CREATE TABLE IF NOT EXISTS mini_app_gens (
  id                 INTEGER PRIMARY KEY,
  request_id         TEXT NOT NULL,
  user_id            INTEGER NOT NULL REFERENCES users(id),
  topic              TEXT NOT NULL,
  session_id         TEXT NOT NULL,
  app_id             INTEGER,
  kind               TEXT NOT NULL,             -- create / iterate
  status             TEXT NOT NULL,             -- pending / done / failed
  stage              TEXT NOT NULL DEFAULT '',  -- thinking / validating / repairing / dry_run
  outcome            TEXT NOT NULL DEFAULT '',  -- ask / spec / refuse / fail
  message            TEXT NOT NULL,
  result_json        TEXT,
  error              TEXT,
  credits            INTEGER NOT NULL,
  refunded           INTEGER NOT NULL DEFAULT 0,
  model              TEXT NOT NULL DEFAULT '',
  prompt_tokens      INTEGER NOT NULL DEFAULT 0,
  completion_tokens  INTEGER NOT NULL DEFAULT 0,
  repair_rounds      INTEGER NOT NULL DEFAULT 0,
  latency_ms         INTEGER NOT NULL DEFAULT 0,
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL,
  UNIQUE(user_id, request_id)
);
CREATE INDEX IF NOT EXISTS idx_mini_app_gens_session ON mini_app_gens(user_id, session_id, id);
CREATE INDEX IF NOT EXISTS idx_mini_app_gens_status ON mini_app_gens(status, updated_at);

-- 运行记录（打开 / 预览 / 模板浏览）；保留 30 天。
CREATE TABLE IF NOT EXISTS mini_app_runs (
  id            INTEGER PRIMARY KEY,
  app_id        INTEGER,
  template_id   TEXT,
  user_id       INTEGER,
  version       INTEGER,
  run_trigger   TEXT NOT NULL,                  -- open / dryrun / template
  status        TEXT NOT NULL,                  -- ok / partial / error
  duration_ms   INTEGER NOT NULL,
  sources_json  TEXT NOT NULL DEFAULT '[]',
  cost_units    INTEGER NOT NULL DEFAULT 0,
  error         TEXT,
  created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_mini_app_runs_created ON mini_app_runs(created_at);
