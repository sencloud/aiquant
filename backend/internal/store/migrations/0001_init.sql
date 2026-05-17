-- Initial schema. 单文件向前演进 — 后续加新 migration 用 0002_xxx.sql。
-- 所有时间戳为 unix 毫秒（INTEGER）— 业务层统一转换。
-- 余额/金额 / 喜点 全部 INTEGER（最小单位：分 或 1 喜点），永不浮点。

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ① 用户
CREATE TABLE IF NOT EXISTS users (
  id              INTEGER PRIMARY KEY,
  uuid            TEXT NOT NULL UNIQUE,
  phone_hmac      TEXT UNIQUE,
  phone_enc       BLOB,
  apple_sub       TEXT UNIQUE,
  wechat_unionid  TEXT UNIQUE,
  nickname        TEXT,
  status          TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','banned','deleted')),
  credit_balance  INTEGER NOT NULL DEFAULT 0,
  risk_score      INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL
);

-- ② 设备 / 推送 token
CREATE TABLE IF NOT EXISTS devices (
  id              INTEGER PRIMARY KEY,
  user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id       TEXT NOT NULL,
  platform        TEXT NOT NULL CHECK(platform IN ('ios','android')),
  push_token      TEXT,
  push_token_at   INTEGER,
  app_version     TEXT,
  last_active_at  INTEGER,
  UNIQUE(user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_devices_token ON devices(push_token) WHERE push_token IS NOT NULL;

-- ③ Refresh token（按 jti 索引，登出/异地撤销立即生效）
CREATE TABLE IF NOT EXISTS refresh_tokens (
  jti          TEXT PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id    TEXT,
  ip           TEXT,
  ua           TEXT,
  expires_at   INTEGER NOT NULL,
  revoked_at   INTEGER,
  created_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id, created_at);

-- ④ 喜点 SKU
CREATE TABLE IF NOT EXISTS credit_skus (
  code             TEXT PRIMARY KEY,
  apple_product_id TEXT UNIQUE,
  base_credits     INTEGER NOT NULL,
  bonus_credits    INTEGER NOT NULL DEFAULT 0,
  price_cents_cny  INTEGER NOT NULL,
  active           INTEGER NOT NULL DEFAULT 1,
  sort             INTEGER NOT NULL DEFAULT 0
);

-- ⑤ 订单
CREATE TABLE IF NOT EXISTS orders (
  id                INTEGER PRIMARY KEY,
  order_no          TEXT NOT NULL UNIQUE,
  user_id           INTEGER NOT NULL REFERENCES users(id),
  sku_code          TEXT NOT NULL,
  credits           INTEGER NOT NULL,
  amount_cents      INTEGER NOT NULL,
  channel           TEXT NOT NULL CHECK(channel IN ('apple_iap','wechat','alipay')),
  channel_order_id  TEXT,
  status            TEXT NOT NULL CHECK(status IN ('pending','paid','credited','refunded','closed','failed')),
  paid_at           INTEGER,
  credited_at       INTEGER,
  refunded_at       INTEGER,
  raw_receipt_id    INTEGER,
  client_request_id TEXT,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_orders_user      ON orders(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_orders_status    ON orders(status, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_chid ON orders(channel, channel_order_id) WHERE channel_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_idem ON orders(user_id, client_request_id) WHERE client_request_id IS NOT NULL;

-- ⑥ 收据 / 回调原始报文
CREATE TABLE IF NOT EXISTS receipts (
  id          INTEGER PRIMARY KEY,
  channel     TEXT NOT NULL,
  payload     TEXT NOT NULL,
  signature   TEXT,
  verified_at INTEGER,
  verify_ok   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);

-- ⑦ 喜点流水（账本，只插入不更新）
CREATE TABLE IF NOT EXISTS credit_ledger (
  id             INTEGER PRIMARY KEY,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  delta          INTEGER NOT NULL,
  balance_after  INTEGER NOT NULL,
  reason         TEXT NOT NULL,
  ref_type       TEXT,
  ref_id         TEXT,
  remark         TEXT,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ledger_user ON credit_ledger(user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_idem
  ON credit_ledger(reason, ref_type, ref_id) WHERE ref_id IS NOT NULL;

-- ⑧ 通知（DING 收件箱 + 系统）
CREATE TABLE IF NOT EXISTS notifications (
  id             INTEGER PRIMARY KEY,
  uuid           TEXT NOT NULL UNIQUE,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  topic          TEXT NOT NULL,
  ref_type       TEXT,
  ref_id         TEXT,
  title          TEXT NOT NULL,
  body_brief     TEXT NOT NULL,
  payload_json   TEXT,
  push_status    TEXT NOT NULL DEFAULT 'pending'
                 CHECK(push_status IN ('pending','pushed','failed','suppressed')),
  push_attempts  INTEGER NOT NULL DEFAULT 0,
  pushed_at      INTEGER,
  read_at        INTEGER,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notif_user_time ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_unread    ON notifications(user_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notif_pending   ON notifications(push_status, created_at)
  WHERE push_status='pending';

-- ⑨ DING 任务
CREATE TABLE IF NOT EXISTS ding_tasks (
  id                     INTEGER PRIMARY KEY,
  uuid                   TEXT NOT NULL UNIQUE,
  user_id                INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title                  TEXT NOT NULL,
  prompt                 TEXT NOT NULL,
  persona_id             TEXT NOT NULL,
  schedule               TEXT NOT NULL,
  enabled                INTEGER NOT NULL DEFAULT 1,
  next_run_at            INTEGER,
  last_run_at            INTEGER,
  cost_credits_per_run   INTEGER NOT NULL DEFAULT 5,
  created_at             INTEGER NOT NULL,
  updated_at             INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ding_due ON ding_tasks(enabled, next_run_at) WHERE enabled=1;

-- ⑩ DING 执行日志
CREATE TABLE IF NOT EXISTS ding_runs (
  id              INTEGER PRIMARY KEY,
  task_id         INTEGER NOT NULL REFERENCES ding_tasks(id) ON DELETE CASCADE,
  status          TEXT NOT NULL CHECK(status IN ('running','success','failed','skipped_no_credit')),
  notification_id INTEGER,
  total_tokens    INTEGER,
  duration_ms     INTEGER,
  error           TEXT,
  started_at      INTEGER NOT NULL,
  finished_at     INTEGER
);
CREATE INDEX IF NOT EXISTS idx_runs_task ON ding_runs(task_id, started_at);

-- ⑪ 短信验证码
CREATE TABLE IF NOT EXISTS sms_codes (
  id          INTEGER PRIMARY KEY,
  phone_hmac  TEXT NOT NULL,
  code_hash   TEXT NOT NULL,
  purpose     TEXT NOT NULL CHECK(purpose IN ('login','change_phone')),
  expires_at  INTEGER NOT NULL,
  consumed_at INTEGER,
  attempts    INTEGER NOT NULL DEFAULT 0,
  ip          TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sms_phone ON sms_codes(phone_hmac, created_at);

-- ⑫ 审计
CREATE TABLE IF NOT EXISTS audit_log (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER,
  action      TEXT NOT NULL,
  ip          TEXT,
  ua          TEXT,
  detail_json TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id, created_at);
