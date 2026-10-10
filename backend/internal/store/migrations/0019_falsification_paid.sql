-- MVP 付费闭环：证伪档案（快照 / 解锁 / 跑一次证伪）+ 邀请奖励改发喜点。
-- 全部为新增表 / 新增列，不改动任何已有数据。

-- ① 证伪档案快照：scheduler 定时从 alpha-radar 拉取（已剔除 report_url），
--    api 读最新一份；没有任何快照时回落到二进制内置的 seed。
CREATE TABLE IF NOT EXISTS falsification_snapshots (
  id                INTEGER PRIMARY KEY,
  generated_at      TEXT NOT NULL DEFAULT '',
  threshold_version TEXT NOT NULL DEFAULT '',
  entry_count       INTEGER NOT NULL DEFAULT 0,
  payload_json      TEXT NOT NULL,
  fetched_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_falsification_snapshots_latest
  ON falsification_snapshots(fetched_at DESC);

-- ② 档案详情解锁：一人一条只扣一次，永久有效。扣费流水 reason=consume_unlock。
CREATE TABLE IF NOT EXISTS falsification_unlocks (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  entry_id    TEXT NOT NULL,
  credits     INTEGER NOT NULL,
  ledger_id   INTEGER,
  created_at  INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_falsification_unlocks
  ON falsification_unlocks(user_id, entry_id);

-- ③ 跑一次证伪：用户下单 → 上游 alpha-radar 任务。扣费 consume_falsify（ref=run uuid），
--    失败退款 refund_falsify。上游没有任务接口时 status=unsupported，不扣费。
CREATE TABLE IF NOT EXISTS falsification_runs (
  id               INTEGER PRIMARY KEY,
  uuid             TEXT NOT NULL UNIQUE,
  user_id          INTEGER NOT NULL REFERENCES users(id),
  strategy         TEXT NOT NULL,
  symbol           TEXT NOT NULL,
  freq             TEXT NOT NULL,
  credits          INTEGER NOT NULL,
  status           TEXT NOT NULL
                   CHECK(status IN ('queued','running','done','failed','unsupported')),
  charged          INTEGER NOT NULL DEFAULT 0,
  refunded         INTEGER NOT NULL DEFAULT 0,
  upstream_job_id  TEXT,
  result_json      TEXT,
  error            TEXT,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_falsification_runs_user
  ON falsification_runs(user_id, created_at DESC);

-- ④ 邀请奖励单位：历史行是螺壳（shell），新行发喜点（credit）。
ALTER TABLE invite_redemptions ADD COLUMN reward_unit TEXT NOT NULL DEFAULT 'shell';
